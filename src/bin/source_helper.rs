//! The privileged entry point only removes previously validated system sources.
fn main() -> std::process::ExitCode {
    let arguments: Vec<_> = std::env::args().skip(1).collect();
    let result = if arguments.len() == 1 {
        flufflinux_appcenter::backend::source_removal::privileged_main(&arguments[0])
    } else {
        Err("A bounded source-removal request is required.".into())
    };
    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            std::process::ExitCode::FAILURE
        }
    }
}
