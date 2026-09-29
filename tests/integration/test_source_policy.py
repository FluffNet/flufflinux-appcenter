#!/usr/bin/env python3
"""Read-only checks for the narrowly scoped installed/source Polkit policy."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

project = Path(__file__).resolve().parents[2]
if len(sys.argv) > 1:
    stage = Path(sys.argv[1])
    policy = stage / "usr/share/polkit-1/actions/com.flufflinux.appcenter.policy"
    helper = stage / "usr/lib/flufflinux-appcenter/source-helper"
    assert helper.is_file() and helper.stat().st_mode & 0o111
    assert not helper.stat().st_mode & 0o6022  # No setuid/setgid or writable shared helper.
    assert (stage / "usr/share/flufflinux-appcenter/LICENSE").read_text().startswith("MIT License")
    document = policy.read_text()
else:
    document = (project / "data/com.flufflinux.appcenter.policy.in").read_text().replace("@PREFIX@", "/usr")
root = ET.fromstring(document)
actions = root.findall("action")
assert len(actions) == 1 and actions[0].attrib["id"] == "com.flufflinux.appcenter"
action = actions[0]
assert action.findtext("defaults/allow_any") == "no"
assert action.findtext("defaults/allow_inactive") == "no"
assert action.findtext("defaults/allow_active") == "auth_admin"
annotations = {element.attrib["key"]: element.text for element in action.findall("annotate")}
assert annotations == {"org.freedesktop.policykit.exec.path": "/usr/lib/flufflinux-appcenter/source-helper"}
assert "FluffNet LLC" in document
print("PASS: exact removal-only helper binding, active administrator authentication, no cached grants or privileged GUI")
