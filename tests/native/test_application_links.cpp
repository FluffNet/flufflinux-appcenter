// Production manager, synthetic local catalog/list: no network or transactions.
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QElapsedTimer>
#include <QThread>
#include <cassert>
#include <functional>

static void until(const std::function<bool()> &condition) {
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < 6000) { QCoreApplication::processEvents(); QThread::msleep(5); }
    assert(condition());
}
int main(int argc, char **argv) {
    QTemporaryDir temporary; assert(temporary.isValid());
    qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-app-link-test-bus");
    QFile flatpak(temporary.filePath("flatpak")); assert(flatpak.open(QIODevice::WriteOnly));
    flatpak.write("#!/bin/sh\ncase \"$1\" in\nlist) sleep 0.15; printf 'org.example.Installed\\tInstalled\\t0\\tfixture\\tuser\\tstable\\tx86_64\\tFixture app\\t1.0\\n';;\n*) exit 1;;\nesac\n");
    flatpak.close(); assert(flatpak.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    qputenv("PATH", temporary.path().toUtf8() + ':' + qgetenv("PATH"));
    QGuiApplication app(argc, argv);
    FlatpakManager manager({QVariantMap{{"id", "org.example.MixedCase.desktop"}, {"name", "Example"},
        {"flatpakRef", "app/org.example.MixedCase/x86_64/stable"}, {"remote", "fixture"}}});
    QString error; QVariantMap opened; int openings = 0;
    QObject::connect(&manager, &FlatpakManager::inputError, &app, [&](const QString &message) { error = message; });
    QObject::connect(&manager, &FlatpakManager::appOpened, &app, [&](const QVariantMap &value) { opened = value; ++openings; });
    until([&] { return manager.installedLoading(); });
    manager.openSource("appstream://org.example.Installed");
    assert(openings == 0 && error.isEmpty());
    until([&] { return openings == 1; });
    assert(opened.value("id") == "org.example.Installed");
    for (const auto &source : {"appstream:org.example.MixedCase", "appstream://org.example.MixedCase.desktop",
                               "flatpak://org.example.MixedCase/", "appstream:org.example.%4DixedCase"}) {
        opened.clear(); error.clear(); manager.openSource(source);
        assert(error.isEmpty() && opened.value("id") == "org.example.MixedCase.desktop");
    }
    for (const auto &source : {"appstream:org.invalid.Missing", "appstream://org.example.MixedCase?bad=1",
                               "appstream://org.example.MixedCase#bad", "appstream:../file",
                               "appstream://user@org.example.MixedCase", "appstream:org.example.MixedCase/other"}) {
        opened.clear(); error.clear(); manager.openSource(source);
        assert(!error.isEmpty() && opened.isEmpty());
    }
    assert(manager.jobs().isEmpty());
    assert(manager.updates().value("state") == "idle");
    qInfo("PASS: AppStream/Flatpak IDs, mixed case, desktop suffix, installed-only apps, deferred loading, unknown/malformed links, no transactions");
}
