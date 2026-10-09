use super::*;
use std::{collections::HashSet, path::PathBuf};
fn link_id(source: &str) -> Option<String> {
    let url = url::Url::parse(source).ok()?;
    if !matches!(url.scheme(), "appstream" | "flatpak")
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return None;
    }
    let id = percent_encoding::percent_decode_str(source.split_once(':')?.1)
        .decode_utf8()
        .ok()?;
    let id = id.strip_prefix("//").unwrap_or(&id);
    let id = id.strip_suffix('/').unwrap_or(id);
    if !id.contains('.')
        || id.is_empty()
        || !id.as_bytes()[0].is_ascii_alphanumeric() && id.as_bytes()[0] != b'_'
        || !id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-' | b'.'))
    {
        return None;
    }
    Some(id.into())
}
impl Manager {
    pub(super) fn open_installed(&mut self, source: &str) {
        let source = source.trim();
        if source.len() > 8192
            || !source
                .split_once(':')
                .is_some_and(|(scheme, _)| scheme.eq_ignore_ascii_case("appstream"))
            || link_id(source).is_none()
            || self.pending_installed_links.len() >= 16
        {
            self.signal("homeRequested", json!([]));
            return;
        }
        self.pending_installed_links.push(source.into());
        self.refresh_installed();
    }
    pub(super) fn drain_links(&mut self) {
        if !flag(&self.properties, "installedLoading") {
            for source in std::mem::take(&mut self.pending_installed_links) {
                let id = link_id(&source).unwrap_or_default();
                let id = normalized_id(&id);
                let mut matching = None;
                let mut folded = HashSet::new();
                if text(&self.properties, "installedError").is_empty() {
                    for app in rows(&self.properties["installedApps"]) {
                        let candidate = normalized_id(text(app, "id"));
                        if candidate == id {
                            matching = Some(app.clone());
                            folded = HashSet::from([candidate.to_owned()]);
                            break;
                        }
                        if candidate.eq_ignore_ascii_case(id) {
                            folded.insert(candidate.to_owned());
                            if matching.is_none() {
                                matching = Some(app.clone());
                            }
                        }
                    }
                }
                if folded.len() == 1 {
                    if let Some(app) = matching {
                        self.signal("appOpened", json!([app]));
                        continue;
                    }
                }
                self.signal("homeRequested", json!([]));
            }
        }
        if self.tasks.contains_key("sources")
            || self.catalog.pending
            || self.catalog.awaiting
            || self.tasks.contains_key("catalog")
            || flag(&self.properties, "installedLoading")
        {
            return;
        }
        for source in std::mem::take(&mut self.pending_links) {
            self.open_source(&source);
        }
    }
    pub(super) fn open_source(&mut self, source: &str) {
        let source = source.trim();
        if source.is_empty() || source.len() > 8192 {
            self.error("Invalid Flatpak link or filename.");
            return;
        }
        if self.tasks.contains_key("sources") {
            if self.pending_inputs.len() < 16 {
                self.pending_inputs.push(source.into());
            } else {
                self.error("Too many files are waiting for software sources to finish updating.");
            }
            return;
        }
        let url = url::Url::parse(source).ok();
        let scheme = url.as_ref().map(|u| u.scheme()).unwrap_or("");
        if matches!(scheme, "appstream" | "flatpak") {
            let Some(id) = link_id(source) else {
                self.error("Use an appstream: or flatpak: link containing an application ID only.");
                return;
            };
            if self.catalog.pending
                || self.catalog.awaiting
                || self.tasks.contains_key("catalog")
                || flag(&self.properties, "installedLoading")
            {
                if self.pending_links.len() < 16 {
                    self.pending_links.push(source.into());
                } else {
                    self.error("Too many applications are waiting for the catalog to load.");
                }
                return;
            }
            let normalized = normalized_id(&id);
            if let Some(app) = rows(&self.properties["installedApps"])
                .iter()
                .find(|app| normalized_id(text(app, "id")) == normalized)
                .cloned()
            {
                self.signal("appOpened", json!([app]));
                return;
            }
            if self.metadata.contains_key(normalized) {
                self.signal("appOpened", json!([self.metadata(normalized)]));
                return;
            }
            let matches: HashSet<_> = self
                .metadata
                .keys()
                .map(String::as_str)
                .chain(
                    rows(&self.properties["installedApps"])
                        .iter()
                        .map(|app| normalized_id(text(app, "id"))),
                )
                .filter(|candidate| candidate.eq_ignore_ascii_case(normalized))
                .map(String::from)
                .collect();
            if matches.len() == 1 {
                let canonical = matches.iter().next().unwrap();
                let app = rows(&self.properties["installedApps"])
                    .iter()
                    .find(|app| normalized_id(text(app, "id")) == canonical)
                    .cloned()
                    .unwrap_or_else(|| self.metadata(canonical));
                self.signal("appOpened", json!([app]));
                return;
            }
            self.error(if matches.len()>1{format!("More than one app matches {id}. Open App Center and choose the app.")}else{format!("No matching Flatpak was found for {id}. App Center manages Flatpak apps, not system packages.")});
            return;
        }
        if !matches!(scheme, "" | "file" | "https" | "flatpak+https") {
            self.error(
                "Use an appstream: app link, a local Flatpak file, or an HTTPS Flatpak link.",
            );
            return;
        }
        let mut source = source.to_owned();
        if matches!(scheme, "" | "file") {
            let path = if let Some(url) = url.as_ref() {
                url.to_file_path().ok()
            } else {
                Some(PathBuf::from(&source))
            };
            let Some(path) = path.filter(|path| {
                path.is_file()
                    && path
                        .extension()
                        .and_then(|s| s.to_str())
                        .is_some_and(|ext| {
                            matches!(
                                ext.to_ascii_lowercase().as_str(),
                                "flatpak" | "flatpakref" | "flatpakrepo"
                            )
                        })
            }) else {
                self.error("Choose a readable .flatpak, .flatpakref or .flatpakrepo file.");
                return;
            };
            let path = if path.is_absolute() {
                path
            } else {
                std::env::current_dir().unwrap_or_default().join(path)
            };
            let Ok(url) = url::Url::from_file_path(path) else {
                self.error("Invalid Flatpak filename.");
                return;
            };
            source = url.to_string();
        }
        let name = url::Url::parse(&source)
            .ok()
            .and_then(|url| {
                url.path_segments()
                    .and_then(|mut parts| parts.next_back())
                    .map(String::from)
            })
            .unwrap_or_default();
        self.enqueue(json!({"action":"source","source":source,"name":name,"installation":"user","prepareOnly":true,"hidden":true}));
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn links_preserve_case_and_reject_extra_commands() {
        assert_eq!(
            link_id("appstream://org.Test.App"),
            Some("org.Test.App".into())
        );
        assert_eq!(
            link_id("flatpak:org.Test.App.desktop"),
            Some("org.Test.App.desktop".into())
        );
        for link in [
            "appstream:org.Test.App?install=true",
            "appstream:org.Test.App#x",
            "appstream://org.Test.App/a",
            "appstream:%2fbin%2fsh",
        ] {
            assert!(link_id(link).is_none());
        }
    }
}
