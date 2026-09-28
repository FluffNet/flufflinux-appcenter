// libflatpak runs in a separate, unprivileged process. JSON messages keep the
// GUI responsive. Installation starts from the app page; removals and new
// software sources retain their explicit confirmation.
#include <flatpak.h>
#include "transaction_status.h"
#include "download_size.h"
#include "flatpak_sources.h"
#include "source_removal.h"
#include "update_plan.h"
#include "install_history.h"
#include "flatpak_addons.h"
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcess>
#include <QRegularExpression>
#include <QTimer>
#include <QUrl>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <thread>
#include <sys/stat.h>
#include <unistd.h>

namespace {
QString str(const char *s) { return QString::fromUtf8(s ? s : ""); }
QString bytes(quint64 size) { return downloadSizeText(size); }
void send(QJsonObject message) {
    static std::mutex outputMutex;
    std::lock_guard<std::mutex> lock(outputMutex);
    const auto line = QJsonDocument(message).toJson(QJsonDocument::Compact);
    std::cout << line.constData() << std::endl;
}
bool validId(const QString &id) {
    static const QRegularExpression pattern("^[A-Za-z_][A-Za-z0-9_-]*(\\.[A-Za-z0-9_-]+){2,}$");
    return id.size() <= 255 && pattern.match(id).hasMatch();
}
bool safeUrl(const QUrl &url) {
    return url.isValid() && url.scheme() == "https" && !url.host().isEmpty()
        && url.userInfo().isEmpty();
}
struct Worker {
    GCancellable *cancel = g_cancellable_new();
    std::mutex mutex;
    std::condition_variable replies;
    int pendingReview = 0;
    int nextReview = 0;
    int answer = -1;
    QJsonArray operations;
    QJsonArray expectedPlan;
    QString installationScope;
    QString appId;
    QString appName;
    QString problem;
    bool removing = false;
    bool addon = false;
    bool updating = false;
    bool removalConfirmed = false;
    bool systemRemoval = false;
    bool hadOperationError = false;
    bool declined = false;
    bool estimateOnly = false;
    bool prepareOnly = false;
    bool planReady = false;

