use super::{bytes, flag, number, rows, text};
use serde_json::{json, Value};
use std::collections::VecDeque;

fn fraction(value: &Value, key: &str) -> f64 {
    value[key].as_f64().unwrap_or(0.0).clamp(0.0, 1.0)
}

pub fn stages(operations: &[Value], phase: &str) -> Value {
    let mut local = 0.0;
    let (mut received, mut total_bytes, mut app_bytes) = (0u64, 0u64, 0u64);
    let (mut complete, mut total) = (0, 0);
    let (mut pending, mut estimating, mut has_app, mut bundle) = (false, false, false, false);
    for op in operations {
        total += 1;
        let done = text(op, "phase") == "complete";
        if done {
            complete += 1;
        }
        if text(op, "action") == "uninstall" {
            continue;
        }
        if text(op, "action") == "install-bundle" {
            bundle = true;
            local += if done {
                1.0
            } else {
                fraction(op, "progress").min(0.99)
            };
            continue;
        }
        let transferred = number(op, "receivedBytes");
        received = received.saturating_add(transferred);
        // Flatpak's operation percentage includes metadata/object processing;
        // it is not the fraction of advertised bytes downloaded. Only a
        // deployment/completion event confirms the pull's final byte total.
        let pulled = done || text(op, "phase") == "install";
        let component = if pulled {
            transferred
        } else {
            transferred.max(number(op, "downloadBytes"))
        };
        total_bytes = total_bytes.saturating_add(component);
        if text(op, "ref").starts_with("app/") {
            has_app = true;
            app_bytes = app_bytes.saturating_add(component);
        }
        pending |= !pulled;
        estimating |= text(op, "phase") == "download" && flag(op, "estimating");
    }
    let download = if total_bytes > 0 {
        (received as f64 / total_bytes as f64).clamp(0.0, 1.0)
    } else {
        1.0
    };
    let install = if total > 0 {
        complete as f64 / total as f64
    } else {
        0.0
    };
    let transfer = if total_bytes > 0 {
        download
    } else if total > 0 {
        local / total as f64
    } else {
        0.0
    };
    // Deployment has no reliable byte-based percentage. Present its status
    // with one indeterminate bar until Flatpak acknowledges completion.
    let indeterminate = phase != "download" || total_bytes == 0;
    let progress = if indeterminate {
        transfer.min(0.99)
    } else {
        transfer
    };
    let mut result = json!({"phase":phase,"downloadProgress":download,"downloadEstimating":estimating,
        "receivedSize":bytes(received),"receivedBytes":received,"downloadTotalBytes":total_bytes,
        "downloadedSize":bytes(received),"downloadTotalSize":bytes(total_bytes),"hasDownload":total_bytes>0,
        "downloadComplete":!pending,"progress":progress,"progressPercent":percentage(progress),"progressIndeterminate":indeterminate,
        "installCompleted":complete,"installTotal":total,"installProgress":install});
    if has_app && !bundle {
        result["sizeInfo"] = json!({"state":"ready","appBytes":app_bytes,
        "totalBytes":total_bytes,"appSize":bytes(app_bytes),"totalSize":bytes(total_bytes)});
    }
    result
}
pub fn percentage(progress: f64) -> u64 {
    (progress.clamp(0.0, 1.0) * 100.0 + 0.000001).floor() as u64
}
#[derive(Default)]
pub struct DownloadRate {
    samples: VecDeque<(u64, u64)>,
    downloading: bool,
}
impl DownloadRate {
    pub fn sample(&mut self, millis: u64, bytes: u64, downloading: bool) -> f64 {
        if !downloading
            || !self.downloading
            || self
                .samples
                .back()
                .is_some_and(|&(time, count)| millis < time || bytes < count)
        {
            self.samples.clear();
            self.samples.push_back((millis, bytes));
            self.downloading = downloading;
            return 0.0;
        }
        if self.samples.back().is_some_and(|sample| sample.0 == millis) {
            self.samples.pop_back();
        }
        self.samples.push_back((millis, bytes));
        while self.samples.len() > 2 && self.samples[1].0 <= millis.saturating_sub(2000) {
            self.samples.pop_front();
        }
        let (time, count) = self.samples[0];
        if millis - time >= 100 {
            (bytes - count) as f64 * 1000.0 / (millis - time) as f64
        } else {
            0.0
        }
    }
    pub fn display(rate: f64) -> String {
        format!("{} MiB/s", super::locale::decimal(rate / 1048576.0))
    }
}
pub fn valid_commit(commit: &str) -> bool {
    commit.len() == 64
        && commit
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}
pub fn matches_plan(expected: &[Value], actual: &[Value]) -> bool {
    actual.iter().all(|op| {
        (if text(op, "action") == "uninstall" {
            valid_commit(text(op, "installedCommit"))
        } else {
            matches!(text(op, "action"), "install" | "update") && valid_commit(text(op, "commit"))
        }) && expected.iter().any(|row| {
            [
                "ref",
                "commit",
                "remote",
                "action",
                "installedCommit",
                "installedOrigin",
                "sourceUrl",
                "sourceKey",
            ]
            .iter()
            .all(|key| row[key] == op[key])
        })
    })
}
pub fn total_size(items: &[Value]) -> u64 {
    let mut seen = std::collections::HashSet::new();
    items
        .iter()
        .flat_map(|row| rows(&row["plan"]).iter().map(move |op| (row, op)))
        .filter(|(row, op)| {
            seen.insert(format!(
                "{}:{}:{}",
                text(row, "installation"),
                text(op, "ref"),
                text(op, "commit")
            ))
        })
        .map(|(_, op)| number(op, "downloadBytes"))
        .fold(0, u64::saturating_add)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pull_is_not_deployment() {
        let ops = [
            json!({"action":"install","ref":"app/a.b.C/x86_64/stable","downloadBytes":100,
            "receivedBytes":40,"downloadProgress":1,"phase":"install"}),
        ];
        let result = stages(&ops, "install");
        assert_eq!(result["downloadTotalBytes"], 40);
        assert!(flag(&result, "progressIndeterminate"));
        assert_eq!(result["progress"], 0.99);
        assert_eq!(result["installCompleted"], 0);
    }
    #[test]
    fn real_bytes_only_and_stall_decays() {
        let mut rate = DownloadRate::default();
        assert_eq!(rate.sample(0, 0, true), 0.0);
        assert_eq!(rate.sample(1000, 1000, true), 1000.0);
        rate.sample(2000, 1000, true);
        rate.sample(3000, 1000, true);
        assert_eq!(rate.sample(4000, 1000, true), 0.0);
        assert_eq!(rate.sample(5000, 1, true), 0.0);
    }
    #[test]
    fn cleanup_counts_as_work_but_never_as_download_bytes() {
        let mut ops = vec![
            json!({"action":"update","ref":"app/a.b.App/x86_64/stable",
            "downloadBytes":100,"receivedBytes":100,"downloadProgress":1,"phase":"complete"}),
            json!({"action":"uninstall","ref":"runtime/a.b.Old/x86_64/stable",
                "downloadBytes":999,"phase":"waiting"}),
        ];
        let stages_before = stages(&ops, "uninstall");
        assert_eq!(stages_before["installTotal"], 2);
        assert_eq!(stages_before["installCompleted"], 1);
        assert_eq!(stages_before["downloadTotalBytes"], 100);
        ops[1]["phase"] = "complete".into();
        assert_eq!(stages(&ops, "complete")["installCompleted"], 2);
    }
    #[test]
    fn reported_operation_percent_cannot_inflate_download_bytes() {
        for (received, total, percent) in [(2, 200, 1), (54, 200, 27), (0, 200, 0), (200, 200, 100)] {
            let op = json!({"ref":"app/a.b.App/x86_64/stable","action":"update",
                "downloadBytes":total,"receivedBytes":received,"downloadProgress":0.99,
                "progress":0.99,"phase":"download"});
            let result = stages(&[op], "download");
            assert_eq!(number(&result, "progressPercent"), percent);
            assert!(!flag(&result, "progressIndeterminate"));
            assert_eq!(number(&result, "downloadTotalBytes"), total);
            assert_eq!(number(&result, "receivedBytes"), received);
        }
    }
    #[test]
    fn cached_dependencies_and_actual_bytes_share_one_denominator() {
        let cached =
            json!({"action":"update","downloadBytes":500,"receivedBytes":0,"phase":"complete"});
        let active = json!({"action":"update","downloadBytes":200,"receivedBytes":54,
            "downloadProgress":0.95,"phase":"download"});
        let result = stages(&[cached, active], "download");
        assert_eq!(result["progressPercent"], 27);
        assert_eq!(result["downloadTotalBytes"], 200);
        assert!(!flag(&result, "downloadComplete"));
    }
    #[test]
    fn finished_pull_does_not_invent_deployment_percentage() {
        for phase in ["preparing", "install", "uninstall"] {
            let op =
                json!({"action":"update","downloadBytes":200,"receivedBytes":54,"phase":phase});
            let result = stages(&[op], phase);
            assert!(flag(&result, "progressIndeterminate"));
            assert!(result["progress"].as_f64().unwrap() < 1.0);
        }
        let result = stages(
            &[json!({"action":"install-bundle","phase":"install","progress":0.9})],
            "install",
        );
        assert!(flag(&result, "progressIndeterminate"));
        assert!(!flag(&result, "hasDownload"));
    }
    #[test]
    fn byte_total_increases_are_reflected_in_percentage_and_do_not_overflow() {
        let mut op =
            json!({"action":"update","downloadBytes":100,"receivedBytes":54,"phase":"download"});
        assert_eq!(stages(&[op.clone()], "download")["progressPercent"], 54);
        op["downloadBytes"] = 200.into();
        assert_eq!(stages(&[op], "download")["progressPercent"], 27);
        let huge = json!({"action":"update","downloadBytes":u64::MAX,"receivedBytes":u64::MAX,"phase":"download"});
        assert_eq!(
            stages(&[huge.clone(), huge], "download")["progressPercent"],
            100
        );
    }
    #[test]
    fn changed_commit_or_source_requires_new_review() {
        let row = json!({"ref":"app/a.b.C/x86_64/stable","commit":"a".repeat(64),"remote":"flathub","action":"update"});
        assert!(matches_plan(
            std::slice::from_ref(&row),
            std::slice::from_ref(&row)
        ));
        let mut changed = row.clone();
        changed["remote"] = "other".into();
        assert!(!matches_plan(std::slice::from_ref(&row), &[changed]));
        let mut changed = row.clone();
        changed["commit"] = "bad".into();
        assert!(!matches_plan(&[row], &[changed]));
    }
}
