// Real manager/controller and KDE libraries on an isolated test D-Bus.
// Workers and power/job services are fixtures; no real apps are changed.
#include "../../src/background_queue.h"
#include "../../src/flatpak_manager.h"
#include <QApplication>
#include <QWindow>
#include <QDBusVirtualObject>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusArgument>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonArray>
#include <QThread>
#include <QSocketNotifier>
#include <cassert>
#include <iostream>
#include <unistd.h>

class Desktop final : public QDBusVirtualObject {
public:
    int created = 0, inhibits = 0, releases = 0;
    QMap<QString, QVariantMap> views;
    QList<uint> results;
    QString introspect(const QString &) const override { return {}; }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &bus) override {
        const auto args = message.arguments();
        if (message.member() == "requestView") {
            const auto path = QString("/JobViewServer/Job%1").arg(++created);
            views[path] = qdbus_cast<QVariantMap>(args[2]);
            bus.send(message.createReply(QVariant::fromValue(QDBusObjectPath(path))));
        } else if (message.member() == "update") {
            views[message.path()].insert(qdbus_cast<QVariantMap>(args[0]));
            bus.send(message.createReply());
        } else if (message.member() == "terminate") {
            results << args[0].toUInt(); views.remove(message.path());
            bus.send(message.createReply());
        } else if (message.member() == "Inhibit") {
            ++inhibits; bus.send(message.createReply(QVariant::fromValue(uint(inhibits))));
        } else if (message.member() == "UnInhibit") {
            ++releases; bus.send(message.createReply());
        } else return false;
        return true;
    }
};
static void waitFor(const std::function<bool()> &condition) {
    static int checkpoint = 0; ++checkpoint;
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < 6000) { QCoreApplication::processEvents(); QThread::msleep(5); }
    if (!condition()) qFatal("Background test timed out at checkpoint %d", checkpoint);
}
static void write(const QString &path, const QByteArray &data, bool executable = false) {
    QFile file(path); assert(file.open(QIODevice::WriteOnly)); file.write(data); file.close();
    if (executable) file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
}
static void send(const QJsonObject &event) { std::cout << QJsonDocument(event).toJson(QJsonDocument::Compact).constData() << std::endl; }