    ~Worker() { g_object_unref(cancel); }
    bool ask(QJsonObject review) {
        std::unique_lock<std::mutex> lock(mutex);
        if (g_cancellable_is_cancelled(cancel)) return false;
        pendingReview = ++nextReview;
        answer = -1;
        review["type"] = "review";
        review["token"] = pendingReview;
        send(review);
        replies.wait(lock, [&] { return answer >= 0 || g_cancellable_is_cancelled(cancel); });
        pendingReview = 0;
        if (answer == 0) declined = true;
        return answer == 1 && !g_cancellable_is_cancelled(cancel);
    }
    void readReplies() {
        std::string line;
        while (std::getline(std::cin, line)) {
            const auto reply = QJsonDocument::fromJson(QByteArray::fromStdString(line)).object();
            std::lock_guard<std::mutex> lock(mutex);
            if (reply["cancel"].toBool()) {
                g_cancellable_cancel(cancel);
                send({{"type", "cancel-ack"}});
            }
            if (pendingReview && reply["token"].toInt() == pendingReview)
                answer = reply["accept"].toBool() ? 1 : 0;
            replies.notify_all();
        }
        g_cancellable_cancel(cancel);
        replies.notify_all();
    }
    void operationUpdate(const QString &ref, const QString &status, double progress,
                         const QString &phase, double downloadProgress = 0,
                         quint64 received = 0, bool estimating = false) {
        send({{"type", "operation"}, {"ref", ref}, {"status", status}, {"progress", progress},
              {"phase", phase}, {"downloadProgress", downloadProgress},
              {"receivedBytes", double(received)}, {"estimating", estimating}});
    }
};

bool appIsRunning(const QString &id) {
    g_autoptr(GPtrArray) instances = flatpak_instance_get_all();
    for (guint i = 0; i < instances->len; ++i) {
        auto instance = FLATPAK_INSTANCE(g_ptr_array_index(instances, i));
        if (str(flatpak_instance_get_app(instance)) == id && flatpak_instance_is_running(instance))
            return true;
    }
    return false;
}

bool forceStopApp(Worker &w) {
    if (!validId(w.appId)) { w.problem = "Invalid app ID for closing the app."; return false; }
    if (!appIsRunning(w.appId)) return true;
    send({{"type", "status"}, {"status", QCoreApplication::translate("Flatpak", "Closing %1…").arg(w.appName)}});
    QElapsedTimer timeout;
    timeout.start();
    do {
        if (g_cancellable_is_cancelled(w.cancel)) return false;
        // Flatpak targets all of this user's matching sandbox instances and
        // sends SIGKILL to their sandbox child. Never match host process names
        // or kill unrelated apps/other users' sessions.
        QProcess stop;
        stop.start("flatpak", {"kill", w.appId});
        if (!stop.waitForFinished(1500)) { stop.kill(); stop.waitForFinished(1000); }
        // A successful command only means the signal was sent. Verify exit
        // before removing files, including instances still starting at click.
        for (int i = 0; i < 5; ++i) {
            if (!appIsRunning(w.appId)) return true;
            if (g_cancellable_is_cancelled(w.cancel)) return false;
            g_usleep(50 * 1000);
        }
    } while (timeout.elapsed() < 5000);
    w.problem = QCoreApplication::translate("Flatpak", "Could not close %1. Nothing has been removed.").arg(w.appName);
    return false;
}

QJsonObject operationInfo(FlatpakTransactionOperation *op) {
    const auto ref = str(flatpak_transaction_operation_get_ref(op));
    const auto kind = flatpak_transaction_operation_get_operation_type(op);
    const auto download = flatpak_transaction_operation_get_download_size(op);
    return {{"ref", ref}, {"name", ref.section('/', 1, 1)},
        {"dependency", ref.startsWith("runtime/")},
        {"remote", str(flatpak_transaction_operation_get_remote(op))},
        {"commit", str(flatpak_transaction_operation_get_commit(op))},
        {"action", str(flatpak_transaction_operation_type_to_string(kind))},
        {"downloadBytes", double(download)}, {"downloadSize", bytes(download)},
        {"installedSize", bytes(flatpak_transaction_operation_get_installed_size(op))},
        {"progress", 0}, {"phase", "waiting"}, {"downloadProgress", 0},
        {"status", QCoreApplication::translate("Flatpak", "Waiting")}};
}

gboolean ready(FlatpakTransaction *tx, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    auto list = flatpak_transaction_get_operations(tx);
    quint64 total = 0, appSize = 0;
    for (auto node = list; node; node = node->next) {
        auto op = FLATPAK_TRANSACTION_OPERATION(node->data);
        if (flatpak_transaction_operation_get_is_skipped(op)) continue;
        w.operations.append(operationInfo(op));
        total += flatpak_transaction_operation_get_download_size(op);
        const auto ref = str(flatpak_transaction_operation_get_ref(op));
        if (!w.appId.isEmpty() && ref.startsWith("app/") && ref.section('/', 1, 1) != w.appId) {
            w.problem = "The Flatpak source changed to a different application. Open it again to review the app.";
            g_list_free(list);
            return false;
        }
        if (w.appId.isEmpty() && ref.startsWith("app/")) w.appId = ref.section('/', 1, 1);
        if (ref.startsWith("app/")) appSize += flatpak_transaction_operation_get_download_size(op);
    }
    g_list_free(list);
    if (w.updating && !Updates::matchesPlan(w.expectedPlan, w.operations)) {
        w.problem = "The update or its dependencies changed. Check for updates again before continuing.";
        return false;
    }
    send({{"type", "identity"}, {"appId", w.appId}});
    send({{"type", "plan"}, {"appId", w.appId}, {"operations", w.operations},
        {"appBytes", double(appSize)}, {"totalBytes", double(total)},
        {"appSize", bytes(appSize)}, {"totalSize", bytes(total)}, {"state", "ready"}});
    w.planReady = true;
    // Abort before payload download/deployment for passive size lookup or a
    // newly opened file/link. Opening a source is not consent to install it.
    if (w.estimateOnly || w.prepareOnly) return false;
    if (!w.removing) return !g_cancellable_is_cancelled(w.cancel);
    if (!w.removalConfirmed && !w.ask({{"kind", "transaction"}, {"operations", w.operations},
        {"appId", w.appId}, {"removing", w.removing}, {"downloadSize", bytes(total)},
        {"title", QCoreApplication::translate("Flatpak", "Uninstall %1?").arg(w.appName)},
        {"message", (w.addon
            ? QCoreApplication::translate("Flatpak", "Only %1 will be removed. The parent app and its data will be kept.") : w.systemRemoval
            ? QCoreApplication::translate("Flatpak", "If you proceed, %1 will be removed for all users, and its app data for this account will be deleted.")
            : QCoreApplication::translate("Flatpak", "If you proceed, %1 and its app data will be removed.")).arg(w.appName)}})) return false;
    return w.addon || forceStopApp(w);
}

gboolean addRemote(FlatpakTransaction *, FlatpakTransactionRemoteReason, const char *,
                   const char *name, const char *url, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    if (w.updating) {
        w.problem = "This update needs a new software source. Configure it first, then check for updates again.";
        return false;
    }
    if (w.estimateOnly) {
        w.problem = QCoreApplication::translate("Flatpak", "Sizes will be available after the required software source is configured.");
        return false;
    }
    if (!safeUrl(QUrl(str(url)))) {
        w.problem = QCoreApplication::translate("Flatpak", "The new repository must use HTTPS without embedded credentials.");
        return false;
    }
    if (!Sources::officialDefinition(str(url)).isEmpty()) return true;
    return w.ask({{"kind", "remote"}, {"title", QCoreApplication::translate("Flatpak", "Trust a new software source?")},
        {"message", QCoreApplication::translate("Flatpak", "Flatpak needs to add %1 for your user:\n%2\nOnly continue if you trust this source. It can remain in your account even if you cancel installation later.").arg(str(name), str(url))},
        {"operations", QJsonArray{}}});
}
void progressChanged(FlatpakTransactionProgress *progress, gpointer data) {
    auto tx = FLATPAK_TRANSACTION(data);
    auto w = static_cast<Worker *>(g_object_get_data(G_OBJECT(tx), "worker"));
    auto op = flatpak_transaction_get_current_operation(tx);
    if (!op) return;
    g_autofree char *status = flatpak_transaction_progress_get_status(progress);
    const auto raw = str(status);
    const auto percent = flatpak_transaction_progress_get_progress(progress) / 100.0;
    const bool bundle = flatpak_transaction_operation_get_operation_type(op) == FLATPAK_TRANSACTION_OPERATION_INSTALL_BUNDLE;
    const bool downloading = isDownloadStatus(raw);
    // In Flatpak 1.18 a non-download 100% callback marks end of pull,
    // NOT end of deployment. Only operation-done completes installation.
    const auto phase = w->removing ? "uninstall" : bundle ? "install" : downloading ? "download" : percent >= 1 ? "install" : "preparing";
    w->operationUpdate(str(flatpak_transaction_operation_get_ref(op)),
                       QString::fromLatin1(phase) == "preparing" ? QCoreApplication::translate("Flatpak", "Preparing…")
                           : simpleTransactionStatus(raw, flatpak_transaction_progress_get_bytes_transferred(progress), w->removing),
                       qMin(0.99, percent), phase, downloading ? qMin(0.99, percent) : percent >= 1 ? 1 : 0,
                       flatpak_transaction_progress_get_bytes_transferred(progress),
                       flatpak_transaction_progress_get_is_estimating(progress));
}
void newOperation(FlatpakTransaction *tx, FlatpakTransactionOperation *op,
                  FlatpakTransactionProgress *progress, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    const bool bundle = flatpak_transaction_operation_get_operation_type(op) == FLATPAK_TRANSACTION_OPERATION_INSTALL_BUNDLE;
    // Sample once more at operation-done: very fast/cached pulls can finish
    // between throttled changed signals. Keep the final byte count, not zero.
    g_object_set_data_full(G_OBJECT(op), "appcenter-progress", g_object_ref(progress), g_object_unref);
    w.operationUpdate(str(flatpak_transaction_operation_get_ref(op)),
        w.removing ? QCoreApplication::translate("Flatpak", "Uninstalling…")
                   : bundle ? QCoreApplication::translate("Flatpak", "Installing…") : QCoreApplication::translate("Flatpak", "Preparing…"), 0,
        w.removing ? "uninstall" : bundle ? "install" : "preparing");
    flatpak_transaction_progress_set_update_frequency(progress, 100);
    g_signal_connect(progress, "changed", G_CALLBACK(progressChanged), tx);
}
void operationDone(FlatpakTransaction *, FlatpakTransactionOperation *op, const char *,
                   FlatpakTransactionResult result, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    const auto ref = str(flatpak_transaction_operation_get_ref(op));
    if (w.updating && ref.startsWith("app/")
        && flatpak_transaction_operation_get_operation_type(op) == FLATPAK_TRANSACTION_OPERATION_UPDATE
        && !(result & FLATPAK_TRANSACTION_RESULT_NO_CHANGE)) {
        // Persist at deployment completion, even if a later operation fails or
        // the UI closes/cancels. Never misreport an unchanged commit as updated.
        InstallHistory history(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/update-dates.json");
        const bool saved = history.installed(w.installationScope, ref);
        send({{"type", "updated"}, {"ref", ref}, {"historySaved", saved}});
    }
    auto progress = static_cast<FlatpakTransactionProgress *>(g_object_get_data(G_OBJECT(op), "appcenter-progress"));
    w.operationUpdate(str(flatpak_transaction_operation_get_ref(op)),
                       QCoreApplication::translate("Flatpak", "Complete"), 1, "complete", 1,
                       progress ? flatpak_transaction_progress_get_bytes_transferred(progress) : 0);
}
gboolean operationError(FlatpakTransaction *, FlatpakTransactionOperation *op,
                        const GError *error, FlatpakTransactionErrorDetails, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    w.hadOperationError = true;
    w.problem = str(error->message);
    w.operationUpdate(str(flatpak_transaction_operation_get_ref(op)), w.problem, 0, "failed");
    return false; // Never silently mark a partially failed transaction successful.
}

QByteArray readSource(const QString &input, Worker &w) {
    QUrl url(input);
    if (url.scheme() == "flatpak+https") url.setScheme("https");
    constexpr qint64 limit = 2 * 1024 * 1024;
    if (url.isLocalFile() || url.scheme().isEmpty()) {
        QFile file(url.isLocalFile() ? url.toLocalFile() : input);
        if (!file.open(QIODevice::ReadOnly) || file.size() > limit) {
            w.problem = QCoreApplication::translate("Flatpak", "Cannot read the reference file, or it exceeds 2 MiB.");
            return {};
        }
        return file.read(limit + 1);
    }
    if (!safeUrl(url)) {
        w.problem = QCoreApplication::translate("Flatpak", "Only local Flatpak files and HTTPS Flatpak links are supported.");
        return {};
    }
    QNetworkAccessManager network;
    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setTransferTimeout(30000);
    auto reply = network.get(request);
    QEventLoop loop;
    QTimer deadline, cancellation;
    deadline.setSingleShot(true);
    QObject::connect(&deadline, &QTimer::timeout, reply, &QNetworkReply::abort);
    QObject::connect(&cancellation, &QTimer::timeout, reply, [&] {
        if (g_cancellable_is_cancelled(w.cancel)) reply->abort();
    });
    QByteArray contents;
    QObject::connect(reply, &QNetworkReply::readyRead, reply, [&] {
        contents += reply->readAll();
        if (contents.size() > limit) reply->abort();
    });
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    deadline.start(60000);
    cancellation.start(100);
    loop.exec();
    contents += reply->readAll();
    if (reply->error() != QNetworkReply::NoError || contents.size() > limit || !safeUrl(reply->url())) {
        w.problem = QCoreApplication::translate("Flatpak", "Could not retrieve a safe Flatpak reference: %1").arg(reply->errorString());
        return {};
    }
    return contents;
}

bool clearAppData(const QString &id, Worker &w) {
    // IDs come from a parsed Flatpak ref, never a path supplied by the UI.
    // Refuse symlinked ancestors. QDir removes child symlinks themselves, never
    // their targets. Do not enumerate/delete any other app or user's directory.
    if (!validId(id)) { w.problem = "Invalid app ID for data removal."; return false; }
    const QString base = QDir::homePath() + "/.var";
    if (QFileInfo(base).isSymLink() || QFileInfo(base + "/app").isSymLink()) {
        w.problem = "App removed, but data cleanup refused a symlinked ~/.var/app directory.";
        return false;
    }
    const QString path = base + "/app/" + id;
    QFileInfo info(path);
    bool ok = true;
    if (info.isSymLink()) ok = QFile::remove(path);
    else if (info.exists()) ok = info.isDir() ? QDir(path).removeRecursively() : QFile::remove(path);
    if (!ok) { w.problem = "App removed, but some sandbox data could not be deleted: " + path; return false; }
    QProcess permissions;
    permissions.start("flatpak", {"permission-reset", id});
    if (!permissions.waitForFinished(15000)) { permissions.kill(); permissions.waitForFinished(); }
    if (permissions.exitStatus() != QProcess::NormalExit || permissions.exitCode() != 0) {
        w.problem = "App and sandbox data removed, but resetting portal permissions failed: "
                    + QString::fromUtf8(permissions.readAllStandardError());
        return false;
    }
    return true;
}

bool addOfficialRemote(FlatpakInstallation *installation, const QString &name, const QString &definition, Worker &w) {
    const auto contents = readSource(definition, w);
    if (contents.isEmpty()) return false;
    g_autoptr(GError) error = nullptr;
    g_autoptr(GKeyFile) key = g_key_file_new();
    if (!g_key_file_load_from_data(key, contents.constData(), contents.size(), G_KEY_FILE_NONE, &error)) {
        w.problem = str(error->message); return false;
    }
    g_autofree char *gpgKey = g_key_file_get_string(key, "Flatpak Repo", "GPGKey", nullptr);
    g_autofree char *url = g_key_file_get_string(key, "Flatpak Repo", "Url", nullptr);
    if (!gpgKey || !*gpgKey || Sources::officialDefinition(str(url)) != definition) {
        w.problem = "The Flathub source file has an unexpected URL or no signing key."; return false;
    }
    g_autoptr(GBytes) data = g_bytes_new(contents.constData(), contents.size());
    g_autoptr(FlatpakRemote) remote = flatpak_remote_new_from_file(name.toUtf8(), data, &error);
    if (!remote) { w.problem = str(error->message); return false; }
    flatpak_remote_set_gpg_verify(remote, true);
    if (!flatpak_installation_modify_remote(installation, remote, w.cancel, &error)) {
        w.problem = str(error->message); return false;
    }
    return true;
}

bool ensureUserRemote(FlatpakInstallation *installation, const QString &name, const QString &expectedUrl, Worker &w) {
    g_autoptr(FlatpakRemote) existing = flatpak_installation_get_remote_by_name(installation, name.toUtf8(), w.cancel, nullptr);
    if (existing) {
        if (!expectedUrl.isEmpty() && Sources::url(existing) != expectedUrl) {
            w.problem = "This software source has changed. Reopen the app and select its source again."; return false;
        }
        if (flatpak_remote_get_disabled(existing)) { w.problem = "This software source is disabled. Enable it in Settings first."; return false; }
        return true;
    }
    if (w.estimateOnly) {
        w.problem = QCoreApplication::translate("Flatpak", "Sizes will be available after the software source is configured for your user.");
        return false;
    }
    g_autoptr(GPtrArray) systems = flatpak_get_system_installations(w.cancel, nullptr);
    for (guint i = 0; systems && i < systems->len; ++i) {
        auto system = FLATPAK_INSTALLATION(g_ptr_array_index(systems, i));
        g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(system, w.cancel, nullptr);
        for (guint j = 0; remotes && j < remotes->len; ++j) {
            auto source = FLATPAK_REMOTE(g_ptr_array_index(remotes, j));
            if (Sources::userName(installation, system, source) != name || Sources::suppressed(system, source)
                || flatpak_remote_get_disabled(source) || (!expectedUrl.isEmpty() && Sources::url(source) != expectedUrl)) continue;
            return Sources::mirror(installation, system, source, w.cancel, w.problem);
        }
    }
    w.problem = "The source " + name + " is not configured. Add it in Settings → Flatpak Sources.";
    return false;
}

bool removeRepositories(FlatpakInstallation *user, const QJsonArray &members, Worker &w) {
    std::vector<SourceRemoval::Target> targets;
    if (!SourceRemoval::resolve(user, members, false, targets, w.problem)) return false;
    QJsonArray systems;
    for (const auto &target : targets)
        if (target.expected["scope"] != "user") systems.append(target.expected);
    if (!systems.isEmpty()) {
        // Only the root-owned, narrowly scoped helper runs with privileges.
        auto prefix = QDir(QCoreApplication::applicationDirPath());
        const auto helper = prefix.dirName() == "bin" && prefix.cdUp()
            ? prefix.filePath("lib/flufflinux-appcenter/source-helper") : QString("/usr/lib/flufflinux-appcenter/source-helper");
        QString pkexec = "/usr/bin/pkexec";
#ifndef APPCENTER_SOURCE_TEST_CONFIG
        const QFileInfo helperInfo(helper);
        if (!helperInfo.isExecutable() || helperInfo.ownerId() != 0
            || (helperInfo.permissions() & (QFile::WriteGroup | QFile::WriteOther))) {
            w.problem = "The system-source helper is missing or not securely installed. Reinstall App Center.";
            return false;
        }
#endif
#ifdef APPCENTER_SOURCE_TEST_CONFIG
        // Test worker only: a local fake authorizer can prove denied/cancelled
        // authentication leaves user sources untouched, without changing Polkit.
        if (!qEnvironmentVariable("APPCENTER_TEST_PKEXEC").isEmpty()) pkexec = qEnvironmentVariable("APPCENTER_TEST_PKEXEC");
#endif
        QProcess process;
        process.start(pkexec, {"--disable-internal-agent", helper,
            QString::fromUtf8(QJsonDocument(systems).toJson(QJsonDocument::Compact))});
        if (!process.waitForStarted()) { w.problem = "Could not start administrator authentication."; return false; }
        while (!process.waitForFinished(100)) {
            if (g_cancellable_is_cancelled(w.cancel)) { process.terminate(); process.waitForFinished(1000); return false; }
        }
        if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
            if (process.exitStatus() == QProcess::NormalExit && (process.exitCode() == 126 || process.exitCode() == 127)) {
                w.declined = true; return false;
            }
            w.problem = QString::fromUtf8(process.readAllStandardError()).trimmed();
            if (w.problem.isEmpty()) w.problem = "Could not remove the system software source.";
            return false;
        }
    }
    // Do not remove a user copy until system authorization/removal succeeds.
    for (const auto &target : targets) {
        if (target.expected["scope"] != "user") continue;
        g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(user, target.expected["name"].toString().toUtf8(), w.cancel, nullptr);
        if (!SourceRemoval::remove(target, w.cancel, w.problem)) {
            if (!systems.isEmpty()) w.problem += " System copies were removed; the user copy remains.";
            return false;
        }
        if (remote) Sources::rememberRemoval(user, remote);
    }
    QSettings settings(Sources::configPath(), QSettings::IniFormat);
    settings.setValue("Sources/initialized", true);
    return true;
}

bool repositories(FlatpakInstallation *user, const QJsonObject &request, Worker &w) {
    const auto operation = request["operation"].toString();
    int availableCatalogs = 0, failedCatalogs = 0, refreshedCatalogs = 0;
    const auto reportCatalogs = [&] {
        if (!g_cancellable_is_cancelled(w.cancel))
            send({{"type", "catalog-load"}, {"available", availableCatalogs},
                {"failed", failedCatalogs}, {"refreshed", refreshedCatalogs}});
    };
    g_autoptr(GError) error = nullptr;
    if (operation == "initialize" || operation == "refresh") {
        QSettings settings(Sources::configPath(), QSettings::IniFormat);
        const bool first = !settings.value("Sources/initialized", false).toBool();
        const bool empty = Sources::list().isEmpty();
        g_autoptr(GPtrArray) systems = flatpak_get_system_installations(w.cancel, &error);
        if (!systems) { w.problem = error ? str(error->message) : "Could not read system sources."; return false; }
        QStringList problems;
        for (guint i = 0; i < systems->len; ++i) {
            auto system = FLATPAK_INSTALLATION(g_ptr_array_index(systems, i));
            g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(system, w.cancel, nullptr);
            for (guint j = 0; remotes && j < remotes->len; ++j) {
                auto remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, j));
                if (flatpak_remote_get_remote_type(remote) != FLATPAK_REMOTE_TYPE_STATIC || Sources::suppressed(system, remote)) continue;
                QString problem;
                if (!Sources::mirror(user, system, remote, w.cancel, problem)) {
                    problems.append(problem);
                    if (!flatpak_remote_get_disabled(remote) && !flatpak_remote_get_noenumerate(remote)) ++failedCatalogs;
                }
            }
        }
        if (first && empty && !addOfficialRemote(user, "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo", w)) {
            problems.append(w.problem);
            ++failedCatalogs;
        }
        if (problems.isEmpty()) settings.setValue("Sources/initialized", true);
        else w.problem = problems.join('\n');
    } else if (operation == "defaults") {
        if (!Sources::list().isEmpty()) { w.problem = "Default sources can only be added when no sources are configured."; return false; }
        if (!addOfficialRemote(user, "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo", w)) {
            ++failedCatalogs; reportCatalogs(); return false;
        }
        QSettings settings(Sources::configPath(), QSettings::IniFormat);
        settings.setValue("Sources/initialized", true);
    } else if (operation == "remove") {
        const bool removed = removeRepositories(user, request["members"].toArray(), w);
        send({{"type", "sources"}, {"sources", Sources::group(Sources::list())}});
        return removed;
    } else if (operation == "enable") {
        const auto name = request["remote"].toString();
        g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(user, name.toUtf8(), w.cancel, &error);
        if (!remote) { w.problem = str(error->message); return false; }
        if (Sources::url(remote) != request["url"].toString()
            || Sources::sourceKey(user, remote) != request["sourceKey"].toString()) {
            w.problem = "The source has changed. Refresh Settings before trying again."; return false;
        }
        flatpak_remote_set_disabled(remote, !request["enabled"].toBool());
        if (!flatpak_installation_modify_remote(user, remote, w.cancel, &error)) { w.problem = str(error->message); return false; }
    } else if (operation != "list" && operation != "refresh") {
        w.problem = "Unknown source operation."; return false;
    }
    send({{"type", "sources"}, {"sources", Sources::group(Sources::list())}});
    if (operation == "list" || operation == "remove") return w.problem.isEmpty();
    // Initialize fetches missing catalogs. Refresh (manual or expired app-list
    // cache) updates every enabled catalog, even if a local copy exists.
    // This runs in the child, never on the GUI thread.
    g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(user, w.cancel, nullptr);
    for (guint i = 0; remotes && i < remotes->len; ++i) {
        auto remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
        if (flatpak_remote_get_disabled(remote) || flatpak_remote_get_noenumerate(remote)) continue;
        g_autoptr(GFile) directory = flatpak_remote_get_appstream_dir(remote, nullptr);
        g_autofree char *path = directory ? g_file_get_path(directory) : nullptr;
        const bool cached = path && (QFileInfo::exists(str(path) + "/appstream.xml.gz")
            || QFileInfo::exists(str(path) + "/appstream.xml"));
        if (operation != "refresh" && cached) { ++availableCatalogs; continue; }
        g_clear_error(&error);
        if (!flatpak_installation_update_appstream_sync(user, flatpak_remote_get_name(remote), nullptr, nullptr, w.cancel, &error)) {
            if (!w.problem.isEmpty()) w.problem += '\n';
            w.problem += str(flatpak_remote_get_name(remote)) + ": " + str(error->message);
            if (cached) ++availableCatalogs;
            else ++failedCatalogs;
        } else { ++availableCatalogs; ++refreshedCatalogs; }
    }
    reportCatalogs();
    return w.problem.isEmpty();
}

