use super::*;
use crate::backend::recovery;

#[derive(Default)]
pub(super) struct RecoveryState {
    path: String,
    loaded: bool,
    failed: bool,
    revision: u64,
    saved: u64,
    notice: u64,
    records: Vec<Value>,
}

impl Manager {
    pub(super) fn enable_recovery(&mut self, path: &str) {
        if !self.recovery.path.is_empty() {
            return;
        }
        self.recovery.path = if path.is_empty() {
            storage::data_dir()
                .join("pending-queue.json")
                .to_string_lossy()
                .into()
        } else {
            path.into()
        };
        self.defer("loadRecovery");
    }
    pub(super) fn load_recovery(&mut self) {
        if self.recovery.path.is_empty()
            || self.tasks.contains_key("recovery")
            || self.tasks.contains_key("journal")
            || (self.recovery.loaded && self.busy())
        {
            return;
        }
        self.recovery.failed = false;
        self.merge("recovery", json!({"checking":true,"error":""}));
        self.start(
            "recovery",
            "@self",
            json!(["--recovery-worker", "load", self.recovery.path]),
            15000,
            recovery::LIMIT * 3,
            false,
            json!({}),
        );
    }
    pub(super) fn queue_changed(&mut self) {
        if !self.recovery.path.is_empty() {
            self.recovery.revision += 1;
        }
    }
    pub(super) fn queue_saved(&self) -> bool {
        self.recovery.path.is_empty()
            || (self.recovery.loaded
                && !self.recovery.failed
                && self.recovery.saved == self.recovery.revision)
    }
    pub(super) fn recovery_pending(&self) -> bool {
        self.tasks.contains_key("recovery")
            || self.tasks.contains_key("journal")
            || (!self.recovery.path.is_empty()
                && !self.recovery.failed
                && self.recovery.saved != self.recovery.revision)
    }
    pub(super) fn flush_queue(&mut self) {
        if self.recovery.path.is_empty()
            || !self.recovery.loaded
            || self.recovery.failed
            || self.tasks.contains_key("journal")
            || self.tasks.contains_key("recovery")
            || self.recovery.saved == self.recovery.revision
            || self.stopping
        {
            return;
        }
        let mut records = self.recovery.records.clone();
        records.extend(
            self.jobs
                .iter()
                .filter(|job| flag(job, "active") && !flag(job, "prepareOnly"))
                .map(recovery::record),
        );
        let data = serde_json::to_string(&records).unwrap();
        if data.len() as u64 > recovery::LIMIT {
            self.recovery_error("The pending queue is too large to save safely.");
            return;
        }
        self.start(
            "journal",
            "@self",
            json!(["--recovery-worker", "save", self.recovery.path]),
            5000,
            8192,
            false,
            json!({"revision":self.recovery.revision}),
        );
        self.transport("journal", "write", json!({"data":data}));
        self.transport("journal", "close", json!({}));
        self.merge("recovery", json!({"saving":true}));
    }
    fn recovery_error(&mut self, message: &str) {
        self.recovery.failed = true;
        self.recovery.notice += 1;
        self.merge("recovery", json!({"error":format!("{message}\nNew queue operations are paused until recovery data can be saved safely."),
            "checking":false,"saving":false,"notice":self.recovery.notice}));
    }
    pub(super) fn recovery_finished(&mut self, role: &str, context: Value, event: &Value) {
        let result: Value = serde_json::from_str(text(event, "stdout")).unwrap_or(Value::Null);
        if !success(event) || !flag(&result, "ok") {
            let error = if flag(event, "timedOut") {
                "Reading or saving the queue timed out. The previous saved queue has been kept."
            } else if !text(&result, "error").is_empty() {
                text(&result, "error")
            } else {
                "Could not read or save queue recovery data. The previous saved queue has been kept."
            };
            self.recovery_error(error);
            return;
        }
        if role == "recovery" {
            // Loading cannot launch any saved transaction. Only explicit review
            // routes back through the current app/update/removal workflows.
            self.recovery.loaded = true;
            self.recovery.records = rows(&result["records"]).to_vec();
            self.recovery.notice += 1;
            self.set("recovery", json!({"items":result["items"],"error":"","checking":false,"saving":false,"notice":self.recovery.notice}));
        } else {
            self.recovery.saved = number(&context, "revision");
            self.merge("recovery", json!({"saving":false,"error":""}));
        }
        self.flush_queue();
        self.defer("startNext");
    }
    pub(super) fn retry_recovery_io(&mut self) {
        if self.tasks.contains_key("journal") || self.tasks.contains_key("recovery") {
            return;
        }
        self.recovery.failed = false;
        self.merge("recovery", json!({"error":""}));
        if self.recovery.loaded {
            self.flush_queue();
        } else {
            self.load_recovery();
        }
    }
    pub(super) fn dismiss_recovery(&mut self) {
        if !self.recovery.loaded || self.tasks.contains_key("recovery") {
            return;
        }
        self.recovery.records.clear();
        self.merge("recovery", json!({"items":[]}));
        self.queue_changed();
    }
    pub(super) fn replace_recovered(&mut self, request: &Value) {
        let replaced: Vec<_> = self
            .recovery
            .records
            .iter()
            .filter(|old| {
                old["action"] == request["action"]
                    && old["installation"] == request["installation"]
                    && ((!text(old, "source").is_empty() && old["source"] == request["source"])
                        || (!text(old, "id").is_empty()
                            && old["id"] == request["id"]
                            && old["flatpakRef"] == request["flatpakRef"]
                            && old["installedArch"] == request["installedArch"]
                            && old["installedBranch"] == request["installedBranch"]))
            })
            .map(|item| item["recoveryId"].clone())
            .collect();
        if replaced.is_empty() {
            return;
        }
        self.recovery
            .records
            .retain(|item| !replaced.contains(&item["recoveryId"]));
        let items: Vec<_> = rows(&self.properties["recovery"]["items"])
            .iter()
            .filter(|item| !replaced.contains(&item["recoveryId"]))
            .cloned()
            .collect();
        self.merge("recovery", json!({"items":items}));
    }
    pub(super) fn review_recovery(&mut self, index: usize) {
        if self.busy() || self.recovery.failed || self.tasks.contains_key("recovery") {
            return;
        }
        let Some(item) = rows(&self.properties["recovery"]["items"])
            .get(index)
            .cloned()
        else {
            return;
        };
        if !matches!(text(&item, "state"), "interrupted") {
            return;
        }
        if item["action"] == "update" {
            self.signal("updatesRequested", json!([]));
            self.check_updates();
        } else if flag(&item, "addon") {
            self.open_source(&format!("appstream:{}", text(&item["parent"], "id")));
        } else if item["action"] == "uninstall" {
            self.uninstall_app(&item);
        } else if item["action"] == "source" {
            self.open_source(text(&item, "source"));
        } else {
            self.open_source(&format!("appstream:{}", text(&item, "id")));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn manager() -> Manager {
        let mut manager = Manager::new(vec![]);
        manager.enable_recovery("/tmp/appcenter-unit-test-journal.json");
        manager.dispatch("loadRecovery", &json!([]));
        manager
    }
    fn finish(manager: &mut Manager, role: &str, result: Value) -> Value {
        let serial = manager.tasks[role].serial;
        manager.dispatch("event", &json!([{"role":role,"serial":serial,"kind":"finished","code":0,"stdout":result.to_string()}]))
    }
    fn request(id: &str) -> Value {
        json!({"action":"install","id":id,"name":id,"installation":"user","flatpakRef":format!("app/{id}/x86_64/stable")})
    }
    #[test]
    fn nothing_starts_until_the_latest_queue_is_durably_saved() {
        let mut manager = manager();
        manager.enqueue(request("org.example.One"));
        manager.initial();
        assert!(!manager.tasks.contains_key("install"));
        finish(
            &mut manager,
            "recovery",
            json!({"ok":true,"records":[],"items":[]}),
        );
        assert!(manager.tasks.contains_key("journal"));
        manager.enqueue(request("org.example.Two"));
        finish(&mut manager, "journal", json!({"ok":true}));
        manager.start_next();
        assert!(!manager.tasks.contains_key("install"));
        assert!(manager.tasks.contains_key("journal"));
        finish(&mut manager, "journal", json!({"ok":true}));
        manager.start_next();
        assert!(manager.tasks.contains_key("install"));
        assert_eq!(manager.jobs.len(), 2);
    }
    #[test]
    fn failed_and_timed_out_saves_pause_work_and_can_be_retried() {
        let mut manager = manager();
        finish(
            &mut manager,
            "recovery",
            json!({"ok":true,"records":[],"items":[]}),
        );
        manager.enqueue(request("org.example.One"));
        manager.initial();
        finish(
            &mut manager,
            "journal",
            json!({"ok":false,"error":"No space left"}),
        );
        manager.start_next();
        assert!(!manager.tasks.contains_key("install"));
        assert!(text(&manager.properties["recovery"], "error").contains("No space"));
        manager.dispatch("retryRecoveryIo", &json!([]));
        let serial = manager.tasks["journal"].serial;
        manager.dispatch("event", &json!([{"role":"journal","serial":serial,"kind":"finished","code":-1,"timedOut":true}]));
        assert!(!manager.queue_saved());
        assert!(!manager.tasks.contains_key("journal"));
        manager.dispatch("retryRecoveryIo", &json!([]));
        finish(&mut manager, "journal", json!({"ok":true}));
        manager.start_next();
        assert!(manager.tasks.contains_key("install"));
    }
    #[test]
    fn recovered_operations_are_not_replayed_and_dismissal_is_saved() {
        let mut manager = manager();
        let items = json!([
            {"recoveryId":"one","action":"update","id":"org.example.One","installation":"user","name":"One","state":"completed"},
            {"recoveryId":"two","action":"uninstall","id":"org.example.Two","installation":"user","name":"Two","state":"interrupted"}
        ]);
        finish(
            &mut manager,
            "recovery",
            json!({"ok":true,"records":items,"items":items}),
        );
        manager.start_next();
        assert!(manager.jobs.is_empty());
        assert!(!manager.tasks.contains_key("install"));
        assert!(!manager.tasks.contains_key("remove"));
        manager.dispatch("dismissRecovery", &json!([]));
        assert!(manager.tasks.contains_key("journal"));
        assert!(manager.recovery.records.is_empty());
    }
    #[test]
    fn damaged_journal_is_not_overwritten_by_new_jobs() {
        let mut manager = manager();
        finish(
            &mut manager,
            "recovery",
            json!({"ok":false,"error":"Damaged journal"}),
        );
        manager.enqueue(request("org.example.One"));
        manager.initial();
        assert!(!manager.tasks.contains_key("journal"));
        assert!(!manager.tasks.contains_key("install"));
        assert!(!manager.queue_saved());
    }
    #[test]
    fn rejecting_removal_rewrites_the_journal() {
        let mut manager = manager();
        finish(
            &mut manager,
            "recovery",
            json!({"ok":true,"records":[],"items":[]}),
        );
        let mut request = request("org.example.One");
        request["action"] = "uninstall".into();
        manager.enqueue(request);
        manager.initial();
        finish(&mut manager, "journal", json!({"ok":true}));
        let token = number(&manager.properties["review"], "token");
        manager.answer_review(token, false);
        manager.initial();
        assert!(manager.tasks.contains_key("journal"));
        assert!(!flag(&manager.jobs[0], "active"));
    }
}
