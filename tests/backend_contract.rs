//! Behavioral contracts from the former C++ backend. All writes are temporary.
use flufflinux_appcenter::backend::{permissions, progress, source_removal, sources, storage};
use libflatpak::{prelude::*, Installation, Remote};
use serde_json::{json, Value};

#[test]
fn optional_live_https_reference_uses_system_trust() {
    // Opt-in only: normal regression runs remain offline and deterministic.
    if std::env::var("APPCENTER_TEST_FLATHUB_TLS").as_deref() != Ok("1") {
        return;
    }
    use flufflinux_appcenter::backend::repositories;
    let data = repositories::read_source(
        "https://dl.flathub.org/repo/flathub.flatpakrepo",
        &gio::Cancellable::new(),
    )
    .unwrap();
    let key = repositories::key_file(&data).unwrap();
    assert!(!key.string("Flatpak Repo", "GPGKey").unwrap().is_empty());
    assert_eq!(
        key.string("Flatpak Repo", "Url").unwrap(),
        "https://dl.flathub.org/repo/"
    );
}

#[test]
fn permission_groups_preserve_denials_unknown_rules_and_hide_environment() {
    let result = permissions::parse(
        br"[Application]
name=org.example.App
[Context]
shared=network;ipc;
sockets=pulseaudio;x11;wayland;ssh-auth;session-bus;
devices=dri;all;!input;
filesystems=home;xdg-download:ro;/tmp/foo:create;!/secret;xdg-documents:rw;
persistent=.local;cache;
features=bluetooth;!devel;multiarch;future-feature;
future-rule=custom;
[Session Bus Policy]
z.service=talk
a.service=own
hidden.service=none
see.service=see
[System Bus Policy]
org.bluez=talk
[USB Devices]
enumerable-devices=all;
hidden-devices=vnd:1234;
[Policy test]
access=foo;!bar;
[Environment]
SECRET_TOKEN=must-not-be-displayed
",
        false,
    );
    assert_eq!(result["state"], "ready");
    let groups = result["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 13);
    assert_eq!(groups[0]["id"], "network");
    assert_eq!(groups[1]["id"], "audio");
    assert_eq!(groups[2]["id"], "devices");
    let details = |id| {
        groups.iter().find(|g| g["id"] == id).unwrap()["details"]
            .as_array()
            .unwrap()
    };
    for label in [
        "Downloads - read only",
        "Documents - read and write",
        "/tmp/foo - read, write and create",
        "/secret - denied",
    ] {
        assert!(details("files").contains(&json!(label)));
    }
    assert!(details("session-bus").contains(&json!("Unrestricted access to this bus")));
    assert!(details("session-bus").contains(&json!("hidden.service - denied")));
    assert!(details("features").contains(&json!("future-feature")));
    assert!(details("devices").contains(&json!("Input devices - denied")));
    assert!(details("other").contains(&json!("test / access: !bar")));
    assert!(!result.to_string().contains("must-not-be-displayed"));
    assert_eq!(permissions::parse(b"", true)["state"], "ready");
    for invalid in [
        b"".as_slice(),
        b"<html>Server error</html>",
        b"[Application]\nname=test\n[Context]\nsockets=\\q;",
        &vec![b'x'; 1024 * 1024 + 1],
    ] {
        assert_eq!(permissions::parse(invalid, false)["state"], "error");
    }
    let escaped = permissions::parse(
        b"[Application]\nname=test\n[Context]\nfilesystems=/semi\\;colon:ro;\nshared=!network;\n",
        false,
    )
    .to_string();
    assert!(escaped.contains("/semi;colon - read only"));
    assert!(escaped.contains("Network connections - denied"));
}

#[test]
fn history_preserves_other_scopes_refs_and_concurrent_instances() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("dates.json");
    let app = "app/org.example.App/x86_64/stable";
    let other = "app/org.example.Other/x86_64/stable";
    let first = "2026-09-16T20:00:00.000Z";
    let second = "2026-09-17T20:00:00.000Z";
    assert!(storage::history_date(&path, "user", app).is_empty());
    storage::history_save(&path, "user", app, Some(first)).unwrap();
    storage::history_save(&path, "system", app, Some(second)).unwrap();
    storage::history_save(&path, "user", other, Some(first)).unwrap();
    assert_eq!(storage::history_date(&path, "user", app), first);
    assert_eq!(storage::history_date(&path, "system", app), second);
    assert!(storage::history_date(&path, "user", "app/org.example.App/aarch64/stable").is_empty());
    storage::history_save(&path, "user", app, None).unwrap();
    assert!(storage::history_date(&path, "user", app).is_empty());
    assert_eq!(storage::history_date(&path, "user", other), first);
    assert_eq!(storage::history_date(&path, "system", app), second);
    storage::history_save(&path, "user", app, Some(second)).unwrap();
    assert_eq!(storage::history_date(&path, "user", app), second);
    assert!(storage::history_save(&path, "user", app, Some("bad date")).is_err());
    assert!(storage::history_save(
        &path,
        "user",
        "runtime/org.example.Platform/x86_64/1",
        Some(first)
    )
    .is_err());
    let lock = storage::FileLock::acquire(&path.with_extension("json.lock")).unwrap();
    assert!(storage::history_save(&path, "user", app, Some(first)).is_err());
    drop(lock);
    assert_eq!(storage::history_date(&path, "user", app), second);
}

