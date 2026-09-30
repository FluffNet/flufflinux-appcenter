#pragma once

#include <QApplication>
#include <QEvent>
#include <QIcon>
#include <QQuickImageProvider>
#include <KIconLoader>

// Theme icons take precedence over the bundled icon, including for source
// runs. Keep the bundle only as a fallback when a theme has no App Center icon.
class ThemeIconProvider final : public QQuickImageProvider {
public:
    explicit ThemeIconProvider(const QIcon &fallback)
        : QQuickImageProvider(QQuickImageProvider::Pixmap), m_fallback(fallback) {}
    QPixmap requestPixmap(const QString &request, QSize *size, const QSize &requested) override {
        const auto id = request.section('?', 0, 0);
        const QSize target = requested.isValid() ? requested : QSize(64, 64);
        QIcon icon = QIcon::fromTheme(id);
        if (icon.isNull()) icon = id == "flufflinux-appcenter"
            ? m_fallback : QIcon::fromTheme("application-x-executable");
        const auto pixmap = icon.pixmap(target);
        if (size) *size = pixmap.size();
        return pixmap;
    }
private:
    QIcon m_fallback;
};

class DesktopTheme final : public QObject {
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY changed)
public:
    explicit DesktopTheme(const QIcon &fallback, QObject *parent = nullptr)
        : QObject(parent), m_fallback(fallback) {
        updateWindowIcon();
        connect(KIconLoader::global(), &KIconLoader::iconChanged, this, [this](int) { reload(); });
        qApp->installEventFilter(this);
    }
    int revision() const { return m_revision; }
signals:
    void changed();
protected:
    bool eventFilter(QObject *object, QEvent *event) override {
        // Symbolic SVGs may depend on the palette even if the icon theme
        // name itself stays the same. Also invalidate the QML image cache.
        if (object == qApp && event->type() == QEvent::ApplicationPaletteChange) reload();
        return QObject::eventFilter(object, event);
    }
private:
    void updateWindowIcon() { qApp->setWindowIcon(QIcon::fromTheme("flufflinux-appcenter", m_fallback)); }
    void reload() { updateWindowIcon(); ++m_revision; emit changed(); }
    QIcon m_fallback;
    int m_revision = 0;
};
