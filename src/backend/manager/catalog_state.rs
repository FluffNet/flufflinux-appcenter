use super::*;
use crate::backend::catalog;
use std::{path::Path, time::Duration};
impl Manager {
    pub(super) fn set_catalog(&mut self, apps: Vec<Value>) {
        self.metadata = apps
            .iter()
            .map(|app| (normalized_id(text(app, "id")).to_owned(), app.clone()))
            .collect();
        self.set("catalog", apps.into());
        self.publish_jobs();
    }
    pub(super) fn catalog_progress(&mut self, progress: u64, reset: bool) {
        self.set(
            "catalogProgress",
            progress
                .min(100)
                .max(if reset {
                    0
                } else {
                    number(&self.properties, "catalogProgress")
                })
                .into(),
        );
    }
    pub(super) fn load_catalog(&mut self, path: &str) {
        self.catalog.path = path.into();
        self.catalog_progress(0, true);
        if path.is_empty() {
            self.reload_catalog(false);
            return;
        }
        let fingerprint = catalog::fingerprint().unwrap_or_default();
        let now = chrono::Utc::now();
        if let Some(cache) = storage::read_cache(Path::new(path), &fingerprint, now)
            .filter(|c| storage::fresh(c.saved_at, now))
        {
            self.catalog.refreshed = true;
            self.catalog.saved = cache.saved_at.to_rfc3339();
            self.catalog.fingerprint = fingerprint;
            self.set_catalog(cache.apps);
            self.catalog_progress(100, false);
            return;
        }
        self.set_catalog(vec![]);
        self.catalog.saved.clear();
        self.catalog.fingerprint.clear();
        self.catalog.refreshed = false;
        self.catalog.pending = true;
        self.start_catalog_refresh();
    }
    pub(super) fn start_catalog_refresh(&mut self) {
        if self.catalog.pending
            && self.catalog.network_ready
            && !self.catalog.offline
            && !self.busy()
            && !self.stopping
        {
            self.source_operation(json!({"operation":"refresh"}));
        }
    }
    pub(super) fn reload_catalog(&mut self, force: bool) {
        if self.stopping
            || self.catalog.awaiting
            || self.catalog.pending
            || (!self.catalog.path.is_empty() && !self.catalog.refreshed)
        {
            return;
        }
        if self.tasks.contains_key("catalog") {
            self.catalog.again = true;
            self.catalog.force_again |= force;
            return;
        }
        let mut args = json!(["--catalog"]);
        if !self.catalog.path.is_empty() {
            self.catalog.reading = catalog::fingerprint().unwrap_or_default();
            let fresh = chrono::DateTime::parse_from_rfc3339(&self.catalog.saved)
                .ok()
                .is_some_and(|date| {
                    storage::fresh(date.with_timezone(&chrono::Utc), chrono::Utc::now())
                });
            if !force
                && !self.catalog.reading.is_empty()
                && self.catalog.reading == self.catalog.fingerprint
                && fresh
            {
                return;
            }
            self.catalog.fingerprint.clear();
            args.as_array_mut().unwrap().push(
                json!({"path":self.catalog.path,"fingerprint":self.catalog.reading,
                "resetAge":self.catalog.reset_age,"savedAt":self.catalog.saved})
                .to_string()
                .into(),
            );
        }
        let reset = self.catalog.deadline.is_none();
        let deadline = *self
            .catalog
            .deadline
            .get_or_insert_with(|| Instant::now() + Duration::from_secs(30));
        let remaining = deadline
            .saturating_duration_since(Instant::now())
            .as_millis() as u64;
        if remaining == 0 {
            self.catalog.reset_age = false;
            self.catalog.again = false;
            self.catalog.force_again = false;
            self.catalog.deadline = None;
            self.catalog.failed = rows(&self.properties["catalog"]).is_empty();
            return;
        }
        self.catalog_progress(70, reset);
        self.start(
            "catalog",
            "@self",
            args,
            remaining,
            storage::CACHE_LIMIT,
            false,
            json!({}),
        );
    }
    pub(super) fn catalog_finished(&mut self, event: &Value) {
        if self.catalog.awaiting || self.catalog.pending {
            self.catalog.deadline = None;
            return;
        }
        let document: Value = serde_json::from_str(text(event, "stdout")).unwrap_or(Value::Null);
        let apps = if document.is_array() {
            document.as_array()
        } else {
            document["apps"].as_array()
        };
        let ok = success(event) && apps.is_some();
        if ok {
            self.set_catalog(apps.cloned().unwrap_or_default());
            if !self.catalog.path.is_empty() {
                let fingerprint = catalog::fingerprint().unwrap_or_default();
                if !fingerprint.is_empty() && fingerprint == self.catalog.reading {
                    self.catalog.fingerprint = fingerprint;
                    if self.catalog.reset_age {
                        self.catalog.saved = text(&document, "savedAt").into();
                    }
                    self.catalog.reset_age = false;
                } else if !fingerprint.is_empty() {
                    self.catalog.again = true;
                }
            }
            if !text(&self.size_app, "id").is_empty() {
                self.install_info(self.size_app.clone());
            }
            self.refresh_installed();
        } else {
            self.catalog.reset_age = false;
            self.catalog.failed = rows(&self.properties["catalog"]).is_empty();
            if flag(event, "timedOut") {
                self.catalog.again = false;
                self.catalog.force_again = false;
            }
        }
        if self.catalog.again {
            let force = self.catalog.force_again;
            self.catalog.again = false;
            self.catalog.force_again = false;
            self.reload_catalog(force);
        }
        if !self.tasks.contains_key("catalog") {
            self.catalog.deadline = None;
            if ok {
                self.catalog_progress(100, false);
            }
        }
    }
    pub(super) fn source_operation(&mut self, mut request: Value) {
        if self.stopping || self.busy() {
            return;
        }
        let operation = text(&request, "operation").to_owned();
        if operation == "refresh"
            && !self.catalog.path.is_empty()
            && (!self.catalog.network_ready || self.catalog.offline)
        {
            self.catalog.pending = true;
            return;
        }
        self.catalog.source_operation = operation.clone();
        if matches!(operation.as_str(), "refresh" | "initialize" | "defaults") {
            self.catalog_progress(0, true);
        }
        if operation == "refresh" && !self.catalog.path.is_empty() {
            self.catalog.pending = false;
            self.set_catalog(vec![]);
            self.catalog.fingerprint.clear();
            self.catalog.saved.clear();
            self.catalog.awaiting = true;
            self.catalog.reset_age = false;
            self.catalog.refreshed = false;
        }
        if operation != "list" {
            if self.properties["updates"]["state"] == "ready" {
                self.merge(
                    "updates",
                    json!({"state":"idle","items":[],"skipped":[],"error":""}),
                );
            }
            self.set("sourcesError", "".into());
            self.catalog.failed = false;
        }
        self.catalog.source_result = false;
        self.catalog.source_success = false;
        self.catalog.source_reported = false;
        self.catalog.source_refreshed = 0;
        request["action"] = "repositories".into();
        // Bound provisioning too, including an unresponsive authentication helper.
        self.worker(
            "sources",
            "--transaction-worker",
            request,
            180000,
            16 * 1024 * 1024,
            true,
            json!({}),
        );
    }
    pub(super) fn source_setting(&mut self, source: &Value, enabled: Option<bool>) {
        let known = rows(&self.properties["repositories"])
            .iter()
            .find(|known| !text(known, "id").is_empty() && known["id"] == source["id"])
            .cloned();
        let Some(known) = known else {
            return;
        };
        if let Some(enabled) = enabled {
            if let Some(member) = rows(&known["members"])
                .iter()
                .find(|m| m["scope"] == "user")
            {
                self.source_operation(json!({"operation":"enable","remote":member["name"],"url":member["url"],"sourceKey":member["sourceKey"],"enabled":enabled}));
            }
        } else {
            self.source_operation(json!({"operation":"remove","members":known["members"]}));
        }
    }
    pub(super) fn source_message(&mut self, message: &Value) {
        match text(message, "type") {
            "sources" => {
                if self.properties["repositories"] != message["sources"] {
                    if self.catalog.source_operation != "list" || self.catalog.path.is_empty() {
                        self.catalog.failed = false;
                    }
                    if self.properties["updates"]["state"] == "ready" {
                        self.merge(
                            "updates",
                            json!({"state":"idle","items":[],"skipped":[],"error":""}),
                        );
                    }
                }
                self.set("repositories", message["sources"].clone());
                if self.catalog.source_operation != "refresh" {
                    self.reload_catalog(false);
                }
            }
            "catalog-progress" => self.catalog_progress(number(message, "progress").min(70), false),
            "catalog-load" => {
                self.catalog.source_reported = true;
                self.catalog.source_refreshed = number(message, "refreshed");
                self.catalog.failed =
                    number(message, "available") == 0 && number(message, "failed") > 0;
            }
            "result" => {
                self.catalog.source_result = true;
                self.catalog.source_success = flag(message, "success");
                if self.catalog.source_operation != "list" || !flag(message, "success") {
                    self.set("sourcesError", text(message, "error").into());
                }
                self.transport("sources", "close", json!({}));
            }
            _ => {}
        }
    }
    pub(super) fn source_finished(&mut self, event: &Value) {
        if !self.catalog.source_result {
            self.set(
                "sourcesError",
                "Could not finish updating software sources.".into(),
            );
        }
        if self.catalog.awaiting {
            self.catalog.awaiting = false;
            let completed = !flag(event, "crashed")
                && text(event, "error").is_empty()
                && (event["code"] == 0 || event["code"] == 1)
                && self.catalog.source_reported
                && self.catalog.source_result;
            self.catalog.reset_age = completed && event["code"] == 0 && self.catalog.source_success;
            self.catalog.refreshed =
                self.catalog.reset_age || (completed && self.catalog.source_refreshed > 0);
            if self.catalog.refreshed {
                self.reload_catalog(true);
            } else {
                self.catalog.failed = true;
            }
        } else {
            self.reload_catalog(self.catalog.source_operation == "refresh");
        }
        for input in std::mem::take(&mut self.pending_inputs) {
            self.open_source(&input);
        }
    }
}
