//! Details for a resolved local file, independent of the Home catalog's lifetime.
use super::{permissions, repositories, sources, storage, text};
use crate::appstream::{self, App};
use gio::prelude::*;
use libflatpak::{prelude::*, Installation, TransactionOperation};
use serde_json::{json, Value};
use std::{io::Read, path::Path, sync::mpsc, time::Duration};

// Cached AppStream icons inside the disposable repository must outlive preview.
// Only copy the selected icon, not its repository or source registration.
pub fn retain_icon(app: &mut Value, directory: &Path) -> Result<(), String> {
    let icon = Path::new(text(app, "icon"));
    if !icon.starts_with(directory) {
        return Ok(());
    }
    let mut data = Vec::new();
    std::fs::File::open(icon)
        .and_then(|file| file.take(4 * 1024 * 1024 + 1).read_to_end(&mut data))
        .map_err(|e| e.to_string())?;
    if data.len() > 4 * 1024 * 1024 {
        return Err("The app icon exceeds 4 MiB.".into());
    }
    let extension = icon.extension().and_then(|s| s.to_str()).unwrap_or("png");
    let path = storage::cache_dir().join("local-icons").join(format!(
        "{}.{}",
        sources::token(&data),
        extension
    ));
    storage::atomic_write(&path, &data).map_err(|e| e.to_string())?;
    app["icon"] = path.to_string_lossy().into_owned().into();
    // Keep the single resolved source variant consistent with the main details.
    for source in app["sources"].as_array_mut().into_iter().flatten() {
        source["icon"] = path.to_string_lossy().into_owned().into();
    }
    Ok(())
}

pub fn reference_hint(key: &glib::KeyFile) -> App {
    let value = |name| {
        key.string("Flatpak Ref", name)
            .unwrap_or_default()
            .to_string()
    };
    let icon = value("Icon");
    App {
        name: value("Title"),
        summary: value("Comment"),
        description: value("Description"),
        homepage: value("Homepage"),
        icon: if repositories::safe_url(&icon) {
            icon
        } else {
            String::new()
        },
        ..Default::default()
    }
}

fn bundle_app(bundle: &libflatpak::BundleRef, id: &str, reference: &str) -> Option<App> {
    let bytes = bundle.appstream()?;
    // Bundle AppStream is gzip-compressed. Bound expansion of untrusted input.
    let input = gio::MemoryInputStream::from_bytes(&bytes);
    let decoder = gio::ZlibDecompressor::new(gio::ZlibCompressorFormat::Gzip);
    let stream = gio::ConverterInputStream::new(&input, &decoder);
    let mut xml = String::new();
    stream
        .into_read()
        .take(4 * 1024 * 1024 + 1)
        .read_to_string(&mut xml)
        .ok()?;
    if xml.len() > 4 * 1024 * 1024 {
        return None;
    }
    let mut app = appstream::app_from_xml(&xml, Path::new("bundle.xml"), id, reference)?;
    if let Some(icon) = bundle
        .icon(128)
        .or_else(|| bundle.icon(64))
        .filter(|data| data.len() <= 4 * 1024 * 1024 && data.starts_with(b"\x89PNG\r\n\x1a\n"))
    {
        let path = storage::cache_dir()
            .join("local-icons")
            .join(format!("{}.png", sources::token(&icon)));
        if storage::atomic_write(&path, &icon).is_ok() {
            app.icon = path.to_string_lossy().into_owned();
        }
    }
    Some(app)
}

fn cached_app(remote: &libflatpak::Remote, id: &str, reference: &str, arch: &str) -> Option<App> {
    let directory = remote.appstream_dir(Some(arch))?.path()?;
    appstream::app_in_catalog(&directory, id, reference)
}

