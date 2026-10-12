//! Check desktop launcher coverage independently of GUI translation completion.
use std::{collections::HashMap, fs, path::Path};

fn section(text: &str, wanted: &str) -> HashMap<String, String> {
    let mut active = false;
    let mut values = HashMap::new();
    for line in text.lines() {
        if line.starts_with('[') { active = line == wanted; continue; }
        if !active || line.starts_with('#') { continue; }
        if let Some((key, value)) = line.split_once('=') {
            assert!(values.insert(key.to_owned(), value.to_owned()).is_none(), "duplicate {key}");
        }
    }
    values
}

#[test]
fn desktop_names_cover_every_language_and_region() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let desktop = fs::read_to_string(root.join("data/flufflinux-appcenter.desktop")).unwrap();
    let regions = fs::read_to_string(root.join("translations/regions.tsv")).unwrap();
    let language_list = fs::read_to_string(root.join("translations/languages.tsv")).unwrap();
    let mut seen = std::collections::HashSet::new();
    for (heading, source) in [("[Desktop Entry]", "App Center"), ("[Desktop Action Updates]", "App Updates")] {
        let names = section(&desktop, heading);
        assert_eq!(names["Name"], source);
        for row in regions.lines().skip(1) {
            let columns: Vec<_> = row.split('\t').collect();
            let code = columns[0];
            let locale = columns[1].replace(".UTF-8", "");
            let key = format!("Name[{locale}]");
            let name = names.get(&key).unwrap_or_else(|| panic!("missing {heading} {key}"));
            assert!(!name.trim().is_empty(), "empty {key}");
            let catalog = root.join(format!("translations/{code}.json"));
            if catalog.exists() {
                let mut text: HashMap<String, String> = serde_json::from_slice(&fs::read(catalog).unwrap()).unwrap();
                let regional = root.join(format!("translations/{locale}.json"));
                if regional.exists() {
                    text.extend(serde_json::from_slice::<HashMap<String, String>>(&fs::read(regional).unwrap()).unwrap());
                }
                assert_eq!(name, &text[source], "launcher/catalog mismatch for {key}");
            }
            seen.insert(code);
        }
        assert_ne!(names["Name[sr_RS]"], names["Name[sr_RS@latin]"]);
        assert_ne!(names["Name[pa_IN]"], names["Name[pa_PK]"]);
        assert_ne!(names["Name[zh_CN]"], names["Name[zh_TW]"]);
        assert_eq!(names["Name[ca_ES@valencia]"], names["Name[ca@valencia]"]);
    }
    assert_eq!(regions.lines().count() - 1, 172);
    assert_eq!(seen.len(), 96);
    for row in language_list.lines().skip(1) {
        assert!(seen.contains(row.split('\t').next().unwrap()));
    }
}
