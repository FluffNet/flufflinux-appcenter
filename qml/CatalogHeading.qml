import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    required property var catalogPage
    spacing: 8
    GridLayout {
        Layout.fillWidth: true
        columns: !catalogPage.installedView && width < 390 ? 1 : 2
        columnSpacing: 18; rowSpacing: 12
        Label {
            objectName: "catalogTitleLabel"
            Layout.fillWidth: true
            text: catalogPage.installedView ? qsTr("Installed") : window.searchText ? qsTr("Search results") : window.selectedCategory
            color: window.textColor; renderType: Text.QtRendering
            font.pixelSize: 32; font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        FluffComboBox {
            objectName: "installedSort"
            visible: catalogPage.installedView; hoverEnabled: true
            Layout.preferredWidth: 210; Layout.preferredHeight: 42
            model: catalogPage.installedSortOptions
            currentIndex: catalogPage.installedSortIndex
            onActivated: function(index) { catalogPage.installedSortIndex = index }
            Accessible.name: qsTr("Sort installed apps")
        }
        FluffComboBox {
            objectName: "catalogSort"
            visible: catalogPage.catalogView; hoverEnabled: true
            Layout.preferredWidth: 240; Layout.preferredHeight: 42
            model: catalogPage.catalogSortOptions
            currentIndex: catalogPage.activeCatalogSortIndex
            onActivated: function(index) { catalogPage.setCatalogSort(index) }
            Accessible.name: qsTr("Sort applications")
        }
        FluffComboBox {
            objectName: "searchCategoryFilter"
            visible: !catalogPage.installedView && window.searchText.length > 0; hoverEnabled: true
            Layout.preferredWidth: 210; Layout.preferredHeight: 42
            model: catalogPage.categories; textRole: "name"
            currentIndex: catalogPage.categoryIndex(window.searchCategoryFilter)
            displayText: currentIndex === 0 ? "Category: All" : "Category: " + currentText
            onActivated: function(index) { window.searchCategoryFilter = catalogPage.categories[index].name }
        }
    }
    Label {
        objectName: "catalogSortDescription"
        Layout.fillWidth: true
        visible: catalogPage.catalogView && catalogPage.activeCatalogSortIndex >= 2 && text.length > 0
        text: catalogPage.sortDescription
        color: window.mutedTextColor; wrapMode: Text.WordWrap
    }
}
