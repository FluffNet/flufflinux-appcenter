#pragma once
#include <QLocale>

// App estimates, dependency sizes, and live transfer totals must use the same
// units. Mixing binary GiB with decimal GB makes identical byte counts appear
// different (1,897,850,000 bytes is both 1.77 GiB and 1.90 GB).
inline constexpr quint64 DownloadMebibyte = 1024 * 1024;
inline constexpr quint64 DownloadGibibyte = 1024 * DownloadMebibyte;

inline QString downloadSizeText(quint64 bytes) {
    const bool gibibytes = bytes >= DownloadGibibyte;
    return QLocale().toString(double(bytes) / (gibibytes ? DownloadGibibyte : DownloadMebibyte), 'f', 2)
        + (gibibytes ? " GiB" : " MiB");
}
