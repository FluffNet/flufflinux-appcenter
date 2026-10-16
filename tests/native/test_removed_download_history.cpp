// Exercise the production manager with fake installations in an isolated
// temporary directory. Never install or remove a real Flatpak or its data.
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
static void write(const QString &path, const QByteArray &body = {}) {
    QFile file(path); assert(file.open(QIODevice::WriteOnly));
    assert(file.write(body) == body.size());
}
static QVariantMap installed(const FlatpakManager &manager, const QString &id) {
    for (const auto &entry : manager.installedApps())
        if (entry.toMap().value("id") == id) return entry.toMap();
    return {};
}
static QVariantMap download(const FlatpakManager &manager, const QString &id) {
    QVariantMap found;
    for (const auto &entry : manager.jobs()) {
        const auto job = entry.toMap();
        if (job.value("id") == id && job.value("action") != "uninstall") found = job;
    }
    return found;
}
int main(int argc, char **argv) {
    if (argc == 2 && QByteArray(argv[1]) == "--catalog") { std::cout << "[]"; return 0; }
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        QCoreApplication child(argc, argv);
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        const auto id = request["id"].toString();
        const bool removing = request["action"] == "uninstall";
        const auto marker = qEnvironmentVariable("XDG_DATA_HOME") + "/installed-" + id;
        send({{"type", "plan"}, {"operations", QJsonArray{QJsonObject{
            {"ref", "app/" + id + "/x86_64/stable"}, {"action", removing ? "uninstall" : "install"}}}}});
        QTimer::singleShot(id.endsWith("Active") ? 5000 : 50, &child, [&] {
            const bool fail = removing && QFile::exists(qEnvironmentVariable("XDG_DATA_HOME") + "/fail-removal");
            if (!fail) {
                if (removing) { assert(request["removalConfirmed"].toBool()); assert(QFile::remove(marker)); }
                else write(marker);
            }
            send({{"type", "result"}, {"success", !fail}, {"error", fail ? "Simulated removal failure" : ""}});
            child.quit();
        });
        return child.exec();
    }
    if (argc > 1) return 2; // Unknown worker modes must not rerun the test.
    QTemporaryDir temporary; assert(temporary.isValid());
    const auto data = temporary.path() + "/data";
    assert(QDir().mkpath(data));
    qputenv("XDG_DATA_HOME", data.toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-history-test-bus");
    const auto flatpak = temporary.filePath("flatpak");
    write(flatpak, "#!/bin/sh\nif [ \"$1\" = list ]; then\n"
        "for id in org.example.History org.example.Other; do\n"
        "if [ -e \"$XDG_DATA_HOME/installed-$id\" ]; then\n"
        "printf '%s\\t%s\\t1 MB\\tflathub\\tuser\\tstable\\tx86_64\\tFixture\\t1.0\\n' \"$id\" \"$id\"\n"
        "fi\ndone\nfi\n");
    write(temporary.filePath("kbuildsycoca6"), "#!/bin/sh\nexit 0\n");
    for (const auto &path : {flatpak, temporary.filePath("kbuildsycoca6")})
        assert(QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    qputenv("PATH", temporary.path().toUtf8() + ':' + qgetenv("PATH"));
    QGuiApplication app(argc, argv);
    FlatpakManager manager({});
    until([&] { return !manager.installedLoading(); });
    const QString id = "org.example.History", other = "org.example.Other", active = "org.example.Active";
    for (const auto &target : {id, other}) {
        manager.installApp({{"id", target}, {"name", target}});
        until([&] { return !manager.busy() && !installed(manager, target).isEmpty(); });
    }
    const int originalIndex = download(manager, id).value("index").toInt();
    manager.uninstallApp(installed(manager, id));
    manager.answerReview(manager.review().value("token").toInt(), false);
    assert(!download(manager, id).isEmpty()); // No preserves history.
    write(data + "/fail-removal");
    manager.uninstallApp(installed(manager, id));
    manager.answerReview(manager.review().value("token").toInt(), true);
    until([&] { return !manager.busy(); });
    assert(!download(manager, id).isEmpty()); // Failure preserves history.
    assert(QFile::remove(data + "/fail-removal"));
    manager.installApp({{"id", active}, {"name", active}});
    const int activeIndex = download(manager, active).value("index").toInt();
    manager.uninstallApp(installed(manager, id));
    manager.answerReview(manager.review().value("token").toInt(), true);
    until([&] { return installed(manager, id).isEmpty() && download(manager, id).isEmpty(); });
    assert(!download(manager, other).isEmpty());
    assert(download(manager, active).value("active").toBool());
    assert(download(manager, active).value("index").toInt() == activeIndex);
    manager.cancelJob(activeIndex);
    until([&] { return !manager.busy(); });
    manager.installApp({{"id", id}, {"name", id}});
    until([&] { return !manager.busy() && !installed(manager, id).isEmpty(); });
    assert(download(manager, id).value("index").toInt() > originalIndex);
    qInfo("PASS: successful uninstall hides old Downloads history; No/failure, other apps, active work and reinstall are preserved");
}
