mod cli;
use flufflinux_appcenter::{appstream, backend};

#[cfg(not(target_os = "linux"))]
compile_error!("App Center supports Fluff Linux/Arch Linux only.");

use std::env;
use std::ffi::CString;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

unsafe extern "C" {
    fn fluff_run_qml(
        qml_path: *const i8,
        icon_path: *const i8,
        input_count: i32,
        inputs: *const *const i8,
        desktop_file: *const i8,
    ) -> i32;
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

fn run() -> Result<i32, String> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.as_slice() == ["--popularity-worker"] {
        if unsafe { libc::geteuid() } == 0 {
            return Err("Run App Center as your desktop user.".into());
        }
        backend::process::parent_death_signal()?;
        println!("{}", backend::popularity::fetch()?);
        return Ok(0);
    }
    if args.first().map(String::as_str) == Some("--catalog") && args.len() <= 2 {
        if args.len() == 2 {
            backend::process::parent_death_signal()?;
        }
        // Keep stdout a single JSON result for existing --catalog consumers.
        // Emit only changed integer milestones, not one IPC event per app.
        let mut last_progress = 0;
        let apps = appstream::load_catalog(|parsed| {
            let overall = 70 + parsed * 25 / 100;
            if overall != last_progress {
                eprintln!("APPCENTER_CATALOG_PROGRESS {overall}");
                last_progress = overall;
            }
        });
        let json = appstream::to_json(&apps);
        eprintln!("APPCENTER_CATALOG_PROGRESS 96");
        if args.len() == 2 {
            let request = serde_json::from_str(&args[1]).map_err(|e| e.to_string())?;
            let apps = serde_json::from_str(&json).map_err(|e| e.to_string())?;
            eprintln!("APPCENTER_CATALOG_PROGRESS 98");
            let result = backend::catalog::snapshot(&request, apps);
            eprintln!("APPCENTER_CATALOG_PROGRESS 99");
            println!("{result}");
            return Ok(0);
        }
        println!("{json}");
        return Ok(0);
    }
    // The unprivileged worker doesn't parse the catalog or initialize a GUI.
    if args.first().map(String::as_str) == Some("--updates-worker") {
        if args.len() != 2 {
            return Err("Missing updates request".into());
        }
        if unsafe { libc::geteuid() } == 0 {
            return Err("Run App Center as your desktop user.".into());
        }
        backend::process::parent_death_signal()?;
        let request = serde_json::from_str(&args[1]).map_err(|e| e.to_string())?;
        let result = backend::updates::scan(&request, backend::transaction::send);
        println!("{result}");
        return Ok(0);
    }
    if args.first().map(String::as_str) == Some("--permissions-worker") {
        if args.len() != 2 {
            return Err("Missing permissions request".into());
        }
        backend::process::parent_death_signal()?;
        let request = serde_json::from_str(&args[1]).map_err(|e| e.to_string())?;
        let result = if unsafe { libc::geteuid() } == 0 {
            backend::permissions::error("Run App Center as your desktop user.")
        } else {
            backend::permissions::read(&request)
        };
        println!("{result}");
        return Ok(0);
    }
    if args.first().map(String::as_str) == Some("--addons-worker") {
        if args.len() != 2 {
            return Err("Missing add-ons request".into());
        }
        backend::process::parent_death_signal()?;
        let request = serde_json::from_str(&args[1]).map_err(|e| e.to_string())?;
        let result = if unsafe { libc::geteuid() } == 0 {
            backend::addons::error("Run App Center as your desktop user.")
        } else {
            backend::addons::read(&request, None, false)
        };
        println!("{result}");
        return Ok(0);
    }
    if args.first().map(String::as_str) == Some("--transaction-worker") {
        if args.len() != 2 {
            return Err("Missing transaction request".into());
        }
        let request = serde_json::from_str(&args[1]).map_err(|e| e.to_string())?;
        return Ok(backend::transaction::run(request));
    }
    let (actions, desktop_file) =
        match cli::parse(&args, &env::current_dir().map_err(|e| e.to_string())?)? {
            cli::Command::NoOp => return Ok(0),
            cli::Command::Print(text) => {
                print!("{text}");
                return Ok(0);
            }
            cli::Command::Launch {
                actions,
                desktop_file,
            } => (
                actions,
                CString::new(desktop_file).map_err(|e| e.to_string())?,
            ),
        };
    let main_qml = find_main_qml().ok_or("The App Center QML files could not be found.")?;
    let icon = find_icon().ok_or("The App Center icon could not be found.")?;
    let qml_path = c_path(&main_qml)?;
    let icon_path = c_path(&icon)?;
    // The bridge owns the Qt event loop and keeps all borrowed C strings alive
    // for the duration of the call.
    let inputs: Vec<CString> = actions
        .iter()
        .map(|(kind, value)| {
            CString::new(serde_json::json!({"type":kind,"value":value}).to_string())
        })
        .collect::<Result<_, _>>()
        .map_err(|e| e.to_string())?;
    if inputs.iter().map(|s| s.as_bytes().len() + 1).sum::<usize>() > 120 * 1024 {
        return Err("Command-line request is too large. Open fewer files at once.".into());
    }
    let pointers: Vec<*const i8> = inputs.iter().map(|s| s.as_ptr()).collect();
    Ok(unsafe {
        fluff_run_qml(
            qml_path.as_ptr(),
            icon_path.as_ptr(),
            pointers.len() as i32,
            pointers.as_ptr(),
            desktop_file.as_ptr(),
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
