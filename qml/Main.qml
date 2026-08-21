import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window
    width: 1180; height: 760
    minimumWidth: 720; minimumHeight: 520
    visible: true
    title: "Fluff Linux App Center"
    icon: Qt.resolvedUrl("flufflinux-appcenter.svg")
    color: palette.window

    property var catalog: []
    property var selectedApp: null
    property string selectedCategory: "All Apps"
    property string searchText: ""
    property bool catalogLoaded: false

    function argumentValue(name) {
        const args = Qt.application.arguments
        const index = args.indexOf(name)
        return index >= 0 && index + 1 < args.length ? args[index + 1] : ""
    }
    function loadCatalog() {
        const source = argumentValue("--catalog")
        if (!source) { catalogLoaded = true; return }
        const request = new XMLHttpRequest()
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE) {
                if (request.status === 0 || request.status === 200)
                    catalog = JSON.parse(request.responseText)
                catalogLoaded = true
            }
        }
        request.open("GET", source); request.send()
    }
    function openApp(app) { selectedApp = app; stack.replace(appPage) }
    function showCatalog() { selectedApp = null; stack.replace(catalogPage) }
    Component.onCompleted: loadCatalog()

    StackView { id: stack; anchors.fill: parent; initialItem: catalogPage }
    Component { id: catalogPage; CatalogPage {} }
    Component { id: appPage; AppPage { app: window.selectedApp } }
}