#[test]
fn staged_progress_distinguishes_pull_deployment_and_bundle_import() {
    let mut runtime = json!({"action":"install","downloadBytes":300,"phase":"download","downloadProgress":0.5,"receivedBytes":100});
    let mut app = json!({"action":"install","downloadBytes":100,"phase":"waiting"});
    let stages = |r: &Value, a: &Value, phase| progress::stages(&[r.clone(), a.clone()], phase);
    let result = stages(&runtime, &app, "download");
    assert_eq!(result["downloadProgress"], 0.375);
    assert!((result["progress"].as_f64().unwrap() - 0.3375).abs() < 1e-9);
    assert_eq!(result["downloadTotalBytes"], 400);
    runtime["phase"] = "install".into();
    runtime["downloadProgress"] = 1.into();
    runtime["receivedBytes"] = 200.into();
    let result = stages(&runtime, &app, "install");
    assert_eq!(result["downloadTotalBytes"], 300);
    assert_eq!(result["installCompleted"], 0);
    assert_eq!(result["downloadComplete"], false);
    runtime["phase"] = "complete".into();
    app["phase"] = "download".into();
    app["downloadProgress"] = 0.5.into();
    app["estimating"] = true.into();
    let result = stages(&runtime, &app, "download");
    assert_eq!(result["downloadProgress"], 0.875);
    assert_eq!(result["downloadEstimating"], true);
    app["phase"] = "install".into();
    app["downloadProgress"] = 1.into();
    app["receivedBytes"] = 80.into();
    let result = stages(&runtime, &app, "install");
    assert_eq!(result["downloadComplete"], true);
    assert_eq!(result["installCompleted"], 1);
    assert!((result["progress"].as_f64().unwrap() - 0.95).abs() < 1e-9);
    assert_eq!(result["downloadTotalBytes"], result["receivedBytes"]);
    app["phase"] = "complete".into();
    assert_eq!(stages(&runtime, &app, "complete")["progress"], 0.99);
    app["phase"] = "install".into();
    app["action"] = "install-bundle".into();
    app["progress"] = 0.5.into();
    let result = progress::stages(&[app.clone()], "install");
    assert_eq!(result["progress"], 0.45);
    assert_eq!(result["receivedBytes"], 0);
    assert_eq!(result["downloadComplete"], true);
    assert_eq!(stages(&runtime, &app, "install")["downloadTotalBytes"], 200);
    runtime["receivedBytes"] = 0.into();
    assert_eq!(stages(&runtime, &app, "install")["hasDownload"], false);
    assert_eq!(progress::stages(&[], "preparing")["progress"], 0.0);
    let mut rate = progress::DownloadRate::default();
    assert_eq!(rate.sample(0, 0, false), 0.0);
    assert_eq!(rate.sample(500, 0, true), 0.0);
    assert_eq!(rate.sample(1000, 1000000, true), 2000000.0);
    assert_eq!(rate.sample(1500, 2000000, true), 2000000.0);
    for t in [2000, 2500, 3000] {
        rate.sample(t, 2000000, true);
    }
    assert_eq!(rate.sample(3500, 2000000, true), 0.0);
    assert_eq!(rate.sample(3600, 2000000, false), 0.0);
    assert_eq!(rate.sample(5000, 2000000, true), 0.0);
    assert_eq!(rate.sample(5500, 2500000, true), 1000000.0);
    assert_eq!(rate.sample(5500, 2500000, true), 1000000.0);
    assert_eq!(rate.sample(6000, 0, true), 0.0);
    assert_eq!(rate.sample(100, 0, true), 0.0);
}

