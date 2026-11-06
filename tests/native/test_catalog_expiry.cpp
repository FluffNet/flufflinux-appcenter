// Real Rust state, Qt timers/transport and cache writer. Package workers are
// fixtures in temporary installations; no desktop Flatpak is read or changed.
#include "rust_cache_fixture.h"
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QTemporaryDir>
#include <QThread>
#include <QJsonDocument>
#include <QSocketNotifier>
#include <cassert>
#include <iostream>
#include <unistd.h>

static void send(const QJsonObject &value) {
    std::cout << QJsonDocument(value).toJson(QJsonDocument::Compact).constData() << std::endl;
}
static void write(const QString &path, const QByteArray &bytes, bool executable = false) {
    QFile file(path); assert(file.open(QIODevice::WriteOnly)); file.write(bytes); file.close();
    if (executable) file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
}
static void until(const std::function<bool()> &condition) {
    static int checkpoint = 0;
    ++checkpoint;
    QElapsedTimer deadline; deadline.start();
    while (!condition() && deadline.elapsed() < 12000) { QCoreApplication::processEvents(); QThread::msleep(5); }
    if (!condition()) qFatal("Catalog expiry timed out at checkpoint %d", checkpoint);
}
static QVariantList apps(const QString &name) {
    return {QVariantMap{{"id","org.example.Cached"},{"name",name}}};
}
int main(int argc, char **argv) {
    if (argc > 1) {
        QCoreApplication child(argc, argv);
        const QByteArray mode(argv[1]);
        if (mode == "--catalog") {
            QThread::msleep(500);
            send(CatalogCache::snapshot(QJsonDocument::fromJson(argv[2]).object(),apps("Refreshed fixture"),CatalogInputs::fingerprint()));
            return 0;
        }
        if (mode != "--transaction-worker") return 2;
        const auto request=QJsonDocument::fromJson(argv[2]).object();
        if (request["action"] == "repositories") {
            QFile marker(qEnvironmentVariable("APPCENTER_EXPIRY_CONTROL") + "/refreshes");
            assert(marker.open(QIODevice::Append)); marker.write("refresh\n"); marker.close();
            const bool ok=!qEnvironmentVariableIsSet("APPCENTER_EXPIRY_FAIL");
            send({{"type","catalog-load"},{"available",ok ? 1 : 0},{"failed",ok ? 0 : 1},{"refreshed",ok ? 1 : 0}});
            send({{"type","result"},{"success",ok},{"error",ok ? "" : "offline fixture"}});
            return ok ? 0 : 1;
        }
        if (request["id"] == "org.example.FailedRetry") {
            const auto marker=qEnvironmentVariable("APPCENTER_EXPIRY_CONTROL")+"/retried";
            const bool repeated=QFile::exists(marker);
            write(marker,"attempted");
            send({{"type","result"},{"success",repeated},{"error",repeated ? "" : "network fixture"}});
            return repeated ? 0 : 1;
        }
        const auto ref="app/"+request["id"].toString()+"/x86_64/stable";
        send({{"type","plan"},{"operations",QJsonArray{QJsonObject{{"ref",ref},{"downloadBytes",200}}}}});
        QSocketNotifier input(STDIN_FILENO,QSocketNotifier::Read);
        QObject::connect(&input,&QSocketNotifier::activated,&child,[&] {
            std::string line;
            if (!std::getline(std::cin,line)) { child.quit(); return; }
            if (QJsonDocument::fromJson(QByteArray::fromStdString(line)).object()["cancel"].toBool()) {
                send({{"type","result"},{"success",false},{"cancelled",true}}); child.quit();
            }
        });
        return child.exec();
    }
    QTemporaryDir temp; assert(temp.isValid());
    for (const auto name : {"XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME","FLATPAK_USER_DIR","FLATPAK_SYSTEM_DIR","FLATPAK_CONFIG_DIR"}) {
        const auto path=temp.filePath(name); assert(QDir().mkpath(path)); qputenv(name,path.toUtf8());
    }
    qputenv("APPCENTER_EXPIRY_CONTROL",temp.path().toUtf8());
    write(temp.filePath("flatpak"),"#!/bin/sh\nexit 0\n",true);
    write(temp.filePath("kbuildsycoca6"),"#!/bin/sh\nexit 0\n",true);
    qputenv("PATH",temp.path().toUtf8()+':'+qgetenv("PATH"));
    QGuiApplication app(argc,argv);
    FlatpakManager manager({});
    until([&] { return !manager.installedLoading(); });
    const auto path=temp.filePath("catalog.json");
    const auto age=QDateTime::currentDateTimeUtc().addSecs(-6*3600+2);
    assert(CatalogCache::write(path,CatalogInputs::fingerprint(),apps("Cached fixture"),age));
    manager.loadCatalog(path);
    for (int i=0;i<200;++i) manager.installApp({{"id",QString("org.example.App%1").arg(i)},{"name","Fixture"}});
    assert(manager.jobs().size()==200);
    QElapsedTimer wait; wait.start();
    while (wait.elapsed()<2500) { QCoreApplication::processEvents(); QThread::msleep(5); }
    assert(!QFile::exists(temp.filePath("refreshes")));
    assert(manager.catalog().first().toMap()["name"]=="Cached fixture");
    assert(!manager.catalogLoading());
    manager.cancelAll();
    until([&] { return QFile::exists(temp.filePath("refreshes")); });
    assert(manager.catalog().first().toMap()["name"]=="Cached fixture");
    assert(!manager.catalogLoading());
    until([&] { return !manager.sourcesBusy(); });
    manager.installApp({{"id","org.example.DuringRefresh"},{"name","Queued during refresh"}});
    assert(!manager.jobs().isEmpty() && manager.jobs().last().toMap()["queued"].toBool());
    until([&] { return manager.catalog().first().toMap()["name"]=="Refreshed fixture"; });
    auto cached=CatalogCache::read(path,CatalogInputs::fingerprint());
    assert(cached.valid && cached.savedAt>age && CatalogCache::fresh(cached.savedAt));
    assert(manager.catalog().first().toMap()["name"]=="Refreshed fixture");
    manager.cancelAll(); until([&] { return !manager.backgroundWorkPending(); });
    qputenv("APPCENTER_EXPIRY_FAIL","1");
    assert(CatalogCache::write(path,CatalogInputs::fingerprint(),apps("Stale fallback"),age.addSecs(-3600)));
    QFile original(path); assert(original.open(QIODevice::ReadOnly)); const auto before=original.readAll(); original.close();
    manager.loadCatalog(path);
    until([&] { return !manager.backgroundWorkPending(); });
    assert(manager.catalog().first().toMap()["name"]=="Stale fallback");
    assert(!manager.catalogLoading() && !manager.catalogSourcesUnavailable());
    assert(original.open(QIODevice::ReadOnly) && original.readAll()==before);
    manager.installApp({{"id","org.example.FailedRetry"},{"name","Retry fixture"}});
    until([&] { return !manager.busy() && !manager.jobs().isEmpty()
        && manager.jobs().last().toMap()["canRetry"].toBool(); });
    const auto failed=manager.jobs().last().toMap()["index"].toInt();
    manager.retryJob(failed);
    until([&] { return !manager.busy() && !manager.jobs().isEmpty()
        && !manager.jobs().last().toMap()["active"].toBool(); });
    assert(manager.jobs().size()==1 && !manager.jobs().last().toMap()["failed"].toBool());
    std::cout << "PASS: real expiry timer, 200 queued items, no refresh during work, idle refresh with old catalog visible, queued install waits for cache replacement, atomic cache renewal, failed refresh preserves stale cache and browsing\n";
    std::cout << "PASS: Qt Retry action requeues failed work and completes without an update scan\n";
}
