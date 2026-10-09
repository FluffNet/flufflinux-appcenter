//! A small queue journal, independent of the application-list cache. Workers
//! perform bounded I/O; recovery inspects deployments but never replays work.
use super::{flag, rows, sources, storage, text};
use libflatpak::prelude::*;
use serde_json::{json, Value};
use std::{collections::HashMap, io::Read, path::Path};

pub const LIMIT: u64 = 2 * 1024 * 1024;
const MAX_ITEMS: usize = 512;

fn fields(value: &Value, keys: &[&str]) -> Value {
    let mut result = json!({});
    for key in keys {
        if let Some(value) = value.get(*key) {
            result[*key] = value.clone();
        }
    }
    result
}
pub fn record(job: &Value) -> Value {
    let mut result = fields(
        job,
        &[
            "recoveryId",
            "action",
            "id",
            "name",
            "installation",
            "flatpakRef",
            "remote",
            "sourceUrl",
            "source",
            "addon",
            "installedArch",
            "installedBranch",
        ],
    );
    if flag(job, "addon") {
        result["parent"] = fields(
            &job["parent"],
            &["id", "name", "installation", "installedRef"],
        );
    }
    let operations = if rows(&job["operations"]).is_empty() {
        &job["plan"]
    } else {
        &job["operations"]
    };
    result["operations"] = rows(operations)
        .iter()
        .map(|op| fields(op, &["action", "ref", "commit", "remote"]))
        .collect::<Vec<_>>()
        .into();
    result
}
fn validate(records: &[Value]) -> Result<(), String> {
    if records.len() > MAX_ITEMS {
        return Err("Too many pending operations to save safely.".into());
    }
    let mut ids = std::collections::HashSet::new();
    for item in records {
        if !matches!(
            text(item, "action"),
            "install" | "source" | "update" | "uninstall"
        ) || text(item, "recoveryId").is_empty()
            || !ids.insert(text(item, "recoveryId"))
            || text(item, "installation").is_empty()
            || text(item, "name").is_empty()
            || rows(&item["operations"]).len() > 1024
            || serde_json::to_vec(item).map_err(|e| e.to_string())?.len() > 256 * 1024
        {
            return Err("The saved queue is invalid. It has been left unchanged.".into());
        }
    }
    Ok(())
}
pub fn save(path: &Path, records: &[Value]) -> Result<(), String> {
    validate(records)?;
    let mut document = json!({"version":1,"items":records});
    document["checksum"] = storage::checksum(&document).into();
    let data = document.to_string();
    if data.len() as u64 > LIMIT {
        return Err("The pending queue is too large to save safely.".into());
    }
    let _lock =
        storage::FileLock::acquire(&path.with_extension("lock")).map_err(|e| e.to_string())?;
    storage::atomic_write(path, data.as_bytes()).map_err(|e| e.to_string())
}
pub fn load(path: &Path) -> Result<Vec<Value>, String> {
    // Do not create a state directory on an ordinary, empty-queue startup.
    let mut document = match storage::read_json(path, LIMIT) {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(vec![]),
        Err(error) => return Err(format!("Could not read the saved queue: {error}")),
    };
    let expected = text(&document, "checksum").to_owned();
    document
        .as_object_mut()
        .ok_or("Invalid saved queue")?
        .remove("checksum");
    if document["version"] != 1 || expected != storage::checksum(&document) {
        return Err(
            "The saved queue is damaged or unsupported. It has been left unchanged.".into(),
        );
    }
    let records = document["items"]
        .as_array_mut()
        .ok_or("Invalid saved queue")?;
    validate(records)?;
    Ok(std::mem::take(records))
}
// A successful removal also deletes user data. An absent deployment alone
// cannot prove that cleanup finished, so removals are never replayed or
// reported as wholly complete based only on a missing ref.
pub fn outcome(record: &Value, installed: &HashMap<String, String>) -> &'static str {
    if record["action"] == "uninstall" {
        return "interrupted";
    }
    let ops = rows(&record["operations"]);
    if !ops.is_empty()
        && ops.iter().all(|op| {
            !text(op, "commit").is_empty()
                && installed
                    .get(text(op, "ref"))
                    .is_some_and(|commit| commit == text(op, "commit"))
                && matches!(text(op, "action"), "install" | "update" | "install-bundle")
        })
    {
        "completed"
    } else {
        "interrupted"
    }
}
pub fn inspect(records: &[Value]) -> Vec<Value> {
    let mut scopes = HashMap::new();
    for record in records {
        scopes
            .entry(text(record, "installation").to_owned())
            .or_insert_with(|| {
                sources::installation(text(record, "installation"))
                    .and_then(|installation| {
                        installation
                            .list_installed_refs(gio::Cancellable::NONE)
                            .map_err(|e| e.to_string())
                    })
                    .map(|installed| {
                        installed
                            .iter()
                            .map(|app| {
                                (
                                    app.format_ref().unwrap_or_default().to_string(),
                                    app.commit().unwrap_or_default().to_string(),
                                )
                            })
                            .collect::<HashMap<_, _>>()
                    })
            });
    }
    records
        .iter()
        .map(|record| {
            let mut item = record.clone();
            match &scopes[text(record, "installation")] {
                Ok(installed) => {
                    item["state"] = outcome(record, installed).into();
                    if record["action"] == "uninstall" {
                        let reference = if !text(record, "flatpakRef").is_empty() {
                            text(record, "flatpakRef").to_owned()
                        } else {
                            format!(
                                "app/{}/{}/{}",
                                text(record, "id"),
                                text(record, "installedArch"),
                                text(record, "installedBranch")
                            )
                        };
                        if !installed.contains_key(&reference) {
                            item["state"] = "removed".into();
                        }
                    }
                }
                Err(error) => {
                    item["state"] = "unknown".into();
                    item["error"] = error.clone().into();
                }
            }
            item
        })
        .collect()
}
pub fn worker(action: &str, path: &Path) -> Value {
    let result = match action {
        "load" => {
            load(path).map(|records| json!({"ok":true,"items":inspect(&records),"records":records}))
        }
        "save" => (|| {
            let mut data = Vec::new();
            std::io::stdin()
                .take(LIMIT + 1)
                .read_to_end(&mut data)
                .map_err(|e| e.to_string())?;
            if data.len() as u64 > LIMIT {
                return Err("Queue journal exceeds its size limit".into());
            }
            let records: Vec<Value> = serde_json::from_slice(&data).map_err(|e| e.to_string())?;
            save(path, &records)?;
            Ok(json!({"ok":true}))
        })(),
        _ => Err("Unknown queue recovery operation".into()),
    };
    result.unwrap_or_else(|error| json!({"ok":false,"error":error}))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn item() -> Value {
        json!({"recoveryId":"fixture:1","name":"Example","id":"org.example.App","action":"install","installation":"user","operations":[{"action":"install","ref":"app/org.example.App/x86_64/stable","commit":"new"},{"action":"install","ref":"runtime/org.example.Runtime/x86_64/stable","commit":"runtime"}]})
    }
    #[test]
    fn requires_all_deployments_and_exact_commits() {
        let item = item();
        let mut installed = HashMap::new();
        assert_eq!(outcome(&item, &installed), "interrupted");
        installed.insert("app/org.example.App/x86_64/stable".into(), "new".into());
        assert_eq!(outcome(&item, &installed), "interrupted");
        installed.insert(
            "runtime/org.example.Runtime/x86_64/stable".into(),
            "runtime".into(),
        );
        assert_eq!(outcome(&item, &installed), "completed");
        let mut removal = item;
        removal["action"] = "uninstall".into();
        assert_eq!(outcome(&removal, &HashMap::new()), "interrupted");
    }
    #[test]
    fn corruption_is_rejected_without_overwriting() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("queue.json");
        assert!(load(&path).unwrap().is_empty());
        save(&path, &[item()]).unwrap();
        assert_eq!(load(&path).unwrap(), vec![item()]);
        let mut corrupt = storage::read_json(&path, LIMIT).unwrap();
        corrupt["items"][0]["name"] = "changed".into();
        storage::write_json(&path, &corrupt).unwrap();
        let before = std::fs::read(&path).unwrap();
        assert!(load(&path).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), before);
    }
    #[test]
    fn journal_does_not_retain_preview_payloads_or_old_consent() {
        let mut job = item();
        job["previewPermissions"] = json!({"secret":"large"});
        job["removalConfirmed"] = true.into();
        job["description"] = "large".into();
        let saved = record(&job);
        for field in ["previewPermissions", "removalConfirmed", "description"] {
            assert!(saved.get(field).is_none());
        }
    }
}
