#include <flatpak.h>
#include "flatpak_manager.h"
#include "transaction_progress.h"
#include "flatpak_sizes.h"
#include "flatpak_permissions.h"
#include "update_plan.h"
#include <algorithm>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QLocale>
#include <QPixmapCache>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <unistd.h>

namespace {
QString normalizedId(QString id) {
    if (id.endsWith(".desktop")) id.chop(8);
    return id;
}
bool active(const QVariantMap &job) { return job.value("active").toBool(); }
}

FlatpakManager::FlatpakManager(const QVariantList &catalog, QObject *parent) : QObject(parent) {
    m_catalog = catalog;
    connect(this, &FlatpakManager::catalogChanged, this, &FlatpakManager::drainApplicationLinks);
    connect(this, &FlatpakManager::installedChanged, this, &FlatpakManager::drainApplicationLinks);
    connect(&m_catalogProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this] { QTimer::singleShot(0, this, &FlatpakManager::drainApplicationLinks); });
    connect(&m_catalogProcess, &QProcess::errorOccurred, this,
        [this] { QTimer::singleShot(0, this, &FlatpakManager::drainApplicationLinks); });
    connect(this, &FlatpakManager::installedChanged, this, &FlatpakManager::updatesChanged);
    m_updatesTimeout.setSingleShot(true);
    m_updatesTimeout.setParent(this); m_updatesTimeout.setObjectName("updateCheckTimeout");
    connect(&m_updatesTimeout, &QTimer::timeout, this, [this] {
        m_updatesState = "error"; m_updatesError = tr("Checking for app updates timed out. Try again.");
        m_updatesProcess.kill(); emit updatesChanged();
    });
    connect(&m_updatesProcess, &QProcess::readyReadStandardOutput, this, [this] {
        m_updatesBuffer += m_updatesProcess.readAllStandardOutput();
        if (m_updatesBuffer.size() > 16 * 1024 * 1024) {
            m_updatesState = "error"; m_updatesError = tr("The app update response was too large.");
            m_updatesProcess.kill(); emit updatesChanged(); return;
        }
        while (m_updatesBuffer.contains('\n')) {
            const auto end = m_updatesBuffer.indexOf('\n');
            const auto message = QJsonDocument::fromJson(m_updatesBuffer.left(end)).object();
            m_updatesBuffer.remove(0, end + 1);
            if (m_updatesState != "checking") continue;
            if (message["type"] == "status") m_updatesStatus = message["message"].toString();
            if (message["type"] == "sources") {
                m_updateSourcesChanged = true;
                m_repositories = message["sources"].toArray().toVariantList();
                emit repositoriesChanged();
            }
            if (message["type"] == "updates") {
                m_updatesResult = true;
                m_updates = message["updates"].toArray().toVariantList();
                for (auto &value : m_updates) {
                    auto row = value.toMap();
                    row["icon"] = metadata(row.value("id").toString()).value("icon");
                    row["selected"] = true; value = row;
                }
                std::sort(m_updates.begin(), m_updates.end(), [](const QVariant &a, const QVariant &b) {
                    const auto left = a.toMap(), right = b.toMap();
                    if (left.value("runtime") != right.value("runtime")) return !left.value("runtime").toBool();
                    return QString::localeAwareCompare(left.value("name").toString(), right.value("name").toString()) < 0;
                });
                QStringList errors;
                for (const auto &error : message["errors"].toArray()) errors.append(error.toString());
                m_updatesError = errors.join('\n');
                m_updatesSkipped.clear();
                for (const auto &skipped : message["skipped"].toArray()) m_updatesSkipped.append(skipped.toString());
                m_lastChecked = message["checkedAt"].toString();
            }
            emit updatesChanged();
        }
    });
    connect(&m_updatesProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this](int code, QProcess::ExitStatus status) {
            m_updatesTimeout.stop();
            if (m_updatesState == "checking") {
                m_updatesState = m_updatesResult && !code && status == QProcess::NormalExit ? "ready" : "error";
                if (m_updatesState == "error") { m_updates.clear(); m_updatesError = tr("Could not finish checking for app updates. Try again."); }
            }
            emit updatesChanged(); emit jobsChanged();
            if (m_updateSourcesChanged) { m_updateSourcesChanged = false; reloadCatalog(); }
        });
    connect(&m_updatesProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        m_updatesTimeout.stop(); m_updatesState = "error";
        m_updatesError = tr("Could not start checking for app updates."); emit updatesChanged(); emit jobsChanged();
    });
    connect(&m_sourceProcess, &QProcess::readyReadStandardOutput, this, [this] {
        m_sourceBuffer += m_sourceProcess.readAllStandardOutput();
        while (m_sourceBuffer.contains('\n')) {
            const int end = m_sourceBuffer.indexOf('\n');
            const auto message = QJsonDocument::fromJson(m_sourceBuffer.left(end)).object();
            m_sourceBuffer.remove(0, end + 1);
            if (message["type"] == "sources") {
                const auto sources = message["sources"].toArray().toVariantList();
                if (sources != m_repositories) {
                    m_catalogLoadsFailed = false;
                    emit catalogChanged();
                }
                if (sources != m_repositories && m_updatesState == "ready") {
                    m_updates.clear(); m_updatesState = "idle"; m_updatesSkipped.clear();
                    m_updatesError.clear(); emit updatesChanged();
                }
                m_repositories = sources;
                emit repositoriesChanged(); reloadCatalog();
            } else if (message["type"] == "catalog-load") {
                // Only completed catalog loads establish availability. A source
                // settings error, empty result set or NM connectivity probe cannot.
                m_catalogLoadsFailed = message["available"].toInt() == 0 && message["failed"].toInt() > 0;
                emit catalogChanged();
            } else if (message["type"] == "result") {
                m_sourceResult = true;
                // Opening Settings must not erase a provisioning/refresh
                // error before the user has had a chance to read it.
                if (!m_sourceListing || !message["success"].toBool()) m_sourcesError = message["error"].toString();
                m_sourceProcess.closeWriteChannel();
            }
        }
    });
    connect(&m_sourceProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this] {
        if (!m_sourceResult) m_sourcesError = tr("Could not finish updating software sources.");
        emit repositoriesChanged(); emit jobsChanged(); reloadCatalog();
        const auto inputs = m_pendingInputs; m_pendingInputs.clear();
        for (const auto &source : inputs) openSource(source);
    });
    connect(&m_sourceProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_sourcesError = tr("Could not start the software-source worker.");
            emit repositoriesChanged(); emit jobsChanged();
        }
    });
    connect(&m_catalogProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this](int code, QProcess::ExitStatus status) {
            const auto document = QJsonDocument::fromJson(m_catalogProcess.readAllStandardOutput());
            if (!code && status == QProcess::NormalExit && document.isArray()) {
                m_catalog = document.array().toVariantList(); m_metadata.clear();
                for (const auto &entry : m_catalog) {
                    const auto app = entry.toMap();
                    m_metadata[normalizedId(app.value("id").toString())] = app;
                }
                emit catalogChanged();
                if (!m_sizeApp.isEmpty()) requestInstallInfo(m_sizeApp);
                refreshInstalled();
            }
            if (m_catalogAgain) { m_catalogAgain = false; reloadCatalog(); }
        });
    connectWorker(m_installWorker);
    connectWorker(m_removalWorker);
    m_downloadRateTimer.setInterval(500);
    connect(&m_downloadRateTimer, &QTimer::timeout, this, [this] {
        if (m_installWorker.current < 0 || m_installWorker.resultReceived) return;
        const auto job = m_jobs[m_installWorker.current].toMap();
        const auto values = downloadRateValues(job);
        if (values.value("downloadSpeed") != job.value("downloadSpeed")) patchJob(m_installWorker.current, values);
    });
    for (const auto &entry : catalog) {
        const auto app = entry.toMap();
        m_metadata.insert(normalizedId(app.value("id").toString()), app);
    }
    m_installedTimeout.setSingleShot(true);
    connect(&m_installedTimeout, &QTimer::timeout, this, [this] {
        m_installedError = tr("Reading installed Flatpaks timed out.");
        m_loading = false; emit installedChanged(); m_installedProcess.kill();
    });
    connect(&m_installedProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_installedTimeout.stop(); m_loading = false;
            m_installedError = tr("Could not start Flatpak to read installed apps."); emit installedChanged();
        }
    });
    connect(&m_installedProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this](int code, QProcess::ExitStatus status) {
            const bool stale = m_installedReadRevision != m_installedRevision;
            if (m_installedRefreshPending || stale) {
                m_installedRefreshPending = false;
                QTimer::singleShot(0, this, &FlatpakManager::refreshInstalled);
            }
            // A successful removal is newer than any list already in flight.
            if (stale) { m_installedTimeout.stop(); return; }
            if (!m_installedTimeout.isActive()) return;
            m_installedTimeout.stop(); m_loading = false;
            if (code || status != QProcess::NormalExit) {
                m_installedError = tr("Could not read installed Flatpaks: %1")
                    .arg(QString::fromUtf8(m_installedProcess.readAllStandardError()));
            } else {
                QVariantList apps;
                m_installHistory.reload();
                m_updateHistory.reload();
                for (const auto &line : QString::fromUtf8(m_installedProcess.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts)) {
                    const auto c = line.split('\t');
                    if (c.size() != 9) { m_installedError = tr("Flatpak returned an unexpected installed-app list."); break; }
                    auto app = metadata(c[0].trimmed());
                    if (!m_metadata.contains(c[0].trimmed())) {
                        app["name"] = c[1].trimmed(); app["summary"] = c[7].trimmed(); app["description"] = c[7].trimmed();
                    }
                    app["installedOrigin"] = c[3].trimmed();
                    app["installation"] = c[4].trimmed(); app["installedBranch"] = c[5].trimmed();
                    app["installedArch"] = c[6].trimmed(); app["installedVersion"] = c[8].trimmed();
                    quint64 installedBytes = 0;
                    const auto installedSize = localInstalledFlatpakSize(app, &installedBytes);
                    app["installedSize"] = installedSize;
                    if (!installedSize.isEmpty()) app["installedBytes"] = installedBytes;
                    const auto ref = "app/" + c[0].trimmed() + "/" + c[6].trimmed() + "/" + c[5].trimmed();
                    app["installedRef"] = ref;
                    const auto date = m_installHistory.date(c[4].trimmed(), ref);
                    if (!date.isEmpty()) {
                        app["installedAt"] = date;
                        app["installedDate"] = InstallHistory::displayDate(date);
                    }
                    const auto updated = m_updateHistory.date(c[4].trimmed(), ref);
                    if (!updated.isEmpty()) {
                        app["updatedAt"] = updated;
                        app["updatedDate"] = InstallHistory::displayDate(updated);
                    }
                    apps.append(app);
                }
                if (m_installedError.isEmpty()) m_installed = apps;
            }
            emit installedChanged();
        });
    m_cacheTimeout.setSingleShot(true);
    connect(&m_cacheTimeout, &QTimer::timeout, &m_cache, [this] { m_cache.kill(); });
    connect(&m_cache, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this](int code, QProcess::ExitStatus status) {
        if (code || status != QProcess::NormalExit)
            qWarning().noquote() << "Desktop cache refresh failed:" << m_cache.program() << m_cache.readAllStandardError().left(2048);
        refreshNextCache();
    });
    connect(&m_cache, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            qWarning().noquote() << "Desktop cache refresh could not start:" << m_cache.program() << m_cache.errorString();
            refreshNextCache();
        }
    });
    QDBusConnection::sessionBus().connect(QString(), QStringLiteral("/KIconLoader"),
        QStringLiteral("org.kde.KIconLoader"), QStringLiteral("iconChanged"), this, SLOT(refreshThemeIcons(int)));
    QTimer::singleShot(0, this, &FlatpakManager::refreshInstalled);
}
void FlatpakManager::connectWorker(WorkerState &worker) {
    worker.cancelTimeout.setSingleShot(true);
    connect(&worker.cancelTimeout, &QTimer::timeout, this, [this, &worker] {
        if (worker.current >= 0 && m_jobs[worker.current].toMap().value("cancelling").toBool()
            && worker.process.state() != QProcess::NotRunning) {
            qWarning("Flatpak cancellation timed out; stopping the transaction worker");
            worker.process.kill();
        }
    });
    connect(&worker.process, &QProcess::readyReadStandardOutput, this, [this, &worker] { receive(worker); });
    connect(&worker.process, &QProcess::readyReadStandardError, this, [&worker] {
        worker.diagnostics += worker.process.readAllStandardError();
        worker.diagnostics = worker.diagnostics.right(8192);
    });
    connect(&worker.process, &QProcess::errorOccurred, this, [this, &worker](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        worker.cancelTimeout.stop();
        if (&worker == &m_installWorker) m_downloadRateTimer.stop();
        patchJob(worker.current, {{"active", false}, {"queued", false}, {"failed", true},
            {"status", tr("Could not start Flatpak worker")}});
        if (m_requests[worker.current].toMap().value("prepareOnly").toBool() && !m_stopping)
            emit inputError(tr("Could not start Flatpak worker"));
        clearReviewsForJob(worker.current);
        worker.current = -1;
        QTimer::singleShot(0, this, &FlatpakManager::startNext);
    });
    connect(&worker.process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this, &worker](int, QProcess::ExitStatus) {
            receive(worker);
            worker.cancelTimeout.stop();
            if (&worker == &m_installWorker) m_downloadRateTimer.stop();
            const int index = worker.current;
            if (index < 0) return;
            if (!worker.resultReceived) {
                const bool cancelled = m_jobs[index].toMap().value("cancelling").toBool();
                patchJob(index, {{"active", false}, {"queued", false}, {"failed", !cancelled}, {"cancelled", cancelled},
                    {"status", cancelled ? QString() : tr("The Flatpak worker stopped unexpectedly")},
                    {"error", cancelled ? QString() : QString::fromUtf8(worker.diagnostics)}});
                if (!cancelled && !m_stopping && m_requests[index].toMap().value("prepareOnly").toBool())
                    emit inputError(tr("The Flatpak worker stopped unexpectedly")
                        + (worker.diagnostics.isEmpty() ? QString() : "\n" + QString::fromUtf8(worker.diagnostics)));
            }
            clearReviewsForJob(index);
            const bool preparation = m_requests[index].toMap().value("prepareOnly").toBool();
            worker.current = -1;
            if (!preparation && !m_stopping) {
                if (!m_sizeApp.isEmpty()) requestInstallInfo(m_sizeApp);
                refreshCaches();
                // Excluded apps are visible only while installed. Re-evaluate
                // that exception after deployment/removal, using local data.
                reloadCatalog();
            }
            QTimer::singleShot(0, this, &FlatpakManager::startNext);
        });
}
FlatpakManager::WorkerState *FlatpakManager::workerForJob(int index) {
    for (auto worker : {&m_installWorker, &m_removalWorker})
        if (worker->current == index) return worker;
    return nullptr;
}
void FlatpakManager::queueReview(QVariantMap review, int index) {
    review["workerToken"] = review.value("token");
    review["token"] = ++m_nextReviewToken;
    review["jobIndex"] = index;
    m_pendingReviews.append(review);
    showNextReview();
}
void FlatpakManager::showNextReview() {
    if (m_stopping || !m_review.isEmpty()) return;
    while (!m_pendingReviews.isEmpty()) {
        auto review = m_pendingReviews.takeFirst().toMap();
        const int index = review.value("jobIndex").toInt();
        if (index < 0 || index >= m_jobs.size() || !active(m_jobs[index].toMap())) continue;
        m_review = review;
        emit reviewChanged();
        return;
    }
}
void FlatpakManager::clearReviewsForJob(int index) {
    for (int i = m_pendingReviews.size() - 1; i >= 0; --i)
        if (m_pendingReviews[i].toMap().value("jobIndex").toInt() == index) m_pendingReviews.removeAt(i);
    if (!m_review.isEmpty() && m_review.value("jobIndex").toInt() == index) {
        m_review.clear();
        emit reviewChanged();
    }
    // Let a dialog's close handler finish before opening the next one.
    QTimer::singleShot(0, this, &FlatpakManager::showNextReview);
}
FlatpakManager::~FlatpakManager() {
    m_stopping = true;
    cancelAppPermissions();
    cancelAll();
    // Normal UI close is prevented while busy. Cover both workers on forced shutdown.
    for (auto worker : {&m_installWorker, &m_removalWorker}) {
        worker->process.closeWriteChannel();
        if (!worker->process.waitForFinished(3000) && worker->process.state() != QProcess::NotRunning) {
            worker->process.kill();
            worker->process.waitForFinished(1000);
        }
    }
    for (auto process : {&m_installedProcess, &m_cache, &m_sourceProcess, &m_catalogProcess, &m_updatesProcess}) {
        if (process->state() != QProcess::NotRunning) { process->kill(); process->waitForFinished(1000); }
    }
}
QVariantList FlatpakManager::jobs() const {
    QVariantList visible;
    // Keep internal indices stable for the worker/queue, but cancellations
    // are not session history and must not reach any of the UI consumers.
    for (const auto &entry : m_jobs) {
        auto job = entry.toMap();
        if (job.value("hidden").toBool() || job.value("cancelled").toBool()) continue;
        // Use catalog artwork before installation too, and retain it in the
        // session history. Unknown external apps fall back to their theme ID.
        job["icon"] = metadata(normalizedId(job.value("id").toString())).value("icon");
        visible.append(job);
    }
    return visible;
}
void FlatpakManager::clearDownloadHistory() {
    bool changed = false;
    for (auto &entry : m_jobs) {
        auto job = entry.toMap();
        if (active(job) || job.value("action") == "uninstall" || job.value("hidden").toBool()) continue;
        job["hidden"] = true;
        entry = job;
        changed = true;
    }
    // Never erase queue entries: workers and pending reviews retain their IDs.
    if (changed) emit jobsChanged();
}
QVariantMap FlatpakManager::installRequest(const QVariantMap &app) const {
    const auto id = normalizedId(app.value("id").toString());
    if (m_sources.contains(id)) {
        auto request = m_sources.value(id);
        request["prepareOnly"] = false; request["hidden"] = false;
        request["id"] = id; request["name"] = app.value("name");
        return request;
    }
    auto catalogApp = m_metadata.value(id, app);
    const auto variants = catalogApp.value("sources").toList();
    if (!variants.isEmpty()) {
        bool found = false;
        for (const auto &entry : variants) {
            const auto candidate = entry.toMap();
            if (candidate.value("remote") == app.value("remote") && candidate.value("flatpakRef") == app.value("flatpakRef")
                && candidate.value("sourceUrl") == app.value("sourceUrl")) {
                catalogApp = candidate; found = true; break;
            }
        }
        if (!found) return {}; // Never silently install from a different source.
    }
    return {{"action", "install"}, {"id", id}, {"name", app.value("name")}, {"installation", "user"},
        {"flatpakRef", catalogApp.value("flatpakRef")}, {"remote", catalogApp.value("remote")},
        {"sourceUrl", catalogApp.value("sourceUrl")}};
}
void FlatpakManager::requestInstallInfo(QVariantMap app) {
    if (m_stopping) return;
    const auto id = normalizedId(app.value("id").toString());
    if (id.isEmpty()) return;
    m_sizeApp = app;
    auto request = installRequest(app);
    // Only the currently displayed values are retained. Every app opening
    // reads current local metadata; there is no size cache or background job.
    m_installSizes = {{id, request.isEmpty() ? QVariantMap{{"state", "unavailable"}} : localFlatpakSizes(request)}};
    emit installSizesChanged();
}
void FlatpakManager::cancelAppPermissions(int token) {
    if (token && token != m_permissionsToken) return;
    auto process = m_permissionsProcess;
    m_permissionsProcess = nullptr;
    if (process) {
        process->disconnect(this);
        process->kill();
        connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), process, &QObject::deleteLater);
        if (process->state() == QProcess::NotRunning) process->deleteLater();
    }
    m_appPermissions.clear();
    emit appPermissionsChanged();
}
int FlatpakManager::requestAppPermissions(QVariantMap app) {
    cancelAppPermissions();
    if (m_stopping) return 0;
    const int token = ++m_permissionsToken;
    const bool installed = !app.value("installation").toString().isEmpty();
    QString program = QCoreApplication::applicationFilePath();
    QStringList arguments;
    QVariantMap request;
    if (installed) {
        for (const auto &item : m_installed) {
            const auto candidate = item.toMap();
            if (candidate.value("id") == app.value("id") && candidate.value("installation") == app.value("installation")
                && candidate.value("installedArch") == app.value("installedArch") && candidate.value("installedBranch") == app.value("installedBranch")) {
                request = candidate; break;
            }
        }
        if (!request.value("installedRef").toString().isEmpty()) {
            program = "flatpak";
            const auto scope = request.value("installation").toString();
            arguments = {"info", "--show-permissions", scope == "user" ? "--user" : scope == "system" ? "--system" : "--installation=" + scope, "--", request.value("installedRef").toString()};
        }
    } else {
        request = installRequest(app);
        if (!request.isEmpty()) arguments = {"--permissions-worker", QString::fromUtf8(QJsonDocument::fromVariant(request).toJson(QJsonDocument::Compact))};
    }
    if (arguments.isEmpty()) {
        m_appPermissions = AppPermissions::error(tr("Permission information is not available for this app. Refresh and try again."));
        emit appPermissionsChanged(); return token;
    }
    m_appPermissions = {{"state", "loading"}, {"installed", installed}};
    emit appPermissionsChanged();
    auto process = new QProcess(this);
    m_permissionsProcess = process;
    auto timer = new QTimer(process);
    timer->setSingleShot(true);
    auto finish = [this, process, installed, timer](QVariantMap result) {
        if (m_permissionsProcess != process) return;
        timer->stop(); m_permissionsProcess = nullptr;
        result["installed"] = installed;
        m_appPermissions = result;
        emit appPermissionsChanged();
    };
    connect(timer, &QTimer::timeout, process, [process, finish] {
        finish(AppPermissions::error(tr("Reading app permissions timed out. Please try again.")));
        process->kill();
    });
    connect(process, &QProcess::readyReadStandardOutput, this, [process, finish] {
        if (process->bytesAvailable() > 2 * 1024 * 1024) {
            finish(AppPermissions::error(tr("The permission information is too large to display."))); process->kill();
        }
    });
    connect(process, &QProcess::errorOccurred, this, [process, finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finish(AppPermissions::error(tr("Could not start the Flatpak permissions reader."))); process->deleteLater();
        }
    });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [process, finish, installed](int code, QProcess::ExitStatus status) {
        QVariantMap result;
        if (code || status != QProcess::NormalExit) result = AppPermissions::error(tr("Could not read app permissions. Please try again."));
        else if (installed) result = AppPermissions::parse(process->readAllStandardOutput(), true);
        else {
            result = QJsonDocument::fromJson(process->readAllStandardOutput()).object().toVariantMap();
            if (result.value("state") != "ready" && result.value("state") != "error")
                result = AppPermissions::error(tr("Flatpak returned invalid permission information."));
        }
        finish(result); process->deleteLater();
    });
    timer->start(30000);
    process->start(program, arguments);
    process->closeWriteChannel();
    return token;
}
bool FlatpakManager::busy() const {
    for (const auto &job : m_jobs) if (active(job.toMap())) return true;
    return m_installWorker.process.state() != QProcess::NotRunning
        || m_removalWorker.process.state() != QProcess::NotRunning || sourcesBusy() || m_refreshingCaches
        || m_updatesProcess.state() != QProcess::NotRunning;
}
QVariantMap FlatpakManager::updates() const {
    QString last;
    for (const auto &value : m_installed) {
        const auto date = value.toMap().value("updatedAt").toString();
        if (date > last) last = date;
    }
    return {{"state", m_updatesState}, {"items", m_updates}, {"status", m_updatesStatus},
        {"skipped", m_updatesSkipped},
        {"error", m_updatesError}, {"lastChecked", InstallHistory::displayDate(m_lastChecked)},
        {"lastUpdated", InstallHistory::displayDate(last)}};
}
void FlatpakManager::checkForUpdates() {
    if (busy()) return;
    m_updates.clear(); m_updatesBuffer.clear(); m_updatesError.clear(); m_updatesResult = false;
    m_updatesSkipped.clear(); m_updateSourcesChanged = false;
    m_updatesState = "checking"; m_updatesStatus = tr("Checking for app updates…");
    m_updatesProcess.start(QCoreApplication::applicationFilePath(), {"--updates-worker", "{\"restoreSystemFlathub\":true}"});
    m_updatesProcess.closeWriteChannel(); m_updatesTimeout.start(180000);
    emit updatesChanged(); emit jobsChanged();
}
void FlatpakManager::cancelUpdateCheck() {
    if (m_updatesState != "checking") return;
    m_updatesState = "cancelled"; m_updatesTimeout.stop(); m_updates.clear();
    m_updatesProcess.kill(); emit updatesChanged();
}
void FlatpakManager::selectUpdate(QString key, bool selected) {
    if (m_updatesState != "ready" || busy()) return;
    for (auto &value : m_updates) {
        auto row = value.toMap(); if (row.value("key") != key) continue;
        row["selected"] = selected; value = row;
    }
    emit updatesChanged();
}
void FlatpakManager::selectAllUpdates(bool selected) {
    if (m_updatesState != "ready" || busy()) return;
    for (auto &value : m_updates) { auto row = value.toMap(); row["selected"] = selected; value = row; }
    emit updatesChanged();
}
void FlatpakManager::installSelectedUpdates() {
    if (m_updatesState != "ready" || busy()) return;
    // Resolve selections from this successful scan; QML cannot supply refs,
    // versions, sources, or an unreviewed transaction plan.
    for (const auto &value : m_updates) {
        auto request = value.toMap(); if (!request.value("selected").toBool()) continue;
        request["action"] = "update"; enqueue(request);
    }
}
QString FlatpakManager::sourceInputStatus() const {
    // File/link inspection is deliberately hidden from Queue. Publish its
    // lifetime separately so Settings still shows work during network waits.
    for (const auto &entry : m_jobs) {
        const auto job = entry.toMap();
        if (!active(job) || !job.value("prepareOnly").toBool()) continue;
        if (job.value("queued").toBool()) return tr("Waiting to check software source…");
        if (job.value("status").toString() == tr("Waiting for confirmation"))
            return tr("Waiting for source confirmation…");
        return tr("Checking software source…");
    }
    return {};
}
QVariantMap FlatpakManager::metadata(const QString &id) const {
    auto app = m_metadata.value(id);
    if (app.isEmpty()) app = {{"id", id}, {"name", id}, {"icon", id}, {"summary", ""},
        {"description", ""}, {"category", ""}, {"developer", ""}, {"license", ""}, {"homepage", ""}, {"screenshots", QVariantList{}}};
    return app;
}
void FlatpakManager::patchJob(int index, const QVariantMap &values) {
    if (index < 0 || index >= m_jobs.size()) return;
    auto job = m_jobs[index].toMap();
    for (auto it = values.begin(); it != values.end(); ++it) job[it.key()] = it.value();
    m_jobs[index] = job; emit jobsChanged();
}
void FlatpakManager::enqueue(QVariantMap request) {
    const auto id = normalizedId(request.value("id").toString());
    if (request.value("action") != "update") request["id"] = id;
    for (const auto &entry : m_jobs) {
        const auto job = entry.toMap();
        if (active(job) && ((!id.isEmpty() && normalizedId(job.value("id").toString()) == id
                && (request.value("action") != "update" || job.value("action") != "update"
                    || job.value("key") == request.value("key")))
            || (id.isEmpty() && job.value("source") == request.value("source")))) return;
    }
    request["active"] = true; request["failed"] = false; request["progress"] = 0; request["queued"] = true;
    if (request.value("action") == "uninstall") request["removalConfirmed"] = false;
    request["status"] = tr("Queued"); request["operations"] = QVariantList{};
    request["index"] = m_jobs.size();
    m_requests.append(request); m_jobs.append(request); emit jobsChanged();
    if (request.value("action") == "uninstall") {
        const bool system = request.value("installation") != "user";
        queueReview({{"localRemoval", true}, {"kind", "transaction"}, {"removing", true},
            {"appId", id}, {"operations", QVariantList{}},
            {"title", tr("Uninstall %1?").arg(request.value("name").toString())},
            {"message", (system
                ? tr("If you proceed, %1 will be removed for all users, and its app data for this account will be deleted.")
                : tr("If you proceed, %1 and its app data will be removed.")).arg(request.value("name").toString())}},
            request.value("index").toInt());
    }
    startNext();
}
void FlatpakManager::installApp(QVariantMap app) {
    if (sourcesBusy()) { emit inputError(tr("Please wait for software sources to finish updating.")); return; }
    const auto id = normalizedId(app.value("id").toString());
    if (id.isEmpty()) return;
    for (const auto &entry : m_installed) if (normalizedId(entry.toMap().value("id").toString()) == id) return;
    const auto request = installRequest(app);
    if (request.isEmpty()) { emit inputError(tr("This app's source has changed. Reopen the app and choose its source again.")); return; }
    enqueue(request);
}
void FlatpakManager::uninstallApp(QVariantMap app) {
    if (sourcesBusy()) { emit inputError(tr("Please wait for software sources to finish updating.")); return; }
    // Re-resolve against our installed list; never trust a path/ref from QML.
    for (const auto &entry : m_installed) {
        auto installed = entry.toMap();
        if (normalizedId(installed.value("id").toString()) == normalizedId(app.value("id").toString())
            && installed.value("installation") == app.value("installation")
            && installed.value("installedBranch") == app.value("installedBranch")
            && installed.value("installedArch") == app.value("installedArch")) {
            enqueue({{"action", "uninstall"}, {"id", installed.value("id")}, {"name", installed.value("name")},
                {"installation", installed.value("installation")}, {"installedBranch", installed.value("installedBranch")},
                {"installedArch", installed.value("installedArch")}});
            return;
        }
    }
    emit inputError(tr("That app is no longer installed. The list has been refreshed.")); refreshInstalled();
}
void FlatpakManager::drainApplicationLinks() {
    if (sourcesBusy() || m_catalogProcess.state() != QProcess::NotRunning || m_loading) return;
    const auto pending = m_pendingApplicationLinks;
    m_pendingApplicationLinks.clear();
    for (const auto &source : pending) openSource(source);
}
void FlatpakManager::openSource(QString source) {
    source = source.trimmed();
    if (source.isEmpty() || source.size() > 8192) { emit inputError(tr("Invalid Flatpak link or filename.")); return; }
    // Desktop file/URL activation can arrive during first-run provisioning.
    // Retain it until sources are ready instead of losing the launch request.
    if (sourcesBusy()) {
        if (m_pendingInputs.size() < 16) m_pendingInputs.append(source);
        else emit inputError(tr("Too many files are waiting for software sources to finish updating."));
        return;
    }
    const QUrl url(source);
    if (url.scheme() == "flatpak" || url.scheme() == "appstream") {
        // Do not use QUrl::host(): host names are lowercased, but app IDs are not.
        auto id = QUrl::fromPercentEncoding(source.mid(source.indexOf(':') + 1).toUtf8());
        if (id.startsWith("//")) id.remove(0, 2);
        if (id.endsWith('/')) id.chop(1);
        static const QRegularExpression validId("^[A-Za-z0-9_][A-Za-z0-9_.-]*\\.[A-Za-z0-9_.-]+$");
        if (!validId.match(id).hasMatch() || url.hasQuery() || url.hasFragment()) {
            emit inputError(tr("Use an appstream: or flatpak: link containing an application ID only.")); return;
        }
        if (m_catalogProcess.state() != QProcess::NotRunning || m_loading) {
            if (m_pendingApplicationLinks.size() < 16) m_pendingApplicationLinks.append(source);
            else emit inputError(tr("Too many applications are waiting for the catalog to load."));
            return;
        }
        const auto normalized = normalizedId(id);
        for (const auto &entry : m_installed) {
            const auto app = entry.toMap();
            if (app.value("id").toString() == id || normalizedId(app.value("id").toString()) == normalized) {
                emit appOpened(app); return;
            }
        }
        if (m_metadata.contains(normalized)) { emit appOpened(metadata(normalized)); return; }
        emit inputError(tr("The application %1 was not found in the available sources or installed apps.").arg(id)); return;
    }
    if (!url.scheme().isEmpty() && !url.isLocalFile() && url.scheme() != "https" && url.scheme() != "flatpak+https") {
        emit inputError(tr("Use an appstream: app link, a local Flatpak file, or an HTTPS Flatpak link.")); return;
    }
    if (url.isLocalFile() || url.scheme().isEmpty()) {
        const QFileInfo file(url.isLocalFile() ? url.toLocalFile() : source);
        if (!file.isFile() || !QStringList{"flatpak", "flatpakref", "flatpakrepo"}.contains(file.suffix().toLower())) {
            emit inputError(tr("Choose a readable .flatpak, .flatpakref or .flatpakrepo file.")); return;
        }
        source = QUrl::fromLocalFile(file.absoluteFilePath()).toString();
    }
    enqueue({{"action", "source"}, {"source", source}, {"name", QUrl(source).fileName()},
        {"installation", "user"}, {"prepareOnly", true}, {"hidden", true}});
}
void FlatpakManager::startNext() {
    if (m_stopping) return;
    for (int i = 0; i < m_jobs.size(); ++i) {
        const auto job = m_jobs[i].toMap();
        if (!active(job)) continue;
        const bool removing = job.value("action") == "uninstall";
        if (removing && !job.value("removalConfirmed").toBool()) continue;
        auto &worker = removing ? m_removalWorker : m_installWorker;
        if (worker.current >= 0 || worker.process.state() != QProcess::NotRunning) continue;
        worker.current = i; worker.buffer.clear(); worker.diagnostics.clear(); worker.resultReceived = false;
        if (!removing) {
            m_downloadRate = DownloadRate{};
            m_downloadClock.start(); m_downloadRateTimer.start();
        }
        patchJob(i, {{"queued", false}, {"status", removing ? tr("Uninstalling…") : tr("Preparing…")},
            {"downloadSpeed", DownloadRate::display(0)}});
        worker.process.start(QCoreApplication::applicationFilePath(), {"--transaction-worker",
            QString::fromUtf8(QJsonDocument::fromVariant(m_requests[i]).toJson(QJsonDocument::Compact))});
    }
    emit jobsChanged();
    if (m_sourcesRefreshPending && !busy()) { m_sourcesRefreshPending = false; refreshSources(true); }
}
void FlatpakManager::receive(WorkerState &worker) {
    worker.buffer += worker.process.readAllStandardOutput();
    while (worker.buffer.contains('\n')) {
        const auto end = worker.buffer.indexOf('\n');
        const auto line = worker.buffer.left(end); worker.buffer.remove(0, end + 1);
        const auto doc = QJsonDocument::fromJson(line);
        if (doc.isObject()) handleMessage(worker, doc.object());
    }
}
QVariantMap FlatpakManager::downloadRateValues(const QVariantMap &job) {
    const auto rate = m_downloadRate.sample(m_downloadClock.elapsed(), job.value("receivedBytes").toULongLong(),
        job.value("phase") == "download" && !job.value("downloadComplete").toBool());
    return {{"downloadSpeed", DownloadRate::display(rate)}};
}
void FlatpakManager::handleMessage(WorkerState &worker, const QJsonObject &message) {
    if (worker.current < 0) return;
    const auto type = message["type"].toString();
    // Buffered progress/reviews must never resurrect a cancelled job.
    if (m_jobs[worker.current].toMap().value("cancelling").toBool() && type != "result" && type != "updated") return;
    if (type == "updated") {
        m_updateHistory.reload();
        if (!message["historySaved"].toBool()) emit inputError(tr("The app updated, but its last-update date could not be saved."));
        refreshInstalled();
    } else if (type == "review") {
        QVariantMap values{{"status", tr("Waiting for confirmation")}};
        const auto operations = message["operations"].toArray().toVariantList();
        // Source-trust prompts can have no operation list. Preserve any plan
        // already received so confirming a prompt cannot discard progress.
        if (!operations.isEmpty()) values["operations"] = operations;
        patchJob(worker.current, values);
        queueReview(message.toVariantMap(), worker.current);
    } else if (type == "identity") {
        const auto id = message["appId"].toString();
        if (!id.isEmpty()) {
            auto app = metadata(id); patchJob(worker.current, {{"id", id}, {"name", app.value("name")}});
        }
    } else if (type == "plan") {
        const auto id = message["appId"].toString();
        const auto operations = message["operations"].toArray().toVariantList();
        auto values = transactionStages(operations, "preparing");
        values["operations"] = operations;
        patchJob(worker.current, values);
        const auto request = m_requests[worker.current].toMap();
        if (request.value("prepareOnly").toBool() && !id.isEmpty()) {
            m_sources[id] = request;
            for (const auto &entry : message["operations"].toArray()) {
                const auto op = entry.toObject();
                if (op["ref"].toString().startsWith("app/")) {
                    m_sources[id]["flatpakRef"] = op["ref"].toString();
                    m_sources[id]["remote"] = op["remote"].toString();
                }
            }
            emit appOpened(metadata(id));
        }
        if (request.value("action") != "uninstall" && id == normalizedId(m_sizeApp.value("id").toString())) {
            // External bundles can carry metadata absent from a repository.
            // Their already-resolved plan is authoritative for the open page.
            m_installSizes = {{id, message.toVariantMap()}}; emit installSizesChanged();
        }
    } else if (type == "operation") {
        auto job = m_jobs[worker.current].toMap();
        auto operations = job.value("operations").toList();
        auto status = message["status"].toString();
        for (auto &entry : operations) {
            auto op = entry.toMap();
            if (op.value("ref").toString() == message["ref"].toString()) {
                op["status"] = message["status"].toString(); op["progress"] = message["progress"].toDouble();
                op["phase"] = message["phase"].toString();
                op["downloadProgress"] = qMax(op.value("downloadProgress").toDouble(), message["downloadProgress"].toDouble());
                op["receivedBytes"] = qMax(op.value("receivedBytes").toDouble(), message["receivedBytes"].toDouble());
                op["estimating"] = message["estimating"].toBool();
                entry = op;
                // Dependency identity is useful, but the app name is already
                // the page/card heading. The worker supplies clean status text.
                if (job.value("action") != "uninstall" && op.value("dependency").toBool())
                    status = tr("Dependency: %1\n%2").arg(op.value("name").toString(), status);
            }
        }
        auto values = transactionStages(operations, message["phase"].toString());
        if (&worker == &m_installWorker) values.insert(downloadRateValues(values));
        values["operations"] = operations;
        // Metadata/transfer estimates can change mid-pull; never move the
        // overall bar backwards. Only a successful result may reach 100%.
        values["progress"] = qMax(job.value("progress").toDouble(), values.value("progress").toDouble());
        // Operation completion can precede data cleanup and the transaction
        // result. Never present that sub-step as a completed app removal.
        values["status"] = job.value("action") == "uninstall" ? tr("Uninstalling…") : status;
        values["currentRef"] = message["ref"].toString();
        patchJob(worker.current, values);
    } else if (type == "status") {
        patchJob(worker.current, {{"status", message["status"].toString()}});
    } else if (type == "result") {
        worker.cancelTimeout.stop();
        if (&worker == &m_installWorker) m_downloadRateTimer.stop();
        worker.resultReceived = true; worker.process.closeWriteChannel();
        const bool ok = message["success"].toBool();
        const bool cancelled = message["cancelled"].toBool() || m_jobs[worker.current].toMap().value("cancelling").toBool();
        const bool preparation = m_requests[worker.current].toMap().value("prepareOnly").toBool();
        if (ok && preparation) m_sourcesRefreshPending = true;
        // A success racing with Cancel still actually installed the app.
        // Record that fact, but do not restore its cancelled Downloads entry.
        if (ok && !preparation) {
            const auto job = m_jobs[worker.current].toMap();
            for (const auto &entry : job.value("operations").toList()) {
                const auto op = entry.toMap();
                const auto ref = op.value("ref").toString();
                if (!ref.startsWith("app/")) continue;
                if (job.value("action") == "uninstall") {
                    m_installHistory.removed(job.value("installation").toString(), ref);
                    m_updateHistory.removed(job.value("installation").toString(), ref);
                }
                else if (op.value("action") == "install" || op.value("action") == "install-bundle")
                    m_installHistory.installed("user", ref);
            }
        }
        // Source setup and file inspection never belong in the app queue,
        // including failures. Report errors through the input dialog instead;
        // installRequest creates a visible job only when installation starts.
        if (preparation && !ok && !cancelled) emit inputError(message["error"].toString());
        const bool removing = m_jobs[worker.current].toMap().value("action") == "uninstall";
        if (ok && m_jobs[worker.current].toMap().value("action") == "update") {
            const auto key = m_requests[worker.current].toMap().value("key");
            for (qsizetype i = m_updates.size(); i-- > 0;)
                if (m_updates[i].toMap().value("key") == key) m_updates.removeAt(i);
            emit updatesChanged();
        }
        if (ok && removing) {
            const auto removed = m_jobs[worker.current].toMap();
            const auto removedId = normalizedId(removed.value("id").toString());
            const auto removedRef = "app/" + removedId + "/" + removed.value("installedArch").toString()
                                    + "/" + removed.value("installedBranch").toString();
            // Remove this deployment's finished download cards, not queue IDs
            // or another installation's history. Failed/declined removals never
            // reach this block. The job-result signal below publishes the change.
            for (auto &entry : m_jobs) {
                auto history = entry.toMap();
                if (active(history) || history.value("action") == "uninstall"
                    || normalizedId(history.value("id").toString()) != removedId
                    || history.value("installation") != removed.value("installation")) continue;
                QString historyRef = history.value("flatpakRef").toString();
                if (historyRef.isEmpty()) {
                    for (const auto &operation : history.value("operations").toList()) {
                        const auto ref = operation.toMap().value("ref").toString();
                        if (ref.startsWith("app/" + removedId + "/")) { historyRef = ref; break; }
                    }
                }
                if (!historyRef.isEmpty() && historyRef != removedRef) continue;
                history["hidden"] = true;
                entry = history;
            }
            ++m_installedRevision;
            // Publish the authoritative removal before declaring the job done.
            // Otherwise the UI briefly offers Open/Uninstall from the old list.
            for (qsizetype i = m_installed.size(); i-- > 0;) {
                const auto app = m_installed[i].toMap();
                if (normalizedId(app.value("id").toString()) == normalizedId(removed.value("id").toString())
                    && app.value("installation") == removed.value("installation")
                    && app.value("installedBranch") == removed.value("installedBranch")
                    && app.value("installedArch") == removed.value("installedArch"))
                    m_installed.removeAt(i);
            }
            emit installedChanged();
        }
        patchJob(worker.current, {{"active", false}, {"queued", false}, {"failed", !ok && !cancelled}, {"cancelled", cancelled},
            {"progress", ok ? 1 : m_jobs[worker.current].toMap().value("progress")},
            {"status", ok ? (removing ? QString() : tr("Complete")) : cancelled ? tr("Cancelled") : tr("Failed")}, {"error", message["error"].toString()}});
        clearReviewsForJob(worker.current);
    }
}
void FlatpakManager::answerReview(int token, bool accept) {
    if (m_review.isEmpty() || m_review.value("token").toInt() != token) return;
    const auto review = m_review;
    const int index = review.value("jobIndex").toInt();
    clearReviewsForJob(index);
    if (review.value("localRemoval").toBool()) {
        if (accept) {
            auto request = m_requests[index].toMap();
            request["removalConfirmed"] = true;
            m_requests[index] = request;
            patchJob(index, {{"removalConfirmed", true}, {"status", tr("Pending…")}});
            startNext();
        } else {
            patchJob(index, {{"active", false}, {"queued", false}, {"cancelled", true}, {"status", QString()}});
        }
        return;
    }
    auto worker = workerForJob(index);
    if (!worker) return;
    QVariantMap values{{"status", accept ? tr("Working…") : tr("Cancelling…")}};
    if (review.value("removing").toBool()) values["removalConfirmed"] = accept;
    patchJob(index, values);
    worker->process.write(QJsonDocument(QJsonObject{{"token", review.value("workerToken").toInt()}, {"accept", accept}})
        .toJson(QJsonDocument::Compact) + '\n');
}
void FlatpakManager::cancelJob(int index) {
    if (index < 0 || index >= m_jobs.size() || !active(m_jobs[index].toMap())) return;
    if (auto worker = workerForJob(index)) {
        if (worker == &m_installWorker) m_downloadRateTimer.stop();
        worker->cancelTimeout.start(250);
        worker->process.write("{\"cancel\":true}\n");
        worker->process.closeWriteChannel();
        patchJob(index, {{"active", false}, {"queued", false}, {"cancelled", true},
            {"status", QString()}, {"cancelling", true}});
    } else {
        patchJob(index, {{"active", false}, {"queued", false}, {"cancelled", true}, {"status", QString()}});
    }
    clearReviewsForJob(index);
}
void FlatpakManager::cancelAll() {
    cancelUpdateCheck();
    m_pendingInputs.clear();
    for (int i = 0; i < m_jobs.size(); ++i) cancelJob(i);
    if (sourcesBusy()) { m_sourceProcess.write("{\"cancel\":true}\n"); m_sourceProcess.closeWriteChannel(); }
}

