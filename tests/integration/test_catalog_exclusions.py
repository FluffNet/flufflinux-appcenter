#!/usr/bin/env python3
"""Read-only real catalog check. Uses temporary exclusion files, never changes apps."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
binary = Path(os.environ.get("APPCENTER_TEST_BINARY", repo / "target/release/flufflinux-appcenter"))
def normalize(app_id):
    return app_id.lower().removesuffix(".desktop")
def bundle_id(app):
    parts = app.get("flatpakRef", "").split("/")
    return parts[1] if len(parts) == 4 and parts[0] == "app" else app["id"]
def identities(app):
    return {app["id"].lower(), bundle_id(app).lower()}
def matches(app, rules):
    return any(any(app_id.startswith(rule[:-1].lower()) if rule.endswith("*")
                   else normalize(app_id) == normalize(rule) for app_id in identities(app)) for rule in rules)
def catalog(path):
    env = dict(os.environ)
    if path is None:
        env.pop("FLUFF_APP_CENTER_EXCLUSIONS", None)
    else:
        env["FLUFF_APP_CENTER_EXCLUSIONS"] = str(path)
    return json.loads(subprocess.check_output([str(binary), "--catalog"], env=env, timeout=30))

with tempfile.TemporaryDirectory(prefix="appcenter-catalog-exclusions-") as directory:
    config = Path(directory) / "exclusions.conf"
    config.write_text("")
    before = catalog(config)
    assert before, "This opt-in test requires a populated catalog"
    installed = {normalize(line) for line in subprocess.check_output(
        ["flatpak", "list", "--app", "--columns=application"], text=True).splitlines()}
    installed_apps = [app for app in before if normalize(bundle_id(app)) in installed]
    assert installed_apps, "Test requires at least one installed catalog app"
    absent_app = next(app for app in before if normalize(bundle_id(app)) not in installed)
    config.write_text('# Test exact IDs, comments and installed exception\n'
                      + '\n'.join(normalize(bundle_id(app)).upper() + ".DESKTOP"
                                  for app in installed_apps + [absent_app]) + '\n')
    after = catalog(config)
    ids = {normalize(app["id"]) for app in after}
    assert all(normalize(app["id"]) in ids for app in installed_apps), "An installed excluded app became inaccessible"
    assert normalize(absent_app["id"]) not in ids, "An uninstalled excluded app remained in the catalog"
    assert len(after) == len(before) - 1
    # A namespace prefix may cover both installed apps and available siblings.
    prefixes = {normalize(bundle_id(app)).rsplit(".", 1)[0] for app in installed_apps + [absent_app]}
    prefix_rules = [prefix.upper() + "*" for prefix in prefixes]
    config.write_text("# Case-insensitive ID prefixes\n" + "\n".join(prefix_rules) + "\n")
    prefix_catalog = catalog(config)
    expected = {normalize(app["id"]) for app in before
                if not matches(app, prefix_rules) or normalize(bundle_id(app)) in installed}
    assert {normalize(app["id"]) for app in prefix_catalog} == expected
    assert all(normalize(app["id"]) in expected for app in installed_apps)
    defaults = catalog(Path(directory) / "missing.conf")
    default_rules = [line.split("#", 1)[0].strip() for line in (repo / "data/exclusions.conf").read_text().splitlines()]
    default_rules = [rule for rule in default_rules if rule]
    expected_defaults = {normalize(app["id"]) for app in before
                         if not matches(app, default_rules) or normalize(bundle_id(app)) in installed}
    assert {normalize(app["id"]) for app in defaults} == expected_defaults, "Bundled exclusions mismatch"
    config.write_text((repo / "data/exclusions.conf").read_text())
    assert {normalize(app["id"]) for app in catalog(config)} == expected_defaults, "File/default behavior differs"
    if os.environ.get("APPCENTER_TEST_ACTIVE_CONFIG") == "1":
        assert {normalize(app["id"]) for app in catalog(None)} == expected_defaults, "Active /etc exclusions mismatch"
        print("PASS: active /etc/flufflinux-appcenter/exclusions.conf")
    hidden = sorted(app["id"] for app in before if normalize(app["id"]) not in expected_defaults)
    assert any(isinstance(app["downloadBytes"], int) and app["downloadBytes"] > 0 for app in before)
    assert any(app["releaseTimestamp"] or app["releaseDate"] for app in before)
    print("PASS: case-insensitive IDs, desktop aliases, trailing-prefix rules, installed exception, bundled/file defaults")
    print("Hidden available IDs:", ", ".join(hidden))
    print("PASS: cached sizes/release dates; no apps installed, updated or removed")
