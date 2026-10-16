import QtQuick

I18nCapture {
    id: capture
    language: "he-bidi"
    expectedSettings: "הגדרות"
    function buildScenes() {
        return capture.baseScenes().filter(scene => ["updates", "source-details", "local-source"].includes(scene.name))
    }
}
