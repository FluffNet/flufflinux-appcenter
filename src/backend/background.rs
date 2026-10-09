//! Notification, batch and sleep-inhibition policy. KDE widgets only display
//! these commands; no decision depends on a notification remaining visible.
use super::{flag, number, text};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};
#[derive(Default)]
pub struct Background {
    pub enabled: bool,
    pub closed: bool,
    proxies: BTreeMap<u64, bool>,
    batch: u64,
    batch_jobs: BTreeMap<u64, Value>,
    reported: bool,
}
fn name(job: &Value) -> &str {
    job.get("name")
        .and_then(Value::as_str)
        .unwrap_or_else(|| text(job, "id"))
}
fn numbered(job: &Value) -> String {
    if number(job, "queueTotal") > 1 {
        format!(
            "{}/{}: {}",
            number(job, "queuePosition"),
            number(job, "queueTotal"),
            name(job)
        )
    } else {
        name(job).into()
    }
}
fn verb(job: &Value, completed: bool) -> &'static str {
    match (text(job, "action"), completed) {
        ("uninstall", false) => "Removing",
        ("update", false) => "Updating",
        (_, false) => "Installing",
        ("uninstall", true) => "removed",
        ("update", true) => "updated",
        (_, true) => "installed",
    }
}
fn html(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
fn presentation(job: &Value) -> Value {
    let downloading =
        flag(job, "hasDownload") && !flag(job, "downloadComplete") && job["phase"] == "download";
    json!({"title":format!("{} {}",verb(job,false),numbered(job)),"completionTitle":format!("{} {}",numbered(job),verb(job,true)),
        "message":if downloading{format!("{} / {} ({})",text(job,"downloadedSize"),text(job,"downloadTotalSize"),text(job,"downloadSpeed"))}else{text(job,"status").into()},
        "totalBytes":number(job,"downloadTotalBytes"),"receivedBytes":number(job,"receivedBytes"),"speed":number(job,"downloadSpeedBytes"),
        "percent":(job["progress"].as_f64().unwrap_or(0.0).clamp(0.0,0.99)*100.0).floor() as u64,"failed":flag(job,"failed"),"error":text(job,"error")})
}
impl Background {
    pub fn synchronize(
        &mut self,
        jobs: &[Value],
        review: &Value,
        work_pending: bool,
    ) -> Vec<Value> {
        if !self.enabled {
            return vec![];
        }
        let mut commands = vec![];
        let by_index: HashMap<_, _> = jobs.iter().map(|job| (number(job, "index"), job)).collect();
        let active: Vec<_> = jobs.iter().filter(|job| flag(job, "active")).collect();
        let transactions = active
            .iter()
            .any(|job| job["action"] != "uninstall" || flag(job, "removalConfirmed"));
        let batch = active
            .iter()
            .map(|job| number(job, "queueBatch"))
            .max()
            .unwrap_or(0);
        if batch != 0 && batch != self.batch {
            self.batch = batch;
            self.batch_jobs.clear();
            self.reported = false;
        }
        for job in jobs {
            if self.batch != 0 && number(job, "queueBatch") == self.batch {
                self.batch_jobs.insert(number(job, "index"), job.clone());
            }
        }
        let mut finished = !self.reported && !self.batch_jobs.is_empty();
        for (index, job) in &mut self.batch_jobs {
            if flag(job, "active") && !by_index.contains_key(index) {
                job["active"] = false.into();
                job["cancelled"] = true.into();
            }
            if flag(job, "active") {
                finished = false;
            }
        }
        commands.push(json!({"kind":"power","active":transactions}));
        for (index, registered) in self.proxies.clone() {
            let job = by_index.get(&index).copied();
            if job.is_none_or(|job| !flag(job, "active")) {
                let discard = !registered
                    || job.is_none_or(|job| flag(job, "cancelled"))
                    || self.batch_jobs.len() > 1;
                commands.push(json!({"kind":"finish","index":index,"discard":discard,"data":job.map(presentation)}));
                self.proxies.remove(&index);
            } else if registered && !self.closed {
                commands.push(json!({"kind":"detach","index":index}));
                self.proxies.insert(index, false);
            }
        }
        for job in active.iter().filter(|job| !flag(job, "queued")) {
            let index = number(job, "index");
            if let std::collections::btree_map::Entry::Vacant(entry) = self.proxies.entry(index) {
                entry.insert(false);
                commands.push(json!({"kind":"create","index":index}));
            }
            if self.closed && !self.proxies[&index] {
                commands.push(json!({"kind":"register","index":index}));
                self.proxies.insert(index, true);
            }
            commands.push(json!({"kind":"update","index":index,"data":presentation(job)}));
        }
        commands.push(json!({"kind":"idle","active":self.closed&&!work_pending}));
        let confirmation = review.as_object().is_some_and(|review| !review.is_empty());
        commands.push(json!({"kind":"tray","visible":self.closed&&!active.is_empty(),"message":if confirmation{"Confirmation needed - open App Center to continue".into()}else{format!("{} app operation(s) in progress",active.len())}}));
        if finished {
            self.reported = true;
            if self.closed && self.batch_jobs.len() > 1 {
                let failed = self.batch_jobs.values().any(|job| flag(job, "failed"));
                let mut lines = vec![];
                for job in self.batch_jobs.values() {
                    let result = if flag(job, "cancelled") {
                        "Cancelled"
                    } else if flag(job, "failed") {
                        "Failed"
                    } else {
                        match text(job, "action") {
                            "uninstall" => "Removed",
                            "update" => "Updated",
                            _ => "Installed",
                        }
                    };
                    lines.push(html(&format!(
                        "{}. {} - {result}",
                        lines.len() + 1,
                        name(job)
                    )));
                }
                commands.push(json!({"kind":"summary","title":if failed{"App queue finished with errors"}else{"App queue complete"},"body":lines.join("\n"),"timeout":5000}));
            }
            self.batch_jobs.clear();
            self.batch = 0;
        }
        commands
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn job(index: u64) -> Value {
        json!({"index":index,"id":format!("a.b.App{index}"),"name":"<App>","action":"install","active":true,"queued":false,"queueBatch":1,"queuePosition":index+1,"queueTotal":2})
    }
    #[test]
    fn reopen_detaches_and_reclose_reregisters_without_restarting_jobs() {
        let mut state = Background {
            enabled: true,
            ..Default::default()
        };
        let jobs = [job(0)];
        let first = state.synchronize(&jobs, &json!({}), true);
        assert!(first.iter().any(|c| c["kind"] == "create"));
        assert!(!first.iter().any(|c| c["kind"] == "register"));
        state.closed = true;
        let closed = state.synchronize(&jobs, &json!({}), true);
        assert!(closed.iter().any(|c| c["kind"] == "register"));
        state.closed = false;
        assert!(state
            .synchronize(&jobs, &json!({}), true)
            .iter()
            .any(|c| c["kind"] == "detach"));
        state.closed = true;
        let again = state.synchronize(&jobs, &json!({}), true);
        assert!(again.iter().any(|c| c["kind"] == "register"));
        assert!(!again.iter().any(|c| c["kind"] == "create"));
    }
    #[test]
    fn summaries_keep_cancelled_items_escape_markup_and_are_emitted_once() {
        let mut state = Background {
            enabled: true,
            closed: true,
            ..Default::default()
        };
        let mut complete = job(0);
        state.synchronize(&[complete.clone(), job(1)], &json!({}), true);
        complete["active"] = false.into();
        let commands = state.synchronize(&[complete.clone()], &json!({}), false);
        let summary = commands.iter().find(|c| c["kind"] == "summary").unwrap();
        assert_eq!(
            summary["body"],
            "1. &lt;App&gt; - Installed\n2. &lt;App&gt; - Cancelled"
        );
        assert_eq!(summary["timeout"], 5000);
        assert!(!state
            .synchronize(&[complete], &json!({}), false)
            .iter()
            .any(|c| c["kind"] == "summary"));
    }
    #[test]
    fn unconfirmed_removal_does_not_inhibit_sleep() {
        let mut state = Background {
            enabled: true,
            ..Default::default()
        };
        let mut removal = job(0);
        removal["action"] = "uninstall".into();
        removal["queued"] = true.into();
        let commands = state.synchronize(&[removal], &json!({}), true);
        assert!(commands
            .iter()
            .any(|c| c["kind"] == "power" && c["active"] == false));
    }
}
