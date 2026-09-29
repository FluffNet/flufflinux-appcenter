// Explicit scan. May restore official system Flathub when requested, but never
// deploys an app/runtime transaction or replaces an existing source.
#include <flatpak.h>
#include "update_plan.h"
#include "download_size.h"
#include "flatpak_sources.h"
#include "update_sources.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QProcess>
#include <QDateTime>
#include <iostream>
#include <csignal>
#include <sys/prctl.h>
#include <unistd.h>

namespace {
QString text(const char *s) { return QString::fromUtf8(s ? s : ""); }
void send(const QJsonObject &event) {
    std::cout << QJsonDocument(event).toJson(QJsonDocument::Compact).constData() << std::endl;
}
struct Plan {
    FlatpakInstallation *installation;
    QString ref;
    QJsonArray operations;
    QVariantMap permissions;
    QString error;
    bool ready = false;
};
gboolean resolved(FlatpakTransaction *tx, gpointer data) {
    auto &plan = *static_cast<Plan *>(data);
    auto operations = flatpak_transaction_get_operations(tx);
    for (auto it = operations; it; it = it->next) {
        auto op = FLATPAK_TRANSACTION_OPERATION(it->data);
        if (flatpak_transaction_operation_get_is_skipped(op)) continue;
        const auto ref = text(flatpak_transaction_operation_get_ref(op));
        const auto action = flatpak_transaction_operation_get_operation_type(op);
        if ((ref.startsWith("app/") && ref != plan.ref)
            || action == FLATPAK_TRANSACTION_OPERATION_UNINSTALL) {
            plan.error = "This update changes other apps. Manage this update with Flatpak.";
            break;
        }
        const auto remoteName = text(flatpak_transaction_operation_get_remote(op));
        g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(plan.installation,
            remoteName.toUtf8(), nullptr, nullptr);
        const auto commit = text(flatpak_transaction_operation_get_commit(op));
        if (!remote || flatpak_remote_get_disabled(remote) || !Updates::validCommit(commit)) {
            plan.error = "The update source is missing, disabled, or could not be verified."; break;
        }
        QJsonObject row{{"ref", ref}, {"commit", commit}, {"remote", remoteName},
            {"sourceUrl", Sources::url(remote)}, {"sourceKey", Sources::sourceKey(plan.installation, remote)},
            {"action", text(flatpak_transaction_operation_type_to_string(action))},
            {"downloadBytes", double(flatpak_transaction_operation_get_download_size(op))}};
        plan.operations.append(row);
        if (ref == plan.ref && ref.startsWith("app/"))
            plan.permissions = Updates::permissionChanges(
                Updates::metadata(flatpak_transaction_operation_get_old_metadata(op)),
                Updates::metadata(flatpak_transaction_operation_get_metadata(op)));
    }
    g_list_free(operations);
    plan.ready = plan.error.isEmpty();
    return false; // ready-pre-auth: before authorization or payload/deployment.
}
gboolean rejectRemote(FlatpakTransaction *, FlatpakTransactionRemoteReason,
                       const char *, const char *, const char *, gpointer) { return false; }

QJsonObject scan(const QJsonObject &request) {
    QJsonArray rows, errors, skipped;
    g_autoptr(GError) installationError = nullptr;
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(nullptr, &installationError);
    if (!user && installationError) errors.append("user: " + text(installationError->message));
    g_clear_error(&installationError);
    g_autoptr(GPtrArray) systems = request["userOnly"].toBool() ? nullptr : flatpak_get_system_installations(nullptr, &installationError);
    if (installationError) errors.append("system: " + text(installationError->message));
    QList<FlatpakInstallation *> installations;
    if (user) installations.append(user);
    for (guint i = 0; systems && i < systems->len; ++i)
        installations.append(FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)));
    if (installations.isEmpty()) errors.append("No Flatpak installation could be read.");
    for (auto installation : installations) {
        const auto rawScope = Sources::scope(installation);
        const auto scope = rawScope == "default" ? QString("system") : rawScope;
        send({{"type", "status"}, {"message", "Checking for app updates…"}});
        g_autoptr(GError) error = nullptr;
        g_autoptr(GPtrArray) installedRefs = flatpak_installation_list_installed_refs(installation, nullptr, &error);
        if (!installedRefs) { errors.append(scope + ": " + text(error ? error->message : "Could not read installed apps")); continue; }
        g_autoptr(GPtrArray) refs = g_ptr_array_new_with_free_func(g_object_unref);
        QMap<QString, QMap<QString, QString>> published;
        auto skippedSource = [&](const QString &origin, const QString &reason) {
            QStringList names;
            for (guint j = 0; j < installedRefs->len; ++j) {
                auto ref = FLATPAK_INSTALLED_REF(g_ptr_array_index(installedRefs, j));
                if (text(flatpak_installed_ref_get_origin(ref)) != origin
                    || flatpak_ref_get_kind(FLATPAK_REF(ref)) != FLATPAK_REF_KIND_APP) continue;
                const auto name = text(flatpak_installed_ref_get_appdata_name(ref));
                names.append(name.isEmpty() ? text(flatpak_ref_get_name(FLATPAK_REF(ref))) : name);
            }
            names.removeDuplicates(); names.sort();
            const auto label = origin + (scope == "user" ? "" : " (" + (scope == "system" ? "System" : scope) + ")");
            skipped.append("Skipped " + (names.isEmpty() ? QString("installed components") : names.join(", "))
                + ": " + label + " " + reason);
        };
        for (guint i = 0; i < installedRefs->len; ++i) {
            auto installed = FLATPAK_INSTALLED_REF(g_ptr_array_index(installedRefs, i));
            const auto origin = text(flatpak_installed_ref_get_origin(installed));
            if (!published.contains(origin)) {
                published[origin] = {};
                g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(installation, origin.toUtf8(), nullptr, nullptr);
                if (!remote && request["restoreSystemFlathub"].toBool()) {
                    const auto definition = UpdateSources::restorationDefinition(scope, origin, Sources::list());
                    if (!definition.isEmpty()) {
                        send({{"type", "status"}, {"message", "Adding " + origin + " for existing system apps… Authorization may be required."}});
                        QProcess restore;
                        restore.setChildProcessModifier([] {
                            prctl(PR_SET_PDEATHSIG, SIGTERM);
                            if (getppid() == 1) _exit(1);
                        });
                        // Flatpak's system service handles authorization. Never run
                        // App Center as root or overwrite name collisions.
                        restore.start("flatpak", UpdateSources::restoreArguments(scope, origin, definition));
                        restore.closeWriteChannel();
                        const bool finished = restore.waitForFinished(120000);
                        if (!finished) { restore.kill(); restore.waitForFinished(); }
                        flatpak_installation_drop_caches(installation, nullptr, nullptr);
                        remote = flatpak_installation_get_remote_by_name(installation, origin.toUtf8(), nullptr, nullptr);
                        send({{"type", "sources"}, {"sources", Sources::group(Sources::list())}});
                        if (!remote) {
                            const auto detail = QString::fromUtf8(restore.readAllStandardError()).trimmed();
                            skippedSource(origin, !finished
                                ? "could not be added before authorization or the connection timed out. Press Check for App Updates to retry."
                                : "could not be added. " + (detail.isEmpty() ? QString("Authorization was not completed. Press Check for App Updates to retry.") : detail));
                            continue;
                        }
                        send({{"type", "status"}, {"message", "Checking for app updates…"}});
                    }
                }
                if (!remote) { skippedSource(origin, "is missing. Add it in Settings to check these app updates."); continue; }
                if (flatpak_remote_get_disabled(remote)) { skippedSource(origin, "is disabled."); continue; }
                g_clear_error(&error);
                // Do not use list_installed_refs_for_update: its internal
                // transaction can ignore an unavailable remote as nonfatal.
                // Explicitly fetch each origin and preserve its failure, while
                // still offering updates from the other healthy sources.
                g_autoptr(GPtrArray) available = flatpak_installation_list_remote_refs_sync_full(installation,
                    origin.toUtf8(), FLATPAK_QUERY_FLAGS_NONE, nullptr, &error);
                if (!available) {
                    skippedSource(origin, "is unavailable. " + text(error ? error->message : "Could not check this source"));
                    continue;
                }
                for (guint j = 0; j < available->len; ++j) {
                    auto item = FLATPAK_REF(g_ptr_array_index(available, j));
                    g_autofree char *formatted = flatpak_ref_format_ref(item);
                    published[origin][text(formatted)] = text(flatpak_ref_get_commit(item));
                }
            }
            g_autofree char *formatted = flatpak_ref_format_ref(FLATPAK_REF(installed));
            const auto latest = published.value(origin).value(text(formatted));
            if (!latest.isEmpty() && latest != text(flatpak_ref_get_commit(FLATPAK_REF(installed))))
                g_ptr_array_add(refs, g_object_ref(installed));
        }
        // Refresh release labels only during the explicitly requested check.
        // Flatpak itself obtains these labels from AppStream, not the commit.
        QMap<QString, QMap<QString, QString>> versions;
        for (guint i = 0; i < refs->len; ++i) {
            auto installed = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, i));
            const auto origin = text(flatpak_installed_ref_get_origin(installed));
            if (versions.contains(origin)) continue;
            versions[origin] = {};
            gboolean changed = false;
            g_autoptr(GError) versionError = nullptr;
            if (!flatpak_installation_update_appstream_sync(installation, origin.toUtf8(), nullptr,
                    &changed, nullptr, &versionError)) continue;
            QProcess labels;
            labels.setChildProcessModifier([] {
                prctl(PR_SET_PDEATHSIG, SIGTERM);
                if (getppid() == 1) _exit(1);
            });
            QStringList args{scope == "user" ? "--user" : scope == "system" ? "--system" : "--installation=" + scope,
                "remote-ls", "--columns=ref,version", origin};
            labels.start("flatpak", args);
            if (!labels.waitForFinished(15000)) { labels.kill(); labels.waitForFinished(); continue; }
            if (labels.exitCode()) continue;
            for (const auto &line : QString::fromUtf8(labels.readAllStandardOutput()).split('\n')) {
                const auto cells = line.split('\t');
                if (cells.size() == 2) versions[origin][cells[0].trimmed()] = cells[1].trimmed();
            }
        }
        for (guint i = 0; i < refs->len; ++i) {
            auto installed = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, i));
            g_autofree char *formatted = flatpak_ref_format_ref(FLATPAK_REF(installed));
            const auto ref = text(formatted), origin = text(flatpak_installed_ref_get_origin(installed));
            const auto id = text(flatpak_ref_get_name(FLATPAK_REF(installed)));
            const auto name = text(flatpak_installed_ref_get_appdata_name(installed));
            send({{"type", "status"}, {"message", "Checking " + (name.isEmpty() ? id : name) + "…"}});
            g_autoptr(FlatpakRemote) remote = flatpak_installation_get_remote_by_name(installation, origin.toUtf8(), nullptr, nullptr);
            if (!remote || flatpak_remote_get_disabled(remote)) continue;
            g_clear_error(&error);
            g_autoptr(FlatpakTransaction) tx = flatpak_transaction_new_for_installation(installation, nullptr, &error);
            if (!tx) { errors.append(scope + ": " + text(error->message)); continue; }
            Plan plan{installation, ref, {}, {}, {}, false};
            flatpak_transaction_set_no_interaction(tx, true);
            flatpak_transaction_add_default_dependency_sources(tx);
            g_signal_connect(tx, "ready-pre-auth", G_CALLBACK(resolved), &plan);
            g_signal_connect(tx, "add-new-remote", G_CALLBACK(rejectRemote), nullptr);
            if (!flatpak_transaction_add_update(tx, formatted, nullptr, nullptr, &error)) {
                errors.append(id + ": " + text(error->message)); continue;
            }
            flatpak_transaction_run(tx, nullptr, &error);
            if (!plan.ready) {
                errors.append(id + ": " + (plan.error.isEmpty() ? text(error ? error->message : "Could not resolve update") : plan.error));
                continue;
            }
            QString commit;
            quint64 download = 0;
            for (const auto &item : plan.operations) {
                const auto op = item.toObject(); download += quint64(op["downloadBytes"].toDouble());
                if (op["ref"] == ref) commit = op["commit"].toString();
            }
            if (commit.isEmpty()) continue; // Already updated, or held/masked.
            auto oldVersion = text(flatpak_installed_ref_get_appdata_version(installed));
            auto newVersion = versions.value(origin).value(ref);
            const auto oldCommit = text(flatpak_ref_get_commit(FLATPAK_REF(installed)));
            if (oldVersion.isEmpty()) oldVersion = "Revision " + oldCommit.left(12);
            if (newVersion.isEmpty()) newVersion = "Revision " + commit.left(12);
            rows.append(QJsonObject{{"key", Updates::key(scope, ref)}, {"id", id},
                {"name", name.isEmpty() ? id : name}, {"installation", scope}, {"flatpakRef", ref},
                {"remote", origin}, {"sourceUrl", Sources::url(remote)},
                {"oldCommit", oldCommit}, {"commit", commit}, {"oldVersion", oldVersion}, {"newVersion", newVersion},
                {"runtime", ref.startsWith("runtime/")}, {"selected", true},
                {"downloadBytes", double(download)}, {"downloadSize", downloadSizeText(download)},
                {"plan", plan.operations}, {"permissions", QJsonObject::fromVariantMap(plan.permissions)}});
        }
    }
    return {{"type", "updates"}, {"updates", rows}, {"errors", errors}, {"skipped", skipped},
        {"checkedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}};
}
}
extern "C" int fluff_updates_worker(const char *json) {
    // A cancelled/killed UI must not leave metadata probes behind.
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1) return 1;
    int argc = 1; char name[] = "flufflinux-appcenter-updates"; char *argv[] = {name, nullptr};
    QCoreApplication app(argc, argv);
    if (geteuid() == 0) return 1;
    send(scan(QJsonDocument::fromJson(QByteArray(json)).object()));
    return 0;
}
