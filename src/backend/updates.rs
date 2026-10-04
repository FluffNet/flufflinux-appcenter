//! Explicit update scanning, pinned transaction plans and permission changes.
use super::{bytes, flag, permissions, process, progress, sources, text};
use libflatpak::{prelude::*, Installation, RefKind, Transaction};
use serde_json::{json, Value};
use std::{cell::RefCell, collections::BTreeMap, rc::Rc};

pub fn operation_info(op: &libflatpak::TransactionOperation) -> Value {
    let reference = op.get_ref().unwrap_or_default();
    json!({"ref":reference.as_str(),"name":reference.split('/').nth(1).unwrap_or(""),"dependency":reference.starts_with("runtime/"),
        "remote":op.remote().unwrap_or_default().as_str(),"commit":op.commit().unwrap_or_default().as_str(),
        "action":op.operation_type().to_str().unwrap_or_default().as_str(),"downloadBytes":op.download_size(),"downloadSize":bytes(op.download_size()),
        "installedSize":bytes(op.installed_size()),"progress":0,"phase":"waiting","downloadProgress":0,"status":"Waiting"})
}
#[derive(Default)]
struct Plan {
    operations: Vec<Value>,
    permissions: Value,
    error: String,
    ready: bool,
}
fn plan(installation: &Installation, reference: &str) -> Result<Plan, String> {
    let tx = Transaction::for_installation(installation, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    tx.set_no_interaction(true);
    tx.add_default_dependency_sources();
    tx.connect_add_new_remote(|_, _, _, _, _| false);
    let result = Rc::new(RefCell::new(Plan::default()));
    let state = result.clone();
    let installation = installation.clone();
    let reference = reference.to_owned();
    let expected_ref = reference.clone();
    tx.connect_ready_pre_auth(move |tx| {
        let mut plan = state.borrow_mut();
        for op in tx.operations() {
            if op.is_skipped() {
                continue;
            }
            let full_ref = op.get_ref().unwrap_or_default();
            if (full_ref.starts_with("app/") && full_ref != expected_ref)
                || op.operation_type() == libflatpak::TransactionOperationType::Uninstall
            {
                plan.error =
                    "This update changes other apps. Manage this update with Flatpak.".into();
                break;
            }
            let remote_name = op.remote().unwrap_or_default();
            let commit = op.commit().unwrap_or_default();
            let remote = installation
                .remote_by_name(&remote_name, gio::Cancellable::NONE)
                .ok();
            if remote.as_ref().is_none_or(|r| r.is_disabled()) || !progress::valid_commit(&commit) {
                plan.error =
                    "The update source is missing, disabled, or could not be verified.".into();
                break;
            }
            let remote = remote.unwrap();
            let Ok(key) = sources::source_key(&installation, &remote) else {
                plan.error = "The update source could not be verified.".into();
                break;
            };
            let mut row = operation_info(&op);
            row["sourceUrl"] = sources::url(&remote).into();
            row["sourceKey"] = key.into();
            plan.operations.push(row);
            if full_ref == expected_ref && full_ref.starts_with("app/") {
                let before = op.old_metadata().map(|k| k.to_data()).unwrap_or_default();
                let after = op.metadata().map(|k| k.to_data()).unwrap_or_default();
                plan.permissions = permissions::changes(before.as_bytes(), after.as_bytes());
            }
        }
        plan.ready = plan.error.is_empty();
        false
    });
    tx.add_update(&reference, &[], None)
        .map_err(|e| e.to_string())?;
    let failure = tx.run(gio::Cancellable::NONE).err();
    drop(tx);
    let result = Rc::try_unwrap(result)
        .map_err(|_| "The transaction plan was retained")?
        .into_inner();
    if result.ready {
        Ok(result)
    } else {
        Err(if result.error.is_empty() {
            failure
                .map(|e| e.to_string())
                .unwrap_or_else(|| "Could not resolve update".into())
        } else {
            result.error
        })
    }
}
fn restoration_definition(scope: &str, origin: &str) -> Option<&'static str> {
    restoration_from_sources(scope, origin, &sources::list())
}
fn restoration_from_sources(scope: &str, origin: &str, sources: &[Value]) -> Option<&'static str> {
    if scope == "user" {
        return None;
    }
    let expected = match origin {
        "flathub" => "https://dl.flathub.org/repo/flathub.flatpakrepo",
        "flathub-beta" => "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo",
        _ => return None,
    };
    if sources.iter().any(|r| {
        text(r, "name") == origin
            && (text(r, "scope") == scope || (scope == "system" && text(r, "scope") == "default"))
    }) {
        return None;
    }
    sources
        .iter()
        .any(|r| {
            text(r, "scope") == "user"
                && text(r, "name") == origin
                && flag(r, "enabled")
                && flag(r, "verified")
                && sources::official_definition(text(r, "url")) == Some(expected)
        })
        .then_some(expected)
}
pub fn scan(request: &Value, mut send: impl FnMut(Value)) -> Value {
    let mut updates = Vec::new();
    let mut errors = Vec::<String>::new();
    let mut skipped = Vec::new();
    let mut installations = Vec::new();
    match sources::installation("user") {
        Ok(i) => installations.push(i),
        Err(e) => errors.push(format!("user: {e}")),
    };
    if !flag(request, "userOnly") {
        match libflatpak::system_installations(gio::Cancellable::NONE) {
            Ok(i) => installations.extend(i),
            Err(e) => errors.push(format!("system: {e}")),
        };
    }
    if installations.is_empty() {
        errors.push("No Flatpak installation could be read.".into());
    }
    for installation in installations {
        let scope = sources::display_scope(&installation);
        send(json!({"type":"status","message":"Checking for app updates…"}));
        let installed = match installation.list_installed_refs(gio::Cancellable::NONE) {
            Ok(refs) => refs,
            Err(e) => {
                errors.push(format!("{scope}: {e}"));
                continue;
            }
        };
        let mut published: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
        let mut refs = Vec::new();
        let mut skipped_source = |origin: &str, reason: &str| {
            let mut names: Vec<_> = installed
                .iter()
                .filter(|r| r.kind() == RefKind::App && r.origin().as_deref() == Some(origin))
                .map(|r| {
                    r.appdata_name()
                        .filter(|n| !n.is_empty())
                        .or_else(|| r.name())
                        .unwrap_or_default()
                        .to_string()
                })
                .collect();
            names.sort();
            names.dedup();
            let label = if scope == "user" {
                origin.to_owned()
            } else {
                format!(
                    "{origin} ({})",
                    if scope == "system" { "System" } else { &scope }
                )
            };
            skipped.push(format!(
                "Skipped {}: {label} {reason}",
                if names.is_empty() {
                    "installed components".into()
                } else {
                    names.join(", ")
                }
            ));
        };
        for installed_ref in &installed {
            let origin = installed_ref.origin().unwrap_or_default().to_string();
            if !published.contains_key(&origin) {
                let mut available = BTreeMap::new();
                published.insert(origin.clone(), BTreeMap::new());
                let mut remote = installation
                    .remote_by_name(&origin, gio::Cancellable::NONE)
                    .ok();
                if remote.is_none() && flag(request, "restoreSystemFlathub") {
                    if let Some(definition) = restoration_definition(&scope, &origin) {
                        send(
                            json!({"type":"status","message":format!("Adding {origin} for existing system apps… Authorization may be required.")}),
                        );
                        let scope_arg = if scope == "system" {
                            "--system".into()
                        } else {
                            format!("--installation={scope}")
                        };
                        let result = process::flatpak(
                            &[
                                &scope_arg,
                                "remote-add",
                                "--if-not-exists",
                                "--from",
                                &origin,
                                definition,
                            ],
                            120,
                            None,
                        );
                        let _ = installation.drop_caches(gio::Cancellable::NONE);
                        remote = installation
                            .remote_by_name(&origin, gio::Cancellable::NONE)
                            .ok();
                        send(json!({"type":"sources","sources":sources::group(&sources::list())}));
                        if remote.is_none() {
                            let detail = match result {
                                Ok(o) => o.stderr,
                                Err(e) => e,
                            };
                            skipped_source(&origin,&format!("could not be added. {detail} Press Check for App Updates to retry."));
                            continue;
                        }
                        send(json!({"type":"status","message":"Checking for app updates…"}));
                    }
                }
                let Some(remote) = remote else {
                    skipped_source(
                        &origin,
                        "is missing. Add it in Settings to check these app updates.",
                    );
                    continue;
                };
                if remote.is_disabled() {
                    skipped_source(&origin, "is disabled.");
                    continue;
                }
                match installation.list_remote_refs_sync_full(
                    &origin,
                    libflatpak::QueryFlags::NONE,
                    gio::Cancellable::NONE,
                ) {
                    Ok(items) => {
                        for item in items {
                            available.insert(
                                item.format_ref().unwrap_or_default().into(),
                                item.commit().unwrap_or_default().into(),
                            );
                        }
                    }
                    Err(e) => {
                        skipped_source(&origin, &format!("is unavailable. {e}"));
                        continue;
                    }
                }
                published.insert(origin.clone(), available);
            }
            let reference = installed_ref.format_ref().unwrap_or_default();
            if published
                .get(&origin)
                .and_then(|m| m.get(reference.as_str()))
                .is_some_and(|c| {
                    !c.is_empty() && Some(c.as_str()) != installed_ref.commit().as_deref()
                })
            {
                refs.push(installed_ref);
            }
        }
        let mut versions: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
        for reference in &refs {
            let origin = reference.origin().unwrap_or_default().to_string();
            if versions.contains_key(&origin) {
                continue;
            }
            versions.insert(origin.clone(), BTreeMap::new());
            if installation
                .update_appstream_sync(&origin, None, gio::Cancellable::NONE)
                .is_err()
            {
                continue;
            }
            let scope_arg = match scope.as_str() {
                "user" => "--user".into(),
                "system" => "--system".into(),
                _ => format!("--installation={scope}"),
            };
            if let Ok(output) = process::flatpak(
                &[&scope_arg, "remote-ls", "--columns=ref,version", &origin],
                15,
                None,
            ) {
                if output.code != 0 {
                    continue;
                }
                for line in String::from_utf8_lossy(&output.stdout).lines() {
                    if let Some((reference, version)) = line.split_once('\t') {
                        versions
                            .get_mut(&origin)
                            .unwrap()
                            .insert(reference.trim().into(), version.trim().into());
                    }
                }
            }
        }
        for installed in refs {
            let reference = installed.format_ref().unwrap_or_default().to_string();
            let origin = installed.origin().unwrap_or_default().to_string();
            let id = installed.name().unwrap_or_default();
            let name = installed
                .appdata_name()
                .filter(|n| !n.is_empty())
                .unwrap_or_else(|| id.clone());
            send(json!({"type":"status","message":format!("Checking {name}…")}));
            let Ok(remote) = installation.remote_by_name(&origin, gio::Cancellable::NONE) else {
                continue;
            };
            if remote.is_disabled() {
                continue;
            }
            let plan = match plan(&installation, &reference) {
                Ok(p) => p,
                Err(e) => {
                    errors.push(format!("{id}: {e}"));
                    continue;
                }
            };
            let commit = plan
                .operations
                .iter()
                .find(|r| text(r, "ref") == reference)
                .map(|r| text(r, "commit"))
                .unwrap_or("");
            if commit.is_empty() {
                continue;
            }
            let download: u64 = plan
                .operations
                .iter()
                .map(|r| super::number(r, "downloadBytes"))
                .sum();
            let old_commit = installed.commit().unwrap_or_default();
            let old_version = installed
                .appdata_version()
                .filter(|v| !v.is_empty())
                .map(String::from)
                .unwrap_or_else(|| {
                    format!(
                        "Revision {}",
                        old_commit.chars().take(12).collect::<String>()
                    )
                });
            let new_version = versions
                .get(&origin)
                .and_then(|v| v.get(&reference))
                .filter(|v| !v.is_empty())
                .cloned()
                .unwrap_or_else(|| {
                    format!("Revision {}", commit.chars().take(12).collect::<String>())
                });
            updates.push(json!({"key":format!("{scope}:{reference}"),"id":id.as_str(),"name":name.as_str(),"installation":scope,"flatpakRef":reference,
                "remote":origin,"sourceUrl":sources::url(&remote),"oldCommit":old_commit.as_str(),"commit":commit,"oldVersion":old_version,"newVersion":new_version,
                "runtime":reference.starts_with("runtime/"),"selected":true,"downloadBytes":download,"downloadSize":bytes(download),"plan":plan.operations,"permissions":plan.permissions}));
        }
    }
    json!({"type":"updates","updates":updates,"errors":errors,"skipped":skipped,"checkedAt":chrono::Utc::now().to_rfc3339()})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn restoration_is_official_verified_enabled_matching_and_never_overwrites() {
        let user = json!({"scope":"user","name":"flathub","url":"https://dl.flathub.org/repo/","enabled":true,"verified":true,"sourceKey":"same-policy"});
        let stable = Some("https://dl.flathub.org/repo/flathub.flatpakrepo");
        assert_eq!(
            restoration_from_sources("system", "flathub", std::slice::from_ref(&user)),
            stable
        );
        assert_eq!(
            restoration_from_sources("extra", "flathub", std::slice::from_ref(&user)),
            stable
        );
        for (scope, origin) in [
            ("user", "flathub"),
            ("system", "custom"),
            ("system", "flathub-beta"),
        ] {
            assert!(restoration_from_sources(scope, origin, std::slice::from_ref(&user)).is_none());
        }
        assert!(restoration_from_sources("system", "flathub", &[]).is_none());
        for field in ["enabled", "verified"] {
            let mut invalid = user.clone();
            invalid[field] = false.into();
            assert!(restoration_from_sources("system", "flathub", &[invalid]).is_none());
        }
        for url in [
            "https://evil.example/repo/",
            "http://dl.flathub.org/repo/",
            "https://dl.flathub.org/beta-repo/",
            "https://dl.flathub.org/repo/?x=1",
        ] {
            let mut invalid = user.clone();
            invalid["url"] = url.into();
            assert!(restoration_from_sources("system", "flathub", &[invalid]).is_none());
        }
        let mut existing = user.clone();
        existing["scope"] = "default".into();
        existing["enabled"] = false.into();
        existing["url"] = "https://different.example".into();
        assert!(restoration_from_sources("system", "flathub", &[user.clone(), existing]).is_none());
        let mut beta = user;
        beta["name"] = "flathub-beta".into();
        beta["url"] = "https://dl.flathub.org/beta-repo/".into();
        assert_eq!(
            restoration_from_sources("system", "flathub-beta", &[beta]),
            Some("https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo")
        );
    }
}
