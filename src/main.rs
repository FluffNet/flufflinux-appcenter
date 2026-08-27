mod appstream;

#[cfg(not(target_os = "linux"))]
compile_error!("Fluff Linux App Center supports Fluff Linux/Arch Linux only.");

use std::env;
use std::ffi::CString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

unsafe extern "C" {
    fn fluff_run_qml(qml_path: *const i8, catalog_path: *const i8, icon_path: *const i8) -> i32;
}

fn find_main_qml() -> Option<PathBuf> {
    if let Some(path) = env::var_os("FLUFF_APP_CENTER_QML") {
        return Some(path.into());
    }
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("qml/Main.qml");
    if source.is_file() {
        return Some(source);
    }
    let installed = PathBuf::from("/usr/share/flufflinux-appcenter/qml/Main.qml");
    installed.is_file().then_some(installed)
}

fn cache_path() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .unwrap_or_else(env::temp_dir)
        .join("flufflinux-appcenter/catalog.json")
}

fn find_icon() -> Option<PathBuf> {
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets/flufflinux-appcenter.svg");
    if source.is_file() {
        return Some(source);
    }
    let installed =
        PathBuf::from("/usr/share/icons/hicolor/scalable/apps/flufflinux-appcenter.svg");
    installed.is_file().then_some(installed)
}

fn c_path(path: &Path) -> Result<CString, String> {
    CString::new(path.as_os_str().to_string_lossy().as_bytes())
        .map_err(|_| format!("path contains an invalid null byte: {}", path.display()))
}

fn run() -> Result<i32, String> {
    let main_qml = find_main_qml().ok_or("The App Center QML files could not be found.")?;
    let icon = find_icon().ok_or("The App Center icon could not be found.")?;
    let catalog = appstream::load_catalog();
    let cache = cache_path();
    if let Some(parent) = cache.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(&cache, appstream::to_json(&catalog)).map_err(|error| error.to_string())?;

    let qml_path = c_path(&main_qml)?;
    let catalog_path = c_path(&cache)?;
    let icon_path = c_path(&icon)?;
    // The bridge owns the Qt event loop and keeps all borrowed C strings alive
    // for the duration of the call.
    Ok(unsafe { fluff_run_qml(qml_path.as_ptr(), catalog_path.as_ptr(), icon_path.as_ptr()) })
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code as u8),
        Err(message) => {
            eprintln!("flufflinux-appcenter: {message}");
            ExitCode::FAILURE
        }
    }
}
