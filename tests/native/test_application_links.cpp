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
    static int checkpoint = 0; ++checkpoint;
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < 6000) { QCoreApplication::processEvents(); QThread::msleep(5); }
    if (!condition()) qFatal("Application-link test timed out at checkpoint %d", checkpoint);
}
int main(int argc, char **argv) {
    if (argc > 1) return 2;
    QTemporaryDir temporary; assert(temporary.isValid());
    qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-app-link-test-bus");
    QFile installedList(temporary.filePath("installed"));
    assert(installedList.open(QIODevice::WriteOnly));
    installedList.write("org.example.Installed\tInstalled\t0\tfixture\tuser\tstable\tx86_64\tFixture app\t1.0\n");
    installedList.close();
    QFile flatpak(temporary.filePath("flatpak")); assert(flatpak.open(QIODevice::WriteOnly));
    flatpak.write("#!/bin/sh\ncase \"$1\" in\nlist) sleep 0.15; cat \""
        + installedList.fileName().toUtf8() + "\";;\n*) exit 1;;\nesac\n");
    flatpak.close(); assert(flatpak.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    qputenv("PATH", temporary.path().toUtf8() + ':' + qgetenv("PATH"));
    QGuiApplication app(argc, argv);
    FlatpakManager manager({QVariantMap{{"id", "org.example.MixedCase.desktop"}, {"name", "Example"},
        {"flatpakRef", "app/org.example.MixedCase/x86_64/stable"}, {"remote", "fixture"}},
        QVariantMap{{"id", "org.example.Collision"}}, QVariantMap{{"id", "org.example.COLLISION"}}});
    QString error; QVariantMap opened; int openings = 0, homes = 0;
    QObject::connect(&manager, &FlatpakManager::inputError, &app, [&](const QString &message) { error = message; });
    QObject::connect(&manager, &FlatpakManager::appOpened, &app, [&](const QVariantMap &value) { opened = value; ++openings; });
    QObject::connect(&manager, &FlatpakManager::homeRequested, &app, [&] { ++homes; });
    until([&] { return manager.installedLoading(); });
    manager.openSource("appstream://org.example.Installed");
    assert(openings == 0 && error.isEmpty());
    until([&] { return openings == 1; });
    assert(opened.value("id") == "org.example.Installed");
    for (const auto &source : {"appstream:org.example.MixedCase", "appstream://org.example.MixedCase.desktop",
                               "flatpak://org.example.MixedCase/", "appstream:org.example.%4DixedCase",
                               "appstream://org.example.mixedcase", "appstream://org.example.mixedcase.desktop"}) {
        opened.clear(); error.clear(); manager.openSource(source);
        assert(error.isEmpty() && opened.value("id") == "org.example.MixedCase.desktop");
    }
    opened.clear(); manager.openSource("appstream://org.example.installed");
    assert(opened.value("id") == "org.example.Installed");
    for (const auto &source : {"appstream:org.invalid.Missing", "appstream://org.example.collision", "appstream://org.example.MixedCase?bad=1",
                               "appstream://org.example.MixedCase#bad", "appstream:../file",
                               "appstream://user@org.example.MixedCase", "appstream:org.example.MixedCase/other"}) {
        opened.clear(); error.clear(); manager.openSource(source);
        assert(!error.isEmpty() && opened.isEmpty());
    }
    // Desktop management links never open uninstalled catalog entries, emit
    // errors, or start transactions. Plain CLI application links still do.
    for (const auto &source : {"appstream://org.example.MixedCase", "appstream://org.invalid.Missing",
            "appstream://org.example.MixedCase?bad=1", "file:///tmp/app.flatpak"}) {
        opened.clear(); error.clear(); const int before = homes;
        manager.openInstalledApplication(source);
        until([&] { return homes == before + 1; });
        assert(opened.isEmpty() && error.isEmpty());
    }
    for (const auto &source : {"appstream://org.example.Installed", "APPSTREAM://org.example.installed.desktop"}) {
        opened.clear(); const int before = openings;
        manager.openInstalledApplication(source);
        assert(opened.isEmpty()); // Wait for a fresh local installation query.
        until([&] { return openings == before + 1; });
        assert(opened.value("id") == "org.example.Installed");
    }
    assert(installedList.open(QIODevice::WriteOnly | QIODevice::Truncate));
    installedList.close();
    opened.clear(); const int before = homes;
    manager.openInstalledApplication("appstream://org.example.Installed");
    until([&] { return homes == before + 1; });
    assert(opened.isEmpty()); // Removal outside App Center invalidates stale data.
    assert(installedList.remove());
    manager.openInstalledApplication("appstream://org.example.Installed");
    until([&] { return homes == before + 2; });
    assert(opened.isEmpty()); // A failed installed-list read must not trust stale data.
    assert(manager.jobs().isEmpty());
    assert(manager.updates().value("state") == "idle");
    qInfo("PASS: CLI links, desktop installed-only/Home fallback, fresh local state, failed reads, mixed case, deferred loading, no transactions");
}
