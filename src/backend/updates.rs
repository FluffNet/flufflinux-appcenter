//! Explicit update scanning, pinned transaction plans and permission changes.
use super::{bytes, flag, permissions, process, progress, sources, text};
use glib::translate::*;
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
    target: String,
}
/// Use the same solver policy for the read-only scan and actual deployment.
/// Flatpak decides which runtimes are unused (including its pin/use checks).
pub struct Policy {
    replacements: Rc<RefCell<BTreeMap<String, String>>>,
    error: Rc<RefCell<String>>,
}
impl Policy {
    pub fn check(&self) -> Result<(), String> {
        let error = self.error.borrow();
        if error.is_empty() {
            Ok(())
        } else {
            Err(error.clone())
        }
    }
    fn target(&self, reference: &str) -> Result<String, String> {
        self.check()?;
        let replacements = self.replacements.borrow();
        let mut target = reference;
        let mut seen = std::collections::HashSet::new();
        while let Some(next) = replacements.get(target) {
            if !seen.insert(target) {
                return Err("The source contains a circular app replacement.".into());
            }
            target = next;
        }
        Ok(target.into())
    }
}
pub fn configure(tx: &Transaction) -> Policy {
    tx.set_include_unused_uninstall_ops(true);
    let replacements = Rc::new(RefCell::new(BTreeMap::new()));
    let recorded = replacements.clone();
    let error = Rc::new(RefCell::new(String::new()));
    let recorded_error = error.clone();
    // The generated Rust binding omits this signal and the rebase API's string
    // array argument. Keep the small FFI adapter here, not in the UI glue.
    tx.connect_local("end-of-lifed-with-rebase", false, move |values| {
        let result = (|| -> Result<bool, glib::Error> {
            let tx = values[0].get::<Transaction>().expect("transaction signal");
            let remote = values[1].get::<String>().expect("remote signal");
            let old = values[2].get::<String>().expect("ref signal");
            let Some(new) = values[4].get::<Option<String>>().expect("rebase signal") else {
                return Ok(false);
            };
            let previous = values[5].get::<glib::StrV>().expect("previous IDs signal");
            let previous: Vec<&str> = previous.iter().map(|s| s.as_str()).collect();
            // The combined API orders removal AFTER a successful replacement.
            // Independent install/uninstall operations cannot guarantee that.
            unsafe {
                let mut error = std::ptr::null_mut();
                let ok = libflatpak::ffi::flatpak_transaction_add_rebase_and_uninstall(
                    tx.to_glib_none().0,
                    remote.to_glib_none().0,
                    new.to_glib_none().0,
                    old.to_glib_none().0,
                    std::ptr::null_mut(),
                    previous.to_glib_none().0,
                    &mut error,
                );
                if ok == 0 {
                    return Err(from_glib_full(error));
                }
            }
            recorded.borrow_mut().insert(old, new);
            Ok(true)
        })();
        let accepted = match result {
            Ok(accepted) => accepted,
            Err(error) => {
                *recorded_error.borrow_mut() = error.to_string();
                false
            }
        };
        Some(accepted.to_value())
    });
    Policy {
        replacements,
        error,
    }
}

fn installed(
    installation: &Installation,
    reference: &str,
) -> Result<Option<libflatpak::InstalledRef>, String> {
    let parsed = libflatpak::Ref::parse(reference).map_err(|e| e.to_string())?;
    match installation.installed_ref(
        parsed.kind(),
        parsed.name().as_deref().ok_or("Invalid installed ref")?,
        parsed.arch().as_deref(),
        parsed.branch().as_deref(),
        gio::Cancellable::NONE,
    ) {
        Ok(value) => Ok(Some(value)),
        Err(error) if error.matches(libflatpak::Error::NotInstalled) => Ok(None),
        Err(error) => Err(error.to_string()),
    }
}

/// Removals have no remote target commit: pin the installed deployment instead.
pub fn checked_operation(
    installation: &Installation,
    op: &libflatpak::TransactionOperation,
) -> Result<Value, String> {
    let mut row = operation_info(op);
    if op.operation_type() == libflatpak::TransactionOperationType::Uninstall {
        let current = installed(installation, text(&row, "ref"))?
            .ok_or("A component scheduled for removal changed. Check for updates again.")?;
        let commit = current.commit().unwrap_or_default();
        if !progress::valid_commit(&commit) {
            return Err("The installed component could not be verified.".into());
        }
        row["installedCommit"] = commit.as_str().into();
        row["installedOrigin"] = current.origin().unwrap_or_default().as_str().into();
        row["downloadBytes"] = 0.into();
        row["downloadSize"] = bytes(0).into();
        return Ok(row);
    }
    let remote = installation
        .remote_by_name(text(&row, "remote"), gio::Cancellable::NONE)
        .map_err(|_| "The update source is missing or could not be verified.")?;
    if remote.is_disabled() || !progress::valid_commit(text(&row, "commit")) {
        return Err("The update source is disabled or could not be verified.".into());
    }
    row["sourceUrl"] = sources::url(&remote).into();
    row["sourceKey"] = sources::source_key(installation, &remote)?.into();
    Ok(row)
}

pub fn operation_satisfied(installation: &Installation, row: &Value) -> bool {
    let Ok(current) = installed(installation, text(row, "ref")) else {
        return false;
    };
    if text(row, "action") == "uninstall" {
        current.is_none()
    } else {
        current.is_some_and(|r| {
            r.commit().as_deref() == Some(text(row, "commit"))
                && r.origin().as_deref() == Some(text(row, "remote"))
        })
    }
}

