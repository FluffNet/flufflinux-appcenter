import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "AppPublishers"
    when: main.visible
    AppCenter.Main { id: main; backend: backend }
    QtObject {
        id: backend
        property var installedApps: []
        property var jobs: []
        property var updates: ({state:"idle", items:[]})
        property var review: ({})
        property var installSizes: ({})
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        function requestInstallInfo(app) {}
    }
    function stack() { return findChild(main, "navigationStack") }
    function page() { return stack().get(0) }
    function app(publisher) {
        return {id:"com.discordapp.Discord", name:"Discord", developer:publisher, category:"Internet",
            summary:"Talk, play, hang out", description:"Description", screenshots:[], icon:"", sources:[],
            license:"Proprietary", homepage:"", version:"1.0", remote:"flathub", sourceUrl:"https://dl.flathub.org/repo/",
            flatpakRef:"app/com.discordapp.Discord/x86_64/stable", searchName:"discord", searchSummary:"talk",
            searchDescription:"description", searchMetadata:"discord", searchHaystack:"discord talk"}
    }
    function installed(publisher) {
        return Object.assign(app(publisher), {installation:"user", installedRef:app(publisher).flatpakRef,
            installedOrigin:"flathub", installedVersion:"1.0", installedBranch:"stable", installedSize:"2 MiB"})
    }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.showCatalog(); tryCompare(stack(), "busy", false)
        main.width = 1180; main.height = 760
        main.searchText = ""; main.selectedCategory = "All Apps"
        backend.jobs = []; backend.installedApps = []; backend.updates = {state:"idle", items:[]}
        main.catalog = [app("Discord Inc.")]
        page().catalogSortIndex = 0
        waitForPolish(page()); wait(30)
    }
    function checkLabel(label, publisher) {
        verify(label)
        compare(label.text, publisher)
        compare(label.visible, !!publisher)
        compare(label.color, main.accentColor)
        compare(label.font.weight, Font.DemiBold)
        compare(label.textFormat, Text.PlainText)
    }
    function test_surfaces_data() {
        const rows = []
        for (const surface of ["catalog", "recommended", "installed", "update", "download", "details"])
            for (const publisher of ["Discord Inc.", "<b>Publisher & Co.</b>", ""])
                rows.push({tag:surface + "-" + publisher, surface:surface, publisher:publisher})
        return rows
    }
    function test_surfaces(data) {
        main.catalog = [app(data.publisher)]
        let label
        if (data.surface === "catalog") {
            const grid = findChild(page(), "catalogGrid")
            grid.positionViewAtEnd(); waitForPolish(grid); wait(30)
            label = findChild(grid.itemAtIndex(0), "catalogAppPublisher")
        } else if (data.surface === "recommended") {
            label = findChild(page(), "recommendedAppPublisher")
        } else if (data.surface === "installed") {
            backend.installedApps = [installed(data.publisher)]
            page().openCategory("Installed"); waitForPolish(page()); wait(30)
            label = findChild(findChild(page(), "installedList").itemAtIndex(0), "installedAppPublisher")
        } else if (data.surface === "update") {
            const update = Object.assign({}, app(""), {key:"user:discord", installation:"user", selected:true,
                oldVersion:"1.0", newVersion:"2.0", downloadBytes:100, runtime:false, permissions:{state:"unchanged"}, plan:[]})
            backend.updates = {state:"ready", items:[update]}
            main.showUpdates(); waitForPolish(page()); wait(30)
            label = findChild(findChild(page(), "updatesList").itemAtIndex(0), "updateAppPublisher")
        } else if (data.surface === "download") {
            backend.jobs = [{index:0, id:app("").id, name:"Discord", icon:"", action:"install", active:false,
                failed:false, operations:[], flatpakRef:app("").flatpakRef, remote:"flathub"}]
            main.showDownloads(); tryCompare(stack(), "busy", false); waitForPolish(stack().currentItem)
            label = findChild(stack().currentItem, "downloadAppPublisher")
        } else {
            main.openApp(main.catalog[0]); tryCompare(stack(), "busy", false)
            label = findChild(stack().currentItem, "appDeveloper")
        }
        checkLabel(label, data.publisher)
    }
    function test_metadata_identity_and_no_invented_publisher() {
        const stable = app("Stable publisher")
        const beta = Object.assign(app("Beta publisher"), {flatpakRef:"app/com.discordapp.Discord/x86_64/beta", remote:"flathub-beta"})
        stable.sources = [beta]
        main.catalog = [stable]
        compare(main.publisherFor({id:stable.id, flatpakRef:beta.flatpakRef, remote:"flathub-beta"}), "Beta publisher")
        compare(main.publisherFor({id:stable.id + ".desktop"}), "Stable publisher")
        compare(main.publisherFor({id:stable.id, flatpakRef:beta.flatpakRef, remote:"flathub"}), "")
        compare(main.publisherFor({id:stable.id, remote:"unconfigured"}), "")
        compare(main.publisherFor({id:stable.id, sourceUrl:"https://example.org/repo"}), "")
        compare(main.publisherFor({id:stable.id, runtime:true}), "")
        compare(main.publisherFor({id:"org.example.Unknown", remote:"flathub"}), "")
        compare(main.publisherFor({developer:"   "}), "")
        compare(main.publisherFor(null), "")
        const telegram = Object.assign(app("Telegram FZ-LLC"), {id:"org.telegram.desktop", flatpakRef:"app/org.telegram.desktop/x86_64/stable"})
        main.catalog = [telegram]
        compare(main.publisherFor({id:"org.telegram.desktop"}), "Telegram FZ-LLC")
        main.catalog = []
        backend.installedApps = [installed("Installed publisher")]
        compare(main.publisherFor({id:stable.id, flatpakRef:stable.flatpakRef, remote:"flathub"}), "Installed publisher")
    }
    function test_recommended_layout_data() {
        return [{tag:"narrow", width:720, height:520}, {tag:"short", width:1180, height:520},
            {tag:"wide", width:1400, height:1000}, {tag:"desktop", width:1920, height:1080}]
    }
    Component {
        id: publisherFixture
        AppCenter.AppPublisher { property var window: main }
    }
    function test_adaptive_label_resizes_without_stale_truncation() {
        const label = createTemporaryObject(publisherFixture, main.contentItem,
            {width:110, app:{developer:"Microsoft Corporation"}})
        verify(label)
        waitForPolish(label)
        compare(label.fontSizeMode, Text.HorizontalFit)
        compare(label.minimumPixelSize, 12)
        compare(label.maximumLineCount, 2)
        verify(!label.truncated)
        verify(label.contentWidth <= label.width + 1)
        const narrowLines = label.lineCount
        label.width = 320
        waitForPolish(label)
        verify(!label.truncated)
        compare(label.lineCount, 1)
        verify(label.lineCount <= narrowLines)
        label.width = 110
        waitForPolish(label)
        verify(!label.truncated)
        compare(label.lineCount, narrowLines)
    }
    function test_extreme_names_keep_readable_floor_and_tooltip() {
        const publisher = "An exceptionally long publisher name that cannot possibly fit in a small card without becoming unreadable"
        const label = createTemporaryObject(publisherFixture, main.contentItem,
            {width:100, app:{developer:publisher}})
        verify(label)
        waitForPolish(label)
        compare(label.text, publisher)
        compare(label.ToolTip.text, publisher)
        compare(label.minimumPixelSize, 12)
        verify(label.lineCount <= 2)
        verify(label.contentWidth <= label.width + 1)
    }
    function test_recommended_layout(data) {
        main.width = data.width; main.height = data.height
        const names = ["Discord", "Steam", "Telegram", "Spotify", "Google Chrome", "Brave", "Visual Studio Code", "Sober", "Minecraft Launcher"]
        const publishers = ["Discord Inc.", "Valve Corporation", "Telegram FZ-LLC", "Spotify", "Google",
            "Brave Software", "Microsoft Corporation", "VinegarHQ & Sober contributors", "Mojang AB"]
        main.catalog = page().recommendedIds.map((id, i) => Object.assign(app(publishers[i]),
            {id:id, name:names[i], flatpakRef:"app/" + id + "/x86_64/stable"}))
        waitForPolish(page()); wait(50)
        const grid = findChild(page(), "catalogGrid")
        grid.positionViewAtBeginning(); wait(30)
        verify(grid.headerItem.height <= grid.height - 32, "All Apps and its first row must remain visible: "
            + grid.headerItem.height + " <= " + (grid.height - 32))
        for (const pick of page().recommendedApps) {
            const card = findChild(page(), "recommended-" + pick.id)
            const title = findChild(card, "recommendedAppName"), publisher = findChild(card, "recommendedAppPublisher")
            verify(!title.truncated, pick.name + " must fit")
            verify(publisher.visible && publisher.height > 0)
            verify(!publisher.truncated, pick.developer + " must be fully readable without hovering")
            verify(publisher.contentWidth <= publisher.width + 1, "Publisher must fit the tile width")
            verify(publisher.contentHeight <= publisher.height + 1, "Publisher must fit the tile height")
            verify(publisher.minimumPixelSize >= 10, "Do not shrink publishers to unreadable sizes")
            const titleBottom = title.mapToItem(card, 0, title.height)
            const publisherTop = publisher.mapToItem(card, 0, 0)
            verify(Math.abs(publisherTop.x - titleBottom.x) < 1, "Publisher must align with the title's left edge")
            verify(Math.abs(publisherTop.y - titleBottom.y - 2) < 1,
                "Publisher must sit directly below the title, not in a separate footer")
            compare(publisher.horizontalAlignment, Text.AlignLeft)
            compare(publisher.verticalAlignment, Text.AlignTop)
            verify(publisher.mapToItem(card, 0, publisher.height).y <= card.height,
                pick.name + " publisher must fit: " + publisher.mapToItem(card, 0, publisher.height).y
                + " <= " + card.height + "; title=" + title.height + "; publisher=" + publisher.height)
            verify(card.ToolTip.text.indexOf(pick.developer) >= 0, "Full publisher is available on hover")
        }
    }
}
