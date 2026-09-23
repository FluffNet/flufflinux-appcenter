#include "../../src/update_plan.h"
#include "../../src/install_history.h"
#include <QTemporaryDir>
#include <cassert>
#include <iostream>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    const QByteArray base = "[Application]\nname=org.example.Test\n[Context]\nsockets=wayland;pulseaudio;\nfilesystems=home:ro;\n";
    const QByteArray changed = "[Application]\nname=org.example.Test\n[Context]\nsockets=wayland;\nshared=network;\nfilesystems=home;\n[Session Bus Policy]\norg.example.Service=talk\n";
    auto delta = Updates::permissionChanges(base, changed);
    assert(delta["state"] == "changed");
    assert(delta["groups"].toList().size() == 4);
    const auto serialized = QJsonDocument::fromVariant(delta).toJson();
    assert(serialized.contains("added") && serialized.contains("removed"));
    assert(Updates::permissionChanges(base, base)["state"] == "unchanged");
    assert(Updates::permissionChanges(base, base + "[Environment]\nSECRET=never-show\n")["state"] == "unchanged");
    assert(Updates::permissionChanges({}, base)["state"] == "unknown");
    assert(Updates::permissionChanges(base, "bad data")["state"] == "unknown");
    QJsonObject operation{{"ref", "app/org.example.Test/x86_64/stable"}, {"action", "update"},
        {"remote", "fixture"}, {"commit", QString(64, 'a')}};
    const QJsonArray expected{operation};
    assert(Updates::matchesPlan(expected, expected));
    assert(Updates::matchesPlan(expected, {})); // Already updated dependency omitted.
    for (const auto &field : {"ref", "commit", "action", "remote"}) {
        auto different = operation; different[field] = "different";
        assert(!Updates::matchesPlan(expected, {different}));
    }
    assert(!Updates::matchesPlan({}, expected));
    assert(!Updates::validCommit("--commit=bad"));
    QTemporaryDir root;
    InstallHistory installations(root.path() + "/install.json"), updates(root.path() + "/update.json");
    const auto ref = operation["ref"].toString();
    const auto first = QDateTime::fromString("2026-09-01T12:00:00.000Z", Qt::ISODateWithMs);
    assert(installations.installed("user", ref, first));
    assert(updates.installed("user", ref, first.addDays(2)));
    assert(updates.installed("system", ref, first.addDays(1)));
    assert(updates.installed("user", ref, first.addDays(4)));
    InstallHistory reopened(root.path() + "/update.json");
    assert(reopened.date("user", ref) == first.addDays(4).toString(Qt::ISODateWithMs));
    assert(reopened.date("system", ref) == first.addDays(1).toString(Qt::ISODateWithMs));
    assert(installations.date("user", ref) == first.toString(Qt::ISODateWithMs));
    std::cout << "PASS: permission additions/removals, unknown data, secret exclusion, pinned plans, independent per-installation persistent dates\n";
}
