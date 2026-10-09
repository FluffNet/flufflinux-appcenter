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
        send({{"type", "result"}, {"success", true}});
        return 0;
    }
    QTemporaryDir root;
    QFile flatpak(root.filePath("flatpak")); assert(flatpak.open(QIODevice::WriteOnly));
    flatpak.write("#!/bin/sh\nexit 0\n"); flatpak.close();
    assert(flatpak.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    qputenv("PATH", root.path().toUtf8() + ':' + qgetenv("PATH"));
    qputenv("XDG_DATA_HOME", (root.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (root.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-update-test-bus");
    QGuiApplication app(argc, argv);
    FlatpakManager manager({});
    until([&] { return !manager.installedLoading(); });
    assert(manager.updates()["state"] == "idle");
    assert(manager.updates()["items"].toList().isEmpty());
    manager.refreshInstalled(); until([&] { return !manager.installedLoading(); });
    assert(manager.updates()["state"] == "idle"); // No indirect check.
    auto check = [&] {
        manager.checkForUpdates(); assert(manager.updates()["state"] == "checking");
        assert(manager.jobs().isEmpty());
        until([&] { return !manager.busy(); });
    };
    check();
    auto rows = manager.updates()["items"].toList();
    assert(rows.size() == 3);
    for (const auto &row : rows) assert(row.toMap()["selected"].toBool());
    manager.selectAllUpdates(false);
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
