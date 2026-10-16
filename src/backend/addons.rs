//! Add-ons must be related to the actual installed parent, not guessed IDs.
use super::{flag, rows, sources, text};
use libflatpak::{prelude::*, Ref, RefKind};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

pub fn error(message: &str) -> Value {
    json!({"state":"error","error":message})
}
pub fn compact_parent(input: &Value) -> Value {
    let mut parent = json!({});
    for key in [
        "installedRef",
        "installation",
        "sourceUrl",
        "parentCommit",
        "remote",
    ] {
        parent[key] = input[key].clone();
    }
    parent["addons"] = rows(&input["addons"])
        .iter()
        .map(|input| {
            let mut row = json!({});
            for key in [
                "id",
                "name",
                "summary",
                "developer",
                "icon",
                "flatpakRef",
                "sourceUrl",
            ] {
                row[key] = input[key].clone();
            }
            row
        })
        .collect::<Vec<_>>()
        .into();
    parent
}
pub fn read(input: &Value, cancel: Option<&gio::Cancellable>, installed_only: bool) -> Value {
    let mut parent = compact_parent(input);
    let scope = text(&parent, "installation").to_owned();
    let not_installed = || json!({"state":"not-installed","items":parent["addons"]});
    if scope.is_empty() {
        return not_installed();
    }
    let full_ref = text(&parent, "installedRef").to_owned();
    let Ok(parsed) = Ref::parse(&full_ref) else {
        return error("The parent app is no longer available. Reopen its page.");
    };
    if parsed.kind() != RefKind::App {
        return error("The parent app is no longer available. Reopen its page.");
    }
    let Ok(instance) = sources::installation(&scope) else {
        return error("Could not open this Flatpak installation.");
    };
    let Ok(installed) = instance.installed_ref(
        RefKind::App,
        &parsed.name().unwrap_or_default(),
        parsed.arch().as_deref(),
        parsed.branch().as_deref(),
        cancel,
    ) else {
        return not_installed();
    };
    let commit = installed.commit().unwrap_or_default();
    if !text(&parent, "parentCommit").is_empty() && text(&parent, "parentCommit") != commit {
        return error("The app changed. Reopen Add-Ons before continuing.");
    }
    let origin = installed.origin().unwrap_or_default();
    let Ok(remote) = instance.remote_by_name(&origin, cancel) else {
        return error("This app's source is unavailable or has changed. Refresh its page.");
    };
    if sources::url(&remote) != text(&parent, "sourceUrl") {
        return error("This app's source is unavailable or has changed. Refresh its page.");
    }
    parent["parentCommit"] = commit.as_str().into();
    parent["remote"] = origin.as_str().into();
    let mut refs = BTreeMap::new();
    for item in instance
        .list_installed_related_refs_sync(&origin, &full_ref, cancel)
        .unwrap_or_default()
    {
        refs.insert(item.format_ref().unwrap_or_default().to_string(), false);
    }
    let mut failure = false;
    if !installed_only && !remote.is_disabled() {
        match instance.list_remote_related_refs_for_installed_sync(&origin, &full_ref, cancel) {
            Ok(available) => {
                for item in available {
                    refs.insert(item.format_ref().unwrap_or_default().to_string(), true);
                }
            }
            Err(_) => failure = true,
        }
    }
    let mut items = Vec::new();
    let mut seen = BTreeSet::new();
    for metadata in rows(&parent["addons"]) {
        let Ok(candidate) = Ref::parse(text(metadata, "flatpakRef")) else {
            continue;
        };
        if candidate.kind() != RefKind::Runtime {
            continue;
        }
        for (full_ref, available) in &refs {
            let Ok(reference) = Ref::parse(full_ref) else {
                continue;
            };
            if reference.kind() != RefKind::Runtime
                || reference.name() != candidate.name()
                || reference.arch() != parsed.arch()
            {
                continue;
            }
            let current = instance
                .installed_ref(
                    RefKind::Runtime,
                    &reference.name().unwrap_or_default(),
                    reference.arch().as_deref(),
                    reference.branch().as_deref(),
                    cancel,
                )
                .ok();
            if current
                .as_ref()
                .is_some_and(|r| r.origin().as_deref() != Some(origin.as_str()))
                || !seen.insert(full_ref.clone())
            {
                continue;
            }
            let mut row = metadata.clone();
            row["id"] = reference.name().unwrap_or_default().as_str().into();
            row["flatpakRef"] = full_ref.clone().into();
            row["installed"] = current.is_some().into();
            row["available"] = (*available).into();
            row["installation"] = scope.clone().into();
            row["remote"] = origin.as_str().into();
            row["addon"] = true.into();
            row["installedArch"] = reference.arch().unwrap_or_default().as_str().into();
            row["installedBranch"] = reference.branch().unwrap_or_default().as_str().into();
            items.push(row);
        }
    }
    json!({"state":"ready","parent":parent,"items":items,"error":if failure {"Could not check available add-ons. Installed add-ons are still shown."}else{""}})
}
pub fn validate(request: &Value, cancel: &gio::Cancellable) -> Result<(), String> {
    let removing = text(request, "action") == "uninstall";
    let result = read(&request["parent"], Some(cancel), removing);
    if text(&result, "state") == "ready"
        && rows(&result["items"]).iter().any(|row| {
            ["flatpakRef", "installation", "remote", "id"]
                .iter()
                .all(|key| row[key] == request[key])
                && flag(row, if removing { "installed" } else { "available" })
        })
    {
        return Ok(());
    }
    let message = text(&result, "error");
    Err(if message.is_empty() {
        "This add-on is no longer compatible or available. Reopen Add-Ons."
    } else {
        message
    }
    .into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn not_installed_parent_is_not_actionable() {
        let output = read(
            &json!({"addons":[{"id":"a.b.C","flatpakRef":"runtime/a.b.C/x86_64/stable","untrusted":"drop"}]}),
            None,
            false,
        );
        assert_eq!(output["state"], "not-installed");
        assert!(output["items"][0]["untrusted"].is_null());
    }
}
