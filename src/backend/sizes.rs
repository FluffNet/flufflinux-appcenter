//! Local metadata only. Size inspection never refreshes a source or resolves a
//! network transaction, and missing dependency metadata stays unknown.
use super::{bytes, normalized_id, process, sources, text};
use gio::prelude::*;
use libflatpak::{prelude::*, Installation, QueryFlags, RefKind, RemoteRef};
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet},
    path::Path,
};
struct Source {
    name: String,
    url: String,
    refs: HashMap<String, RemoteRef>,
}
struct Lookup {
    sources: Vec<Source>,
    installed: HashSet<String>,
    user_installed: HashSet<String>,
    visited: HashSet<String>,
    drivers: Option<Vec<String>>,
    theme: String,
    complete: bool,
    total: u64,
}
fn setting(key: &glib::KeyFile, group: &str, name: &str) -> String {
    key.string(group, name).unwrap_or_default().into()
}
fn base(reference: &str) -> String {
    reference.split('/').take(3).collect::<Vec<_>>().join("/")
}
impl Lookup {
    fn load(&mut self, installation: &Installation) {
        for reference in installation
            .list_installed_refs(gio::Cancellable::NONE)
            .unwrap_or_default()
        {
            let reference = reference.format_ref().unwrap_or_default().to_string();
            self.installed.insert(reference.clone());
            if installation.is_user() {
                self.user_installed.insert(base(&reference));
            }
        }
        for remote in installation
            .list_remotes(gio::Cancellable::NONE)
            .unwrap_or_default()
        {
            if remote.is_disabled() {
                continue;
            }
            let name = sources::name(&remote);
            let url = sources::url(&remote);
            if self
                .sources
                .iter()
                .any(|source| source.name == name && (source.url != url || !source.refs.is_empty()))
            {
                continue;
            }
            let refs = installation
                .list_remote_refs_sync_full(&name, QueryFlags::ONLY_CACHED, gio::Cancellable::NONE)
                .unwrap_or_default()
                .into_iter()
                .map(|r| (r.format_ref().unwrap_or_default().to_string(), r))
                .collect();
            self.sources.push(Source { name, url, refs });
        }
    }
    fn matches(&mut self, id: &str, reasons: &str, fallback: bool) -> bool {
        if reasons.is_empty() {
            return fallback;
        }
        let suffix = id.rsplit('.').next().unwrap_or("");
        for reason in reasons.split(';').filter(|s| !s.is_empty()) {
            match reason {
                "active-gl-driver" => {
                    if self.drivers.is_none() {
                        self.drivers = Some(match process::flatpak(&["--gl-drivers"], 1, None) {
                            Ok(output) if output.code == 0 => {
                                String::from_utf8_lossy(&output.stdout)
                                    .split_whitespace()
                                    .map(String::from)
                                    .collect()
                            }
                            _ => {
                                self.complete = false;
                                vec![]
                            }
                        });
                    }
                    if self
                        .drivers
                        .as_ref()
                        .is_some_and(|drivers| drivers.iter().any(|driver| driver == suffix))
                    {
                        return true;
                    }
                }
                "active-gtk-theme" => {
                    if self.theme == suffix {
                        return true;
                    }
                }
                "have-intel-gpu" => {
                    if Path::new("/sys/module/i915").exists()
                        || Path::new("/sys/module/xe").exists()
                    {
                        return true;
                    }
                }
                _ => {
                    if let Some(module) = reason.strip_prefix("have-kernel-module-") {
                        if !module.contains('/') && Path::new("/sys/module").join(module).exists() {
                            return true;
                        }
                    } else if let Some(desktop) = reason.strip_prefix("on-xdg-desktop-") {
                        if std::env::var("XDG_CURRENT_DESKTOP")
                            .unwrap_or_default()
                            .split(':')
                            .any(|name| name.eq_ignore_ascii_case(desktop))
                        {
                            return true;
                        }
                    } else {
                        self.complete = false;
                    }
                }
            }
        }
        false
    }
    fn add(&mut self, reference: &str, source: usize, app: bool) {
        if (!app && self.installed.contains(reference)) || !self.visited.insert(reference.into()) {
            return;
        }
        if self.visited.len() > 256 {
            self.complete = false;
            return;
        }
        let Some(remote) = self.sources[source].refs.get(reference) else {
            self.complete = false;
            return;
        };
        let Some(metadata) = remote.metadata() else {
            self.complete = false;
            return;
        };
        self.total = self.total.saturating_add(remote.download_size());
        let key = glib::KeyFile::new();
        if metadata.len() > 1024 * 1024
            || std::str::from_utf8(metadata.as_ref())
                .ok()
                .is_none_or(|data| key.load_from_data(data, glib::KeyFileFlags::NONE).is_err())
        {
            self.complete = false;
            return;
        }
        if app {
            let runtime = setting(&key, "Application", "runtime");
            let runtime = format!("runtime/{runtime}");
            if runtime != "runtime/" && !self.installed.contains(&runtime) {
                let candidate = if self.sources[source].refs.contains_key(&runtime) {
                    Some(source)
                } else {
                    self.sources
                        .iter()
                        .position(|s| s.refs.contains_key(&runtime))
                };
                if let Some(index) = candidate {
                    self.add(&runtime, index, false);
                } else {
                    self.complete = false;
                }
            }
        }
        let parts: Vec<_> = reference.split('/').collect();
        if parts.len() != 4 {
            self.complete = false;
            return;
        }
        for group in key.groups().iter() {
            let Some(extension) = group
                .strip_prefix("Extension ")
                .map(|id| id.split('@').next().unwrap_or(""))
            else {
                continue;
            };
            if extension.ends_with(".Debug") {
                continue;
            }
            let version_list = setting(&key, group, "versions");
            let mut versions: Vec<_> = version_list
                .split(';')
                .filter(|s| !s.is_empty())
                .map(String::from)
                .collect();
            if versions.is_empty() {
                let version = setting(&key, group, "version");
                versions.push(if version.is_empty() {
                    parts[3].into()
                } else {
                    version
                });
            }
            let subdirs = key.boolean(group, "subdirectories").unwrap_or(false);
            let auto = !key.boolean(group, "no-autodownload").unwrap_or(false);
            let reasons = setting(&key, group, "download-if");
            for version in versions {
                let tail = format!("/{}/{version}", parts[2]);
                let exact = format!("runtime/{extension}{tail}");
                let candidates: Vec<_> = if self.sources[source].refs.contains_key(&exact) {
                    vec![exact]
                } else if subdirs {
                    self.sources[source]
                        .refs
                        .keys()
                        .filter(|r| {
                            r.starts_with(&format!("runtime/{extension}."))
                                && r.ends_with(&tail)
                                && r.split('/')
                                    .nth(1)
                                    .is_some_and(|id| !id[extension.len() + 1..].contains('.'))
                        })
                        .cloned()
                        .collect()
                } else {
                    vec![]
                };
                for candidate in candidates {
                    if !self.installed.contains(&candidate)
                        && (self.user_installed.contains(&base(&candidate))
                            || self.matches(
                                candidate.split('/').nth(1).unwrap_or(""),
                                &reasons,
                                auto,
                            ))
                    {
                        self.add(&candidate, source, false);
                    }
                }
            }
        }
    }
}
pub fn installed(app: &Value) -> Option<u64> {
    let scope = text(app, "installation");
    let id = normalized_id(text(app, "id"));
    let arch = text(app, "installedArch");
    let branch = text(app, "installedBranch");
    if [scope, id, arch, branch].iter().any(|s| s.is_empty()) {
        return None;
    }
    sources::installation(scope)
        .ok()?
        .installed_ref(
            RefKind::App,
            id,
            Some(arch),
            Some(branch),
            gio::Cancellable::NONE,
        )
        .ok()
        .map(|r| r.installed_size())
}
pub fn local(request: &Value) -> Value {
    let mut lookup = Lookup {
        sources: vec![],
        installed: HashSet::new(),
        user_installed: HashSet::new(),
        visited: HashSet::new(),
        drivers: None,
        theme: String::new(),
        complete: true,
        total: 0,
    };
    for installation in sources::installations().unwrap_or_default() {
        lookup.load(&installation);
    }
    if let Some(schema) = gio::SettingsSchemaSource::default()
        .and_then(|s| s.lookup("org.gnome.desktop.interface", true))
        .filter(|s| s.has_key("gtk-theme"))
    {
        lookup.theme = gio::Settings::new_full(&schema, None::<&gio::SettingsBackend>, None)
            .string("gtk-theme")
            .into();
    }
    let remote = if text(request, "remote").is_empty() {
        "flathub"
    } else {
        text(request, "remote")
    };
    let reference = if text(request, "flatpakRef").is_empty() {
        format!(
            "app/{}/{}/stable",
            text(request, "id"),
            libflatpak::default_arch().unwrap_or_default()
        )
    } else {
        text(request, "flatpakRef").into()
    };
    for index in 0..lookup.sources.len() {
        let source = &lookup.sources[index];
        if source.name != remote
            || (!text(request, "sourceUrl").is_empty() && source.url != text(request, "sourceUrl"))
        {
            continue;
        }
        let Some(app) = source.refs.get(&reference) else {
            continue;
        };
        if app.metadata().is_none() {
            break;
        }
        let app_bytes = app.download_size();
        lookup.add(&reference, index, true);
        let mut result = json!({"state":if lookup.complete{"ready"}else{"partial"},"appBytes":app_bytes,"appSize":bytes(app_bytes)});
        if lookup.complete {
            result["totalBytes"] = lookup.total.into();
            result["totalSize"] = bytes(lookup.total).into();
        }
        return result;
    }
    json!({"state":"unavailable"})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn record(lookup: &mut Lookup, reference: &str, size: u64, metadata: &str) {
        let parts: Vec<_> = reference.split('/').collect();
        let remote = RemoteRef::builder()
            .name(parts[1])
            .arch(parts[2])
            .branch(parts[3])
            .kind(if parts[0] == "app" {
                RefKind::App
            } else {
                RefKind::Runtime
            })
            .download_size(size)
            .metadata(&glib::Bytes::from_owned(metadata.as_bytes().to_vec()))
            .build();
        lookup.sources[0].refs.insert(reference.into(), remote);
    }
    fn calculate(lookup: &mut Lookup) {
        lookup.total = 0;
        lookup.complete = true;
        lookup.visited.clear();
        lookup.add("app/org.example.App/x86_64/stable", 0, true);
    }
    #[test]
    fn local_dependency_sizes_handle_shared_installed_missing_and_graphics_extensions() {
        let app = "app/org.example.App/x86_64/stable";
        let runtime = "runtime/org.example.Platform/x86_64/1";
        let locale = "runtime/org.example.App.Locale/x86_64/stable";
        let mut lookup = Lookup {
            sources: vec![Source {
                name: "fixture".into(),
                url: "https://example.org".into(),
                refs: HashMap::new(),
            }],
            installed: HashSet::new(),
            user_installed: HashSet::new(),
            visited: HashSet::new(),
            drivers: Some(vec!["default".into()]),
            theme: String::new(),
            complete: true,
            total: 0,
        };
        record(&mut lookup,app,100,"[Application]\nruntime=org.example.Platform/x86_64/1\n[Extension org.example.App.Locale]\n[Extension org.example.App.Debug]\nno-autodownload=true\n");
        record(
            &mut lookup,
            runtime,
            400,
            "[Runtime]\nname=org.example.Platform\n",
        );
        record(
            &mut lookup,
            locale,
            10,
            "[Runtime]\nname=org.example.App.Locale\n",
        );
        record(
            &mut lookup,
            "runtime/org.example.App.Debug/x86_64/stable",
            2000,
            "[Runtime]\nname=org.example.App.Debug\n",
        );
        calculate(&mut lookup);
        assert!(lookup.complete);
        assert_eq!(lookup.total, 510);
        lookup.installed.insert(runtime.into());
        calculate(&mut lookup);
        assert_eq!(lookup.total, 110);
        lookup.installed.insert(locale.into());
        calculate(&mut lookup);
        assert_eq!(lookup.total, 100);
        lookup.installed.clear();
        lookup.sources[0].refs.remove(runtime);
        calculate(&mut lookup);
        assert!(!lookup.complete);
        record(
            &mut lookup,
            runtime,
            400,
            "[Runtime]\n[Extension org.example.App.Locale]\nversion=stable\n",
        );
        calculate(&mut lookup);
        assert!(lookup.complete);
        assert_eq!(lookup.total, 510);
        record(&mut lookup,app,100,"[Application]\n[Extension org.example.GL]\nsubdirectories=true\nno-autodownload=true\ndownload-if=active-gl-driver\n");
        record(
            &mut lookup,
            "runtime/org.example.GL.default/x86_64/stable",
            20,
            "[Runtime]\nname=org.example.GL.default\n",
        );
        record(
            &mut lookup,
            "runtime/org.example.GL.nvidia-old/x86_64/stable",
            500,
            "[Runtime]\nname=org.example.GL.nvidia-old\n",
        );
        record(
            &mut lookup,
            "runtime/org.example.GL.Debug.default/x86_64/stable",
            2000,
            "[Runtime]\nname=org.example.GL.Debug.default\n",
        );
        calculate(&mut lookup);
        assert!(lookup.complete);
        assert_eq!(lookup.total, 120);
        record(&mut lookup,app,100,"[Application]\n[Extension org.example.GL]\nsubdirectories=true\ndownload-if=future-rule\n");
        calculate(&mut lookup);
        assert!(!lookup.complete);
        assert!(installed(&json!({})).is_none());
        assert!(installed(&json!({"id":"org.example.App","installation":"user"})).is_none());
    }
}
