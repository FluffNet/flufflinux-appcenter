mod appstream;

#[cfg(not(target_os = "linux"))]
compile_error!("Fluff Linux App Center supports Fluff Linux/Arch Linux only.");

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

fn find_qml() -> Option<PathBuf> {
    if let Some(path) = env::var_os("FLUFF_APP_CENTER_QML_RUNTIME") {
        return Some(path.into());
    }
    for path in ["/usr/lib/qt6/bin/qml", "/usr/bin/qml6", "/usr/bin/qml"] {
        if Path::new(path).is_file() {
            return Some(path.into());
        }
    }
    None
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

fn run() -> Result<i32, String> {
    let qml = find_qml().ok_or("Qt 6 QML runtime not found. Install qt6-declarative.")?;
    let main_qml = find_main_qml().ok_or("The App Center QML files could not be found.")?;
    let catalog = appstream::load_catalog();
    let cache = cache_path();
    if let Some(parent) = cache.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(&cache, appstream::to_json(&catalog)).map_err(|error| error.to_string())?;

    let status = Command::new(qml)
        // Qt requires a UTF-8 locale. Fluff's live/development environment can
        // otherwise inherit the legacy C locale from a terminal session.
        .env("LC_ALL", "C.UTF-8")
        .arg(main_qml)
        .arg("--")
        .arg("--catalog")
        .arg(format!("file://{}", cache.display()))
        .status()
        .map_err(|error| format!("Unable to start the QML interface: {error}"))?;
    Ok(status.code().unwrap_or(1))
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
