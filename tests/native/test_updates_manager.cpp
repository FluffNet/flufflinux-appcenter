// Production manager, fake subprocesses, isolated state. No real app changes.
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QThread>
#include <cassert>
#include <functional>
#include <iostream>

static void send(const QJsonObject &message) {
    std::cout << QJsonDocument(message).toJson(QJsonDocument::Compact).constData() << std::endl;
}
static void until(const std::function<bool()> &condition) {
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < 6000) { QCoreApplication::processEvents(); QThread::msleep(5); }
    assert(condition());
}
int main(int argc, char **argv) {
    if (argc == 2 && QByteArray(argv[1]) == "--catalog") { std::cout << "[]\n"; return 0; }
    if (argc == 3 && QByteArray(argv[1]) == "--updates-worker") {
        assert(QJsonDocument::fromJson(argv[2]).object()["restoreSystemFlathub"].toBool());
        const auto mode = qgetenv("UPDATE_TEST_MODE");
        if (mode == "crash") return 5;
        if (mode == "invalid") { std::cout << "bad json\n"; return 0; }
        if (mode == "slow") QThread::msleep(1500);
        if (mode == "restored") send({{"type", "sources"}, {"sources", QJsonArray{
            QJsonObject{{"name", "flathub"}, {"scope", "merged"}, {"hasUser", true}, {"hasSystem", true}}}}});
        QJsonArray rows;
        for (const auto &scope : {"user", "system", "extra"}) {
            const QString ref = "app/org.example.Test.desktop/x86_64/stable";
            rows.append(QJsonObject{{"key", QString(scope) + ":" + ref}, {"id", "org.example.Test.desktop"},
                {"flatpakRef", ref}, {"installation", scope}, {"name", "Test"}, {"selected", false},
                {"commit", QString(64, 'a')}, {"oldCommit", QString(64, 'b')}, {"plan", QJsonArray{}}});
        }
        send({{"type", "updates"}, {"updates", rows},
            {"skipped", mode == "partial" ? QJsonArray{"Skipped missing-source app"} : QJsonArray{}},
            {"errors", mode == "partial" ? QJsonArray{"One source is offline"} : QJsonArray{}},
            {"checkedAt", "2026-09-23T12:00:00.000Z"}});
        return 0;
    }
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        if (request["action"] == "repositories") {
            send({{"type", "sources"}, {"sources", QJsonArray{}}});
            send({{"type", "result"}, {"success", true}});
            return 0;
        }
        assert(request["action"] == "update");
        assert(request["id"] == "org.example.Test.desktop");
        assert(request["installation"] != "system"); // Unselected deployment.
        send({{"type", "plan"}, {"operations", QJsonArray{QJsonObject{{"ref", request["flatpakRef"]},
            {"commit", request["commit"]}, {"downloadBytes", 1000}}}}});
        send({{"type", "operation"}, {"ref", request["flatpakRef"]}, {"phase", "download"},
            {"progress", 0.5}, {"downloadProgress", 0.5}, {"receivedBytes", 500}});
        send({{"type", "result"}, {"success", true}});
        return 0;
    }
    QTemporaryDir root;
    QFile flatpak(root.filePath("flatpak")); assert(flatpak.open(QIODevice::WriteOnly));
    flatpak.write("#!/bin/sh\nif [ \"$1\" = list ] && [ -n \"$APPCENTER_INSTALLED_VERSION\" ]; then\n"
        "printf 'org.example.InstalledDiff\\tInstalled\\t1 MB\\tfixture\\tuser\\tstable\\tx86_64\\tTest\\t%s\\n' \"$APPCENTER_INSTALLED_VERSION\"\nfi\n"); flatpak.close();
    assert(flatpak.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    qputenv("PATH", root.path().toUtf8() + ':' + qgetenv("PATH"));
    qputenv("XDG_DATA_HOME", (root.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (root.path() + "/config").toUtf8());
    qputenv("FLATPAK_USER_DIR", (root.path() + "/user").toUtf8());
    qputenv("FLATPAK_SYSTEM_DIR", (root.path() + "/system").toUtf8());
    qputenv("FLATPAK_CONFIG_DIR", (root.path() + "/flatpak-config").toUtf8());
    qunsetenv("APPCENTER_INSTALLED_VERSION");
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-update-test-bus");
    QGuiApplication app(argc, argv);
    FlatpakManager manager({});
    const int imageToken = manager.requestScreenshots({"https://example.org/one.png", "https://example.org/two.png"});
    assert(imageToken > 0 && manager.screenshotFiles().size() == 2);
    manager.cancelScreenshots(imageToken);
    assert(manager.screenshotFiles().isEmpty());
    QVariantList updateMirror = manager.updateItems();
    int updateSnapshots = 0, updateRowChanges = 0;
    QObject::connect(&manager, &FlatpakManager::updateItemsSnapshotChanged, &app, [&] {
        updateMirror = manager.updateItems();
        ++updateSnapshots;
    });
    QObject::connect(&manager, &FlatpakManager::updateItemRowsChanged, &app, [&](const QVariantMap &rows) {
        const auto removed = rows.value("removed").toList();
        for (auto row = removed.rbegin(); row != removed.rend(); ++row) updateMirror.removeAt(row->toInt());
        for (auto it = rows.begin(); it != rows.end(); ++it) {
            if (it.key() == "removed") continue;
            const int row = it.key().toInt();
            assert(row >= 0 && row < updateMirror.size());
            updateMirror[row] = it.value();
            ++updateRowChanges;
        }
        assert(updateMirror == manager.updateItems());
    });
    QVariantList mirror = manager.jobs();
    int changedRows = 0;
    QObject::connect(&manager, &FlatpakManager::jobsSnapshotChanged, &app, [&] { mirror = manager.jobs(); });
    QObject::connect(&manager, &FlatpakManager::jobRowsChanged, &app, [&](const QVariantMap &rows) {
        for (auto it = rows.begin(); it != rows.end(); ++it) {
            const int row = it.key().toInt();
            assert(row >= 0 && row < mirror.size());
            mirror[row] = it.value();
            ++changedRows;
        }
        assert(mirror == manager.jobs());
    });
    until([&] { return !manager.installedLoading(); });
    assert(manager.updates()["state"] == "idle");
    assert(manager.updates()["items"].toList().isEmpty());
    int installedSnapshots = 0;
    QObject::connect(&manager, &FlatpakManager::installedAppsChanged, &app, [&] { ++installedSnapshots; });
    manager.refreshInstalled(); until([&] { return !manager.installedLoading(); });
    assert(installedSnapshots == 0); // Loading/error/icon changes do not republish an unchanged list.
    assert(manager.updates()["state"] == "idle"); // No indirect check.
    QVariantList installedMirror = manager.installedApps();
    int installedRowChanges = 0;
    QObject::connect(&manager, &FlatpakManager::installedAppsSnapshotChanged, &app,
        [&] { installedMirror = manager.installedApps(); });
    QObject::connect(&manager, &FlatpakManager::installedAppRowsChanged, &app, [&](const QVariantMap &rows) {
        for (auto it = rows.begin(); it != rows.end(); ++it) {
            const int row = it.key().toInt();
            assert(row >= 0 && row < installedMirror.size());
            installedMirror[row] = it.value();
            ++installedRowChanges;
        }
        assert(installedMirror == manager.installedApps());
    });
    qputenv("APPCENTER_INSTALLED_VERSION", "1");
    manager.refreshInstalled(); until([&] { return !manager.installedLoading(); });
    assert(installedMirror.size() == 1);
    qputenv("APPCENTER_INSTALLED_VERSION", "2");
    manager.refreshInstalled(); until([&] { return !manager.installedLoading(); });
    assert(installedRowChanges == 1 && installedMirror[0].toMap()["installedVersion"] == "2");
    qunsetenv("APPCENTER_INSTALLED_VERSION");
    manager.refreshInstalled(); until([&] { return !manager.installedLoading(); });
    assert(installedMirror.isEmpty());
    auto check = [&] {
        manager.checkForUpdates(); assert(manager.updates()["state"] == "checking");
        assert(manager.jobs().isEmpty());
        until([&] { return !manager.busy(); });
    };
    check();
    auto rows = manager.updates()["items"].toList();
    assert(rows.size() == 3);
    assert(updateMirror == rows && !manager.updateStatus().contains("items"));
    const int snapshotsBeforeSelection = updateSnapshots;
    for (const auto &row : rows) assert(row.toMap()["selected"].toBool());
    manager.selectAllUpdates(false);
    assert(updateSnapshots == snapshotsBeforeSelection && updateRowChanges == 3);
    for (const auto &row : manager.updates()["items"].toList()) assert(!row.toMap()["selected"].toBool());
    manager.selectAllUpdates(true);
    for (const auto &row : rows) if (row.toMap()["installation"] == "system") manager.selectUpdate(row.toMap()["key"].toString(), false);
    manager.selectUpdate("forged:app/org.example.Other/x86_64/stable", true);
    assert(manager.updates()["items"].toList().size() == 3);
    qputenv("UPDATE_TEST_MODE", "slow");
    manager.checkForUpdates(); manager.cancelUpdateCheck();
    until([&] { return !manager.busy(); });
    assert(manager.updates()["state"] == "cancelled" && manager.updates()["items"].toList().isEmpty());
    manager.checkForUpdates();
    auto timer = manager.findChild<QTimer *>("updatesWorkTimeout"); assert(timer); timer->start(20);
    until([&] { return !manager.busy(); });
    assert(manager.updates()["state"] == "error");
    assert(manager.updates()["error"].toString().contains("timed out"));
    for (const auto &mode : {"crash", "invalid"}) {
        qputenv("UPDATE_TEST_MODE", mode); check();
        assert(manager.updates()["state"] == "error");
        assert(manager.updates()["items"].toList().isEmpty());
    }
    qputenv("UPDATE_TEST_MODE", "partial"); check();
    assert(manager.updates()["skipped"].toStringList() == QStringList{"Skipped missing-source app"});
    assert(manager.updates()["state"] == "ready" && !manager.updates()["error"].toString().isEmpty());
    for (const auto &row : manager.updates()["items"].toList())
        if (row.toMap()["installation"] == "system") manager.selectUpdate(row.toMap()["key"].toString(), false);
    manager.installSelectedUpdates();
    manager.installSelectedUpdates(); // Busy double-click must not duplicate.
    until([&] { return !manager.busy(); });
    assert(manager.jobs().size() == 2);
    assert(changedRows > 0 && mirror == manager.jobs());
    assert(manager.updates()["items"].toList().size() == 1);
    assert(manager.updates()["items"].toList()[0].toMap()["installation"] == "system");
    assert(manager.updates()["state"] == "ready"); // Completion never triggers a check.
    qputenv("UPDATE_TEST_MODE", "restored"); manager.checkForUpdates();
    until([&] { return !manager.busy(); });
    assert(manager.repositories().size() == 1);
    assert(manager.repositories()[0].toMap()["hasSystem"].toBool());
    assert(manager.updates()["items"].toList().size() == 3);
    manager.refreshSources(true);
    assert(manager.updates()["state"] == "idle" && manager.updates()["items"].toList().isEmpty());
    until([&] { return !manager.busy(); });
    assert(manager.updates()["state"] == "idle"); // Source changes invalidate; they never trigger a check.
    std::cout << "PASS: no automatic checks, defaults, selection, scopes, exact .desktop ID, cancel, timeout, crash, malformed output, partial errors, selected jobs only, duplicate prevention\n";
}
