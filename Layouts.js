.pragma library


var SUPER_ICON = "file:///usr/share/icons/hicolor/256x256/apps/omarchy.png"

function charKey(label, shiftLabel, flex) {
  return { type: "char", label: label, shift: shiftLabel || label.toUpperCase(), flex: flex }
}

function pageKey(label, target, flex) {
  return { type: "page", label: label, target: target, flex: flex || 1.4 }
}

function modKey(type, label, flex) {
  return { type: type, label: label, flex: flex || 0.9 }
}

function superKey(flex) {
  return { type: "super", label: "", icon: SUPER_ICON, flex: flex || 0.9 }
}

var STYLES = ["minimal", "simple", "omapad", "complete"]

function rowFlexSum(row) {
  var sum = 0
  for (var i = 0; i < row.length; i++) sum += (row[i].flex || 1)
  return sum
}

function styleDefaults(style) {
  var rows = buildLetterRows(style)
  var maxFlex = 0
  var maxCount = 0
  for (var i = 0; i < rows.length; i++) {
    var flex = rowFlexSum(rows[i])
    if (flex > maxFlex) maxFlex = flex
    if (rows[i].length > maxCount) maxCount = rows[i].length
  }
  var widthUnit = style === "complete" ? 68 : 82
  var width = maxFlex * widthUnit + Math.max(0, maxCount - 1) * 5 + 20
  var height = rows.length * 56 + Math.max(0, rows.length - 1) * 6 + 20 + 24
  if (rows.length > 4) height += (rows.length - 4) * 36
  return { width: width, height: height }
}

function styleMinSize(style) {
  var rows = buildLetterRows(style)
  var maxFlex = 0
  var maxCount = 0
  for (var i = 0; i < rows.length; i++) {
    var flex = rowFlexSum(rows[i])
    if (flex > maxFlex) maxFlex = flex
    if (rows[i].length > maxCount) maxCount = rows[i].length
  }
  var widthUnit = (style === "complete" ? 68 : 82) * 0.5
  var width = maxFlex * widthUnit + Math.max(0, maxCount - 1) * 5 + 20
  var height = rows.length * 30 + Math.max(0, rows.length - 1) * 6 + 20 + 24
  return { width: width, height: height }
}

var US_FALLBACK_KEYS = {
  AE01: ["1", "!"], AE02: ["2", "@"], AE03: ["3", "#"], AE04: ["4", "$"],
  AE05: ["5", "%"], AE06: ["6", "^"], AE07: ["7", "&"], AE08: ["8", "*"],
  AE09: ["9", "("], AE10: ["0", ")"], AE11: ["-", "_"], AE12: ["=", "+"],
  AD01: ["q", "Q"], AD02: ["w", "W"], AD03: ["e", "E"], AD04: ["r", "R"],
  AD05: ["t", "T"], AD06: ["y", "Y"], AD07: ["u", "U"], AD08: ["i", "I"],
  AD09: ["o", "O"], AD10: ["p", "P"], AD11: ["[", "{"], AD12: ["]", "}"],
  AC01: ["a", "A"], AC02: ["s", "S"], AC03: ["d", "D"], AC04: ["f", "F"],
  AC05: ["g", "G"], AC06: ["h", "H"], AC07: ["j", "J"], AC08: ["k", "K"],
  AC09: ["l", "L"], AC10: [";", ":"], AC11: ["'", "\""],
  TLDE: ["`", "~"], BKSL: ["\\", "|"],
  AB01: ["z", "Z"], AB02: ["x", "X"], AB03: ["c", "C"], AB04: ["v", "V"],
  AB05: ["b", "B"], AB06: ["n", "N"], AB07: ["m", "M"],
  AB08: [",", "<"], AB09: [".", ">"], AB10: ["/", "?"]
}

function posKey(lang, pos, flex) {
  var keys = lang && lang.keys
  var pair = (keys && keys[pos]) || US_FALLBACK_KEYS[pos] || [pos, pos]
  var key = charKey(pair[0], pair[1], flex)
  key.pos = pos
  key.l3 = pair[2] || ""
  key.l4 = pair[3] || ""
  var dead = lang && lang.dead && lang.dead[pos]
  if (dead) key.dead = [dead[0] || "", dead[1] || "", dead[2] || "", dead[3] || ""]
  var syms = lang && lang.keysyms && lang.keysyms[pos]
  if (syms) key.keysyms = syms
  return key
}

function hasAltGr(lang) {
  var keys = lang && lang.keys
  if (!keys) return false
  for (var pos in keys) {
    if (keys[pos][2]) return true
  }
  return false
}

function numberRow() {
  return [
    charKey("1"), charKey("2"), charKey("3"), charKey("4"), charKey("5"),
    charKey("6"), charKey("7"), charKey("8"), charKey("9"), charKey("0")
  ]
}

