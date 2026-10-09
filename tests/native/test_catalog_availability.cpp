// Production manager + isolated worker protocol; no real sources/apps changed.
#include "rust_cache_fixture.h"
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
    if ((argc == 2 || argc == 3) && QByteArray(argv[1]) == "--catalog") {
        QCoreApplication child(argc, argv);
        QFile calls(qEnvironmentVariable("APPCENTER_TEST_CATALOG_CALLS"));
        if (calls.open(QIODevice::WriteOnly | QIODevice::Append)) calls.write("parse\n");
        QThread::msleep(qEnvironmentVariableIntValue("APPCENTER_TEST_CATALOG_DELAY"));
        if (qEnvironmentVariableIsSet("APPCENTER_TEST_CATALOG_FAIL")) return 1;
        // Chunked, duplicated and backwards reports must not reset progress.
        std::cerr << "diagnostic\nAPPCENTER_CATALOG_PROGRESS " << std::flush;
        QThread::msleep(20);
        std::cerr << "85\nAPPCENTER_CATALOG_PROGRESS 73\nAPPCENTER_CATALOG_PROGRESS 100\n"
                  << "APPCENTER_CATALOG_PROGRESS invalid\nAPPCENTER_CATALOG_PROGRESS 98\n" << std::flush;
        QThread::msleep(20);
        const auto apps = QJsonDocument::fromJson(qEnvironmentVariableIsSet("APPCENTER_TEST_CACHED")
            ? "[{\"id\":\"org.example.Cached\",\"name\":\"Cached\"}]" : "[]");
        if (argc == 3) send(CatalogCache::snapshot(QJsonDocument::fromJson(argv[2]).object(),
            apps.array().toVariantList(), CatalogInputs::fingerprint()));
        else std::cout << apps.toJson(QJsonDocument::Compact).constData();
        return 0;
    }
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        QCoreApplication child(argc, argv);
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        assert(request["action"] == "repositories"); // Never an app update check.
        const bool listing = request["operation"] == "list";
        QFile operations(qEnvironmentVariable("APPCENTER_TEST_SOURCE_CALLS"));
        if (operations.open(QIODevice::WriteOnly | QIODevice::Append))
            operations.write(request["operation"].toString().toUtf8() + '\n');
        send({{"type", "sources"}, {"sources", QJsonArray{QJsonObject{{"id", "fixture"}}}}});
        if (!listing) {
            send({{"type", "catalog-progress"}, {"progress", 5}});
            send({{"type", "catalog-progress"}, {"progress", 50}});
            send({{"type", "catalog-progress"}, {"progress", 30}});
        }
        QThread::msleep(qEnvironmentVariableIntValue("APPCENTER_TEST_SOURCE_DELAY"));
        if (!listing) send({{"type", "catalog-load"},
            {"available", qEnvironmentVariableIntValue("APPCENTER_TEST_AVAILABLE")},
            {"failed", qEnvironmentVariableIntValue("APPCENTER_TEST_FAILED")},
            {"refreshed", qEnvironmentVariableIsSet("APPCENTER_TEST_REFRESHED")
                ? qEnvironmentVariableIntValue("APPCENTER_TEST_REFRESHED")
                : qEnvironmentVariableIntValue("APPCENTER_TEST_FAILED") ? 0 : 1}});
        send({{"type", "result"}, {"success", qEnvironmentVariableIntValue("APPCENTER_TEST_FAILED") == 0}});
        return qEnvironmentVariableIntValue("APPCENTER_TEST_FAILED") ? 1 : 0;
    }
    QTemporaryDir temporary; assert(temporary.isValid());
    qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("XDG_CACHE_HOME", (temporary.path() + "/cache").toUtf8());
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
    until([&] { return !manager.catalogLoading() && !manager.busy(); });
    const auto cachePath = temporary.filePath("catalog.json");
    const auto callsPath = temporary.filePath("catalog-calls");
    const auto exclusionsPath = temporary.filePath("exclusions.conf");
    qputenv("FLUFF_APP_CENTER_EXCLUSIONS", exclusionsPath.toUtf8());
    qputenv("APPCENTER_TEST_CATALOG_CALLS", callsPath.toUtf8());
    const auto sourcesPath = temporary.filePath("source-calls");
    qputenv("APPCENTER_TEST_SOURCE_CALLS", sourcesPath.toUtf8());
    qputenv("APPCENTER_TEST_FAILED", "0");
    qputenv("APPCENTER_TEST_AVAILABLE", "1");
    qputenv("APPCENTER_TEST_SOURCE_DELAY", "150");
    const auto sourceCalls = [&] {
        QFile file(sourcesPath); if (!file.open(QIODevice::ReadOnly)) return QByteArray();
        return file.readAll();
    };
    const auto calls = [&] {
        QFile file(callsPath); if (!file.open(QIODevice::ReadOnly)) return 0;
        return int(file.readAll().count('\n'));
    };
    {
        FlatpakManager cold({});
        QList<int> progress;
        QObject::connect(&cold, &FlatpakManager::catalogProgressChanged, &app, [&] {
            const int next = cold.catalogProgress();
            assert(progress.isEmpty() || next >= progress.last());
            assert(next >= 0 && next <= 100);
            if (next == 100) assert(!cold.catalogLoading());
            progress.append(next);
        });
        cold.loadCatalog(cachePath);
        assert(cold.catalogLoading() && cold.catalog().isEmpty());
        until([&] { return !cold.catalogLoading() && !cold.installedLoading(); });
        assert(calls() == 1 && QFileInfo::exists(cachePath));
        assert(sourceCalls() == "refresh\n");
        assert(progress.contains(5) && progress.contains(50) && progress.contains(70)
            && progress.contains(85) && progress.contains(98) && progress.last() == 100);
        assert(!progress.contains(30) && !progress.contains(73));
    }
    {
        FlatpakManager warm({}); warm.loadCatalog(cachePath);
        assert(!warm.catalogLoading() && warm.catalog().size() == 1);
        assert(warm.catalogProgress() == 100);
        until([&] { return !warm.installedLoading(); });
        warm.initializeSources(); until([&] { return !warm.busy(); });
        assert(!warm.catalogLoading() && calls() == 1); // No redundant startup parse.
        assert(sourceCalls() == "refresh\n"); // Fresh cache makes no source request.
        warm.refreshSources(true);
        until([&] { return !warm.busy() && !warm.catalogLoading(); });
        assert(calls() == 2); // Explicit refresh still rebuilds even unchanged data.
    }
    auto saved = CatalogCache::read(cachePath, CatalogInputs::fingerprint());
    assert(saved.valid);
    assert(CatalogCache::write(cachePath, CatalogInputs::fingerprint(), saved.apps,
        QDateTime::currentDateTimeUtc().addDays(-2)));
    {
        qputenv("APPCENTER_TEST_CATALOG_FAIL", "1");
        FlatpakManager stale({}); stale.loadCatalog(cachePath);
        assert(stale.catalogLoading() && stale.catalog().isEmpty());
        until([&] { return !stale.catalogLoading(); });
        assert(stale.catalog().isEmpty() && calls() == 3);
        assert(stale.catalogProgress() < 100); // Failed work never claims completion.
        assert(!CatalogCache::fresh(CatalogCache::read(cachePath, CatalogInputs::fingerprint()).savedAt));
        qunsetenv("APPCENTER_TEST_CATALOG_FAIL");
    }
    {
        FlatpakManager stale({}); stale.loadCatalog(cachePath);
        assert(stale.catalogLoading() && stale.catalog().isEmpty());
        until([&] { return !stale.catalogLoading(); });
        assert(calls() == 4);
        assert(CatalogCache::fresh(CatalogCache::read(cachePath, CatalogInputs::fingerprint()).savedAt));
    }
    QFile exclusions(exclusionsPath); assert(exclusions.open(QIODevice::WriteOnly));
    exclusions.write("org.example.Cached\n"); exclusions.close();
    {
        FlatpakManager changed({}); changed.loadCatalog(cachePath);
        assert(changed.catalogLoading() && changed.catalog().isEmpty());
        until([&] { return !changed.catalogLoading(); });
        assert(calls() == 5); // Exclusion edits cannot reuse a same-day list.
    }
    // If inputs change mid-parse, only the subsequent stable result is cached.
    assert(QFile::remove(cachePath));
    qputenv("APPCENTER_TEST_CATALOG_DELAY", "200");
    {
        FlatpakManager changing({});
        int last = 0;
        QObject::connect(&changing, &FlatpakManager::catalogProgressChanged, &app, [&] {
            assert(changing.catalogProgress() >= last);
            last = changing.catalogProgress();
            if (last == 100) assert(!changing.catalogLoading());
        });
        changing.loadCatalog(cachePath);
        until([&] { return calls() == 6; }); // Inputs change during parsing, not during source refresh.
        assert(exclusions.open(QIODevice::WriteOnly)); exclusions.write("org.example.Other\n"); exclusions.close();
        until([&] { return !changing.catalogLoading(); });
        assert(calls() == 7);
        assert(CatalogCache::read(cachePath, CatalogInputs::fingerprint()).valid);
    }
    // A local-only rebuild must preserve the age of the source refresh.
    saved = CatalogCache::read(cachePath, CatalogInputs::fingerprint()); assert(saved.valid);
    const auto aged = QDateTime::currentDateTimeUtc().addSecs(-3600);
    assert(CatalogCache::write(cachePath, CatalogInputs::fingerprint(), saved.apps, aged));
    {
        FlatpakManager local({}); local.loadCatalog(cachePath);
        assert(!local.catalogLoading());
        until([&] { return !local.installedLoading(); });
        assert(exclusions.open(QIODevice::WriteOnly)); exclusions.write("org.example.Changed\n"); exclusions.close();
        local.refreshSources(false);
        until([&] { return !local.busy() && !local.catalogLoading(); });
        assert(CatalogCache::read(cachePath, CatalogInputs::fingerprint()).savedAt == aged);
    }
    // Fully offline defers refresh until a connection exists. LAN/limited are
    // allowed to attempt it; failed refreshes neither show nor renew old data.
    saved = CatalogCache::read(cachePath, CatalogInputs::fingerprint());
    assert(CatalogCache::write(cachePath, CatalogInputs::fingerprint(), saved.apps, aged.addDays(-1)));
    {
        FlatpakManager offline({}); offline.setCatalogNetworkState("offline", true);
        const auto before = sourceCalls(); offline.loadCatalog(cachePath);
        until([&] { return !offline.installedLoading(); });
        assert(offline.catalog().isEmpty() && !offline.sourcesBusy() && sourceCalls() == before);
        assert(offline.catalogProgress() == 0);
        qputenv("APPCENTER_TEST_FAILED", "1");
        offline.setCatalogNetworkState("local", true);
        until([&] { return !offline.catalogLoading(); });
        assert(sourceCalls() == before + "refresh\n" && offline.catalog().isEmpty());
        assert(offline.catalogSourcesUnavailable());
        assert(offline.catalogProgress() < 100);
        assert(!CatalogCache::fresh(CatalogCache::read(cachePath, CatalogInputs::fingerprint()).savedAt));
        const int beforeListing = calls();
        offline.refreshSources(false); until([&] { return !offline.busy(); });
        assert(offline.catalog().isEmpty() && offline.catalogSourcesUnavailable() && calls() == beforeListing);
        qputenv("APPCENTER_TEST_REFRESHED", "1");
        offline.refreshSources(true); until([&] { return !offline.catalogLoading(); });
        assert(!offline.catalog().isEmpty()); // Partial success is browsable, not cache-renewing.
        assert(!CatalogCache::fresh(CatalogCache::read(cachePath, CatalogInputs::fingerprint()).savedAt));
        qunsetenv("APPCENTER_TEST_REFRESHED");
        qputenv("APPCENTER_TEST_FAILED", "0");
        offline.setCatalogNetworkState("limited", true);
        offline.refreshSources(true);
        until([&] { return !offline.catalogLoading(); });
        assert(!offline.catalog().isEmpty());
        assert(CatalogCache::fresh(CatalogCache::read(cachePath, CatalogInputs::fingerprint()).savedAt));
    }
    // Exercise real input discovery against only this test's user repository.
    auto previous = CatalogInputs::fingerprint(); assert(!previous.isEmpty());
    QFile config(temporary.filePath("data/flatpak/repo/config"));
    assert(config.open(QIODevice::WriteOnly | QIODevice::Append)); config.write("\n"); config.close();
    auto current = CatalogInputs::fingerprint(); assert(!current.isEmpty() && current != previous);
    previous = current;
    QFile deployments(temporary.filePath("data/flatpak/.changed"));
    assert(deployments.open(QIODevice::WriteOnly)); deployments.write("changed"); deployments.close();
    current = CatalogInputs::fingerprint(); assert(!current.isEmpty() && current != previous);
    qInfo("PASS: 12-hour cache, refresh-before-parse, no stale display, no warm source requests, unchanged local rebuild age, offline deferral, LAN/limited failure/recovery, invalidation and parse races");
    qInfo("PASS: nonblocking startup, deferred app links, failed worker, aggregate failures, partial/empty success, Settings, retry, cached fallback, no update checks");
    qInfo("PASS: overall progress, chunked IPC, monotonic retries, completion only after success, no false completion on source/parser failure");
}
