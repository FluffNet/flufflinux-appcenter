// libflatpak runs in a separate, unprivileged process. JSON messages keep the
// GUI responsive; only an explicit reply to a review allows a transaction on.
#include <flatpak.h>
#include <QCoreApplication>
#include <QDir>
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
QString bytes(quint64 size) { return QLocale().formattedDataSize(size); }
void send(QJsonObject message) {
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
    QString appId;
    QString problem;
    bool removing = false;
    bool systemRemoval = false;
    bool hadOperationError = false;
    bool declined = false;

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
            if (reply["cancel"].toBool()) g_cancellable_cancel(cancel);
            if (pendingReview && reply["token"].toInt() == pendingReview)
                answer = reply["accept"].toBool() ? 1 : 0;
            replies.notify_all();
        }
        g_cancellable_cancel(cancel);
        replies.notify_all();
    }
    void operationUpdate(const QString &ref, const QString &status, double progress) {
        send({{"type", "operation"}, {"ref", ref}, {"status", status}, {"progress", progress}});
    }
};

QJsonObject operationInfo(FlatpakTransactionOperation *op) {
    const auto ref = str(flatpak_transaction_operation_get_ref(op));
    const auto kind = flatpak_transaction_operation_get_operation_type(op);
    const auto download = flatpak_transaction_operation_get_download_size(op);
    return {{"ref", ref}, {"name", ref.section('/', 1, 1)},
        {"dependency", ref.startsWith("runtime/")},
        {"remote", str(flatpak_transaction_operation_get_remote(op))},
        {"action", str(flatpak_transaction_operation_type_to_string(kind))},
        {"downloadBytes", double(download)}, {"downloadSize", bytes(download)},
        {"installedSize", bytes(flatpak_transaction_operation_get_installed_size(op))},
        {"progress", 0}, {"status", QCoreApplication::translate("Flatpak", "Waiting")}};
}

gboolean ready(FlatpakTransaction *tx, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    auto list = flatpak_transaction_get_operations(tx);
    quint64 total = 0;
    for (auto node = list; node; node = node->next) {
        auto op = FLATPAK_TRANSACTION_OPERATION(node->data);
        if (flatpak_transaction_operation_get_is_skipped(op)) continue;
        w.operations.append(operationInfo(op));
        total += flatpak_transaction_operation_get_download_size(op);
        const auto ref = str(flatpak_transaction_operation_get_ref(op));
        if (w.appId.isEmpty() && ref.startsWith("app/")) w.appId = ref.section('/', 1, 1);
    }
    g_list_free(list);
    // Do not use the transaction to silently update arbitrary apps or runtimes.
    // Only the resolved operations explicitly shown here may proceed.
    send({{"type", "identity"}, {"appId", w.appId}});
    return w.ask({{"kind", "transaction"}, {"operations", w.operations},
        {"appId", w.appId}, {"removing", w.removing}, {"downloadSize", bytes(total)},
        {"title", w.removing ? QCoreApplication::translate("Flatpak", "Uninstall and delete app data?")
                              : QCoreApplication::translate("Flatpak", "Review installation")},
        {"message", w.removing
            ? (w.systemRemoval ? QCoreApplication::translate("Flatpak", "This app was installed system-wide. Removing it affects all users and may require administrator authorization.\n\n") : QString())
                + QCoreApplication::translate("Flatpak", "This removes the app and its saved settings, cache and data in ~/.var/app/%1 for your user, and resets its Flatpak permissions. Files saved elsewhere and other users’ data are not deleted. Close the app first. This cannot be undone.").arg(w.appId)
            : QCoreApplication::translate("Flatpak", "The following app and dependencies will be installed for your user only. Download sizes are estimates; shared dependencies already installed are reused.")}});
}

