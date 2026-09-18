.pragma library

var CHAR_CODES = {
  "a": 30, "b": 48, "c": 46, "d": 32, "e": 18, "f": 33, "g": 34, "h": 35,
  "i": 23, "j": 36, "k": 37, "l": 38, "m": 50, "n": 49, "o": 24, "p": 25,
  "q": 16, "r": 19, "s": 31, "t": 20, "u": 22, "v": 47, "w": 17, "x": 45,
  "y": 21, "z": 44,
  "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
  "-": 12, "=": 13, "[": 26, "]": 27, "\\": 43, ";": 39, "'": 40, "`": 41,
  ",": 51, ".": 52, "/": 53, " ": 57
}

var SHIFT_CODES = {
  "A": 30, "B": 48, "C": 46, "D": 32, "E": 18, "F": 33, "G": 34, "H": 35,
  "I": 23, "J": 36, "K": 37, "L": 38, "M": 50, "N": 49, "O": 24, "P": 25,
  "Q": 16, "R": 19, "S": 31, "T": 20, "U": 22, "V": 47, "W": 17, "X": 45,
  "Y": 21, "Z": 44,
  "!": 2, "@": 3, "#": 4, "$": 5, "%": 6, "^": 7, "&": 8, "*": 9, "(": 10, ")": 11,
  "_": 12, "+": 13, "{": 26, "}": 27, "|": 43, ":": 39, "\"": 40, "~": 41,
  "<": 51, ">": 52, "?": 53
}

var KEYSYM_CODES = {
  "Return": 28, "BackSpace": 14, "Tab": 15, "Escape": 1,
  "Left": 105, "Right": 106, "Up": 103, "Down": 108
}

var MOD_CODES = { ctrl: 29, alt: 56, logo: 125, shift: 42 }

function resolveKey(value) {
  if (Object.prototype.hasOwnProperty.call(SHIFT_CODES, value))
    return { code: SHIFT_CODES[value], shift: true }
  if (Object.prototype.hasOwnProperty.call(CHAR_CODES, value))
    return { code: CHAR_CODES[value], shift: false }
  if (Object.prototype.hasOwnProperty.call(KEYSYM_CODES, value))
    return { code: KEYSYM_CODES[value], shift: false }
  return null
}

function buildKeySequence(mods, value) {
  var target = resolveKey(value)
  if (!target) return null

  var modCodes = []
  for (var i = 0; i < mods.length; i++) {
    var code = MOD_CODES[mods[i]]
    if (code && modCodes.indexOf(code) < 0) modCodes.push(code)
  }
  if (target.shift && modCodes.indexOf(MOD_CODES.shift) < 0) modCodes.push(MOD_CODES.shift)

  var seq = []
  for (var i = 0; i < modCodes.length; i++) seq.push(modCodes[i] + ":1")
  seq.push(target.code + ":1")
  seq.push(target.code + ":0")
  for (var j = modCodes.length - 1; j >= 0; j--) seq.push(modCodes[j] + ":0")
  return seq
}

var KEYSYM_NAME_FOR_CHAR = {
  " ": "space", "!": "exclam", "\"": "quotedbl", "#": "numbersign", "$": "dollar",
  "%": "percent", "&": "ampersand", "'": "apostrophe", "(": "parenleft", ")": "parenright",
  "*": "asterisk", "+": "plus", ",": "comma", "-": "minus", ".": "period", "/": "slash",
  ":": "colon", ";": "semicolon", "<": "less", "=": "equal", ">": "greater", "?": "question",
  "@": "at", "[": "bracketleft", "\\": "backslash", "]": "bracketright", "^": "asciicircum",
  "_": "underscore", "`": "grave", "{": "braceleft", "|": "bar", "}": "braceright", "~": "asciitilde"
}

function wtypeKeyName(sym) {
  return (sym.length === 1 && KEYSYM_NAME_FOR_CHAR[sym]) || sym
}
