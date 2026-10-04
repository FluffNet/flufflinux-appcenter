//! Desktop state machine. Qt executes transport commands and renders properties;
//! it does not choose sources, plan jobs, validate requests, or manage the cache.
mod apps;
mod catalog_state;
mod navigation;
mod queue;
mod update_state;
use super::{bytes, flag, normalized_id, number, progress, rows, storage, text};
use serde_json::{json, Map, Value};
use std::{
    collections::{HashMap, VecDeque},
    time::Instant,
};

#[derive(Default)]
struct Task {
    serial: u64,
    context: Value,
}
#[derive(Default)]
struct CatalogState {
    path: String,
    fingerprint: String,
    reading: String,
    saved: String,
    pending: bool,
    awaiting: bool,
    refreshed: bool,
    reset_age: bool,
    again: bool,
    force_again: bool,
    failed: bool,
    deadline: Option<Instant>,
    network_ready: bool,
    offline: bool,
    source_operation: String,
    source_result: bool,
    source_success: bool,
    source_reported: bool,
    source_refreshed: u64,
}
pub struct Manager {
    properties: Value,
    dirty: Map<String, Value>,
    signals: Vec<Value>,
    commands: Vec<Value>,
    tasks: HashMap<String, Task>,
    serial: u64,
    stopping: bool,
    metadata: HashMap<String, Value>,
    sources: HashMap<String, Value>,
    jobs: Vec<Value>,
    requests: Vec<Value>,
    batch: u64,
    reviews: VecDeque<Value>,
    review_token: u64,
    rate: progress::DownloadRate,
    clock: Instant,
    catalog: CatalogState,
    size_app: Value,
    permissions_token: u64,
    addons_token: u64,
    installed_revision: u64,
    installed_again: bool,
    desktop_commands: VecDeque<Value>,
    desktop_again: bool,
    source_refresh_pending: bool,
    update_sources_changed: bool,
    pending_inputs: Vec<String>,
    pending_links: Vec<String>,
    pending_installed_links: Vec<String>,
    popularity_attempt: Option<Instant>,
    background: super::background::Background,
}
impl Manager {
    pub fn new(catalog: Vec<Value>) -> Self {
        let properties = json!({"jobs":[],"review":{},"busy":false,"backgroundWorkPending":false,
            "installedApps":[],"installedLoading":true,"installedError":"","iconRevision":0,
            "installSizes":{},"appPermissions":{},"appAddons":{},
            "updates":{"state":"idle","items":[],"status":"","skipped":[],"error":"","lastChecked":"","lastUpdated":""},
            "catalog":[],"catalogLoading":false,"catalogProgress":0,"catalogSourcesUnavailable":false,
            "repositories":[],"sourcesBusy":false,"sourceInputStatus":"","sourcesError":"","popularity":super::popularity::cached()});
        let mut manager = Self {
            dirty: properties.as_object().unwrap().clone(),
            properties,
            signals: vec![],
            commands: vec![],
            tasks: HashMap::new(),
            serial: 0,
            stopping: false,
            metadata: HashMap::new(),
            sources: HashMap::new(),
            jobs: vec![],
            requests: vec![],
            batch: 0,
            reviews: VecDeque::new(),
            review_token: 0,
            rate: Default::default(),
            clock: Instant::now(),
            catalog: CatalogState {
                network_ready: true,
                ..Default::default()
            },
            size_app: json!({}),
            permissions_token: 0,
            addons_token: 0,
            installed_revision: 0,
            installed_again: false,
            desktop_commands: VecDeque::new(),
            desktop_again: false,
            source_refresh_pending: false,
            update_sources_changed: false,
            pending_inputs: vec![],
            pending_links: vec![],
            pending_installed_links: vec![],
            popularity_attempt: None,
            background: Default::default(),
        };
        if !catalog.is_empty() {
            manager.set_catalog(catalog);
            manager.catalog_progress(100, true);
        }
        manager.defer("refreshInstalled");
        manager
    }
    fn set(&mut self, key: &str, value: Value) {
        if self.properties[key] != value {
            self.properties[key] = value.clone();
            self.dirty.insert(key.into(), value);
        }
    }
    fn merge(&mut self, key: &str, patch: Value) {
        let mut value = self.properties[key].clone();
        merge(&mut value, &patch);
        self.set(key, value);
    }
    fn signal(&mut self, name: &str, args: Value) {
        self.signals.push(json!({"name":name,"args":args}));
    }
    fn error(&mut self, message: impl Into<String>) {
        self.signal("inputError", json!([message.into()]));
    }
    fn command(&mut self, command: Value) {
        self.commands.push(command);
    }
    fn defer(&mut self, action: &str) {
        self.command(json!({"command":"defer","action":action}));
    }
    fn busy(&self) -> bool {
        self.jobs.iter().any(|job| flag(job, "active"))
            || ["install", "remove", "sources", "desktop", "updates"]
                .iter()
                .any(|role| self.tasks.contains_key(*role))
    }
    // Keep the transport limits explicit at each worker call site.
    #[allow(clippy::too_many_arguments)]
    fn start(
        &mut self,
        role: &str,
        program: &str,
        args: Value,
        timeout: u64,
        limit: u64,
        stream: bool,
        context: Value,
    ) {
        self.serial += 1;
        self.tasks.insert(
            role.into(),
            Task {
                serial: self.serial,
                context,
            },
        );
        self.command(json!({"command":"start","role":role,"serial":self.serial,"program":program,"args":args,
            "timeout":timeout,"limit":limit,"stream":stream,"stderrLines":role=="catalog","interactive":matches!(role,"install"|"remove"|"sources")}));
    }
    #[allow(clippy::too_many_arguments)]
    fn worker(
        &mut self,
        role: &str,
        option: &str,
        request: Value,
        timeout: u64,
        limit: u64,
        stream: bool,
        context: Value,
    ) {
        self.start(
            role,
            "@self",
            json!([option, request.to_string()]),
            timeout,
            limit,
            stream,
            context,
        );
    }
    fn transport(&mut self, role: &str, command: &str, extra: Value) {
        if let Some(task) = self.tasks.get(role) {
            let mut request = json!({"command":command,"role":role,"serial":task.serial});
            merge(&mut request, &extra);
            self.command(request);
        }
    }
    fn cancel_reader(&mut self, role: &str) {
        self.transport(role, "kill", json!({}));
        self.tasks.remove(role);
    }
    fn metadata(&self, id: &str) -> Value {
        self.metadata.get(normalized_id(id)).cloned().unwrap_or_else(||json!({"id":id,"name":id,"icon":id,
            "summary":"","description":"","category":"","developer":"","license":"","homepage":"","screenshots":[]}))
    }
    fn finish_envelope(&mut self, result: Value) -> Value {
        let busy = self.busy();
        self.set("busy", busy.into());
        self.set(
            "backgroundWorkPending",
            (busy || self.tasks.contains_key("catalog")).into(),
        );
        self.set("sourcesBusy", self.tasks.contains_key("sources").into());
        self.set(
            "catalogLoading",
            (self.catalog.pending || self.catalog.awaiting || self.tasks.contains_key("catalog"))
                .into(),
        );
        self.set(
            "catalogSourcesUnavailable",
            (self.catalog.failed && rows(&self.properties["catalog"]).is_empty()).into(),
        );
        for data in self.background.synchronize(
            rows(&self.properties["jobs"]),
            &self.properties["review"],
            flag(&self.properties, "backgroundWorkPending"),
        ) {
            self.command(json!({"command":"background","data":data}));
        }
        json!({"state":std::mem::take(&mut self.dirty),"signals":std::mem::take(&mut self.signals),"commands":std::mem::take(&mut self.commands),"return":result})
    }
    pub fn initial(&mut self) -> Value {
        self.finish_envelope(Value::Null)
    }
    pub fn dispatch(&mut self, action: &str, args: &Value) -> Value {
        let arg = |index: usize| args.get(index).cloned().unwrap_or(Value::Null);
        let mut result = Value::Null;
        match action {
            "event" => self.event(&arg(0)),
            "backgroundEnable" => self.background.enabled = true,
            "backgroundClosed" => self.background.closed = arg(0) == true,
            "backgroundIdle" => {
                if self.background.closed && !self.busy() && !self.tasks.contains_key("catalog") {
                    self.command(json!({"command":"background","data":{"kind":"quit"}}));
                }
            }
            "loadPopularity" => {
                if super::popularity::should_load(
                    &self.properties["popularity"],
                    self.popularity_attempt,
                ) {
                    self.popularity_attempt = Some(Instant::now());
                    self.merge("popularity", json!({"state":"loading"}));
                    self.start(
                        "popularity",
                        "@self",
                        json!(["--popularity-worker"]),
                        300000,
                        1024 * 1024,
                        false,
                        json!({}),
                    );
                }
            }
            "loadCatalog" => self.load_catalog(arg(0).as_str().unwrap_or("")),
            "setCatalogNetworkState" => {
                self.catalog.network_ready = arg(1).as_bool().unwrap_or(false);
                self.catalog.offline = arg(0) == "offline";
                self.start_catalog_refresh();
            }
            "initializeSources" => {
                if self.catalog.path.is_empty() {
                    self.source_operation(json!({"operation":"initialize"}));
                }
            }
            "refreshSources" => {
                self.source_operation(json!({"operation":if arg(0)==true{"refresh"}else{"list"}}))
            }
            "addDefaultSources" => self.source_operation(json!({"operation":"defaults"})),
            "setSourceEnabled" => self.source_setting(&arg(0), Some(arg(1) == true)),
            "removeSource" => self.source_setting(&arg(0), None),
            "refreshInstalled" => self.refresh_installed(),
            "requestInstallInfo" => self.install_info(arg(0)),
            "requestAppPermissions" => result = self.request_permissions(arg(0)).into(),
            "cancelAppPermissions" => self.cancel_permissions(arg(0).as_u64().unwrap_or(0)),
            "requestAppAddons" => result = self.request_addons(arg(0)).into(),
            "cancelAppAddons" => self.cancel_addons(arg(0).as_u64().unwrap_or(0)),
            "changeAddon" => self.change_addon(arg(0).as_str().unwrap_or(""), arg(1) == true),
            "checkForUpdates" => self.check_updates(),
            "cancelUpdateCheck" => self.cancel_updates(),
            "selectUpdate" => {
                self.select_update(Some(arg(0).as_str().unwrap_or("")), arg(1) == true)
            }
            "selectAllUpdates" => self.select_update(None, arg(0) == true),
            "installSelectedUpdates" => self.install_updates(),
            "installApp" => self.install_app(&arg(0)),
            "uninstallApp" => self.uninstall_app(&arg(0)),
            "launchApp" => self.launch_app(&arg(0)),
            "openSource" => self.open_source(arg(0).as_str().unwrap_or("")),
            "openInstalledApplication" => self.open_installed(arg(0).as_str().unwrap_or("")),
            "answerReview" => self.answer_review(arg(0).as_u64().unwrap_or(0), arg(1) == true),
            "cancelJob" => {
                if let Some(index) = arg(0).as_u64() {
                    self.cancel_job(index as usize);
                }
            }
            "cancelAll" => self.cancel_all(),
            "clearDownloadHistory" => {
                for job in &mut self.jobs {
                    if !flag(job, "active") && text(job, "action") != "uninstall" {
                        job["hidden"] = true.into();
                    }
                }
                self.publish_jobs();
            }
            "startNext" => {
                self.start_next();
                self.start_catalog_refresh();
            }
            "showNextReview" => self.show_review(),
            "downloadTick" => self.download_tick(),
            "iconsChanged" => {
                self.set(
                    "iconRevision",
                    (number(&self.properties, "iconRevision") + 1).into(),
                );
            }
            "shutdown" => {
                self.stopping = true;
                self.cancel_all();
            }
            _ => {}
        }
        self.drain_links();
        self.start_catalog_refresh();
        self.finish_envelope(result)
    }
    fn event(&mut self, event: &Value) {
        let role = text(event, "role");
        let Some(task) = self.tasks.get(role) else {
            return;
        };
        if task.serial != number(event, "serial") {
            return;
        }
        if text(event, "kind") == "line" {
            if role == "catalog" {
                if !self.catalog.awaiting && !self.catalog.pending {
                    if let Some(progress) = text(event, "line")
                        .strip_prefix("APPCENTER_CATALOG_PROGRESS ")
                        .and_then(|s| s.trim().parse::<u64>().ok())
                        .filter(|n| (70..=99).contains(n))
                    {
                        self.catalog_progress(progress, false);
                    }
                }
            } else if let Ok(message) = serde_json::from_str::<Value>(text(event, "line")) {
                match role {
                    "install" | "remove" => self.job_message(role, &message),
                    "sources" => self.source_message(&message),
                    "updates" => self.update_message(&message),
                    _ => {}
                }
            }
        } else if text(event, "kind") == "finished" {
            let task = self.tasks.remove(role).unwrap();
            match role {
                "install" | "remove" => self.job_finished(role, task.context, event),
                "sources" => self.source_finished(event),
                "catalog" => self.catalog_finished(event),
                "installed" => self.installed_finished(task.context, event),
                "permissions" | "addons" => self.reader_finished(role, task.context, event),
                "updates" => self.updates_finished(flag(&task.context, "result"), event),
                "desktop" => self.next_desktop_cache(),
                "popularity" => {
                    let result: Value =
                        serde_json::from_str(text(event, "stdout")).unwrap_or(Value::Null);
                    if success(event) && result["state"] == "ready" {
                        self.set("popularity", result);
                    } else {
                        self.merge("popularity", json!({"state":"unavailable"}));
                    }
                }
                _ => {}
            }
            self.defer("startNext");
        }
    }
}
fn merge(value: &mut Value, patch: &Value) {
    if let (Some(target), Some(patch)) = (value.as_object_mut(), patch.as_object()) {
        for (key, value) in patch {
            target.insert(key.clone(), value.clone());
        }
    }
}
fn success(event: &Value) -> bool {
    event["code"] == 0 && text(event, "error").is_empty() && !flag(event, "crashed")
}
fn date_label(value: &str) -> String {
    super::locale::date(value)
}