#[test]
fn source_mirroring_preserves_policy_user_overrides_and_identity() {
    source_mirror_contract(&[]);
    // A public repository key can extend this offline test to signed remotes.
    if let Some(path) = std::env::var_os("APPCENTER_TEST_PUBLIC_KEY") {
        source_mirror_contract(&std::fs::read(path).unwrap());
    }
}
fn source_mirror_contract(keys: &[u8]) {
    let temp = tempfile::tempdir().unwrap();
    let make = |name| {
        Installation::for_path(
            &gio::File::for_path(temp.path().join(name)),
            true,
            gio::Cancellable::NONE,
        )
        .unwrap()
    };
    let user = make("user");
    let system = make("system");
    let cancel = gio::Cancellable::new();
    let add = |name, url, disabled| {
        let remote = Remote::new(name);
        remote.set_url(url);
        remote.set_gpg_verify(!keys.is_empty());
        if !keys.is_empty() {
            remote.set_gpg_key(&glib::Bytes::from_owned(keys.to_vec()));
        }
        remote.set_disabled(disabled);
        remote.set_noenumerate(true);
        remote.set_nodeps(true);
        remote.set_default_branch("testing");
        system
            .modify_remote(&remote, gio::Cancellable::NONE)
            .unwrap();
        system.remote_by_name(name, gio::Cancellable::NONE).unwrap()
    };
    let original = add("source", "https://example.org/repo/", false);
    let before = std::fs::read(temp.path().join("system/repo/config")).unwrap();
    sources::mirror(&user, &system, &original, &cancel).unwrap();
    assert_eq!(
        std::fs::read(temp.path().join("system/repo/config")).unwrap(),
        before
    );
    let copy = user
        .remote_by_name("source", gio::Cancellable::NONE)
        .unwrap();
    assert_eq!(sources::url(&copy), sources::url(&original));
    assert_eq!(copy.is_gpg_verify(), !keys.is_empty());
    assert!(copy.is_noenumerate() && copy.is_nodeps());
    assert_eq!(
        sources::source_key(&user, &copy).unwrap(),
        sources::source_key(&system, &original).unwrap()
    );
    assert_eq!(copy.default_branch().as_deref(), Some("testing"));
    copy.set_disabled(true);
    user.modify_remote(&copy, gio::Cancellable::NONE).unwrap();
    let before = std::fs::read(temp.path().join("user/repo/config")).unwrap();
    sources::mirror(&user, &system, &original, &cancel).unwrap();
    assert_eq!(
        std::fs::read(temp.path().join("user/repo/config")).unwrap(),
        before
    );
    let conflict = add("source", "https://other.example.org/repo/", true);
    let alias = sources::user_name(&user, &system, &conflict);
    assert!(alias.starts_with("source-system-"));
    sources::mirror(&user, &system, &conflict, &cancel).unwrap();
    let aliased = user.remote_by_name(&alias, gio::Cancellable::NONE).unwrap();
    assert!(aliased.is_disabled());
    assert_eq!(
        sources::source_key(&user, &aliased).unwrap(),
        sources::source_key(&system, &conflict).unwrap()
    );
    let expected = json!({"name":alias,"scope":"user","url":sources::url(&aliased),"sourceKey":sources::source_key(&user,&aliased).unwrap()});
    source_removal::matches(&user, &expected).unwrap();
    for (key, value) in [
        ("name", "../../repo"),
        ("url", "https://changed.example/repo/"),
        ("sourceKey", "changed"),
    ] {
        let mut forged = expected.clone();
        forged[key] = value.into();
        assert!(source_removal::matches(&user, &forged).is_err());
    }
    let target = source_removal::Target {
        installation: user.clone(),
        expected,
    };
    source_removal::remove(&target, None).unwrap();
    assert!(user.remote_by_name(&alias, gio::Cancellable::NONE).is_err());
    assert!(system
        .remote_by_name("source", gio::Cancellable::NONE)
        .is_ok());
    let missing = Remote::new("missing-keys");
    missing.set_url("https://example.org/missing/");
    missing.set_gpg_verify(true);
    system
        .modify_remote(&missing, gio::Cancellable::NONE)
        .unwrap();
    assert!(sources::mirror(&user, &system, &missing, &cancel).is_err());
    assert!(user
        .remote_by_name("missing-keys", gio::Cancellable::NONE)
        .is_err());
}
