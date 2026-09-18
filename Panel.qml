import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "Layouts.js" as Layouts
import "Ydotool.js" as Ydotool

Panel {
  id: root
  moduleName: "M44F4.omatouch"
  ipcTarget: "M44F4.omatouch"

  property bool shiftActive: false
  property bool capsActive: false
  property real lastShiftTapTime: 0

  property bool altgrActive: false
  property bool altgrLocked: false
  property real lastAltgrTapTime: 0

  property string armedDead: ""
  readonly property var armedDeadMap: (root.armedDead && root.composeData && root.composeData.rules)
    ? (root.composeData.rules[root.armedDead] || null) : null
  readonly property string armedDeadGlyph: root.armedDeadMap
    ? (root.armedDeadMap[root.armedDead] || root.armedDeadMap[" "] || "◌") : "◌"

  property var variantKey: null
  property rect variantRect: Qt.rect(0, 0, 0, 0)

  property string languageId: ""
  property var languageData: null
  property var availableLanguages: []
  property string languageError: ""
  property bool languageManuallyChosen: false
  property string page: "letters"
  property string keyboardStyle: "minimal"

  property bool ctrlArmed: false
  property bool altArmed: false
  property bool superArmed: false
  property string modBehavior: "oneshot"

  function activeModList() {
    var mods = []
    if (root.ctrlArmed) mods.push("ctrl")
    if (root.altArmed) mods.push("alt")
    if (root.superArmed) mods.push("logo")
    if (root.shiftActive && mods.length > 0) mods.push("shift")
    return mods
  }

  function clearArmedMods() {
    root.ctrlArmed = false
    root.altArmed = false
    root.superArmed = false
    root.shiftActive = false
  }

  readonly property var activeMods: ({ ctrl: root.ctrlArmed, alt: root.altArmed, super: root.superArmed, altgr: root.altgrActive })

  property real cardX: -1
  property real cardY: -1
  property real cardWidthOverride: -1
  property real cardHeightOverride: -1

  property real dragStartX: 0
  property real dragStartY: 0
  property real dragStartWidth: 0
  property real dragStartHeight: 0

  property bool previewActive: false
  property real previewX: 0
  property real previewY: 0
  property real previewWidth: 0
  property real previewHeight: 0

  property bool suppressSizeTransition: false

  readonly property var styleDefaults: Layouts.styleDefaults(root.keyboardStyle)
  readonly property var currentSizeOverride: root.styleSizeOverrides[root.keyboardStyle] || null
  readonly property real defaultCardWidth: {
    var base = Math.min(kbWindow.width - Style.space(16), Style.space(root.styleDefaults.width))
    var ov = root.currentSizeOverride
    return (ov && ov.width) ? Math.min(kbWindow.width - Style.space(16), ov.width) : base
  }
  readonly property real defaultCardHeight: {
    var base = Style.space(root.styleDefaults.height)
    var ov = root.currentSizeOverride
    return (ov && ov.height) ? ov.height : base
  }
  readonly property real effectiveCardWidth: root.cardWidthOverride > 0
    ? Math.max(root.modeMinWidth, root.cardWidthOverride)
    : root.defaultCardWidth
  readonly property real effectiveCardHeight: root.cardHeightOverride > 0
    ? Math.max(root.modeMinHeight, root.cardHeightOverride)
    : root.defaultCardHeight
  readonly property real maxLaunchHeight: kbWindow.height * root.maxCardHeightFrac

  function setStyleSizeOverride(width, height) {
    var o = {}
    for (var k in root.styleSizeOverrides) o[k] = root.styleSizeOverrides[k]
    o[root.keyboardStyle] = { width: width, height: height }
    root.styleSizeOverrides = o
    root.saveGlobalSettings()
  }

  function resetStyleSize() {
    var o = {}
    for (var k in root.styleSizeOverrides) o[k] = root.styleSizeOverrides[k]
    delete o[root.keyboardStyle]
    root.styleSizeOverrides = o
    root.suppressSizeTransition = true
    root.cardWidthOverride = -1
    root.cardHeightOverride = -1
    root.saveGlobalSettings()
    resetTransitionRearmTimer.restart()
  }

  Timer {
    id: resetTransitionRearmTimer
    interval: 0
    onTriggered: root.suppressSizeTransition = false
  }

  readonly property real minCardWidth: Style.space(420)
  readonly property real minCardHeight: Style.space(200)
  readonly property var currentMinSize: Layouts.styleMinSize(root.keyboardStyle)
  readonly property real modeMinWidth: Style.space(root.currentMinSize.width)
  readonly property real modeMinHeight: Style.space(root.currentMinSize.height)
  readonly property real maxCardHeightFrac: 0.7
  readonly property real handleAreaHeight: Style.space(24)
  readonly property real cornerGrabSize: Style.space(34)

  onKeyboardStyleChanged: {
    root.cardX = -1
    root.cardY = -1
    root.cardWidthOverride = -1
    root.cardHeightOverride = -1
    root.saveGlobalSettings()
  }

  property string pendingKeyboardStyle: ""
  property bool styleGhostAnimating: false

  function requestKeyboardStyle(newStyle) {
    if (newStyle === root.keyboardStyle || root.styleSwitching) return
    root.pendingKeyboardStyle = newStyle

    var target = Layouts.styleDefaults(newStyle)
    var maxWidth = Math.max(root.modeMinWidth, kbWindow.width - Style.space(16))
    var targetWidth = Math.min(maxWidth, Style.space(target.width))
    var targetHeight = Style.space(target.height)
    var override = root.styleSizeOverrides[newStyle]
    if (override && override.width) targetWidth = Math.min(maxWidth, override.width)
    if (override && override.height) targetHeight = override.height

    root.previewX = Math.max(0, (kbWindow.width - targetWidth) / 2)
    root.previewY = Math.max(0, kbWindow.height - targetHeight - Style.space(8))
    root.previewWidth = targetWidth
    root.previewHeight = targetHeight
    root.styleGhostAnimating = true
    root.styleSwitching = true
    root.previewActive = true
    styleGhostSettleTimer.restart()
  }

  Timer {
    id: styleGhostSettleTimer
    interval: 240
    onTriggered: {
      root.keyboardStyle = root.pendingKeyboardStyle
      root.cardX = root.previewX
      root.cardY = root.previewY
      root.cardWidthOverride = root.previewWidth
      root.cardHeightOverride = root.previewHeight
      styleGhostReleaseTimer.restart()
    }
  }

  Timer {
    id: styleGhostReleaseTimer
    interval: 20
    onTriggered: {
      root.previewActive = false
      root.styleGhostAnimating = false
      root.styleSwitching = false
    }
  }

  function previewStyleSize(width, height) {
    var w = Math.max(root.modeMinWidth, width)
    var h = Math.max(root.modeMinHeight, height)
    root.previewX = Math.max(0, (kbWindow.width - w) / 2)
    root.previewY = Math.max(0, kbWindow.height - h - Style.space(8))
    root.previewWidth = w
    root.previewHeight = h
    root.previewActive = true
  }

  function commitStyleSize(width, height) {
    var w = Math.max(root.modeMinWidth, width)
    var h = Math.max(root.modeMinHeight, height)
    root.setStyleSizeOverride(w, h)
    root.cardX = -1
    root.cardY = -1
    root.cardWidthOverride = w
    root.cardHeightOverride = h
    root.previewActive = false
  }

  function beginDrag() {
    root.dragStartX = card.x
    root.dragStartY = card.y
    root.dragStartWidth = card.width
    root.dragStartHeight = card.height
    root.previewX = card.x
    root.previewY = card.y
    root.previewWidth = card.width
    root.previewHeight = card.height
    root.previewActive = true
  }

  function commitDrag() {
    root.cardX = root.previewX
    root.cardY = root.previewY
    root.cardWidthOverride = root.previewWidth
    root.cardHeightOverride = root.previewHeight
    root.previewActive = false
  }

  function resizeFromCorner(isRightSide, isBottomSide, tx, ty) {
    var startCenterX = root.dragStartX + root.dragStartWidth / 2
    var isCentered = Math.abs(startCenterX - kbWindow.width / 2) < 1

    var newLeft, newWidth
    if (isCentered) {
      var growthX = isRightSide ? tx : -tx
      var candidateWidth = Math.max(root.modeMinWidth, root.dragStartWidth + 2 * growthX)
      var candidateLeft = startCenterX - candidateWidth / 2
      var candidateRight = startCenterX + candidateWidth / 2

      if (candidateLeft < 0 && candidateRight > kbWindow.width) {
        newLeft = 0
        newWidth = kbWindow.width
      } else if (candidateLeft < 0) {
        newLeft = 0
        newWidth = Math.min(candidateRight, kbWindow.width)
      } else if (candidateRight > kbWindow.width) {
        newWidth = kbWindow.width - candidateLeft
        newLeft = candidateLeft
      } else {
        newLeft = candidateLeft
        newWidth = candidateWidth
      }
    } else if (isRightSide) {
      newWidth = root.dragStartWidth + tx
      var maxFromLeft = kbWindow.width - root.dragStartX - Style.space(8)
      newWidth = Math.max(root.modeMinWidth, Math.min(maxFromLeft, newWidth))
      newLeft = root.dragStartX
    } else {
      var rightEdge = root.dragStartX + root.dragStartWidth
      newWidth = root.dragStartWidth - tx
      newWidth = Math.max(root.modeMinWidth, Math.min(rightEdge - Style.space(8), newWidth))
      newLeft = rightEdge - newWidth
    }
    newWidth = Math.max(root.modeMinWidth, newWidth)
    root.previewWidth = newWidth
    root.previewX = Math.max(0, Math.min(kbWindow.width - newWidth, newLeft))

    var screenCap = kbWindow.screen ? kbWindow.screen.height * root.maxCardHeightFrac : root.dragStartHeight
    var newTop, newHeight
    if (isBottomSide) {
      newHeight = root.dragStartHeight + ty
      var maxFromTop = Math.min(screenCap, kbWindow.height - root.dragStartY - Style.space(8))
      newHeight = Math.max(root.modeMinHeight, Math.min(maxFromTop, newHeight))
      newTop = root.dragStartY
    } else {
      var bottomEdge = root.dragStartY + root.dragStartHeight
      newHeight = root.dragStartHeight - ty
      var maxFromBottom = Math.min(screenCap, bottomEdge - Style.space(8))
      newHeight = Math.max(root.modeMinHeight, Math.min(maxFromBottom, newHeight))
      newTop = bottomEdge - newHeight
    }
    root.previewHeight = newHeight
    root.previewY = Math.max(0, Math.min(kbWindow.height - newHeight, newTop))
  }

  function moveTo(tx, ty) {
    root.previewX = Math.max(0, Math.min(kbWindow.width - root.dragStartWidth, root.dragStartX + tx))
    root.previewY = Math.max(0, Math.min(kbWindow.height - root.dragStartHeight, root.dragStartY + ty))
  }

  function resetLayout() {
    root.cardX = -1
    root.cardY = -1
    root.cardWidthOverride = -1
    root.cardHeightOverride = -1
  }

  function centerHorizontally() {
    root.cardX = Math.max(0, (kbWindow.width - card.width) / 2)
    root.saveGlobalSettings()
  }

  property real cardOpacity: 1.0
  property real keyOpacity: 0.0
  property string keyTintMode: "neutral" // "neutral" | "accent"
  readonly property color keyTintColor: keyTintMode === "accent"
    ? Color.accent
    : Qt.lighter(Color.popups.background, 1.4)
  property string cardBorderWidth: "thin" // "thin" | "bold"
  readonly property real cardBorderWidthPx: cardBorderWidth === "bold"
    ? Math.max(2, Style.space(4))
    : Math.max(1, Style.space(2))
  property real keyLabelScale: 1.0
  property real cardCornerRadius: Style.cornerRadius
  property string radiusScope: "theme"
  property bool showSuperKey: false
  property bool showLanguageSwitcher: true
  property bool showClipboard: true
  property bool showAltLevelHint: true
  property bool onboardingSeen: false
  property bool onboardingOpen: false
  property var styleSizeOverrides: ({})
  property bool settingsOpen: false
  onSettingsOpenChanged: if (settingsOpen) root.reloadLanguages()
  property string settingsTab: "style"
  property bool styleSwitching: false

  function styleDisplayName(style) {
    switch (style) {
    case "minimal": return "Omicro"
    case "simple": return "Omini"
    case "omapad": return "Omapad"
    case "complete": return "Omaplus"
    default: return style
    }
  }

  function superBadge() {
    if (root.superBusy) return "CHECKING\u2026"
    if (root.superReady) return root.showSuperKey ? "ON" : "HIDDEN"
    if (root.superPendingRelogin) return "NOT ACTIVE YET"
    return "OFF"
  }

  function superStatusText() {
    if (root.superBusy) return "Checking\u2026"
    if (root.superReady)
      return root.showSuperKey
        ? "Super shortcuts (Super+Return, workspace switches, \u2026) work from this keyboard."
        : "Installed, but hidden. Turn it back on above to show the Super key on this keyboard."
    if (root.superPendingRelogin)
      return "Setup ran, but the background service isn\u2019t running yet. Tap \u201cCheck Now\u201d. If it still says this after a few tries, re-run the install command to see what went wrong."
    return "Not set up. Tap below to copy a setup script you run yourself in a terminal."
  }

  function superButtonLabel() {
    if (root.superReady || root.superPendingRelogin) return "Get Uninstall Command\u2026"
    return "Get Install Command\u2026"
  }
  property bool keyboardEnabled: true
  property bool activatorOpen: false
  property bool settingsLoaded: false
  property string currentThemeName: ""

  function resetAppearanceSettings() {
    root.cardOpacity = 1.0
    root.keyOpacity = 0.0
    root.keyTintMode = "neutral"
    root.cardBorderWidth = "thin"
    root.keyLabelScale = 1.0
    root.radiusScope = "theme"
    root.cardCornerRadius = Style.cornerRadius
    root.keyboardStyle = "minimal"
    root.modBehavior = "oneshot"
    root.showSuperKey = false
    root.styleSizeOverrides = {}
    root.resetLayout()
  }

  function resetAppearanceForTheme() {
    root.cardOpacity = 1.0
    root.keyOpacity = 0.0
    root.keyTintMode = "neutral"
    root.cardBorderWidth = "thin"
    root.keyLabelScale = 1.0
    root.cardCornerRadius = Style.cornerRadius
    if (root.radiusScope === "theme") root.saveThemeRadius()
    root.saveGlobalSettings()
  }

  function resetAppearanceForAllThemes() {
    root.cardOpacity = 1.0
    root.keyOpacity = 0.0
    root.keyTintMode = "neutral"
    root.cardBorderWidth = "thin"
    root.keyLabelScale = 1.0
    root.radiusScope = "all"
    root.cardCornerRadius = Style.cornerRadius
    root.saveGlobalSettings()
    clearThemeRadiusFilesProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight


  function sendText(str) {
    if (!str) return
    if (root.activeModList().length > 0) { root.sendKeysym(str); return }
    Quickshell.execDetached(["wtype", str])
  }

  function sendKeysym(sym) {
    var mods = root.activeModList()
    if (mods.length === 0) {
      Quickshell.execDetached(["wtype", "-k", Ydotool.wtypeKeyName(sym)])
      return
    }
    if (mods.indexOf("logo") >= 0 && root.superReady) {
      var seq = Ydotool.buildKeySequence(mods, sym)
      if (seq) {
        Quickshell.execDetached(["ydotool", "key"].concat(seq))
        if (root.modBehavior !== "sticky") root.clearArmedMods()
        return
      }
    }
    var args = []
    for (var i = 0; i < mods.length; i++) args.push("-M", mods[i])
    args.push("-k", Ydotool.wtypeKeyName(sym))
    for (var j = mods.length - 1; j >= 0; j--) args.push("-m", mods[j])
    Quickshell.execDetached(["wtype"].concat(args))
    if (root.modBehavior !== "sticky") root.clearArmedMods()
  }

  function keyLevel(key) {
    if (root.altgrActive) return root.shiftActive ? 3 : 2
    var isAlpha = key.label.toLowerCase() !== key.label.toUpperCase()
    return (isAlpha ? (root.capsActive !== root.shiftActive) : root.shiftActive) ? 1 : 0
  }

  function levelChar(key, level) {
    if (level === 0) return key.label
    if (level === 1) return key.shift
    if (level === 2) return key.l3 || key.label
    return key.l4 || key.l3 || key.shift || key.label
  }

  function levelDead(key, level) {
    return (key.dead && key.dead[level]) || ""
  }

  function armDead(name) {
    if (!root.armedDead) { root.armedDead = name; return }
    var hit = root.armedDeadMap ? root.armedDeadMap[name] : ""
    if (hit) { root.sendText(hit); root.armedDead = ""; return }
    root.sendText(root.armedDeadGlyph)
    root.armedDead = name
  }

  function resolveCompose(ch) {
    var map = root.armedDeadMap
    var glyph = root.armedDeadGlyph
    root.armedDead = ""
    if (!map) return glyph + ch
    if (map[ch]) return map[ch]
    var lower = ch.toLowerCase(), upper = ch.toUpperCase()
    if (ch !== lower && map[lower]) return map[lower].toUpperCase()
    if (ch !== upper && map[upper]) return map[upper].toLowerCase()
    return glyph + ch
  }

  function openVariants(key, keyRect) {
    if (!key || !key.variants || key.variants.length === 0) return
    if (root.activeModList().length > 0) return
    root.variantKey = key
    root.variantRect = keyRect
  }

  function closeVariants() {
    root.variantKey = null
  }

  function chooseVariant(ch) {
    var out = (root.shiftActive || root.capsActive) ? ch.toUpperCase() : ch
    if (root.armedDead) out = root.resolveCompose(out)
    root.sendText(out)
    root.closeVariants()
    if (root.shiftActive) root.shiftActive = false
  }

  function pressKey(key) {
    if (!key) return

    if (root.armedDead && (key.type === "enter" || key.type === "tab"
        || key.type === "ctrl" || key.type === "alt" || key.type === "super")) {
      root.sendText(root.armedDeadGlyph)
      root.armedDead = ""
    }

    switch (key.type) {
    case "char":
      var level = root.keyLevel(key)
      var ch = root.levelChar(key, level)
      var dead = root.levelDead(key, level)
      if (dead && root.activeModList().length === 0) {
        root.armDead(dead)
      } else if (root.armedDead) {
        root.sendText(root.resolveCompose(ch))
      } else {
        root.sendText(ch)
      }
      if (root.shiftActive) root.shiftActive = false
      if (root.altgrActive && !root.altgrLocked) root.altgrActive = false
      break
    case "space":
      if (root.armedDead) {
        var spaceOut = root.armedDeadMap ? root.armedDeadMap[" "] : ""
        root.sendText(spaceOut || root.armedDeadGlyph)
        root.armedDead = ""
      } else {
        root.sendText(" ")
      }
      break
    case "backspace":
      if (root.armedDead) {
        root.armedDead = ""
        break
      }
      root.sendKeysym("BackSpace")
      break
    case "enter":
      root.sendKeysym("Return")
      break
    case "tab":
      root.sendKeysym("Tab")
      break
    case "shift":
      if (root.keyboardStyle !== "complete") {
        var now = Date.now()
        var isDoubleTap = (now - root.lastShiftTapTime) < 350
        root.lastShiftTapTime = isDoubleTap ? 0 : now
        if (isDoubleTap) {
          root.capsActive = !root.capsActive
          root.shiftActive = false
          break
        }
        if (root.capsActive) {
          root.capsActive = false
          root.shiftActive = false
          break
        }
      }
      root.shiftActive = !root.shiftActive
      break
    case "capslock":
      root.capsActive = !root.capsActive
      break
    case "ctrl":
      root.ctrlArmed = !root.ctrlArmed
      break
    case "alt":
      root.altArmed = !root.altArmed
      break
    case "altgr":
      var nowAG = Date.now()
      var isDoubleTapAG = (nowAG - root.lastAltgrTapTime) < 350
      root.lastAltgrTapTime = isDoubleTapAG ? 0 : nowAG
      if (isDoubleTapAG) {
        root.altgrLocked = !root.altgrLocked
        root.altgrActive = root.altgrLocked
        break
      }
      if (root.altgrLocked) {
        root.altgrLocked = false
        root.altgrActive = false
        break
      }
      root.altgrActive = !root.altgrActive
      break
    case "super":
      if (root.superReady) root.superArmed = !root.superArmed
      else { root.settingsTab = "advanced"; root.settingsOpen = true }
      break
    case "page":
      root.page = key.target || "letters"
      break
    case "close":
      root.close()
      break
    }
  }

  onKeyboardEnabledChanged: {
    if (!root.keyboardEnabled) root.close()
    root.saveGlobalSettings()
  }

  onOpenedChanged: {
    if (root.opened) {
      if (root.settingsLoaded && !root.languageManuallyChosen) root.detectSystemLanguage()
      if (root.settingsLoaded && !root.onboardingSeen) root.onboardingOpen = true
    } else {
      root.page = "letters"
      root.shiftActive = false
      root.capsActive = false
      root.altgrActive = false
      root.altgrLocked = false
      root.armedDead = ""
      root.variantKey = null
      root.clearArmedMods()
    }
  }

  function openClipboard() {
    Quickshell.execDetached(["omarchy-menu-clipboard"])
  }


  function applyGlobalSettings(raw) {
    try {
      var d = JSON.parse(raw || "{}")
      if (typeof d.cardOpacity === "number") root.cardOpacity = d.cardOpacity
      if (typeof d.keyOpacity === "number") root.keyOpacity = d.keyOpacity
      if (typeof d.keyTintMode === "string") root.keyTintMode = d.keyTintMode
      if (typeof d.keyLabelScale === "number") root.keyLabelScale = d.keyLabelScale
      if (typeof d.radiusScope === "string") root.radiusScope = d.radiusScope
      if (typeof d.keyboardStyle === "string") root.keyboardStyle = d.keyboardStyle
      if (typeof d.modBehavior === "string") root.modBehavior = d.modBehavior
      if (typeof d.keyboardEnabled === "boolean") root.keyboardEnabled = d.keyboardEnabled
      if (typeof d.cardBorderWidth === "string") root.cardBorderWidth = d.cardBorderWidth
      if (typeof d.showSuperKey === "boolean") root.showSuperKey = d.showSuperKey
      if (typeof d.showLanguageSwitcher === "boolean") root.showLanguageSwitcher = d.showLanguageSwitcher
      if (typeof d.showClipboard === "boolean") root.showClipboard = d.showClipboard
      if (typeof d.showAltLevelHint === "boolean") root.showAltLevelHint = d.showAltLevelHint
      if (typeof d.onboardingSeen === "boolean") root.onboardingSeen = d.onboardingSeen
      if (typeof d.gestureEnabled === "boolean") root.gestureEnabled = d.gestureEnabled
      if (typeof d.languageId === "string") root.languageId = d.languageId
      if (typeof d.languageManuallyChosen === "boolean") root.languageManuallyChosen = d.languageManuallyChosen
      if (d.styleSizeOverrides && typeof d.styleSizeOverrides === "object")
        root.styleSizeOverrides = d.styleSizeOverrides
      if (root.radiusScope === "all" && typeof d.cardCornerRadius === "number")
        root.cardCornerRadius = d.cardCornerRadius
    } catch (e) {}
    root.settingsLoaded = true
    if (root.languageId === "") root.detectSystemLanguage()
  }

  function saveGlobalSettings() {
    if (!root.settingsLoaded) return
    var payload = {
      cardOpacity: root.cardOpacity,
      keyOpacity: root.keyOpacity,
      keyTintMode: root.keyTintMode,
      keyLabelScale: root.keyLabelScale,
      radiusScope: root.radiusScope,
      keyboardStyle: root.keyboardStyle,
      modBehavior: root.modBehavior,
      keyboardEnabled: root.keyboardEnabled,
      cardBorderWidth: root.cardBorderWidth,
      showSuperKey: root.showSuperKey,
      showLanguageSwitcher: root.showLanguageSwitcher,
      showClipboard: root.showClipboard,
      showAltLevelHint: root.showAltLevelHint,
      onboardingSeen: root.onboardingSeen,
      gestureEnabled: root.gestureEnabled,
      languageId: root.languageId,
      languageManuallyChosen: root.languageManuallyChosen,
      styleSizeOverrides: root.styleSizeOverrides
    }
    if (root.radiusScope === "all") payload.cardCornerRadius = root.cardCornerRadius
    globalSettingsFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function dismissOnboarding() {
    root.onboardingSeen = true
    root.onboardingOpen = false
    root.saveGlobalSettings()
  }

  function onboardingLanguageSummary() {
    var names = root.availableLanguages.map(function(l) { return l.name })
    if (names.length <= 1) return "You're set up with English to start."
    return "You're set up with " + names.join(" and ") + ", based on your system's language."
  }

  function applyThemeRadius(raw) {
    if (root.radiusScope !== "theme") return
    try {
      var d = JSON.parse(raw || "{}")
      if (typeof d.cardCornerRadius === "number") {
        root.hasThemeRadiusOverride = true
        root.cardCornerRadius = d.cardCornerRadius
        return
      }
    } catch (e) {}
    root.hasThemeRadiusOverride = false
    root.cardCornerRadius = Style.cornerRadius
  }

  function saveThemeRadius() {
    if (!root.settingsLoaded || root.radiusScope !== "theme" || !root.currentThemeName) return
    themeRadiusFile.setText(JSON.stringify({ cardCornerRadius: root.cardCornerRadius }, null, 2) + "\n")
  }

  onCardOpacityChanged: root.saveGlobalSettings()
  onKeyOpacityChanged: root.saveGlobalSettings()
  onKeyTintModeChanged: root.saveGlobalSettings()
  onCardBorderWidthChanged: root.saveGlobalSettings()
  onKeyLabelScaleChanged: root.saveGlobalSettings()
  onRadiusScopeChanged: root.saveGlobalSettings()
  onModBehaviorChanged: root.saveGlobalSettings()
  onShowSuperKeyChanged: root.saveGlobalSettings()
  onShowLanguageSwitcherChanged: root.saveGlobalSettings()
  onShowClipboardChanged: root.saveGlobalSettings()
  onShowAltLevelHintChanged: root.saveGlobalSettings()
  onCardCornerRadiusChanged: {
    if (root.radiusScope === "all") root.saveGlobalSettings()
    else root.saveThemeRadius()
  }

  readonly property string sanitizedThemeName: root.currentThemeName.replace(/[^A-Za-z0-9_-]/g, "_")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omatouch"

  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("Panel.qml"))
    var path = decodeURIComponent(url.indexOf("file://") === 0 ? url.substring(7) : url)
    var tail = "/Panel.qml"
    if (path.length > tail.length && path.lastIndexOf(tail) === path.length - tail.length)
      return path.substring(0, path.length - tail.length)
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/M44F4.omatouch"
  }

  property string appVersion: ""
  property string appId: ""
  FileView {
    id: appManifestFile
    path: root.pluginDir + "/manifest.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.appVersion = data.version || ""
        root.appId = data.id || ""
      } catch (e) {}
    }
  }

  readonly property string updateCommand: "omarchy plugin update " + (root.appId.length > 0 ? root.appId : "M44F4.omatouch")
  property bool updateCommandJustCopied: false
  function copyUpdateCommand() {
    Util.execDetached("printf '%s' " + Util.shellQuote(root.updateCommand) + " | wl-copy")
    root.updateCommandJustCopied = true
    updateCommandCopiedResetTimer.restart()
  }

  Timer {
    id: updateCommandCopiedResetTimer
    interval: 2200
    onTriggered: root.updateCommandJustCopied = false
  }

  property bool superPkg: false
  property bool superRule: false
  property bool superGroupMember: false
  property bool superServiceActive: false
  readonly property bool superReady: root.superPkg && root.superRule && root.superServiceActive
  readonly property bool superPendingRelogin: root.superPkg && root.superRule && !root.superServiceActive
  property bool superBusy: false
  property bool superJustChecked: false
  property string superConfirmMode: ""

  function refreshSuperStatus() {
    root.superBusy = true
    superStatusProc.running = true
  }
  function requestSuperInstall() { root.superConfirmMode = "install"; root.superJustCopied = false }
  function requestSuperUninstall() { root.superConfirmMode = "uninstall"; root.superJustCopied = false }
  function cancelSuperConfirm() { root.superConfirmMode = "" }

  readonly property string superCommand: root.superConfirmMode === "uninstall"
    ? ("bash \"" + root.pluginDir + "/bin/omatouch-super.sh\" uninstall")
    : ("bash \"" + root.pluginDir + "/bin/omatouch-super.sh\" install")

  property bool superJustCopied: false
  function copySuperCommand() {
    Util.execDetached("printf '%s' " + Util.shellQuote(root.superCommand) + " | wl-copy")
    root.superJustCopied = true
    superCopiedResetTimer.restart()
  }

  Timer {
    id: superCopiedResetTimer
    interval: 2200
    onTriggered: root.superJustCopied = false
  }

  property bool gestureUnitInstalled: false
  property bool gestureGroupMember: false
  property bool gestureServiceActive: false
  readonly property bool gestureReady: root.gestureUnitInstalled && root.gestureServiceActive
  readonly property bool gesturePendingRelogin: root.gestureUnitInstalled && root.gestureGroupMember && !root.gestureServiceActive
  property real gestureHeartbeatAgeSec: -1
  property string gestureDevice: ""
  readonly property bool gestureHeartbeatFresh: root.gestureHeartbeatAgeSec >= 0 && root.gestureHeartbeatAgeSec <= 90
  property bool gestureBusy: false
  property bool gestureJustChecked: false
  property string gestureConfirmMode: ""
  property bool gestureEnabled: true

  function refreshGestureStatus() {
    root.gestureBusy = true
    gestureStatusProc.running = true
  }
  function requestGestureInstall() { root.gestureConfirmMode = "install"; root.gestureJustCopied = false }
  function requestGestureUninstall() { root.gestureConfirmMode = "uninstall"; root.gestureJustCopied = false }
  function cancelGestureConfirm() { root.gestureConfirmMode = "" }

  readonly property string gestureCommand: root.gestureConfirmMode === "uninstall"
    ? ("bash \"" + root.pluginDir + "/bin/omatouch-gesture.sh\" uninstall")
    : ("bash \"" + root.pluginDir + "/bin/omatouch-gesture.sh\" install")

  property bool gestureJustCopied: false
  function copyGestureCommand() {
    Util.execDetached("printf '%s' " + Util.shellQuote(root.gestureCommand) + " | wl-copy")
    root.gestureJustCopied = true
    gestureCopiedResetTimer.restart()
  }

  Timer {
    id: gestureCopiedResetTimer
    interval: 2200
    onTriggered: root.gestureJustCopied = false
  }

  function setGestureEnabled(enabled) {
    root.gestureEnabled = enabled
    root.saveGlobalSettings()
    gestureEnabledFile.setText(enabled ? "1" : "0")
  }

  FileView {
    id: gestureEnabledFile
    path: root.stateDir + "/gesture-enabled"
    watchChanges: false
    printErrors: false
  }

  Process {
    id: gestureStatusProc
    command: [root.pluginDir + "/bin/omatouch-gesture-status.sh"]
    stdout: StdioCollector {
      id: gestureStatusStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.gestureBusy = false
      try {
        var data = JSON.parse(String(gestureStatusStdout.text))
        root.gestureUnitInstalled = !!data.unitInstalled
        root.gestureGroupMember = !!data.groupMember
        root.gestureServiceActive = !!data.serviceActive
        root.gestureHeartbeatAgeSec = (typeof data.heartbeatAgeSec === "number") ? data.heartbeatAgeSec : -1
        root.gestureDevice = data.device || ""
      } catch (e) {}
      root.gestureJustChecked = true
      gestureCheckedResetTimer.restart()
    }
  }

  Timer {
    id: gestureCheckedResetTimer
    interval: 1800
    onTriggered: root.gestureJustChecked = false
  }

  function gestureBadge() {
    if (root.gestureBusy) return "CHECKING…"
    if (root.gestureReady) {
      if (!root.gestureEnabled) return "PAUSED"
      return root.gestureHeartbeatFresh ? "ON" : "SILENT"
    }
    if (root.gesturePendingRelogin) return "NOT ACTIVE YET"
    return "OFF"
  }

  function gestureStatusText() {
    if (root.gestureBusy) return "Checking…"
    if (root.gestureReady) {
      if (!root.gestureEnabled)
        return "Installed, but paused. Flip it back on above to start reacting to the gesture again."
      if (!root.gestureHeartbeatFresh)
        return "Running, but not receiving touch events. This usually means the wrong touchscreen was picked. Try re-running the install command to pick again."
      return "Watching " + (root.gestureDevice || "your touchscreen") + ". Tap three fingers on the screen twice, quickly, to open or close the keyboard."
    }
    if (root.gesturePendingRelogin)
      return "Setup ran, but the background service isn’t running yet. Tap “Check Now”. If it still says this after a few tries, re-run the install command to see what went wrong."
    return "Off by default. Tap below to copy a setup script you run yourself in a terminal."
  }

  function gestureButtonLabel() {
    if (root.gestureReady || root.gesturePendingRelogin) return "Get Uninstall Command…"
    return "Get Install Command…"
  }

  property bool languageConfirmOpen: false
  property string languageSearchText: ""
  property var languageLayoutOptions: []
  property bool languageLayoutOptionsLoaded: false
  property bool addLanguageBusy: false
  property string addLanguageStatus: ""

  readonly property var filteredLanguageLayoutOptions: {
    var q = root.languageSearchText.trim().toLowerCase()
    if (q.length === 0) return root.languageLayoutOptions
    return root.languageLayoutOptions.filter(function(o) {
      return o.description.toLowerCase().indexOf(q) === 0
    })
  }

  function ensureLanguageLayoutOptions() {
    if (root.languageLayoutOptionsLoaded) return
    listLayoutsProc.running = true
  }

  Process {
    id: listLayoutsProc
    command: ["python3", root.pluginDir + "/bin/omatouch-lang-gen.py", "--list", "--json"]
    stdout: StdioCollector {
      id: listLayoutsStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      try {
        root.languageLayoutOptions = JSON.parse(String(listLayoutsStdout.text))
      } catch (e) {
        root.languageLayoutOptions = []
      }
      root.languageLayoutOptionsLoaded = true
    }
  }

  function addLanguageFromList(layout, variant, description) {
    if (root.addLanguageBusy) return
    var id = variant ? (layout + "-" + variant) : layout
    root.addLanguageBusy = true
    root.addLanguageStatus = "Adding " + description + "…"
    addLanguageProc.command = ["python3", root.pluginDir + "/bin/omatouch-lang-gen.py",
      "--layout", layout, "--variant", variant, "--id", id, "--name", description]
    addLanguageProc.pendingId = id
    addLanguageProc.pendingDescription = description
    addLanguageProc.running = true
  }

  Process {
    id: addLanguageProc
    property string pendingId: ""
    property string pendingDescription: ""
    onExited: function(exitCode) {
      root.addLanguageBusy = false
      if (exitCode === 0) {
        root.addLanguageStatus = ""
        root.reloadLanguages()
        root.switchLanguage(pendingId)
        root.languageConfirmOpen = false
      } else {
        root.addLanguageStatus = "Couldn't add " + pendingDescription + ". Check it's a valid layout and try again."
      }
    }
  }

  property bool languageRemoveOpen: false

  function removeLanguage(id) {
    if (id === "en-us") return
    removeLanguageProc.command = ["python3", root.pluginDir + "/bin/omatouch-lang-gen.py", "--remove", id]
    removeLanguageProc.running = true
    if (root.languageId === id) {
      root.languageId = "en-us"
      root.saveGlobalSettings()
      stateLanguageFile.reload()
    }
    root.languageRemoveOpen = false
  }

  Process {
    id: removeLanguageProc
    onExited: function(exitCode) { root.reloadLanguages() }
  }

  FileView {
    id: globalSettingsFile
    path: root.stateDir + "/settings.json"
    watchChanges: false
    printErrors: false
    onLoaded: root.applyGlobalSettings(text())
    onLoadFailed: {
      root.settingsLoaded = true
      if (root.languageId === "") root.detectSystemLanguage()
    }
  }

  property string themeRadiusFileTheme: ""

  FileView {
    id: themeRadiusFile
    path: root.sanitizedThemeName.length > 0 ? root.stateDir + "/radius-" + root.sanitizedThemeName + ".json" : ""
    watchChanges: false
    printErrors: false
    onPathChanged: root.themeRadiusFileTheme = root.currentThemeName
    onLoaded: {
      if (root.themeRadiusFileTheme !== root.currentThemeName) return
      root.applyThemeRadius(text())
    }
    onLoadFailed: {
      if (root.themeRadiusFileTheme !== root.currentThemeName) return
      root.applyThemeRadius("")
    }
  }

  readonly property string languagesDir: root.pluginDir + "/languages"
  readonly property string stateLanguagesDir: root.stateDir + "/languages"

  property var bundledLanguageList: []
  property var stateLanguageList: []

  function recomputeAvailableLanguages() {
    var merged = {}
    for (var i = 0; i < root.bundledLanguageList.length; i++) {
      var b = root.bundledLanguageList[i]
      if (b && b.id) merged[b.id] = b
    }
    for (var j = 0; j < root.stateLanguageList.length; j++) {
      var s = root.stateLanguageList[j]
      if (s && s.id) merged[s.id] = s
    }
    var out = []
    for (var id in merged) out.push(merged[id])
    out.sort(function(a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0) })
    root.availableLanguages = out
  }

  FileView {
    id: bundledManifestFile
    path: root.languagesDir + "/index.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.bundledLanguageList = data.languages || []
      } catch (e) {
      }
      root.recomputeAvailableLanguages()
    }
    onLoadFailed: { root.bundledLanguageList = []; root.recomputeAvailableLanguages() }
  }

  FileView {
    id: stateManifestFile
    path: root.stateLanguagesDir + "/index.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.stateLanguageList = data.languages || []
      } catch (e) {}
      root.recomputeAvailableLanguages()
    }
    onLoadFailed: { root.stateLanguageList = []; root.recomputeAvailableLanguages() }
  }

  FileView {
    id: stateLanguageFile
    path: root.languageId.length > 0 ? root.stateLanguagesDir + "/" + root.languageId + ".json" : ""
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        root.languageData = JSON.parse(text())
      } catch (e) {
        bundledLanguageFile.path = root.languagesDir + "/" + root.languageId + ".json"
        bundledLanguageFile.reload()
      }
    }
    onLoadFailed: {
      bundledLanguageFile.path = root.languageId.length > 0 ? (root.languagesDir + "/" + root.languageId + ".json") : ""
      if (bundledLanguageFile.path.length > 0) bundledLanguageFile.reload()
      else root.languageData = null
    }
  }

  FileView {
    id: bundledLanguageFile
    path: ""
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        root.languageData = JSON.parse(text())
      } catch (e) {
        root.handleLanguageLoadFailure()
      }
    }
    onLoadFailed: root.handleLanguageLoadFailure()
  }

  function handleLanguageLoadFailure() {
    root.languageData = null
    if (root.languageId.length === 0 || root.languageId === "en-us") return
    var badId = root.languageId
    root.languageError = "'" + badId + "' couldn't be loaded, so switched back to English."
    root.languageId = "en-us"
    root.saveGlobalSettings()
  }

  property var composeData: null
  FileView {
    id: composeFile
    path: root.languagesDir + "/compose.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      try {
        root.composeData = JSON.parse(text())
      } catch (e) {
        root.composeData = null
      }
    }
    onLoadFailed: root.composeData = null
  }

  function reloadLanguages() {
    bundledManifestFile.reload()
    stateManifestFile.reload()
    if (root.languageId.length > 0) stateLanguageFile.reload()
  }

  function detectSystemLanguage() {
    detectLayoutProc.running = true
  }

  Process {
    id: detectLayoutProc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      id: detectLayoutStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var layout = "us"
      var variant = ""
      try {
        var data = JSON.parse(String(detectLayoutStdout.text))
        var kb = data.keyboards && data.keyboards[0]
        if (kb && kb.layout) {
          layout = String(kb.layout).split(",")[0].trim() || "us"
          variant = String(kb.variant || "").split(",")[0].trim()
        }
      } catch (e) {}
      root.applyDetectedLanguage(layout, variant)
    }
  }

  function applyDetectedLanguage(layout, variant) {
    if (root.languageManuallyChosen) return
    if (layout === "us" && !variant) {
      root.languageId = "en-us"
      root.saveGlobalSettings()
      root.reloadLanguages()
      return
    }
    var id = variant ? (layout + "-" + variant) : layout
    root.languageId = id
    root.saveGlobalSettings()
    generateLanguageProc.command = ["python3", root.pluginDir + "/bin/omatouch-lang-gen.py",
      "--layout", layout, "--variant", variant, "--id", id, "--name", id.toUpperCase()]
    generateLanguageProc.running = true
  }

  Process {
    id: generateLanguageProc
    onExited: function(exitCode) { root.reloadLanguages() }
  }

  function switchLanguage(id) {
    root.languageManuallyChosen = true
    root.languageError = ""
    if (id === root.languageId) { root.saveGlobalSettings(); return }
    root.languageId = id
    root.saveGlobalSettings()
    stateLanguageFile.reload()
  }

  function cycleLanguage() {
    if (root.availableLanguages.length < 2) return
    var ids = root.availableLanguages.map(function(l) { return l.id })
    var idx = ids.indexOf(root.languageId)
    root.switchLanguage(ids[(idx + 1) % ids.length])
  }

  Process {
    id: ensureStateDirProc
    command: ["mkdir", "-p", root.stateDir]
  }

  Process {
    id: clearThemeRadiusFilesProc
    command: ["bash", "-c", "rm -f -- \"$0\"/radius-*.json", root.stateDir]
  }

  Process {
    id: themeNameProc
    command: ["omarchy", "theme", "current"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentThemeName = String(text).trim()
    }
  }

  Connections {
    target: Color
    function onAccentChanged() { themeNameProc.running = true }
  }

  Connections {
    target: Style
    function onCornerRadiusChanged() {
      if (root.radiusScope === "theme" && !root.hasThemeRadiusOverride) root.cardCornerRadius = Style.cornerRadius
    }
  }
  property bool hasThemeRadiusOverride: false

  Timer {
    interval: 4000
    running: true
    repeat: true
    onTriggered: if (!themeNameProc.running) themeNameProc.running = true
  }

  Process {
    id: superStatusProc
    command: [root.pluginDir + "/bin/omatouch-super-status.sh"]
    stdout: StdioCollector {
      id: superStatusStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.superBusy = false
      try {
        var data = JSON.parse(String(superStatusStdout.text))
        root.superPkg = !!data.pkg
        root.superRule = !!data.rule
        root.superGroupMember = !!data.groupMember
        root.superServiceActive = !!data.serviceActive
      } catch (e) {
      }
      root.superJustChecked = true
      superCheckedResetTimer.restart()
    }
  }

  Timer {
    id: superCheckedResetTimer
    interval: 1800
    onTriggered: root.superJustChecked = false
  }

  Component.onCompleted: {
    ensureStateDirProc.running = true
    themeNameProc.running = true
    root.refreshSuperStatus()
    root.refreshGestureStatus()
    gestureEnabledFile.setText(root.gestureEnabled ? "1" : "0")
  }


  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u2328"
    onPressed: {
      if (root.keyboardEnabled) root.toggle()
      else root.activatorOpen = !root.activatorOpen
    }
  }

  PanelWindow {
    id: kbWindow
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omatouch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    property var cardMask: Region {
      x: card.x
      y: card.y
      width: card.width
      height: card.height
    }
    mask: (root.settingsOpen || root.variantKey !== null) ? null : cardMask

    BorderSurface {
      id: card
      visible: root.opened
      width: root.cardWidthOverride > 0
        ? Math.max(root.modeMinWidth, root.cardWidthOverride)
        : root.defaultCardWidth
      height: root.cardHeightOverride > 0
        ? Math.max(root.modeMinHeight, root.cardHeightOverride)
        : root.defaultCardHeight
      x: root.cardX >= 0
        ? Math.max(0, Math.min(kbWindow.width - width, root.cardX))
        : (kbWindow.width - width) / 2
      y: root.cardY >= 0
        ? Math.max(0, Math.min(kbWindow.height - height, root.cardY))
        : Math.max(0, kbWindow.height - height - Style.space(8))
      opacity: (root.previewActive || root.variantKey !== null) ? 0.35 : 1.0
      radius: root.cardCornerRadius
      color: Util.alpha(Color.popups.background, root.cardOpacity)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, root.cardBorderWidthPx)
      padding: Style.space(10)

      Behavior on opacity { NumberAnimation { duration: 90 } }
      Behavior on width { enabled: !root.previewActive && !root.suppressSizeTransition; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on height { enabled: !root.previewActive && !root.suppressSizeTransition; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on x { enabled: !root.previewActive && !root.suppressSizeTransition; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: !root.previewActive && !root.suppressSizeTransition; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

      component HeaderIcon: CursorSurface {
        id: iconRoot
        property string glyph: ""
        property string tooltip: ""
        property string labelText: ""
        signal activated()

        width: labelText.length > 0
          ? Style.space(24) + iconLabel.implicitWidth + Style.space(4)
          : Style.space(24)
        height: Style.space(24)
        radius: Style.cornerRadius
        hasCursor: iconMouse.containsPress

        Row {
          anchors.centerIn: parent
          spacing: Style.space(3)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: iconRoot.glyph
            color: Color.foreground
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: iconLabel
            visible: iconRoot.labelText.length > 0
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: iconRoot.labelText
            color: Color.foreground
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        MouseArea {
          id: iconMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: iconRoot.activated()
        }

        PanelToolTip {
          visible: iconRoot.tooltip !== "" && iconMouse.containsMouse
          text: iconRoot.tooltip
        }
      }

      KeyGrid {
        id: grid
        languageData: root.languageData
        composeData: root.composeData
        style: root.keyboardStyle
        page: root.page
        shiftActive: root.shiftActive
        capsActive: root.capsActive
        altgrActive: root.altgrActive
        showAltLevelHint: root.showAltLevelHint && root.keyboardStyle === "complete"
        armedDead: root.armedDead
        activeMods: root.activeMods
        keyOpacity: root.keyOpacity
        keyTint: root.keyTintColor
        labelScale: root.keyLabelScale
        keyRadius: root.cardCornerRadius
        showSuperKey: root.showSuperKey
        superReady: root.superReady
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: card.padding + root.handleAreaHeight
        anchors.leftMargin: card.padding
        anchors.rightMargin: card.padding
        anchors.bottomMargin: card.padding
        onKeyPressed: function(key) { root.pressKey(key) }
        onKeyVariantsRequested: function(key, rect) { root.openVariants(key, rect) }
      }

      component CornerGrab: Item {
        id: grabRoot
        property bool isRightSide: true
        property bool isBottomSide: true
        width: root.cornerGrabSize
        height: root.cornerGrabSize

        DragHandler {
          id: grabDrag
          target: null
          onActiveChanged: {
            if (active) root.beginDrag()
            else root.commitDrag()
          }
          onTranslationChanged: {
            if (active) root.resizeFromCorner(grabRoot.isRightSide, grabRoot.isBottomSide, translation.x, translation.y)
          }
        }
      }

      CornerGrab { isRightSide: false; isBottomSide: false; anchors.top: parent.top; anchors.left: parent.left }
      CornerGrab { isRightSide: true; isBottomSide: false; anchors.top: parent.top; anchors.right: parent.right }
      CornerGrab { isRightSide: false; isBottomSide: true; anchors.bottom: parent.bottom; anchors.left: parent.left }
      CornerGrab { isRightSide: true; isBottomSide: true; anchors.bottom: parent.bottom; anchors.right: parent.right }

      Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: Style.space(2)
        anchors.leftMargin: root.cornerGrabSize + Style.space(2)
        spacing: Style.space(6)

        HeaderIcon {
          visible: root.showClipboard
          glyph: "󰅇"
          tooltip: "Clipboard history"
          anchors.verticalCenter: parent.verticalCenter
          onActivated: root.openClipboard()
        }

        HeaderIcon {
          visible: root.showLanguageSwitcher
          glyph: "󰗊"
          labelText: root.languageData ? root.languageData.name : ""
          tooltip: root.languageData
            ? ("Language: " + root.languageData.name + (root.availableLanguages.length > 1 ? " (tap to switch)" : ""))
            : "Language"
          anchors.verticalCenter: parent.verticalCenter
          onActivated: root.cycleLanguage()
        }

        HeaderIcon {
          visible: root.armedDead !== ""
          glyph: root.armedDeadGlyph
          tooltip: "Waiting for a letter to accent, tap to cancel"
          anchors.verticalCenter: parent.verticalCenter
          onActivated: root.armedDead = ""
        }
      }

      HeaderIcon {
        glyph: "󰅖"
        tooltip: "Close keyboard"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.space(2)
        anchors.rightMargin: root.cornerGrabSize + Style.space(2)
        onActivated: root.close()
      }

      Row {
        anchors.top: parent.top
        anchors.topMargin: Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(10)

        HeaderIcon {
          glyph: "󰑐"
          tooltip: "Reset size & position"
          anchors.verticalCenter: parent.verticalCenter
          onActivated: root.resetLayout()
        }

        Item {
          id: moveHitArea
          width: Style.space(60)
          height: root.handleAreaHeight
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            width: Style.space(34)
            height: Style.space(5)
            radius: height / 2
            color: Color.foreground
            opacity: moveDrag.active ? 0.55 : 0.3
            anchors.centerIn: parent

            Behavior on opacity { NumberAnimation { duration: 120 } }
          }

          HoverHandler {
            id: moveHover
            acceptedDevices: PointerDevice.AllDevices
          }

          PanelToolTip {
            visible: moveHover.hovered && !moveDrag.active
            text: "Drag to move · double-tap to center"
          }

          DragHandler {
            id: moveDrag
            target: null
            onActiveChanged: {
              if (active) root.beginDrag()
              else root.commitDrag()
            }
            onTranslationChanged: {
              if (active) root.moveTo(translation.x, translation.y)
            }
          }

          TapHandler {
            gesturePolicy: TapHandler.WithinBounds
            onTapped: if (tapCount === 2) root.centerHorizontally()
          }
        }

        HeaderIcon {
          glyph: "󰒓"
          tooltip: "Keyboard settings"
          anchors.verticalCenter: parent.verticalCenter
          onActivated: root.settingsOpen = true
        }
      }
    }

    Rectangle {
      id: dragGhost
      visible: root.previewActive
      color: "transparent"
      border.color: Color.accent
      border.width: Math.max(1, Style.space(2))
      radius: root.cardCornerRadius
      x: root.previewX
      y: root.previewY
      width: root.previewWidth
      height: root.previewHeight

      Behavior on x { enabled: root.styleGhostAnimating; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: root.styleGhostAnimating; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      Behavior on width { enabled: root.styleGhostAnimating; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      Behavior on height { enabled: root.styleGhostAnimating; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }

    Item {
      id: variantLayer
      visible: root.variantKey !== null
      anchors.fill: parent

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeVariants()
      }

      BorderSurface {
        id: variantBubble
        readonly property var variants: root.variantKey ? (root.variantKey.variants || []) : []
        readonly property real cellSize: Style.space(44)
        radius: root.cardCornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.space(6)
        width: Math.max(cellSize, variants.length * cellSize
          + Math.max(0, variants.length - 1) * Style.space(4)) + padding * 2
        height: cellSize + padding * 2

        x: Math.max(Style.space(4), Math.min(kbWindow.width - width - Style.space(4),
             root.variantRect.x + root.variantRect.width / 2 - width / 2))
        y: (root.variantRect.y - height - Style.space(6) >= 0)
             ? root.variantRect.y - height - Style.space(6)
             : root.variantRect.y + root.variantRect.height + Style.space(6)

        MouseArea { anchors.fill: parent } // swallow clicks so they don't dismiss via the backdrop

        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)

          Repeater {
            model: variantBubble.variants

            CursorSurface {
              id: variantCell
              required property string modelData
              width: variantBubble.cellSize
              height: variantBubble.cellSize
              radius: root.cardCornerRadius
              bordered: true
              foreground: Color.foreground
              hasCursor: variantCellMouse.containsPress

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: variantCell.modelData
                color: Color.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
              }

              MouseArea {
                id: variantCellMouse
                anchors.fill: parent
                onClicked: root.chooseVariant(variantCell.modelData)
              }
            }
          }
        }
      }
    }

    Item {
      id: settingsModal
      visible: root.settingsOpen
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.55)
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.settingsOpen = false
      }

      BorderSurface {
        id: settingsDialog
        anchors.centerIn: parent
        width: Math.min(Style.space(520), kbWindow.width - Style.space(48))
        height: Math.min(dialogColumn.implicitHeight + padding * 2, kbWindow.height - Style.space(64))
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.space(14)

        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent } // swallow clicks so they don't dismiss the dialog

        component SettingHeader: Item {
          property string label: ""
          property string valueText: ""
          property var onResetDouble: null
          property real lastResetTapTime: 0
          width: parent ? parent.width : 0
          height: Math.max(hdr.implicitHeight, val.implicitHeight)

          PanelSectionHeader {
            id: hdr
            text: label
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: val
            textFormat: Text.PlainText
            text: valueText
            color: Qt.darker(Color.foreground, 1.4)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }

          MouseArea {
            id: resetArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !!parent.onResetDouble
            onClicked: {
              var now = Date.now()
              var isDoubleTap = (now - parent.lastResetTapTime) < 350
              parent.lastResetTapTime = isDoubleTap ? 0 : now
              if (isDoubleTap && parent.onResetDouble) parent.onResetDouble()
            }
          }

          PanelToolTip {
            visible: resetArea.enabled && resetArea.containsMouse
            text: "Double-tap to reset"
          }
        }

        component OutlinedSlider: CursorSurface {
          property alias slider: sliderInner
          width: parent ? parent.width : 0
          height: sliderInner.implicitHeight + Style.spacing.controlGap
          foreground: Color.foreground
          outline: true

          PanelSlider {
            id: sliderInner
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
          }
        }

        component PillGrid: Grid {
          id: pillGrid
          property var options: []
          property string current: ""
          property int cols: 2
          signal chosen(string value)

          width: parent ? parent.width : 0
          columns: cols
          rowSpacing: Style.spacing.xs
          columnSpacing: Style.spacing.xs
          readonly property real cellWidth: (width - columnSpacing * (cols - 1)) / cols

          Repeater {
            model: pillGrid.options

            Item {
              id: pillCell
              required property var modelData
              width: pillGrid.cellWidth
              height: pillButton.implicitHeight
              clip: true

              TextMetrics {
                id: pillLabelMetrics
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                text: pillCell.modelData.label
                elide: Text.ElideRight
                elideWidth: Math.max(0, pillGrid.cellWidth - Style.spacing.controlPaddingX * 2 - Style.space(4))
              }

              Button {
                id: pillButton
                anchors.left: parent.left
                anchors.right: parent.right
                text: pillLabelMetrics.elidedText
                tooltipText: text !== pillCell.modelData.label ? pillCell.modelData.label : ""
                fontSize: Style.font.caption
                foreground: Color.foreground
                fontFamily: Style.font.menuFamily
                verticalPadding: Style.spacing.xs
                bordered: true
                active: pillGrid.current === modelData.value
                onClicked: pillGrid.chosen(modelData.value)
              }
            }
          }
        }

        component VDivider: Rectangle {
          width: Math.max(1, Style.space(1))
          color: Util.alpha(Color.foreground, 0.18)
        }

        component SliderCell: Column {
          property string label: ""
          property string valueText: ""
          property var onResetDouble: null
          property alias slider: cellSlider.slider
          spacing: Style.space(6)

          SettingHeader {
            label: parent.label
            valueText: parent.valueText
            onResetDouble: parent.onResetDouble
          }

          OutlinedSlider { id: cellSlider }
        }

        component SwitchCell: Column {
          property string label: ""
          property alias options: cellPills.options
          property alias current: cellPills.current
          signal chosen(string value)
          spacing: Style.space(6)

          PanelSectionHeader {
            text: parent.label
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
          }

          PillGrid {
            id: cellPills
            cols: 2
            onChosen: function(v) { parent.chosen(v) }
          }
        }

        component SwitchRow: Item {
          property string label: ""
          property bool checked: false
          property bool switchEnabled: true
          signal toggled(bool value)

          width: parent ? parent.width : 0
          height: Math.max(rowLabel.implicitHeight, rowSwitch.implicitHeight)
          opacity: switchEnabled ? 1.0 : 0.4

          PanelSectionHeader {
            id: rowLabel
            text: parent.label
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          ToggleSwitch {
            id: rowSwitch
            checked: parent.checked
            interactive: parent.switchEnabled
            foreground: Color.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: if (parent.switchEnabled) parent.toggled(!parent.checked)
          }
        }

        component CapabilityCard: Column {
          id: cardRoot
          property string title: ""
          property string statusText: ""
          property bool isInstalled: false
          signal installRequested()
          signal uninstallRequested()
          property bool checkBusy: false
          property bool justChecked: false
          signal checkRequested()
          property bool showToggle: false
          property bool toggleChecked: false
          property bool toggleEnabled: true
          signal toggleRequested(bool value)
          property string badgeText: ""
          property bool badgeActive: false

          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: Math.max(cardTitleRow.implicitHeight, cardControlsRow.implicitHeight)

            Row {
              id: cardTitleRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              PanelSectionHeader {
                text: cardRoot.title
                foreground: Color.foreground
                fontFamily: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              CursorSurface {
                id: actionSurface
                width: actionText.implicitWidth + Style.space(10)
                height: Style.space(20)
                radius: Style.cornerRadius
                foreground: Color.foreground
                hasCursor: actionMouse.containsPress
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: actionText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: cardRoot.isInstalled ? "Uninstall…" : "Install…"
                  color: Color.foreground
                  opacity: 0.55
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: actionMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: cardRoot.isInstalled ? cardRoot.uninstallRequested() : cardRoot.installRequested()
                }
              }
            }

            Row {
              id: cardControlsRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              HeaderIcon {
                glyph: "󰑐"
                tooltip: cardRoot.checkBusy ? "Checking…" : (cardRoot.justChecked ? "Checked ✓" : "Sync status")
                anchors.verticalCenter: parent.verticalCenter
                onActivated: if (!cardRoot.checkBusy) cardRoot.checkRequested()
              }

              Text {
                visible: cardRoot.badgeText.length > 0
                textFormat: Text.PlainText
                text: cardRoot.badgeText
                color: cardRoot.badgeActive ? Color.accent : Color.foreground
                opacity: cardRoot.badgeActive ? 1.0 : 0.5
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                visible: cardRoot.showToggle
                checked: cardRoot.toggleChecked
                interactive: cardRoot.toggleEnabled
                foreground: Color.foreground
                anchors.verticalCenter: parent.verticalCenter
                onToggled: if (cardRoot.toggleEnabled) cardRoot.toggleRequested(!cardRoot.toggleChecked)
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: cardRoot.statusText
            color: Color.foreground
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Column {
          id: dialogColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: settingsDialog.padding
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, dialogCloseIcon.height, heroEnabledSwitch.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󰌌"
              color: Color.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroHelpIcon.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "OmaTouch Settings"
                color: Color.foreground
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: root.styleDisplayName(root.keyboardStyle).toUpperCase() + " LAYOUT"
                color: Qt.darker(Color.foreground, 1.4)
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            CursorSurface {
              id: heroHelpIcon
              width: Style.space(26)
              height: Style.space(26)
              radius: Style.cornerRadius
              hasCursor: heroHelpMouse.containsPress
              anchors.right: heroEnabledSwitch.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "?"
                color: Color.foreground
                opacity: 0.7
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              MouseArea {
                id: heroHelpMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.onboardingOpen = true
              }

              PanelToolTip {
                visible: heroHelpMouse.containsMouse
                text: "Show the welcome guide"
              }
            }

            ToggleSwitch {
              id: heroEnabledSwitch
              checked: root.keyboardEnabled
              foreground: Color.foreground
              anchors.right: dialogCloseIcon.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              onToggled: {
                root.keyboardEnabled = !root.keyboardEnabled
                if (!root.keyboardEnabled) root.settingsOpen = false
              }
            }

            CursorSurface {
              id: dialogCloseIcon
              width: Style.space(26)
              height: Style.space(26)
              radius: Style.cornerRadius
              hasCursor: closeMouse.containsPress
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰅖"
                color: Color.foreground
                opacity: 0.7
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: closeMouse
                anchors.fill: parent
                onClicked: root.settingsOpen = false
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: Color.foreground }

          component TabButton: CursorSurface {
            id: tabBtn
            property string label: ""
            property bool active: false
            signal activated()
            width: parent ? parent.width / 3 : 0
            height: tabLabel.implicitHeight + Style.space(14)
            hasCursor: tabMouse.containsPress
            color: "transparent"

            Text {
              id: tabLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: tabBtn.label
              color: Color.foreground
              opacity: tabBtn.active ? 1.0 : 0.5
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              font.bold: tabBtn.active
              font.letterSpacing: 0.6

              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Rectangle {
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: tabLabel.implicitWidth + Style.space(4)
              height: Math.max(2, Style.space(2))
              radius: height / 2
              color: Color.accent
              opacity: tabBtn.active ? 1.0 : 0.0

              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              onClicked: tabBtn.activated()
            }
          }

          Row {
            width: parent.width

            TabButton {
              label: "MODE"
              active: root.settingsTab === "style"
              onActivated: root.settingsTab = "style"
            }
            TabButton {
              label: "APPEARANCE"
              active: root.settingsTab === "appearance"
              onActivated: root.settingsTab = "appearance"
            }
            TabButton {
              label: "ADVANCED"
              active: root.settingsTab === "advanced"
              onActivated: root.settingsTab = "advanced"
            }
          }

          PanelSeparator { width: parent.width; foreground: Color.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.settingsTab === "style"

            PillGrid {
              cols: 4
              current: root.keyboardStyle
              options: [
                { value: "minimal", label: "Omicro" },
                { value: "simple", label: "Omini" },
                { value: "omapad", label: "Omapad" },
                { value: "complete", label: "Omaplus" }
              ]
              onChosen: function(v) { root.requestKeyboardStyle(v) }
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            PanelSectionHeader {
              text: "LAUNCH SIZE (" + root.styleDisplayName(root.keyboardStyle).toUpperCase() + ")"
              foreground: Color.foreground
              fontFamily: Style.font.menuFamily
            }

            Grid {
              id: sizeGrid
              width: parent.width
              columns: 2
              rowSpacing: Style.space(10)
              columnSpacing: Style.space(10)
              readonly property real cellWidth: (width - columnSpacing) / 2

              SliderCell {
                width: sizeGrid.cellWidth
                label: "WIDTH"
                valueText: Math.round(slider.dragging ? slider.liveValue : root.effectiveCardWidth) + "px"
                onResetDouble: function() { root.resetStyleSize() }
                slider.minimum: root.modeMinWidth
                slider.maximum: Math.max(root.modeMinWidth, kbWindow.width - Style.space(16))
                slider.step: 4
                slider.integer: true
                slider.value: root.effectiveCardWidth
                slider.onMoved: function(v) { root.previewStyleSize(v, root.effectiveCardHeight) }
                slider.onReleased: function(v) { root.commitStyleSize(v, root.effectiveCardHeight) }
              }

              SliderCell {
                width: sizeGrid.cellWidth
                label: "HEIGHT"
                valueText: Math.round(slider.dragging ? slider.liveValue : root.effectiveCardHeight) + "px"
                onResetDouble: function() { root.resetStyleSize() }
                slider.minimum: root.modeMinHeight
                slider.maximum: Math.max(root.modeMinHeight, root.maxLaunchHeight)
                slider.step: 4
                slider.integer: true
                slider.value: root.effectiveCardHeight
                slider.onMoved: function(v) { root.previewStyleSize(root.effectiveCardWidth, v) }
                slider.onReleased: function(v) { root.commitStyleSize(root.effectiveCardWidth, v) }
              }
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            PanelSectionHeader {
              text: "LANGUAGE"
              foreground: Color.foreground
              fontFamily: Style.font.menuFamily
            }

            PillGrid {
              cols: 4
              current: root.languageId
              options: root.availableLanguages.map(function(l) { return { value: l.id, label: l.name } })
              onChosen: function(v) { root.switchLanguage(v) }
            }

            Text {
              width: parent.width
              visible: root.languageError.length > 0
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: root.languageError
              color: Color.foreground
              opacity: 0.7
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Add a Language\u2026"
                fontSize: Style.font.caption
                foreground: Color.foreground
                fontFamily: Style.font.menuFamily
                verticalPadding: Style.spacing.sm
                bordered: true
                onClicked: root.languageConfirmOpen = true
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Remove a Language\u2026"
                fontSize: Style.font.caption
                foreground: Color.foreground
                fontFamily: Style.font.menuFamily
                verticalPadding: Style.spacing.sm
                bordered: true
                enabled: root.availableLanguages.length > 1
                onClicked: root.languageRemoveOpen = true
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.settingsTab === "appearance"

            Grid {
              id: sliderGrid
              width: parent.width
              columns: 2
              rowSpacing: Style.space(10)
              columnSpacing: Style.space(10)
              readonly property real cellWidth: (width - columnSpacing) / 2

              SliderCell {
                width: sliderGrid.cellWidth
                label: "BACKGROUND"
                valueText: Math.round((slider.dragging ? slider.liveValue : root.cardOpacity) * 100) + "%"
                onResetDouble: function() { root.cardOpacity = 1.0 }
                slider.minimum: 0.3
                slider.maximum: 1.0
                slider.step: 0.05
                slider.value: root.cardOpacity
                slider.onMoved: function(v) { root.cardOpacity = v }
              }

              SliderCell {
                width: sliderGrid.cellWidth
                label: "KEY FILL"
                valueText: Math.round((slider.dragging ? slider.liveValue : root.keyOpacity) * 100) + "%"
                onResetDouble: function() { root.keyOpacity = 0.0 }
                slider.minimum: 0.0
                slider.maximum: 1.0
                slider.step: 0.05
                slider.value: root.keyOpacity
                slider.onMoved: function(v) { root.keyOpacity = v }
              }

              SliderCell {
                width: sliderGrid.cellWidth
                label: "RADIUS"
                valueText: Math.round(slider.dragging ? slider.liveValue : root.cardCornerRadius) + "px"
                onResetDouble: function() { root.cardCornerRadius = Style.cornerRadius }
                slider.minimum: 0
                slider.maximum: 28
                slider.step: 1
                slider.integer: true
                slider.value: root.cardCornerRadius
                slider.onMoved: function(v) { root.cardCornerRadius = v }
              }

              SliderCell {
                width: sliderGrid.cellWidth
                label: "KEY LABEL SIZE"
                valueText: Math.round((slider.dragging ? slider.liveValue : root.keyLabelScale) * 100) + "%"
                onResetDouble: function() { root.keyLabelScale = 1.0 }
                slider.minimum: 0.7
                slider.maximum: 1.6
                slider.step: 0.05
                slider.value: root.keyLabelScale
                slider.onMoved: function(v) { root.keyLabelScale = v }
              }
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            Row {
              id: colorRow
              width: parent.width
              height: Math.max(keyColorCell.implicitHeight, cardBorderCell.implicitHeight)
              spacing: Style.space(10)

              SwitchCell {
                id: keyColorCell
                width: (colorRow.width - colorRow.spacing * 2 - Style.space(1)) / 2
                label: "KEY COLOR"
                current: root.keyTintMode
                options: [
                  { value: "neutral", label: "Neutral" },
                  { value: "accent", label: "Accent" }
                ]
                onChosen: function(v) { root.keyTintMode = v }
              }

              VDivider { height: colorRow.height }

              SwitchCell {
                id: cardBorderCell
                width: (colorRow.width - colorRow.spacing * 2 - Style.space(1)) / 2
                label: "CARD BORDER"
                current: root.cardBorderWidth
                options: [
                  { value: "thin", label: "Thin" },
                  { value: "bold", label: "Bold" }
                ]
                onChosen: function(v) { root.cardBorderWidth = v }
              }
            }

            SwitchCell {
              width: parent.width
              label: "SAVE TO"
              current: root.radiusScope
              options: [
                { value: "theme", label: "This theme" },
                { value: "all", label: "All themes" }
              ]
              onChosen: function(v) { root.radiusScope = v }
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Reset This Theme"
                fontSize: Style.font.caption
                foreground: Color.foreground
                fontFamily: Style.font.menuFamily
                verticalPadding: Style.spacing.sm
                bordered: true
                onClicked: root.resetAppearanceForTheme()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Reset All Themes"
                fontSize: Style.font.caption
                foreground: Color.foreground
                fontFamily: Style.font.menuFamily
                verticalPadding: Style.spacing.sm
                bordered: true
                onClicked: root.resetAppearanceForAllThemes()
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.settingsTab === "advanced"

            Row {
              width: parent.width
              spacing: Style.space(10)

              SwitchRow {
                width: (parent.width - parent.spacing) / 2
                label: "SHOW CLIPBOARD"
                checked: root.showClipboard
                onToggled: function(v) { root.showClipboard = v }
              }

              SwitchRow {
                width: (parent.width - parent.spacing) / 2
                label: "SHOW LANGUAGE SWITCHER"
                checked: root.showLanguageSwitcher
                onToggled: function(v) { root.showLanguageSwitcher = v }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              SwitchRow {
                width: (parent.width - parent.spacing) / 2
                label: "ALTGR CHARACTER HINT"
                checked: root.showAltLevelHint
                onToggled: function(v) { root.showAltLevelHint = v }
              }

              SwitchRow {
                width: (parent.width - parent.spacing) / 2
                label: "STAY ON (CTRL/ALT/SUPER)"
                checked: root.modBehavior === "sticky"
                onToggled: function(v) { root.modBehavior = v ? "sticky" : "oneshot" }
              }
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            CapabilityCard {
              title: "SUPER KEY SUPPORT"
              statusText: root.superStatusText()
              isInstalled: root.superReady || root.superPendingRelogin
              onInstallRequested: root.requestSuperInstall()
              onUninstallRequested: root.requestSuperUninstall()
              checkBusy: root.superBusy
              justChecked: root.superJustChecked
              onCheckRequested: root.refreshSuperStatus()
              badgeText: root.superBadge()
              badgeActive: root.superReady && root.showSuperKey
              showToggle: true
              toggleChecked: root.showSuperKey
              toggleEnabled: true
              onToggleRequested: function(v) { root.showSuperKey = v }
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            CapabilityCard {
              title: "THREE-FINGER GESTURE"
              statusText: root.gestureStatusText()
              isInstalled: root.gestureReady || root.gesturePendingRelogin
              onInstallRequested: root.requestGestureInstall()
              onUninstallRequested: root.requestGestureUninstall()
              checkBusy: root.gestureBusy
              justChecked: root.gestureJustChecked
              onCheckRequested: root.refreshGestureStatus()
              badgeText: root.gestureBadge()
              badgeActive: root.gestureReady && root.gestureEnabled && root.gestureHeartbeatFresh
              showToggle: true
              toggleChecked: root.gestureEnabled
              toggleEnabled: root.gestureReady
              onToggleRequested: function(v) { root.setGestureEnabled(v) }
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            SettingHeader {
              width: parent.width
              label: "ABOUT"
              valueText: "OmaTouch" + (root.appVersion.length > 0 ? " " + root.appVersion : "")
            }

            CommandBlock {
              command: root.updateCommand
              justCopied: root.updateCommandJustCopied
              onCopyRequested: root.copyUpdateCommand()
            }

            PanelSeparator { width: parent.width; foreground: Color.foreground }

            Button {
              width: parent.width
              text: "Reset All Settings To Defaults"
              fontSize: Style.font.caption
              foreground: Color.foreground
              fontFamily: Style.font.menuFamily
              verticalPadding: Style.spacing.sm
              bordered: true
              onClicked: root.resetAppearanceSettings()
            }
          }
        }
      }
    }

    Item {
      id: superConfirmModal
      visible: root.superConfirmMode !== ""
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.6)
      }

      MouseArea { anchors.fill: parent; onClicked: root.cancelSuperConfirm() }

      BorderSurface {
        id: superConfirmDialog
        anchors.centerIn: parent
        width: Math.min(Style.space(460), kbWindow.width - Style.space(48))
        height: superConfirmColumn.implicitHeight + padding * 2
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.space(16)

        MouseArea { anchors.fill: parent }

        component CommandBlock: Item {
          id: blockRoot
          property string command: ""
          property bool justCopied: false
          signal copyRequested()

          width: parent ? parent.width : 0
          height: Math.max(blockText.implicitHeight, copyIcon.height + Style.space(12)) + Style.space(12)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Util.alpha(Color.foreground, 0.06)
            border.width: Math.max(1, Style.space(1))
            border.color: Util.alpha(Color.foreground, 0.18)
          }

          Text {
            id: blockText
            anchors.left: parent.left
            anchors.right: copyIcon.left
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            anchors.rightMargin: Style.space(6)
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            text: blockRoot.command
            color: Color.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.caption
          }

          CursorSurface {
            id: copyIcon
            width: Style.space(26)
            height: Style.space(26)
            radius: Style.cornerRadius
            foreground: Color.foreground
            hasCursor: copyIconMouse.containsPress
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(6)

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: blockRoot.justCopied ? "󰄬" : "󰆏"
              color: Color.foreground
              opacity: 0.75
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: copyIconMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: blockRoot.copyRequested()
            }

            PanelToolTip {
              visible: copyIconMouse.containsMouse
              text: blockRoot.justCopied ? "Copied!" : "Copy"
            }
          }
        }

        Column {
          id: superConfirmColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(16)
          spacing: Style.space(12)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.superConfirmMode === "uninstall" ? "Turn Off Super Key Support" : "Enable Super Key Support"
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Copy the command below and run it in your own terminal."
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.superConfirmMode === "uninstall"
              ? "It removes:\n• the udev rule and background service\n• your account's ‘omatouch’ group membership\n• the ydotool package"
              : "It installs:\n• ydotool (official Arch package)\n• a dedicated ‘omatouch’ group + one udev rule\n• a small background service"
            color: Color.foreground
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            lineHeight: 1.3
          }

          PanelSectionHeader {
            text: "TERMINAL COMMAND"
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
          }

          CommandBlock {
            command: root.superCommand
            justCopied: root.superJustCopied
            onCopyRequested: root.copySuperCommand()
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "It's a plain shell script, so open it in a text editor first if you want to see what it does. Run it in your terminal, enter your password when it asks, then come back and tap \u201cCheck Now\u201d."
            color: Color.foreground
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            width: parent.width
            text: "Close"
            fontSize: Style.font.caption
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
            verticalPadding: Style.spacing.sm
            bordered: true
            onClicked: root.cancelSuperConfirm()
          }
        }
      }
    }

    Item {
      id: languageConfirmModal
      visible: root.languageConfirmOpen
      anchors.fill: parent
      onVisibleChanged: {
        if (visible) root.ensureLanguageLayoutOptions()
        else {
          root.languageSearchText = ""
          root.addLanguageStatus = ""
        }
      }

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.6)
      }

      MouseArea { anchors.fill: parent; onClicked: root.languageConfirmOpen = false }

      BorderSurface {
        id: languageConfirmDialog
        anchors.centerIn: parent
        width: Math.min(Style.space(480), kbWindow.width - Style.space(48))
        height: Math.min(languageConfirmColumn.implicitHeight + padding * 2, kbWindow.height - Style.space(64))
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.space(16)

        MouseArea { anchors.fill: parent }

        Column {
          id: languageConfirmColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: languageConfirmDialog.padding
          spacing: Style.space(10)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Add a Language"
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.languageLayoutOptionsLoaded
              ? "Tap a letter to jump to it, or just scroll, then tap a layout to add it."
              : "Loading the list of layouts\u2026"
            color: Color.foreground
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            lineHeight: 1.3
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              readonly property string letters: "ABCDEFGHIJKLM"

              Repeater {
                model: parent.letters.length
                delegate: Rectangle {
                  required property int index
                  readonly property string letter: parent.letters[index]
                  readonly property bool active: root.languageSearchText === letter.toLowerCase()
                  width: parent.width / parent.letters.length
                  height: Style.space(30)
                  color: active
                    ? Style.selectedFillFor(Color.foreground, Color.accent)
                    : (letterMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
                  Behavior on color { ColorAnimation { duration: 80 } }

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.letter
                    color: Color.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: letterMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.languageSearchText = parent.active ? "" : parent.letter.toLowerCase()
                  }
                }
              }
            }

            Row {
              width: parent.width
              readonly property string letters: "NOPQRSTUVWXYZ"

              Repeater {
                model: parent.letters.length
                delegate: Rectangle {
                  required property int index
                  readonly property string letter: parent.letters[index]
                  readonly property bool active: root.languageSearchText === letter.toLowerCase()
                  width: parent.width / parent.letters.length
                  height: Style.space(30)
                  color: active
                    ? Style.selectedFillFor(Color.foreground, Color.accent)
                    : (letterMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
                  Behavior on color { ColorAnimation { duration: 80 } }

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.letter
                    color: Color.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: letterMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.languageSearchText = parent.active ? "" : parent.letter.toLowerCase()
                  }
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(260)
            radius: Style.cornerRadius
            color: Util.alpha(Color.foreground, 0.03)
            border.width: Math.max(1, Style.space(1))
            border.color: Util.alpha(Color.foreground, 0.14)
            clip: true

            ListView {
              anchors.fill: parent
              anchors.margins: Math.max(1, Style.space(1))
              clip: true
              model: root.filteredLanguageLayoutOptions
              boundsBehavior: Flickable.StopAtBounds
              spacing: 0

              Text {
                anchors.centerIn: parent
                visible: root.languageLayoutOptionsLoaded && root.filteredLanguageLayoutOptions.length === 0
                textFormat: Text.PlainText
                text: "No layouts match \u201c" + root.languageSearchText + "\u201d"
                color: Color.foreground
                opacity: 0.5
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }

              delegate: Item {
                id: layoutRow
                required property var modelData
                required property int index
                width: ListView.view.width
                height: Style.space(38)

                readonly property bool isLast: index === root.filteredLanguageLayoutOptions.length - 1

                Rectangle {
                  anchors.fill: parent
                  color: layoutRowMouse.pressed
                    ? Style.selectedFillFor(Color.foreground, Color.accent)
                    : (layoutRowMouse.containsMouse
                      ? Style.hoverFillFor(Color.foreground, Color.accent)
                      : "transparent")
                  Behavior on color { ColorAnimation { duration: 80 } }
                }

                Rectangle {
                  visible: !layoutRow.isLast
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  height: Math.max(1, Style.space(1))
                  color: Util.alpha(Color.foreground, 0.08)
                }

                Row {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Text {
                    width: parent.width - trailingInfo.implicitWidth - parent.spacing
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: layoutRow.modelData.description
                    color: Color.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }

                  Row {
                    id: trailingInfo
                    spacing: Style.space(6)

                    Text {
                      visible: layoutRow.modelData.nativeScript === false
                      textFormat: Text.PlainText
                      text: "NOT SUPPORTED"
                      color: Color.foreground
                      opacity: 0.5
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      id: codeLabel
                      textFormat: Text.PlainText
                      text: layoutRow.modelData.variant
                        ? layoutRow.modelData.layout + " (" + layoutRow.modelData.variant + ")"
                        : layoutRow.modelData.layout
                      color: Color.foreground
                      opacity: 0.45
                      font.family: Style.font.menuFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  id: layoutRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.addLanguageFromList(layoutRow.modelData.layout, layoutRow.modelData.variant, layoutRow.modelData.description)
                }
              }
            }
          }

          Text {
            id: addLanguageStatusText
            width: parent.width
            visible: root.addLanguageStatus.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.addLanguageStatus
            color: Color.foreground
            opacity: 0.8
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: languageConfirmCloseButton
            width: parent.width
            text: "Close"
            fontSize: Style.font.caption
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
            verticalPadding: Style.spacing.sm
            bordered: true
            onClicked: root.languageConfirmOpen = false
          }
        }
      }
    }

    Item {
      id: languageRemoveModal
      visible: root.languageRemoveOpen
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.6)
      }

      MouseArea { anchors.fill: parent; onClicked: root.languageRemoveOpen = false }

      BorderSurface {
        id: languageRemoveDialog
        anchors.centerIn: parent
        width: Math.min(Style.space(380), kbWindow.width - Style.space(48))
        height: languageRemoveColumn.implicitHeight + padding * 2
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.space(16)

        MouseArea { anchors.fill: parent }

        Column {
          id: languageRemoveColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(16)
          spacing: Style.space(12)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Remove a Language"
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Tap one to remove it. You can always add it back later."
            color: Color.foreground
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          PillGrid {
            cols: 3
            current: ""
            options: root.availableLanguages
              .filter(function(l) { return l.id !== "en-us" })
              .map(function(l) { return { value: l.id, label: l.name } })
            onChosen: function(v) { root.removeLanguage(v) }
          }

          Button {
            width: parent.width
            text: "Close"
            fontSize: Style.font.caption
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
            verticalPadding: Style.spacing.sm
            bordered: true
            onClicked: root.languageRemoveOpen = false
          }
        }
      }
    }

    Item {
      id: gestureConfirmModal
      visible: root.gestureConfirmMode !== ""
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.6)
      }

      MouseArea { anchors.fill: parent; onClicked: root.cancelGestureConfirm() }

      BorderSurface {
        id: gestureConfirmDialog
        anchors.centerIn: parent
        width: Math.min(Style.space(460), kbWindow.width - Style.space(48))
        height: gestureConfirmColumn.implicitHeight + padding * 2
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.space(16)

        MouseArea { anchors.fill: parent }

        Column {
          id: gestureConfirmColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(16)
          spacing: Style.space(12)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.gestureConfirmMode === "uninstall" ? "Turn Off Three-Finger Gesture" : "Enable Three-Finger Gesture"
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Copy the command below and run it in your own terminal."
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.gestureConfirmMode === "uninstall"
              ? "It removes:\n• the background service\n• your account's ‘input’ group membership, if this script was the one that added it"
              : "It installs:\n• your account into the standard ‘input’ group (the one that already owns touch devices)\n• a small background service watching for the gesture"
            color: Color.foreground
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            lineHeight: 1.3
          }

          PanelSectionHeader {
            text: "TERMINAL COMMAND"
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
          }

          CommandBlock {
            command: root.gestureCommand
            justCopied: root.gestureJustCopied
            onCopyRequested: root.copyGestureCommand()
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "It's a plain shell script, so open it in a text editor first if you want to see what it does. Run it in your terminal, enter your password when it asks, then come back and tap “Check Now”."
            color: Color.foreground
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            width: parent.width
            text: "Close"
            fontSize: Style.font.caption
            foreground: Color.foreground
            fontFamily: Style.font.menuFamily
            verticalPadding: Style.spacing.sm
            bordered: true
            onClicked: root.cancelGestureConfirm()
          }
        }
      }
    }

    Item {
      id: onboardingModal
      visible: root.onboardingOpen
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.6)
      }

      MouseArea { anchors.fill: parent }

      BorderSurface {
        id: onboardingDialog
        anchors.centerIn: parent
        width: Math.min(Style.space(460), kbWindow.width - Style.space(48))
        height: onboardingColumn.implicitHeight + padding * 2
        radius: Style.cornerRadius
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        padding: Style.space(16)

        MouseArea { anchors.fill: parent }

        Column {
          id: onboardingColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: onboardingDialog.padding
          spacing: Style.space(12)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Welcome to OmaTouch"
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "It works right now. No setup needed."
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.onboardingLanguageSummary()
            color: Color.foreground
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            lineHeight: 1.3
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Super key shortcuts and the three-finger gesture are optional. Find them in Settings, under Advanced. Nothing installs unless you run a command yourself."
            color: Color.foreground
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            lineHeight: 1.3
          }

          Row {
            width: parent.width
            spacing: Style.space(10)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Add a Language…"
              fontSize: Style.font.caption
              foreground: Color.foreground
              fontFamily: Style.font.menuFamily
              verticalPadding: Style.spacing.sm
              bordered: true
              onClicked: {
                root.dismissOnboarding()
                root.languageConfirmOpen = true
              }
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: "Got It"
              fontSize: Style.font.caption
              foreground: Color.foreground
              fontFamily: Style.font.menuFamily
              verticalPadding: Style.spacing.sm
              onClicked: root.dismissOnboarding()
            }
          }
        }
      }
    }
  }

  QtObject {
    id: activatorOwner
    function close() { root.activatorOpen = false }
  }

  KeyboardPanel {
    id: activatorPanel
    anchorItem: button
    owner: activatorOwner
    bar: root.bar
    open: root.activatorOpen
    contentWidth: activatorPanel.fittedContentWidth(Style.space(340))
    contentHeight: activatorPanel.fittedContentHeight(activatorColumn.implicitHeight)

    Column {
      id: activatorColumn
      anchors.fill: parent
      spacing: Style.space(12)

      PanelHero {
        title: "OmaTouch"
        meta: root.keyboardEnabled ? "ENABLED" : "TURNED OFF"
        foreground: root.bar ? root.bar.foreground : Color.foreground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.menuFamily

        iconComponent: Text {
          textFormat: Text.PlainText
          text: "󰌌"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily
          font.pixelSize: Style.font.display
          opacity: root.keyboardEnabled ? 1.0 : 0.5
        }

        trailingControl: ToggleSwitch {
          checked: root.keyboardEnabled
          foreground: root.bar ? root.bar.foreground : Color.foreground
          onToggled: {
            root.keyboardEnabled = !root.keyboardEnabled
            if (root.keyboardEnabled) {
              root.activatorOpen = false
              root.open()
            }
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: root.bar ? root.bar.foreground : Color.foreground }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Turn on to bring the on-screen keyboard back. The bar icon then opens it as usual."
        color: root.bar ? root.bar.foreground : Color.foreground
        opacity: 0.6
        font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
