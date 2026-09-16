import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: window
    width: 1180; height: 760
    minimumWidth: 720; minimumHeight: 520
    visible: true
    title: "App Center"
    color: "transparent"

    readonly property bool darkMode: palette.window.hslLightness < 0.5
    readonly property color accentColor: darkMode ? "#e05562" : "#820101"
    readonly property color textColor: palette.windowText
    readonly property color mutedTextColor: palette.placeholderText
    readonly property color surfaceColor: darkMode ? Qt.rgba(0.13, 0.15, 0.18, 0.94) : Qt.rgba(0.98, 0.985, 0.995, 0.95)
    readonly property color raisedSurfaceColor: darkMode ? Qt.rgba(0.18, 0.20, 0.23, 0.96) : Qt.rgba(1, 1, 1, 0.97)
    readonly property color sidebarColor: darkMode ? Qt.rgba(0.10, 0.115, 0.14, 0.96) : Qt.rgba(0.925, 0.94, 0.96, 0.96)
    readonly property color borderColor: darkMode ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0.08, 0.10, 0.14, 0.16)
    readonly property color hoverColor: darkMode ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(0.13, 0.15, 0.20, 0.065)
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
        for (const field of ["installedSize", "installedVersion", "installation", "installedBranch", "installedArch", "installedAt", "installedDate"])
            delete clean[field]
        return clean
    }
    function uninstallApp(app) { if (backend) backend.uninstallApp(app) }
    Connections {
        target: window.backend
        function onAppOpened(app) { window.openApp(app) }
        function onInputError(message) { inputError.text = message; errorDialog.open() }
    }
    onClosing: function(close) {
        if (backend && backend.busy) { close.accepted = false; closeDialog.open() }
    }
    function showDownloads() {
        if (stack.currentItem.objectName !== "downloadsPage")
            stack.push(downloadsPage)
    }
    function goBack() { if (stack.depth > 1) stack.pop() }
    function openApp(app) {
        selectedApp = app
        // Track the displayed app even while installed. The backend refreshes
        // these local estimates after transactions, before revealing Install
        // again; otherwise an uninstall refreshes nothing (or the prior app).
        if (backend && typeof backend.requestInstallInfo === "function")
            backend.requestInstallInfo(app)
        if (stack.depth === 1)
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
    TransactionReview { backend: window.backend }
    Dialog {
        id: errorDialog
        anchors.centerIn: parent; width: Math.min(window.width - 48, 600)
        title: qsTr("Could not open Flatpak")
        modal: true; standardButtons: Dialog.Ok
        contentItem: Label { id: inputError; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    }
    Dialog {
        id: closeDialog
        anchors.centerIn: parent; width: Math.min(window.width - 48, 520)
        title: qsTr("An operation is still running")
        modal: true; standardButtons: Dialog.Ok
        contentItem: ColumnLayout {
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: qsTr("Please wait for completion, or cancel the operations before closing App Center. Completed downloads stay in this session’s history.") }
            Button { text: qsTr("Cancel operations"); onClicked: { backend.cancelAll(); closeDialog.close() } }
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