bool execute(const QJsonObject &request, Worker &w) {
    g_autoptr(GError) error = nullptr;
    const auto scope = request["installation"].toString("user");
    w.removing = request["action"].toString() == "uninstall";
    w.addon = request["addon"].toBool();
    w.updating = request["action"].toString() == "update";
    w.installationScope = scope;
    w.expectedPlan = request["plan"].toArray();
    // The manager can obtain consent before this worker gets its queue slot.
    // Direct worker callers still receive the normal confirmation prompt.
    w.removalConfirmed = w.removing && request["removalConfirmed"].toBool();
    w.estimateOnly = request["estimateOnly"].toBool();
    w.prepareOnly = request["prepareOnly"].toBool();
    if (w.estimateOnly && request["action"].toString() != "install") {
        w.problem = "Passive estimates only support catalog applications."; return false;
    }
    w.appId = request["id"].toString();
    w.appName = request["name"].toString().trimmed();
    if (w.appName.isEmpty()) w.appName = w.appId;
    if (!w.appId.isEmpty() && !validId(w.appId)) { w.problem = "Invalid Flatpak app ID."; return false; }
    w.systemRemoval = w.removing && scope != "user";
    if (w.addon && !AppAddons::validate(request, w.cancel, w.problem)) return false;
    // New apps, bundles, references and repositories ALWAYS belong to the
    // current user. Updates/removals keep an existing app's installation scope.
    // Validated add-ons use their already-installed parent's scope.
    g_autoptr(FlatpakInstallation) installation = !(w.systemRemoval || ((w.updating || w.addon) && scope != "user"))
        ? flatpak_installation_new_user(w.cancel, &error)
        : scope != "system" && !scope.isEmpty()
            ? flatpak_installation_new_system_with_id(scope.toUtf8(), w.cancel, &error)
            : flatpak_installation_new_system(w.cancel, &error);
    if (!installation) { w.problem = str(error->message); return false; }
    if (request["action"].toString() == "repositories") return repositories(installation, request, w);
    if (!w.addon && request["action"].toString() == "install"
        && !ensureUserRemote(installation, request["remote"].toString().isEmpty()
            ? "flathub" : request["remote"].toString(), request["sourceUrl"].toString(), w)) return false;
    g_autoptr(FlatpakTransaction) tx = flatpak_transaction_new_for_installation(installation, w.cancel, &error);
    if (!tx) { w.problem = str(error->message); return false; }
    g_object_set_data(G_OBJECT(tx), "worker", &w);
    flatpak_transaction_set_no_interaction(tx, false);
    if (w.addon) flatpak_transaction_set_disable_related(tx, true);
    // Reuse compatible system runtimes too; new deployments remain per-user.
    if (!w.removing) flatpak_transaction_add_default_dependency_sources(tx);
    g_signal_connect(tx, "ready-pre-auth", G_CALLBACK(ready), &w);
    g_signal_connect(tx, "add-new-remote", G_CALLBACK(addRemote), &w);
    g_signal_connect(tx, "new-operation", G_CALLBACK(newOperation), &w);
    g_signal_connect(tx, "operation-done", G_CALLBACK(operationDone), &w);
    g_signal_connect(tx, "operation-error", G_CALLBACK(operationError), &w);
    bool added = false;
    if (w.updating) {
        const auto ref = request["flatpakRef"].toString(), commit = request["commit"].toString();
        g_autoptr(FlatpakRef) parsed = flatpak_ref_parse(ref.toUtf8(), &error);
        if (!parsed || str(flatpak_ref_get_name(parsed)) != request["id"].toString()
            || !Updates::validCommit(commit) || !Updates::validCommit(request["oldCommit"].toString())
            || w.expectedPlan.isEmpty()) { w.problem = "Invalid update selection. Check for updates again."; return false; }
        g_autoptr(FlatpakInstalledRef) current = flatpak_installation_get_installed_ref(installation,
            flatpak_ref_get_kind(parsed), flatpak_ref_get_name(parsed), flatpak_ref_get_arch(parsed),
            flatpak_ref_get_branch(parsed), w.cancel, &error);
        if (!current) { w.problem = "This app is no longer installed. Check for updates again."; return false; }
        const auto actual = str(flatpak_ref_get_commit(FLATPAK_REF(current)));
        if (str(flatpak_installed_ref_get_origin(current)) != request["remote"].toString()) {
            w.problem = "The installed source changed. Check for updates again."; return false;
        }
        if (actual == commit) return true;
        if (actual != request["oldCommit"].toString()) {
            w.problem = "The installed version changed. Check for updates again."; return false;
        }
        for (const auto &value : w.expectedPlan) {
            const auto op = value.toObject();
            g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(installation,
                op["remote"].toString().toUtf8(), w.cancel, nullptr);
            if (!remote || flatpak_remote_get_disabled(remote) || Sources::url(remote) != op["sourceUrl"].toString()
                || op["sourceKey"].toString().isEmpty() || Sources::sourceKey(installation, remote) != op["sourceKey"].toString()) {
                w.problem = "An update source changed or was disabled. Check for updates again."; return false;
            }
        }
        // Let Flatpak resolve the normal signed update through its system
        // helper. Supplying an explicit commit is a privileged downgrade/
        // arbitrary-revision operation, even when it happens to be the latest.
        // ready-pre-auth still checks every resolved commit against the
        // reviewed plan and aborts before authorization/download/deployment
        // if the source has advanced since the user checked for updates.
        added = flatpak_transaction_add_update(tx, ref.toUtf8(), nullptr, nullptr, &error);
    } else if (w.removing) {
        const auto arch = request["installedArch"].toString();
        const auto branch = request["installedBranch"].toString();
        g_autoptr(FlatpakInstalledRef) installed = flatpak_installation_get_installed_ref(installation,
            w.addon ? FLATPAK_REF_KIND_RUNTIME : FLATPAK_REF_KIND_APP,
            w.appId.toUtf8(), arch.toUtf8(), branch.toUtf8(), w.cancel, &error);
        if (!installed) { w.problem = str(error->message); return false; }
        g_autofree char *ref = flatpak_ref_format_ref(FLATPAK_REF(installed));
        added = flatpak_transaction_add_uninstall(tx, ref, &error);
    } else if (request["action"].toString() == "install") {
        auto ref = request["flatpakRef"].toString();
        auto remote = request["remote"].toString();
        if (ref.isEmpty()) ref = "app/" + w.appId + "/" + str(flatpak_get_default_arch()) + "/stable";
        if (remote.isEmpty()) remote = "flathub";
        g_autoptr(FlatpakRef) parsed = flatpak_ref_parse(ref.toUtf8(), &error);
        if (!parsed || flatpak_ref_get_kind(parsed) != (w.addon ? FLATPAK_REF_KIND_RUNTIME : FLATPAK_REF_KIND_APP)
            || str(flatpak_ref_get_name(parsed)) != w.appId) {
            w.problem = "Catalog has an invalid Flatpak application reference."; return false;
        }
        added = flatpak_transaction_add_install(tx, remote.toUtf8(), ref.toUtf8(), nullptr, &error);
    } else if (request["action"].toString() == "source") {
        const auto input = request["source"].toString();
        const QUrl url(input);
        const auto path = url.isLocalFile() ? url.toLocalFile() : input;
        if ((url.isLocalFile() || url.scheme().isEmpty()) && path.endsWith(".flatpak", Qt::CaseInsensitive)) {
            if (!w.ask({{"kind", "bundle"}, {"title", QCoreApplication::translate("Flatpak", "Open local Flatpak bundle?")},
                {"message", QCoreApplication::translate("Flatpak", "Only open bundles from a source you trust. Flatpak may register the bundle’s software source for your user while preparing it.\n\n%1").arg(path)},
                {"operations", QJsonArray{}}})) return false;
            g_autoptr(GFile) file = g_file_new_for_path(QFile::encodeName(QFileInfo(path).absoluteFilePath()));
            added = flatpak_transaction_add_install_bundle(tx, file, nullptr, &error);
        } else {
            const auto contents = readSource(input, w);
            if (contents.isEmpty()) return false;
            g_autoptr(GKeyFile) key = g_key_file_new();
            if (!g_key_file_load_from_data(key, contents.constData(), contents.size(), G_KEY_FILE_NONE, &error)) {
                w.problem = str(error->message); return false;
            }
            if (g_key_file_has_group(key, "Flatpak Repo")) {
                if (!w.appId.isEmpty()) { w.problem = "The app reference was replaced by a repository file."; return false; }
                g_autofree char *repositoryUrl = g_key_file_get_string(key, "Flatpak Repo", "Url", nullptr);
                if (!safeUrl(QUrl(str(repositoryUrl)))) { w.problem = "Repository URL must use HTTPS."; return false; }
                const QString name = QFileInfo(url.path()).completeBaseName().isEmpty()
                    ? "imported-repository" : QFileInfo(url.path()).completeBaseName();
                if (!QRegularExpression("^[A-Za-z0-9_-]+$").match(name).hasMatch()) {
                    w.problem = "Invalid repository filename."; return false;
                }
                g_autoptr(FlatpakRemote) existing = flatpak_installation_get_remote_by_name(installation, name.toUtf8(), w.cancel, nullptr);
                if (existing) {
                    w.problem = QCoreApplication::translate("Flatpak", "A source named %1 is already configured for your user. Its URL, signing keys and settings have not been changed.").arg(name);
                    return false;
                }
                g_autoptr(GBytes) data = g_bytes_new(contents.constData(), contents.size());
                g_autoptr(FlatpakRemote) remote = flatpak_remote_new_from_file(name.toUtf8(), data, &error);
                if (!remote) { w.problem = str(error->message); return false; }
                g_autofree char *gpgKey = g_key_file_get_string(key, "Flatpak Repo", "GPGKey", nullptr);
                if (!gpgKey || !*gpgKey) { w.problem = "Repositories without a signing key are not supported."; return false; }
                // A newly constructed remote has no persisted verification
                // flag yet. Require its supplied key and explicitly enable
                // verification before committing the configuration.
                flatpak_remote_set_gpg_verify(remote, true);
                const auto official = Sources::officialDefinition(str(repositoryUrl));
                if (!official.isEmpty()) return addOfficialRemote(installation, name, official, w);
                if (!w.ask({{"kind", "remote"}, {"title", "Add software source?"},
                    {"message", name + "\n" + str(repositoryUrl) + "\nThis source will be available for your user only."}, {"operations", QJsonArray{}}})) return false;
                if (!flatpak_installation_modify_remote(installation, remote, w.cancel, &error)) {
                    w.problem = str(error->message); return false;
                }
                return true;
            }
            if (!g_key_file_has_group(key, "Flatpak Ref")) { w.problem = "This is not a Flatpak reference or repository file."; return false; }
            g_autofree char *id = g_key_file_get_string(key, "Flatpak Ref", "Name", nullptr);
            g_autofree char *repoUrl = g_key_file_get_string(key, "Flatpak Ref", "Url", nullptr);
            if (!validId(str(id)) || !safeUrl(QUrl(str(repoUrl)))) { w.problem = "Invalid app ID or insecure repository in reference file."; return false; }
            if (!w.appId.isEmpty() && w.appId != str(id)) { w.problem = "The reference now names a different app. Open it again."; return false; }
            w.appId = str(id);
            send({{"type", "identity"}, {"appId", w.appId}});
            g_autoptr(GBytes) data = g_bytes_new(contents.constData(), contents.size());
            added = flatpak_transaction_add_install_flatpakref(tx, data, &error);
        }
    } else { w.problem = "Unsupported transaction request."; return false; }
    if (!added) { w.problem = error ? str(error->message) : "No app selected."; return false; }
    if (!flatpak_transaction_run(tx, w.cancel, &error) || w.hadOperationError) {
        if ((w.estimateOnly || w.prepareOnly) && w.planReady && !g_cancellable_is_cancelled(w.cancel)) return true;
        if (w.problem.isEmpty() && error) w.problem = str(error->message);
        return false;
    }
    if (w.removing && !w.addon) {
        // Recheck after deployment removal in case the app was relaunched
        // during authorization/removal. Do not let it rewrite deleted data.
        if (!forceStopApp(w)) {
            w.problem = QCoreApplication::translate("Flatpak", "App removed, but it could not be closed to delete its data.");
            return false;
        }
        send({{"type", "status"}, {"status", "Deleting sandbox data and resetting permissions…"}});
        return clearAppData(w.appId, w);
    }
    return true;
}
} // namespace

extern "C" int fluff_transaction_worker(const char *json) {
    if (geteuid() == 0) { send({{"type", "result"}, {"success", false}, {"error", "Run App Center as your desktop user, not root."}}); return 1; }
    // Flatpak expects readable staged/exported files. This change is isolated
    // to the child process, never the GUI/user session.
    umask(022);
    int argc = 1;
    char name[] = "flufflinux-appcenter-worker";
    char *argv[] = {name, nullptr};
    QCoreApplication application(argc, argv);
    QCoreApplication::setApplicationName("flufflinux-appcenter");
    QCoreApplication::setOrganizationName("FluffNet LLC");
    Worker worker;
    std::thread reader([&] { worker.readReplies(); });
    const auto request = QJsonDocument::fromJson(QByteArray(json)).object();
    const bool success = execute(request, worker);
    const bool cancelled = worker.declined || g_cancellable_is_cancelled(worker.cancel)
        || (!success && worker.problem.isEmpty());
    send({{"type", "result"}, {"success", success}, {"cancelled", cancelled}, {"error", worker.problem}});
    // Parent closes stdin after receiving the final result. EOF also cancels
    // an orphaned worker if App Center crashes or the session ends.
    reader.join();
    return success ? 0 : cancelled ? 2 : 1;
}
