#include <QCoreApplication>
#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTimer>
#include <QHash>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QPixmap>
#include <QQuickImageProvider>
#include <QUrl>

class ThemeIconProvider final : public QQuickImageProvider
{
public:
    ThemeIconProvider()
        : QQuickImageProvider(QQuickImageProvider::Pixmap)
    {
    }

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requested_size) override
    {
        const QSize target = requested_size.isValid() ? requested_size : QSize(64, 64);
        QIcon icon = QIcon::fromTheme(id);
        if (icon.isNull()) {
            icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        }
        const QPixmap pixmap = icon.pixmap(target);
        if (size) {
            *size = pixmap.size();
        }
        return pixmap;
    }
};

extern "C" int fluff_run_qml(const char *qml_path,
                              const char *catalog_path,
                              const char *icon_path)
{
    int argc = 1;
    char application_name[] = "flufflinux-appcenter";
    char *arguments[] = {application_name, nullptr};
    QGuiApplication application(argc, arguments);

    QCoreApplication::setApplicationName(QStringLiteral("flufflinux-appcenter"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("App Center"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.1.0"));
    QCoreApplication::setOrganizationName(QStringLiteral("FluffNet"));
    QGuiApplication::setDesktopFileName(QStringLiteral("flufflinux-appcenter"));
    application.setWindowIcon(QIcon(QString::fromUtf8(icon_path)));

    QFile catalog(QString::fromUtf8(catalog_path));
    if (!catalog.open(QIODevice::ReadOnly)) {
        return 2;
    }
    QJsonParseError parse_error;
    const QJsonDocument document = QJsonDocument::fromJson(catalog.readAll(), &parse_error);
    if (parse_error.error != QJsonParseError::NoError || !document.isArray()) {
        return 3;
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("fluffDownloadsDemo"),
        qEnvironmentVariableIntValue("FLUFF_APP_CENTER_DEMO_DOWNLOADS") == 1);
    engine.addImageProvider(QStringLiteral("icon"), new ThemeIconProvider);
    engine.rootContext()->setContextProperty(
        QStringLiteral("fluffAppIconUrl"),
        QUrl::fromLocalFile(QString::fromUtf8(icon_path)));
    engine.rootContext()->setContextProperty(QStringLiteral("fluffInitialCatalog"),
                                             document.array().toVariantList());
    engine.rootContext()->setContextProperty(QStringLiteral("fluffInstalledApps"), QVariantList{});
    engine.rootContext()->setContextProperty(QStringLiteral("fluffInstalledLoading"), true);
    engine.rootContext()->setContextProperty(QStringLiteral("fluffInstalledError"), QString{});

    // Query applications only (including user and system installations), off the
    // UI thread's event loop. QProcess uses pipes, so Flatpak emits tab-separated
    // full columns without terminal headers or truncation.
    QHash<QString, QVariantMap> metadata;
    for (const auto &entry : document.array()) {
        auto app = entry.toObject().toVariantMap();
        QString id = app.value(QStringLiteral("id")).toString();
        if (id.endsWith(QStringLiteral(".desktop"))) id.chop(8);
        metadata.insert(id, app);
    }
    QProcess installed;
    QTimer installedTimeout;
    installedTimeout.setSingleShot(true);
    auto failInstalled = [&](const QString &message) {
        installedTimeout.stop();
        engine.rootContext()->setContextProperty(QStringLiteral("fluffInstalledError"), message);
        engine.rootContext()->setContextProperty(QStringLiteral("fluffInstalledLoading"), false);
    };
    QObject::connect(&installedTimeout, &QTimer::timeout, &engine, [&] {
        failInstalled(QCoreApplication::translate("Installed", "Reading installed Flatpaks timed out."));
        installed.kill();
    });
    QObject::connect(&installed, &QProcess::errorOccurred, &engine, [&](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            failInstalled(QCoreApplication::translate("Installed", "Could not start Flatpak to read installed apps."));
    });
    QObject::connect(&installed, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                     &engine, [&](int code, QProcess::ExitStatus status) {
        if (!installedTimeout.isActive()) return;
        installedTimeout.stop();
        if (code != 0 || status != QProcess::NormalExit) {
            failInstalled(QCoreApplication::translate("Installed", "Could not read installed Flatpak apps."));
            return;
        }
        QVariantList apps;
        const QString output = QString::fromUtf8(installed.readAllStandardOutput());
        for (const QString &line : output.split('\n', Qt::SkipEmptyParts)) {
            const auto columns = line.split('\t');
            if (columns.size() != 9) {
                failInstalled(QCoreApplication::translate("Installed", "Flatpak returned an unexpected installed-app list."));
                return;
            }
            const QString id = columns[0].trimmed();
            auto app = metadata.value(id);
            if (app.isEmpty()) {
                app = {{"id", id}, {"name", columns[1].trimmed()},
                       {"summary", columns[7].trimmed()}, {"description", columns[7].trimmed()},
                       {"icon", id}, {"category", ""}, {"developer", ""},
                       {"license", ""}, {"homepage", ""}, {"screenshots", QVariantList{}}};
            }
            app.insert(QStringLiteral("installedSize"), columns[2].trimmed());
            app.insert(QStringLiteral("installedOrigin"), columns[3].trimmed());
            app.insert(QStringLiteral("installation"), columns[4].trimmed());
            app.insert(QStringLiteral("installedBranch"), columns[5].trimmed());
            app.insert(QStringLiteral("installedArch"), columns[6].trimmed());
            app.insert(QStringLiteral("installedVersion"), columns[8].trimmed());
            apps.append(app);
        }
        engine.rootContext()->setContextProperty(QStringLiteral("fluffInstalledApps"), apps);
        engine.rootContext()->setContextProperty(QStringLiteral("fluffInstalledLoading"), false);
    });
    installedTimeout.start(15000);
    installed.start(QStringLiteral("flatpak"), {QStringLiteral("list"), QStringLiteral("--app"),
        QStringLiteral("--columns=application:f,name:f,size,origin:f,installation:f,branch:f,arch:f,description:f,version:f")});
    engine.load(QUrl::fromLocalFile(QString::fromUtf8(qml_path)));
    if (engine.rootObjects().isEmpty()) {
        return 4;
    }
    return application.exec();
}
