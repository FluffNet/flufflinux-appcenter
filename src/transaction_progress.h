#pragma once
#include <QVariantMap>
#include <QVariantList>
#include "download_size.h"

// One overall estimate: transfer work occupies 90%, confirmed deployment 10%.
// Flatpak's transfer size is a maximum, not an exact network requirement. Once
// a pull finishes, replace that component's estimate with its actual bytes.
// Keep transfer and deployment signals separate internally; never advance a
// percentage on a timer, or treat a finished pull as an installed component.
inline QVariantMap transactionStages(const QVariantList &operations, const QString &phase) {
    double downloaded = 0, weight = 0, localProgress = 0;
    quint64 received = 0, downloadTotal = 0, appDownloadTotal = 0;
    int complete = 0, total = 0;
    bool pendingDownload = false, estimating = false, hasApp = false, hasLocalBundle = false;
    for (const auto &entry : operations) {
        const auto op = entry.toMap();
        if (op.value("action") == "uninstall") continue;
        ++total;
        if (op.value("phase") == "complete") ++complete;
        // Local bundles have no download of their own; dependencies still do.
        if (op.value("action") == "install-bundle") {
            hasLocalBundle = true;
            localProgress += op.value("phase") == "complete" ? 1
                : qBound(0.0, op.value("progress").toDouble(), 0.99);
            continue;
        }
        const auto transferred = op.value("receivedBytes").toULongLong();
        received += transferred;
        const bool pullFinished = op.value("downloadProgress").toDouble() >= 1;
        const auto componentTotal = pullFinished ? transferred
            : qMax(transferred, op.value("downloadBytes").toULongLong());
        downloadTotal += componentTotal;
        if (op.value("ref").toString().startsWith("app/")) {
            hasApp = true;
            appDownloadTotal += componentTotal;
        }
        const double size = qMax(1.0, op.value("downloadBytes").toDouble());
        const double progress = qBound(0.0, op.value("downloadProgress").toDouble(), 1.0);
        downloaded += size * progress;
        weight += size;
        pendingDownload |= progress < 1;
        estimating |= op.value("phase") == "download" && op.value("estimating").toBool();
    }
    const double downloadProgress = weight > 0 ? qMin(pendingDownload ? 0.99 : 1.0, downloaded / weight) : 1;
    const double installProgress = total ? double(complete) / total : 0;
    // A pure local bundle uses its import callbacks instead of network work.
    const double transferProgress = weight > 0 ? downloadProgress : total ? localProgress / total : 0;
    const double overall = qMin(0.99, 0.9 * transferProgress + 0.1 * installProgress);
    QVariantMap result{{"phase", phase}, {"downloadProgress", downloadProgress},
            {"downloadEstimating", estimating}, {"receivedSize", downloadSizeText(received)},
            {"receivedBytes", received}, {"downloadTotalBytes", downloadTotal},
            {"downloadedSize", downloadSizeText(received)}, {"downloadTotalSize", downloadSizeText(downloadTotal)},
            {"hasDownload", downloadTotal > 0}, {"downloadComplete", !pendingDownload}, {"progress", overall},
            {"installCompleted", complete}, {"installTotal", total},
            {"installProgress", installProgress}};
    // Once a transaction resolves a smaller locale subset/reused payload, the
    // page must show that same total instead of keeping its original maximum.
    // Local bundle sizes are file/import sizes, not network byte totals.
    if (hasApp && !hasLocalBundle)
        result["sizeInfo"] = QVariantMap{{"state", "ready"}, {"appBytes", appDownloadTotal},
            {"totalBytes", downloadTotal}, {"appSize", downloadSizeText(appDownloadTotal)},
            {"totalSize", downloadSizeText(downloadTotal)}};
    return result;
}
