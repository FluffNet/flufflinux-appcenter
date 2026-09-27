#include "background_queue.h"
#include "flatpak_manager.h"
#include <KJob>
#include <KUiServerV2JobTracker>
#include "sleep_inhibitor.h"
#include <KStatusNotifierItem>
#include <QApplication>
#include <QCloseEvent>
#include <QMenu>
#include <QWindow>
#include <cmath>

class BackgroundJob final : public KJob {
public:
    explicit BackgroundJob(QObject *parent, std::function<void()> cancel = {})
        : KJob(parent), m_cancel(std::move(cancel)) {
        if (m_cancel) setCapabilities(Killable);
        setProperty("desktopFileName", "org.kde.discover");
        setProperty("immediateProgressReporting", true);
    }
    void start() override {}
    void update(const QVariantMap &job) {
        const auto name = job.value("name", job.value("id")).toString();
        const auto action = job.value("action").toString();
        const auto title = action == "uninstall" ? tr("Removing %1").arg(name)
            : action == "update" ? tr("Updating %1").arg(name) : tr("Installing %1").arg(name);
        Q_EMIT description(this, title, {}, {});
        const bool downloading = job.value("hasDownload").toBool() && !job.value("downloadComplete").toBool()
            && job.value("phase") == "download";
        Q_EMIT infoMessage(this, downloading
            ? tr("%1 / %2 (%3)").arg(job.value("downloadedSize").toString(),
                job.value("downloadTotalSize").toString(), job.value("downloadSpeed").toString())
            : job.value("status").toString());
        setTotalAmount(Bytes, job.value("downloadTotalBytes").toULongLong());
        setProcessedAmount(Bytes, job.value("receivedBytes").toULongLong());
        // Same overall percentage as the in-window bar, including deployment.
        setPercent(static_cast<unsigned long>(std::floor(qBound(0.0, job.value("progress").toDouble(), .99) * 100)));
        emitSpeed(job.value("downloadSpeedBytes").toULongLong());
    }
    void finish(int error = 0, const QString &message = {}) {
        setError(error); setErrorText(message); emitResult();
    }
    void complete(const QVariantMap &job) {
        if (job.value("failed").toBool()) { finish(UserDefinedError, job.value("error").toString()); return; }
        const auto name = job.value("name", job.value("id")).toString();
        const auto action = job.value("action").toString();
        Q_EMIT description(this, action == "uninstall" ? tr("%1 removed").arg(name)
            : action == "update" ? tr("%1 updated").arg(name) : tr("%1 installed").arg(name), {}, {});
        Q_EMIT infoMessage(this, tr("Complete"));
        setPercent(100); finish();
    }
protected:
    bool doKill() override {
        // Cancellation must be acknowledged by Flatpak, not declared finished
        // by the notification's Stop button while a deployment still runs.
        if (m_cancel) m_cancel();
        return false;
    }
private:
    std::function<void()> m_cancel;
};

BackgroundQueue::BackgroundQueue(FlatpakManager *manager, QWindow *window,
                                 std::function<void()> showWindow, QObject *parent)
    : QObject(parent), m_manager(manager), m_window(window), m_showWindow(std::move(showWindow)),
      m_tracker(std::make_unique<KUiServerV2JobTracker>()),
      m_power(std::make_unique<SleepInhibitor>()) {
    window->installEventFilter(this);
    connect(manager, &FlatpakManager::jobsChanged, this, &BackgroundQueue::synchronize);
    connect(manager, &FlatpakManager::reviewChanged, this, &BackgroundQueue::synchronize);
    connect(window, &QWindow::visibleChanged, this, [this](bool visible) {
        if (!visible || !m_closed) return;
        m_closed = false; m_idle.stop(); detachJobs(); m_tray.reset();
    });
    m_idle.setInterval(2000);
    m_idle.setSingleShot(true);
    connect(&m_idle, &QTimer::timeout, this, [this] {
        if (m_closed && !m_manager->busy()) QCoreApplication::quit();
    });
    synchronize();
}

BackgroundQueue::~BackgroundQueue() {
    detachJobs();
}
bool BackgroundQueue::inhibiting() const { return m_power->requested(); }

bool BackgroundQueue::eventFilter(QObject *object, QEvent *event) {
    if (object == m_window && event->type() == QEvent::Close) {
        // A real Close (not Minimize or focus loss) enters background mode.
        static_cast<QCloseEvent *>(event)->ignore();
        m_closed = true;
        m_window->hide();
        synchronize();
        return true;
    }
    return QObject::eventFilter(object, event);
}

void BackgroundQueue::detachJobs() {
    const auto jobs = m_jobs; m_jobs.clear();
    // KDE discards cancelled proxy views. This does NOT cancel the underlying
    // worker, and does not produce a false "finished" notification on reopen.
    for (auto job : jobs) job->finish(KJob::KilledJobError);
}

void BackgroundQueue::synchronize() {
    const auto jobs = m_manager->jobs();
    bool transactions = false;
    int count = 0;
    QMap<int, QVariantMap> byIndex;
    for (const auto &entry : jobs) {
        const auto job = entry.toMap();
        byIndex.insert(job.value("index").toInt(), job);
        if (!job.value("active").toBool()) continue;
        ++count;
        if (job.value("action") != "uninstall" || job.value("removalConfirmed").toBool()) transactions = true;
    }
    m_power->setActive(transactions);
    if (!m_closed) return;
    if (m_manager->busy()) m_idle.stop();
    else if (!m_idle.isActive()) m_idle.start();

    if (count && !m_tray) {
        m_tray = std::make_unique<KStatusNotifierItem>("flufflinux-appcenter-queue");
        m_tray->setCategory(KStatusNotifierItem::ApplicationStatus);
        m_tray->setTitle(tr("App Center"));
        m_tray->setIconByName("flufflinux-appcenter");
        m_tray->setStandardActionsEnabled(false);
        auto menu = new QMenu;
        menu->addAction(tr("Open App Center"), this, m_showWindow);
        m_tray->setContextMenu(menu);
        connect(m_tray.get(), &KStatusNotifierItem::activateRequested, this, [this] { m_showWindow(); });
        // Never NeedsAttention: fullscreen apps must not get an attention popup.
        m_tray->setStatus(KStatusNotifierItem::Active);
    }
    if (m_tray) {
        m_tray->setToolTip("flufflinux-appcenter", tr("App Center"), m_manager->review().isEmpty()
            ? tr("%n app operation(s) in progress", nullptr, count)
            : tr("Confirmation needed — open App Center to continue"));
        if (!count) m_tray.reset();
    }
    for (auto it = m_jobs.begin(); it != m_jobs.end();) {
        const auto job = byIndex.value(it.key());
        if (job.isEmpty() || !job.value("active").toBool()) {
            auto proxy = it.value(); it = m_jobs.erase(it);
            if (job.isEmpty() || job.value("cancelled").toBool()) proxy->finish(KJob::KilledJobError);
            else proxy->complete(job);
        } else ++it;
    }
    for (auto it = byIndex.cbegin(); it != byIndex.cend(); ++it) {
        const auto &job = it.value();
        if (!job.value("active").toBool() || job.value("queued").toBool()) continue;
        if (!m_jobs.contains(it.key())) {
            const int index = it.key();
            auto proxy = new BackgroundJob(this, [this, index] { m_manager->cancelJob(index); });
            m_jobs.insert(index, proxy); m_tracker->registerJob(proxy);
        }
        m_jobs[it.key()]->update(job);
    }
}
