import QtQuick

I18nCapture {
    function buildScenes() {
        return [{name:"app-details-url-fixed", run:openSample, after:bottom}]
    }
    function capture(scene, mode) {
        for (const item of [page().header, page().header.contentItem, findPage("backButton"), findPage("backButton").contentItem])
            console.log("I18N_GEOMETRY", item, item.x, item.y, item.width, item.height, item.implicitHeight)
        const link = findPage("appWebsiteLink")
        check(link && link.mirrored, "website inherits RTL")
        check(Math.abs(link.x + link.width - link.parent.width) < 1, "website aligned to right edge of value column")
        check(link.text === sampleApp.homepage, "website address remains unchanged")
        const file = outputDirectory + "he-" + mode + "-" + scene.name + ".png"
        // Qt Quick Test's image writer returns void; check the produced files outside QML.
        find("captureProbe").grabImage(contentItem).save(Qt.resolvedUrl(file).toString().replace("file://", ""))
        console.log("I18N_URL_PASS", mode, link.text, link.x, link.width, link.parent.width)
    }
}
