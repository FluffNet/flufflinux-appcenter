// Production manager + isolated worker protocol; no real sources/apps changed.
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QFile>
#include <QThread>
#include <cassert>
#include <functional>
#include <iostream>

static void send(const QJsonObject &message) {
    std::cout << QJsonDocument(message).toJson(QJsonDocument::Compact).constData() << std::endl;
}
static void until(const std::function<bool()> &condition) {
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < 6000) {
        QCoreApplication::processEvents(); QThread::msleep(5);
    }
    assert(condition());
}
int main(int argc, char **argv) {
    if (argc == 2 && QByteArray(argv[1]) == "--catalog") {
        QThread::msleep(qEnvironmentVariableIntValue("APPCENTER_TEST_CATALOG_DELAY"));
        if (qEnvironmentVariableIsSet("APPCENTER_TEST_CATALOG_FAIL")) return 1;
        std::cout << (qEnvironmentVariableIsSet("APPCENTER_TEST_CACHED")
            ? "[{\"id\":\"org.example.Cached\",\"name\":\"Cached\"}]" : "[]");
        return 0;
    }
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        QCoreApplication child(argc, argv);
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        assert(request["action"] == "repositories"); // Never an app update check.
        const bool listing = request["operation"] == "list";
        send({{"type", "sources"}, {"sources", QJsonArray{QJsonObject{{"id", "fixture"}}}}});
        if (!listing) send({{"type", "catalog-load"},
            {"available", qEnvironmentVariableIntValue("APPCENTER_TEST_AVAILABLE")},
            {"failed", qEnvironmentVariableIntValue("APPCENTER_TEST_FAILED")}});
        send({{"type", "result"}, {"success", qEnvironmentVariableIntValue("APPCENTER_TEST_FAILED") == 0}});
        return 0;
    }
    QTemporaryDir temporary; assert(temporary.isValid());
    qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-catalog-test-bus");
    QFile flatpak(temporary.filePath("flatpak")); assert(flatpak.open(QIODevice::WriteOnly));
    flatpak.write("#!/bin/sh\nexit 0\n"); flatpak.close();
    assert(flatpak.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    qputenv("PATH", temporary.path().toUtf8() + ':' + qgetenv("PATH"));
    QGuiApplication app(argc, argv);
    FlatpakManager manager({});
    until([&] { return !manager.installedLoading(); });
    qputenv("APPCENTER_TEST_CACHED", "1");
    qputenv("APPCENTER_TEST_CATALOG_DELAY", "200");
    QString opened, error;
    QObject::connect(&manager, &FlatpakManager::appOpened, &app,
        [&](const QVariantMap &value) { opened = value.value("id").toString(); });
    QObject::connect(&manager, &FlatpakManager::inputError, &app,
        [&](const QString &message) { error = message; });
    QElapsedTimer load; load.start();
    manager.loadCatalog();
    assert(load.elapsed() < 100 && manager.catalogLoading());
    manager.openSource("appstream:org.example.Cached");
    assert(opened.isEmpty() && error.isEmpty());
    until([&] { return !manager.catalogLoading() && !opened.isEmpty(); });
    assert(opened == "org.example.Cached" && error.isEmpty());
    qputenv("APPCENTER_TEST_CATALOG_FAIL", "1");
    manager.loadCatalog();
    until([&] { return !manager.catalogLoading(); });
    assert(!manager.catalog().isEmpty()); // A failed refresh retains usable data.
    qunsetenv("APPCENTER_TEST_CATALOG_FAIL");
    qunsetenv("APPCENTER_TEST_CATALOG_DELAY");
    qunsetenv("APPCENTER_TEST_CACHED");
    manager.loadCatalog();
    until([&] { return !manager.catalogLoading() && !manager.installedLoading(); });
    assert(!manager.catalogSourcesUnavailable());
    const auto refresh = [&](int available, int failed) {
        qputenv("APPCENTER_TEST_AVAILABLE", QByteArray::number(available));
        qputenv("APPCENTER_TEST_FAILED", QByteArray::number(failed));
        manager.refreshSources(true);
        assert(!manager.catalogSourcesUnavailable()); // Loading is not failure.
        until([&] { return !manager.busy(); });
    };
    refresh(0, 2); assert(manager.catalogSourcesUnavailable());
    manager.refreshSources(false);
    until([&] { return !manager.busy(); });
    assert(manager.catalogSourcesUnavailable()); // Opening Settings preserves failure.
    refresh(1, 2); assert(!manager.catalogSourcesUnavailable()); // Partial success.
    refresh(0, 0); assert(!manager.catalogSourcesUnavailable()); // No enabled sources.
    refresh(1, 0); assert(!manager.catalogSourcesUnavailable()); // Valid empty catalog.
    refresh(0, 1); assert(manager.catalogSourcesUnavailable()); // Subsequent failure.
    qputenv("APPCENTER_TEST_CACHED", "1");
    refresh(0, 1);
    until([&] { return !manager.catalog().isEmpty(); });
    assert(!manager.catalogSourcesUnavailable()); // System/cache fallback stays browsable.
    assert(manager.updates().value("state") == "idle");
    qInfo("PASS: nonblocking startup, deferred app links, failed worker, aggregate failures, partial/empty success, Settings, retry, cached fallback, no update checks");
}
