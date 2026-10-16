import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as App

TestCase {
    name: "LongTranslatedLabels"
    when: window.visible
    ApplicationWindow {
        id: window
        width: 720; height: 900; visible: true
        property bool darkMode: true
        property color textColor: "white"
        property color accentColor: "#e05562"
        property color borderColor: "#404448"
        property color surfaceColor: "#252525"
        property color raisedSurfaceColor: "#252525"
        property color hoverColor: "#333333"
        property int cornerRadius: 8
        function iconSource(name) { return "" }
        App.FluffButton { id: standard; x:20; y:20; width:176; icon.name:"dialog-ok-apply" }
        App.AppActionButton { id: action; x:220; y:20; width:176; icon.name:"media-playback-start" }
        App.FluffComboBox { id: combo; x:420; y:20; width:200 }
    }
    function test_labels_fit_data() {
        const result = []
        for (const rtl of [false,true]) for (const dark of [false,true]) for (const size of [18,24])
            for (const [language, label] of [
                ["de", "Ausgewählte Anwendungen aktualisieren"],
                ["fi", "Tarkista sovelluspäivitykset"],
                ["hu", "Alkalmazásengedélyek módosításainak megtekintése"],
                ["el", "Ενημερώσεις επιλεγμένων εφαρμογών"],
                ["he", "הצגת השינויים בהרשאות של היישומים שנבחרו"],
                ["ar", "عرض تغييرات أذونات التطبيقات المحددة"],
                ["ta", "தேர்ந்தெடுத்த செயலிகளைப் புதுப்பி"],
                ["ml", "തിരഞ്ഞെടുത്ത ആപ്പുകൾ പുതുക്കുക"],
                ["si", "තෝරාගත් යෙදුම් යාවත්කාලීන කරන්න"],
                ["compound", "Anwendungsberechtigungsänderungsübersicht"]
            ]) result.push({tag:language+rtl+dark+size, rtl:rtl, dark:dark, size:size, label:label})
        return result
    }
    function fits(control, labelName) {
        const label = findChild(control, labelName)
        verify(label !== null)
        tryVerify(function() {
            // Wrapped text and its enclosing layout settle in separate polish passes.
            const top = label.mapToItem(control, 0, 0)
            const bottom = label.mapToItem(control, label.width, label.height)
            return label.contentWidth <= label.width + 1 && label.contentHeight <= label.height + 1
                && top.x >= -1 && top.y >= -1
                && bottom.x <= control.width + 1 && bottom.y <= control.height + 1
        }, 2000, "translated label and its enclosing control contain all wrapped text")
    }
    function test_labels_fit(data) {
        window.darkMode = data.dark
        window.textColor = data.dark ? "white" : "#232629"
        for (const control of [standard,action,combo]) {
            control.LayoutMirroring.enabled = data.rtl
            control.LayoutMirroring.childrenInherit = true
            control.font.pixelSize = data.size
        }
        standard.text = data.label; action.text = data.label
        combo.model = [data.label]; combo.currentIndex = 0
        waitForPolish(window.contentItem)
        fits(standard, "fluffButtonLabel")
        fits(action, "appActionLabel")
        fits(combo, "comboDisplayLabel")
    }
}
