#include "../../src/flatpak_permissions.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <cassert>
#include <iostream>

static QVariantMap group(const QVariantMap &result, const QString &id) {
    for (const auto &entry : result.value("groups").toList())
        if (entry.toMap().value("id") == id) return entry.toMap();
    return {};
}
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    const auto result = AppPermissions::parse(R"([Application]
name=org.example.App
[Context]
shared=network;ipc;
sockets=pulseaudio;x11;wayland;ssh-auth;session-bus;
devices=dri;all;!input;
filesystems=home;xdg-download:ro;/tmp/foo:create;!/secret;xdg-documents:rw;
persistent=.local;cache;
features=bluetooth;!devel;multiarch;future-feature;
future-rule=custom;
[Session Bus Policy]
z.service=talk
a.service=own
hidden.service=none
see.service=see
[System Bus Policy]
org.bluez=talk
[USB Devices]
enumerable-devices=all;
hidden-devices=vnd:1234;
[Policy test]
access=foo;!bar;
[Environment]
SECRET_TOKEN=must-not-be-displayed
)");
    assert(result.value("state") == "ready");
    const auto groups = result.value("groups").toList();
    assert(groups.size() == 13);
    assert(groups[0].toMap()["id"] == "network");
    assert(groups[1].toMap()["id"] == "audio");
    assert(groups[2].toMap()["id"] == "devices");
    const auto files = group(result, "files")["details"].toStringList();
    assert(files.contains("Downloads — read only"));
    assert(files.contains("Documents — read and write"));
    assert(files.contains("/tmp/foo — read, write and create"));
    assert(files.contains("/secret — denied"));
    const auto bus = group(result, "session-bus")["details"].toStringList();
    assert(bus.contains("Unrestricted access to this bus"));
    assert(bus.contains("hidden.service — denied"));
    assert(bus.indexOf("a.service — own service name") < bus.indexOf("z.service — communicate"));
    assert(group(result, "features")["details"].toStringList().contains("future-feature"));
    assert(group(result, "devices")["details"].toStringList().contains("Input devices — denied"));
    assert(group(result, "other")["details"].toStringList().contains("test / access: !bar"));
    assert(!QJsonDocument::fromVariant(result).toJson().contains("must-not-be-displayed"));
    const auto minimal = AppPermissions::parse("[Application]\nname=org.example.Minimal\n");
    assert(minimal.value("state") == "ready" && minimal.value("groups").toList().isEmpty());
    assert(AppPermissions::parse({}, true).value("state") == "ready");
    assert(AppPermissions::parse({}).value("state") == "error");
    assert(AppPermissions::parse("<html>Server error</html>").value("state") == "error");
    assert(AppPermissions::parse("[Application]\nname=test\n[Context]\nsockets=\\q;").value("state") == "error");
    assert(AppPermissions::parse(QByteArray(1024 * 1024 + 1, 'x')).value("state") == "error");
    const auto escaped = AppPermissions::parse("[Application]\nname=test\n[Context]\nfilesystems=/semi\\;colon:ro;\nshared=!network;\n");
    assert(group(escaped, "files")["details"].toStringList().contains("/semi;colon — read only"));
    assert(group(escaped, "network")["details"].toStringList().contains("Network connections — denied"));
    std::cout << "Permission parser checks passed\n";
}
