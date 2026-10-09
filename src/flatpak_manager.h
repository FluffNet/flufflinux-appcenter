#pragma once
#include <QObject>
#include <QVariant>
#include <QJsonObject>
#include <QHash>
#include <QQueue>
#include <QTimer>
#include <memory>

// Presentation and Qt event-loop transport. The opaque Rust object owns all
// application state, validation, queue policy and persistence.
class FlatpakManager final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList jobs READ jobs NOTIFY jobsChanged)
    Q_PROPERTY(QVariantMap review READ review NOTIFY reviewChanged)
    Q_PROPERTY(QVariantMap recovery READ recovery NOTIFY recoveryChanged)
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
    QVariantList jobs() const { return m_state.value("jobs").toList(); }
    QVariantMap review() const { return m_state.value("review").toMap(); }
    QVariantMap recovery() const { return m_state.value("recovery").toMap(); }
    void enableRecovery() { dispatch("enableRecovery"); }
    Q_INVOKABLE void reviewRecovery(int index) { dispatch("reviewRecovery", {index}); }
    Q_INVOKABLE void dismissRecovery() { dispatch("dismissRecovery"); }
    Q_INVOKABLE void retryRecoveryIo() { dispatch("retryRecoveryIo"); }
    Q_INVOKABLE void refreshRecovery() { dispatch("loadRecovery"); }
    bool busy() const { return m_state.value("busy").toBool(); }
    QVariantList installedApps() const { return m_state.value("installedApps").toList(); }
    bool installedLoading() const { return m_state.value("installedLoading").toBool(); }
    QString installedError() const { return m_state.value("installedError").toString(); }
    int iconRevision() const { return m_state.value("iconRevision").toInt(); }
    QVariantMap installSizes() const { return m_state.value("installSizes").toMap(); }
    QVariantMap appPermissions() const { return m_state.value("appPermissions").toMap(); }
    QVariantMap appAddons() const { return m_state.value("appAddons").toMap(); }
    QVariantMap updates() const { return m_state.value("updates").toMap(); }
    QVariantList catalog() const { return m_state.value("catalog").toList(); }
    bool catalogLoading() const { return m_state.value("catalogLoading").toBool(); }
    int catalogProgress() const { return m_state.value("catalogProgress").toInt(); }
    bool catalogSourcesUnavailable() const { return m_state.value("catalogSourcesUnavailable").toBool(); }
    QVariantList repositories() const { return m_state.value("repositories").toList(); }
    bool sourcesBusy() const { return m_state.value("sourcesBusy").toBool(); }
    QString sourceInputStatus() const { return m_state.value("sourceInputStatus").toString(); }
    QString sourcesError() const { return m_state.value("sourcesError").toString(); }
    Q_INVOKABLE int requestAppAddons(QVariantMap app) { return dispatch("requestAppAddons", {app}).toInt(); }
    Q_INVOKABLE void cancelAppAddons(int token = 0) { dispatch("cancelAppAddons", {token}); }
    Q_INVOKABLE void changeAddon(QString reference, bool install) { dispatch("changeAddon", {reference, install}); }
    Q_INVOKABLE void checkForUpdates() { dispatch("checkForUpdates", {}); }
    Q_INVOKABLE void cancelUpdateCheck() { dispatch("cancelUpdateCheck", {}); }
    Q_INVOKABLE void selectUpdate(QString key, bool selected) { dispatch("selectUpdate", {key, selected}); }
    Q_INVOKABLE void selectAllUpdates(bool selected) { dispatch("selectAllUpdates", {selected}); }
    Q_INVOKABLE void installSelectedUpdates() { dispatch("installSelectedUpdates", {}); }
    Q_INVOKABLE int requestAppPermissions(QVariantMap app) { return dispatch("requestAppPermissions", {app}).toInt(); }
    Q_INVOKABLE void cancelAppPermissions(int token = 0) { dispatch("cancelAppPermissions", {token}); }
    Q_INVOKABLE void installApp(QVariantMap app) { dispatch("installApp", {app}); }
    Q_INVOKABLE void requestInstallInfo(QVariantMap app) { dispatch("requestInstallInfo", {app}); }
    Q_INVOKABLE void uninstallApp(QVariantMap app) { dispatch("uninstallApp", {app}); }
    Q_INVOKABLE void openSource(QString source) { dispatch("openSource", {source}); }
    Q_INVOKABLE void answerReview(int token, bool accept) { dispatch("answerReview", {token, accept}); }
    Q_INVOKABLE void cancelJob(int index) { dispatch("cancelJob", {index}); }
    Q_INVOKABLE void cancelAll() { dispatch("cancelAll", {}); }
    Q_INVOKABLE void clearDownloadHistory() { dispatch("clearDownloadHistory", {}); }
    Q_INVOKABLE void refreshInstalled() { dispatch("refreshInstalled", {}); }
    Q_INVOKABLE void launchApp(QVariantMap app) { dispatch("launchApp", {app}); }
    Q_INVOKABLE void refreshSources(bool refreshCatalogs = false) { dispatch("refreshSources", {refreshCatalogs}); }
    Q_INVOKABLE void setSourceEnabled(QVariantMap source, bool enabled) { dispatch("setSourceEnabled", {source, enabled}); }
    Q_INVOKABLE void removeSource(QVariantMap source) { dispatch("removeSource", {source}); }
    Q_INVOKABLE void addDefaultSources() { dispatch("addDefaultSources", {}); }
    void openInstalledApplication(QString source) { dispatch("openInstalledApplication", {source}); }
    void loadCatalog(const QString &path = {}) { dispatch("loadCatalog", {path}); }
    void setCatalogNetworkState(const QString &state, bool ready) { dispatch("setCatalogNetworkState", {state, ready}); }
    void initializeSources() { dispatch("initializeSources"); }
    bool backgroundWorkPending() const { return m_state.value("backgroundWorkPending").toBool(); }
    QVariantMap popularity() const { return m_state.value("popularity").toMap(); }
    void loadPopularity() { dispatch("loadPopularity"); }
    void enableBackground() { dispatch("backgroundEnable"); }
    void setBackgroundClosed(bool closed) { dispatch("backgroundClosed", {closed}); }
    void backgroundIdle() { dispatch("backgroundIdle"); }
signals:
    void jobsChanged();
    void reviewChanged();
    void recoveryChanged();
    void updatesRequested();
    void installedChanged();
    void installSizesChanged();
    void appPermissionsChanged();
    void appAddonsChanged();
    void updatesChanged();
    void catalogChanged();
    void catalogProgressChanged();
    void repositoriesChanged();
    void appOpened(QVariantMap app);
    void homeRequested();
    void inputError(QString message);
    void popularityChanged();
    void backgroundCommand(QVariantMap command);
private slots:
    void refreshThemeIcons(int group);
private:
    struct Process;
    QVariant dispatch(const QString &action, const QVariantList &arguments = {});
    QVariant apply(char *reply);
    void applyResponse(const QJsonObject &response);
    void execute(const QJsonObject &command);
    void readOutput(const std::shared_ptr<Process> &process, bool diagnostics);
    void finish(const std::shared_ptr<Process> &process, int code, bool crashed);
    void processEvent(const std::shared_ptr<Process> &process, QJsonObject message);
    void *m_backend = nullptr;
    QVariantMap m_state;
    QQueue<QJsonObject> m_responses;
    QHash<quint64, std::shared_ptr<Process>> m_processes;
    QHash<QString, QTimer *> m_timers;
    bool m_stopping = false;
    bool m_applying = false;
};
