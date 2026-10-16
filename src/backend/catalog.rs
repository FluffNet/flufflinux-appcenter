//! Read-only catalog inputs. No remote refresh or per-app network request.
use super::{normalized_id, sources, storage};
use gio::prelude::*;
use libflatpak::prelude::*;
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet},
    fs,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
};

#[derive(Default)]
pub struct Inputs {
    pub roots: Vec<(PathBuf, String, String)>,
    pub installed: HashSet<String>,
    pub sizes: HashMap<(String, String, String), u64>,
}
pub fn inputs() -> Inputs {
    let mut result = Inputs::default();
    let Ok(user) = sources::installation("user") else {
        return result;
    };
    for installation in sources::installations().unwrap_or_default() {
        for installed in installation
            .list_installed_refs(gio::Cancellable::NONE)
            .unwrap_or_default()
        {
            if installed.kind() == libflatpak::RefKind::App {
                result
                    .installed
                    .insert(normalized_id(&installed.name().unwrap_or_default()).into());
            }
        }
        for remote in installation
            .list_remotes(gio::Cancellable::NONE)
            .unwrap_or_default()
        {
            if remote.is_disabled() || remote.is_noenumerate() {
                continue;
            }
            let mut name = sources::name(&remote);
            if !installation.is_user() {
                if sources::suppressed(&installation, &remote) {
                    continue;
                }
                name = sources::user_name(&user, &installation, &remote);
                if let Ok(copy) = user.remote_by_name(&name, gio::Cancellable::NONE) {
                    if copy.is_disabled() || sources::url(&copy) != sources::url(&remote) {
                        continue;
                    }
                }
            }
            let Some(path) = remote.appstream_dir(None).and_then(|p| p.path()) else {
                continue;
            };
            let url = sources::url(&remote);
            for reference in installation
                .list_remote_refs_sync_full(
                    &sources::name(&remote),
                    libflatpak::QueryFlags::ONLY_CACHED,
                    gio::Cancellable::NONE,
                )
                .unwrap_or_default()
            {
                if reference.kind() != libflatpak::RefKind::App || reference.metadata().is_none() {
                    continue;
                }
                result
                    .sizes
                    .entry((
                        name.clone(),
                        url.clone(),
                        reference.format_ref().unwrap_or_default().into(),
                    ))
                    .or_insert(reference.download_size());
            }
            result.roots.push((path, name, url));
        }
    }
    result
}
fn stamp(path: &Path) -> Value {
    let metadata = fs::metadata(path).ok();
    json!([
        path,
        fs::canonicalize(path).ok(),
        metadata.as_ref().map(|m| (
            m.len(),
            m.mtime(),
            m.mtime_nsec(),
            m.ctime(),
            m.ctime_nsec()
        ))
    ])
}
fn contents(path: &Path) -> String {
    fs::read(path)
        .map(sources::token)
        .unwrap_or_else(|_| "unreadable".into())
}
fn entries(path: &Path) -> Vec<PathBuf> {
    let mut paths: Vec<_> = fs::read_dir(path)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .collect();
    paths.sort();
    paths
}
fn catalog_files(output: &mut Vec<Value>, path: &Path, depth: u8) {
    if depth > 5 {
        return;
    }
    let active = path.join("active");
    if active.join("appstream.xml.gz").is_file() || active.join("appstream.xml").is_file() {
        output.push(stamp(&active.join("appstream.xml.gz")));
        output.push(stamp(&active.join("appstream.xml")));
        return;
    }
    for path in entries(path) {
        if path.is_dir() {
            catalog_files(output, &path, depth + 1);
        } else if matches!(
            path.extension().and_then(|s| s.to_str()),
            Some("xml" | "gz")
        ) {
            output.push(stamp(&path));
        }
    }
}
pub fn fingerprint() -> Result<String, String> {
    let mut output = vec![stamp(&std::env::current_exe().map_err(|e| e.to_string())?)];
    let exclusions = PathBuf::from(
        std::env::var_os("FLUFF_APP_CENTER_EXCLUSIONS")
            .unwrap_or_else(|| "/etc/flufflinux-appcenter/exclusions.conf".into()),
    );
    output.push(json!([exclusions, contents(&exclusions)]));
    output.push(json!(sources::removed_sources()));
    for installation in sources::installations()? {
        let path = sources::location(&installation)?;
        output.push(json!(path));
        output.push(contents(&path.join("repo/config")).into());
        output.push(stamp(&path.join(".changed")));
        for key in entries(&path.join("repo"))
            .into_iter()
            .filter(|p| p.extension().is_some_and(|x| x == "gpg"))
        {
            output.push(stamp(&key));
        }
        for remote in installation
            .list_remotes(gio::Cancellable::NONE)
            .map_err(|e| e.to_string())?
        {
            let filter = remote.filter().unwrap_or_default();
            output.push(json!([
                sources::name(&remote),
                filter.as_str(),
                if filter.is_empty() {
                    String::new()
                } else {
                    contents(Path::new(filter.as_str()))
                }
            ]));
            if let Some(directory) = remote.appstream_dir(None).and_then(|p| p.path()) {
                catalog_files(&mut output, &directory, 0);
            }
        }
        for file in entries(&path.join("repo/tmp/cache/summaries")) {
            output.push(stamp(&file));
        }
        let mut deployments = Vec::new();
        for reference in installation
            .list_installed_refs(gio::Cancellable::NONE)
            .map_err(|e| e.to_string())?
        {
            if reference.kind() == libflatpak::RefKind::App {
                deployments.push(format!(
                    "{}:{}",
                    reference.format_ref().unwrap_or_default(),
                    reference.commit().unwrap_or_default()
                ));
            }
        }
        deployments.sort();
        output.push(json!(deployments));
    }
    Ok(storage::checksum(&json!(output)))
}

