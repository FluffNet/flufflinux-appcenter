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
            self.enqueue_request(row);
        }
        self.publish_jobs();
        self.start_next();
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repeated_large_batches_release_requests_tasks_and_cleared_history() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        for batch in 0..5 {
            let items: Vec<_> = (0..200)
                .map(|index| {
                    json!({
                        "id":format!("org.example.App{index}"),"key":format!("user:{index}"),
                        "installation":"user","selected":true,
                        "plan":[{"ref":format!("app/org.example.App{index}/x86_64/stable"),
                            "commit":"a".repeat(64),"downloadBytes":1000}]
                    })
                })
                .collect();
            manager.properties["updates"] = json!({"state":"ready","items":items});
            manager.dispatch("installSelectedUpdates", &json!([]));
            // Desktop subprocesses are simulated, never run by this state test.
            manager.tasks.insert("desktop".into(), Task::default());
            for index in 0..200 {
                let serial = manager.tasks["install"].serial;
                for progress in [0.1, 0.5, 0.9] {
                    let line = json!({"type":"operation","ref":format!("app/org.example.App{index}/x86_64/stable"),
                        "progress":progress,"phase":"download","downloadProgress":progress,"receivedBytes":500}).to_string();
                    manager.dispatch(
                        "event",
                        &json!([{"kind":"line","role":"install","serial":serial,"line":line}]),
                    );
                }
                let result = match index % 4 {
                    0 => json!({"type":"result","success":true}),
                    1 => json!({"type":"result","success":false,"cancelled":true}),
                    _ => json!({"type":"result","success":false,"error":"fixture failure"}),
                };
                // Every fourth job simulates an abrupt worker death, no result.
                if index % 4 != 3 {
                    manager.dispatch("event", &json!([{"kind":"line","role":"install","serial":serial,"line":result.to_string()}]));
                }
                manager.dispatch(
                    "event",
                    &json!([{"kind":"finished","role":"install","serial":serial,"code":1}]),
                );
                manager.dispatch("startNext", &json!([]));
                assert!(manager.requests[index].is_null());
                assert!(
                    manager.tasks.len() <= 2,
                    "worker tasks grew in batch {batch}"
                );
            }
            assert!(!manager.jobs.iter().any(|job| flag(job, "active")));
            manager.dispatch("clearDownloadHistory", &json!([]));
            assert!(manager.jobs.is_empty() && manager.requests.is_empty());
            assert!(rows(&manager.properties["jobs"]).is_empty());
            assert!(manager.reviews.is_empty());
            manager.tasks.clear();
            manager.desktop_again = false;
        }
    }

    #[test]
    fn catalog_rebuild_waits_for_the_whole_queue_including_new_items_and_worker_exit() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        manager.catalog_after_queue = true;
        manager.jobs = vec![json!({"active":true})];
        manager.refresh_after_queue();
        assert!(!manager.tasks.contains_key("catalog"));
        manager.jobs.push(json!({"active":true}));
        manager.jobs[0]["active"] = false.into();
        manager.refresh_after_queue();
        assert!(!manager.tasks.contains_key("catalog"));
        manager.jobs[1]["active"] = false.into();
        manager.tasks.insert("install".into(), Task::default());
        manager.refresh_after_queue();
        assert!(!manager.tasks.contains_key("catalog"));
        manager.tasks.remove("install");
        manager.refresh_after_queue();
        assert!(manager.tasks.contains_key("catalog"));
        assert!(!manager.catalog_after_queue);
        let serial = manager.serial;
        manager.refresh_after_queue();
        assert_eq!(manager.serial, serial);
    }

    #[test]
    fn two_hundred_updates_publish_one_complete_batch_and_start_one_worker() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        let plan: Vec<_> = (0..12)
            .map(|index| {
                json!({
                    "ref":format!("runtime/org.example.Runtime{index}/x86_64/stable"),
                    "commit":"0123456789abcdef".repeat(4), "downloadBytes":100_000_000
                })
            })
            .collect();
        let items: Vec<_> = (0..200)
            .map(|index| {
                json!({
                    "id":format!("org.example.App{index}"), "key":format!("user:{index}"),
                    "installation":"user", "selected":true, "plan":plan
                })
            })
            .collect();
        manager.properties["updates"] = json!({"state":"ready","items":items});
        let start = Instant::now();
        let reply = manager.dispatch("installSelectedUpdates", &json!([]));
        eprintln!("QUEUE_BATCH 200 updates: {:?}", start.elapsed());
        assert_eq!(rows(&reply["state"]["jobs"]).len(), 200);
        assert_eq!(manager.requests.len(), 200);
        assert_eq!(manager.jobs.len(), 200);
        for (index, job) in rows(&reply["state"]["jobs"]).iter().enumerate() {
            assert_eq!(number(job, "queuePosition"), index as u64 + 1);
            assert_eq!(number(job, "queueTotal"), 200);
            assert_eq!(flag(job, "queued"), index != 0);
        }
        assert_eq!(
            rows(&reply["commands"])
                .iter()
                .filter(|command| command["command"] == "start" && command["role"] == "install")
                .count(),
            1
        );
        // A second click while busy cannot enqueue the same selection again.
        manager.dispatch("installSelectedUpdates", &json!([]));
        assert_eq!(manager.jobs.len(), 200);
    }
}