pub fn matches_resolved_plan(
    installation: &Installation,
    expected: &[Value],
    actual: &[Value],
) -> bool {
    // Earlier queued updates can release the final user of a runtime. Permit
    // only *new* solver-selected runtime cleanup here, not changed snapshots,
    // unreviewed downloads, or arbitrary app removals. These rows come from
    // libflatpak's ready signal, never by replaying request uninstall entries.
    let mut permitted = expected.to_vec();
    permitted.extend(
        actual
            .iter()
            .filter(|op| {
                text(op, "action") == "uninstall"
                    && text(op, "ref").starts_with("runtime/")
                    && !expected.iter().any(|row| row["ref"] == op["ref"])
            })
            .cloned(),
    );
    progress::matches_plan(&permitted, actual)
        && expected.iter().all(|row| {
            actual
                .iter()
                .any(|op| op["ref"] == row["ref"] && op["action"] == row["action"])
                || operation_satisfied(installation, row)
        })
}
fn plan(installation: &Installation, reference: &str) -> Result<Plan, String> {
    let tx = Transaction::for_installation(installation, gio::Cancellable::NONE)
        .map_err(|e| e.to_string())?;
    tx.set_no_interaction(true);
    let policy = configure(&tx);
    tx.add_default_dependency_sources();
    tx.connect_add_new_remote(|_, _, _, _, _| false);
    let result = Rc::new(RefCell::new(Plan::default()));
    let state = result.clone();
    let installation = installation.clone();
    let reference = reference.to_owned();
    let expected_ref = reference.clone();
    tx.connect_ready_pre_auth(move |tx| {
        let mut plan = state.borrow_mut();
        plan.target = match policy.target(&expected_ref) {
            Ok(target) => target,
            Err(error) => {
                plan.error = error;
                return false;
            }
        };
        for op in tx.operations() {
            if op.is_skipped() {
                continue;
            }
            let full_ref = op.get_ref().unwrap_or_default();
            let row = match checked_operation(&installation, &op) {
                Ok(row) => row,
                Err(error) => {
                    plan.error = error;
                    break;
                }
            };
            plan.operations.push(row);
            if full_ref == plan.target && full_ref.starts_with("app/") {
                let before = if plan.target != expected_ref {
                    installed(&installation, &expected_ref)
                        .ok()
                        .flatten()
                        .and_then(|r| r.load_metadata(gio::Cancellable::NONE).ok())
                        .map(|b| b.as_ref().to_vec())
                        .unwrap_or_default()
                } else {
                    op.old_metadata()
                        .map(|k| k.to_data().as_bytes().to_vec())
                        .unwrap_or_default()
                };
                let after = op.metadata().map(|k| k.to_data()).unwrap_or_default();
                plan.permissions = permissions::changes(&before, after.as_bytes());
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
        let mut rebased = std::collections::HashSet::new();
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
                            if item.eol_rebase().is_some_and(|r| !r.is_empty()) {
                                rebased.insert(item.format_ref().unwrap_or_default().to_string());
                            }
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
            if rebased.contains(reference.as_str())
                || published
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
                    errors.push(format!("{id} ({scope}): {e}"));
                    continue;
                }
            };
            let commit = plan
                .operations
                .iter()
                .find(|r| text(r, "ref") == plan.target && text(r, "action") != "uninstall")
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
                .and_then(|v| v.get(&plan.target))
                .filter(|v| !v.is_empty())
                .cloned()
                .unwrap_or_else(|| {
                    format!("Revision {}", commit.chars().take(12).collect::<String>())
                });
            updates.push(json!({"key":format!("{scope}:{reference}"),"id":id.as_str(),"name":name.as_str(),"installation":scope,"flatpakRef":reference,
                "remote":origin,"sourceUrl":sources::url(&remote),"oldCommit":old_commit.as_str(),"commit":commit,"targetRef":plan.target,"oldVersion":old_version,"newVersion":new_version,
                "runtime":reference.starts_with("runtime/"),"selected":true,"downloadBytes":download,"downloadSize":bytes(download),"plan":plan.operations,"permissions":plan.permissions}));
        }
    }
    json!({"type":"updates","updates":updates,"errors":errors,"skipped":skipped,"checkedAt":chrono::Utc::now().to_rfc3339()})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn full_plan_accepts_related_apps_but_pins_removal_deployments() {
        let removal = json!({"ref":"runtime/org.kde.Platform/x86_64/6.9","action":"uninstall",
            "commit":"","remote":"","installedCommit":"a".repeat(64),"installedOrigin":"flathub"});
        let related = json!({"ref":"app/org.example.Other/x86_64/stable","action":"install",
            "commit":"b".repeat(64),"remote":"flathub","sourceKey":"verified"});
        let expected = vec![removal.clone(), related];
        assert!(progress::matches_plan(&expected, &expected));
        let mut changed = removal.clone();
        changed["installedCommit"] = "c".repeat(64).into();
        assert!(!progress::matches_plan(&expected, &[changed]));
        let mut unknown = removal.clone();
        unknown["ref"] = "runtime/org.example.Unreviewed/x86_64/stable".into();
        assert!(!progress::matches_plan(&expected, &[unknown]));
        let mut invalid = removal;
        invalid["installedCommit"] = "".into();
        assert!(!progress::matches_plan(&expected, &[invalid]));
    }
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
