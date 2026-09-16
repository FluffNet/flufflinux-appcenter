#pragma once
#include <glib.h>
#include <QCoreApplication>
#include <QLocale>
#include <QStringList>

// Flatpak exposes a human-readable status, not a download/deploy phase enum.
// Recognize only its known download templates (in its current gettext locale).
// Never forward the rest: OSTree's end-of-pull summary contains delta/object
// counters, and reaching 100% for a pull does not mean deployment is complete.
inline QStringList flatpakDownloadFormats() {
    QStringList formats;
    for (const auto format : {"Downloading: %s/%s", "Downloading metadata: %u/(estimating) %s",
                              "Downloading extra data: %s/%s", "Downloading files: %d/%d %s"}) {
        formats.append(QString::fromUtf8(format));
        formats.append(QString::fromUtf8(g_dgettext("flatpak", format)));
    }
    return formats;
}

inline QString simpleTransactionStatus(const QString &raw, quint64 received, bool removing,
                                       const QStringList &downloadFormats = flatpakDownloadFormats()) {
    if (removing) return QCoreApplication::translate("Flatpak", "Uninstalling…");
    for (const auto &format : downloadFormats) {
        const auto placeholder = format.indexOf('%');
        const auto prefix = format.left(placeholder).trimmed();
        if (placeholder > 0 && !prefix.isEmpty() && raw.startsWith(prefix)) {
            return received ? QCoreApplication::translate("Flatpak", "Downloading… %1 received")
                                  .arg(QLocale().formattedDataSize(received))
                            : QCoreApplication::translate("Flatpak", "Downloading…");
        }
    }
    // Installation includes preparation, unpacking and deployment. Unknown
    // progress messages get this safe activity label, not raw diagnostics.
    // Actual failures arrive separately through operation-error/result.
    return QCoreApplication::translate("Flatpak", "Installing…");
}
