import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    width: 1180; height: 760; visible: true
    palette.window: "#202020"
    palette.windowText: "#ffffff"
    palette.placeholderText: "#aaaaaa"
    selectedCategory: "Installed"
    installedApps: Array.from({length:7}, (_, i) => ({
        id:"org.example.Font" + i, name:"Flatpak Builder Flatpak " + i, icon:"",
        installedOrigin:"flathub", installation:"default", installedSize:"319.62 MiB",
        installedVersion:"v0-Flathub", screenshots:[], summary:"", description:"", category:""
    }))
}
