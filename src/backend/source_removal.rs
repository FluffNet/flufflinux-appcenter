//! Privileged source removal accepts identities, never executable or file paths.
use super::{process, sources, text};
use libflatpak::{prelude::*, Installation, Remote};
use serde_json::Value;
use std::{collections::BTreeSet, process::Command, time::Duration};

pub struct Target {
    pub installation: Installation,
    pub expected: Value,
}
pub fn matches(installation: &Installation, expected: &Value) -> Result<Remote, String> {
    let name = text(expected, "name");
    if !sources::valid_name(name) {
        return Err("Invalid software-source name.".into());
    }
    installation
        .drop_caches(gio::Cancellable::NONE)
        .map_err(|_| "Could not re-read the software source safely.")?;
    let remote = installation
        .list_remotes(gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|r| sources::name(r) == name)
        .ok_or_else(|| {
            format!(
                "Could not read source {name} ({}): source not found",
                sources::scope(installation)
            )
        })?;
    if sources::url(&remote) != text(expected, "url") {
        return Err(format!(
            "The address of {name} changed. Refresh Settings before removing it."
        ));
    }
    if text(expected, "sourceKey").is_empty()
        || sources::source_key(installation, &remote)? != text(expected, "sourceKey")
    {
        return Err(format!(
            "The signing keys or settings of {name} changed. Refresh Settings before removing it."
        ));
    }
    Ok(remote)
}
pub fn resolve(
    user: Option<&Installation>,
    members: &[Value],
    system_only: bool,
) -> Result<Vec<Target>, String> {
    if members.is_empty() || members.len() > 32 {
        return Err("Invalid source-removal request.".into());
    }
    let systems =
        libflatpak::system_installations(gio::Cancellable::NONE).map_err(|e| e.to_string())?;
    let mut seen = BTreeSet::new();
    let mut targets = Vec::new();
    for member in members {
        let scope = text(member, "scope");
        let installation = if scope == "user" && !system_only {
            user.cloned()
        } else {
            systems.iter().find(|i| sources::scope(i) == scope).cloned()
        };
        let Some(installation) = installation else {
            return Err("Invalid source-removal target.".into());
        };
        if scope.is_empty() || !seen.insert(format!("{scope}:{}", text(member, "name"))) {
            return Err("Invalid source-removal target.".into());
        }
        matches(&installation, member)?;
        targets.push(Target {
            installation,
            expected: member.clone(),
        });
    }
    Ok(targets)
}
pub fn remove(target: &Target, cancel: Option<&gio::Cancellable>) -> Result<(), String> {
    matches(&target.installation, &target.expected)?;
    let scope = sources::scope(&target.installation);
    if scope.is_empty() {
        return Err("Invalid system installation.".into());
    }
    let mut command = Command::new("/usr/bin/flatpak");
    command.args(["remote-delete", "--force"]);
    if target.installation.is_user() {
        command
            .arg("--user")
            .env("FLATPAK_USER_DIR", sources::location(&target.installation)?);
    } else {
        command.arg(format!("--installation={scope}"));
    }
    command.args(["--", text(&target.expected, "name")]);
    let output = process::run(command, Duration::from_secs(120), 1024 * 1024, cancel)?;
    if output.code != 0 {
        return Err(if output.stderr.is_empty() {
            "Could not remove the software source.".into()
        } else {
            output.stderr
        });
    }
    target
        .installation
        .drop_caches(gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    Ok(())
}
pub fn privileged_main(request: &str) -> Result<(), String> {
    if unsafe { libc::geteuid() } != 0 || request.len() > 65536 {
        return Err(
            "Administrator authorization and a bounded source-removal request are required.".into(),
        );
    }
    // Elevation clears a pre-exec parent-death signal. Restore it here so a
    // cancelled or killed caller cannot leave this privileged helper behind.
    process::parent_death_signal()?;
    for key in [
        "FLATPAK_USER_DIR",
        "FLATPAK_SYSTEM_DIR",
        "FLATPAK_CONFIG_DIR",
    ] {
        std::env::remove_var(key);
    }
    let members: Vec<Value> =
        serde_json::from_str(request).map_err(|_| "Invalid source-removal request.")?;
    let targets = resolve(None, &members, true)?;
    for (index, target) in targets.iter().enumerate() {
        remove(target, None).map_err(|e| {
            if index == 0 {
                e
            } else {
                format!("{e} Some system copies were already removed; refresh Settings.")
            }
        })?;
    }
    Ok(())
}
