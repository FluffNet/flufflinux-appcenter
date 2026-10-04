use super::*;
impl Manager {
    pub(super) fn check_updates(&mut self) {
        if self.busy() || self.stopping {
            return;
        }
        self.merge("updates",json!({"state":"checking","items":[],"error":"","skipped":[],"status":"Checking for app updates…"}));
        self.update_sources_changed = false;
        self.worker(
            "updates",
            "--updates-worker",
            json!({"restoreSystemFlathub":true}),
            180000,
            16 * 1024 * 1024,
            true,
            json!({"result":false}),
        );
    }
    pub(super) fn cancel_updates(&mut self) {
        if self.properties["updates"]["state"] != "checking" {
            return;
        }
        self.merge("updates", json!({"state":"cancelled","items":[]}));
        self.transport("updates", "kill", json!({}));
    }
    pub(super) fn select_update(&mut self, key: Option<&str>, selected: bool) {
        if self.properties["updates"]["state"] != "ready" || self.busy() {
            return;
        }
        let mut items = rows(&self.properties["updates"]["items"]).to_vec();
        for row in &mut items {
            if key.is_none_or(|key| text(row, "key") == key) {
                row["selected"] = selected.into();
            }
        }
        self.merge("updates", json!({"items":items}));
    }
    pub(super) fn install_updates(&mut self) {
        if self.properties["updates"]["state"] != "ready" || self.busy() {
            return;
        }
        let selected: Vec<_> = rows(&self.properties["updates"]["items"])
            .iter()
            .filter(|row| flag(row, "selected"))
            .cloned()
            .collect();
        for mut row in selected {
            row["action"] = "update".into();
            self.enqueue(row);
        }
    }
    pub(super) fn update_message(&mut self, message: &Value) {
        if self.properties["updates"]["state"] != "checking" {
            return;
        }
        match text(message, "type") {
            "status" => self.merge("updates", json!({"status":message["message"]})),
            "sources" => {
                self.update_sources_changed = true;
                self.set("repositories", message["sources"].clone());
            }
            "updates" => {
                self.tasks.get_mut("updates").unwrap().context["result"] = true.into();
                let mut items = rows(&message["updates"]).to_vec();
                for row in &mut items {
                    row["icon"] = self.metadata(text(row, "id"))["icon"].clone();
                    row["selected"] = true.into();
                }
                items.sort_by(|a, b| {
                    flag(a, "runtime").cmp(&flag(b, "runtime")).then_with(|| {
                        glib::CollationKey::from(text(a, "name"))
                            .cmp(&glib::CollationKey::from(text(b, "name")))
                    })
                });
                let errors = rows(&message["errors"])
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join("\n");
                self.merge("updates",json!({"items":items,"error":errors,"skipped":message["skipped"],"lastChecked":date_label(text(message,"checkedAt"))}));
            }
            _ => {}
        }
    }
    pub(super) fn updates_finished(&mut self, result: bool, event: &Value) {
        // The result marker is captured before the transport removes its task.
        if self.properties["updates"]["state"] == "checking" {
            if success(event) && result {
                self.merge("updates", json!({"state":"ready"}));
            } else {
                self.merge("updates",json!({"state":"error","items":[],"error":if flag(event,"timedOut"){"Checking for app updates timed out. Try again."}else{"Could not finish checking for app updates. Try again."}}));
            }
        }
        if self.update_sources_changed {
            self.update_sources_changed = false;
            self.reload_catalog(false);
        }
    }
}
