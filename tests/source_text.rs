//! App Center uses the ASCII hyphen for all authored dashes, including comments.
use std::{fs, path::Path};

fn non_ascii_dash(character: char) -> bool {
    // Unicode dash punctuation plus soft hyphen and mathematical minus.
    matches!(character as u32,
        0x00ad | 0x058a | 0x05be | 0x1400 | 0x1806 | 0x2010..=0x2015 |
        0x2053 | 0x207b | 0x208b | 0x2212 | 0x2e17 | 0x2e1a |
        0x2e3a..=0x2e3b | 0x2e40 | 0x2e5d | 0x301c | 0x3030 |
        0x30a0 | 0xfe31..=0xfe32 | 0xfe58 | 0xfe63 | 0xff0d |
        0x10d6e | 0x10ead)
}

fn inspect(directory: &Path, root: &Path, failures: &mut Vec<String>) {
    for entry in fs::read_dir(directory).expect("read source directory") {
        let entry = entry.expect("read source entry");
        let kind = entry.file_type().expect("source file type");
        let path = entry.path();
        if kind.is_symlink() { continue; }
        if kind.is_dir() {
            // Build products, archived screenshots and local tool state are
            // not authored source. Never descend into dependencies or VCS data.
            if matches!(entry.file_name().to_str(), Some("target" | "build" | "output" | "fakeroot" |
                ".git" | ".codex" | ".agents" | ".venv" | "node_modules" | "__pycache__")) { continue; }
            inspect(&path, root, failures);
        } else if kind.is_file() {
            let bytes = fs::read(&path).expect("read source file");
            let Ok(text) = std::str::from_utf8(&bytes) else { continue; };
            for (line, text) in text.lines().enumerate() {
                for character in text.chars().filter(|c| non_ascii_dash(*c)) {
                    failures.push(format!("{}:{}: U+{:04X}; use ASCII '-'",
                        path.strip_prefix(root).unwrap().display(), line + 1, character as u32));
                }
            }
        }
    }
}

#[test]
fn only_ascii_dashes_in_source() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut failures = Vec::new();
    inspect(root, root, &mut failures);
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn dash_guard_detects_typographic_variants() {
    assert!(!non_ascii_dash('-'));
    for code in [0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212, 0xff0d] {
        assert!(non_ascii_dash(char::from_u32(code).unwrap()));
    }
}
