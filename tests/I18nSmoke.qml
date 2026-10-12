import QtQuick

// Read-only catalog plus simulated queue and dialog states.
I18nCapture {
    id: smoke
    width: 900
    height: 900
    readonly property var languageNames: ({
        "הגדרות":"he", "Einstellungen":"de", "Paramètres":"fr",
        "Configuración":"es", "Definições":"pt", "Configurações":"pt_BR",
        "الإعدادات":"ar", "Настройки":"ru", "Налаштування":"uk",
        "تنظیمات":"fa", "Impostazioni":"it", "设置":"zh_Hans", "設定":"zh_Hant",
        "ترتیبات":"ur", "ترتیباں":"pa_Arab", "امستنې":"ps", "تەڭشەكلەر":"ug",
        "Instellingen":"nl", "Ustawienia":"pl", "설정":"ko", "Ayarlar":"tr",
        "Inställningar":"sv", "Indstillinger":"da", "Asetukset":"fi",
        "Innstillinger":"nb", "Innstillingar":"nn", "Nastavení":"cs",
        "Nastavenia":"sk", "Beállítások":"hu", "Configurări":"ro", "Pengaturan":"id",
        "Ρυθμίσεις":"el", "Configuració":"ca", "Podešavanja":"sr_Latn", "Подешавања":"sr",
        "Instellings":"af"
    })
    language: qsTr("App Center") === "アプリセンター" ? "ja"
        : qsTr("Back") === "Arrere" ? "ca_valencia" : languageNames[qsTr("Settings")] || "unknown"
    expectedSettings: qsTr("Settings")
    function buildScenes() {
        check(language !== "unknown", "the selected translation catalog is active")
        check(rtl === ["he", "ar", "fa", "ur", "pa_Arab", "ps", "ug"].includes(language), "layout direction follows language")
        const names = ["home", "menu", "search", "updates", "queue", "app", "app-details",
                       "permissions", "addons-install-first", "settings", "source-add",
                       "source-details", "source-remove", "uninstall", "about", "file-error"]
        return superScenes().filter(scene => names.includes(scene.name))
    }
    function superScenes() { return smoke.baseScenes() }
    function capture(scene, mode) {
        check(sampleApp.name === "Firefox", "catalog application names are not translated")
        for (const name of ["appActionLabel", "comboDisplayLabel", "updatesNavigationLabel", "appUpdatesTitle"]) {
            const label = findPage(name)
            if (!label || !label.visible || label.width <= 0) continue
            check(label.contentWidth <= label.width + 1, "text fits horizontally: " + name + " / " + language)
            check(label.contentHeight <= label.height + 1, "text fits vertically: " + name + " / " + language)
        }
        if (scene.name === "updates") {
            for (const name of ["appUpdatesTitle", "checkForUpdatesButton", "selectAllUpdates", "installUpdatesButton", "updatesDownloadSummary"]) {
                const item = findPage(name)
                if (!item || !item.visible) continue
                const bounds = item.mapToItem(contentItem, 0, 0)
                check(bounds.x >= -1 && bounds.x + item.width <= width + 1,
                      "updates control fits window: " + name + " / " + language)
            }
        }
        const filename = language + "-smoke-" + mode + "-" + scene.name + ".png"
        find("captureProbe").grabImage(contentItem).save(Qt.resolvedUrl(outputDirectory + filename).toString().replace("file://", ""))
        console.log("I18N_SMOKE", filename)
    }
}
