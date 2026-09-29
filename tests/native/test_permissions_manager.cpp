// Fake subprocesses around the production manager; no real Flatpak writes.
#include "../../src/flatpak_manager.h"
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonArray>
#include <QTemporaryDir>
#include <QFile>
#include <QThread>
#include <cassert>
#include <functional>
#include <iostream>

static void until(const std::function<bool()> &condition) {
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < 6000) { QCoreApplication::processEvents(); QThread::msleep(5); }
    assert(condition());
}
int main(int argc, char **argv) {
    if (argc == 3 && QByteArray(argv[1]) == "--permissions-worker") {
        QCoreApplication child(argc, argv);
        const auto request = QJsonDocument::fromJson(argv[2]).object();
        const auto remote = request["remote"].toString();
        if (remote == "crash") return 8;
        if (remote == "invalid") { std::cout << "not JSON"; return 0; }
        QTimer::singleShot(remote == "slow" ? 400 : 30, &child, [&] {
            std::cout << QJsonDocument(QJsonObject{{"state", "ready"}, {"groups", QJsonArray{}}, {"remote", remote}}).toJson().constData();
            child.quit();
        });
        return child.exec();
    }
    QTemporaryDir temporary; assert(temporary.isValid());
    const auto command = temporary.filePath("flatpak");
    QFile file(command); assert(file.open(QIODevice::WriteOnly));
    file.write(R"SH(#!/bin/sh
if [ "$1" = list ]; then
    printf 'org.example.Installed\tInstalled\t1 MB\tinstalled-origin\tuser\tstable\tx86_64\tTest\t1.0\n'
    printf 'org.example.System\tSystem\t1 MB\tinstalled-origin\tsystem\tstable\tx86_64\tTest\t1.0\n'
    printf 'org.example.Named.desktop\tNamed\t1 MB\tinstalled-origin\textra\tbeta\taarch64\tTest\t1.0\n'
elif [ "$1" = info ] && [ "$2" = --show-permissions ] && [ "$4" = -- ]; then
    case "$3:$5" in
        --user:app/org.example.Installed/x86_64/stable|--system:app/org.example.System/x86_64/stable|--installation=extra:app/org.example.Named.desktop/aarch64/beta)
            printf '[Context]\nshared=network;\nfilesystems=xdg-download:ro;\n' ;;
        *) exit 3 ;;
    esac
else
    exit 2
fi
)SH");
    file.close(); assert(file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    qputenv("PATH", temporary.path().toUtf8() + ':' + qgetenv("PATH"));
    qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
    qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
    qputenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent-permissions-test-bus");
    QGuiApplication app(argc, argv);
    QVariantMap catalog{{"id", "org.example.App"}, {"remote", "good"}, {"sourceUrl", "https://example.org/repo/"},
        {"flatpakRef", "app/org.example.App/x86_64/stable"}};
    QVariantList variants;
    for (const auto &remote : {"good", "slow", "crash", "invalid"}) { auto variant = catalog; variant["remote"] = remote; variants.append(variant); }
    catalog["sources"] = variants;
    FlatpakManager manager({catalog});
    until([&] { return !manager.installedLoading(); });
    auto read = [&](const QVariantMap &request) {
        manager.requestAppPermissions(request);
        assert(manager.appPermissions().value("state") == "loading");
        assert(manager.jobs().isEmpty() && !manager.busy());
        until([&] { return manager.appPermissions().value("state") != "loading"; });
    };
    read(catalog); assert(manager.appPermissions().value("state") == "ready");
    assert(manager.appPermissions().value("remote") == "good");
    auto slow = catalog; slow["remote"] = "slow";
    const auto staleToken = manager.requestAppPermissions(slow);
    manager.requestAppPermissions(catalog);
    manager.cancelAppPermissions(staleToken); // A closing old dialog cannot cancel a new one.
    until([&] { return manager.appPermissions().value("state") == "ready"; });
    QElapsedTimer timer; timer.start();
    while (timer.elapsed() < 500) { QCoreApplication::processEvents(); QThread::msleep(5); }
    assert(manager.appPermissions().value("remote") == "good");
    manager.requestAppPermissions(slow); manager.cancelAppPermissions();
    assert(manager.appPermissions().isEmpty());
    manager.requestAppPermissions(slow);
    for (auto process : manager.findChildren<QProcess *>())
        for (auto timeout : process->findChildren<QTimer *>())
            if (timeout->isActive() && timeout->interval() == 30000) timeout->start(40);
    until([&] { return manager.appPermissions().value("state") == "error"; });
    assert(manager.appPermissions().value("message").toString().contains("timed out"));
    for (const auto &remote : {"crash", "invalid"}) {
        auto bad = catalog; bad["remote"] = remote; read(bad);
        assert(manager.appPermissions().value("state") == "error");
    }
    auto wrongSource = catalog; wrongSource["sourceUrl"] = "https://different.example/";
    manager.requestAppPermissions(wrongSource);
    assert(manager.appPermissions().value("state") == "error");
    assert(manager.installedApps().size() == 3);
    for (const auto &installed : manager.installedApps()) {
        read(installed.toMap());
        assert(manager.appPermissions().value("state") == "ready");
        assert(manager.appPermissions().value("installed").toBool());
        assert(manager.appPermissions().value("groups").toList().size() == 2);
    }
    assert(manager.jobs().isEmpty() && manager.review().isEmpty() && !manager.busy());
    std::cout << "Permissions manager routing, stale-result, cancellation and failure checks passed\n";
}
