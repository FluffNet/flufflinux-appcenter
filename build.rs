use std::env;
use std::path::PathBuf;
use std::process::Command;

const QT_PACKAGES: &[&str] = &[
    "Qt6Core",
    "Qt6Gui",
    "Qt6Widgets",
    "Qt6Qml",
    "Qt6Quick",
    "Qt6Network",
    "Qt6DBus",
    "flatpak",
    "ostree-1",
];

fn command_output(program: &str, arguments: &[&str]) -> String {
    let output = Command::new(program)
        .args(arguments)
        .output()
        .unwrap_or_else(|error| panic!("failed to run {program}: {error}"));
    if !output.status.success() {
        panic!(
            "{program} failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    String::from_utf8(output.stdout).expect("tool output was not UTF-8")
}

fn main() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("linux") {
        panic!("App Center can only be built on Fluff Linux/Arch Linux");
    }

    let output_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is missing"));
    let archive = output_dir.join("libfluff_qt_bridge.a");

    let mut cflags_arguments = vec!["--cflags"];
    cflags_arguments.extend(QT_PACKAGES);
    let cflags = command_output("pkg-config", &cflags_arguments);

    let moc =
        PathBuf::from(command_output("pkg-config", &["--variable=libexecdir", "Qt6Core"]).trim())
            .join("moc");
    let generated = output_dir.join("moc_flatpak_manager.cpp");
    let status = Command::new(moc)
        .arg("src/flatpak_manager.h")
        .arg("-o")
        .arg(&generated)
        .args(
            cflags
                .split_whitespace()
                .filter(|flag| flag.starts_with("-I") || flag.starts_with("-D")),
        )
        .status()
        .expect("failed to run Qt moc");
    assert!(
        status.success(),
        "failed to generate Flatpak manager bindings"
    );
    let mut objects = Vec::new();
    let display_version = std::fs::read_to_string("VERSION").expect("VERSION is missing");
    for source in [
        PathBuf::from("src/qt_bridge.cpp"),
        PathBuf::from("src/flatpak_manager.cpp"),
        PathBuf::from("src/flatpak_worker.cpp"),
        PathBuf::from("src/flatpak_sizes.cpp"),
        PathBuf::from("src/flatpak_permissions.cpp"),
        PathBuf::from("src/flatpak_updates.cpp"),
        PathBuf::from("src/flatpak_catalog.cpp"),
        generated,
    ] {
        let object = output_dir
            .join(source.file_stem().unwrap())
            .with_extension("o");
        let status = Command::new("c++")
            .args(["-std=c++17", "-fPIC", "-pthread", "-Wall", "-Wextra", "-c"])
            .arg(format!("-DAPPCENTER_DISPLAY_VERSION=\"{}\"", display_version.trim()))
            .arg(&source)
            .arg("-o")
            .arg(&object)
            .args(cflags.split_whitespace())
            .status()
            .expect("failed to start the C++ compiler");
        assert!(status.success(), "failed to compile {}", source.display());
        objects.push(object);
    }

    let status = Command::new("ar")
        .args(["crs"])
        .arg(&archive)
        .args(&objects)
        .status()
        .expect("failed to start ar");
    assert!(status.success(), "failed to archive the Qt bridge");

    println!("cargo:rustc-link-search=native={}", output_dir.display());
    println!("cargo:rustc-link-lib=static=fluff_qt_bridge");
    println!("cargo:rustc-link-lib=dylib=stdc++");

    let mut libs_arguments = vec!["--libs"];
    libs_arguments.extend(QT_PACKAGES);
    for flag in command_output("pkg-config", &libs_arguments).split_whitespace() {
        if let Some(path) = flag.strip_prefix("-L") {
            println!("cargo:rustc-link-search=native={path}");
        } else if let Some(library) = flag.strip_prefix("-l") {
            println!("cargo:rustc-link-lib=dylib={library}");
        } else {
            println!("cargo:rustc-link-arg={flag}");
        }
    }

    println!("cargo:rerun-if-changed=src/qt_bridge.cpp");
    println!("cargo:rerun-if-changed=VERSION");
    println!("cargo:rerun-if-changed=src/source_removal.h");
    println!("cargo:rerun-if-changed=src/window_preferences.h");
    println!("cargo:rerun-if-changed=src/ui_typography.h");
    println!("cargo:rerun-if-changed=src/flatpak_manager.h");
    println!("cargo:rerun-if-changed=src/flatpak_sources.h");
    println!("cargo:rerun-if-changed=src/flatpak_catalog.cpp");
    println!("cargo:rerun-if-changed=src/flatpak_manager.cpp");
    println!("cargo:rerun-if-changed=src/install_history.h");
    println!("cargo:rerun-if-changed=src/flatpak_worker.cpp");
    println!("cargo:rerun-if-changed=src/transaction_status.h");
    println!("cargo:rerun-if-changed=src/transaction_progress.h");
    println!("cargo:rerun-if-changed=src/download_rate.h");
    println!("cargo:rerun-if-changed=src/download_size.h");
    println!("cargo:rerun-if-changed=src/flatpak_sizes.cpp");
    println!("cargo:rerun-if-changed=src/flatpak_sizes.h");
    println!("cargo:rerun-if-changed=src/flatpak_permissions.cpp");
    println!("cargo:rerun-if-changed=src/flatpak_permissions.h");
    println!("cargo:rerun-if-changed=src/flatpak_updates.cpp");
    println!("cargo:rerun-if-changed=src/update_plan.h");
}
