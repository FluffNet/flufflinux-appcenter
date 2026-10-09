use super::{flag, process, rows, source_removal, sources, storage, text};
use gio::prelude::*;
use libflatpak::{prelude::*, Installation, Remote};
use serde_json::{json, Value};
use std::{
    io::Read,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

pub fn safe_url(value: &str) -> bool {
    url::Url::parse(value).is_ok_and(|u| {
        u.scheme() == "https"
            && u.host_str().is_some()
            && u.username().is_empty()
            && u.password().is_none()
    })
}
pub fn local_path(input: &str) -> Option<PathBuf> {
    match url::Url::parse(input) {
        Ok(u) => u.to_file_path().ok(),
        Err(_) => Some(input.into()),
    }
}
pub fn read_source(input: &str, cancel: &gio::Cancellable) -> Result<Vec<u8>, String> {
    const LIMIT: u64 = 2 * 1024 * 1024;
    if let Some(path) = local_path(input) {
        let file = std::fs::File::open(path)
            .map_err(|_| "Cannot read the reference file, or it exceeds 2 MiB.")?;
        if !file.metadata().map_err(|e| e.to_string())?.is_file() {
            return Err("Not a regular Flatpak reference file.".into());
        }
        let mut data = Vec::new();
        file.take(LIMIT + 1)
            .read_to_end(&mut data)
            .map_err(|e| e.to_string())?;
        if data.len() as u64 > LIMIT {
            return Err("Cannot read the reference file, or it exceeds 2 MiB.".into());
        }
        return Ok(data);
    }
    let mut current = input
        .strip_prefix("flatpak+https:")
        .map(|s| format!("https:{s}"))
        .unwrap_or_else(|| input.into());
    // Handle redirects explicitly so neither credentials nor an HTTPS downgrade
    // can hide behind a previously trusted entry URL.
    let start = std::time::Instant::now();
    for _ in 0..6 {
        if cancel.is_cancelled() {
            return Err("Cancelled".into());
        }
        let remaining = Duration::from_secs(60).saturating_sub(start.elapsed());
        if remaining.is_zero() {
            return Err("Retrieving the reference timed out.".into());
        }
        if !safe_url(&current) {
            return Err("Only local Flatpak files and HTTPS Flatpak links are supported.".into());
        }
        let agent = super::http::agent(remaining.min(Duration::from_secs(30)));
        let mut response = agent
            .get(&current)
            .call()
            .map_err(|e| format!("Could not retrieve a safe Flatpak reference: {e}"))?;
        if response.status().is_redirection() {
            let location = response
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .ok_or("Invalid redirect from Flatpak source")?;
            current = url::Url::parse(&current)
                .and_then(|u| u.join(location))
                .map_err(|e| e.to_string())?
                .into();
            continue;
        }
        if !response.status().is_success() {
            return Err(format!("Flatpak source returned {}", response.status()));
        }
        let mut data = Vec::new();
        let mut reader = response.body_mut().as_reader();
        let mut chunk = [0u8; 8192];
        loop {
            if cancel.is_cancelled() {
                return Err("Cancelled".into());
            }
            let count = reader.read(&mut chunk).map_err(|e| e.to_string())?;
            if count == 0 {
                break;
            }
            data.extend_from_slice(&chunk[..count]);
            if data.len() as u64 > LIMIT {
                return Err("The Flatpak reference exceeds 2 MiB.".into());
            }
        }
        return Ok(data);
    }
    Err("Too many redirects from the Flatpak source.".into())
}
pub fn key_file(data: &[u8]) -> Result<glib::KeyFile, String> {
    let key = glib::KeyFile::new();
    let data = std::str::from_utf8(data).map_err(|e| e.to_string())?;
    if data.contains('\0') {
        return Err("Invalid reference file".into());
    }
    key.load_from_data(data, glib::KeyFileFlags::NONE)
        .map_err(|e| e.to_string())?;
    Ok(key)
}
pub fn add_official(
    installation: &Installation,
    name: &str,
    definition: &str,
    cancel: &gio::Cancellable,
) -> Result<(), String> {
    let contents = read_source(definition, cancel)?;
    let key = key_file(&contents)?;
    let gpg = key.string("Flatpak Repo", "GPGKey").unwrap_or_default();
    let url = key.string("Flatpak Repo", "Url").unwrap_or_default();
    if gpg.is_empty() || sources::official_definition(&url) != Some(definition) {
        return Err("The Flathub source file has an unexpected URL or no signing key.".into());
    }
    let remote =
        Remote::from_file(name, &glib::Bytes::from_owned(contents)).map_err(|e| e.to_string())?;
    remote.set_gpg_verify(true);
    installation
        .modify_remote(&remote, Some(cancel))
        .map_err(|e| e.to_string())
}
pub fn ensure_user(
    installation: &Installation,
    name: &str,
    expected_url: &str,
    estimate_only: bool,
    cancel: &gio::Cancellable,
) -> Result<(), String> {
    if let Ok(existing) = installation.remote_by_name(name, Some(cancel)) {
        if !expected_url.is_empty() && sources::url(&existing) != expected_url {
            return Err(
                "This software source has changed. Reopen the app and select its source again."
                    .into(),
            );
        }
        if existing.is_disabled() {
            return Err("This software source is disabled. Enable it in Settings first.".into());
        }
        return Ok(());
    }
    if estimate_only {
        return Err(
            "Sizes will be available after the software source is configured for your user.".into(),
        );
    }
    for system in libflatpak::system_installations(Some(cancel)).map_err(|e| e.to_string())? {
        for source in system.list_remotes(Some(cancel)).unwrap_or_default() {
            if sources::user_name(installation, &system, &source) != name
                || sources::suppressed(&system, &source)
                || source.is_disabled()
                || (!expected_url.is_empty() && sources::url(&source) != expected_url)
            {
                continue;
            }
            return sources::mirror(installation, &system, &source, cancel);
        }
    }
    Err(format!(
        "The source {name} is not configured. Add it in Settings → Flatpak Sources."
    ))
}
fn remove(user: &Installation, members: &[Value], cancel: &gio::Cancellable) -> Result<(), String> {
    let targets = source_removal::resolve(Some(user), members, false)?;
    let systems: Vec<_> = targets
        .iter()
        .filter(|t| text(&t.expected, "scope") != "user")
        .map(|t| t.expected.clone())
        .collect();
    if !systems.is_empty() {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let helper = exe
            .parent()
            .filter(|p| p.file_name().is_some_and(|n| n == "bin"))
            .and_then(Path::parent)
            .map(|p| p.join("lib/flufflinux-appcenter/source-helper"))
            .unwrap_or_else(|| "/usr/lib/flufflinux-appcenter/source-helper".into());
        let secure = std::fs::metadata(&helper).is_ok_and(|m| {
            m.is_file() && m.uid() == 0 && m.mode() & 0o022 == 0 && m.mode() & 0o111 != 0
        });
        if !secure {
            return Err("The system-source helper is missing or not securely installed. Reinstall App Center.".into());
        }
        let mut command = Command::new("/usr/bin/pkexec");
        command
            .arg("--disable-internal-agent")
            .arg(helper)
            .arg(json!(systems).to_string());
        let output = process::run(command, Duration::from_secs(180), 1024 * 1024, Some(cancel))?;
        if matches!(output.code, 126 | 127) {
            return Err("Cancelled".into());
        }
        if output.code != 0 {
            return Err(if output.stderr.is_empty() {
                "Could not remove the system software source.".into()
            } else {
                output.stderr
            });
        }
    }
    for target in targets
        .iter()
        .filter(|t| text(&t.expected, "scope") == "user")
    {
        let remote = source_removal::matches(user, &target.expected)?;
        source_removal::remove(target, Some(cancel)).map_err(|e| {
            if systems.is_empty() {
                e
            } else {
                format!("{e} System copies were removed; the user copy remains.")
            }
        })?;
        sources::remember_removal(user, &remote)?;
    }
    storage::update_config(|c| c.set_boolean("Sources", "initialized", true))
        .map_err(|e| e.to_string())
}
pub fn operate(
    user: &Installation,
    request: &Value,
    cancel: &gio::Cancellable,
    mut send: impl FnMut(Value),
) -> Result<(), String> {
    let operation = text(request, "operation");
    let (mut available, mut failed, mut refreshed) = (0, 0, 0);
    let mut problems = Vec::new();
    match operation {
        "initialize" | "refresh" => {
            send(json!({"type":"catalog-progress","progress":5}));
            let first = !storage::config()
                .boolean("Sources", "initialized")
                .unwrap_or(false);
            let empty = sources::list().is_empty();
            for system in
                libflatpak::system_installations(Some(cancel)).map_err(|e| e.to_string())?
            {
                for remote in system.list_remotes(Some(cancel)).unwrap_or_default() {
                    if remote.remote_type() != libflatpak::RemoteType::Static
                        || sources::suppressed(&system, &remote)
                    {
                        continue;
                    }
                    if let Err(e) = sources::mirror(user, &system, &remote, cancel) {
                        problems.push(e);
                        if !remote.is_disabled() && !remote.is_noenumerate() {
                            failed += 1;
                        }
                    }
                }
            }
            if first && empty {
                if let Err(e) = add_official(
                    user,
                    "flathub",
                    "https://dl.flathub.org/repo/flathub.flatpakrepo",
                    cancel,
                ) {
                    problems.push(e);
                    failed += 1;
                }
            }
            if problems.is_empty() {
                storage::update_config(|c| c.set_boolean("Sources", "initialized", true))
                    .map_err(|e| e.to_string())?;
            }
        }
        "defaults" => {
            if !sources::list().is_empty() {
                return Err(
                    "Default sources can only be added when no sources are configured.".into(),
                );
            }
            if let Err(e) = add_official(
                user,
                "flathub",
                "https://dl.flathub.org/repo/flathub.flatpakrepo",
                cancel,
            ) {
                send(json!({"type":"catalog-load","available":0,"failed":1,"refreshed":0}));
                return Err(e);
            }
            storage::update_config(|c| c.set_boolean("Sources", "initialized", true))
                .map_err(|e| e.to_string())?;
        }
        "remove" => {
            let result = remove(user, rows(&request["members"]), cancel);
            send(json!({"type":"sources","sources":sources::group(&sources::list())}));
            return result;
        }
        "enable" => {
            let remote = user
                .remote_by_name(text(request, "remote"), Some(cancel))
                .map_err(|e| e.to_string())?;
            if sources::url(&remote) != text(request, "url")
                || text(request, "sourceKey").is_empty()
                || sources::source_key(user, &remote)? != text(request, "sourceKey")
            {
                return Err("The source has changed. Refresh Settings before trying again.".into());
            }
            remote.set_disabled(!flag(request, "enabled"));
            user.modify_remote(&remote, Some(cancel))
                .map_err(|e| e.to_string())?;
        }
        "list" => {}
        _ => return Err("Unknown source operation.".into()),
    }
    send(json!({"type":"sources","sources":sources::group(&sources::list())}));
    if operation == "list" {
        return Ok(());
    }
    let remotes: Vec<_> = user
        .list_remotes(Some(cancel))
        .map_err(|e| e.to_string())?
        .into_iter()
        .filter(|r| !r.is_disabled() && !r.is_noenumerate())
        .collect();
    let total = remotes.len().max(1);
    let mut last = 9;
    for (index, remote) in remotes.iter().enumerate() {
        let mut report = |percent: u32| {
            let value = 10 + (index * 100 + percent.min(100) as usize) * 60 / (total * 100);
            if value > last {
                last = value;
                send(json!({"type":"catalog-progress","progress":value}));
            }
        };
        report(0);
        let cached = remote
            .appstream_dir(None)
            .and_then(|d| d.path())
            .is_some_and(|p| {
                p.join("appstream.xml.gz").is_file() || p.join("appstream.xml").is_file()
            });
        if operation != "refresh" && cached {
            available += 1;
            report(100);
            continue;
        }
        match user.update_appstream_full_sync(
            &sources::name(remote),
            None,
            Some(&mut |_, p, estimating| {
                if !estimating {
                    report(p);
                }
            }),
            Some(cancel),
        ) {
            Ok(_) => {
                available += 1;
                refreshed += 1;
            }
            Err(e) => {
                problems.push(format!("{}: {e}", sources::name(remote)));
                if cached {
                    available += 1;
                } else {
                    failed += 1;
                }
            }
        }
        report(100);
    }
    if !cancel.is_cancelled() {
        if last < 70 {
            send(json!({"type":"catalog-progress","progress":70}));
        }
        send(
            json!({"type":"catalog-load","available":available,"failed":failed,"refreshed":refreshed}),
        );
    }
    if problems.is_empty() {
        Ok(())
    } else {
        Err(problems.join("\n"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reference_urls_do_not_accept_credentials_or_downgrades() {
        assert!(safe_url("https://dl.flathub.org/repo"));
        for url in [
            "http://dl.flathub.org",
            "https://user:password@example.org",
            "file:///tmp/repo",
            "javascript:alert(1)",
        ] {
            assert!(!safe_url(url));
        }
    }
}
