#include "background_queue.h"
#include "flatpak_manager.h"
#include "sleep_inhibitor.h"
#include <KJob>
#include <KUiServerV2JobTracker>
#include <KStatusNotifierItem>
#include <QApplication>
#include <QCloseEvent>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QMenu>
#include <QWindow>

class BackgroundJob final : public KJob {
public:
    explicit BackgroundJob(QObject *parent, std::function<void()> cancel)
        : KJob(parent), m_cancel(std::move(cancel)) {
        setCapabilities(Killable);
        setProperty("desktopFileName", "org.kde.discover");
        setProperty("immediateProgressReporting", true);
    }
    void start() override { startElapsedTimer(); }
    void detach(KUiServerV2JobTracker *tracker) {
        // Unregister only the native view, without resetting elapsed time.
        setError(KilledJobError); tracker->unregisterJob(this); setError(NoError);
    }
    void update(const QVariantMap &data) {
        Q_EMIT description(this, data.value("title").toString(), {}, {});
        Q_EMIT infoMessage(this, data.value("message").toString());
        setTotalAmount(Bytes, data.value("totalBytes").toULongLong());
        setProcessedAmount(Bytes, data.value("receivedBytes").toULongLong());
        setPercent(data.value("percent").toUInt());
        emitSpeed(data.value("speed").toULongLong());
    }
    void finish(const QVariantMap &data, bool discard) {
        if (discard) setError(KilledJobError);
        else if (data.value("failed").toBool()) {
            setError(UserDefinedError); setErrorText(data.value("error").toString());
        } else {
            Q_EMIT description(this, data.value("completionTitle").toString(), {}, {});
            Q_EMIT infoMessage(this, tr("Complete"));
            setPercent(100);
        }
        emitResult();
    }
protected:
    bool doKill() override {
        m_cancel();
        // The real transaction, not the proxy, acknowledges cancellation.
        return false;
    }
private:
    std::function<void()> m_cancel;
};

BackgroundQueue::BackgroundQueue(FlatpakManager *manager, QWindow *window,
                                 std::function<void()> showWindow, QObject *parent)
    : QObject(parent), m_manager(manager), m_window(window), m_showWindow(std::move(showWindow)),
      m_tracker(std::make_unique<KUiServerV2JobTracker>()), m_power(std::make_unique<SleepInhibitor>()) {
    window->installEventFilter(this);
    connect(manager, &FlatpakManager::backgroundCommand, this, &BackgroundQueue::execute);
    connect(window, &QWindow::visibleChanged, this, [this](bool visible) {
        if (visible && m_closed) { m_closed = false; synchronize(); }
    });
    m_idle.setInterval(2000); m_idle.setSingleShot(true);
    connect(&m_idle, &QTimer::timeout, manager, &FlatpakManager::backgroundIdle);
    manager->enableBackground();
}
BackgroundQueue::~BackgroundQueue() {
    for (int index : m_registeredJobs) if (m_jobs.contains(index)) m_jobs[index]->detach(m_tracker.get());
}
bool BackgroundQueue::inhibiting() const { return m_power->requested(); }
void BackgroundQueue::synchronize() { m_manager->setBackgroundClosed(m_closed); }
bool BackgroundQueue::eventFilter(QObject *object, QEvent *event) {
    if (object == m_window && event->type() == QEvent::Close) {
        static_cast<QCloseEvent *>(event)->ignore();
        m_closed = true; m_window->hide(); synchronize(); return true;
    }
    return QObject::eventFilter(object, event);
}
void BackgroundQueue::execute(const QVariantMap &command) {
    const auto kind = command.value("kind").toString();
    const int index = command.value("index").toInt();
    if (kind == "create") {
        auto proxy = new BackgroundJob(this, [this, index] { m_manager->cancelJob(index); });
        proxy->start(); m_jobs.insert(index, proxy);
    } else if (kind == "register") {
        if (auto proxy = m_jobs.value(index)) { m_registeredJobs.insert(index); m_tracker->registerJob(proxy); }
    } else if (kind == "detach") {
        if (auto proxy = m_jobs.value(index)) { m_registeredJobs.remove(index); proxy->detach(m_tracker.get()); }
    } else if (kind == "update") {
        if (auto proxy = m_jobs.value(index)) proxy->update(command.value("data").toMap());
    } else if (kind == "finish") {
        m_registeredJobs.remove(index);
        if (auto proxy = m_jobs.take(index)) proxy->finish(command.value("data").toMap(), command.value("discard").toBool());
    } else if (kind == "power") {
        m_power->setActive(command.value("active").toBool());
    } else if (kind == "idle") {
        if (!command.value("active").toBool()) m_idle.stop();
        else if (!m_idle.isActive()) m_idle.start();
    } else if (kind == "quit") {
        QCoreApplication::quit();
    } else if (kind == "tray") {
        if (!command.value("visible").toBool()) { m_tray.reset(); return; }
        if (!m_tray) {
            m_tray = std::make_unique<KStatusNotifierItem>("flufflinux-appcenter-queue");
            m_tray->setCategory(KStatusNotifierItem::ApplicationStatus);
            m_tray->setTitle(tr("App Center")); m_tray->setIconByName("flufflinux-appcenter");
            m_tray->setStandardActionsEnabled(false);
            auto menu = new QMenu;
            menu->addAction(tr("Open App Center"), this, m_showWindow);
            m_tray->setContextMenu(menu);
            connect(m_tray.get(), &KStatusNotifierItem::activateRequested, this, [this] { m_showWindow(); });
            // KDE supplies fullscreen/DND behavior. Never request attention.
            m_tray->setStatus(KStatusNotifierItem::Active);
        }
        m_tray->setToolTip("flufflinux-appcenter", tr("App Center"), command.value("message").toString());
    } else if (kind == "summary") {
        auto message = QDBusMessage::createMethodCall("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications", "Notify");
        message << QStringLiteral("App Center") << uint(0) << QStringLiteral("flufflinux-appcenter")
            << command.value("title").toString() << command.value("body").toString() << QStringList{}
            << QVariantMap{{"desktop-entry", "org.kde.discover"}, {"urgency", uchar(1)}} << command.value("timeout").toInt();
        QDBusConnection::sessionBus().asyncCall(message);
    }
}
