//! Real desktop/manager/IPC with simulated package workers. Never installed.
//! APPCENTER_PROFILE_CATALOG is a read-only catalog JSON array from --catalog.
//! Build: cargo build --release --features native-tests --example update-profile
//! Run under dbus-run-session with the desktop's Wayland display and
//! QT_FORCE_STDERR_LOGGING=1. Use queue_memory_probe.rs to sample RSS/PSS and
//! per-thread CPU. APPCENTER_PROFILE_QML can select UpdateProfileSoak.qml for
//! three batches; FLUFF_APP_CENTER_BACKGROUND_TEST=1 includes native jobs/power.
//! QML heartbeat gaps are responsiveness diagnostics, not rendered frame times
//! or a substitute for physical mouse/touchpad testing. This fixture does not
//! measure libflatpak transfer/deployment memory: those workers are simulated.
use flufflinux_appcenter::backend;
use serde_json::{json, Value};
use std::{
    env,
    ffi::CString,
    fs,
    io::{self, Write},
    path::PathBuf,
    time::Duration,
};

unsafe extern "C" {
    fn fluff_run_qml(
        qml: *const i8,
        icon: *const i8,
        count: i32,
        inputs: *const *const i8,
        desktop: *const i8,
    ) -> i32;
}
fn catalog() -> Vec<Value> {
    serde_json::from_slice(&fs::read(env::var("APPCENTER_PROFILE_CATALOG").unwrap()).unwrap())
        .unwrap()
}
fn item_count() -> usize {
    env::var("APPCENTER_PROFILE_ITEMS")
        .ok()
        .map(|value| value.parse::<usize>().expect("numeric fixture item count"))
        .unwrap_or(200)
        .clamp(1, 200)
}
fn send(value: Value) {
    println!("{value}");
    io::stdout().flush().unwrap();
}
fn main() {
    let args: Vec<_> = env::args().collect();
    if args.len() > 1 || PathBuf::from(&args[0]).file_name().unwrap() != "update-profile" {
        let root =
            PathBuf::from(env::var("APPCENTER_PROFILE_ROOT").expect("isolated fixture required"));
        assert!(
            root.starts_with("/tmp")
                && root
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with("appcenter-profile-")
        );
        assert!(root.join("fixture").is_file());
        for key in [
            "FLATPAK_USER_DIR",
            "FLATPAK_SYSTEM_DIR",
            "FLATPAK_CONFIG_DIR",
            "XDG_DATA_HOME",
        ] {
            assert!(PathBuf::from(env::var(key).unwrap()).starts_with(&root));
        }
        backend::process::parent_death_signal().unwrap();
        match args.get(1).map(String::as_str) {
            Some("--catalog") => send(catalog().into()),
            Some("--updates-worker") => {
                let rows: Vec<_> = catalog().into_iter().take(item_count()).enumerate().map(|(i, app)| {
                    let id = app["id"].as_str().unwrap();
                    let reference = format!("app/{id}/x86_64/stable");
                    let plan: Vec<_> = (0..12).map(|part| json!({"ref":if part == 0 {reference.clone()} else {format!("runtime/org.example.Shared{part}/x86_64/stable")},
                        "commit":"a".repeat(64),"downloadBytes":100000000,"action":"update","name":format!("Operation {part}")})).collect();
                    json!({"id":id,"name":app["name"],"developer":app["developer"],"icon":app["icon"],
                        "key":format!("user:{reference}"),"flatpakRef":reference,"installation":"user","remote":"fixture",
                        "commit":"a".repeat(64),"oldCommit":"b".repeat(64),"oldVersion":"1.0","newVersion":"2.0",
                        "selected":true,"plan":plan,"downloadBytes":1200000000u64,"permissions":{"state":"unchanged","groups":[]},"fixtureIndex":i})
                }).collect();
                send(
                    json!({"type":"updates","updates":rows,"errors":[],"skipped":[],"checkedAt":"2026-10-16T10:00:00Z"}),
                );
            }
            Some("--transaction-worker") => {
                let request: Value = serde_json::from_str(&args[2]).unwrap();
                assert_eq!(
                    request["action"], "update",
                    "fixture must never execute a real transaction"
                );
                send(json!({"type":"plan","operations":request["plan"]}));
                for tick in 1..=12 {
                    send(
                        json!({"type":"operation","ref":request["flatpakRef"],"phase":"download",
                        "progress":tick as f64/12.0,"downloadProgress":tick as f64/12.0,
                        "receivedBytes":tick * 8000000,"status":"Downloading"}),
                    );
                    std::thread::sleep(Duration::from_millis(10));
                }
                let saved = backend::storage::history_save(
                    &backend::storage::data_dir().join("update-dates.json"),
                    "user",
                    request["flatpakRef"].as_str().unwrap(),
                    Some(&chrono::Utc::now().to_rfc3339()),
                )
                .is_ok();
                send(json!({"type":"updated","ref":request["flatpakRef"],"historySaved":saved}));
                send(json!({"type":"result","success":true}));
            }
            Some("list") if PathBuf::from(&args[0]).file_name().unwrap() == "flatpak" => {
                for app in catalog().into_iter().take(item_count()) {
                    // Match flatpak list's tab-separated installed-app protocol.
                    println!(
                        "{}\t{}\t100 MB\tfixture\tuser\tstable\tx86_64\tFixture application\t2.0",
                        app["id"].as_str().unwrap(),
                        app["name"].as_str().unwrap()
                    );
                }
            }
            Some("--sizes-worker") => send(json!({"state":"unavailable"})),
            Some("--image-worker") => send(backend::images::worker(
                &serde_json::from_str(&args[2]).unwrap(),
            )),
            Some("--popularity-worker") => send(json!({})),
            Some("--recovery-worker") => send(backend::recovery::worker(
                &args[2],
                &PathBuf::from(&args[3]),
            )),
            _ if ["flatpak", "kbuildsycoca6", "gtk-update-icon-cache"].contains(
                &PathBuf::from(&args[0])
                    .file_name()
                    .unwrap()
                    .to_str()
                    .unwrap(),
            ) => {}
            _ => panic!("unexpected fixture command: {args:?}"),
        }
        return;
    }
    let root = tempfile::Builder::new()
        .prefix("appcenter-profile-")
        .tempdir_in("/tmp")
        .unwrap();
    fs::write(root.path().join("fixture"), b"isolated update profiling").unwrap();
    env::set_var("APPCENTER_PROFILE_ROOT", root.path());
    for (key, dir) in [
        ("FLATPAK_USER_DIR", "user"),
        ("FLATPAK_SYSTEM_DIR", "system"),
        ("FLATPAK_CONFIG_DIR", "flatpak-config"),
        ("XDG_DATA_HOME", "data"),
        ("XDG_CONFIG_HOME", "config"),
        ("XDG_CACHE_HOME", "cache"),
        ("XDG_RUNTIME_DIR", "runtime"),
    ] {
        let value = root.path().join(dir);
        fs::create_dir_all(&value).unwrap();
        env::set_var(key, value);
    }
    use std::os::unix::fs::{symlink, PermissionsExt};
    fs::set_permissions(
        root.path().join("runtime"),
        fs::Permissions::from_mode(0o700),
    )
    .unwrap();
    let bin = root.path().join("bin");
    fs::create_dir(&bin).unwrap();
    for name in ["flatpak", "kbuildsycoca6", "gtk-update-icon-cache"] {
        symlink(env::current_exe().unwrap(), bin.join(name)).unwrap();
    }
    env::set_var(
        "PATH",
        format!("{}:{}", bin.display(), env::var("PATH").unwrap()),
    );
    let project = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let qml = env::var("APPCENTER_PROFILE_QML").unwrap_or_else(|_| {
        project
            .join("tests/UpdateProfile.qml")
            .to_string_lossy()
            .into()
    });
    env::set_var("FLUFF_APP_CENTER_QML", &qml);
    env::set_var("FLUFF_APP_CENTER_RECOVERY_TEST", "1");
    // Opt-in attachment applies only to this isolated test process, never the app.
    if env::var("APPCENTER_PROFILE_ATTACH").as_deref() == Ok("1") {
        assert_eq!(
            unsafe { libc::prctl(libc::PR_SET_PTRACER, libc::PR_SET_PTRACER_ANY) },
            0
        );
    }
    eprintln!("PROFILE_PID {}", std::process::id());
    let qml = CString::new(qml).unwrap();
    let icon = CString::new(
        project
            .join("assets/flufflinux-appcenter.svg")
            .to_string_lossy()
            .as_bytes(),
    )
    .unwrap();
    let desktop = CString::new("appcenter-isolated-profile").unwrap();
    let code = unsafe {
        fluff_run_qml(
            qml.as_ptr(),
            icon.as_ptr(),
            0,
            std::ptr::null(),
            desktop.as_ptr(),
        )
    };
    drop(root);
    if code != 0 {
        std::process::exit(code);
    }
}
