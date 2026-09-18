import QtQuick
import qs.Commons
import "Layouts.js" as Layouts

Item {
  id: root

  property var languageData: null
  property var composeData: null
  property string style: "minimal"
  property string page: "letters"
  property bool shiftActive: false
  property bool capsActive: false
  property bool altgrActive: false
  property bool showAltLevelHint: true
  property string armedDead: ""
  property var activeMods: ({})
  property real keyOpacity: 0.0
  property color keyTint: Color.foreground
  property real labelScale: 1.0
  property real keyRadius: Style.cornerRadius
  property real rowSpacing: Style.space(6)
  property real keySpacing: Style.space(5)
  property real minKeyHeight: Style.space(30)
  property bool showSuperKey: false
  property bool superReady: false

  signal keyPressed(var key)
  signal keyVariantsRequested(var key, rect keyRect)

  readonly property var layoutData: Layouts.get(languageData, style, showSuperKey, composeData)
  readonly property var pageData: layoutData.pages[page] || layoutData.pages.letters
  readonly property int rowCount: pageData.rows.length
  readonly property real keyHeight: rowCount > 0
    ? Math.max(root.minKeyHeight, (root.height - root.rowSpacing * (rowCount - 1)) / rowCount)
    : root.minKeyHeight
  readonly property bool effectiveShift: root.shiftActive !== root.capsActive

  function isActive(key) {
    if (key.type === "shift") return root.shiftActive || root.capsActive
    if (key.type === "capslock") return root.capsActive
    if (root.armedDead && key.dead && key.dead.indexOf(root.armedDead) >= 0) return true
    return !!root.activeMods[key.type]
  }

  Column {
    anchors.fill: parent
    spacing: root.rowSpacing

    Repeater {
      model: root.pageData.rows

      delegate: Item {
        id: rowItem
        required property var modelData

        width: root.width
        height: root.keyHeight

        readonly property var rowKeys: modelData
        readonly property real totalFlex: {
          var sum = 0
          for (var i = 0; i < rowKeys.length; i++) sum += (rowKeys[i].flex || 1)
          return sum
        }
        readonly property real availableWidth: Math.max(0,
          width - root.keySpacing * Math.max(0, rowKeys.length - 1))

        function flexBefore(idx) {
          var sum = 0
          for (var i = 0; i < idx; i++) sum += (rowKeys[i].flex || 1)
          return sum
        }

        Repeater {
          model: rowItem.rowKeys

          delegate: Key {
            required property var modelData
            required property int index

            readonly property real leftPx: rowItem.totalFlex > 0
              ? Math.round(rowItem.flexBefore(index) / rowItem.totalFlex * rowItem.availableWidth) + index * root.keySpacing
              : 0
            readonly property real rightPx: rowItem.totalFlex > 0
              ? Math.round(rowItem.flexBefore(index + 1) / rowItem.totalFlex * rowItem.availableWidth) + index * root.keySpacing
              : 0

            x: leftPx
            y: 0
            width: Math.max(1, rightPx - leftPx)
            height: rowItem.height

            keyData: modelData
            shiftActive: root.altgrActive ? root.shiftActive : root.effectiveShift
            altgrActive: root.altgrActive
            showAltLevelHint: root.showAltLevelHint
            active: root.isActive(modelData)
            restOpacity: root.keyOpacity
            restColor: root.keyTint
            labelScale: root.labelScale
            keyRadius: root.keyRadius
            opacity: (modelData.type === "super" && !root.superReady) ? 0.4 : 1.0
            onActivated: root.keyPressed(modelData)
            onVariantsRequested: function(key, rect) { root.keyVariantsRequested(key, rect) }
          }
        }
      }
    }
  }
}
