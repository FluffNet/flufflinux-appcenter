// Exercises the production manager against this executable's fake workers.
// No Flatpaks are installed/removed: workers only emit protocol messages.
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonArray>
#include <QThread>
#include <cassert>
#include <functional>
#include <iostream>
#include <cstdlib>

static void send(const QJsonObject &message) {
    std::cout << QJsonDocument(message).toJson(QJsonDocument::Compact).constData() << std::endl;
}
static void until(const std::function<bool()> &condition) {
    QElapsedTimer deadline; deadline.start();
    while (!condition() && deadline.elapsed() < 5000) {
        QCoreApplication::processEvents();
        QThread::msleep(5);
    }
    assert(condition());
}
int main(int argc, char **argv) {
    if (argc == 3 && QByteArray(argv[1]) == "--transaction-worker") {
        QCoreApplication child(argc, argv);
        const auto id = QJsonDocument::fromJson(argv[2]).object()["id"].toString();
        const auto ref = "app/" + id + "/x86_64/stable";
        send({{"type", "plan"}, {"operations", QJsonArray{QJsonObject{
            {"ref", ref}, {"action", "install"}, {"downloadBytes", 10000000}}}}});
        QTimer progress;
        QObject::connect(&progress, &QTimer::timeout, &child, [&] {
            send({{"type", "operation"}, {"ref", ref}, {"phase", "download"},
                {"progress", 0.4}, {"downloadProgress", 0.4}, {"status", "Downloading"}, {"receivedBytes", 1000000}});
        });
        progress.start(20);
        // Deliberately ignore stdin/EOF: reproduce a stuck, noisy worker.
        if (id.endsWith("Crash")) QTimer::singleShot(150, &child, [] { std::_Exit(7); });
        else if (id.endsWith("Following")) QTimer::singleShot(700, &child, [&] {
            send({{"type", "result"}, {"success", false}, {"error", "following worker completed normally"}});
            child.quit();
        });
        return child.exec();
    }
    QGuiApplication app(argc, argv);
    app.setApplicationName("appcenter-cancel-worker-test");
    FlatpakManager manager({});
    until([&] { return !manager.installedLoading(); });
    manager.installApp({{"id", "org.example.Uncooperative"}, {"name", "Uncooperative"}});
    until([&] { return !manager.jobs().isEmpty() && manager.jobs().first().toMap().contains("currentRef"); });
    const auto index = manager.jobs().first().toMap()["index"].toInt();
    QElapsedTimer stopped; stopped.start();
    manager.cancelJob(index);
    assert(manager.jobs().isEmpty()); // Immediate, no wait for worker acknowledgment.
    manager.installApp({{"id", "org.example.Following"}, {"name", "Following"}});
    assert(manager.jobs().size() == 1); // Retry/next job can queue during abort.
    until([&] { return manager.jobs().first().toMap().contains("currentRef"); });
    assert(stopped.elapsed() < 2000); // Hung worker cannot retain the queue.
    until([&] { return !manager.busy(); });
    assert(manager.jobs().size() == 1);
    auto job = manager.jobs().first().toMap();
    assert(job["error"] == "following worker completed normally"); // No stale watchdog killed the next worker.
    assert(!job["cancelled"].toBool());
    manager.installApp({{"id", "org.example.Crash"}, {"name", "Crash"}});
    until([&] { return !manager.busy(); });
    assert(manager.jobs().size() == 2); // Only cancellation was removed from history.
    job = manager.jobs().last().toMap();
    assert(job["failed"].toBool() && !job["cancelled"].toBool());
    assert(job["status"] == "The Flatpak worker stopped unexpectedly");
    manager.installApp({{"id", "org.example.StillActive"}, {"name", "Still active"}});
    const int activeIndex = manager.jobs().last().toMap()["index"].toInt();
    manager.clearDownloadHistory();
    assert(manager.jobs().size() == 1);
    assert(manager.jobs().first().toMap()["active"].toBool());
    assert(manager.jobs().first().toMap()["index"].toInt() == activeIndex);
    manager.cancelJob(activeIndex); // Clearing history must not invalidate cancellation IDs.
    until([&] { return !manager.busy(); });
    assert(manager.jobs().isEmpty());
    qInfo("PASS: immediate cancellation, forced worker exit, ignored late progress, safe next worker, genuine crash retained");
}
