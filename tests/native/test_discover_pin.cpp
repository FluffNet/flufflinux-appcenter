// Run in the VM's real KDE session after installing the replacement package.
// Uses KDE's launcher and window-matching functions; never edits panel/pins.
#include <QApplication>
#include <QIcon>
#include <QDebug>
#include <iostream>
#include <KService>
#include <KApplicationTrader>
#include <taskmanager/launchertasksmodel.h>
#include <taskmanager/tasktools.h>

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    auto service = KService::serviceByDesktopName(QStringLiteral("org.kde.discover"));
    if (!service || service->name() != "App Center" || service->icon() != "flufflinux-appcenter")
        return 1;
    const auto visible = KApplicationTrader::query([](const KService::Ptr &item) {
        return !item->noDisplay() && item->name() == "App Center";
    });
    if (visible.size() != 1) { qCritical() << "Duplicate/missing App Center entries:" << visible.size(); return 2; }
    TaskManager::LauncherTasksModel launcher;
    const QStringList pins{QStringLiteral("applications:org.kde.discover.desktop")};
    launcher.setLauncherList(pins);
    const auto index = launcher.index(0, 0);
    if (launcher.rowCount() != 1 || index.data(Qt::DisplayRole).toString() != "App Center"
        || qvariant_cast<QIcon>(index.data(Qt::DecorationRole)).isNull()) return 3;
    // Supply the real Wayland desktop ID reported by the running App Center.
    // This does not require granting the probe privileged Wayland protocols.
    if (argc != 2 || QString::fromLocal8Bit(argv[1]) != "org.kde.discover") return 4;
    const auto windowUrl = TaskManager::windowUrlFromMetadata(QString::fromLocal8Bit(argv[1]));
    const auto windowData = TaskManager::appDataFromUrl(windowUrl);
    const auto pinUrl = index.data(TaskManager::AbstractTasksModel::LauncherUrlWithoutIcon).toUrl();
    if (windowData.name != "App Center" || windowData.id != service->storageId()
        || windowData.icon.isNull() || !TaskManager::launcherUrlsMatch(windowUrl, pinUrl)) {
        std::cerr << "Window name=" << windowData.name.toStdString() << " id=" << windowData.id.toStdString()
                  << " url=" << windowUrl.toString().toStdString() << " pin=" << pinUrl.toString().toStdString()
                  << " iconNull=" << windowData.icon.isNull() << '\n';
        return 5;
    }
    if (windowData.id != index.data(TaskManager::AbstractTasksModel::AppId).toString()) return 6;
    std::cout << "PASS: old Discover pin shows App Center with its icon; running window ID matches the pin; exactly one visible menu entry\n";
    return 0;
}
