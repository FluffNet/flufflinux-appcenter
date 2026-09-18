import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1180; height: 760
    minimumWidth: 720; minimumHeight: 520
    // The native launcher restores geometry before showing the real window.
    // Standalone QML fixtures keep their explicit, non-persistent geometry.
    visible: typeof fluffWindowManaged === "undefined" || !fluffWindowManaged
    title: "App Center"
    color: backgroundColor

    readonly property bool darkMode: palette.window.hslLightness < 0.5
    readonly property color accentColor: darkMode ? "#e05562" : "#820101"
    readonly property color textColor: palette.windowText
    readonly property color mutedTextColor: palette.placeholderText
    // Two opaque, theme-derived levels. No independent blue-gray/translucent
    // panels: the header/sidebar belong to the window, cards/fields sit above it.
    readonly property color backgroundColor: Qt.rgba(palette.window.r, palette.window.g, palette.window.b, 1)
    readonly property color surfaceColor: Qt.tint(backgroundColor, Qt.rgba(1, 1, 1, darkMode ? 0.035 : 0.60))
    readonly property color raisedSurfaceColor: surfaceColor
    readonly property color sidebarColor: backgroundColor
    readonly property color borderColor: Qt.tint(surfaceColor, Qt.rgba(textColor.r, textColor.g, textColor.b, 0.11))
    // Keep hover visibly distinct from the raised button surface. This is a
    // background tint only; hovering must not look like keyboard focus.
    readonly property color hoverColor: Qt.tint(surfaceColor, Qt.rgba(textColor.r, textColor.g, textColor.b, 0.085))
    readonly property int cornerRadius: 8
    readonly property url appIconUrl: typeof fluffAppIconUrl !== "undefined"
                                      ? fluffAppIconUrl : ""

    property var catalog: typeof fluffInitialCatalog !== "undefined"
                          ? fluffInitialCatalog : []
    property var selectedApp: null
    property var backend: typeof fluffBackend !== "undefined" ? fluffBackend : null
    property var installedApps: backend ? backend.installedApps : []
    property bool installedLoading: backend ? backend.installedLoading : false
    property string installedError: backend ? backend.installedError : ""
    readonly property int iconRevision: backend ? backend.iconRevision : 0
    property string selectedCategory: "All Apps"
    property string searchCategoryFilter: "All Apps"
    property string searchText: ""
    readonly property bool catalogLoaded: true
    DownloadQueue {
        id: downloads
        objectName: "downloadQueue"
        jobs: window.backend ? window.backend.jobs.filter(function(job) {
            return job.action !== "uninstall" && job.cancelled !== true
        }) : []
    }
    readonly property alias downloadQueue: downloads
    function findInstalled(app) {
        if (!app) return null
        const id = String(app.id).replace(/\.desktop$/, "")
        const matches = installedApps.filter(function(item) {
            return String(item.id).replace(/\.desktop$/, "") === id
        })
        return matches.find(function(item) { return item.installation === app.installation
            && item.installedBranch === app.installedBranch }) || matches[0] || null
    }
    function jobForApp(app) {
        if (!app) return null
        const id = String(app.id).replace(/\.desktop$/, "")
        // App/Installed progress also includes removals, which never belong
        // in Downloads or its badge. Cancellations are never status history.
        const matches = (backend ? backend.jobs : []).filter(function(job) {
            return job.id === id && job.cancelled !== true
        })
        return matches.length ? matches[matches.length - 1] : null
    }
    function iconSource(icon) {
        let source = icon || "application-x-executable"
        if (source.indexOf("://") < 0)
            source = source.indexOf("/") >= 0 ? "file://" + source : "image://icon/" + source
        return source.startsWith("image://icon/") || source.startsWith("file://")
            ? source + "?revision=" + iconRevision : source
    }
    function installApp(app) { if (backend) backend.installApp(app) }
    function detailsFor(app) {
        const installed = findInstalled(app)
        if (installed) return installed
        const clean = Object.assign({}, app)
        for (const field of ["installedSize", "installedBytes", "installedVersion", "installedOrigin", "installation", "installedBranch", "installedArch", "installedAt", "installedDate"])
            delete clean[field]
        return clean
    }
    function uninstallApp(app) { if (backend) backend.uninstallApp(app) }
    Connections {
        target: window.backend
        ignoreUnknownSignals: true
        function onAppOpened(app) { window.openApp(app) }
        function onInputError(message) { inputError.text = message; errorDialog.open() }
        function onCatalogChanged() { window.catalog = window.backend.catalog }
    }
    onClosing: function(close) {
        if (backend && backend.busy) { close.accepted = false; closeDialog.open() }
    }
    function showDownloads() {
        if (stack.currentItem.objectName !== "downloadsPage")
            stack.push(downloadsPage)
    }
    function goBack() { if (stack.depth > 1) stack.pop() }
    function showSettings() {
        if (stack.currentItem.objectName !== "settingsPage") stack.push(settingsPage)
        if (backend && typeof backend.refreshSources === "function") backend.refreshSources()
    }
    function showAbout() { aboutDialog.open() }
    function selectSource(source) {
        selectedApp = Object.assign({}, source, { sources: selectedApp.sources || [] })
        if (backend) backend.requestInstallInfo(selectedApp)
    }
    function openApp(app) {
        selectedApp = app
        // Track the displayed app even while installed. The backend refreshes
        // these local estimates after transactions, before revealing Install
        // again; otherwise an uninstall refreshes nothing (or the prior app).
        if (backend && typeof backend.requestInstallInfo === "function")
            backend.requestInstallInfo(app)
        if (stack.depth === 1 || stack.currentItem.objectName === "downloadsPage")
            stack.push(appPage)
        else
            stack.replace(appPage)
    }
    function showCatalog() {
        // Pop back to the existing CatalogPage instance. Keeping that item
        // alive preserves its exact GridView position, search, and category.
        if (stack.depth > 1)
            stack.pop(stack.get(0))
    }
    FluffBackground { anchors.fill: parent }
    MouseArea {
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.LeftButton
        onPressed: function(mouse) {
            // Observe the press, then pass it through untouched. Clearing
            // before delivery lets the clicked control take focus normally.
            // This also works with KDE controls that swallow empty-area clicks.
            const focused = window.activeFocusItem
            let ancestor = focused
            while (ancestor && ancestor !== stack) ancestor = ancestor.parent
            if (ancestor && focused !== stack
                    && !focused.contains(focused.mapFromItem(this, mouse.x, mouse.y))) {
                focused.focus = false
                window.contentItem.forceActiveFocus(Qt.MouseFocusReason)
            }
            mouse.accepted = false
        }
    }
    StackView {
        id: stack
        objectName: "navigationStack"
        anchors.fill: parent
        initialItem: catalogPage
        background: null
        pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        pushExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }
        popEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        popExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }
        replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }
    }
    Component { id: catalogPage; CatalogPage {} }
    Component { id: appPage; AppPage { app: window.detailsFor(window.selectedApp) } }
    Component { id: downloadsPage; DownloadsPage {} }
    Component { id: settingsPage; SettingsPage {} }
    Dialog {
        id: aboutDialog
        objectName: "aboutDialog"
        anchors.centerIn: parent; width: Math.min(window.width - 48, 440)
        title: qsTr("About App Center")
        modal: true; standardButtons: Dialog.Close
        footer: DialogButtonBox {
            standardButtons: Dialog.Close
            alignment: Qt.AlignHCenter
            topPadding: 8; bottomPadding: 8
            leftPadding: 8; rightPadding: 8
            delegate: FluffButton { objectName: "aboutCloseButton" }
            onRejected: aboutDialog.close()
        }
        contentItem: ColumnLayout {
            spacing: 16
            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 72; Layout.preferredHeight: 72
                source: window.appIconUrl; fillMode: Image.PreserveAspectFit
            }
            Label { text: qsTr("App Center"); font.pixelSize: 26; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Label { objectName: "aboutVersion"; text: qsTr("Version %1").arg(Qt.application.version || "2026.09 (Beta)"); Layout.alignment: Qt.AlignHCenter }
            Label { text: qsTr("Discover and manage Flatpak apps on Fluff Linux."); Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
            Label {
                objectName: "aboutCopyright"
                text: qsTr("Copyright © 2026 FluffNet LLC - MIT License")
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }
    }
    TransactionReview { backend: window.backend }
    Dialog {
        id: errorDialog
        anchors.centerIn: parent; width: Math.min(window.width - 48, 600)
        title: qsTr("Could not open Flatpak")
        modal: true; standardButtons: Dialog.Ok
        footer: DialogButtonBox {
            standardButtons: Dialog.Ok
            delegate: FluffButton {}
            onAccepted: errorDialog.accept()
        }
        contentItem: Label { id: inputError; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    }
    Dialog {
        id: closeDialog
        anchors.centerIn: parent; width: Math.min(window.width - 48, 520)
        title: qsTr("An operation is still running")
        modal: true; standardButtons: Dialog.Ok
        footer: DialogButtonBox {
            standardButtons: Dialog.Ok
            delegate: FluffButton {}
            onAccepted: closeDialog.accept()
        }
        contentItem: ColumnLayout {
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: qsTr("Please wait for completion, or cancel the operations before closing App Center. Completed downloads stay in this session’s history.") }
            FluffButton { text: qsTr("Cancel operations"); onClicked: { backend.cancelAll(); closeDialog.close() } }
        }
    }
    DropArea {
        anchors.fill: parent
        onDropped: function(drop) {
            if (!backend || !drop.hasUrls) return
            for (let i = 0; i < Math.min(drop.urls.length, 16); ++i) backend.openSource(drop.urls[i].toString())
            drop.acceptProposedAction()
        }
    }
}
