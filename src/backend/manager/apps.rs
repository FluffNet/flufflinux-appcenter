use super::*;
use crate::backend::{addons, permissions, sizes, sources};
use std::os::unix::fs::MetadataExt;

fn installed_columns(line: &str, line_number: usize) -> Result<[&str; 9], String> {
    let mut columns: Vec<_> = line.split('\t').map(str::trim).collect();
    // Flatpak's table printer trims trailing whitespace, including separators
    // for an absent version and summary. Neither optional field is required
    // to identify an installed app. Do not pad missing identity fields.
    if !(7..=9).contains(&columns.len()) {
        let entry: String = columns[0]
            .chars()
            .filter(|c| !c.is_control())
            .take(120)
            .collect();
        return Err(format!(
            "App Center could not read the installed-app list: line {line_number} has {} fields; expected 7-9. Entry: {entry}\nThis is a list-reading error, not an update failure. No apps were removed by this check. Run flatpak list --app to inspect the installed apps.",
            columns.len()
        ));
    }
    columns.resize(9, "");
    Ok(columns.try_into().unwrap())
}

impl Manager {
    pub(super) fn install_request(&self, app: &Value) -> Option<Value> {
        let id = normalized_id(text(app, "id"));
        if !text(app, "localSource").is_empty() {
            let source = self.sources.get(id).filter(|source| {
                source["source"] == app["localSource"]
                    && source["flatpakRef"] == app["flatpakRef"]
                    && source["sourceUrl"] == app["sourceUrl"]
            })?;
            let mut request = source.clone();
            merge(
                &mut request,
                &json!({"prepareOnly":false,"hidden":false,"id":id,"name":app["name"],"sourceReviewed":true}),
            );
            return Some(request);
        }
        let catalog = self.catalog_app(id).unwrap_or(app);
        let variants = rows(&catalog["sources"]);
        let chosen = if variants.is_empty() {
            catalog
        } else {
            variants.iter().find(|candidate| {
                ["remote", "flatpakRef", "sourceUrl"]
                    .iter()
                    .all(|key| candidate[*key] == app[*key])
            })?
        };
        Some(
            json!({"action":"install","id":id,"name":app["name"],"installation":"user","flatpakRef":chosen["flatpakRef"],"remote":chosen["remote"],"sourceUrl":chosen["sourceUrl"]}),
        )
    }
    pub(super) fn install_info(&mut self, app: Value) {
        if self.stopping || text(&app, "id").is_empty() {
            return;
        }
        let id = normalized_id(text(&app, "id")).to_owned();
        self.size_app = app.clone();
        self.cancel_reader("sizes");
        if rows(&self.properties["installedApps"])
            .iter()
            .any(|installed| normalized_id(text(installed, "id")) == id)
        {
            // Installed pages display deployment size, not a new-install estimate.
            // Keep size_app so removal completion can calculate it when needed.
            self.set("installSizes", json!({}));
            return;
        }
        let Some(request) = self.install_request(&app) else {
            self.set("installSizes", json!({id:{"state":"unavailable"}}));
            return;
        };
        let preview = request["previewSizes"].clone();
        // A complete disposable local-file preview already resolved dependencies.
        if preview["state"] == "ready" {
            self.set("installSizes", json!({id:preview}));
            return;
        }
        self.set("installSizes", json!({id.as_str():{"state":"loading"}}));
        // Remote-ref enumeration can allocate a whole repository's metadata.
        // Keep it out of the GUI process and bound its lifetime and output.
        self.worker(
            "sizes",
            "--sizes-worker",
            request,
            30000,
            64 * 1024,
            false,
            json!({"id":id,"preview":preview}),
        );
    }
    pub(super) fn sizes_finished(&mut self, context: Value, event: &Value) {
        let mut result: Value = if success(event) && !flag(event, "timedOut") {
            serde_json::from_str(text(event, "stdout")).unwrap_or(Value::Null)
        } else {
            Value::Null
        };
        if !matches!(text(&result, "state"), "ready" | "partial") {
            result = if context["preview"]["appBytes"].is_u64() {
                context["preview"].clone()
            } else {
                json!({"state":"unavailable"})
            };
        }
        self.set("installSizes", json!({text(&context,"id"):result}));
    }
    fn installed_match(&self, app: &Value) -> Option<Value> {
        rows(&self.properties["installedApps"])
            .iter()
            .find(|installed| {
                normalized_id(text(installed, "id")) == normalized_id(text(app, "id"))
                    && ["installation", "installedArch", "installedBranch"]
                        .iter()
                        .all(|key| installed[*key] == app[*key])
            })
            .cloned()
    }
    pub(super) fn install_app(&mut self, app: &Value) {
        if self.tasks.contains_key("sources") {
            self.error("Please wait for software sources to finish updating.");
            return;
        }
        let id = normalized_id(text(app, "id"));
        if id.is_empty()
            || rows(&self.properties["installedApps"])
                .iter()
                .any(|app| normalized_id(text(app, "id")) == id)
        {
            return;
        }
        if let Some(request) = self.install_request(app) {
            self.enqueue(request);
        } else {
            self.error(
                "This app's source has changed. Reopen the app and choose its source again.",
            );
        }
    }
    pub(super) fn uninstall_app(&mut self, app: &Value) {
        if self.tasks.contains_key("sources") {
            self.error("Please wait for software sources to finish updating.");
            return;
        }
        if let Some(installed) = self.installed_match(app) {
            self.enqueue(json!({"action":"uninstall","id":installed["id"],"name":installed["name"],"installation":installed["installation"],"installedBranch":installed["installedBranch"],"installedArch":installed["installedArch"]}));
        } else {
            self.error("That app is no longer installed. The list has been refreshed.");
            self.refresh_installed();
        }
    }
    pub(super) fn launch_app(&mut self, app: &Value) {
        let installed = rows(&self.properties["installedApps"])
            .iter()
            .find(|installed| {
                normalized_id(text(installed, "id")) == normalized_id(text(app, "id"))
                    && (app.get("installation").is_none()
                        || ["installation", "installedBranch", "installedArch"]
                            .iter()
                            .all(|key| installed[*key] == app[*key]))
            })
            .cloned();
        if let Some(installed) = installed {
            self.command(json!({"command":"launch","program":"/usr/bin/flatpak","args":["run",scope_arg(text(&installed,"installation")),
            format!("--branch={}",text(&installed,"installedBranch")),format!("--arch={}",text(&installed,"installedArch")),normalized_id(text(&installed,"id"))]}));
        }
    }
    pub(super) fn refresh_installed(&mut self) {
        if self.stopping {
            return;
        }
        if self.tasks.contains_key("installed") {
            self.installed_again = true;
            return;
        }
        self.set("installedLoading", true.into());
        self.set("installedError", "".into());
        self.start("installed","flatpak",json!(["list","--app","--columns=application:f,name:f,size,origin:f,installation:f,branch:f,arch:f,description:f,version:f"]),15000,16*1024*1024,false,json!({"revision":self.installed_revision}));
    }
    pub(super) fn installed_finished(&mut self, context: Value, event: &Value) {
        let stale = number(&context, "revision") != self.installed_revision;
        if self.installed_again || stale {
            self.installed_again = false;
            self.defer("refreshInstalled");
        }
        if stale {
            return;
        }
        self.set("installedLoading", false.into());
        if !success(event) {
            self.set(
                "installedError",
                if flag(event, "timedOut") {
                    json!("Reading installed Flatpaks timed out.")
                } else {
                    json!(format!(
                        "Could not read installed Flatpaks: {}",
                        text(event, "stderr")
                    ))
                },
            );
            return;
        }
        let mut apps = vec![];
        // Read each date file once, not once per installed application.
        let history = storage::read_json(
            &storage::data_dir().join("installation-dates.json"),
            4 * 1024 * 1024,
        )
        .unwrap_or(Value::Null);
        let updates = storage::read_json(
            &storage::data_dir().join("update-dates.json"),
            4 * 1024 * 1024,
        )
        .unwrap_or(Value::Null);
        // A list refresh must not reopen the same Flatpak repository once per
        // app. Keep one local handle per scope for this snapshot, then release
        // all handles together. Do not retain them across transactions.
        let mut installations = HashMap::new();
        for line in text(event, "stdout")
            .lines()
            .enumerate()
            .filter(|(_, line)| !line.trim().is_empty())
        {
            let columns = match installed_columns(line.1, line.0 + 1) {
                Ok(columns) => columns,
                Err(error) => {
                    self.set("installedError", error.into());
                    return;
                }
            };
            let mut app = self.metadata(columns[0]);
            if !self.metadata.contains_key(normalized_id(columns[0])) {
                app["name"] = columns[1].into();
                app["summary"] = columns[7].into();
                app["description"] = columns[7].into();
            }
            merge(
                &mut app,
                &json!({"installedOrigin":columns[3],"installation":columns[4],"installedBranch":columns[5],"installedArch":columns[6],"installedVersion":columns[8]}),
            );
            let installation = installations
                .entry(columns[4].to_owned())
                .or_insert_with(|| sources::installation(columns[4]).ok());
            if let Some(size) = installation
                .as_ref()
                .and_then(|scope| sizes::installed(&app, scope))
            {
                app["installedBytes"] = size.into();
                app["installedSize"] = bytes(size).into();
            }
            let reference = format!("app/{}/{}/{}", columns[0], columns[6], columns[5]);
            app["installedRef"] = reference.clone().into();
            let key = format!("{}:{reference}", columns[4]);
            for (data, raw, label) in [
                (&history, "installedAt", "installedDate"),
                (&updates, "updatedAt", "updatedDate"),
            ] {
                let date = data["installations"][&key].as_str().unwrap_or("");
                let display = date_label(date);
                if !display.is_empty() {
                    app[raw] = date.into();
                    app[label] = display.into();
                }
            }
            apps.push(app);
        }
        self.set("installedError", "".into());
        self.set_installed_rows(apps);
        self.update_date();
    }
    pub(super) fn update_date(&mut self) {
        let last = rows(&self.properties["installedApps"])
            .iter()
            .map(|app| text(app, "updatedAt"))
            .max()
            .unwrap_or("");
        self.merge("updates", json!({"lastUpdated":date_label(last)}));
    }
    pub(super) fn cancel_permissions(&mut self, token: u64) {
        if token != 0 && token != self.permissions_token {
            return;
        }
        self.cancel_reader("permissions");
        self.set("appPermissions", json!({}));
    }
    pub(super) fn request_permissions(&mut self, app: Value) -> u64 {
        self.cancel_permissions(0);
        if self.stopping {
            return 0;
        }
        self.permissions_token += 1;
        let installed = !text(&app, "installation").is_empty();
        let request = if installed {
            self.installed_match(&app)
        } else {
            self.install_request(&app)
        };
        let Some(request) = request.filter(|r| !installed || !text(r, "installedRef").is_empty())
        else {
            self.set(
                "appPermissions",
                permissions::error(
                    "Permission information is not available for this app. Refresh and try again.",
                ),
            );
            return self.permissions_token;
        };
        self.set(
            "appPermissions",
            json!({"state":"loading","installed":installed}),
        );
        let context = json!({"installed":installed});
        if !installed && request["previewPermissions"]["state"] == "ready" {
            self.set("appPermissions", request["previewPermissions"].clone());
            return self.permissions_token;
        }
        if installed {
            self.start(
                "permissions",
                "flatpak",
                json!([
                    "info",
                    "--show-permissions",
                    scope_arg(text(&request, "installation")),
                    "--",
                    request["installedRef"]
                ]),
                30000,
                2 * 1024 * 1024,
                false,
                context,
            );
        } else {
            self.worker(
                "permissions",
                "--permissions-worker",
                request,
                30000,
                2 * 1024 * 1024,
                false,
                context,
            );
        }
        self.permissions_token
    }
    pub(super) fn cancel_addons(&mut self, token: u64) {
        if token != 0 && token != self.addons_token {
            return;
        }
        self.cancel_reader("addons");
        self.set("appAddons", json!({}));
    }
    pub(super) fn request_addons(&mut self, app: Value) -> u64 {
        self.cancel_addons(0);
        if self.stopping {
            return 0;
        }
        self.addons_token += 1;
        let id = normalized_id(text(&app, "id"));
        let mut parent = self.metadata(id);
        if let Some(installed) = rows(&self.properties["installedApps"])
            .iter()
            .find(|installed| {
                normalized_id(text(installed, "id")) == id
                    && installed["installation"] == app["installation"]
                    && installed["installedRef"] == app["installedRef"]
            })
        {
            parent = installed.clone();
            for source in rows(&self.metadata(id)["sources"]) {
                if source["flatpakRef"] == installed["installedRef"]
                    && source["remote"] == installed["installedOrigin"]
                {
                    parent["addons"] = source["addons"].clone();
                    parent["sourceUrl"] = source["sourceUrl"].clone();
                    break;
                }
            }
        }
        self.set("appAddons", json!({"state":"loading"}));
        self.worker(
            "addons",
            "--addons-worker",
            addons::compact_parent(&parent),
            30000,
            4 * 1024 * 1024,
            false,
            json!({}),
        );
        self.addons_token
    }
    pub(super) fn reader_finished(&mut self, role: &str, context: Value, event: &Value) {
        let installed = flag(&context, "installed");
        let permissions = role == "permissions";
        let label = if permissions {
            "app permissions"
        } else {
            "add-ons"
        };
        let mut result = if flag(event, "timedOut") {
            permissions::error(&format!("Reading {label} timed out. Please try again."))
        } else if !success(event) {
            permissions::error(&format!("Could not read {label}. Please try again."))
        } else if permissions && installed {
            permissions::parse(text(event, "stdout").as_bytes(), true)
        } else {
            serde_json::from_str(text(event, "stdout"))
                .unwrap_or_else(|_| permissions::error(&format!("Invalid {label} information.")))
        };
        if !matches!(text(&result, "state"), "ready" | "error" | "not-installed") {
            result = permissions::error(&format!("Invalid {label} information."));
        }
        if permissions {
            result["installed"] = installed.into();
        }
        self.set(
            if permissions {
                "appPermissions"
            } else {
                "appAddons"
            },
            result,
        );
    }
    pub(super) fn change_addon(&mut self, reference: &str, install: bool) {
        if self.tasks.contains_key("sources") || self.properties["appAddons"]["state"] != "ready" {
            return;
        }
        let row = rows(&self.properties["appAddons"]["items"])
            .iter()
            .find(|row| text(row, "flatpakRef") == reference && flag(row, "addon"))
            .cloned();
        if let Some(mut row) = row {
            if if install {
                !flag(&row, "available") || flag(&row, "installed")
            } else {
                !flag(&row, "installed")
            } {
                return;
            }
            row["action"] = if install { "install" } else { "uninstall" }.into();
            row["parent"] = self.properties["appAddons"]["parent"].clone();
            self.enqueue(row);
        }
    }
    pub(super) fn refresh_desktop_caches(&mut self) {
        if self.stopping {
            return;
        }
        if self.tasks.contains_key("desktop") {
            self.desktop_again = true;
            return;
        }
        if let Ok(path) = sources::installation("user").and_then(|i| sources::location(&i)) {
            let icons = path.join("exports/share/icons/hicolor");
            if icons.metadata().is_ok_and(|m| {
                m.is_dir() && m.uid() == unsafe { libc::geteuid() } && m.mode() & 0o200 != 0
            }) {
                self.desktop_commands.push_back(json!({"program":"gtk-update-icon-cache","args":["--force","--ignore-theme-index",icons]}));
            }
        }
        self.desktop_commands
            .push_back(json!({"program":"kbuildsycoca6","args":["--noincremental"]}));
        self.next_desktop_cache();
    }
    pub(super) fn next_desktop_cache(&mut self) {
        if self.stopping {
            return;
        }
        if let Some(command) = self.desktop_commands.pop_front() {
            self.start(
                "desktop",
                text(&command, "program"),
                command["args"].clone(),
                15000,
                1024 * 1024,
                false,
                json!({}),
            );
        } else {
            self.desktop_icons_pending = true;
            if self.desktop_again {
                self.desktop_again = false;
                self.refresh_desktop_caches();
            }
            self.refresh_installed();
        }
    }
    pub(super) fn refresh_desktop_icons_if_idle(&mut self) {
        if self.stopping
            || !self.desktop_icons_pending
            || self.jobs.iter().any(|job| flag(job, "active"))
            || ["install", "remove", "desktop"]
                .iter()
                .any(|role| self.tasks.contains_key(*role))
        {
            return;
        }
        // Launcher files and installed state are refreshed per deployment.
        // Repeated global icon invalidations force synchronous theme searches
        // and SVG painting in every visible control. Broadcast once per batch.
        // External desktop theme changes still follow the normal live signal.
        self.desktop_icons_pending = false;
        self.command(json!({"command":"refreshIcons"}));
    }
}
fn scope_arg(scope: &str) -> String {
    match scope {
        "user" => "--user".into(),
        "system" => "--system".into(),
        _ => format!("--installation={scope}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn installed_list_accepts_missing_optional_trailing_metadata() {
        let identity = "org.example.App\tExample\t12 MB\tflathub\tuser\tstable\tx86_64";
        for (suffix, summary, version) in [
            ("", "", ""),
            ("\tSummary", "Summary", ""),
            ("\t\t", "", ""),
            ("\t\t1.0", "", "1.0"),
            ("\tSummary\t1.0", "Summary", "1.0"),
        ] {
            let line = format!("{identity}{suffix}");
            let columns = installed_columns(&line, 1).unwrap();
            assert_eq!(columns[0], "org.example.App");
            assert_eq!(columns[4], "user");
            assert_eq!(columns[7], summary);
            assert_eq!(columns[8], version);
        }
    }

    #[test]
    fn malformed_installed_list_explains_the_row_and_preserves_previous_apps() {
        let mut manager = Manager::new(vec![]);
        let previous = json!([{"id":"org.example.Kept", "installation":"user"}]);
        manager.set("installedApps", previous.clone());
        manager.installed_finished(
            json!({"revision":manager.installed_revision}),
            &json!({"code":0,"stdout":"\norg.example.Broken\ttoo few\n"}),
        );
        let error = text(&manager.properties, "installedError");
        assert!(error.contains("line 2 has 2 fields"));
        assert!(error.contains("org.example.Broken"));
        assert!(error.contains("not an update failure"));
        assert_eq!(manager.properties["installedApps"], previous);
        assert!(installed_columns("a\tb\tc\td\te\tf", 1).is_err());
        assert!(installed_columns("a\tb\tc\td\te\tf\tg\th\ti\tj", 1).is_err());
    }

    #[test]
    fn installed_date_changes_transport_only_the_changed_app() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        let mut apps: Vec<_> = (0..200)
            .map(|index| {
                json!({"id":format!("a.b.App{index}"),
            "installedRef":format!("app/a.b.App{index}/x86_64/stable"),"installation":"user",
            "description":"unchanged metadata", "updatedAt":"before"})
            })
            .collect();
        manager.set_installed_rows(apps.clone());
        assert!(manager.initial()["state"]["installedApps"].is_array());
        apps[42]["updatedAt"] = "after".into();
        manager.set_installed_rows(apps.clone());
        let delta = manager.initial();
        assert!(delta["state"].get("installedApps").is_none());
        assert_eq!(delta["rows"]["installedApps"].as_object().unwrap().len(), 1);
        assert_eq!(delta["rows"]["installedApps"]["42"], apps[42]);
        manager.set_installed_rows(apps.clone());
        assert!(manager.initial()["rows"].get("installedApps").is_none());
        apps.swap(0, 1);
        manager.set_installed_rows(apps.clone());
        assert_eq!(manager.initial()["state"]["installedApps"], json!(apps));
        apps.pop();
        manager.set_installed_rows(apps.clone());
        assert_eq!(manager.initial()["state"]["installedApps"], json!(apps));
        apps[42]["updatedAt"] = "latest".into();
        manager.set_installed_rows(apps);
        manager.set("installedApps", json!([]));
        let replaced = manager.initial();
        assert_eq!(replaced["state"]["installedApps"], json!([]));
        assert!(replaced["rows"].get("installedApps").is_none());
    }

    #[test]
    fn desktop_icon_invalidations_are_coalesced_until_the_batch_finishes() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        manager.jobs = vec![json!({"active":true})];
        for _ in 0..200 {
            manager.desktop_icons_pending = true;
            manager.refresh_desktop_icons_if_idle();
        }
        assert!(!manager
            .commands
            .iter()
            .any(|command| command["command"] == "refreshIcons"));
        // A real theme change is independent of deferred deployment refreshes.
        let changed = manager.dispatch("iconsChanged", &json!([]));
        assert_eq!(changed["state"]["iconRevision"], 1);
        manager.jobs[0]["active"] = false.into();
        for role in ["install", "remove", "desktop"] {
            manager.tasks.insert(role.into(), Task::default());
            manager.refresh_desktop_icons_if_idle();
            assert!(manager.desktop_icons_pending);
            manager.tasks.remove(role);
        }
        manager.refresh_desktop_icons_if_idle();
        manager.refresh_desktop_icons_if_idle();
        assert!(!manager.desktop_icons_pending);
        assert_eq!(
            manager
                .commands
                .iter()
                .filter(|command| command["command"] == "refreshIcons")
                .count(),
            1
        );
    }

    #[test]
    fn installed_details_do_not_enumerate_remotes_until_the_app_is_removed() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        let app = json!({"id":"a.b.App"});
        manager.properties["installedApps"] = json!([app]);
        manager.install_info(app.clone());
        assert!(!manager.tasks.contains_key("sizes"));
        assert_eq!(manager.size_app, app);
        manager.properties["installedApps"] = json!([]);
        manager.install_info(manager.size_app.clone());
        assert!(manager.tasks.contains_key("sizes"));
    }

    #[test]
    fn size_reads_are_bounded_async_and_ignore_replaced_worker_results() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        let first = manager.dispatch("requestInstallInfo", &json!([{"id":"a.b.First"}]));
        let command = rows(&first["commands"])
            .iter()
            .find(|c| c["role"] == "sizes")
            .unwrap();
        assert_eq!(command["args"][0], "--sizes-worker");
        assert_eq!(command["timeout"], 30000);
        assert_eq!(command["limit"], 65536);
        let serial = command["serial"].clone();
        manager.dispatch("requestInstallInfo", &json!([{"id":"a.b.Second"}]));
        manager.event(
            &json!({"role":"sizes","serial":serial,"kind":"finished","code":0,
            "stdout":"{\"state\":\"ready\",\"appSize\":\"1 MiB\"}"}),
        );
        assert!(manager.properties["installSizes"]
            .get("a.b.First")
            .is_none());
        assert_eq!(
            manager.properties["installSizes"]["a.b.Second"]["state"],
            "loading"
        );
        let serial = manager.tasks["sizes"].serial;
        manager.event(
            &json!({"role":"sizes","serial":serial,"kind":"finished","code":0,
            "stdout":"{\"state\":\"ready\",\"appSize\":\"2 MiB\"}"}),
        );
        assert_eq!(
            manager.properties["installSizes"]["a.b.Second"]["appSize"],
            "2 MiB"
        );
        assert!(!manager.tasks.contains_key("sizes"));
    }

    #[test]
    fn failed_size_reads_keep_partial_local_preview_without_inventing_a_total() {
        for event in [
            json!({"code":1}),
            json!({"code":0,"stdout":"bad json"}),
            json!({"code":1,"timedOut":true}),
        ] {
            let mut manager = Manager::new(vec![]);
            manager.sizes_finished(
                json!({"id":"a.b.App","preview":{
                "state":"partial","appBytes":1024,"appSize":"1 KiB"}}),
                &event,
            );
            assert_eq!(
                manager.properties["installSizes"]["a.b.App"]["state"],
                "partial"
            );
            assert!(manager.properties["installSizes"]["a.b.App"]
                .get("totalBytes")
                .is_none());
        }
    }
}
