#pragma once
#include <QVariantMap>

// Reads the repository metadata Flatpak already has on disk. No transaction,
// network requests, application cache, or saved size results.
QVariantMap localFlatpakSizes(const QVariantMap &request);

// Exact deployed app bytes, formatted in MiB/GiB. Empty when unavailable;
// never reinterpret the CLI's rounded decimal size as a binary value.
QString localInstalledFlatpakSize(const QVariantMap &app);
