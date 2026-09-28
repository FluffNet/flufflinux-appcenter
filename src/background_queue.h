#pragma once

#include <QObject>
#include <QEventLoopLocker>
#include <QPointer>
#include <QTimer>
#include <QMap>
#include <QSet>
#include <QVariantMap>
#include <functional>
#include <memory>

class FlatpakManager;
class QWindow;
class KUiServerV2JobTracker;
class SleepInhibitor;
class KStatusNotifierItem;
class BackgroundJob;

// The session service owns the manager, not the visible window. KDE's native
// job tracker supplies tray progress and respects fullscreen / Do Not Disturb.
class BackgroundQueue final : public QObject {
public:
    BackgroundQueue(FlatpakManager *manager, QWindow *window,
                    std::function<void()> showWindow, QObject *parent = nullptr);
    ~BackgroundQueue() override;
    bool closed() const { return m_closed; }
    int trackedJobs() const { return m_registeredJobs.size(); }
    bool inhibiting() const;
    void synchronize();
protected:
    bool eventFilter(QObject *object, QEvent *event) override;
private:
    void detachJobs();
    void reportBatch();
    FlatpakManager *m_manager;
    QPointer<QWindow> m_window;
    std::function<void()> m_showWindow;
    std::unique_ptr<KUiServerV2JobTracker> m_tracker;
    std::unique_ptr<SleepInhibitor> m_power;
    std::unique_ptr<KStatusNotifierItem> m_tray;
    QMap<int, BackgroundJob *> m_jobs;
    QSet<int> m_registeredJobs;
    QMap<int, QVariantMap> m_batchJobs;
    quint64 m_batchId = 0;
    bool m_batchReported = true;
    QTimer m_idle;
    bool m_closed = false;
    // Native KJob notifications have their own quit locks. Their final release
    // must not exit the hidden app before our workers/cache writes finish.
    // Only the controller's explicit idle quit ends this service.
    QEventLoopLocker m_lifetimeLock;
};
