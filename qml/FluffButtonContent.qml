import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// KDE's native button style draws its text in the background itself. Provide
// explicit content as well as a background so custom hover styling cannot hide it.
Item {
    id: content
    property var control: parent
    property bool monochromeIcon: false
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    opacity: control.enabled ? 1 : 0.45
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Image {
            objectName: "fluffButtonIcon"
            visible: !content.monochromeIcon && (content.control.icon.name.length > 0 || content.control.icon.source.toString().length > 0)
            Layout.preferredWidth: 20; Layout.preferredHeight: 20
            sourceSize: Qt.size(20, 20)
            source: !visible ? "" : content.control.icon.source.toString().length > 0
                    ? content.control.icon.source : window.iconSource(content.control.icon.name)
            fillMode: Image.PreserveAspectFit
        }
        Kirigami.Icon {
            objectName: "fluffButtonMonochromeIcon"
            visible: content.monochromeIcon && (content.control.icon.name.length > 0 || content.control.icon.source.toString().length > 0)
            Layout.preferredWidth: 20; Layout.preferredHeight: 20
            source: !visible ? "" : content.control.icon.source.toString().length > 0
                ? content.control.icon.source : content.control.icon.name
            isMask: true
            color: content.control.palette.buttonText
            Accessible.ignored: true
        }
        Label {
            objectName: "fluffButtonLabel"
            visible: text.length > 0
            text: content.control.text
            textFormat: Text.PlainText
            font: content.control.font
            color: content.control.palette.buttonText
        }
    }
}
