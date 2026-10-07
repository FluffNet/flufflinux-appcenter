use super::*;
use crate::backend::{addons, permissions, sizes, sources};
use std::os::unix::fs::MetadataExt;
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
        let catalog = self.metadata.get(id).unwrap_or(app);
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
        let result = self
            .install_request(&app)
            .map(|request| {
                // Local-file sizes come from a complete disposable transaction,
                // not a registered source or the metadata-only preview plan.
                let preview = &request["previewSizes"];
                if preview["state"] == "ready" {
                    return preview.clone();
                }
                let result = sizes::local(&request);
                if result["state"] == "unavailable" && preview["appBytes"].is_u64() {
                    return preview.clone();
                }
                result
            })
            .unwrap_or_else(|| json!({"state":"unavailable"}));
        self.set("installSizes", json!({id:result}));
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
        for line in text(event, "stdout")
            .lines()
            .filter(|line| !line.is_empty())
        {
            let columns: Vec<_> = line.split('\t').map(str::trim).collect();
            if columns.len() != 9 {
                self.set(
                    "installedError",
                    "Flatpak returned an unexpected installed-app list.".into(),
                );
                return;
            }
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
            if let Some(size) = sizes::installed(&app) {
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
        self.set("installedApps", apps.into());
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
            self.command(json!({"command":"refreshIcons"}));
            if self.desktop_again {
                self.desktop_again = false;
                self.refresh_desktop_caches();
            }
            self.refresh_installed();
        }
    }
}
fn scope_arg(scope: &str) -> String {
    match scope {
        "user" => "--user".into(),
        "system" => "--system".into(),
        _ => format!("--installation={scope}"),
    }
}
