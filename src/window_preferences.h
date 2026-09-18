#pragma once

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QPointer>
#include <QScreen>
#include <QSettings>
#include <QTimer>
#include <QWindow>

// Keep the normal size separately: maximized/minimized geometry must never
// overwrite the size the user chose for the restored window. No position is
// saved; the compositor places the window on the launch screen (also on Wayland).
class WindowPreferences final : public QObject {
public:
    struct Launch {
        QSize normalSize;
        QSize initialSize;
        bool maximized;
    };

    explicit WindowPreferences(const QString &path = defaultPath())
        : m_settings(path, QSettings::IniFormat) {
        m_capture.setSingleShot(true);
        m_capture.setInterval(0);
        m_save.setSingleShot(true);
        m_save.setInterval(250);
        connect(&m_capture, &QTimer::timeout, this, [this] { captureNormalSize(); });
        connect(&m_save, &QTimer::timeout, this, [this] { save(); });
    }

    static QString defaultPath() {
        return QDir::homePath() + "/.config/flufflinux-appcenter.conf";
    }

    Launch launchFor(const QSize &available) const {
        const QSize normal(dimension("Window/width", 1180, 720),
                           dimension("Window/height", 760, 520));
        const bool tooLarge = normal.width() > available.width() || normal.height() > available.height();
        const QString state = m_settings.value("Window/maximized", true).toString().toLower();
        return {normal, normal.boundedTo(available).expandedTo(QSize(1, 1)),
                state != "false" || tooLarge};
    }

    void restore(QWindow *window) {
        m_window = window;
        window->installEventFilter(this);
        QScreen *screen = window->screen() ? window->screen() : QGuiApplication::primaryScreen();
        const QSize available = screen ? screen->availableGeometry().size() : QSize(1180, 760);
        const auto launch = launchFor(available);
        m_normalSize = launch.normalSize;
        m_maximized = launch.maximized;
        window->setMinimumSize(QSize(720, 520).boundedTo(available));
        window->resize(launch.initialSize);
        connect(window, &QWindow::widthChanged, this, [this] { queueCapture(); });
        connect(window, &QWindow::heightChanged, this, [this] { queueCapture(); });
        connect(window, &QWindow::windowStateChanged, this, [this](Qt::WindowState state) {
            // Minimizing is temporary, not a startup preference.
            if (state == Qt::WindowMinimized || state == Qt::WindowFullScreen) return;
            m_maximized = state == Qt::WindowMaximized;
            queueCapture();
            m_save.start();
        });
        connect(qApp, &QCoreApplication::aboutToQuit, this, [this] { flush(); });
        if (launch.maximized) window->showMaximized();
        else window->showNormal();
        // Create the file on first launch, even when the user leaves the
        // default maximized preference unchanged.
        save();
    }

    void flush() {
        captureNormalSize();
        save();
    }

    bool maximized() const { return m_maximized; }

protected:
    bool eventFilter(QObject *object, QEvent *event) override {
        if (object == m_window && event->type() == QEvent::Expose
                && m_firstExpose && m_window->isExposed()) {
            m_firstExpose = false;
            // Wayland may assign a different output when it first maps the
            // window. Validate against that screen, not just the primary one.
            if (const auto screen = m_window->screen()) {
                const auto available = screen->availableGeometry().size();
                m_window->setMinimumSize(QSize(720, 520).boundedTo(available));
                if (m_normalSize.width() > available.width() || m_normalSize.height() > available.height())
                    m_window->showMaximized();
            }
        } else if (object == m_window && event->type() == QEvent::Close) {
            flush();
        }
        return QObject::eventFilter(object, event);
    }

private:
    int dimension(const char *key, int fallback, int minimum) const {
        bool valid = false;
        const int value = m_settings.value(key, fallback).toInt(&valid);
        return valid && value >= minimum ? value : fallback;
    }

    void queueCapture() {
        // Read both dimensions after Qt has applied the complete configure
        // event and its state change, rather than saving intermediate sizes.
        m_capture.start();
        m_save.start();
    }

    void captureNormalSize() {
        if (m_window && m_window->visibility() == QWindow::Windowed
                && m_window->windowState() == Qt::WindowNoState && !m_maximized
                && m_window->width() > 0 && m_window->height() > 0)
            m_normalSize = m_window->size();
    }

    void save() {
        if (!m_normalSize.isValid()) return;
        if (!QDir().mkpath(QFileInfo(m_settings.fileName()).absolutePath())) {
            qWarning("Cannot create the App Center settings directory.");
            return;
        }
        m_settings.setValue("Window/width", m_normalSize.width());
        m_settings.setValue("Window/height", m_normalSize.height());
        m_settings.setValue("Window/maximized", m_maximized);
        // QSettings uses an atomic replacement and preserves unrelated keys.
        m_settings.sync();
        if (m_settings.status() != QSettings::NoError)
            qWarning("Cannot save App Center window preferences.");
    }

    QSettings m_settings;
    QPointer<QWindow> m_window;
    QTimer m_capture, m_save;
    QSize m_normalSize;
    bool m_maximized = true;
    bool m_firstExpose = true;
};
