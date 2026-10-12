import QtQuick

I18nNarrowSmoke {
    function buildScenes() {
        const names = ["settings", "source-add", "source-details", "source-remove"]
        return superScenes().filter(scene => names.includes(scene.name))
    }
}