int main(int argc, char **argv) {
    if (argc == 2 && QByteArray(argv[1]) == "--catalog") { std::cout << "[]"; return 0; }
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        QCoreApplication worker(argc, argv);
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        if (request["action"] == "repositories") { send({{"type", "sources"}, {"sources", QJsonArray{}}}); return 0; }
        const auto ref = "app/" + request["id"].toString() + "/x86_64/stable";
        send({{"type", "plan"}, {"operations", QJsonArray{QJsonObject{{"ref", ref}, {"action", "install"}, {"downloadBytes", 1048576}}}}});
        send({{"type", "operation"}, {"ref", ref}, {"phase", "download"}, {"progress", .5},
              {"downloadProgress", .5}, {"receivedBytes", 524288}, {"status", "Downloading"}});
        QSocketNotifier input(STDIN_FILENO, QSocketNotifier::Read);
        QObject::connect(&input, &QSocketNotifier::activated, &worker, [&] {
            std::string line;
            if (!std::getline(std::cin, line)) { input.setEnabled(false); return; }
            if (QJsonDocument::fromJson(QByteArray::fromStdString(line)).object()["cancel"].toBool()) {
                send({{"type", "result"}, {"success", false}, {"cancelled", true}}); worker.quit();
            }
        });
        QTimer poll;
        QObject::connect(&poll, &QTimer::timeout, &worker, [&] {
            QFile signal(qEnvironmentVariable("BACKGROUND_TEST_CONTROL") + "/" + request["id"].toString());
            if (!signal.open(QIODevice::ReadOnly)) return;
            const auto command = signal.readAll();
            if (command == "crash") std::_Exit(7);
            send({{"type", "result"}, {"success", command == "ok"}, {"error", "Fixture failure"}}); worker.quit();
        });
        poll.start(20); QTimer::singleShot(20000, &worker, &QCoreApplication::quit);
        return worker.exec();
    }
    QTemporaryDir temp; assert(temp.isValid());
    for (const auto variable : {"XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "BACKGROUND_TEST_CONTROL"})
        qputenv(variable, temp.path().toUtf8());
    write(temp.filePath("flatpak"), "#!/bin/sh\nif [ \"$1\" = list ]; then printf 'org.example.Remove\\tRemove\\t1 MB\\tflathub\\tuser\\tstable\\tx86_64\\tTest\\t1.0\\n'; fi\n", true);
    write(temp.filePath("kbuildsycoca6"), "#!/bin/sh\nexit 0\n", true);
    qputenv("PATH", temp.path().toUtf8() + ':' + qgetenv("PATH"));
    QApplication app(argc, argv); app.setQuitOnLastWindowClosed(false);
    Desktop desktop; auto bus = QDBusConnection::sessionBus();
    assert(bus.registerService("org.kde.JobViewServer"));
    assert(bus.registerService("org.freedesktop.PowerManagement.Inhibit"));
    assert(bus.registerVirtualObject("/JobViewServer", &desktop, QDBusConnection::SubPath));
    assert(bus.registerVirtualObject("/org/freedesktop/PowerManagement/Inhibit", &desktop));
    FlatpakManager manager({}); QWindow window; window.show();
    BackgroundQueue background(&manager, &window, [&] { window.show(); });
    waitFor([&] { return !manager.installedLoading(); });
    auto install = [&](const QString &id) { manager.installApp({{"id", id}, {"name", id}}); };
    install("org.example.A"); install("org.example.B");
    waitFor([&] { return desktop.inhibits == 1 && manager.jobs()[0].toMap().value("receivedBytes").toInt() == 524288; });
    assert(background.inhibiting() && background.trackedJobs() == 0 && desktop.created == 0);
    window.showMinimized(); QCoreApplication::processEvents(); assert(!background.closed());
    window.showNormal(); window.close();
    waitFor([&] { return desktop.views.size() == 1 && desktop.views.first().value("processedBytes").toULongLong() == 524288; });
    assert(background.closed() && !window.isVisible() && background.trackedJobs() == 1);
    assert(desktop.views.first().value("totalBytes").toULongLong() == 1048576);
    assert(desktop.views.first().value("percent").toUInt() == 45);
    window.show(); waitFor([&] { return desktop.views.isEmpty(); });
    assert(!background.closed() && manager.busy() && desktop.results.last() == 1 && background.inhibiting());
    window.close(); waitFor([&] { return desktop.views.size() == 1; });
    write(temp.filePath("org.example.A"), "fail");
    waitFor([&] { return desktop.results.size() == 2 && desktop.views.size() == 1; });
    assert(desktop.results.last() >= 100 && background.inhibiting());
    write(temp.filePath("org.example.B"), "ok");
    waitFor([&] { return desktop.results.size() == 3 && desktop.releases == 1 && !manager.busy(); });
    assert(desktop.results.last() == 0 && !background.inhibiting());
    window.show(); install("org.example.Cancel"); window.close();
    waitFor([&] { return desktop.views.size() == 1 && desktop.inhibits == 2
        && desktop.views.first().value("processedBytes").toULongLong() == 524288; });
    auto cancel = QDBusMessage::createSignal(desktop.views.firstKey(), "org.kde.JobViewV3", "cancelRequested"); bus.send(cancel);
    waitFor([&] { return desktop.views.isEmpty() && desktop.releases == 2 && !manager.busy(); });
    assert(desktop.results.last() == 1);
    window.show(); install("org.example.Crash"); window.close();
    waitFor([&] { return desktop.views.size() == 1 && desktop.inhibits == 3; });
    write(temp.filePath("org.example.Crash"), "crash");
    waitFor([&] { return desktop.views.isEmpty() && desktop.releases == 3 && !manager.busy(); });
    assert(desktop.results.last() >= 100);
    window.show();
    manager.uninstallApp({{"id", "org.example.Remove"}, {"name", "Remove"}, {"installation", "user"}, {"installedArch", "x86_64"}, {"installedBranch", "stable"}});
    window.close(); assert(!background.inhibiting() && background.trackedJobs() == 0);
    waitFor([&] { return !manager.review().isEmpty(); }); // Hidden reviews are never auto-approved.
    manager.answerReview(manager.review().value("token").toInt(), true);
    waitFor([&] { return background.trackedJobs() == 1 && desktop.inhibits == 4; });
    write(temp.filePath("org.example.Remove"), "ok");
    waitFor([&] { return desktop.releases == 4 && !manager.busy(); });
    window.show();
    assert(!background.inhibiting() && background.trackedJobs() == 0);
    std::cout << "PASS: close/reopen/minimize, real manager queue, one running vs queued view, exact progress, success/failure/cancel/crash, hidden removal confirmation, suspend inhibit/release\n";
}
