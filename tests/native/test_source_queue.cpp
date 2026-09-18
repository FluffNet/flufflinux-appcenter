// Production manager, fake worker protocol. No network or real Flatpak changes.
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
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
static void script(const QString &path, const QByteArray &body) {
    QFile file(path); assert(file.open(QIODevice::WriteOnly));
    assert(file.write(body) == body.size()); file.close();
    assert(file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
}
int main(int argc, char **argv) {
    if (argc == 2 && QByteArray(argv[1]) == "--catalog") { std::cout << "[]"; return 0; }
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        QCoreApplication child(argc, argv);
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        if (request["action"] == "repositories") {
            send({{"type", "sources"}, {"sources", QJsonArray{}}});
            send({{"type", "result"}, {"success", true}}); return 0;
        }
        const QString source = request["source"].toString();
        const bool preparation = request["prepareOnly"].toBool();
        if (source.contains("crash")) return 7;
        QTimer::singleShot(40, &child, [&] {
            const bool fail = source.contains("fail"), cancel = source.contains("cancel");
            if (!fail && !cancel && !source.endsWith("flatpakrepo")) {
                send({{"type", "plan"}, {"appId", "org.example.Local"}, {"operations", QJsonArray{QJsonObject{
                    {"ref", "app/org.example.Local/x86_64/stable"}, {"action", "install-bundle"}}}}});
            }
            send({{"type", "result"}, {"success", !fail && !cancel}, {"cancelled", cancel},
                {"error", fail ? "Source fixture failed" : ""}});
            child.quit();
        });
        // The source is still the same input on the second, visible install.
        if (!preparation) assert(request["hidden"].toBool() == false);
        return child.exec();
    }
    QTemporaryDir temporary; assert(temporary.isValid());
    qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-source-queue-test-bus");
    script(temporary.filePath("flatpak"), "#!/bin/sh\nexit 0\n");
    script(temporary.filePath("kbuildsycoca6"), "#!/bin/sh\nexit 0\n");
    qputenv("PATH", temporary.path().toUtf8() + ':' + qgetenv("PATH"));
    QGuiApplication app(argc, argv);
    FlatpakManager manager({});
    until([&] { return !manager.installedLoading(); });
    QString error; QVariantMap opened;
    QObject::connect(&manager, &FlatpakManager::inputError, &app, [&](const QString &message) { error = message; });
    QObject::connect(&manager, &FlatpakManager::appOpened, &app, [&](const QVariantMap &value) { opened = value; });
    bool preparing = true;
    QObject::connect(&manager, &FlatpakManager::jobsChanged, &app, [&] {
        if (preparing) assert(manager.jobs().isEmpty()); // Includes every transient state.
    });
    for (const auto &name : {"source.flatpakrepo", "fail.flatpakrepo", "fail.flatpakref", "fail.flatpak",
                            "cancel.flatpakrepo", "crash.flatpakrepo", "local.flatpak"}) {
        error.clear();
        script(temporary.filePath(name), "fixture");
        manager.openSource(temporary.filePath(name));
        until([&] { return !manager.busy(); });
        assert(manager.jobs().isEmpty());
        const QString file(name);
        assert(error.isEmpty() == (!file.startsWith("fail") && !file.startsWith("crash")));
    }
    assert(opened.value("id") == "org.example.Local");
    preparing = false;
    manager.installApp(opened);
    assert(manager.jobs().size() == 1);
    assert(manager.jobs().first().toMap().value("active").toBool());
    until([&] { return !manager.busy(); });
    assert(manager.jobs().size() == 1);
    assert(!manager.jobs().first().toMap().value("failed").toBool());
    assert(!manager.jobs().first().toMap().value("active").toBool());
    manager.clearDownloadHistory(); assert(manager.jobs().isEmpty());
    qInfo("PASS: source success/failure/cancellation/crash stay out of Queue; errors are reported; local installation is visible");
}
