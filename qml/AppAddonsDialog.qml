import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog
    objectName: "appAddonsDialog"
    required property var app
    property var backend: null
    property int requestToken: 0
    property bool wasBusy: false
    readonly property var addonData: backend && backend.appAddons || ({})
    readonly property var rows: addonData.items || []
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent.width - 48, 960)
    height: Math.min(parent.height - 48, 640)
    modal: true
    padding: 24
    title: qsTr("Add-Ons - %1").arg(app.name || "")
    background: Rectangle { color: window.raisedSurfaceColor; radius: window.cornerRadius; border.color: window.borderColor }
    header: Label {
        text: dialog.title; textFormat: Text.PlainText
        color: window.textColor; font.pixelSize: 23; wrapMode: Text.Wrap
        padding: 24; bottomPadding: 8
    }
    function refresh() {
        if (backend && typeof backend.requestAppAddons === "function")
            requestToken = backend.requestAppAddons(app)
    }
    function jobFor(row) {
        if (!backend) return null
        return (backend.jobs || []).filter(job => job.addon && job.flatpakRef === row.flatpakRef
            && job.installation === row.installation && !job.cancelled).slice(-1)[0] || null
    }
    onOpened: { wasBusy = backend && backend.busy; refresh() }
    onClosed: {
        if (backend && typeof backend.cancelAppAddons === "function") backend.cancelAppAddons(requestToken)
        requestToken = 0
    }
    Component.onDestruction: {
        if (requestToken && backend && typeof backend.cancelAppAddons === "function") backend.cancelAppAddons(requestToken)
    }
    Connections {
        target: dialog.backend
        ignoreUnknownSignals: true
        function onJobsChanged() {
            if (!dialog.opened) return
            const busy = !!dialog.backend.busy
            if (dialog.wasBusy && !busy) dialog.refresh()
            dialog.wasBusy = busy
        }
    }
    contentItem: ColumnLayout {
        spacing: 16
        Label {
            Layout.fillWidth: true
            visible: dialog.addonData.state === "not-installed"
            text: qsTr("Install this app first to manage its add-ons.")
            color: window.mutedTextColor; wrapMode: Text.Wrap
        }
        Label {
            Layout.fillWidth: true
            visible: text.length > 0
            text: dialog.addonData.error || ""
            color: window.accentColor; wrapMode: Text.Wrap
        }
        Item {
            id: viewport
            Layout.fillWidth: true; Layout.fillHeight: true
            RowLayout {
                anchors.centerIn: parent
                visible: dialog.addonData.state === "loading"
                LoadingSpinner { running: dialog.addonData.state === "loading"; color: window.textColor }
                PageStatusLabel { objectName: "addonsLoadingMessage"; text: qsTr("Loading...") }
            }
            PageStatusLabel {
                objectName: "addonsEmptyMessage"
                anchors.centerIn: parent; width: parent.width
                visible: dialog.addonData.state === "ready" && dialog.rows.length === 0
                text: qsTr("No compatible add-ons are available for this installed version.")
                wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
            }
            Flickable {
                id: scroll
                anchors.fill: parent; clip: true
                visible: dialog.addonData.state !== "loading"
                contentWidth: width; contentHeight: entries.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: PageScrollBar {
                    parent: viewport
                    anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                    anchors.rightMargin: 1
                    visible: size < 1
                    surfaceColor: window.raisedSurfaceColor
                    Accessible.name: qsTr("Scroll app add-ons")
                }
                NaturalWheelScroll { scrollTarget: scroll }
                ColumnLayout {
                    id: entries
                    width: parent.width - 16; spacing: 12
                    Repeater {
                        objectName: "addonRows"
                        model: dialog.rows
                        delegate: Pane {
                            id: card
                            required property var modelData
                            readonly property var job: dialog.jobFor(modelData)
                            Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.maximumWidth: entries.width; padding: 16
                            background: Rectangle { radius: window.cornerRadius; color: window.surfaceColor; border.color: window.borderColor }
                            contentItem: ColumnLayout {
                                RowLayout {
                                    Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.maximumWidth: card.availableWidth; spacing: 16
                                    ColumnLayout {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 6
                                        Label { text: card.modelData.name; textFormat: Text.PlainText; font.bold: true; color: window.textColor; Layout.fillWidth: true; Layout.minimumWidth: 0; wrapMode: Text.Wrap }
                                        Label { text: card.modelData.summary || ""; textFormat: Text.PlainText; color: window.mutedTextColor; Layout.fillWidth: true; Layout.minimumWidth: 0; wrapMode: Text.Wrap; visible: text.length > 0 }
                                        Label { text: card.modelData.installed ? qsTr("Installed") : ""; color: window.mutedTextColor; visible: text.length > 0 }
                                    }
                                    AppActionButton {
                                        objectName: "addonActionButton"
                                        Layout.fillWidth: false
                                        Layout.minimumWidth: 110; Layout.minimumHeight: 40
                                        leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
                                        font: Qt.application.font
                                        visible: dialog.addonData.state === "ready"
                                        text: card.job && card.job.active ? qsTr("Cancel") : card.modelData.installed ? qsTr("Remove") : qsTr("Install")
                                        enabled: card.job && card.job.active || card.modelData.installed || card.modelData.available
                                        downloadArrow: !(card.job && card.job.active) && !card.modelData.installed
                                        icon.name: card.job && card.job.active ? "dialog-cancel" : "download"
                                        icon.source: card.modelData.installed && !(card.job && card.job.active) ? Qt.resolvedUrl("trash-red.svg") : ""
                                        icon.color: "transparent"
                                        onClicked: {
                                            if (card.job && card.job.active) dialog.backend.cancelJob(card.job.index)
                                            else dialog.backend.changeAddon(card.modelData.flatpakRef, !card.modelData.installed)
                                        }
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    visible: !!card.job && (card.job.active || card.job.failed)
                                    text: !card.job ? "" : card.job.failed ? card.job.error : card.job.queued ? qsTr("Queued...") : card.job.status
                                    color: card.job && card.job.failed ? window.accentColor : window.textColor
                                    wrapMode: Text.Wrap
                                }
                                InstallationProgress {
                                    Layout.fillWidth: true
                                    job: card.job
                                }
                            }
                        }
                    }
                }
            }
        }
        FluffButton {
            objectName: "retryAddonsButton"
            visible: dialog.addonData.state === "error" || !!dialog.addonData.error
            text: qsTr("Retry"); onClicked: dialog.refresh()
        }
    }
    footer: DialogButtonBox {
        alignment: Qt.AlignHCenter
        topPadding: 8; bottomPadding: 8; leftPadding: 8; rightPadding: 8
        FluffButton {
            objectName: "closeAddonsButton"
            text: qsTr("Close"); icon.name: "window-close"
            contentItem: FluffButtonContent { monochromeIcon: true }
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        onRejected: dialog.close()
    }
}
