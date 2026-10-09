use super::*;
impl Manager {
    pub(super) fn publish_jobs(&mut self) {
        let mut totals = HashMap::new();
        let mut positions = HashMap::new();
        let mut visible = vec![];
        for job in &self.jobs {
            if !job.is_null() && !flag(job, "cancelled") && !flag(job, "prepareOnly") {
                *totals.entry(number(job, "queueBatch")).or_insert(0u64) += 1;
            }
        }
        for item in &self.jobs {
            if item.is_null() || flag(item, "cancelled") || flag(item, "prepareOnly") {
                continue;
            }
            let mut job = item.clone();
            let batch = number(&job, "queueBatch");
            let position = positions.entry(batch).or_insert(0u64);
            *position += 1;
            job["queuePosition"] = (*position).into();
            job["queueTotal"] = totals[&batch].into();
            if flag(&job, "hidden") {
                continue;
            }
            if !flag(&job, "addon") {
                job["icon"] = self.metadata(text(&job, "id"))["icon"].clone();
            }
            visible.push(job);
        }
        self.set("jobs", visible.into());
        let status = self
            .jobs
            .iter()
            .find(|job| flag(job, "active") && flag(job, "prepareOnly"))
            .map(|job| {
                if flag(job, "queued") {
                    "Waiting to check software source…"
                } else if job["status"] == "Waiting for confirmation" {
                    "Waiting for source confirmation…"
                } else {
                    "Checking software source…"
                }
            })
            .unwrap_or("");
        self.set("sourceInputStatus", status.into());
    }
    fn patch_job(&mut self, index: usize, patch: Value) {
        if let Some(job) = self.jobs.get_mut(index) {
            merge(job, &patch);
            self.publish_jobs();
        }
    }
    pub(super) fn enqueue(&mut self, mut request: Value) {
        let id = normalized_id(text(&request, "id")).to_owned();
        if request["action"] != "update" {
            request["id"] = id.clone().into();
        }
        if self.jobs.iter().any(|job| {
            flag(job, "active")
                && ((!id.is_empty()
                    && normalized_id(text(job, "id")) == id
                    && (request["action"] != "update"
                        || job["action"] != "update"
                        || job["key"] == request["key"]))
                    || (id.is_empty() && job["source"] == request["source"]))
        }) {
            return;
        }
        if !flag(&request, "prepareOnly") {
            self.replace_recovered(&request);
            request["recoveryId"] = format!(
                "{}:{}:{}",
                std::process::id(),
                chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default(),
                self.jobs.len()
            )
            .into();
            if !self
                .jobs
                .iter()
                .any(|job| flag(job, "active") && !flag(job, "prepareOnly"))
            {
                self.batch += 1;
            }
            request["queueBatch"] = self.batch.into();
        }
        // Reuse released slots. Live indices remain stable for delegates,
        // worker replies and confirmation dialogs.
        let index = if flag(&request, "prepareOnly") {
            self.jobs
                .iter()
                .position(Value::is_null)
                .unwrap_or(self.jobs.len())
        } else {
            self.jobs.len()
        };
        let removing = request["action"] == "uninstall";
        merge(
            &mut request,
            &json!({"active":true,"failed":false,"progress":0,"queued":true,"status":"Queued","operations":[],"index":index}),
        );
        if removing {
            request["removalConfirmed"] = false.into();
        }
        if index == self.jobs.len() {
            self.requests.push(request.clone());
            self.jobs.push(request.clone());
        } else {
            self.requests[index] = request.clone();
            self.jobs[index] = request.clone();
        }
        self.publish_jobs();
        if !flag(&request, "prepareOnly") {
            self.queue_changed();
        }
        if removing {
            let name = text(&request, "name");
            let message = if flag(&request, "addon") {
                format!("Only {name} will be removed. The parent app and its data will be kept.")
            } else if request["installation"] != "user" {
                format!("If you proceed, {name} will be removed for all users, and its app data for this account will be deleted.")
            } else {
                format!("If you proceed, {name} and its app data will be removed.")
            };
            self.queue_review(json!({"localRemoval":true,"kind":"transaction","removing":true,"appId":id,"operations":[],"title":format!("Uninstall {name}?"),"message":message}),index);
        }
        self.start_next();
    }
    pub(super) fn start_next(&mut self) {
        if self.stopping {
            return;
        }
        for index in 0..self.jobs.len() {
            let job = &self.jobs[index];
            if !flag(job, "active") {
                continue;
            }
            if !flag(job, "prepareOnly") && !self.queue_saved() {
                continue;
            }
            let removing = job["action"] == "uninstall";
            if removing && !flag(job, "removalConfirmed") {
                continue;
            }
            let role = if removing { "remove" } else { "install" };
            if self.tasks.contains_key(role) {
                continue;
            }
            if !removing {
                self.rate = Default::default();
                self.clock = Instant::now();
                self.command(json!({"command":"timer","action":"downloadTick","interval":500}));
            }
            self.patch_job(index,json!({"queued":false,"status":if removing{"Uninstalling…"}else{"Preparing…"},"downloadSpeed":progress::DownloadRate::display(0.0)}));
            self.worker(
                role,
                "--transaction-worker",
                self.requests[index].clone(),
                0,
                16 * 1024 * 1024,
                true,
                json!({"index":index,"result":false}),
            );
        }
        if self.source_refresh_pending && !self.busy() {
            self.source_refresh_pending = false;
            self.source_operation(json!({"operation":"refresh"}));
        }
    }
    fn queue_review(&mut self, mut review: Value, index: usize) {
        self.review_token += 1;
        review["workerToken"] = review["token"].clone();
        review["token"] = self.review_token.into();
        review["jobIndex"] = index.into();
        self.reviews.push_back(review);
        self.show_review();
    }
    pub(super) fn show_review(&mut self) {
        if self.stopping
            || self.properties["review"]
                .as_object()
                .is_some_and(|map| !map.is_empty())
        {
            return;
        }
        while let Some(review) = self.reviews.pop_front() {
            if self
                .jobs
                .get(number(&review, "jobIndex") as usize)
                .is_some_and(|job| flag(job, "active"))
            {
                self.set("review", review);
                return;
            }
        }
    }
    fn clear_reviews(&mut self, index: usize) {
        self.reviews
            .retain(|review| number(review, "jobIndex") as usize != index);
        if self.properties["review"].get("jobIndex").is_some()
            && number(&self.properties["review"], "jobIndex") as usize == index
        {
            self.set("review", json!({}));
        }
        self.defer("showNextReview");
    }
    fn job_role(&self, index: usize) -> Option<&'static str> {
        ["install", "remove"].into_iter().find(|role| {
            self.tasks
                .get(*role)
                .is_some_and(|task| number(&task.context, "index") as usize == index)
        })
    }
    pub(super) fn answer_review(&mut self, token: u64, accept: bool) {
        let review = self.properties["review"].clone();
        if token == 0 || number(&review, "token") != token {
            return;
        }
        let index = number(&review, "jobIndex") as usize;
        if index >= self.jobs.len() {
            return;
        }
        self.clear_reviews(index);
        if flag(&review, "localRemoval") {
            if accept {
                self.requests[index]["removalConfirmed"] = true.into();
                self.patch_job(index, json!({"removalConfirmed":true,"status":"Pending…"}));
                self.start_next();
            } else {
                self.patch_job(
                    index,
                    json!({"active":false,"queued":false,"cancelled":true,"status":""}),
                );
                self.queue_changed();
            }
            return;
        }
        if let Some(role) = self.job_role(index) {
            let mut patch = json!({"status":if accept{"Working…"}else{"Cancelling…"}});
            if flag(&review, "removing") {
                patch["removalConfirmed"] = accept.into();
            }
            self.patch_job(index, patch);
            self.transport(role,"write",json!({"data":format!("{}\n",json!({"token":review["workerToken"],"accept":accept}))}));
        }
    }
    pub(super) fn cancel_job(&mut self, index: usize) {
        if !self.jobs.get(index).is_some_and(|job| flag(job, "active")) {
            return;
        }
        let running = self.job_role(index);
        if let Some(role) = running {
            if role == "install" {
                self.command(json!({"command":"timer","action":"downloadTick","interval":0}));
            }
            self.transport(role, "write", json!({"data":"{\"cancel\":true}\n"}));
            self.transport(role, "close", json!({}));
            self.transport(role, "deadline", json!({"timeout":250}));
        }
        self.patch_job(index,json!({"active":false,"queued":false,"cancelled":true,"status":"","cancelling":running.is_some()}));
        self.clear_reviews(index);
        if !flag(&self.jobs[index], "prepareOnly") {
            self.queue_changed();
        }
    }
    pub(super) fn cancel_all(&mut self) {
        self.cancel_updates();
        self.pending_inputs.clear();
        for index in 0..self.jobs.len() {
            self.cancel_job(index);
        }
        self.transport("sources", "write", json!({"data":"{\"cancel\":true}\n"}));
        self.transport("sources", "close", json!({}));
        self.transport("sources", "deadline", json!({"timeout":1000}));
    }
    fn rate_values(&mut self, job: &Value) -> Value {
        let rate = self.rate.sample(
            self.clock.elapsed().as_millis() as u64,
            number(job, "receivedBytes"),
            job["phase"] == "download" && !flag(job, "downloadComplete"),
        );
        json!({"downloadSpeed":progress::DownloadRate::display(rate),"downloadSpeedBytes":rate})
    }
    pub(super) fn download_tick(&mut self) {
        if let Some(task) = self.tasks.get("install") {
            if flag(&task.context, "result") {
                return;
            }
            let index = number(&task.context, "index") as usize;
            let job = self.jobs[index].clone();
            let patch = self.rate_values(&job);
            if job["downloadSpeed"] != patch["downloadSpeed"] {
                self.patch_job(index, patch);
            }
        }
    }
    pub(super) fn job_message(&mut self, role: &str, message: &Value) {
        let Some(task) = self.tasks.get(role) else {
            return;
        };
        let index = number(&task.context, "index") as usize;
        if flag(&self.jobs[index], "cancelling")
            && !matches!(text(message, "type"), "result" | "updated")
        {
            return;
        }
        match text(message, "type") {
            "updated" => {
                if !flag(message, "historySaved") {
                    self.error("The app updated, but its last-update date could not be saved.");
                }
                self.refresh_installed();
            }
            "review" => {
                let mut patch = json!({"status":"Waiting for confirmation"});
                if !rows(&message["operations"]).is_empty() {
                    patch["operations"] = message["operations"].clone();
                }
                self.patch_job(index, patch);
                self.queue_review(message.clone(), index);
            }
            "identity" => {
                let id = text(message, "appId");
                if !id.is_empty() && !flag(&self.jobs[index], "addon") {
                    self.patch_job(index, json!({"id":id,"name":self.metadata(id)["name"]}));
                }
            }
            "plan" => {
                let operations = rows(&message["operations"]);
                let mut patch = progress::stages(operations, "preparing");
                patch["operations"] = message["operations"].clone();
                self.patch_job(index, patch);
                if !flag(&self.jobs[index], "prepareOnly") {
                    self.queue_changed();
                }
                let id = text(message, "appId");
                let request = self.requests[index].clone();
                if flag(&request, "prepareOnly") && !id.is_empty() {
                    let mut prepared = request.clone();
                    for op in operations {
                        if text(op, "ref").starts_with("app/") {
                            prepared["flatpakRef"] = op["ref"].clone();
                            prepared["remote"] = op["remote"].clone();
                        }
                    }
                    let mut app = if normalized_id(text(&message["app"], "id")) == id {
                        // A skipped operation (already installed) is absent from
                        // the download plan but still has resolved preview identity.
                        prepared["flatpakRef"] = message["app"]["flatpakRef"].clone();
                        prepared["remote"] = message["app"]["remote"].clone();
                        message["app"].clone()
                    } else {
                        self.metadata(id)
                    };
                    prepared["sourceUrl"] = app["sourceUrl"].clone();
                    prepared["previewPermissions"] = message["permissions"].clone();
                    let mut sizes = json!({});
                    for key in [
                        "state",
                        "appBytes",
                        "appSize",
                        "totalBytes",
                        "totalSize",
                        "sizeError",
                    ] {
                        if let Some(value) = message.get(key) {
                            sizes[key] = value.clone();
                        }
                    }
                    prepared["previewSizes"] = sizes;
                    app["localSource"] = request["source"].clone();
                    // A preview is not an installed app. Keep installation scope
                    // in the request only, or permissions would query flatpak info.
                    app.as_object_mut().unwrap().remove("installation");
                    app["flatpakRef"] = prepared["flatpakRef"].clone();
                    app["remote"] = prepared["remote"].clone();
                    self.sources.insert(id.into(), prepared);
                    self.signal("appOpened", json!([app]));
                }
                if request["action"] != "uninstall"
                    && id == normalized_id(text(&self.size_app, "id"))
                {
                    self.set("installSizes", json!({id:message}));
                }
            }
            "operation" => {
                let job = self.jobs[index].clone();
                let mut operations = rows(&job["operations"]).to_vec();
                let mut status = text(message, "status").to_owned();
                for op in &mut operations {
                    if op["ref"] == message["ref"] {
                        for key in ["status", "progress", "phase", "estimating"] {
                            op[key] = message[key].clone();
                        }
                        for key in ["downloadProgress", "receivedBytes"] {
                            op[key] = op[key]
                                .as_f64()
                                .unwrap_or(0.0)
                                .max(message[key].as_f64().unwrap_or(0.0))
                                .into();
                        }
                        if job["action"] != "uninstall" && flag(op, "dependency") {
                            status = format!("Dependency: {}\n{status}", text(op, "name"));
                        }
                    }
                }
                let mut patch = progress::stages(&operations, text(message, "phase"));
                if role == "install" {
                    let rate = self.rate_values(&patch);
                    merge(&mut patch, &rate);
                }
                patch["operations"] = operations.into();
                patch["progress"] = job["progress"]
                    .as_f64()
                    .unwrap_or(0.0)
                    .max(patch["progress"].as_f64().unwrap_or(0.0))
                    .into();
                patch["status"] = if job["action"] == "uninstall" {
                    "Uninstalling…".into()
                } else {
                    status.into()
                };
                patch["currentRef"] = message["ref"].clone();
                self.patch_job(index, patch);
            }
            "status" => self.patch_job(index, json!({"status":message["status"]})),
            "result" => self.job_result(role, index, message),
            _ => {}
        }
    }
    fn job_result(&mut self, role: &str, index: usize, message: &Value) {
        self.tasks.get_mut(role).unwrap().context["result"] = true.into();
        self.transport(role, "close", json!({}));
        self.transport(role, "deadline", json!({"timeout":3000}));
        if role == "install" {
            self.command(json!({"command":"timer","action":"downloadTick","interval":0}));
        }
        let job = self.jobs[index].clone();
        let ok = flag(message, "success");
        let cancelled = flag(message, "cancelled") || flag(&job, "cancelling");
        let preparation = flag(&self.requests[index], "prepareOnly");
        if ok && flag(message, "sourcesChanged") {
            self.source_refresh_pending = true;
        }
        if ok && !preparation {
            for op in rows(&job["operations"]) {
                let reference = text(op, "ref");
                if !reference.starts_with("app/") {
                    continue;
                }
                let (scope, date) = if job["action"] == "uninstall" {
                    (text(&job, "installation"), None)
                } else if matches!(text(op, "action"), "install" | "install-bundle") {
                    ("user", Some(chrono::Utc::now().to_rfc3339()))
                } else {
                    continue;
                };
                if let Err(error) = storage::history_save(
                    &storage::data_dir().join("installation-dates.json"),
                    scope,
                    reference,
                    date.as_deref(),
                ) {
                    eprintln!("Could not save installation date: {error}");
                }
                if job["action"] == "uninstall" {
                    let _ = storage::history_save(
                        &storage::data_dir().join("update-dates.json"),
                        scope,
                        reference,
                        None,
                    );
                }
            }
        }
        if preparation && !ok && !cancelled {
            self.error(text(message, "error"));
        }
        if ok && job["action"] == "update" {
            let items: Vec<_> = rows(&self.properties["updates"]["items"])
                .iter()
                .filter(|row| row["key"] != self.requests[index]["key"])
                .cloned()
                .collect();
            self.merge("updates", json!({"items":items}));
        }
        let removing = job["action"] == "uninstall";
        if ok && removing {
            self.apply_removal(&job);
        }
        self.patch_job(index,json!({"active":false,"queued":false,"failed":!ok&&!cancelled,"cancelled":cancelled,
            "progress":if ok{json!(1)}else{job["progress"].clone()},"status":if ok{if removing{""}else{"Complete"}}else if cancelled{"Cancelled"}else{"Failed"},"error":text(message,"error")}));
        self.clear_reviews(index);
        if !preparation {
            self.queue_changed();
        }
    }
    fn apply_removal(&mut self, removed: &Value) {
        let id = normalized_id(text(removed, "id"));
        let reference = format!(
            "{}/{}/{}/{}",
            if flag(removed, "addon") {
                "runtime"
            } else {
                "app"
            },
            id,
            text(removed, "installedArch"),
            text(removed, "installedBranch")
        );
        for job in &mut self.jobs {
            if flag(job, "active")
                || job["action"] == "uninstall"
                || normalized_id(text(job, "id")) != id
                || job["installation"] != removed["installation"]
            {
                continue;
            }
            let mut old_ref = text(job, "flatpakRef").to_owned();
            if old_ref.is_empty() {
                old_ref = rows(&job["operations"])
                    .iter()
                    .find(|op| text(op, "ref").starts_with(&format!("app/{id}/")))
                    .map(|op| text(op, "ref").to_owned())
                    .unwrap_or_default();
            }
            if old_ref.is_empty() || old_ref == reference {
                job["hidden"] = true.into();
            }
        }
        self.installed_revision += 1;
        let apps: Vec<_> = rows(&self.properties["installedApps"])
            .iter()
            .filter(|app| {
                !(normalized_id(text(app, "id")) == id
                    && ["installation", "installedArch", "installedBranch"]
                        .iter()
                        .all(|key| app[*key] == removed[*key]))
            })
            .cloned()
            .collect();
        self.set("installedApps", apps.into());
        self.update_date();
    }
    pub(super) fn job_finished(&mut self, role: &str, context: Value, event: &Value) {
        let index = number(&context, "index") as usize;
        if role == "install" {
            self.command(json!({"command":"timer","action":"downloadTick","interval":0}));
        }
        let preparation = flag(&self.requests[index], "prepareOnly");
        if !flag(&context, "result") {
            let cancelled = flag(&self.jobs[index], "cancelling");
            self.patch_job(index,json!({"active":false,"queued":false,"failed":!cancelled,"cancelled":cancelled,
                "status":if cancelled{""}else{"The Flatpak worker stopped unexpectedly"},"error":if cancelled{""}else{text(event,"stderr")}}));
            if preparation && !cancelled && !self.stopping {
                self.error(format!(
                    "The Flatpak worker stopped unexpectedly\n{}",
                    text(event, "stderr")
                ));
            }
            if !preparation {
                self.queue_changed();
            }
        }
        self.clear_reviews(index);
        self.requests[index] = Value::Null;
        self.release_finished_jobs();
        if !preparation && !self.stopping {
            if !text(&self.size_app, "id").is_empty() {
                self.install_info(self.size_app.clone());
            }
            self.refresh_desktop_caches();
            self.reload_catalog(false);
        }
    }
    pub(super) fn release_finished_jobs(&mut self) {
        let active_batches: std::collections::HashSet<_> = self
            .jobs
            .iter()
            .filter(|job| flag(job, "active") && !flag(job, "prepareOnly"))
            .map(|job| number(job, "queueBatch"))
            .collect();
        for index in 0..self.jobs.len() {
            let job = &self.jobs[index];
            if !flag(job, "active")
                && (flag(job, "prepareOnly") || flag(job, "hidden"))
                && self.job_role(index).is_none()
            {
                // Cleared history still contributes to a running batch's
                // 2/5 position. Keep only that accounting until it finishes.
                self.jobs[index] = if !flag(job, "prepareOnly")
                    && active_batches.contains(&number(job, "queueBatch"))
                {
                    json!({"index":index,"queueBatch":job["queueBatch"],"hidden":true,"cancelled":flag(job,"cancelled")})
                } else {
                    Value::Null
                };
                self.requests[index] = Value::Null;
            }
        }
        while self.jobs.last().is_some_and(Value::is_null) {
            self.jobs.pop();
            self.requests.pop();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::permissions;
    fn request(id: &str) -> Value {
        json!({"id":id,"action":"install","name":id,"installation":"user"})
    }
    #[test]
    fn finished_previews_release_slots_without_losing_current_preview_details() {
        let mut manager = Manager::new(vec![]);
        for _ in 0..1000 {
            manager.enqueue(json!({"action":"source","source":"file:///tmp/example.flatpakref","installation":"user","prepareOnly":true,"hidden":true}));
            let serial = manager.tasks["install"].serial;
            manager.dispatch("event", &json!([{"role":"install","serial":serial,"kind":"line","line":json!({"type":"result","success":true}).to_string()}]));
            manager.dispatch(
                "event",
                &json!([{"role":"install","serial":serial,"kind":"finished","code":0}]),
            );
            assert!(manager.jobs.is_empty());
            assert!(manager.requests.is_empty());
        }
    }
    #[test]
    fn clearing_history_preserves_live_indices_and_releases_finished_payloads() {
        let mut manager = Manager::new(vec![]);
        manager.enqueue(request("a.b.First"));
        manager.enqueue(request("a.b.Second"));
        manager.jobs[1]["active"] = false.into();
        manager.dispatch("clearDownloadHistory", &json!([]));
        assert_eq!(manager.jobs.len(), 2);
        assert!(manager.jobs[1].get("id").is_none());
        assert!(manager.requests[1].is_null());
        assert_eq!(number(&manager.tasks["install"].context, "index"), 0);
        assert!(flag(&manager.jobs[0], "active"));
        manager.enqueue(request("a.b.Third"));
        assert_eq!(manager.jobs[2]["id"], "a.b.Third");
        assert_eq!(manager.properties["jobs"][1]["queuePosition"], 3);
        assert_eq!(manager.properties["jobs"][0]["queueTotal"], 3);
        manager.jobs[0]["active"] = false.into();
        manager.jobs[2]["active"] = false.into();
        manager.tasks.clear();
        manager.dispatch("clearDownloadHistory", &json!([]));
        assert!(manager.jobs.is_empty());
    }
    #[test]
    fn local_preview_keeps_details_permissions_and_source_without_hijacking_catalog_installs() {
        let catalog = json!({"id":"a.b.App","name":"Catalog app","remote":"catalog",
            "flatpakRef":"app/a.b.App/x86_64/stable","sourceUrl":"https://catalog.example/repo/"});
        let mut manager = Manager::new(vec![catalog.clone()]);
        manager.enqueue(
            json!({"action":"source","source":"file:///tmp/local.flatpakref",
            "prepareOnly":true,"hidden":true,"installation":"user"}),
        );
        let preview = json!({"id":"a.b.App","name":"Local app","description":"Source details",
            "screenshots":["https://local.example/image.png"],"remote":"local",
            "flatpakRef":"app/a.b.App/x86_64/beta","sourceUrl":"https://local.example/repo/"});
        let permissions = permissions::parse(
            b"[Application]\nname=a.b.App\n[Context]\nshared=network;\n",
            false,
        );
        manager.job_message("install", &json!({"type":"plan","appId":"a.b.App","app":preview,
            "state":"ready","appBytes":12345,"appSize":"12.06 KiB","totalBytes":23456,"totalSize":"22.91 KiB",
            "permissions":permissions,"operations":[{"ref":"app/a.b.App/x86_64/beta","remote":"local"}]}));
        let opened = manager
            .signals
            .iter()
            .find(|s| s["name"] == "appOpened")
            .unwrap()["args"][0]
            .clone();
        assert_eq!(opened["description"], "Source details");
        assert_eq!(opened["screenshots"], preview["screenshots"]);
        assert!(opened.get("installation").is_none());
        let request = manager.install_request(&opened).unwrap();
        assert_eq!(request["sourceUrl"], preview["sourceUrl"]);
        assert_eq!(request["source"], "file:///tmp/local.flatpakref");
        assert_eq!(request["sourceReviewed"], true);
        assert_eq!(request["previewSizes"]["appBytes"], 12345);
        manager.install_info(opened.clone());
        assert_eq!(
            manager.properties["installSizes"]["a.b.App"]["totalBytes"],
            23456
        );
        assert_eq!(
            manager.properties["installSizes"]["a.b.App"]["state"],
            "ready"
        );
        manager.job_message(
            "install",
            &json!({"type":"result","success":true,"sourcesChanged":false}),
        );
        assert!(
            !manager.source_refresh_pending,
            "A preview must not provision or refresh the real sources"
        );
        manager.request_permissions(opened.clone());
        assert_eq!(manager.properties["appPermissions"], permissions);
        assert!(
            !manager.tasks.contains_key("permissions"),
            "Reuse resolved permissions without another fetch"
        );
        let catalog_request = manager.install_request(&catalog).unwrap();
        assert_eq!(catalog_request["action"], "install");
        assert_eq!(catalog_request["remote"], "catalog");
        let mut changed = opened;
        changed["localSource"] = "file:///tmp/replaced.flatpakref".into();
        assert!(manager.install_request(&changed).is_none());
    }
    #[test]
    fn adding_to_running_batch_changes_every_total() {
        let mut manager = Manager::new(vec![]);
        for id in ["a.b.One", "a.b.Two", "a.b.Three"] {
            manager.enqueue(request(id));
        }
        assert_eq!(manager.properties["jobs"][0]["queueTotal"], 3);
        assert_eq!(manager.properties["jobs"][2]["queuePosition"], 3);
        assert_eq!(manager.tasks.len(), 1);
    }
    #[test]
    fn cancellation_cannot_be_resurrected_by_buffered_progress() {
        let mut manager = Manager::new(vec![]);
        manager.enqueue(request("a.b.One"));
        manager.cancel_job(0);
        manager.job_message("install", &json!({"type":"status","status":"Downloading"}));
        assert_eq!(manager.properties["jobs"], json!([]));
        assert!(!flag(&manager.jobs[0], "active"));
    }
    #[test]
    fn removal_waits_for_its_own_consent() {
        let mut manager = Manager::new(vec![]);
        let mut request = request("a.b.One");
        request["action"] = "uninstall".into();
        manager.enqueue(request);
        assert!(!manager.tasks.contains_key("remove"));
        let token = number(&manager.properties["review"], "token");
        manager.answer_review(token + 1, true);
        assert!(!manager.tasks.contains_key("remove"));
        manager.answer_review(token, true);
        assert!(manager.tasks.contains_key("remove"));
    }
}
