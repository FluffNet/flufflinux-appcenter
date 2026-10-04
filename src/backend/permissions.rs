use super::{rows, text};
use glib::{KeyFile, KeyFileFlags};
use libflatpak::prelude::*;
use serde_json::{json, Value};

pub fn read(request: &Value) -> Value {
    let source = text(request, "source");
    let local = match url::Url::parse(source) {
        Ok(url) => url.to_file_path().ok(),
        Err(_) if !source.is_empty() => Some(std::path::PathBuf::from(source)),
        _ => None,
    };
    if let Some(path) = local.filter(|p| {
        p.extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("flatpak"))
            && p.is_file()
    }) {
        return match libflatpak::BundleRef::new(&gio::File::for_path(path))
            .ok()
            .and_then(|b| b.metadata())
        {
            Some(data) => parse(&data, false),
            None => error("Could not read this local Flatpak bundle."),
        };
    }
    let Ok(reference) = libflatpak::Ref::parse(text(request, "flatpakRef")) else {
        return error("Permission information is not available for this app source.");
    };
    let remote_name = text(request, "remote");
    let remote_url = text(request, "sourceUrl");
    if reference.kind() != libflatpak::RefKind::App
        || remote_name.is_empty()
        || remote_url.is_empty()
    {
        return error("Permission information is not available for this app source.");
    }
    let mut matching = Vec::new();
    for installation in super::sources::installations().unwrap_or_default() {
        let Ok(remote) = installation.remote_by_name(remote_name, gio::Cancellable::NONE) else {
            continue;
        };
        if super::sources::url(&remote) != remote_url {
            continue;
        }
        if let Ok(cached) = installation.fetch_remote_ref_sync_full(
            remote_name,
            reference.kind(),
            &reference.name().unwrap_or_default(),
            reference.arch().as_deref(),
            reference.branch().as_deref(),
            libflatpak::QueryFlags::ONLY_CACHED,
            gio::Cancellable::NONE,
        ) {
            if let Some(metadata) = cached.metadata().filter(|m| !m.is_empty()) {
                return parse(&metadata, false);
            }
        }
        if !remote.is_disabled() {
            matching.push(installation);
        }
    }
    for installation in matching {
        if let Ok(metadata) =
            installation.fetch_remote_metadata_sync(remote_name, &reference, gio::Cancellable::NONE)
        {
            if !metadata.is_empty() {
                return parse(&metadata, false);
            }
        }
    }
    error(
        "Could not read permissions from the selected source. Check your connection and try again.",
    )
}

