#pragma once
#include <QVariantMap>
#include <QVariantList>
#include <QLocale>

// Transfer percentage and deployment completion are different signals.
// Flatpak can finish a pull at 100% while still installing that component.
// Keep actual completed operations for installation; never invent a timed %.
inline QVariantMap transactionStages(const QVariantList &operations, const QString &phase) {
    double downloaded = 0, weight = 0;
    quint64 received = 0;
    int complete = 0, total = 0;
    bool pendingDownload = false, estimating = false;
    for (const auto &entry : operations) {
        const auto op = entry.toMap();
        if (op.value("action") == "uninstall") continue;
        ++total;
        if (op.value("phase") == "complete") ++complete;
        received += op.value("receivedBytes").toULongLong();
        // Local bundles have no download of their own; dependencies still do.
        if (op.value("action") == "install-bundle") continue;
        const double size = qMax(1.0, op.value("downloadBytes").toDouble());
        const double progress = qBound(0.0, op.value("downloadProgress").toDouble(), 1.0);
        downloaded += size * progress;
        weight += size;
        pendingDownload |= progress < 1;
        estimating |= op.value("phase") == "download" && op.value("estimating").toBool();
    }
    const double downloadProgress = weight > 0 ? qMin(pendingDownload ? 0.99 : 1.0, downloaded / weight) : 1;
    return {{"phase", phase}, {"hasDownload", weight > 0}, {"downloadProgress", downloadProgress},
            {"downloadEstimating", estimating}, {"receivedSize", QLocale().formattedDataSize(received)},
            {"installCompleted", complete}, {"installTotal", total},
            {"installProgress", total ? double(complete) / total : 0}};
}
