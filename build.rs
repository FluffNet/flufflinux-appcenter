use std::env;
use std::path::PathBuf;
use std::process::Command;

const QT_PACKAGES: &[&str] = &["Qt6Core", "Qt6Gui", "Qt6Qml", "Qt6Quick"];

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
        panic!("Fluff Linux App Center can only be built on Fluff Linux/Arch Linux");
    }

    let output_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is missing"));
    let object = output_dir.join("qt_bridge.o");
    let archive = output_dir.join("libfluff_qt_bridge.a");

    let mut cflags_arguments = vec!["--cflags"];
    cflags_arguments.extend(QT_PACKAGES);
    let cflags = command_output("pkg-config", &cflags_arguments);

    let mut compiler = Command::new("c++");
    compiler
        .arg("-std=c++17")
        .arg("-fPIC")
        .arg("-c")
        .arg("src/qt_bridge.cpp")
        .arg("-o")
        .arg(&object)
        .args(cflags.split_whitespace());
    let status = compiler.status().expect("failed to start the C++ compiler");
    assert!(status.success(), "failed to compile the Qt bridge");

    let status = Command::new("ar")
        .args(["crs"])
        .arg(&archive)
        .arg(&object)
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
}
