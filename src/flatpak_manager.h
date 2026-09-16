#pragma once
#include <QObject>
#include <QVariant>
#include <QProcess>
#include <QTimer>
#include <QHash>
#include <QJsonObject>

class FlatpakManager final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList jobs READ jobs NOTIFY jobsChanged)
    Q_PROPERTY(QVariantMap review READ review NOTIFY reviewChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY jobsChanged)
    Q_PROPERTY(QVariantList installedApps READ installedApps NOTIFY installedChanged)
    Q_PROPERTY(bool installedLoading READ installedLoading NOTIFY installedChanged)
    Q_PROPERTY(QString installedError READ installedError NOTIFY installedChanged)
    Q_PROPERTY(int iconRevision READ iconRevision NOTIFY installedChanged)
public:
    explicit FlatpakManager(const QVariantList &catalog, QObject *parent = nullptr);
    ~FlatpakManager() override;
    QVariantList jobs() const { return m_jobs; }
    QVariantMap review() const { return m_review; }
    bool busy() const;
    QVariantList installedApps() const { return m_installed; }
    bool installedLoading() const { return m_loading; }
    QString installedError() const { return m_installedError; }
    int iconRevision() const { return m_iconRevision; }
    Q_INVOKABLE void installApp(QVariantMap app);
    Q_INVOKABLE void uninstallApp(QVariantMap app);
    Q_INVOKABLE void openSource(QString source);
    Q_INVOKABLE void answerReview(int token, bool accept);
    Q_INVOKABLE void cancelJob(int index);
    Q_INVOKABLE void cancelAll();
    Q_INVOKABLE void refreshInstalled();
    Q_INVOKABLE void launchApp(QVariantMap app);
signals:
    void jobsChanged();
    void reviewChanged();
    void installedChanged();
    void appOpened(QVariantMap app);
    void inputError(QString message);
private:
    void enqueue(QVariantMap request);
    void startNext();
    void receive();
    void handleMessage(const QJsonObject &message);
    void patchJob(int index, const QVariantMap &values);
    void refreshCaches();
    QVariantMap metadata(const QString &id) const;
    QVariantList m_jobs, m_requests, m_installed;
    QVariantMap m_review;
    QHash<QString, QVariantMap> m_metadata;
    QProcess m_worker, m_installedProcess, m_cache;
    QTimer m_installedTimeout, m_cacheTimeout;
    QByteArray m_buffer, m_diagnostics;
    int m_current = -1, m_iconRevision = 0;
    bool m_resultReceived = false, m_loading = true, m_stopping = false;
    QString m_installedError;
};
