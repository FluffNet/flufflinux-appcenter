#!/bin/sh
set -eu
mkdir -p target/qml-suite
printf '%s\n' tests/qml/tst_*.qml | xargs -P3 -I{} sh -c '
    suite=$(basename "$1" .qml)
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -input "$1" -o "target/qml-suite/$suite.log,txt" >"target/qml-suite/$suite.stderr" 2>&1
' sh {}
rg 'FAIL!|Totals:' target/qml-suite/*.log
