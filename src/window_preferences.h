#pragma once

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QPointer>
#include <QScreen>
#include "rust_backend.h"
#include <QStandardPaths>
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
        : m_path(path) {
        m_capture.setSingleShot(true);
        m_capture.setInterval(0);
        m_save.setSingleShot(true);
        m_save.setInterval(250);
        connect(&m_capture, &QTimer::timeout, this, [this] { captureNormalSize(); });
        connect(&m_save, &QTimer::timeout, this, [this] { save(); });
    }

    static QString defaultPath() {
        return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/flufflinux-appcenter.conf";
    }

    Launch launchFor(const QSize &available) const {
        const auto value = rustUtility({{"operation", "window-read"}, {"path", m_path},
            {"width", available.width()}, {"height", available.height()}});
        return {QSize(value["normalWidth"].toInt(), value["normalHeight"].toInt()),
            QSize(value["width"].toInt(), value["height"].toInt()), value["maximized"].toBool()};
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
            // Wayland can briefly report NoState while a minimized/hidden
            // surface is unmapped. That is not the user unmaximizing it.
            if (state == Qt::WindowNoState && QGuiApplication::platformName().startsWith("wayland")
                    && (!m_window->isVisible()
                    || m_window->visibility() == QWindow::Minimized)) return;
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

    void present() {
        if (!m_window) return;
        // QWindow::show() means automatic visibility, not just "raise". It
        // resets maximized windows to normal during service/CLI activation.
        if (!m_window->isVisible() || m_window->visibility() == QWindow::Minimized) {
            if (m_maximized) m_window->showMaximized();
            else m_window->showNormal();
        }
    }

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
        const auto result = rustUtility({{"operation", "window-save"}, {"path", m_path},
            {"width", m_normalSize.width()}, {"height", m_normalSize.height()}, {"maximized", m_maximized}});
        if (!result["saved"].toBool())
            qWarning("Cannot save App Center window preferences.");
    }

    QString m_path;
    QPointer<QWindow> m_window;
    QTimer m_capture, m_save;
    QSize m_normalSize;
    bool m_maximized = true;
    bool m_firstExpose = true;
};