fn refresh(installation: &Installation, name: &str, arch: &str, parent: &gio::Cancellable) {
    // Optional artwork/details must not hold an otherwise usable preview forever.
    // Cancellation is separate from the resolved transaction and never deploys an app.
    let cancel = gio::Cancellable::new();
    let watchdog_cancel = cancel.clone();
    let parent = parent.clone();
    let (done, receiver) = mpsc::channel();
    let watchdog = std::thread::spawn(move || {
        for _ in 0..450 {
            if receiver.recv_timeout(Duration::from_millis(100))
                != Err(mpsc::RecvTimeoutError::Timeout)
            {
                return;
            }
            if parent.is_cancelled() {
                break;
            }
        }
        watchdog_cancel.cancel();
    });
    if let Err(error) = installation.update_appstream_sync(name, Some(arch), Some(&cancel)) {
        eprintln!("Could not load local-file app details from {name}: {error}");
    }
    let _ = done.send(());
    let _ = watchdog.join();
}

pub fn resolve(
    installation: &Installation,
    request: &Value,
    op: &TransactionOperation,
    hint: &App,
    cancel: &gio::Cancellable,
) -> Value {
    let reference = op.get_ref().unwrap_or_default().to_string();
    let parts: Vec<_> = reference.split('/').collect();
    if parts.len() != 4 || parts[0] != "app" {
        return json!({});
    }
    let (id, arch) = (parts[1], parts[2]);
    let remote_name = op.remote().unwrap_or_default().to_string();
    let remote = installation.remote_by_name(&remote_name, Some(cancel)).ok();
    let source_url = remote.as_ref().map(sources::url).unwrap_or_default();
    let bundle = repositories::local_path(text(request, "source"))
        .filter(|p| {
            p.extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("flatpak"))
        })
        .and_then(|p| libflatpak::BundleRef::new(&gio::File::for_path(p)).ok())
        .filter(|b| b.format_ref().as_deref() == Some(reference.as_str()));
    let mut found = bundle.as_ref().and_then(|b| bundle_app(b, id, &reference));
    if found.is_none() {
        found = remote
            .as_ref()
            .and_then(|r| cached_app(r, id, &reference, arch));
    }
    // Reuse another installation's catalog only for the exact same repository URL.
    if found.is_none() && !source_url.is_empty() {
        for other in sources::installations().unwrap_or_default() {
            for candidate in other.list_remotes(Some(cancel)).unwrap_or_default() {
                if !candidate.is_disabled() && sources::url(&candidate) == source_url {
                    found = cached_app(&candidate, id, &reference, arch);
                    if found.is_some() {
                        break;
                    }
                }
            }
            if found.is_some() {
                break;
            }
        }
    }
    if found.is_none() && bundle.is_none() && !cancel.is_cancelled() {
        if let Some(remote) = remote
            .as_ref()
            .filter(|r| !r.is_disabled() && repositories::safe_url(&sources::url(r)))
        {
            refresh(installation, &remote_name, arch, cancel);
            found = cached_app(remote, id, &reference, arch);
        }
    }
    let warning = if found.is_some() {
        ""
    } else if bundle.is_some() {
        "This Flatpak bundle does not include app details."
    } else {
        "Could not load app details from this source. Check your connection and reopen the file to try again."
    };
    let mut app = found.unwrap_or_else(|| hint.clone());
    app.id = id.into();
    if app.name.is_empty() {
        app.name = id.into();
    }
    app.remote = remote_name;
    app.source_url = source_url;
    app.flatpak_ref = reference;
    app.download_bytes = Some(op.download_size());
    app.sources.clear();
    app.sources.push(app.clone());
    let mut apps: Value =
        serde_json::from_str(&appstream::to_json(&[app])).unwrap_or_else(|_| json!([]));
    apps[0]["detailsWarning"] = warning.into();
    let permissions = op
        .metadata()
        .map(|key| permissions::parse(key.to_data().as_bytes(), false))
        .unwrap_or_else(|| {
            permissions::error("The source did not provide application permission information.")
        });
    json!({"app":apps[0],"permissions":permissions})
}
