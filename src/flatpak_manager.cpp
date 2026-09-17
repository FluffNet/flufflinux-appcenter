#include <flatpak.h>
#include "flatpak_manager.h"
#include "transaction_progress.h"
#include "flatpak_sizes.h"
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
    for (const auto &entry : catalog) {
        const auto app = entry.toMap();
        m_metadata.insert(normalizedId(app.value("id").toString()), app);
    }
    connect(&m_worker, &QProcess::readyReadStandardOutput, this, &FlatpakManager::receive);
    connect(&m_worker, &QProcess::readyReadStandardError, this, [this] {
        m_diagnostics += m_worker.readAllStandardError();
        m_diagnostics = m_diagnostics.right(8192);
    });
    connect(&m_worker, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            patchJob(m_current, {{"active", false}, {"failed", true}, {"status", tr("Could not start Flatpak worker")}});
            m_current = -1;
            QTimer::singleShot(0, this, &FlatpakManager::startNext);
        }
    });
    connect(&m_worker, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this](int, QProcess::ExitStatus) {
            receive();
            if (!m_resultReceived) patchJob(m_current, {{"active", false}, {"failed", true},
                {"status", tr("The Flatpak worker stopped unexpectedly")}, {"error", QString::fromUtf8(m_diagnostics)}});
            m_review.clear(); emit reviewChanged();
            const bool preparation = m_current >= 0 && m_requests[m_current].toMap().value("prepareOnly").toBool();
            m_current = -1;
            if (preparation) QTimer::singleShot(0, this, &FlatpakManager::startNext);
            else {
                // Dependencies may now be installed (or removed). Never reuse
                // stale totals after another transaction changes the machine.
                if (!m_sizeApp.isEmpty()) requestInstallInfo(m_sizeApp);
                refreshCaches();
            }
        });
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
            if (!m_installedTimeout.isActive()) return;
            m_installedTimeout.stop(); m_loading = false;
            if (code || status != QProcess::NormalExit) {
                m_installedError = tr("Could not read installed Flatpaks: %1")
                    .arg(QString::fromUtf8(m_installedProcess.readAllStandardError()));
            } else {
                QVariantList apps;
                m_installHistory.reload();
                for (const auto &line : QString::fromUtf8(m_installedProcess.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts)) {
                    const auto c = line.split('\t');
                    if (c.size() != 9) { m_installedError = tr("Flatpak returned an unexpected installed-app list."); break; }
                    auto app = metadata(c[0].trimmed());
                    if (!m_metadata.contains(c[0].trimmed())) {
                        app["name"] = c[1].trimmed(); app["summary"] = c[7].trimmed(); app["description"] = c[7].trimmed();
                    }
                    app["installedSize"] = c[2].trimmed(); app["installedOrigin"] = c[3].trimmed();
                    app["installation"] = c[4].trimmed(); app["installedBranch"] = c[5].trimmed();
                    app["installedArch"] = c[6].trimmed(); app["installedVersion"] = c[8].trimmed();
                    const auto ref = "app/" + c[0].trimmed() + "/" + c[6].trimmed() + "/" + c[5].trimmed();
                    const auto date = m_installHistory.date(c[4].trimmed(), ref);
                    if (!date.isEmpty()) {
                        app["installedAt"] = date;
                        app["installedDate"] = InstallHistory::displayDate(date);
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
FlatpakManager::~FlatpakManager() {
    m_stopping = true;
    cancelAll();
    m_worker.closeWriteChannel();
    // Normal UI close is prevented while busy. This only covers forced shutdown.
    if (!m_worker.waitForFinished(3000) && m_worker.state() != QProcess::NotRunning) {
        m_worker.terminate(); m_worker.waitForFinished(1000);
    }
    for (auto process : {&m_installedProcess, &m_cache}) {
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
QVariantMap FlatpakManager::installRequest(const QVariantMap &app) const {
    const auto id = normalizedId(app.value("id").toString());
    if (m_sources.contains(id)) {
        auto request = m_sources.value(id);
        request["prepareOnly"] = false; request["hidden"] = false;
        request["id"] = id; request["name"] = app.value("name");
        return request;
    }
    const auto catalogApp = m_metadata.value(id, app);
    return {{"action", "install"}, {"id", id}, {"name", app.value("name")}, {"installation", "user"},
        {"flatpakRef", catalogApp.value("flatpakRef")}, {"remote", catalogApp.value("remote")}};
}
void FlatpakManager::requestInstallInfo(QVariantMap app) {
    if (m_stopping) return;
    const auto id = normalizedId(app.value("id").toString());
    if (id.isEmpty()) return;
    m_sizeApp = app;
    auto request = installRequest(app);
    // Only the currently displayed values are retained. Every app opening
    // reads current local metadata; there is no size cache or background job.
    m_installSizes = {{id, localFlatpakSizes(request)}};
    emit installSizesChanged();
}
bool FlatpakManager::busy() const {
    for (const auto &job : m_jobs) if (active(job.toMap())) return true;
    return m_worker.state() != QProcess::NotRunning || m_refreshingCaches;
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
    request["id"] = id;
    for (const auto &entry : m_jobs) {
        const auto job = entry.toMap();
        if (active(job) && ((!id.isEmpty() && job.value("id") == id)
            || (id.isEmpty() && job.value("source") == request.value("source")))) return;
    }
    request["active"] = true; request["failed"] = false; request["progress"] = 0;
    request["status"] = tr("Queued"); request["operations"] = QVariantList{};
    request["index"] = m_jobs.size();
    m_requests.append(request); m_jobs.append(request); emit jobsChanged(); startNext();
}
void FlatpakManager::installApp(QVariantMap app) {
    const auto id = normalizedId(app.value("id").toString());
    if (id.isEmpty()) return;
    for (const auto &entry : m_installed) if (normalizedId(entry.toMap().value("id").toString()) == id) return;
    enqueue(installRequest(app));
}
void FlatpakManager::uninstallApp(QVariantMap app) {
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
void FlatpakManager::openSource(QString source) {
    source = source.trimmed();
    if (source.isEmpty() || source.size() > 8192) { emit inputError(tr("Invalid Flatpak link or filename.")); return; }
    const QUrl url(source);
    if (url.scheme() == "flatpak") {
        // flatpak:org.example.App and flatpak://org.example.App preserve ID case.
        const auto id = source.mid(source.indexOf(':') + 1).remove(QRegularExpression("^//"));
        emit appOpened(metadata(id)); return;
    }
    if (!url.scheme().isEmpty() && !url.isLocalFile() && url.scheme() != "https" && url.scheme() != "flatpak+https") {
        emit inputError(tr("Use a local .flatpak, .flatpakref or .flatpakrepo file, or an HTTPS Flatpak link.")); return;
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
    if (m_stopping || m_current >= 0 || m_worker.state() != QProcess::NotRunning || m_refreshingCaches) return;
    for (int i = 0; i < m_jobs.size(); ++i) {
        if (!active(m_jobs[i].toMap())) continue;
        m_current = i; m_buffer.clear(); m_diagnostics.clear(); m_resultReceived = false;
        patchJob(i, {{"status", tr("Preparing…")}});
        m_worker.start(QCoreApplication::applicationFilePath(), {"--transaction-worker",
            QString::fromUtf8(QJsonDocument::fromVariant(m_requests[i]).toJson(QJsonDocument::Compact))});
        return;
    }
    emit jobsChanged();
}
void FlatpakManager::receive() {
    m_buffer += m_worker.readAllStandardOutput();
    while (m_buffer.contains('\n')) {
        const auto end = m_buffer.indexOf('\n');
        const auto line = m_buffer.left(end); m_buffer.remove(0, end + 1);
        const auto doc = QJsonDocument::fromJson(line);
        if (doc.isObject()) handleMessage(doc.object());
    }
}
void FlatpakManager::handleMessage(const QJsonObject &message) {
    if (m_current < 0) return;
    const auto type = message["type"].toString();
    if (type == "review") {
        m_review = message.toVariantMap(); m_review["jobIndex"] = m_current;
        patchJob(m_current, {{"status", tr("Waiting for confirmation")}, {"operations", m_review.value("operations")}});
        emit reviewChanged();
    } else if (type == "identity") {
        const auto id = message["appId"].toString();
        if (!id.isEmpty()) {
            auto app = metadata(id); patchJob(m_current, {{"id", id}, {"name", app.value("name")}});
        }
    } else if (type == "plan") {
        const auto id = message["appId"].toString();
        const auto operations = message["operations"].toArray().toVariantList();
        auto values = transactionStages(operations, "preparing");
        values["operations"] = operations;
        patchJob(m_current, values);
        const auto request = m_requests[m_current].toMap();
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
        auto job = m_jobs[m_current].toMap();
        auto operations = job.value("operations").toList();
        auto status = message["status"].toString();
        double weighted = 0, weight = 0;
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
            const double size = qMax(1.0, op.value("downloadBytes").toDouble());
            weighted += size * op.value("progress").toDouble(); weight += size;
        }
        auto values = transactionStages(operations, message["phase"].toString());
        values["operations"] = operations;
        values["progress"] = weight > 0 ? qMin(0.99, weighted / weight) : 0;
        values["status"] = status;
        values["currentRef"] = message["ref"].toString();
        patchJob(m_current, values);
    } else if (type == "status") {
        patchJob(m_current, {{"status", message["status"].toString()}});
    } else if (type == "result") {
        m_resultReceived = true; m_worker.closeWriteChannel();
        const bool ok = message["success"].toBool(), cancelled = message["cancelled"].toBool();
        const bool preparation = m_requests[m_current].toMap().value("prepareOnly").toBool();
        if (ok && !cancelled && !preparation) {
            const auto job = m_jobs[m_current].toMap();
            for (const auto &entry : job.value("operations").toList()) {
                const auto op = entry.toMap();
                const auto ref = op.value("ref").toString();
                if (!ref.startsWith("app/")) continue;
                if (job.value("action") == "uninstall")
                    m_installHistory.removed(job.value("installation").toString(), ref);
                else if (op.value("action") == "install" || op.value("action") == "install-bundle")
                    m_installHistory.installed("user", ref);
            }
        }
        // A prepared app is not an installed download. Repository additions
        // and failed source imports still get an honest session-history row.
        if (preparation && !cancelled && (!ok || m_jobs[m_current].toMap().value("id").toString().isEmpty()))
            patchJob(m_current, {{"hidden", false}});
        if (preparation && !ok && !cancelled) emit inputError(message["error"].toString());
        patchJob(m_current, {{"active", false}, {"failed", !ok && !cancelled}, {"cancelled", cancelled},
            {"progress", ok ? 1 : m_jobs[m_current].toMap().value("progress")},
            {"status", ok ? tr("Complete") : cancelled ? tr("Cancelled") : tr("Failed")}, {"error", message["error"].toString()}});
        m_review.clear(); emit reviewChanged();
    }
}
void FlatpakManager::answerReview(int token, bool accept) {
    if (m_review.isEmpty() || m_review.value("token").toInt() != token) return;
    m_worker.write(QJsonDocument(QJsonObject{{"token", token}, {"accept", accept}}).toJson(QJsonDocument::Compact) + '\n');
    m_review.clear(); emit reviewChanged();
    patchJob(m_current, {{"status", accept ? tr("Working…") : tr("Cancelling…")}});
}
void FlatpakManager::cancelJob(int index) {
    if (index < 0 || index >= m_jobs.size() || !active(m_jobs[index].toMap())) return;
    if (index == m_current) {
        m_worker.write("{\"cancel\":true}\n");
        patchJob(index, {{"status", tr("Cancelling…")}});
        m_review.clear(); emit reviewChanged();
    } else patchJob(index, {{"active", false}, {"cancelled", true}, {"status", tr("Cancelled")}});
}
void FlatpakManager::cancelAll() { for (int i = 0; i < m_jobs.size(); ++i) cancelJob(i); }
void FlatpakManager::refreshInstalled() {
    if (m_installedProcess.state() != QProcess::NotRunning) return;
    m_loading = true; m_installedError.clear(); emit installedChanged();
    m_installedTimeout.start(15000);
    m_installedProcess.start("flatpak", {"list", "--app",
        "--columns=application:f,name:f,size,origin:f,installation:f,branch:f,arch:f,description:f,version:f"});
}
void FlatpakManager::refreshCaches() {
    if (m_stopping || m_refreshingCaches) return;
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