gboolean addRemote(FlatpakTransaction *, FlatpakTransactionRemoteReason, const char *,
                   const char *name, const char *url, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    if (!safeUrl(QUrl(str(url)))) {
        w.problem = QCoreApplication::translate("Flatpak", "The new repository must use HTTPS without embedded credentials.");
        return false;
    }
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
    w->operationUpdate(str(flatpak_transaction_operation_get_ref(op)), str(status),
                       flatpak_transaction_progress_get_progress(progress) / 100.0);
}
void newOperation(FlatpakTransaction *tx, FlatpakTransactionOperation *op,
                  FlatpakTransactionProgress *progress, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    w.operationUpdate(str(flatpak_transaction_operation_get_ref(op)),
        w.removing ? QCoreApplication::translate("Flatpak", "Uninstalling…")
                   : QCoreApplication::translate("Flatpak", "Downloading / installing…"), 0);
    flatpak_transaction_progress_set_update_frequency(progress, 100);
    g_signal_connect(progress, "changed", G_CALLBACK(progressChanged), tx);
}
void operationDone(FlatpakTransaction *, FlatpakTransactionOperation *op, const char *,
                   FlatpakTransactionResult, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    w.operationUpdate(str(flatpak_transaction_operation_get_ref(op)),
                       QCoreApplication::translate("Flatpak", "Complete"), 1);
}
gboolean operationError(FlatpakTransaction *, FlatpakTransactionOperation *op,
                        const GError *error, FlatpakTransactionErrorDetails, gpointer data) {
    auto &w = *static_cast<Worker *>(data);
    w.hadOperationError = true;
    w.problem = str(error->message);
    w.operationUpdate(str(flatpak_transaction_operation_get_ref(op)), w.problem, 0);
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

bool ensureUserRemote(FlatpakInstallation *installation, const QString &name, Worker &w) {
    g_autoptr(FlatpakRemote) existing = flatpak_installation_get_remote_by_name(installation, name.toUtf8(), w.cancel, nullptr);
    if (existing) return true;
    // A distro commonly ships a system Flathub catalog but no per-user source.
    // Bootstrap the official signed source, never silently install system-wide
    // or copy a different source's name without its signing key and policy.
    if (name != "flathub") {
        w.problem = QCoreApplication::translate("Flatpak", "The source %1 is not configured for your user. Open its .flatpakrepo file first.").arg(name);
        return false;
    }
    g_autoptr(FlatpakInstallation) system = flatpak_installation_new_system(w.cancel, nullptr);
    g_autoptr(FlatpakRemote) systemRemote = system
        ? flatpak_installation_get_remote_by_name(system, "flathub", w.cancel, nullptr) : nullptr;
    if (systemRemote) {
        g_autofree char *url = flatpak_remote_get_url(systemRemote);
        const auto source = str(url);
        if (source != "https://dl.flathub.org/repo/" && source != "https://flathub.org/repo/") {
            w.problem = QCoreApplication::translate("Flatpak", "The system source named flathub is not the official Flathub URL. Open its .flatpakrepo file to configure it for your user.");
            return false;
        }
    }
    const auto contents = readSource("https://dl.flathub.org/repo/flathub.flatpakrepo", w);
    if (contents.isEmpty()) return false;
    g_autoptr(GError) error = nullptr;
    g_autoptr(GKeyFile) key = g_key_file_new();
    if (!g_key_file_load_from_data(key, contents.constData(), contents.size(), G_KEY_FILE_NONE, &error)) {
        w.problem = str(error->message); return false;
    }
    g_autofree char *gpgKey = g_key_file_get_string(key, "Flatpak Repo", "GPGKey", nullptr);
    g_autofree char *url = g_key_file_get_string(key, "Flatpak Repo", "Url", nullptr);
    if (!gpgKey || !*gpgKey || str(url) != "https://dl.flathub.org/repo/") {
        w.problem = "The Flathub source file has an unexpected URL or no signing key."; return false;
    }
    g_autoptr(GBytes) data = g_bytes_new(contents.constData(), contents.size());
    g_autoptr(FlatpakRemote) remote = flatpak_remote_new_from_file("flathub", data, &error);
    if (!remote) { w.problem = str(error->message); return false; }
    flatpak_remote_set_gpg_verify(remote, true);
    if (!addRemote(nullptr, FLATPAK_TRANSACTION_REMOTE_GENERIC_REPO, nullptr, "flathub", url, &w)) return false;
    if (!flatpak_installation_modify_remote(installation, remote, w.cancel, &error)) {
        w.problem = str(error->message); return false;
    }
    return true;
}

bool execute(const QJsonObject &request, Worker &w) {
    g_autoptr(GError) error = nullptr;
    const auto scope = request["installation"].toString("user");
    w.removing = request["action"].toString() == "uninstall";
    w.appId = request["id"].toString();
    if (!w.appId.isEmpty() && !validId(w.appId)) { w.problem = "Invalid Flatpak app ID."; return false; }
    w.systemRemoval = w.removing && scope != "user";
    // New apps, bundles, references and repositories ALWAYS belong to the
    // current user. Only removal of an existing system app uses that scope.
    g_autoptr(FlatpakInstallation) installation = !w.systemRemoval
        ? flatpak_installation_new_user(w.cancel, &error)
        : scope != "system" && !scope.isEmpty()
            ? flatpak_installation_new_system_with_id(scope.toUtf8(), w.cancel, &error)
            : flatpak_installation_new_system(w.cancel, &error);
    if (!installation) { w.problem = str(error->message); return false; }
    if (request["action"].toString() == "install"
        && !ensureUserRemote(installation, request["remote"].toString().isEmpty()
            ? "flathub" : request["remote"].toString(), w)) return false;
    g_autoptr(FlatpakTransaction) tx = flatpak_transaction_new_for_installation(installation, w.cancel, &error);
    if (!tx) { w.problem = str(error->message); return false; }
    g_object_set_data(G_OBJECT(tx), "worker", &w);
    flatpak_transaction_set_no_interaction(tx, false);
    g_signal_connect(tx, "ready-pre-auth", G_CALLBACK(ready), &w);
    g_signal_connect(tx, "add-new-remote", G_CALLBACK(addRemote), &w);
    g_signal_connect(tx, "new-operation", G_CALLBACK(newOperation), &w);
    g_signal_connect(tx, "operation-done", G_CALLBACK(operationDone), &w);
    g_signal_connect(tx, "operation-error", G_CALLBACK(operationError), &w);
    bool added = false;
    if (w.removing) {
        const auto arch = request["installedArch"].toString();
        const auto branch = request["installedBranch"].toString();
        g_autoptr(FlatpakInstalledRef) installed = flatpak_installation_get_installed_ref(installation,
            FLATPAK_REF_KIND_APP, w.appId.toUtf8(), arch.toUtf8(), branch.toUtf8(), w.cancel, &error);
        if (!installed) { w.problem = str(error->message); return false; }
        g_autofree char *ref = flatpak_ref_format_ref(FLATPAK_REF(installed));
        added = flatpak_transaction_add_uninstall(tx, ref, &error);
    } else if (request["action"].toString() == "install") {
        auto ref = request["flatpakRef"].toString();
        auto remote = request["remote"].toString();
        if (ref.isEmpty()) ref = "app/" + w.appId + "/" + str(flatpak_get_default_arch()) + "/stable";
        if (remote.isEmpty()) remote = "flathub";
        g_autoptr(FlatpakRef) parsed = flatpak_ref_parse(ref.toUtf8(), &error);
        if (!parsed || flatpak_ref_get_kind(parsed) != FLATPAK_REF_KIND_APP
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
                {"message", QCoreApplication::translate("Flatpak", "Only open bundles from a source you trust. Flatpak may register the bundle’s software source for your user while preparing it. You will review its dependencies before installation.\n\n%1").arg(path)},
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
            w.appId = str(id);
            send({{"type", "identity"}, {"appId", w.appId}});
            g_autoptr(GBytes) data = g_bytes_new(contents.constData(), contents.size());
            added = flatpak_transaction_add_install_flatpakref(tx, data, &error);
        }
    } else { w.problem = "Unsupported transaction request."; return false; }
    if (!added) { w.problem = error ? str(error->message) : "No app selected."; return false; }
    if (!flatpak_transaction_run(tx, w.cancel, &error) || w.hadOperationError) {
        if (w.problem.isEmpty() && error) w.problem = str(error->message);
        return false;
    }
    if (w.removing) {
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
