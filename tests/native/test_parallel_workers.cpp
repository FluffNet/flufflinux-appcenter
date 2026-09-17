// Production manager with isolated installed-list fixtures and fake workers.
// Never installs/removes real apps, changes real history, or signals the desktop.
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSocketNotifier>
#include <QTemporaryDir>
#include <QFile>
#include <QThread>
#include <cassert>
#include <functional>
#include <iostream>
#include <cstdlib>
#include <unistd.h>

static void send(const QJsonObject &message) {
    std::cout << QJsonDocument(message).toJson(QJsonDocument::Compact).constData() << std::endl;
}
static FlatpakManager *testedManager = nullptr;
static void until(const std::function<bool()> &condition) {
    static int checkpoint = 0;
    ++checkpoint;
    QElapsedTimer deadline; deadline.start();
    while (!condition() && deadline.elapsed() < 6000) {
        QCoreApplication::processEvents();
        QThread::msleep(5);
    }
    if (!condition()) {
        if (testedManager) qWarning().noquote() << QJsonDocument::fromVariant(testedManager->jobs()).toJson()
            << QJsonDocument::fromVariant(testedManager->review()).toJson();
        qFatal("Timed out at checkpoint %d", checkpoint);
    }
}
static QVariantMap job(const FlatpakManager &manager, const QString &id) {
    for (const auto &entry : manager.jobs())
        if (entry.toMap().value("id") == id) return entry.toMap();
    return {};
}
static void script(const QString &path, const QByteArray &body) {
    QFile file(path); assert(file.open(QIODevice::WriteOnly));
    assert(file.write(body) == body.size()); file.close();
    assert(file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
}
int main(int argc, char **argv) {
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        QCoreApplication child(argc, argv);
        QTimer::singleShot(15000, &child, [] { std::_Exit(9); }); // Do not orphan a fake worker if a parent assertion fails.
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        const auto id = request["id"].toString();
        const bool removing = request["action"] == "uninstall";
        const auto ref = "app/" + id + "/x86_64/stable";
        if (removing) assert(request["removalConfirmed"].toBool());
        send({{"type", "plan"}, {"operations", QJsonArray{QJsonObject{
            {"ref", ref}, {"action", removing ? "uninstall" : "install"}, {"downloadBytes", 10000000}}}}});
        bool approved = removing;
        if (!removing) send({{"type", "review"}, {"kind", "remote"}, {"token", 77}, {"operations", QJsonArray{}}});
        QSocketNotifier input(STDIN_FILENO, QSocketNotifier::Read);
        QObject::connect(&input, &QSocketNotifier::activated, &child, [&] {
            std::string line;
            if (!std::getline(std::cin, line)) { input.setEnabled(false); return; }
            const auto reply = QJsonDocument::fromJson(QByteArray::fromStdString(line)).object();
            if (reply.contains("token")) {
                assert(!removing && reply["token"].toInt() == 77 && reply["accept"].toBool());
                approved = true;
            }
            // Deliberately ignore Cancel/EOF to exercise only this lane's watchdog.
        });
        QTimer updates; int received = 0;
        QObject::connect(&updates, &QTimer::timeout, &child, [&] {
            if (!approved) return;
            received += 1000;
            send({{"type", "operation"}, {"ref", ref}, {"phase", removing ? "uninstall" : "download"},
                {"progress", 0.4}, {"downloadProgress", 0.4},
                {"status", removing ? "Removing" : "Downloading"}, {"receivedBytes", received}});
        });
        updates.start(25);
        if (removing) {
            QTimer::singleShot(500, &child, [&] {
                updates.stop();
                send({{"type", "operation"}, {"ref", ref}, {"phase", "complete"},
                    {"progress", 1}, {"status", "Complete"}});
            });
            QTimer::singleShot(1000, &child, [&] {
                send({{"type", "result"}, {"success", true}});
                child.quit();
            });
        }
        return child.exec();
    }
    QTemporaryDir temporary; assert(temporary.isValid());
    qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-appcenter-test-bus");
    script(temporary.filePath("flatpak"),
        "#!/bin/sh\nif [ \"$1\" = list ]; then\n"
        "printf 'org.example.RemoveA\tRemove A\t1 MB\tflathub\tuser\tstable\tx86_64\tTest A\t1.0\\n'\n"
        "printf 'org.example.RemoveB\tRemove B\t1 MB\tflathub\tuser\tstable\tx86_64\tTest B\t1.0\\n'\n"
        "printf 'org.example.RemoveC\tRemove C\t1 MB\tflathub\tuser\tstable\tx86_64\tTest C\t1.0\\n'\nfi\n");
    script(temporary.filePath("kbuildsycoca6"), "#!/bin/sh\nexit 0\n");
    qputenv("PATH", temporary.path().toUtf8() + ':' + qgetenv("PATH"));
    QGuiApplication app(argc, argv);
    app.setApplicationName("appcenter-parallel-worker-test");
    FlatpakManager manager({});
    testedManager = &manager;
    until([&] { return !manager.installedLoading(); });
    assert(manager.installedApps().size() == 3);
    const auto a = manager.installedApps()[0].toMap();
    const auto b = manager.installedApps()[1].toMap();
    const auto c = manager.installedApps()[2].toMap();
    const QString download = "org.example.Download";
    manager.installApp({{"id", download}, {"name", "Download"}});
    until([&] { return manager.review().value("kind") == "remote"; });
    const int trustToken = manager.review().value("token").toInt();
    manager.uninstallApp(a);
    assert(manager.review().value("token").toInt() == trustToken); // Never replace an open prompt.
    assert(job(manager, a["id"].toString())["queued"].toBool());
    assert(!job(manager, a["id"].toString())["removalConfirmed"].toBool());
    manager.answerReview(trustToken + 999, true);
    assert(manager.review().value("token").toInt() == trustToken);
    manager.answerReview(trustToken, true);
    until([&] { return manager.review().value("appId") == a["id"]; });
    const int aToken = manager.review().value("token").toInt();
    manager.answerReview(aToken, true);
    until([&] { return job(manager, a["id"].toString()).contains("currentRef")
                       && job(manager, download).contains("currentRef"); });
    assert(job(manager, download)["active"].toBool()); // Removal started before download finished.
    manager.uninstallApp(b);
    manager.answerReview(manager.review().value("token").toInt(), true);
    auto pending = job(manager, b["id"].toString());
    assert(pending["queued"].toBool() && pending["removalConfirmed"].toBool());
    assert(pending["status"] == "Pending…" && !pending.contains("currentRef"));
    manager.uninstallApp(c);
    const int cToken = manager.review().value("token").toInt();
    manager.answerReview(aToken, true); // Old approvals cannot approve a later removal.
    assert(manager.review().value("token").toInt() == cToken);
    until([&] { return job(manager, a["id"].toString())["phase"] == "complete"; });
    assert(job(manager, a["id"].toString())["active"].toBool());
    assert(job(manager, a["id"].toString())["status"] == "Uninstalling…");
    until([&] { return job(manager, b["id"].toString()).contains("currentRef"); });
    assert(!job(manager, a["id"].toString())["active"].toBool());
    assert(job(manager, a["id"].toString())["status"].toString().isEmpty());
    assert(manager.review().value("token").toInt() == cToken); // Other worker's result preserves this prompt.
    const auto bytes = job(manager, download)["receivedBytes"].toLongLong();
    until([&] { return job(manager, download)["receivedBytes"].toLongLong() > bytes; });
    manager.cancelJob(job(manager, download)["index"].toInt());
    assert(job(manager, download).isEmpty());
    manager.answerReview(cToken, false);
    assert(job(manager, c["id"].toString()).isEmpty()); // No never launches a removal.
    until([&] { return !manager.busy(); });
    assert(manager.jobs().size() == 2);
    for (const auto &entry : manager.jobs()) {
        const auto completed = entry.toMap();
        assert(!completed["failed"].toBool() && !completed["cancelled"].toBool());
        assert(completed["status"].toString().isEmpty());
    }
    qInfo("PASS: concurrent download/removal, confirmed pending queue, isolated review tokens and cancellation, truthful cleanup status");
}
