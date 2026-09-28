#pragma once
#include <QObject>
#include <QVariant>
#include <QProcess>
#include <QTimer>
#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QDateTime>
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
    Q_PROPERTY(QVariantMap appPermissions READ appPermissions NOTIFY appPermissionsChanged)
    Q_PROPERTY(QVariantMap appAddons READ appAddons NOTIFY appAddonsChanged)
    Q_PROPERTY(QVariantMap updates READ updates NOTIFY updatesChanged)
    Q_PROPERTY(QVariantList catalog READ catalog NOTIFY catalogChanged)
    Q_PROPERTY(bool catalogLoading READ catalogLoading NOTIFY catalogChanged)
    Q_PROPERTY(int catalogProgress READ catalogProgress NOTIFY catalogProgressChanged)
    Q_PROPERTY(bool catalogSourcesUnavailable READ catalogSourcesUnavailable NOTIFY catalogChanged)
    Q_PROPERTY(QVariantList repositories READ repositories NOTIFY repositoriesChanged)
    Q_PROPERTY(bool sourcesBusy READ sourcesBusy NOTIFY repositoriesChanged)
    Q_PROPERTY(QString sourceInputStatus READ sourceInputStatus NOTIFY jobsChanged)
    Q_PROPERTY(QString sourcesError READ sourcesError NOTIFY repositoriesChanged)
public:
    explicit FlatpakManager(const QVariantList &catalog, QObject *parent = nullptr);
    ~FlatpakManager() override;
    QVariantList jobs() const;
    QVariantMap installSizes() const { return m_installSizes; }
    QVariantMap appPermissions() const { return m_appPermissions; }
    QVariantMap appAddons() const { return m_appAddons; }
    Q_INVOKABLE int requestAppAddons(QVariantMap app);
    Q_INVOKABLE void cancelAppAddons(int token = 0);
    Q_INVOKABLE void changeAddon(QString reference, bool install);
    QVariantMap updates() const;
    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void cancelUpdateCheck();
    Q_INVOKABLE void selectUpdate(QString key, bool selected);
    Q_INVOKABLE void selectAllUpdates(bool selected);
    Q_INVOKABLE void installSelectedUpdates();
    Q_INVOKABLE int requestAppPermissions(QVariantMap app);
    Q_INVOKABLE void cancelAppPermissions(int token = 0);
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
    void openInstalledApplication(QString source);
    Q_INVOKABLE void answerReview(int token, bool accept);
    Q_INVOKABLE void cancelJob(int index);
    Q_INVOKABLE void cancelAll();
    Q_INVOKABLE void clearDownloadHistory();
    Q_INVOKABLE void refreshInstalled();
    Q_INVOKABLE void launchApp(QVariantMap app);
    QVariantList catalog() const { return m_catalog; }
    bool catalogLoading() const { return m_catalogRefreshPending || m_catalogAwaitingSources || m_catalogProcess.state() != QProcess::NotRunning; }
    int catalogProgress() const { return m_catalogProgress; }
    // Closing the window must not kill a post-transaction cache write. A
    // refresh deferred for offline connectivity is not active background work.
    bool backgroundWorkPending() const { return busy() || m_catalogProcess.state() != QProcess::NotRunning; }
    void loadCatalog(const QString &cachePath = {});
    void setCatalogNetworkState(const QString &state, bool ready);
    // Usable cached applications remain browsable even if refreshing fails.
    bool catalogSourcesUnavailable() const { return m_catalogLoadsFailed && m_catalog.isEmpty(); }
    QVariantList repositories() const { return m_repositories; }
    bool sourcesBusy() const { return m_sourceProcess.state() != QProcess::NotRunning; }
    QString sourceInputStatus() const;
    QString sourcesError() const { return m_sourcesError; }
    void initializeSources();
    Q_INVOKABLE void refreshSources(bool refreshCatalogs = false);
    Q_INVOKABLE void setSourceEnabled(QVariantMap source, bool enabled);
    Q_INVOKABLE void removeSource(QVariantMap source);
    Q_INVOKABLE void addDefaultSources();
signals:
    void jobsChanged();
    void reviewChanged();
    void installedChanged();
    void appOpened(QVariantMap app);
    void homeRequested();
    void inputError(QString message);
    void installSizesChanged();
    void appPermissionsChanged();
    void appAddonsChanged();
    void updatesChanged();
    void catalogChanged();
    void catalogProgressChanged();
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
    void reloadCatalog(bool force = false);
    void setCatalog(const QVariantList &catalog);
    void setCatalogProgress(int progress, bool reset = false);
    void readCatalogProgress();
    void startCatalogRefresh();
    void drainApplicationLinks();
    void drainInstalledApplicationLinks();
    QStringList m_pendingApplicationLinks;
    QStringList m_pendingInstalledApplicationLinks;
    QVariantList m_jobs, m_requests, m_installed, m_pendingReviews;
    quint64 m_queueBatch = 0;
    QVariantMap m_review;
    QVariantMap m_installSizes, m_sizeApp;
    QVariantMap m_appPermissions;
    QProcess *m_permissionsProcess = nullptr;
    int m_permissionsToken = 0;
    QVariantMap m_appAddons;
    QProcess *m_addonsProcess = nullptr;
    int m_addonsToken = 0;
    InstallHistory m_installHistory;
    InstallHistory m_updateHistory{QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/update-dates.json"};
    QProcess m_updatesProcess;
    QTimer m_updatesTimeout;
    QByteArray m_updatesBuffer;
    QVariantList m_updates;
    QStringList m_updatesSkipped;
    bool m_updateSourcesChanged = false;
    QString m_updatesState = "idle", m_updatesStatus, m_updatesError, m_lastChecked;
    bool m_updatesResult = false;
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
    QTimer m_catalogTimeout;
    bool m_catalogTimedOut = false;
    int m_catalogProgress = 0;
    QByteArray m_catalogProgressBuffer;
    QByteArray m_sourceBuffer;
    QString m_sourcesError;
    bool m_catalogLoadsFailed = false;
    QString m_catalogCachePath, m_catalogFingerprint, m_catalogReadFingerprint;
    QDateTime m_catalogSavedAt;
    bool m_catalogForceAgain = false, m_sourceRefreshCatalog = false;
    bool m_catalogAwaitingSources = false, m_catalogResetAge = false;
    bool m_catalogHasRefreshedSources = false;
    bool m_catalogRefreshPending = false, m_catalogNetworkReady = true, m_catalogOffline = false;
    bool m_sourceSucceeded = false, m_sourceCatalogReported = false;
    int m_sourceCatalogsRefreshed = 0;
    QStringList m_pendingInputs;
    bool m_sourceResult = false, m_sourceListing = false, m_catalogAgain = false, m_sourcesRefreshPending = false;
};
