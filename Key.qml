import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

CursorSurface {
  id: root

  required property var keyData
  property bool shiftActive: false
  property bool altgrActive: false
  property bool showAltLevelHint: true
  property bool active: false
  property real restOpacity: 0.0
  property color restColor: Color.foreground
  property real labelScale: 1.0
  property real keyRadius: Style.cornerRadius

  signal activated()
  signal variantsRequested(var keyData, rect keyRect)

  readonly property bool isChar: keyData.type === "char"
  readonly property bool repeatable: keyData.type === "backspace"
  readonly property bool hasVariants: root.isChar && !!keyData.variants && keyData.variants.length > 0
  readonly property string displayLabel: {
    if (!isChar) return keyData.label
    if (root.altgrActive) {
      if (root.shiftActive) return keyData.l4 || keyData.l3 || keyData.label
      return keyData.l3 || keyData.label
    }
    return root.shiftActive ? keyData.shift : keyData.label
  }
  readonly property string altLevelHint: (keyData.l3 && keyData.l3 !== keyData.label) ? keyData.l3 : ""
  readonly property string iconSource: keyData.icon || ""
  readonly property bool pressed: mouseArea.pressed
  readonly property bool hovered: hoverHandler.hovered && !pressed

  hasCursor: pressed
  current: root.active
  bordered: true
  radius: root.keyRadius
  color: pressed
    ? fill
    : (current
      ? currentFill
      : (hovered
        ? Style.hoverFillFor(root.restColor, Color.accent)
        : Util.alpha(root.restColor, root.restOpacity)))

  Behavior on color {
    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  function relLuminance(c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
  }
  readonly property color labelColor: {
    if (root.color.a < 0.45) return Color.foreground
    var fillLum = relLuminance(root.color)
    var fgDiff = Math.abs(fillLum - relLuminance(Color.foreground))
    var bgDiff = Math.abs(fillLum - relLuminance(Color.background))
    return bgDiff > fgDiff ? Color.background : Color.foreground
  }

  Image {
    id: superIcon
    visible: root.iconSource !== ""
    anchors.centerIn: parent
    width: Math.round(Style.font.title * root.labelScale * 1.15)
    height: width
    source: root.iconSource
    fillMode: Image.PreserveAspectFit
    sourceSize.width: width * 2
    sourceSize.height: height * 2
    smooth: true

    layer.enabled: true
    layer.effect: MultiEffect {
      colorization: 1.0
      colorizationColor: root.labelColor
    }
  }

  Text {
    visible: root.iconSource === ""
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.displayLabel
    color: root.labelColor
    font.family: Style.font.menuFamily
    font.pixelSize: Math.round(Style.font.title * root.labelScale)
  }

  Text {
    visible: root.showAltLevelHint && root.iconSource === "" && root.altLevelHint !== "" && !root.altgrActive
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Style.space(3)
    anchors.bottomMargin: Style.space(2)
    textFormat: Text.PlainText
    text: root.altLevelHint
    color: root.labelColor
    opacity: 0.45
    font.family: Style.font.menuFamily
    font.pixelSize: Math.round(Style.font.caption * root.labelScale)
  }

  HoverHandler {
    id: hoverHandler
    acceptedDevices: PointerDevice.AllDevices
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    pressAndHoldInterval: 350
    property bool swallowClick: false

    onPressed: {
      swallowClick = false
      if (root.repeatable) {
        root.activated()
        repeatDelay.restart()
      }
    }

    onReleased: {
      repeatDelay.stop()
      repeatTimer.stop()
    }

    onCanceled: {
      repeatDelay.stop()
      repeatTimer.stop()
      swallowClick = true
    }

    onPressAndHold: {
      if (!root.hasVariants) return
      swallowClick = true
      var origin = root.mapToItem(null, 0, 0)
      root.variantsRequested(root.keyData, Qt.rect(origin.x, origin.y, root.width, root.height))
    }

    onClicked: {
      if (swallowClick) { swallowClick = false; return }
      if (root.repeatable) return // already fired on press, see above
      root.activated()
    }
  }

  Timer { id: repeatDelay; interval: 400; onTriggered: repeatTimer.start() }
  Timer { id: repeatTimer; interval: 60; repeat: true; onTriggered: root.activated() }
}
