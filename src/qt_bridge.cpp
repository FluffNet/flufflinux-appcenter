#include "flatpak_manager.h"
#include "catalog_stats.h"
#include "catalog_preferences.h"
#include "network_status.h"
#include "window_preferences.h"
#include "ui_typography.h"
#include "background_queue.h"
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusObjectPath>
#include <QElapsedTimer>
#include <QThread>
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
#include <KWindowSystem>
#include <cstdio>
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

extern "C" int fluff_run_qml(const char *qml_path, const char *icon_path,
                              int input_count, const char *const *inputs, const char *desktop_file) {
    if (geteuid() == 0) { qCritical("Run App Center as your regular desktop user, not root."); return 1; }
    QElapsedTimer startup; startup.start();
    const bool traceStartup = qEnvironmentVariableIntValue("FLUFF_APP_CENTER_TRACE_STARTUP") == 1;
    const auto trace = [&](const char *stage) {
        if (traceStartup) std::fprintf(stderr, "APPCENTER_STARTUP %s %lld ms\n", stage,
                                      static_cast<long long>(startup.elapsed()));
    };
    // Qt may consume this environment variable. Capture it before constructing
    // QApplication so the launcher can hand it to the session service over IPC.
    const auto activationToken = qEnvironmentVariable("XDG_ACTIVATION_TOKEN");
    int argc = 1;
    char name[] = "flufflinux-appcenter";
    char *argv[] = {name, nullptr};
    // KDE only offers native file dialogs to QApplication instances. Prefer
    // its XDG portal picker without replacing the desktop's platform theme;
    // respect an explicit user override (including opting out with 0).
    if (!qEnvironmentVariableIsSet("PLASMA_INTEGRATION_USE_PORTAL"))
        qputenv("PLASMA_INTEGRATION_USE_PORTAL", "1");
    QApplication application(argc, argv);
    trace("qt-ready");
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
    if (!activationToken.isEmpty() && activationToken.size() <= 8192)
        incoming.append(QJsonObject{{"type", "activation"}, {"value", activationToken}});
    const auto socketPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/flufflinux-appcenter.socket";
    QLocalSocket existing;
    const auto forward = [&] {
        existing.write(QJsonDocument(incoming).toJson(QJsonDocument::Compact) + '\n');
        if (!existing.waitForBytesWritten(2000)) return false;
        // Keep the launcher alive until the service has shown a frame, so KDE
        // does not finish launch feedback while the window is still mapping.
        if (existing.waitForReadyRead(15000)) return existing.readLine() == "ready\n";
        // Previous releases acknowledge by closing, without a response body.
        return existing.error() == QLocalSocket::PeerClosedError;
    };
    existing.connectToServer(socketPath);
    if (existing.waitForConnected(200)) {
        return forward() ? 0 : 1;
    }
    // Installed launches activate an on-demand user service. Closing a window
    // or the launching terminal cannot kill its transaction workers.
    if (!qEnvironmentVariableIsSet("FLUFF_APP_CENTER_SESSION_SERVICE")
            && !qEnvironmentVariableIsSet("FLUFF_APP_CENTER_QML")
            && QCoreApplication::applicationFilePath() == "/usr/bin/flufflinux-appcenter"
            && QFile::exists("/usr/lib/systemd/user/flufflinux-appcenter.service")) {
        QDBusInterface systemd("org.freedesktop.systemd1", "/org/freedesktop/systemd1",
                              "org.freedesktop.systemd1.Manager", QDBusConnection::sessionBus());
        const QDBusReply<QDBusObjectPath> started = systemd.call("StartUnit", "flufflinux-appcenter.service", "replace");
        if (!started.isValid()) {
            qCritical().noquote() << "Cannot start App Center's session service:" << started.error().message();
            return 1;
        }
        QElapsedTimer deadline; deadline.start();
        while (deadline.elapsed() < 15000) {
            existing.abort(); existing.connectToServer(socketPath);
            if (existing.waitForConnected(100)) {
                return forward() ? 0 : 1;
            }
            QThread::msleep(50);
        }
        qCritical("App Center's session service did not become ready."); return 1;
    }
    QLockFile lock(socketPath + ".lock");
    if (!lock.tryLock(1000)) { qCritical("Another App Center instance is starting."); return 1; }
    QLocalServer server;
    server.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(socketPath);
    if (!server.listen(socketPath)) { qCritical("Cannot create the App Center link handler socket."); return 1; }

    FlatpakManager manager({});
    // Parsing AppStream can take seconds. Do it in the existing worker,
    // while the window is already responsive. CLI clients never parse it.
    manager.loadCatalog();
    CatalogStats catalogStats;
    NetworkStatus networkStatus;
    // Custom QML is used by read-only UI fixtures; it must not read/write the
    // desktop user's window preferences or override fixture geometry.
    const bool manageWindow = !qEnvironmentVariableIsSet("FLUFF_APP_CENTER_QML");
    // Explicitly opt-in live fixtures exercise this exact controller using an
    // isolated Flatpak installation, without touching user window settings.
    const bool manageBackground = manageWindow || qEnvironmentVariableIntValue("FLUFF_APP_CENTER_BACKGROUND_TEST") == 1;
    if (manageBackground) application.setQuitOnLastWindowClosed(false);
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
    engine.rootContext()->setContextProperty("fluffInitialCatalog", QVariantList{});
    engine.rootContext()->setContextProperty("fluffWindowManaged", manageWindow);
    if (manageWindow) QTimer::singleShot(0, &manager, &FlatpakManager::initializeSources);
    engine.load(QUrl::fromLocalFile(QString::fromUtf8(qml_path)));
    if (engine.rootObjects().isEmpty()) return 4;
    trace("qml-ready");
    bool firstFrame = true, firstCatalog = true;
    QObject::connect(&manager, &FlatpakManager::catalogChanged, &application, [&] {
        if (firstCatalog && !manager.catalogLoading()) { firstCatalog = false; trace("catalog-ready"); }
    });
    if (auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
        QObject::connect(window, &QQuickWindow::frameSwapped, &application, [&] {
            if (firstFrame) { firstFrame = false; trace("first-frame"); }
        }, Qt::QueuedConnection);
    }
    if (manageWindow) {
        if (auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first()))
            windowPreferences->restore(window);
    }
    auto dispatch = [&](const QJsonArray &sources) {
        QString token;
        // The optional activation record is separate from the 16 CLI actions.
        // Older instances safely ignore it, retaining their array IPC format.
        for (const auto &source : sources) {
            const auto action = source.toObject();
            if (action["type"] == "activation" && action["value"].toString().size() <= 8192)
                token = action["value"].toString();
        }
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
            else if (type == "installed-application") manager.openInstalledApplication(value);
            else if (QStringList{"mode", "search", "category", "mime"}.contains(type))
                QMetaObject::invokeMethod(engine.rootObjects().first(), "handleCliAction", Q_ARG(QVariant, action.toVariantMap()));
        }
        if (auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
            if (windowPreferences) windowPreferences->present();
            else if (!window->isVisible() || window->visibility() == QWindow::Minimized) {
                if (window->windowStates().testFlag(Qt::WindowMaximized)) window->showMaximized();
                else window->showNormal();
            }
            if (!token.isEmpty()) KWindowSystem::setCurrentXdgActivationToken(token);
            KWindowSystem::activateWindow(window);
        }
    };
    std::unique_ptr<BackgroundQueue> background;
    if (manageBackground) {
        if (auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first()))
            background = std::make_unique<BackgroundQueue>(&manager, window, [&] { dispatch(QJsonArray{}); });
    }
    QObject::connect(&server, &QLocalServer::newConnection, &engine, [&] {
        while (auto socket = server.nextPendingConnection()) {
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            const auto receive = [socket, &dispatch, &engine, &firstFrame] {
                if (socket->property("handled").toBool()) return;
                if (socket->bytesAvailable() > 128 * 1024) { socket->disconnectFromServer(); return; }
                if (!socket->canReadLine()) return;
                socket->setProperty("handled", true);
                const auto doc = QJsonDocument::fromJson(socket->readLine(128 * 1024));
                if (doc.isArray()) dispatch(doc.array());
                const auto acknowledge = [socket] {
                    socket->write("ready\n"); socket->disconnectFromServer();
                };
                const auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
                if (window && (firstFrame || !window->isExposed())) {
                    QObject::connect(window, &QQuickWindow::frameSwapped, socket, acknowledge,
                        Qt::ConnectionType(Qt::QueuedConnection | Qt::SingleShotConnection));
                    window->requestUpdate();
                } else acknowledge();
            };
            QObject::connect(socket, &QLocalSocket::readyRead, &engine, receive);
            // A fast launcher can finish writing before newConnection is handled.
            receive();
        }
    });
    QTimer::singleShot(0, &engine, [&] { if (!incoming.isEmpty()) dispatch(incoming); });
    return application.exec();
}
