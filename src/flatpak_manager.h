#pragma once
#include <QObject>
#include <QVariant>
#include <QProcess>
#include <QTimer>
#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include "install_history.h"
#include "download_rate.h"

class FlatpakManager final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList jobs READ jobs NOTIFY jobsChanged)
    Q_PROPERTY(QVariantMap review READ review NOTIFY reviewChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY jobsChanged)
    Q_PROPERTY(QVariantList installedApps READ installedApps NOTIFY installedChanged)
    Q_PROPERTY(bool installedLoading READ installedLoading NOTIFY installedChanged)
    Q_PROPERTY(QString installedError READ installedError NOTIFY installedChanged)
    Q_PROPERTY(int iconRevision READ iconRevision NOTIFY installedChanged)
    Q_PROPERTY(QVariantMap installSizes READ installSizes NOTIFY installSizesChanged)
    Q_PROPERTY(QVariantList catalog READ catalog NOTIFY catalogChanged)
    Q_PROPERTY(QVariantList repositories READ repositories NOTIFY repositoriesChanged)
    Q_PROPERTY(bool sourcesBusy READ sourcesBusy NOTIFY repositoriesChanged)
    Q_PROPERTY(QString sourcesError READ sourcesError NOTIFY repositoriesChanged)
public:
    explicit FlatpakManager(const QVariantList &catalog, QObject *parent = nullptr);
    ~FlatpakManager() override;
    QVariantList jobs() const;
    QVariantMap installSizes() const { return m_installSizes; }
    QVariantMap review() const { return m_review; }
    bool busy() const;
    QVariantList installedApps() const { return m_installed; }
    bool installedLoading() const { return m_loading; }
    QString installedError() const { return m_installedError; }
    int iconRevision() const { return m_iconRevision; }
    Q_INVOKABLE void installApp(QVariantMap app);
    Q_INVOKABLE void requestInstallInfo(QVariantMap app);
    Q_INVOKABLE void uninstallApp(QVariantMap app);
    Q_INVOKABLE void openSource(QString source);
    Q_INVOKABLE void answerReview(int token, bool accept);
    Q_INVOKABLE void cancelJob(int index);
    Q_INVOKABLE void cancelAll();
    Q_INVOKABLE void clearDownloadHistory();
    Q_INVOKABLE void refreshInstalled();
    Q_INVOKABLE void launchApp(QVariantMap app);
    QVariantList catalog() const { return m_catalog; }
    QVariantList repositories() const { return m_repositories; }
    bool sourcesBusy() const { return m_sourceProcess.state() != QProcess::NotRunning; }
    QString sourcesError() const { return m_sourcesError; }
    void initializeSources();
    Q_INVOKABLE void refreshSources(bool refreshCatalogs = false);
    Q_INVOKABLE void setSourceEnabled(QVariantMap source, bool enabled);
    Q_INVOKABLE void removeSource(QVariantMap source);
signals:
    void jobsChanged();
    void reviewChanged();
    void installedChanged();
    void appOpened(QVariantMap app);
    void inputError(QString message);
    void installSizesChanged();
    void catalogChanged();
    void repositoriesChanged();
private slots:
    void refreshThemeIcons(int group);
private:
    struct WorkerState {
        QProcess process;
        QTimer cancelTimeout;
        QByteArray buffer, diagnostics;
        int current = -1;
        bool resultReceived = false;
    };
    void connectWorker(WorkerState &worker);
    WorkerState *workerForJob(int index);
    void queueReview(QVariantMap review, int index);
    void showNextReview();
    void clearReviewsForJob(int index);
    void enqueue(QVariantMap request);
    void startNext();
    void receive(WorkerState &worker);
    void handleMessage(WorkerState &worker, const QJsonObject &message);
    void patchJob(int index, const QVariantMap &values);
    QVariantMap downloadRateValues(const QVariantMap &job);
    void refreshCaches();
    void refreshNextCache();
    QVariantMap installRequest(const QVariantMap &app) const;
    QVariantMap metadata(const QString &id) const;
    void runSourceOperation(QVariantMap request);
    void reloadCatalog();
    QVariantList m_jobs, m_requests, m_installed, m_pendingReviews;
    QVariantMap m_review;
    QVariantMap m_installSizes, m_sizeApp;
    InstallHistory m_installHistory;
    QHash<QString, QVariantMap> m_sources;
    QHash<QString, QVariantMap> m_metadata;
    WorkerState m_installWorker, m_removalWorker;
    QProcess m_installedProcess, m_cache;
    QTimer m_installedTimeout, m_cacheTimeout, m_downloadRateTimer;
    QElapsedTimer m_downloadClock;
    DownloadRate m_downloadRate;
    QList<QStringList> m_cacheCommands;
    int m_iconRevision = 0, m_nextReviewToken = 0;
    int m_installedRevision = 0, m_installedReadRevision = 0;
    bool m_loading = true, m_stopping = false;
    bool m_refreshingCaches = false, m_cacheRefreshPending = false, m_installedRefreshPending = false;
    QString m_installedError;
    QVariantList m_catalog, m_repositories;
    QProcess m_sourceProcess, m_catalogProcess;
    QByteArray m_sourceBuffer;
    QString m_sourcesError;
    QStringList m_pendingInputs;
    bool m_sourceResult = false, m_sourceListing = false, m_catalogAgain = false, m_sourcesRefreshPending = false;
};
