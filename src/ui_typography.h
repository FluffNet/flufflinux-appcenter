#pragma once

#include <QApplication>
#include <QFontDatabase>
#include <QQuickWindow>

inline void configureDesktopTypography(QApplication &application) {
    // Keep the desktop's general font (Noto Sans on Fluff Linux), including its
    // configured size and preferences. Match the scalable Qt glyph path used
    // by text inputs, rather than mixing it with small native hinted bitmaps.
    application.setFont(QFontDatabase::systemFont(QFontDatabase::GeneralFont));
    QQuickWindow::setTextRenderType(QQuickWindow::QtTextRendering);
}
