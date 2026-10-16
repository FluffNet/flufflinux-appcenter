//! Check complete GUI catalogs and desktop launcher coverage.
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
fn qml_translation_literals_are_in_the_shared_catalog() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let english: HashMap<String, String> = serde_json::from_slice(
        &fs::read(root.join("translations/en.json")).unwrap()
    ).unwrap();
    for entry in fs::read_dir(root.join("qml")).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().is_none_or(|extension| extension != "qml") { continue; }
        let source = fs::read_to_string(&path).unwrap();
        for call in ["qsTr(", "qsTranslate(\"AppCenter\","] {
            for tail in source.split(call).skip(1) {
                let literal = tail.trim_start();
                if !literal.starts_with('"') { continue; }
                let key = serde_json::Deserializer::from_str(literal)
                    .into_iter::<String>().next().unwrap().unwrap();
                assert!(english.contains_key(&key), "{}: missing translation key {key}", path.display());
            }
        }
    }
}

#[test]
fn desktop_names_cover_every_language_and_region() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let desktop = fs::read_to_string(root.join("data/flufflinux-appcenter.desktop")).unwrap();
    let regions = fs::read_to_string(root.join("translations/regions.tsv")).unwrap();
    let language_list = fs::read_to_string(root.join("translations/languages.tsv")).unwrap();
    let english: HashMap<String, String> = serde_json::from_slice(
        &fs::read(root.join("translations/en.json")).unwrap()
    ).unwrap();
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
        let code = row.split('\t').next().unwrap();
        assert!(seen.contains(code));
        let catalog = root.join(format!("translations/{code}.json"));
        let text: HashMap<String, String> = serde_json::from_slice(
            &fs::read(&catalog).unwrap_or_else(|error| panic!("missing catalog {code}: {error}"))
        ).unwrap();
        assert_eq!(text.len(), english.len(), "incomplete catalog {code}");
        for key in english.keys() {
            assert!(text.get(key).is_some_and(|value| !value.trim().is_empty()), "missing {code}: {key}");
        }
    }
}
