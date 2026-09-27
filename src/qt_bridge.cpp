#include "flatpak_manager.h"
#include "catalog_stats.h"
#include "catalog_preferences.h"
#include "network_status.h"
#include "window_preferences.h"
#include "ui_typography.h"
#include <QFile>
#include <QApplication>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QUrl>
#include <memory>
#include <unistd.h>

class ThemeIconProvider final : public QQuickImageProvider {
public:
    ThemeIconProvider() : QQuickImageProvider(QQuickImageProvider::Pixmap) {}
    QPixmap requestPixmap(const QString &request, QSize *size, const QSize &requested) override {
        const auto id = request.section('?', 0, 0);
        const QSize target = requested.isValid() ? requested : QSize(64, 64);
        QIcon icon = QIcon::fromTheme(id);
        if (icon.isNull()) icon = QIcon::fromTheme("application-x-executable");
        const auto pixmap = icon.pixmap(target);
        if (size) *size = pixmap.size();
        return pixmap;
    }
};

extern "C" int fluff_run_qml(const char *qml_path, const char *catalog_path, const char *icon_path,
                              int input_count, const char *const *inputs, const char *desktop_file) {
    if (geteuid() == 0) { qCritical("Run App Center as your regular desktop user, not root."); return 1; }
    int argc = 1;
    char name[] = "flufflinux-appcenter";
    char *argv[] = {name, nullptr};
    // KDE only offers native file dialogs to QApplication instances. Prefer
    // its XDG portal picker without replacing the desktop's platform theme;
    // respect an explicit user override (including opting out with 0).
    if (!qEnvironmentVariableIsSet("PLASMA_INTEGRATION_USE_PORTAL"))
        qputenv("PLASMA_INTEGRATION_USE_PORTAL", "1");
    QApplication application(argc, argv);
    configureDesktopTypography(application);
    QCoreApplication::setApplicationName("flufflinux-appcenter");
    QGuiApplication::setApplicationDisplayName("App Center");
    QCoreApplication::setApplicationVersion(APPCENTER_DISPLAY_VERSION);
    QCoreApplication::setOrganizationName("FluffNet LLC");
    // Keep existing Plasma Discover pins associated with this window. The
    // package owns this legacy desktop ID, with App Center's name and icon.
    QGuiApplication::setDesktopFileName(QString::fromUtf8(desktop_file));
    application.setWindowIcon(QIcon(QString::fromUtf8(icon_path)));
    QJsonArray incoming;
    for (int i = 0; i < input_count && i < 16; ++i)
        incoming.append(QJsonDocument::fromJson(inputs[i]).object());
    const auto socketPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/flufflinux-appcenter.socket";
    QLocalSocket existing;
    existing.connectToServer(socketPath);
    if (existing.waitForConnected(200)) {
        existing.write(QJsonDocument(incoming).toJson(QJsonDocument::Compact) + '\n');
        existing.waitForBytesWritten(2000);
        return 0;
    }
    QLockFile lock(socketPath + ".lock");
    if (!lock.tryLock(1000)) { qCritical("Another App Center instance is starting."); return 1; }
    QLocalServer server;
    server.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(socketPath);
    if (!server.listen(socketPath)) { qCritical("Cannot create the App Center link handler socket."); return 1; }

    QFile catalog(QString::fromUtf8(catalog_path));
    if (!catalog.open(QIODevice::ReadOnly)) return 2;
    const auto document = QJsonDocument::fromJson(catalog.readAll());
    if (!document.isArray()) return 3;
    FlatpakManager manager(document.array().toVariantList());
    CatalogStats catalogStats;
    NetworkStatus networkStatus;
    // Custom QML is used by read-only UI fixtures; it must not read/write the
    // desktop user's window preferences or override fixture geometry.
    const bool manageWindow = !qEnvironmentVariableIsSet("FLUFF_APP_CENTER_QML");
    CatalogPreferences catalogPreferences(manageWindow ? WindowPreferences::defaultPath() : QString());
    std::unique_ptr<WindowPreferences> windowPreferences;
    if (manageWindow) windowPreferences = std::make_unique<WindowPreferences>();
    QQmlApplicationEngine engine;
    engine.addImageProvider("icon", new ThemeIconProvider);
    engine.rootContext()->setContextProperty("fluffBackend", &manager);
    engine.rootContext()->setContextProperty("fluffCatalogStats", &catalogStats);
    engine.rootContext()->setContextProperty("fluffNetworkStatus", &networkStatus);
    engine.rootContext()->setContextProperty("fluffCatalogPreferences", &catalogPreferences);
    engine.rootContext()->setContextProperty("fluffAppIconUrl", QUrl::fromLocalFile(QString::fromUtf8(icon_path)));
    engine.rootContext()->setContextProperty("fluffInitialCatalog", document.array().toVariantList());
    engine.rootContext()->setContextProperty("fluffWindowManaged", manageWindow);
    if (manageWindow) QTimer::singleShot(0, &manager, &FlatpakManager::initializeSources);
    engine.load(QUrl::fromLocalFile(QString::fromUtf8(qml_path)));
    if (engine.rootObjects().isEmpty()) return 4;
    if (manageWindow) {
        if (auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first()))
            windowPreferences->restore(window);
    }
    auto dispatch = [&](const QJsonArray &sources) {
        for (int i = 0; i < sources.size() && i < 16; ++i) {
            // Accept the previous release's IPC format during an in-place
            // upgrade, but new requests explicitly distinguish files/actions.
            const auto action = sources[i].isObject() ? sources[i].toObject()
                : QJsonObject{{"type", sources[i].toString() == "--updates" ? "mode" : "source"},
                              {"value", sources[i].toString() == "--updates" ? "Update" : sources[i].toString()}};
            const auto type = action.value("type").toString(), value = action.value("value").toString();
            if (type == "mode" && value == "Update")
                QMetaObject::invokeMethod(engine.rootObjects().first(), "showUpdates");
            else if (type == "source") manager.openSource(value);
            else if (QStringList{"mode", "search", "category", "mime"}.contains(type))
                QMetaObject::invokeMethod(engine.rootObjects().first(), "handleCliAction", Q_ARG(QVariant, action.toVariantMap()));
        }
        if (auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
            // Raising an existing instance must not undo its maximized state.
            if (window->visibility() == QWindow::Minimized) {
                if (windowPreferences ? windowPreferences->maximized()
                                      : window->windowStates().testFlag(Qt::WindowMaximized)) window->showMaximized();
                else window->showNormal();
            } else window->show();
            window->raise(); window->requestActivate();
        }
    };
    QObject::connect(&server, &QLocalServer::newConnection, &engine, [&] {
        while (auto socket = server.nextPendingConnection()) {
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            QObject::connect(socket, &QLocalSocket::readyRead, &engine, [socket, &dispatch] {
                if (socket->bytesAvailable() > 128 * 1024) { socket->disconnectFromServer(); return; }
                if (!socket->canReadLine()) return;
                const auto doc = QJsonDocument::fromJson(socket->readLine(128 * 1024));
                if (doc.isArray()) dispatch(doc.array());
                socket->disconnectFromServer();
            });
        }
    });
    QTimer::singleShot(0, &engine, [&] { if (!incoming.isEmpty()) dispatch(incoming); });
    return application.exec();
}
