#pragma once
#include <QVariantMap>

// Reads the repository metadata Flatpak already has on disk. No transaction,
// network requests, application cache, or saved size results.
QVariantMap localFlatpakSizes(const QVariantMap &request);
