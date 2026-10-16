//! Test-only probe, never installed or linked into the application executable.
use flufflinux_appcenter::backend::{progress, sizes, source_removal, sources};
use gio::prelude::*;
use libflatpak::prelude::*;
use serde_json::json;
fn main() {
    let args: Vec<_> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("sizes") => {
            let start = std::time::Instant::now();
            let mut result = sizes::local(&json!({"id":args.get(2),"remote":"flathub"}));
            result["elapsedMs"] = (start.elapsed().as_millis() as u64).into();
            let stages = progress::stages(
                &[
                    json!({"action":"install","downloadBytes":result["appBytes"],"downloadProgress":0.5}),
                ],
                "download",
            );
            result["singleAppProgressTotal"] = stages["downloadTotalSize"].clone();
            println!("{result}");
        }
        Some("remove") => {
            // Only temporary offline fixture repositories are accepted here.
            let root = std::env::var("APPCENTER_REMOVAL_FIXTURE").unwrap();
            assert!(
                root.starts_with("/tmp/appcenter-remove-used-")
                    && std::path::Path::new(&root).is_dir()
            );
            for key in [
                "FLATPAK_USER_DIR",
                "FLATPAK_SYSTEM_DIR",
                "FLATPAK_CONFIG_DIR",
            ] {
                assert!(std::env::var(key).unwrap().starts_with(&format!("{root}/")));
            }
            let scope = args.get(2).unwrap();
            let members: Vec<_> = sources::list()
                .into_iter()
                .filter(|s| s["name"] == "fixture" && (scope == "merged" || s["scope"] == *scope))
                .collect();
            assert_eq!(members.len(), if scope == "merged" { 3 } else { 1 });
            let user = sources::installation("user").unwrap();
            let targets = source_removal::resolve(
                Some(&user),
                &members,
                scope != "user" && scope != "merged",
            )
            .unwrap();
            for target in targets {
                let error = target
                    .installation
                    .remove_remote("fixture", gio::Cancellable::NONE)
                    .unwrap_err();
                assert!(error.matches(libflatpak::Error::RemoteUsed));
                let mut stale = target.expected.clone();
                stale["sourceKey"] = "stale".into();
                assert!(source_removal::matches(&target.installation, &stale).is_err());
                let cancel = gio::Cancellable::new();
                cancel.cancel();
                assert!(source_removal::remove(&target, Some(&cancel)).is_err());
                source_removal::matches(&target.installation, &target.expected).unwrap();
                source_removal::remove(&target, None).unwrap();
                assert!(source_removal::matches(&target.installation, &target.expected).is_err());
            }
        }
        _ => panic!("Use sizes APP_ID or remove FIXTURE_SCOPE"),
    }
}
