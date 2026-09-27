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
    QList<QString> summaries;
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
        } else if (message.member() == "Notify") {
            summaries << args[4].toString();
            bus.send(message.createReply(QVariant::fromValue(uint(summaries.size()))));
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
    if (argc == 3 && QByteArray(argv[1]) == "--updates-worker") {
        const QString ref = "app/org.example.Update/x86_64/stable";
        send({{"type", "updates"}, {"updates", QJsonArray{QJsonObject{
            {"key", "user:" + ref}, {"id", "org.example.Update"}, {"name", "Update test"},
            {"flatpakRef", ref}, {"installation", "user"}, {"plan", QJsonArray{}}}}}});
        return 0;
    }
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
    assert(bus.registerService("org.freedesktop.Notifications"));
    assert(bus.registerVirtualObject("/JobViewServer", &desktop, QDBusConnection::SubPath));
    assert(bus.registerVirtualObject("/org/freedesktop/PowerManagement/Inhibit", &desktop));
    assert(bus.registerVirtualObject("/org/freedesktop/Notifications", &desktop));
    FlatpakManager manager({}); QWindow window; window.show();
    BackgroundQueue background(&manager, &window, [&] { window.show(); });
    waitFor([&] { return !manager.installedLoading(); });
    auto install = [&](const QString &id) { manager.installApp({{"id", id}, {"name", id}}); };
    install("org.example.A"); install("org.example.B");
    waitFor([&] { return desktop.inhibits == 1 && manager.jobs()[0].toMap().value("receivedBytes").toInt() == 524288; });
    assert(background.inhibiting() && background.trackedJobs() == 0 && desktop.created == 0);
    QElapsedTimer operationTime; operationTime.start();
    // Simulate downloading with the window open before creating a native view.
    while (operationTime.elapsed() < 150) { QCoreApplication::processEvents(); QThread::msleep(5); }
    window.showMinimized(); QCoreApplication::processEvents(); assert(!background.closed());
    window.showNormal(); window.close();
    waitFor([&] { return desktop.views.size() == 1 && desktop.views.first().value("processedBytes").toULongLong() == 524288; });
    assert(background.closed() && !window.isVisible() && background.trackedJobs() == 1);
    assert(desktop.views.first().value("totalBytes").toULongLong() == 1048576);
    assert(desktop.views.first().value("percent").toUInt() == 45);
    waitFor([&] { return desktop.views.first().value("title") == "Installing 1/2: org.example.A"; });
    const auto firstElapsed = desktop.views.first().value("elapsedTime").toLongLong();
    assert(firstElapsed >= 150);
    assert(524288 * 1000 / firstElapsed > 0); // Plasma's average bytes/second.
    assert(manager.jobs()[0].toMap().value("queuePosition").toInt() == 1);
    assert(manager.jobs()[1].toMap().value("queuePosition").toInt() == 2);
    assert(manager.jobs()[1].toMap().value("queueTotal").toInt() == 2);
    window.show(); waitFor([&] { return desktop.views.isEmpty(); });
    assert(!background.closed() && manager.busy() && desktop.results.last() == 1 && background.inhibiting());
    while (operationTime.elapsed() < firstElapsed + 150) { QCoreApplication::processEvents(); QThread::msleep(5); }
    window.close(); waitFor([&] { return desktop.views.size() == 1; });
    assert(desktop.views.first().value("elapsedTime").toLongLong() >= firstElapsed + 150);
    write(temp.filePath("org.example.A"), "fail");
    waitFor([&] { return desktop.results.size() == 2 && desktop.views.size() == 1; });
    assert(desktop.results.last() == 1 && background.inhibiting() && desktop.summaries.isEmpty());
    write(temp.filePath("org.example.B"), "ok");
    waitFor([&] { return desktop.results.size() == 3 && desktop.releases == 1 && !manager.busy(); });
    waitFor([&] { return desktop.summaries.size() == 1; });
    assert(desktop.results.last() == 1 && !background.inhibiting());
    assert(desktop.summaries.last() == "1. org.example.A - Failed\n2. org.example.B - Installed");
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
    waitFor([&] { return desktop.views.size() == 1 && desktop.views.first().value("title") == "Removing Remove"; });
    write(temp.filePath("org.example.Remove"), "ok");
    waitFor([&] { return desktop.releases == 4 && !manager.busy(); });
    window.show();
    assert(!background.inhibiting() && background.trackedJobs() == 0);
    for (int i = 1; i <= 5; ++i) {
        if (i == 4) manager.installApp({{"id", "org.example.Batch4"}, {"name", "Test <b>& Four"}});
        else install(QString("org.example.Batch%1").arg(i));
    }
    window.close();
    auto batchJob = [&](int number) {
        for (const auto &entry : manager.jobs()) {
            const auto job = entry.toMap();
            if (job.value("id") == QString("org.example.Batch%1").arg(number)) return job;
        }
        return QVariantMap{};
    };
    waitFor([&] { return batchJob(1).value("receivedBytes").toInt() > 0; });
    assert(batchJob(1).value("queuePosition").toInt() == 1 && batchJob(1).value("queueTotal").toInt() == 5);
    write(temp.filePath("org.example.Batch1"), "ok");
    waitFor([&] { return batchJob(2).value("receivedBytes").toInt() > 0; });
    assert(batchJob(2).value("queuePosition").toInt() == 2 && batchJob(2).value("queueTotal").toInt() == 5);
    waitFor([&] { return desktop.views.size() == 1 && desktop.views.first().value("title") == "Installing 2/5: org.example.Batch2"; });
    const auto runningView = desktop.views.firstKey();
    const int createdBeforeAppend = desktop.created;
    install("org.example.Batch6");
    assert(batchJob(2).value("queuePosition").toInt() == 2 && batchJob(2).value("queueTotal").toInt() == 6);
    assert(batchJob(6).value("queued").toBool() && batchJob(6).value("queuePosition").toInt() == 6);
    waitFor([&] { return desktop.views.value(runningView).value("title") == "Installing 2/6: org.example.Batch2"; });
    assert(desktop.created == createdBeforeAppend); // Update in place, never restart the notification/job.
    manager.clearDownloadHistory();
    assert(batchJob(2).value("queuePosition").toInt() == 2 && batchJob(2).value("queueTotal").toInt() == 6);
    manager.cancelJob(batchJob(5).value("index").toInt());
    assert(batchJob(2).value("queuePosition").toInt() == 2 && batchJob(2).value("queueTotal").toInt() == 5);
    for (int i = 2; i <= 4; ++i) write(temp.filePath(QString("org.example.Batch%1").arg(i)), "ok");
    write(temp.filePath("org.example.Batch6"), "ok");
    waitFor([&] { return !manager.busy() && !background.inhibiting(); });
    waitFor([&] { return desktop.summaries.size() == 2; });
    assert(desktop.summaries.last().count(" - Installed") == 5);
    assert(desktop.summaries.last().contains("org.example.Batch5 - Cancelled"));
    assert(desktop.summaries.last().contains("Test &lt;b&gt;&amp; Four - Installed"));
    const auto summaryLines = desktop.summaries.last().split('\n');
    assert(summaryLines.size() == 6);
    for (int i = 0; i < summaryLines.size(); ++i)
        assert(summaryLines[i].startsWith(QString::number(i + 1) + ". "));
    background.synchronize(); QCoreApplication::processEvents(); assert(desktop.summaries.size() == 2);
    window.show();
    install("org.example.Open1"); install("org.example.Open2");
    write(temp.filePath("org.example.Open1"), "ok"); write(temp.filePath("org.example.Open2"), "ok");
    waitFor([&] { return !manager.busy() && !background.inhibiting(); });
    window.close(); QCoreApplication::processEvents(); assert(desktop.summaries.size() == 2);
    window.show();
    manager.checkForUpdates();
    waitFor([&] { return manager.updates().value("state") == "ready"; });
    manager.installSelectedUpdates(); window.close();
    waitFor([&] { return desktop.views.size() == 1 && desktop.views.first().value("title") == "Updating Update test"; });
    write(temp.filePath("org.example.Update"), "ok");
    waitFor([&] { return !manager.busy() && desktop.views.isEmpty(); });
    assert(desktop.results.last() == 0);
    window.show();
    std::cout << "PASS: close/reopen/minimize, real manager queue, one running vs queued view, exact progress and continuous average-speed timer, success/failure/cancel/crash, hidden removal confirmation, suspend inhibit/release, batch 2/5 and history/cancellation accounting, escaped once-only closed-window summary\n";
}