function ansiNumberRow(lang) {
  return [
    posKey(lang, "TLDE"), posKey(lang, "AE01"), posKey(lang, "AE02"), posKey(lang, "AE03"),
    posKey(lang, "AE04"), posKey(lang, "AE05"), posKey(lang, "AE06"), posKey(lang, "AE07"),
    posKey(lang, "AE08"), posKey(lang, "AE09"), posKey(lang, "AE10"),
    posKey(lang, "AE11"), posKey(lang, "AE12"),
    { type: "backspace", label: "󰁮", flex: 1.6 }
  ]
}

function qwertyRow(lang) {
  return [
    posKey(lang, "AD01"), posKey(lang, "AD02"), posKey(lang, "AD03"), posKey(lang, "AD04"), posKey(lang, "AD05"),
    posKey(lang, "AD06"), posKey(lang, "AD07"), posKey(lang, "AD08"), posKey(lang, "AD09"), posKey(lang, "AD10")
  ]
}

function ansiQwertyRow(lang) {
  return [
    { type: "tab", label: "󰌒", flex: 1.4 },
    posKey(lang, "AD01"), posKey(lang, "AD02"), posKey(lang, "AD03"), posKey(lang, "AD04"), posKey(lang, "AD05"),
    posKey(lang, "AD06"), posKey(lang, "AD07"), posKey(lang, "AD08"), posKey(lang, "AD09"), posKey(lang, "AD10"),
    posKey(lang, "AD11"), posKey(lang, "AD12"), posKey(lang, "BKSL")
  ]
}

function homeRow(lang) {
  return [
    posKey(lang, "AC01"), posKey(lang, "AC02"), posKey(lang, "AC03"), posKey(lang, "AC04"), posKey(lang, "AC05"),
    posKey(lang, "AC06"), posKey(lang, "AC07"), posKey(lang, "AC08"), posKey(lang, "AC09")
  ]
}

function ansiHomeRow(lang) {
  return [
    { type: "capslock", label: "󰌎", flex: 1.6 },
    posKey(lang, "AC01"), posKey(lang, "AC02"), posKey(lang, "AC03"), posKey(lang, "AC04"), posKey(lang, "AC05"),
    posKey(lang, "AC06"), posKey(lang, "AC07"), posKey(lang, "AC08"), posKey(lang, "AC09"),
    posKey(lang, "AC10"), posKey(lang, "AC11"),
    { type: "enter", label: "󰌑", flex: 1.6 }
  ]
}

function shiftRow(lang) {
  return [
    { type: "shift", label: "󰘶", flex: 1.6 },
    posKey(lang, "AB01"), posKey(lang, "AB02"), posKey(lang, "AB03"), posKey(lang, "AB04"),
    posKey(lang, "AB05"), posKey(lang, "AB06"), posKey(lang, "AB07"),
    { type: "backspace", label: "󰁮", flex: 1.6 }
  ]
}

function ansiShiftRow(lang) {
  return [
    { type: "shift", label: "󰘶", flex: 1.8 },
    posKey(lang, "AB01"), posKey(lang, "AB02"), posKey(lang, "AB03"), posKey(lang, "AB04"),
    posKey(lang, "AB05"), posKey(lang, "AB06"), posKey(lang, "AB07"),
    posKey(lang, "AB08"), posKey(lang, "AB09"), posKey(lang, "AB10"),
    { type: "shift", label: "󰘶", flex: 1.8 }
  ]
}

function bottomRow(withMods, pageLabel, pageTarget, showSuper) {
  if (!withMods) {
    return [
      pageKey(pageLabel, pageTarget),
      charKey(",", "!"),
      { type: "space", label: "", flex: 5 },
      charKey(".", "?"),
      { type: "enter", label: "󰌑", flex: 1.6 }
    ]
  }
  var includeSuper = showSuper !== false
  var row = [
    pageKey(pageLabel, pageTarget, 1.1),
    modKey("ctrl", "Ctrl"),
    modKey("alt", "Alt")
  ]
  if (includeSuper) row.push(superKey(1.2))
  row.push({ type: "space", label: "", flex: includeSuper ? 3.2 : 4.4 })
  row.push(charKey(",", "!", 0.8))
  row.push(charKey(".", "?", 0.8))
  row.push({ type: "enter", label: "󰌑", flex: 1.3 })
  return row
}

function ansiBottomRow(showSuper, pageLabel, pageTarget, lang) {
  var includeSuper = showSuper !== false
  var includeAltgr = hasAltGr(lang)
  var row = [pageKey(pageLabel || "#+=", pageTarget || "symbols2", 1.0)]
  row.push(modKey("ctrl", "Ctrl", 1.1))
  if (includeSuper) row.push(superKey(1.1))
  row.push(modKey("alt", "Alt", 1.1))
  row.push({ type: "space", label: "", flex: includeSuper ? 4 : 6.2 })
  row.push(includeAltgr ? modKey("altgr", "AltGr", 1.1) : modKey("alt", "Alt", 1.1))
  if (includeSuper) row.push(superKey(1.1))
  row.push(modKey("ctrl", "Ctrl", 1.1))
  return row
}

