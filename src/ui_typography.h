#pragma once

#include <QApplication>
#include <QFontDatabase>
#include <QQuickWindow>

inline void configureDesktopTypography(QApplication &application) {
    // Keep the desktop's general font (Noto Sans on Fluff Linux), including its
    // configured size and preferences. Match the scalable Qt glyph path used
    // by text inputs, rather than mixing it with small native hinted bitmaps.
    application.setFont(QFontDatabase::systemFont(QFontDatabase::GeneralFont));
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    // Some desktops put legacy Droid Tamil ahead of Noto in their fallback
    // list, which breaks combining marks. Prefer an installed shaping-capable
    // fallback for missing Tamil glyphs without changing the user's main font.
    if (QFontDatabase::families(QFontDatabase::Tamil).contains(QStringLiteral("Noto Sans Tamil")))
        QFontDatabase::addApplicationFallbackFontFamily(QChar::Script_Tamil, QStringLiteral("Noto Sans Tamil"));
#endif
    QQuickWindow::setTextRenderType(QQuickWindow::QtTextRendering);
}
