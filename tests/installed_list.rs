//! Offline regression with a real Flatpak that has no AppStream version/summary.
//! All installations, caches and repositories live in this test's temporary tree.
use flufflinux_appcenter::backend::{manager::Manager, process};
use serde_json::json;
use std::{fs, process::Command, time::Duration};

fn flatpak(args: &[&str]) -> String {
    let mut command = Command::new("flatpak");
    command.args(args);
    let result = process::run(command, Duration::from_secs(60), 1024 * 1024, None).unwrap();
    assert_eq!(result.code, 0, "{}", result.stderr);
    String::from_utf8(result.stdout).unwrap()
}

#[test]
fn real_app_without_version_or_summary_is_still_listed() {
    let root = tempfile::Builder::new()
        .prefix("appcenter-installed-list-")
        .tempdir()
        .unwrap();
    // This integration-test executable has one test and no other libflatpak users.
    for (key, dir) in [
        ("FLATPAK_USER_DIR", "user"),
        ("FLATPAK_SYSTEM_DIR", "system"),
        ("FLATPAK_CONFIG_DIR", "config"),
        ("XDG_CONFIG_HOME", "settings"),
        ("XDG_DATA_HOME", "data"),
        ("XDG_CACHE_HOME", "cache"),
    ] {
        fs::create_dir_all(root.path().join(dir)).unwrap();
        std::env::set_var(key, root.path().join(dir));
    }
    let app = "org.flufflinux.MissingVersionFixture";
    let build = root.path().join("build");
    fs::create_dir_all(build.join("files")).unwrap();
    fs::create_dir_all(build.join("export")).unwrap();
    let arch = flatpak(&["--default-arch"]).trim().to_owned();
    fs::write(
        build.join("metadata"),
        format!("[Application]\nname={app}\nruntime=org.flufflinux.TestRuntime/{arch}/stable\n"),
    )
    .unwrap();
    fs::write(build.join("files/fixture"), "offline fixture\n").unwrap();
    let repo = root.path().join("repo");
    flatpak(&[
        "build-export",
        repo.to_str().unwrap(),
        build.to_str().unwrap(),
        "stable",
    ]);
    flatpak(&[
        "remote-add",
        "--user",
        "--no-gpg-verify",
        "fixture",
        repo.to_str().unwrap(),
    ]);
    flatpak(&[
        "install",
        "--user",
        "--noninteractive",
        "--no-deps",
        "--no-related",
        "fixture",
        app,
    ]);

    let mut manager = Manager::new(vec![]);
    manager.initial();
    let request = manager.dispatch("refreshInstalled", &json!([]));
    let command = request["commands"]
        .as_array()
        .unwrap()
        .iter()
        .find(|command| command["role"] == "installed")
        .unwrap();
    let args: Vec<_> = command["args"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap())
        .collect();
    let output = flatpak(&args);
    let line = output.lines().find(|line| line.starts_with(app)).unwrap();
    assert_eq!(
        line.split('\t').count(),
        7,
        "Reproduce the old nine-field parser rejection: {line:?}"
    );
    let response = manager.dispatch("event", &json!([{
        "role":"installed", "serial":command["serial"], "kind":"finished", "code":0, "stdout":output
    }]));
    assert_eq!(response["state"]["installedLoading"], false);
    assert!(response["state"]
        .get("installedError")
        .is_none_or(|error| error == ""));
    let installed = response["state"]["installedApps"].as_array().unwrap();
    assert_eq!(installed.len(), 1);
    assert_eq!(installed[0]["id"], app);
    assert_eq!(installed[0]["installation"], "user");
    assert_eq!(installed[0]["installedVersion"], "");
    assert_eq!(
        installed[0]["installedRef"],
        format!("app/{app}/{arch}/stable")
    );
    assert!(installed[0]["installedBytes"].as_u64().is_some());
}
