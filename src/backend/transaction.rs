//! Killable, unprivileged Flatpak transactions. UI requests never bypass consent.
use super::{
    addons, bytes, flag, local_preview, number, process, progress, repositories, rows, sources,
    storage, text, updates, valid_id,
};
use gio::prelude::*;
use libflatpak::{prelude::*, RefKind, Transaction, TransactionOperationType as OpType};
use serde_json::{json, Value};
use std::{
    cell::RefCell,
    collections::HashMap,
    io::{BufRead, Read, Write},
    path::Path,
    rc::Rc,
    sync::{Arc, Condvar, Mutex},
    time::{Duration, Instant},
};

pub fn send(message: Value) {
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    let _ = writeln!(out, "{message}");
    let _ = out.flush();
}
#[derive(Default)]
struct Reply {
    token: u64,
    next: u64,
    answer: Option<bool>,
}
struct Control {
    cancel: gio::Cancellable,
    reply: Mutex<Reply>,
    wake: Condvar,
}
impl Control {
    fn new() -> Arc<Self> {
        let control = Arc::new(Self {
            cancel: gio::Cancellable::new(),
            reply: Mutex::new(Reply::default()),
            wake: Condvar::new(),
        });
        let reader = control.clone();
        std::thread::spawn(move || {
            let input = std::io::stdin();
            let mut input = input.lock();
            loop {
                let mut line = Vec::new();
                // Bound a single command even if stdin is not the GUI pipe.
                let read = (&mut input).take(65537).read_until(b'\n', &mut line);
                if read.is_err() || line.is_empty() || line.len() > 65536 {
                    break;
                }
                let Ok(message) = serde_json::from_slice::<Value>(&line) else {
                    continue;
                };
                let mut reply = reader.reply.lock().unwrap_or_else(|e| e.into_inner());
                if flag(&message, "cancel") {
                    reader.cancel.cancel();
                    send(json!({"type":"cancel-ack"}));
                }
                if reply.token != 0 && number(&message, "token") == reply.token {
                    reply.answer = Some(flag(&message, "accept"));
                }
                reader.wake.notify_all();
            }
            reader.cancel.cancel();
            reader.wake.notify_all();
        });
        control
    }
    fn ask(&self, mut review: Value) -> bool {
        let mut reply = self.reply.lock().unwrap_or_else(|e| e.into_inner());
        if self.cancel.is_cancelled() {
            return false;
        }
        reply.next += 1;
        reply.token = reply.next;
        reply.answer = None;
        review["type"] = "review".into();
        review["token"] = reply.token.into();
        send(review);
        while reply.answer.is_none() && !self.cancel.is_cancelled() {
            reply = self.wake.wait(reply).unwrap_or_else(|e| e.into_inner());
        }
        reply.token = 0;
        reply.answer == Some(true) && !self.cancel.is_cancelled()
    }
}
struct State {
    control: Arc<Control>,
    request: Value,
    id: String,
    name: String,
    scope: String,
    problem: String,
    removing: bool,
    addon: bool,
    updating: bool,
    plan_ready: bool,
    preview_plan: Option<Value>,
    preview_hint: crate::appstream::App,
    declined: bool,
    operation_error: bool,
    progress: HashMap<String, libflatpak::TransactionProgress>,
}
impl State {
    fn ask(&mut self, review: Value) -> bool {
        let answer = self.control.ask(review);
        if !answer {
            self.declined = true;
        }
        answer
    }
    // These fields map directly to the worker's operation progress protocol.
    #[allow(clippy::too_many_arguments)]
    fn operation(
        &self,
        reference: &str,
        status: &str,
        value: f64,
        phase: &str,
        download: f64,
        received: u64,
        estimating: bool,
    ) {
        send(
            json!({"type":"operation","ref":reference,"status":status,"progress":value,"phase":phase,"downloadProgress":download,"receivedBytes":received,"estimating":estimating}),
        );
    }
    fn close_app(&mut self) -> Result<(), String> {
        if !valid_id(&self.id) {
            return Err("Invalid app ID for closing the app.".into());
        }
        if !running(&self.id) {
            return Ok(());
        }
        send(json!({"type":"status","status":format!("Closing {}…",self.name)}));
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(5) {
            if self.control.cancel.is_cancelled() {
                return Err("Cancelled".into());
            }
            let _ = process::flatpak(&["kill", &self.id], 1, Some(&self.control.cancel));
            for _ in 0..5 {
                if !running(&self.id) {
                    return Ok(());
                }
                if self.control.cancel.is_cancelled() {
                    return Err("Cancelled".into());
                }
                std::thread::sleep(Duration::from_millis(50));
            }
        }
        Err(format!(
            "Could not close {}. Nothing has been removed.",
            self.name
        ))
    }
}
fn running(id: &str) -> bool {
    libflatpak::Instance::all()
        .iter()
        .any(|i| i.app().as_deref() == Some(id) && i.is_running())
}
fn download_status(raw: &str) -> bool {
    for format in [
        "Downloading: %s/%s",
        "Downloading metadata: %u/(estimating) %s",
        "Downloading extra data: %s/%s",
        "Downloading files: %d/%d %s",
    ] {
        let translated = glib::dgettext(Some("flatpak"), format);
        for template in [format, translated.as_str()] {
            if let Some((prefix, _)) = template.split_once('%') {
                if !prefix.trim().is_empty() && raw.starts_with(prefix.trim()) {
                    return true;
                }
            }
        }
    }
    false
}
fn connect(tx: &Transaction, state: Rc<RefCell<State>>) {
    let s = state.clone();
    tx.connect_ready_pre_auth(move|tx|{
        let mut w=s.borrow_mut();let mut operations=Vec::new();let(mut total,mut app_size)=(0,0);
        for op in tx.operations(){
            if op.is_skipped(){continue;}let reference=op.get_ref().unwrap_or_default();let id=reference.split('/').nth(1).unwrap_or("");
            if reference.starts_with("app/"){
                if !w.id.is_empty()&&w.id!=id{w.problem="The Flatpak source changed to a different application. Open it again to review the app.".into();return false;}
                if w.id.is_empty(){w.id=id.into();}app_size+=op.download_size();
            }
            total+=op.download_size();operations.push(updates::operation_info(&op));
        }
        if w.updating&&!progress::matches_plan(rows(&w.request["plan"]),&operations){w.problem="The update or its dependencies changed. Check for updates again before continuing.".into();return false;}
        send(json!({"type":"identity","appId":w.id}));
        let plan=json!({"type":"plan","appId":w.id,"operations":operations,"appBytes":app_size,"totalBytes":total,"appSize":bytes(app_size),"totalSize":bytes(total),"state":"ready"});w.plan_ready=true;
        if flag(&w.request,"prepareOnly"){w.preview_plan=Some(plan);return false;}
        send(plan);
        if flag(&w.request,"estimateOnly"){return false;}
        if !w.removing{return !w.control.cancel.is_cancelled();}
        if !flag(&w.request,"removalConfirmed"){
            let message=if w.addon{format!("Only {} will be removed. The parent app and its data will be kept.",w.name)}else if w.scope!="user"{format!("If you proceed, {} will be removed for all users, and its app data for this account will be deleted.",w.name)}else{format!("If you proceed, {} and its app data will be removed.",w.name)};
            let review=json!({"kind":"transaction","operations":operations,"appId":w.id,"removing":true,"downloadSize":bytes(total),"title":format!("Uninstall {}?",w.name),"message":message});
            if !w.ask(review){return false;}
        }
        if !w.addon{if let Err(error)=w.close_app(){w.problem=error;return false;}}true
    });
    let s = state.clone();
    tx.connect_add_new_remote(move|_,_,_,name,url|{
        let mut w=s.borrow_mut();
        if w.updating{w.problem="This update needs a new software source. Configure it first, then check for updates again.".into();return false;}
        if flag(&w.request,"estimateOnly"){w.problem="Sizes will be available after the required software source is configured.".into();return false;}
        if !repositories::safe_url(url){w.problem="The new repository must use HTTPS without embedded credentials.".into();return false;}
        if sources::official_definition(url).is_some(){return true;}
        w.ask(json!({"kind":"remote","title":"Trust a new software source?","message":format!("Flatpak needs to add {name} for your user:\n{url}\nOnly continue if you trust this source. It can remain in your account even if you cancel installation later."),"operations":[]}))
    });
    let s = state.clone();
    tx.connect_new_operation(move |_, op, progress| {
        let reference = op.get_ref().unwrap_or_default().to_string();
        let bundle = op.operation_type() == OpType::InstallBundle;
        {
            let mut w = s.borrow_mut();
            w.progress.insert(reference.clone(), progress.clone());
            w.operation(
                &reference,
                if w.removing {
                    "Uninstalling…"
                } else if bundle {
                    "Installing…"
                } else {
                    "Preparing…"
                },
                0.0,
                if w.removing {
                    "uninstall"
                } else if bundle {
                    "install"
                } else {
                    "preparing"
                },
                0.0,
                0,
                false,
            );
        }
        progress.set_update_frequency(100);
        let s = s.clone();
        progress.connect_changed(move |progress| {
            let w = s.borrow();
            let raw = progress.status().unwrap_or_default();
            let percent = (progress.progress() as f64 / 100.0).clamp(0.0, 1.0);
            let downloading = download_status(&raw);
            let phase = if w.removing {
                "uninstall"
            } else if bundle {
                "install"
            } else if downloading {
                "download"
            } else if percent >= 1.0 {
                "install"
            } else {
                "preparing"
            };
            let received = progress.bytes_transferred();
            let status = if phase == "preparing" {
                "Preparing…".into()
            } else if w.removing {
                "Uninstalling…".into()
            } else if downloading && received > 0 {
                format!("Downloading… {} received", bytes(received))
            } else if downloading {
                "Downloading…".into()
            } else {
                "Installing…".into()
            };
            w.operation(
                &reference,
                &status,
                percent.min(0.99),
                phase,
                if downloading {
                    percent.min(0.99)
                } else if percent >= 1.0 {
                    1.0
                } else {
                    0.0
                },
                received,
                progress.is_estimating(),
            );
        });
    });
    // libflatpak-rs 0.7 assumes the commit argument is non-null. Uninstall
    // completion legitimately has no commit, so use GLib's safe value signal
    // API without converting that unused nullable argument into a Rust string.
    let s = state.clone();
    tx.connect_local("operation-done", false, move |values| {
        let op = values[1]
            .get::<libflatpak::TransactionOperation>()
            .expect("operation-done operation type");
        let result = values[3]
            .get::<libflatpak::TransactionResult>()
            .or_else(|_| {
                values[3]
                    .get::<i32>()
                    .map(|bits| libflatpak::TransactionResult::from_bits_truncate(bits as u32))
            })
            .expect("operation-done result type");
        let mut w = s.borrow_mut();
        let reference = op.get_ref().unwrap_or_default();
        // The generated binding calls FLATPAK_TRANSACTION_RESULT_NO_CHANGE CHANGE.
        if w.updating
            && reference.starts_with("app/")
            && op.operation_type() == OpType::Update
            && !result.contains(libflatpak::TransactionResult::CHANGE)
        {
            let saved = storage::history_save(
                &storage::data_dir().join("update-dates.json"),
                &w.scope,
                &reference,
                Some(&chrono::Utc::now().to_rfc3339()),
            )
            .is_ok();
            send(json!({"type":"updated","ref":reference.as_str(),"historySaved":saved}));
        }
        let received = w
            .progress
            .remove(reference.as_str())
            .map(|p| p.bytes_transferred())
            .unwrap_or(0);
        w.operation(
            &reference, "Complete", 1.0, "complete", 1.0, received, false,
        );
        None
    });
    tx.connect_operation_error(move |_, op, error, _| {
        let mut w = state.borrow_mut();
        w.operation_error = true;
        w.problem = error.to_string();
        w.operation(
            &op.get_ref().unwrap_or_default(),
            &w.problem,
            0.0,
            "failed",
            0.0,
            0,
            false,
        );
        false
    });
}
fn clear_data(id: &str, cancel: &gio::Cancellable) -> Result<(), String> {
    if !valid_id(id) {
        return Err("Invalid app ID for data removal.".into());
    }
    let home = std::env::var_os("HOME").ok_or("Home directory is unavailable")?;
    let base = Path::new(&home).join(".var");
    for path in [&base, &base.join("app")] {
        if std::fs::symlink_metadata(path).is_ok_and(|m| m.is_symlink()) {
            return Err(
                "App removed, but data cleanup refused a symlinked ~/.var/app directory.".into(),
            );
        }
    }
    let path = base.join("app").join(id);
    if let Ok(metadata) = std::fs::symlink_metadata(&path) {
        let result = if metadata.is_dir() && !metadata.is_symlink() {
            std::fs::remove_dir_all(&path)
        } else {
            std::fs::remove_file(&path)
        };
        result.map_err(|e| {
            format!(
                "App removed, but some sandbox data could not be deleted: {}: {e}",
                path.display()
            )
        })?;
    }
    let result = process::flatpak(&["permission-reset", id], 15, Some(cancel))?;
    if result.code != 0 {
        return Err(format!(
            "App and sandbox data removed, but resetting portal permissions failed: {}",
            result.stderr
        ));
    }
    Ok(())
}
fn execute(state: Rc<RefCell<State>>) -> Result<(), String> {
    let request = state.borrow().request.clone();
    let cancel = state.borrow().control.cancel.clone();
    let action = text(&request, "action");
    let id = text(&request, "id");
    let addon = flag(&request, "addon");
    let removing = action == "uninstall";
    let updating = action == "update";
    if flag(&request, "estimateOnly") && action != "install" {
        return Err("Passive estimates only support catalog applications.".into());
    }
    if !id.is_empty() && !valid_id(id) {
        return Err("Invalid Flatpak app ID.".into());
    }
    if addon {
        addons::validate(&request, &cancel)?;
    }
    let scope = if (removing || updating || addon) && !text(&request, "installation").is_empty() {
        text(&request, "installation")
    } else {
        "user"
    };
    let installation = sources::installation(scope)?;
    if action == "repositories" {
        return repositories::operate(&installation, &request, &cancel, send);
    }
    let remote = if text(&request, "remote").is_empty() {
        "flathub"
    } else {
        text(&request, "remote")
    };
    if !addon && action == "install" {
        repositories::ensure_user(
            &installation,
            remote,
            text(&request, "sourceUrl"),
            flag(&request, "estimateOnly"),
            &cancel,
        )?;
    }
    let tx =
        Transaction::for_installation(&installation, Some(&cancel)).map_err(|e| e.to_string())?;
    tx.set_no_interaction(false);
    if addon {
        tx.set_disable_related(true);
    }
    if !removing {
        tx.add_default_dependency_sources();
    }
    connect(&tx, state.clone());
    if updating {
        let reference = text(&request, "flatpakRef");
        let commit = text(&request, "commit");
        let parsed = libflatpak::Ref::parse(reference)
            .map_err(|_| "Invalid update selection. Check for updates again.")?;
        if parsed.name().as_deref() != Some(id)
            || !progress::valid_commit(commit)
            || !progress::valid_commit(text(&request, "oldCommit"))
            || rows(&request["plan"]).is_empty()
        {
            return Err("Invalid update selection. Check for updates again.".into());
        }
        let current = installation
            .installed_ref(
                parsed.kind(),
                id,
                parsed.arch().as_deref(),
                parsed.branch().as_deref(),
                Some(&cancel),
            )
            .map_err(|_| "This app is no longer installed. Check for updates again.")?;
        if current.origin().as_deref() != Some(remote) {
            return Err("The installed source changed. Check for updates again.".into());
        }
        if current.commit().as_deref() == Some(commit) {
            return Ok(());
        }
        if current.commit().as_deref() != Some(text(&request, "oldCommit")) {
            return Err("The installed version changed. Check for updates again.".into());
        }
        for op in rows(&request["plan"]) {
            let remote = installation
                .remote_by_name(text(op, "remote"), Some(&cancel))
                .map_err(|_| {
                    "An update source changed or was disabled. Check for updates again."
                })?;
            if remote.is_disabled()
                || sources::url(&remote) != text(op, "sourceUrl")
                || text(op, "sourceKey").is_empty()
                || sources::source_key(&installation, &remote)? != text(op, "sourceKey")
            {
                return Err(
                    "An update source changed or was disabled. Check for updates again.".into(),
                );
            }
        }
        tx.add_update(reference, &[], None)
            .map_err(|e| e.to_string())?;
    } else if removing {
        let current = installation
            .installed_ref(
                if addon {
                    RefKind::Runtime
                } else {
                    RefKind::App
                },
                id,
                Some(text(&request, "installedArch")),
                Some(text(&request, "installedBranch")),
                Some(&cancel),
            )
            .map_err(|e| e.to_string())?;
        tx.add_uninstall(&current.format_ref().unwrap_or_default())
            .map_err(|e| e.to_string())?;
    } else if action == "install" {
        let reference = if text(&request, "flatpakRef").is_empty() {
            format!(
                "app/{id}/{}/stable",
                libflatpak::default_arch().unwrap_or_default()
            )
        } else {
            text(&request, "flatpakRef").into()
        };
        let parsed = libflatpak::Ref::parse(&reference)
            .map_err(|_| "Catalog has an invalid Flatpak application reference.")?;
        if parsed.kind()
            != (if addon {
                RefKind::Runtime
            } else {
                RefKind::App
            })
            || parsed.name().as_deref() != Some(id)
        {
            return Err("Catalog has an invalid Flatpak application reference.".into());
        }
        tx.add_install(remote, &reference, &[])
            .map_err(|e| e.to_string())?;
    } else if action == "source" {
        let input = text(&request, "source");
        let path = repositories::local_path(input);
        if let Some(path) = path.filter(|p| {
            p.extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("flatpak"))
        }) {
            if !state.borrow_mut().ask(json!({"kind":"bundle","title":"Open local Flatpak bundle?","message":format!("Only open bundles from a source you trust. Flatpak may register the bundle's software source for your user while preparing it.\n\n{}",path.display()),"operations":[]})){return Err("Cancelled".into());}
            if flag(&request, "prepareOnly") {
                // The bundle contains its own app metadata and permissions.
                // Preview must not require its runtime or a reachable source.
                // Actual installation still resolves every required dependency.
                tx.set_disable_dependencies(true);
                tx.set_disable_related(true);
            }
            tx.add_install_bundle(&gio::File::for_path(path), None)
                .map_err(|e| e.to_string())?;
        } else {
            let contents = repositories::read_source(input, &cancel)?;
            let key = repositories::key_file(&contents)?;
            if key.has_group("Flatpak Repo") {
                if !id.is_empty() {
                    return Err("The app reference was replaced by a repository file.".into());
                }
                let url = key.string("Flatpak Repo", "Url").unwrap_or_default();
                if !repositories::safe_url(&url) {
                    return Err("Repository URL must use HTTPS.".into());
                }
                let path = url::Url::parse(input)
                    .ok()
                    .map(|u| u.path().to_owned())
                    .unwrap_or_else(|| input.into());
                let name = Path::new(&path)
                    .file_stem()
                    .and_then(|n| n.to_str())
                    .filter(|n| !n.is_empty())
                    .unwrap_or("imported-repository");
                if !name
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
                {
                    return Err("Invalid repository filename.".into());
                }
                if installation.remote_by_name(name, Some(&cancel)).is_ok() {
                    return Err(format!("A source named {name} is already configured for your user. Its URL, signing keys and settings have not been changed."));
                }
                if key
                    .string("Flatpak Repo", "GPGKey")
                    .unwrap_or_default()
                    .is_empty()
                {
                    return Err("Repositories without a signing key are not supported.".into());
                }
                if let Some(definition) = sources::official_definition(&url) {
                    return repositories::add_official(&installation, name, definition, &cancel);
                }
                let remote =
                    libflatpak::Remote::from_file(name, &glib::Bytes::from_owned(contents))
                        .map_err(|e| e.to_string())?;
                remote.set_gpg_verify(true);
                if !state.borrow_mut().ask(json!({"kind":"remote","title":"Add software source?","message":format!("{name}\n{url}\nThis source will be available for your user only."),"operations":[]})){return Err("Cancelled".into());}
                return installation
                    .modify_remote(&remote, Some(&cancel))
                    .map_err(|e| e.to_string());
            }
            if !key.has_group("Flatpak Ref") {
                return Err("This is not a Flatpak reference or repository file.".into());
            }
            let next_id = key.string("Flatpak Ref", "Name").unwrap_or_default();
            let url = key.string("Flatpak Ref", "Url").unwrap_or_default();
            if !valid_id(&next_id) || !repositories::safe_url(&url) {
                return Err("Invalid app ID or insecure repository in reference file.".into());
            }
            if !id.is_empty() && id != next_id {
                return Err("The reference now names a different app. Open it again.".into());
            }
            state.borrow_mut().id = next_id.to_string();
            state.borrow_mut().preview_hint = local_preview::reference_hint(&key);
            send(json!({"type":"identity","appId":next_id.as_str()}));
            tx.add_install_flatpakref(&glib::Bytes::from_owned(contents))
                .map_err(|e| e.to_string())?;
        }
    } else {
        return Err("Unsupported transaction request.".into());
    }
    let result = tx.run(Some(&cancel));
    // A preview stops before deployment. Resolve its details after the transaction
    // has released its locks, not inside a nested repository refresh callback.
    let preview = state.borrow_mut().preview_plan.take();
    if let Some(mut plan) = preview.filter(|_| !cancel.is_cancelled()) {
        let app_id = text(&plan, "appId");
        if let Some(op) = tx.operations().into_iter().find(|op| {
            op.get_ref()
                .is_some_and(|r| r.starts_with(&format!("app/{app_id}/")))
        }) {
            let hint = state.borrow().preview_hint.clone();
            let details = local_preview::resolve(&installation, &request, &op, &hint, &cancel);
            plan["app"] = details["app"].clone();
            plan["permissions"] = details["permissions"].clone();
        }
        if !cancel.is_cancelled() {
            send(plan);
        }
    }
    {
        let w = state.borrow();
        if result.is_err() || w.operation_error {
            if (flag(&request, "estimateOnly") || flag(&request, "prepareOnly"))
                && w.plan_ready
                && !cancel.is_cancelled()
            {
                return Ok(());
            }
            return Err(if !w.problem.is_empty() {
                w.problem.clone()
            } else {
                result
                    .err()
                    .map(|e| e.to_string())
                    .unwrap_or_else(|| "The transaction failed".into())
            });
        }
    }
    if removing && !addon {
        state
            .borrow_mut()
            .close_app()
            .map_err(|_| "App removed, but it could not be closed to delete its data.")?;
        send(json!({"type":"status","status":"Deleting sandbox data and resetting permissions…"}));
        clear_data(id, &cancel)?;
    }
    Ok(())
}
pub fn run(request: Value) -> i32 {
    if unsafe { libc::geteuid() } == 0 {
        send(
            json!({"type":"result","success":false,"error":"Run App Center as your desktop user, not root."}),
        );
        return 1;
    }
    if let Err(error) = process::parent_death_signal() {
        send(json!({"type":"result","success":false,"error":error}));
        return 1;
    }
    unsafe {
        libc::umask(0o022);
    }
    let control = Control::new();
    let action = text(&request, "action");
    let id = text(&request, "id").to_owned();
    let name = text(&request, "name").trim();
    let name = if name.is_empty() {
        id.clone()
    } else {
        name.into()
    };
    let state = Rc::new(RefCell::new(State {
        control: control.clone(),
        id,
        name,
        scope: request["installation"].as_str().unwrap_or("user").into(),
        problem: String::new(),
        removing: action == "uninstall",
        addon: flag(&request, "addon"),
        updating: action == "update",
        request,
        plan_ready: false,
        preview_plan: None,
        preview_hint: Default::default(),
        declined: false,
        operation_error: false,
        progress: HashMap::new(),
    }));
    let result = execute(state.clone());
    let success = result.is_ok();
    let error = result.err().unwrap_or_default();
    let cancelled =
        state.borrow().declined || control.cancel.is_cancelled() || error == "Cancelled";
    send(json!({"type":"result","success":success,"cancelled":cancelled,"error":error}));
    // The stdin reader owns no transaction state and is intentionally detached.
    // Process exit must never wait indefinitely for another stdin byte.
    if success {
        0
    } else if cancelled {
        2
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_pull_status_counts_as_download() {
        assert!(download_status("Downloading: 1/2"));
        assert!(!download_status("Writing objects: 100%"));
        assert!(!download_status("Deployment complete"));
    }
}