function buildLetterRows(style, showSuper, lang) {
  if (style === "complete") {
    return [
      ansiNumberRow(lang),
      ansiQwertyRow(lang),
      ansiHomeRow(lang),
      ansiShiftRow(lang),
      ansiBottomRow(showSuper, undefined, undefined, lang)
    ]
  }

  var rows = []
  if (style === "omapad") rows.push(numberRow())
  rows.push(qwertyRow(lang))
  rows.push(homeRow(lang))
  rows.push(shiftRow(lang))
  rows.push(bottomRow(style !== "minimal", "123", "numbers", showSuper))
  return rows
}

function modBottomRow(style, pageLabel, pageTarget, showSuper, lang) {
  if (style === "complete") return ansiBottomRow(showSuper, pageLabel, pageTarget, lang)
  return bottomRow(style !== "minimal", pageLabel, pageTarget, showSuper)
}

function buildSymbolPages(style, showSuper, lang) {
  return {
    numbers: {
      rows: [
        [
          charKey("1"), charKey("2"), charKey("3"), charKey("4"), charKey("5"),
          charKey("6"), charKey("7"), charKey("8"), charKey("9"), charKey("0")
        ],
        [
          charKey("@"), charKey("#"), charKey("$"), charKey("_"), charKey("&"),
          charKey("-"), charKey("+"), charKey("("), charKey(")"), charKey("/")
        ],
        [
          { type: "page", label: "#+=", target: "symbols2", flex: 1.6 },
          charKey("*"), charKey("\""), charKey("'"), charKey(":"),
          charKey(";"), charKey("!"), charKey("?"),
          { type: "backspace", label: "󰁮", flex: 1.6 }
        ],
        modBottomRow(style, "ABC", "letters", showSuper, lang)
      ]
    },
    symbols2: {
      rows: [
        [
          charKey("~"), charKey("`"), charKey("|"), charKey("•"), charKey("√"),
          charKey("π"), charKey("÷"), charKey("×"), charKey("¶"), charKey("Δ")
        ],
        [
          charKey("£"), charKey("€"), charKey("¥"), charKey("^"), charKey("°"),
          charKey("="), charKey("{"), charKey("}"), charKey("["), charKey("]")
        ],
        [
          { type: "page", label: "123", target: "numbers", flex: 1.6 },
          charKey("\\"), charKey("<"), charKey(">"), charKey("%"),
          charKey("©"), charKey("®"), charKey("™"),
          { type: "backspace", label: "󰁮", flex: 1.6 }
        ],
        modBottomRow(style, "ABC", "letters", showSuper, lang)
      ]
    }
  }
}

var _variantUnset = ({})
var _variantSource = _variantUnset
var _variantIndex = {}
var MAX_VARIANTS = 12

function variantIndex(compose) {
  if (compose === _variantSource) return _variantIndex
  var index = {}
  var rules = (compose && compose.rules) || {}
  for (var dead in rules) {
    var map = rules[dead]
    for (var base in map) {
      if (base.length !== 1 || base === " ") continue
      var out = map[base]
      if (!out || out === base) continue
      if (!index[base]) index[base] = []
      if (index[base].indexOf(out) < 0) index[base].push(out)
    }
  }
  _variantSource = compose
  _variantIndex = index
  return index
}

function attachVariants(pages, compose) {
  var index = variantIndex(compose)
  for (var pageName in pages) {
    var rows = pages[pageName].rows
    for (var r = 0; r < rows.length; r++) {
      for (var i = 0; i < rows[r].length; i++) {
        var key = rows[r][i]
        if (key.type !== "char") continue
        var list = []
        if (key.l3 && key.l3 !== key.label) list.push(key.l3)
        if (key.l4 && key.l4 !== key.label && list.indexOf(key.l4) < 0) list.push(key.l4)
        var accents = index[key.label] || []
        for (var a = 0; a < accents.length && list.length < MAX_VARIANTS; a++) {
          if (list.indexOf(accents[a]) < 0) list.push(accents[a])
        }
        if (list.length) key.variants = list
      }
    }
  }
}

function get(languageData, style, showSuper, compose) {
  var name = (languageData && languageData.name) || "EN"
  var effectiveStyle = STYLES.indexOf(style) >= 0 ? style : "minimal"
  var symbolPages = buildSymbolPages(effectiveStyle, showSuper, languageData)
  var pages = {
    letters: { rows: buildLetterRows(effectiveStyle, showSuper, languageData) },
    numbers: symbolPages.numbers,
    symbols2: symbolPages.symbols2
  }
  attachVariants(pages, compose)
  return {
    name: name,
    direction: (languageData && languageData.direction) || "ltr",
    pages: pages
  }
}
