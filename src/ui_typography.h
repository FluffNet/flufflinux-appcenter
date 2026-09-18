#pragma once

#include <QApplication>
#include <QFontDatabase>
#include <QQuickWindow>

inline void configureDesktopTypography(QApplication &application) {
    // Keep the desktop's general font (Noto Sans on Fluff Linux), including its
    // configured size. Use the same rasterizer for headings, controls and small
    // metadata. RGB subpixel glyphs can acquire colored/uneven edges when their
    // cached bitmap lands between physical pixels at fractional Wayland scales.
    auto font = QFontDatabase::systemFont(QFontDatabase::GeneralFont);
    font.setStyleStrategy(QFont::StyleStrategy(font.styleStrategy() | QFont::NoSubpixelAntialias));
    application.setFont(font);
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
}
