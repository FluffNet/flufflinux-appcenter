//! Explicit opt-in, offline fixture only. Never touches a desktop deployment.
use serde_json::{json, Value};
use std::{
    fs,
    io::{BufRead, BufReader},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::mpsc,
    time::Duration,
};

struct Fixture(PathBuf);
impl Fixture {
    fn command(&self, program: &str) -> Command {
        let mut command = Command::new(program);
        for (key, directory) in [
            ("FLATPAK_USER_DIR", "user"),
            ("FLATPAK_SYSTEM_DIR", "system"),
            ("FLATPAK_CONFIG_DIR", "config"),
            ("XDG_DATA_HOME", "data"),
            ("XDG_CACHE_HOME", "cache"),
            ("XDG_CONFIG_HOME", "settings"),
        ] {
            command.env(key, self.0.join(directory));
        }
        command
    }
    fn output(&self, program: &str, args: &[&str]) -> String {
        let mut command = self.command(program);
        command.args(args);
        let result = flufflinux_appcenter::backend::process::run(
            command,
            Duration::from_secs(60),
            4 * 1024 * 1024,
            None,
        )
        .unwrap();
        assert_eq!(result.code, 0, "{}", result.stderr);
        String::from_utf8(result.stdout).unwrap()
    }
    fn transaction(&self, binary: &str, request: &Value) -> Vec<Value> {
        struct Worker(Child);
        impl Drop for Worker {
            fn drop(&mut self) {
                let _ = self.0.kill();
                let _ = self.0.wait();
            }
        }
        let mut child = Worker(
            self.command(binary)
                .args(["--transaction-worker", &request.to_string()])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .spawn()
                .unwrap(),
        );
        let output = child.0.stdout.take().unwrap();
        let (send, receive) = mpsc::channel();
        let reader = std::thread::spawn(move || {
            for line in BufReader::new(output).lines() {
                let line = line.unwrap();
                if send
                    .send(serde_json::from_str::<Value>(&line).unwrap())
                    .is_err()
                {
                    break;
                }
            }
        });
        let mut events = vec![];
        loop {
            let event = receive
                .recv_timeout(Duration::from_secs(60))
                .expect("worker response deadline");
            let done = event["type"] == "result";
            assert_ne!(
                event["type"], "review",
                "Fixture must not request a new source"
            );
            events.push(event);
            if done {
                break;
            }
        }
        drop(child.0.stdin.take());
        // The reader is reaped by worker exit; do not wait on a stuck worker.
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while child.0.try_wait().unwrap().is_none() {
            assert!(std::time::Instant::now() < deadline, "worker exit deadline");
            std::thread::sleep(Duration::from_millis(10));
        }
        reader.join().unwrap();
        events
    }
}

#[test]
#[ignore = "requires an explicit untouched offline update fixture"]
fn missing_download_payload_fails_after_progress_and_can_retry() {
    let root = PathBuf::from(std::env::var("APPCENTER_UPDATE_FIXTURE").unwrap())
        .canonicalize()
        .unwrap();
    assert!(
        root.starts_with("/tmp")
            && root
                .file_name()
                .unwrap()
                .to_str()
                .unwrap()
                .starts_with("appcenter-")
    );
    let fixture = Fixture(root);
    let manifest: Value =
        serde_json::from_slice(&fs::read(fixture.0.join("manifest.json")).unwrap()).unwrap();
    assert_eq!(manifest["fixture"], "appcenter-updates-v1");
    let binary = std::env::var("APPCENTER_TEST_BINARY").unwrap();
    let scan = fixture.output(&binary, &["--updates-worker", "{\"userOnly\":true}"]);
    let scan: Value = serde_json::from_str(scan.lines().last().unwrap()).unwrap();
    let mut request = scan["updates"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["id"] == "org.flufflinux.UpdateFixtureAlpha")
        .unwrap()
        .clone();
    request["action"] = json!("update");
    let reference = request["flatpakRef"].as_str().unwrap();
    let repo = format!("--repo={}", fixture.0.join("repo").display());
    let listing = fixture.output(
        "ostree",
        &[&repo, "ls", "--checksum", reference, "/files/bin/fixture"],
    );
    let checksum = listing
        .split_whitespace()
        .find(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit()))
        .unwrap();
    let payload = fixture.0.join(format!(
        "repo/objects/{}/{}.filez",
        &checksum[..2],
        &checksum[2..]
    ));
    let saved = fixture.0.join("withheld-test-payload.filez");
    assert!(payload.is_file() && !saved.exists());
    struct Restore(PathBuf, PathBuf);
    impl Drop for Restore {
        fn drop(&mut self) {
            fs::rename(&self.1, &self.0).expect("restore test payload");
        }
    }
    fs::rename(&payload, &saved).unwrap();
    let restore = Restore(payload, saved);
    let failed = fixture.transaction(&binary, &request);
    assert!(
        failed.iter().any(|event| event["type"] == "operation"),
        "Failure must occur after progress starts"
    );
    assert_eq!(failed.last().unwrap()["success"], false);
    let current = fixture.output("flatpak", &["info", "--user", "--show-commit", reference]);
    assert_eq!(current.trim(), request["oldCommit"].as_str().unwrap());
    drop(restore);
    let retry = fixture.transaction(&binary, &request);
    assert_eq!(retry.last().unwrap()["success"], true, "{retry:?}");
    assert_eq!(
        fixture
            .output("flatpak", &["info", "--user", "--show-commit", reference])
            .trim(),
        request["commit"].as_str().unwrap()
    );
}
