#include <QCoreApplication>
#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
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
    engine.addImageProvider(QStringLiteral("icon"), new ThemeIconProvider);
    engine.rootContext()->setContextProperty(
        QStringLiteral("fluffAppIconUrl"),
        QUrl::fromLocalFile(QString::fromUtf8(icon_path)));
    engine.rootContext()->setContextProperty(QStringLiteral("fluffInitialCatalog"),
                                             document.array().toVariantList());
    engine.load(QUrl::fromLocalFile(QString::fromUtf8(qml_path)));
    if (engine.rootObjects().isEmpty()) {
        return 4;
    }
    return application.exec();
}
