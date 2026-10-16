import QtQuick

I18nCapture {
    id: navigationCapture
    function buildScenes() {
        return [
            {name:"app-back-rtl", button:"backButton", run:openSample},
            {name:"queue-back-rtl", button:"downloadsBackButton", run:function() { navigationCapture.showDownloads() }},
            {name:"settings-back-rtl", button:"settingsBackButton", run:function() { navigationCapture.showSettings() }}
        ]
    }
    function capture(scene, mode) {
        const back = findPage(scene.button)
        check(back && back.mirrored, "back button inherits RTL: " + scene.name)
        check(back.icon.name === "go-next", "back arrow points right: " + scene.name)
        const file = outputDirectory + "he-" + mode + "-" + scene.name + ".png"
        find("captureProbe").grabImage(contentItem).save(Qt.resolvedUrl(file).toString().replace("file://", ""))
        console.log("I18N_BACK_PASS", mode, scene.name)
    }
}
