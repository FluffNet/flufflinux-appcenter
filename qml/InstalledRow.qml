import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: row
    required property var app
    height: Math.max(108, contentItem.implicitHeight + topPadding + bottomPadding)
    padding: 16
    hoverEnabled: true
    Accessible.name: app.name + ", " + app.installedSize
    background: Rectangle {
        radius: 8
        color: row.hovered ? window.raisedSurfaceColor : window.surfaceColor
        border.color: row.activeFocus ? window.accentColor : window.borderColor
    }
    contentItem: RowLayout {
        spacing: 16
        Image {
            Layout.preferredWidth: 56; Layout.preferredHeight: 56
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: typeof window.iconSource === "function" ? window.iconSource(app.icon)
                    : !app.icon ? "image://icon/application-x-executable"
                    : app.icon.indexOf("://") >= 0 ? app.icon
                    : app.icon.indexOf("/") >= 0 ? "file://" + app.icon
                    : "image://icon/" + app.icon
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            Label {
                Layout.fillWidth: true
                text: app.name; color: window.textColor
                font.pixelSize: 18; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 3
                Label { text: qsTr("Version:"); color: window.mutedTextColor }
                Label {
                    Layout.fillWidth: true
                    text: app.installedVersion || qsTr("Unavailable")
                    color: window.textColor
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                Label { text: qsTr("Size:"); color: window.mutedTextColor }
                Label {
                    Layout.fillWidth: true
                    text: app.installedSize || qsTr("Unavailable")
                    color: window.textColor
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
        ToolButton {
            objectName: "uninstallButton"
            enabled: !!window.backend && !(window.jobForApp(app) && window.jobForApp(app).active)
            Layout.preferredWidth: 44; Layout.preferredHeight: 44
            Accessible.name: qsTr("Uninstall %1").arg(app.name)
            onClicked: window.uninstallApp(app)
            // Explicit image keeps the trash red in both Breeze palettes.
            contentItem: Image {
                source: "trash-red.svg"
                sourceSize: Qt.size(24, 24)
                fillMode: Image.PreserveAspectFit
            }
            background: Rectangle { radius: 6; color: "transparent"; border.color: window.borderColor }
        }
    }
}