pub fn snapshot(request: &Value, apps: Vec<Value>) -> Value {
    let now = chrono::Utc::now();
    let saved = if super::flag(request, "resetAge") {
        Some(now)
    } else {
        chrono::DateTime::parse_from_rfc3339(super::text(request, "savedAt"))
            .ok()
            .map(|date| date.with_timezone(&chrono::Utc))
    };
    let fingerprint = fingerprint().unwrap_or_default();
    let stable = !fingerprint.is_empty() && fingerprint == super::text(request, "fingerprint");
    let saved_cache = stable
        && saved.is_some_and(|date| {
            storage::fresh(date, now)
                && storage::write_cache(
                    Path::new(super::text(request, "path")),
                    &fingerprint,
                    &apps,
                    date,
                )
                .is_ok()
        });
    if stable && saved.is_some_and(|date| storage::fresh(date, now)) && !saved_cache {
        eprintln!("Could not save application-list cache; browsing remains available");
    }
    json!({"apps":apps,"savedAt":saved.map(|date|date.to_rfc3339()).unwrap_or_default(),"cacheSaved":saved_cache})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fingerprint_inputs_include_same_size_edits_and_active_deployment_target() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("appstream");
        let xml = root.join("snapshot-a/appstream.xml");
        fs::create_dir_all(xml.parent().unwrap()).unwrap();
        fs::write(&xml, "one").unwrap();
        let first = contents(&xml);
        fs::write(&xml, "two").unwrap();
        assert_ne!(contents(&xml), first);
        std::os::unix::fs::symlink("snapshot-a", root.join("active")).unwrap();
        let mut first = vec![];
        catalog_files(&mut first, &root, 0);
        assert_eq!(first.len(), 2);
        fs::create_dir_all(root.join("snapshot-b")).unwrap();
        fs::copy(&xml, root.join("snapshot-b/appstream.xml")).unwrap();
        fs::remove_file(root.join("active")).unwrap();
        std::os::unix::fs::symlink("snapshot-b", root.join("active")).unwrap();
        let mut second = vec![];
        catalog_files(&mut second, &root, 0);
        assert_ne!(first, second);
        assert_ne!(stamp(&xml), stamp(&root.join("missing")));
    }
}
