import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: notice
    property string networkState: "unknown"
    property bool compact: false
    property bool allowRetry: false
    property bool retryEnabled: true
    signal retryRequested()
    readonly property string title: networkState === "offline" ? qsTr("No Network Connection")
        : networkState === "sources-unavailable" ? qsTr("Cannot Connect to Sources") : ""
    readonly property string note: networkState === "offline"
        ? qsTr("Connect to a network to browse apps and check for updates.")
        : qsTr("Please check your internet connection and try again.")
    readonly property string compactText: title
    visible: title.length > 0
    implicitHeight: compact ? inlineNote.implicitHeight : offlineMessage.implicitHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: compact ? compactText : title + ". " + note
    RowLayout {
        id: inlineNote
        visible: notice.compact
        width: parent.width; spacing: 6
        AppIcon {
            objectName: "networkInlineWarningIcon"
            icon: "dialog-warning"
            // Use KDE's colored triangle, not the small symbolic variant.
            sourceSize: Qt.size(64, 64)
            Layout.preferredWidth: 18; Layout.preferredHeight: 18
        }
        Label {
            objectName: "networkInlineText"
            Layout.fillWidth: true
            text: notice.compactText; textFormat: Text.PlainText
            font.pixelSize: 11; color: window.mutedTextColor
            wrapMode: Text.WordWrap
        }
    }
    ColumnLayout {
        id: offlineMessage
        visible: !notice.compact
        width: parent.width; spacing: 14
        AppIcon {
            objectName: "networkWarningIcon"
            icon: "dialog-warning"; sourceSize: Qt.size(64, 64)
            Layout.preferredWidth: 64; Layout.preferredHeight: 64
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            objectName: "networkOfflineTitle"
            text: notice.title; textFormat: Text.PlainText
            Layout.fillWidth: true
            font.pixelSize: 26; font.weight: Font.DemiBold
            color: window.textColor; wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
        Label {
            text: notice.note; textFormat: Text.PlainText
            Layout.fillWidth: true
            font.pixelSize: 14; color: window.mutedTextColor
            wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
        }
        Button {
            objectName: "retryCatalogSourcesButton"
            text: qsTr("Try Again")
            visible: notice.allowRetry
            enabled: notice.retryEnabled
            focusPolicy: Qt.TabFocus
            Layout.alignment: Qt.AlignHCenter
            onClicked: notice.retryRequested()
        }
    }
}
