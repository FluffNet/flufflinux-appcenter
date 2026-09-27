mod appstream;
mod catalog_exclusions;

#[cfg(not(target_os = "linux"))]
compile_error!("App Center supports Fluff Linux/Arch Linux only.");

use std::env;
use std::ffi::CString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

unsafe extern "C" {
    fn fluff_run_qml(
        qml_path: *const i8,
        catalog_path: *const i8,
        icon_path: *const i8,
        input_count: i32,
        inputs: *const *const i8,
    ) -> i32;
    fn fluff_transaction_worker(request: *const i8) -> i32;
    fn fluff_permissions_worker(request: *const i8) -> i32;
    fn fluff_updates_worker(request: *const i8) -> i32;
}

fn installed_assets(executable: &Path) -> Option<PathBuf> {
    let bin = executable.parent()?;
    // An installed executable must use its installed interface, even while
    // the original build checkout still exists and is being edited.
    (bin.file_name()? == "bin").then(|| {
        bin.parent()
            .map(|prefix| prefix.join("share/flufflinux-appcenter"))
    })?
}

fn find_main_qml() -> Option<PathBuf> {
    if let Some(path) = env::var_os("FLUFF_APP_CENTER_QML") {
        return Some(path.into());
    }
    if let Some(assets) = env::current_exe()
        .ok()
        .and_then(|exe| installed_assets(&exe))
    {
        let installed = assets.join("qml/Main.qml");
        return installed.is_file().then_some(installed);
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
    if let Some(assets) = env::current_exe()
        .ok()
        .and_then(|exe| installed_assets(&exe))
    {
        let installed = assets.join("qml/flufflinux-appcenter.svg");
        return installed.is_file().then_some(installed);
    }
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

fn launch_inputs(args: Vec<String>) -> Result<Vec<String>, String> {
    // Preserve Discover's pinned-launcher update action, without checking for
    // updates automatically. All other legacy options remain unsupported.
    if args == ["--updates"] || args == ["--mode", "update"] || args == ["--mode=update"] {
        return Ok(vec!["--updates".into()]);
    }
    if args.iter().any(|arg| arg.starts_with('-')) {
        return Err("Usage: flufflinux-appcenter [--updates | FILE.flatpak|FILE.flatpakref|FILE.flatpakrepo|flatpak+https://URL …]".into());
    }
    Ok(args)
}

fn run() -> Result<i32, String> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args == ["--catalog"] {
        println!("{}", appstream::to_json(&appstream::load_catalog()));
        return Ok(0);
    }
    // The unprivileged worker doesn't parse the catalog or initialize a GUI.
    if args.first().map(String::as_str) == Some("--updates-worker") {
        if args.len() != 2 { return Err("Missing updates request".into()); }
        let request = CString::new(args[1].as_str()).map_err(|e| e.to_string())?;
        return Ok(unsafe { fluff_updates_worker(request.as_ptr()) });
    }
    if args.first().map(String::as_str) == Some("--permissions-worker") {
        if args.len() != 2 { return Err("Missing permissions request".into()); }
        let request = CString::new(args[1].as_str()).map_err(|e| e.to_string())?;
        return Ok(unsafe { fluff_permissions_worker(request.as_ptr()) });
    }
    if args.first().map(String::as_str) == Some("--transaction-worker") {
        if args.len() != 2 {
            return Err("Missing transaction request".into());
        }
        let request = CString::new(args[1].as_str()).map_err(|e| e.to_string())?;
        return Ok(unsafe { fluff_transaction_worker(request.as_ptr()) });
    }
    let args = launch_inputs(args)?;
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
    let inputs: Vec<CString> = args
        .iter()
        .map(|s| CString::new(s.as_str()))
        .collect::<Result<_, _>>()
        .map_err(|e| e.to_string())?;
    let pointers: Vec<*const i8> = inputs.iter().map(|s| s.as_ptr()).collect();
    Ok(unsafe {
        fluff_run_qml(
            qml_path.as_ptr(),
            catalog_path.as_ptr(),
            icon_path.as_ptr(),
            pointers.len() as i32,
            pointers.as_ptr(),
        )
    })
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discover_update_shortcuts_only_request_the_updates_page() {
        for args in [vec!["--updates"], vec!["--mode", "update"], vec!["--mode=update"]] {
            assert_eq!(launch_inputs(args.into_iter().map(String::from).collect()).unwrap(), ["--updates"]);
        }
        assert!(launch_inputs(vec!["--mode".into()]).is_err());
        assert!(launch_inputs(vec!["--mode".into(), "remove".into()]).is_err());
        assert!(launch_inputs(vec!["--updates".into(), "unexpected".into()]).is_err());
        assert_eq!(launch_inputs(vec!["/tmp/App.flatpakref".into()]).unwrap(), ["/tmp/App.flatpakref"]);
    }

    #[test]
    fn installed_binary_uses_its_own_prefix_not_the_build_checkout() {
        assert_eq!(
            installed_assets(Path::new("/usr/bin/flufflinux-appcenter")),
            Some(PathBuf::from("/usr/share/flufflinux-appcenter"))
        );
        assert_eq!(
            installed_assets(Path::new("/opt/appcenter/bin/flufflinux-appcenter")),
            Some(PathBuf::from("/opt/appcenter/share/flufflinux-appcenter"))
        );
        assert_eq!(
            installed_assets(Path::new("/tmp/source/target/release/flufflinux-appcenter")),
            None
        );
        assert_eq!(
            installed_assets(Path::new("/tmp/source/target/debug/flufflinux-appcenter")),
            None
        );
    }
}