void FlatpakManager::initializeSources() { runSourceOperation({{"operation", "initialize"}}); }
void FlatpakManager::refreshSources(bool catalogs) { runSourceOperation({{"operation", catalogs ? "refresh" : "list"}}); }
void FlatpakManager::addDefaultSources() { runSourceOperation({{"operation", "defaults"}}); }
void FlatpakManager::runSourceOperation(QVariantMap request) {
    if (m_stopping || busy()) return;
    m_sourceListing = request.value("operation") == "list";
    if (!m_sourceListing && m_updatesState == "ready") {
        m_updates.clear(); m_updatesState = "idle"; m_updatesSkipped.clear();
        m_updatesError.clear(); emit updatesChanged();
    }
    if (!m_sourceListing) {
        m_sourcesError.clear();
        m_catalogLoadsFailed = false;
        emit catalogChanged();
    }
    m_sourceBuffer.clear(); m_sourceResult = false;
    request["action"] = "repositories";
    m_sourceProcess.start(QCoreApplication::applicationFilePath(), {"--transaction-worker",
        QString::fromUtf8(QJsonDocument::fromVariant(request).toJson(QJsonDocument::Compact))});
    emit repositoriesChanged(); emit jobsChanged();
}
void FlatpakManager::setSourceEnabled(QVariantMap source, bool enabled) {
    for (const auto &entry : m_repositories) {
        const auto known = entry.toMap();
        if (known.value("id").toString().isEmpty() || known.value("id") != source.value("id")) continue;
        for (const auto &entry : known.value("members").toList()) {
            const auto member = entry.toMap();
            if (member.value("scope") != "user") continue;
            runSourceOperation({{"operation", "enable"}, {"remote", member.value("name")},
                {"url", member.value("url")}, {"sourceKey", member.value("sourceKey")}, {"enabled", enabled}});
            return;
        }
    }
}
void FlatpakManager::removeSource(QVariantMap source) {
    for (const auto &entry : m_repositories) {
        const auto known = entry.toMap();
        if (!known.value("id").toString().isEmpty() && known.value("id") == source.value("id")) {
            runSourceOperation({{"operation", "remove"}, {"members", known.value("members")}});
            return;
        }
    }
}
void FlatpakManager::reloadCatalog() {
    if (m_stopping) return;
    if (m_catalogProcess.state() != QProcess::NotRunning) { m_catalogAgain = true; return; }
    m_catalogProcess.start(QCoreApplication::applicationFilePath(), {"--catalog"});
}
void FlatpakManager::refreshInstalled() {
    if (m_installedProcess.state() != QProcess::NotRunning) { m_installedRefreshPending = true; return; }
    m_loading = true; m_installedError.clear(); emit installedChanged();
    m_installedTimeout.start(15000);
    m_installedReadRevision = m_installedRevision;
    m_installedProcess.start("flatpak", {"list", "--app",
        "--columns=application:f,name:f,size,origin:f,installation:f,branch:f,arch:f,description:f,version:f"});
}
void FlatpakManager::refreshCaches() {
    if (m_stopping) return;
    if (m_refreshingCaches) { m_cacheRefreshPending = true; return; }
    m_refreshingCaches = true;
    // Finish the user export's icon cache before refreshing the application
    // database. Never rebuild root-owned system icon trees or restart Plasma.
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, nullptr);
    if (user) {
        g_autofree char *path = g_file_get_path(flatpak_installation_get_path(user));
        const auto icons = QDir(QString::fromUtf8(path)).filePath("exports/share/icons/hicolor");
        const QFileInfo directory(icons);
        if (path && directory.isDir() && directory.ownerId() == geteuid() && directory.isWritable())
            m_cacheCommands.append(QStringList{"gtk-update-icon-cache", "--force", "--ignore-theme-index", icons});
    }
    m_cacheCommands.append(QStringList{"kbuildsycoca6", "--noincremental"});
    refreshNextCache();
}
void FlatpakManager::refreshNextCache() {
    m_cacheTimeout.stop();
    if (m_stopping) return;
    if (m_cacheCommands.isEmpty()) {
        // Same session-bus notification as KIconLoader::emitChange(Desktop).
        // Sycoca only refreshes application entries, not the running shell's
        // cached missing icons. All KDE icon loaders must invalidate those.
        auto message = QDBusMessage::createSignal(QStringLiteral("/KIconLoader"),
            QStringLiteral("org.kde.KIconLoader"), QStringLiteral("iconChanged"));
        message << 0; // KIconLoader::Desktop
        if (!QDBusConnection::sessionBus().send(message)) {
            qWarning("Could not notify Plasma to refresh application icons");
            refreshThemeIcons(0);
        }
        m_refreshingCaches = false;
        if (m_cacheRefreshPending) {
            m_cacheRefreshPending = false;
            refreshCaches();
        }
        refreshInstalled();
        QTimer::singleShot(0, this, &FlatpakManager::startNext);
        return;
    }
    auto command = m_cacheCommands.takeFirst();
    const auto program = command.takeFirst();
    m_cacheTimeout.start(15000);
    m_cache.start(program, command);
}
void FlatpakManager::refreshThemeIcons(int) {
    // Let KDE's own icon loaders handle this signal before asking QML to load
    // its images again. Changing QIcon::themeName would bypass Plasma's icon
    // engine and can break theme-aware coloring; keep the selected theme.
    QTimer::singleShot(0, this, [this] {
        if (m_stopping) return;
        QPixmapCache::clear();
        ++m_iconRevision;
        emit installedChanged();
    });
}
void FlatpakManager::launchApp(QVariantMap app) {
    for (const auto &entry : m_installed) {
        const auto installed = entry.toMap();
        if (normalizedId(installed.value("id").toString()) != normalizedId(app.value("id").toString())) continue;
        if (app.contains("installation") && (installed.value("installation") != app.value("installation")
            || installed.value("installedBranch") != app.value("installedBranch")
            || installed.value("installedArch") != app.value("installedArch"))) continue;
        const QString scope = installed.value("installation").toString();
        QStringList args{"run", scope == "user" ? "--user" : scope == "system" ? "--system" : "--installation=" + scope,
            "--branch=" + installed.value("installedBranch").toString(), "--arch=" + installed.value("installedArch").toString(),
            normalizedId(installed.value("id").toString())};
        if (!QProcess::startDetached("flatpak", args)) emit inputError(tr("Could not start this app."));
        return;
    }
}