pub fn error(message: &str) -> Value {
    json!({"state":"error","message":message})
}
fn sorted(mut values: Vec<String>) -> Vec<String> {
    values.sort_by_key(|s| s.to_lowercase());
    values.dedup();
    values
}
fn labeled(values: Vec<String>, labels: &[(&str, &str)]) -> Vec<String> {
    values
        .into_iter()
        .map(|value| {
            let name = value.strip_prefix('!').unwrap_or(&value);
            let label = labels
                .iter()
                .find(|(key, _)| *key == name)
                .map(|(_, label)| *label)
                .unwrap_or(name);
            if value.starts_with('!') {
                format!("{label} - denied")
            } else {
                label.to_owned()
            }
        })
        .collect()
}
pub fn parse(data: &[u8], installed: bool) -> Value {
    if data.len() > 1024 * 1024 {
        return error("The permission information is too large to display.");
    }
    let Ok(data) = std::str::from_utf8(data) else {
        return error("Flatpak returned invalid permission information.");
    };
    if data.contains('\0') {
        return error("Flatpak returned invalid permission information.");
    }
    let key = KeyFile::new();
    if !data.trim().is_empty() && key.load_from_data(data, KeyFileFlags::NONE).is_err() {
        return error("Flatpak returned invalid permission information.");
    }
    if !installed && !key.has_group("Application") {
        return error("The source did not provide application permission information.");
    }
    let invalid = std::cell::Cell::new(false);
    let list = |group: &str, name: &str| -> Vec<String> {
        if !key.has_key(group, name).unwrap_or(false) {
            return Vec::new();
        }
        match key.string_list(group, name) {
            Ok(values) => sorted(
                values
                    .iter()
                    .filter(|v| !v.is_empty())
                    .map(ToString::to_string)
                    .collect(),
            ),
            Err(_) => {
                invalid.set(true);
                Vec::new()
            }
        }
    };
    let mut groups = Vec::new();
    let mut add = |id: &str, title: &str, icon: &str, description: &str, details: Vec<String>| {
        if !details.is_empty() {
            groups.push(json!({"id":id,"title":title,"icon":icon,"description":description,"details":sorted(details)}));
        }
    };
    let shared = list("Context", "shared");
    let sockets = list("Context", "sockets");
    let subset = |values: &[String], names: &[&str]| {
        values
            .iter()
            .filter(|s| names.contains(&s.trim_start_matches('!')))
            .cloned()
            .collect()
    };
    add(
        "network",
        "Network Access",
        "network-wireless",
        "Internet and local network connections.",
        labeled(
            subset(&shared, &["network"]),
            &[("network", "Network connections")],
        ),
    );
    add(
        "audio",
        "Sound System Access",
        "audio-volume-high",
        "Audio playback and recording through the sound server.",
        labeled(
            subset(&sockets, &["pulseaudio"]),
            &[("pulseaudio", "Play and record audio")],
        ),
    );
    add(
        "devices",
        "Device Access",
        "computer",
        "Access to hardware devices outside the sandbox.",
        labeled(
            list("Context", "devices"),
            &[
                ("all", "All devices"),
                ("dri", "Graphics acceleration"),
                ("kvm", "Virtualization"),
                ("shm", "Shared device memory"),
                ("input", "Input devices"),
                ("usb", "USB devices"),
            ],
        ),
    );
    add(
        "display",
        "Display Access",
        "video-display",
        "Connections to the desktop display system.",
        labeled(
            subset(&sockets, &["wayland", "x11", "fallback-x11"]),
            &[
                ("wayland", "Wayland"),
                ("x11", "X11 - access to other X11 windows and input"),
                ("fallback-x11", "X11 when Wayland is unavailable"),
            ],
        ),
    );
    add(
        "ipc",
        "Shared Memory Access",
        "preferences-system",
        "Inter-process communication shared with the host session.",
        labeled(subset(&shared, &["ipc"]), &[("ipc", "Host IPC namespace")]),
    );
    let files = list("Context", "filesystems")
        .into_iter()
        .map(|path| {
            let denied = path.starts_with('!');
            let mut name = path.trim_start_matches('!');
            let mode = if name.ends_with(":ro") {
                name = &name[..name.len() - 3];
                "read only"
            } else if name.ends_with(":rw") {
                name = &name[..name.len() - 3];
                "read and write"
            } else if name.ends_with(":create") {
                name = &name[..name.len() - 7];
                "read, write and create"
            } else {
                "read and write"
            };
            let names = [
                ("host", "Host files"),
                ("home", "Home folder"),
                ("host-os", "Operating system files"),
                ("host-etc", "System configuration"),
                ("host-root", "Root filesystem"),
                ("xdg-desktop", "Desktop"),
                ("xdg-documents", "Documents"),
                ("xdg-download", "Downloads"),
                ("xdg-music", "Music"),
                ("xdg-pictures", "Pictures"),
                ("xdg-videos", "Videos"),
                ("xdg-public-share", "Public folder"),
                ("xdg-templates", "Templates"),
            ];
            let label = names
                .iter()
                .find(|(key, _)| *key == name)
                .map(|(_, label)| *label)
                .unwrap_or(name);
            format!("{label} - {}", if denied { "denied" } else { mode })
        })
        .collect();
    add("files", "File Access", "folder", "Locations available outside the app's private storage. Denied entries are exceptions to broader access.", files);
    add("persistent", "Persistent Storage", "document-save", "Sandbox home locations saved in this app's private storage, not access to your real home folder.", list("Context", "persistent"));
    for (id, section, title, description) in [
        (
            "session-bus",
            "Session Bus Policy",
            "Session Bus Access",
            "Communication with applications and services in your desktop session.",
        ),
        (
            "system-bus",
            "System Bus Policy",
            "System Bus Access",
            "Communication with system-wide services.",
        ),
    ] {
        let mut details = Vec::new();
        if sockets.iter().any(|s| s == id) {
            details.push("Unrestricted access to this bus".to_owned());
        }
        if sockets.iter().any(|s| s == &format!("!{id}")) {
            details.push("Unrestricted access denied; individual rules apply".to_owned());
        }
        for name in key.keys(section).unwrap_or_default() {
            let policy = key.string(section, &name).unwrap_or_default();
            let mode = match policy.as_str() {
                "talk" => "communicate",
                "own" => "own service name",
                "see" => "see service name",
                "none" => "denied",
                other => other,
            };
            details.push(format!("{name} - {mode}"));
        }
        add(id, title, "network-connect", description, details);
    }
    add(
        "features",
        "Additional Capabilities",
        "preferences-system",
        "Extra capabilities enabled or denied by the sandbox configuration.",
        labeled(
            list("Context", "features"),
            &[
                ("devel", "Development and debugging system calls"),
                ("multiarch", "Programs for other processor architectures"),
                ("bluetooth", "Bluetooth sockets"),
                ("canbus", "CAN bus sockets"),
                (
                    "per-app-dev-shm",
                    "Shared memory between this app's instances",
                ),
            ],
        ),
    );
    add(
        "sockets",
        "Other Socket Access",
        "network-connect",
        "Other host connections requested by the app.",
        labeled(
            sockets
                .iter()
                .filter(|s| {
                    ![
                        "pulseaudio",
                        "wayland",
                        "x11",
                        "fallback-x11",
                        "session-bus",
                        "system-bus",
                    ]
                    .contains(&s.trim_start_matches('!'))
                })
                .cloned()
                .collect(),
            &[
                ("ssh-auth", "SSH authentication agent"),
                ("gpg-agent", "GPG agent"),
                ("pcsc", "Smart cards"),
                ("cups", "Printing service"),
                ("inherit-wayland-socket", "Inherited Wayland connection"),
            ],
        ),
    );
    let mut usb: Vec<String> = list("USB Devices", "enumerable-devices")
        .into_iter()
        .map(|s| format!("{s} - visible to the USB portal"))
        .collect();
    usb.extend(
        list("USB Devices", "hidden-devices")
            .into_iter()
            .map(|s| format!("{s} - hidden from the USB portal")),
    );
    add("usb","USB Device Portal","drive-removable-media-usb","Which USB devices can be listed through the portal. Device access still requires portal authorization.",usb);
    let mut other: Vec<String> = shared
        .iter()
        .filter(|s| !["ipc", "network"].contains(&s.trim_start_matches('!')))
        .cloned()
        .collect();
    for name in key.keys("Context").unwrap_or_default() {
        if ![
            "shared",
            "sockets",
            "devices",
            "filesystems",
            "persistent",
            "features",
            "unset-environment",
        ]
        .contains(&name.as_str())
        {
            other.push(format!(
                "{name}: {}",
                key.value("Context", &name).unwrap_or_default()
            ));
        }
    }
    // Environment variables are not permissions and may contain secrets.
    for section in key.groups() {
        if let Some(policy) = section.strip_prefix("Policy ") {
            for name in key.keys(&section).unwrap_or_default() {
                for value in list(&section, &name) {
                    other.push(format!("{policy} / {name}: {value}"));
                }
            }
        }
    }
    add(
        "other",
        "Other Permissions and Conditions",
        "dialog-information",
        "Additional rules reported by Flatpak.",
        other,
    );
    if invalid.get() {
        error("Flatpak returned invalid permission information.")
    } else {
        json!({"state":"ready","groups":groups})
    }
}
pub fn changes(before: &[u8], after: &[u8]) -> Value {
    let (before, after) = (parse(before, false), parse(after, false));
    if before["state"] != "ready" || after["state"] != "ready" {
        return json!({"state":"unknown","groups":[]});
    }
    let mut order: Vec<&Value> = rows(&after["groups"]).iter().collect();
    order.extend(rows(&before["groups"]).iter().filter(|old| {
        !rows(&after["groups"])
            .iter()
            .any(|new| new["id"] == old["id"])
    }));
    let mut groups = Vec::new();
    for group in order {
        let old = rows(&before["groups"])
            .iter()
            .find(|row| row["id"] == group["id"]);
        let new = rows(&after["groups"])
            .iter()
            .find(|row| row["id"] == group["id"]);
        let left = old.map(|g| rows(&g["details"])).unwrap_or(&[]);
        let right = new.map(|g| rows(&g["details"])).unwrap_or(&[]);
        let added: Vec<_> = right
            .iter()
            .filter(|v| !left.contains(v))
            .cloned()
            .collect();
        let removed: Vec<_> = left
            .iter()
            .filter(|v| !right.contains(v))
            .cloned()
            .collect();
        if added.is_empty() && removed.is_empty() {
            continue;
        }
        let mut row = group.clone();
        row.as_object_mut().unwrap().remove("details");
        row["added"] = added.into();
        row["removed"] = removed.into();
        groups.push(row);
    }
    json!({"state":if groups.is_empty() {"unchanged"} else {"changed"},"groups":groups})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn secrets_are_not_permissions() {
        let output = parse(
            b"[Application]\nname=a.b.C\n[Context]\nshared=network;\n[Environment]\nTOKEN=secret\n",
            false,
        )
        .to_string();
        assert!(output.contains("Network Access"));
        assert!(!output.contains("secret"));
        assert!(!output.contains("TOKEN"));
    }
    #[test]
    fn changes_separate_additions_and_removals() {
        let old = b"[Application]\nname=a.b.C\n[Context]\nshared=network;\n";
        assert_eq!(changes(old, old)["state"], "unchanged");
        let new = b"[Application]\nname=a.b.C\n[Context]\nsockets=wayland;\n";
        let changed = changes(old, new);
        assert_eq!(changed["state"], "changed");
        assert_eq!(rows(&changed["groups"]).len(), 2);
    }
    #[test]
    fn invalid_metadata_is_not_no_permissions() {
        assert_eq!(parse(b"not a key file", false)["state"], "error");
        assert_eq!(parse(b"[Environment]\nFOO=bar\n", false)["state"], "error");
    }
}
