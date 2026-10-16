use super::*;
impl Manager {
    pub(super) fn request_screenshots(&mut self, urls: &Value) -> u64 {
        self.cancel_screenshots(self.image_token);
        self.image_token += 1;
        let mut files = Map::new();
        for source in rows(urls)
            .iter()
            .filter_map(Value::as_str)
            .filter(|s| super::super::images::valid_url(s))
            .take(16)
        {
            if files.contains_key(source) {
                continue;
            }
            files.insert(source.into(), json!({"state":"loading","source":""}));
            self.pending_images.push_back(source.into());
        }
        self.set("screenshotFiles", files.into());
        self.start_images();
        self.image_token
    }
    pub(super) fn cancel_screenshots(&mut self, token: u64) {
        if token != self.image_token {
            return;
        }
        self.pending_images.clear();
        for role in ["image0", "image1"] {
            self.cancel_reader(role);
        }
        self.set("screenshotFiles", json!({}));
    }
    fn start_images(&mut self) {
        if self.stopping {
            return;
        }
        for role in ["image0", "image1"] {
            if self.tasks.contains_key(role) {
                continue;
            }
            let Some(url) = self.pending_images.pop_front() else {
                break;
            };
            self.worker(
                role,
                "--image-worker",
                json!({"url":url}),
                25000,
                16384,
                false,
                json!({"url":url}),
            );
        }
    }
    pub(super) fn image_finished(&mut self, context: Value, event: &Value) {
        let result: Value = serde_json::from_str(text(event, "stdout")).unwrap_or(Value::Null);
        let result = if success(event) && result["state"] == "ready" {
            result
        } else {
            json!({"state":"error","source":""})
        };
        let mut files = self.properties["screenshotFiles"].clone();
        files[text(&context, "url")] = result;
        self.set("screenshotFiles", files);
        self.start_images();
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn screenshot_jobs_are_bounded_cancelled_and_ignore_stale_results() {
        let mut manager = Manager::new(vec![]);
        manager.initial();
        let urls: Vec<_> = (0..200)
            .map(|i| format!("https://example.org/{i}.png"))
            .collect();
        let first = manager.dispatch("requestScreenshots", &json!([urls]));
        assert_eq!(
            first["state"]["screenshotFiles"].as_object().unwrap().len(),
            16
        );
        assert_eq!(
            first["commands"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|c| c["command"] == "start")
                .count(),
            2
        );
        let serial = manager.tasks["image0"].serial;
        let token = number(&first, "return");
        manager.dispatch(
            "requestScreenshots",
            &json!([["https://example.org/new.png"]]),
        );
        manager.dispatch("cancelScreenshots", &json!([token]));
        assert!(manager.tasks.contains_key("image0"));
        manager.dispatch(
            "event",
            &json!([{"kind":"finished","role":"image0","serial":serial,"code":0,"stdout":"{}"}]),
        );
        assert_eq!(
            manager.properties["screenshotFiles"]
                .as_object()
                .unwrap()
                .len(),
            1
        );
        manager.dispatch("cancelScreenshots", &json!([manager.image_token]));
        assert!(manager.pending_images.is_empty());
        assert!(!manager.tasks.contains_key("image0"));
    }
}
