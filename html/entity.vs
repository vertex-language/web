package html

/// Escapes special HTML characters (`&`, `<`, `>`, `"`, `'`).
public func Escape(_ text: string) -> string {
    var out = ""
    for b in text.utf8 {
        switch b {
        case 38: out += "&amp;"   // '&'
        case 60: out += "&lt;"    // '<'
        case 62: out += "&gt;"    // '>'
        case 34: out += "&quot;"  // '"'
        case 39: out += "&#39;"   // '\''
        default:
            var single: [CChar] = [CChar(truncatingIfNeeded: b), 0]
            out += string(cString: single)
        }
    }
    return out
}

/// Decodes standard HTML entities in text (e.g. `&amp;`, `&lt;`, `&#65;`).
public func Unescape(_ text: string) -> string {
    let bytes = bytesFromString(text)
    var out: [uint8] = []
    var i = 0
    let len = bytes.count

    while i < len {
        if bytes[i] == 38 { // '&'
            // Look for closing ';'
            var semi = i + 1
            while semi < len && semi < i + 12 && bytes[semi] != 59 && bytes[semi] != 38 && !isWhitespace(bytes[semi]) {
                semi += 1
            }

            if semi < len && bytes[semi] == 59 { // ';'
                let entity = stringFromBytes(bytes, from: i + 1, to: semi)
                if let decoded = decodeNamedOrNumericEntity(entity) {
                    for db in decoded.utf8 {
                        out.append(db)
                    }
                    i = semi + 1
                    continue
                }
            }
        }
        out.append(bytes[i])
        i += 1
    }

    return stringFromBytes(out, from: 0, to: out.count)
}

/// The named character references HTML 4 defines, and &apos;: what
/// pages write by name.
let namedEntities: [string: uint32] = [
    "AElig": 0xC6, "Aacute": 0xC1, "Acirc": 0xC2, "Agrave": 0xC0, "Alpha": 0x391, "Aring": 0xC5,
    "Atilde": 0xC3, "Auml": 0xC4, "Beta": 0x392, "Ccedil": 0xC7, "Chi": 0x3A7, "Dagger": 0x2021,
    "Delta": 0x394, "ETH": 0xD0, "Eacute": 0xC9, "Ecirc": 0xCA, "Egrave": 0xC8, "Epsilon": 0x395,
    "Eta": 0x397, "Euml": 0xCB, "Gamma": 0x393, "Iacute": 0xCD, "Icirc": 0xCE, "Igrave": 0xCC,
    "Iota": 0x399, "Iuml": 0xCF, "Kappa": 0x39A, "Lambda": 0x39B, "Mu": 0x39C, "Ntilde": 0xD1,
    "Nu": 0x39D, "OElig": 0x152, "Oacute": 0xD3, "Ocirc": 0xD4, "Ograve": 0xD2, "Omega": 0x3A9,
    "Omicron": 0x39F, "Oslash": 0xD8, "Otilde": 0xD5, "Ouml": 0xD6, "Phi": 0x3A6, "Pi": 0x3A0,
    "Prime": 0x2033, "Psi": 0x3A8, "Rho": 0x3A1, "Scaron": 0x160, "Sigma": 0x3A3, "THORN": 0xDE,
    "Tau": 0x3A4, "Theta": 0x398, "Uacute": 0xDA, "Ucirc": 0xDB, "Ugrave": 0xD9, "Upsilon": 0x3A5,
    "Uuml": 0xDC, "Xi": 0x39E, "Yacute": 0xDD, "Yuml": 0x178, "Zeta": 0x396, "aacute": 0xE1,
    "acirc": 0xE2, "acute": 0xB4, "aelig": 0xE6, "agrave": 0xE0, "alefsym": 0x2135, "alpha": 0x3B1,
    "amp": 0x26, "and": 0x2227, "ang": 0x2220, "aring": 0xE5, "asymp": 0x2248, "atilde": 0xE3,
    "auml": 0xE4, "bdquo": 0x201E, "beta": 0x3B2, "brvbar": 0xA6, "bull": 0x2022, "cap": 0x2229,
    "ccedil": 0xE7, "cedil": 0xB8, "cent": 0xA2, "chi": 0x3C7, "circ": 0x2C6, "clubs": 0x2663,
    "cong": 0x2245, "copy": 0xA9, "crarr": 0x21B5, "cup": 0x222A, "curren": 0xA4, "dArr": 0x21D3,
    "dagger": 0x2020, "darr": 0x2193, "deg": 0xB0, "delta": 0x3B4, "diams": 0x2666, "divide": 0xF7,
    "eacute": 0xE9, "ecirc": 0xEA, "egrave": 0xE8, "empty": 0x2205, "emsp": 0x2003, "ensp": 0x2002,
    "epsilon": 0x3B5, "equiv": 0x2261, "eta": 0x3B7, "eth": 0xF0, "euml": 0xEB, "euro": 0x20AC,
    "exist": 0x2203, "fnof": 0x192, "forall": 0x2200, "frac12": 0xBD, "frac14": 0xBC, "frac34": 0xBE,
    "frasl": 0x2044, "gamma": 0x3B3, "ge": 0x2265, "gt": 0x3E, "hArr": 0x21D4, "harr": 0x2194,
    "hearts": 0x2665, "hellip": 0x2026, "iacute": 0xED, "icirc": 0xEE, "iexcl": 0xA1, "igrave": 0xEC,
    "image": 0x2111, "infin": 0x221E, "int": 0x222B, "iota": 0x3B9, "iquest": 0xBF, "isin": 0x2208,
    "iuml": 0xEF, "kappa": 0x3BA, "lArr": 0x21D0, "lambda": 0x3BB, "lang": 0x2329, "laquo": 0xAB,
    "larr": 0x2190, "lceil": 0x2308, "ldquo": 0x201C, "le": 0x2264, "lfloor": 0x230A, "lowast": 0x2217,
    "loz": 0x25CA, "lrm": 0x200E, "lsaquo": 0x2039, "lsquo": 0x2018, "lt": 0x3C, "macr": 0xAF,
    "mdash": 0x2014, "micro": 0xB5, "middot": 0xB7, "minus": 0x2212, "mu": 0x3BC, "nabla": 0x2207,
    "nbsp": 0xA0, "ndash": 0x2013, "ne": 0x2260, "ni": 0x220B, "not": 0xAC, "notin": 0x2209,
    "nsub": 0x2284, "ntilde": 0xF1, "nu": 0x3BD, "oacute": 0xF3, "ocirc": 0xF4, "oelig": 0x153,
    "ograve": 0xF2, "oline": 0x203E, "omega": 0x3C9, "omicron": 0x3BF, "oplus": 0x2295, "or": 0x2228,
    "ordf": 0xAA, "ordm": 0xBA, "oslash": 0xF8, "otilde": 0xF5, "otimes": 0x2297, "ouml": 0xF6,
    "para": 0xB6, "part": 0x2202, "permil": 0x2030, "perp": 0x22A5, "phi": 0x3C6, "pi": 0x3C0,
    "piv": 0x3D6, "plusmn": 0xB1, "pound": 0xA3, "prime": 0x2032, "prod": 0x220F, "prop": 0x221D,
    "psi": 0x3C8, "quot": 0x22, "rArr": 0x21D2, "radic": 0x221A, "rang": 0x232A, "raquo": 0xBB,
    "rarr": 0x2192, "rceil": 0x2309, "rdquo": 0x201D, "real": 0x211C, "reg": 0xAE, "rfloor": 0x230B,
    "rho": 0x3C1, "rlm": 0x200F, "rsaquo": 0x203A, "rsquo": 0x2019, "sbquo": 0x201A, "scaron": 0x161,
    "sdot": 0x22C5, "sect": 0xA7, "shy": 0xAD, "sigma": 0x3C3, "sigmaf": 0x3C2, "sim": 0x223C,
    "spades": 0x2660, "sub": 0x2282, "sube": 0x2286, "sum": 0x2211, "sup": 0x2283, "sup1": 0xB9,
    "sup2": 0xB2, "sup3": 0xB3, "supe": 0x2287, "szlig": 0xDF, "tau": 0x3C4, "there4": 0x2234,
    "theta": 0x3B8, "thetasym": 0x3D1, "thinsp": 0x2009, "thorn": 0xFE, "tilde": 0x2DC, "times": 0xD7,
    "trade": 0x2122, "uArr": 0x21D1, "uacute": 0xFA, "uarr": 0x2191, "ucirc": 0xFB, "ugrave": 0xF9,
    "uml": 0xA8, "upsih": 0x3D2, "upsilon": 0x3C5, "uuml": 0xFC, "weierp": 0x2118, "xi": 0x3BE,
    "yacute": 0xFD, "yen": 0xA5, "yuml": 0xFF, "zeta": 0x3B6, "zwj": 0x200D, "zwnj": 0x200C,
    "apos": 0x27,
]

/// The bytes of a code point in UTF-8.
func utf8Of(_ cp: uint32) -> string {
    var b: [uint8] = []
    if cp < 0x80 {
        b.append(uint8(cp))
    } else if cp < 0x800 {
        b.append(uint8(0xC0 | (cp >> 6)))
        b.append(uint8(0x80 | (cp & 0x3F)))
    } else if cp < 0x10000 {
        b.append(uint8(0xE0 | (cp >> 12)))
        b.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        b.append(uint8(0x80 | (cp & 0x3F)))
    } else {
        b.append(uint8(0xF0 | (cp >> 18)))
        b.append(uint8(0x80 | ((cp >> 12) & 0x3F)))
        b.append(uint8(0x80 | ((cp >> 6) & 0x3F)))
        b.append(uint8(0x80 | (cp & 0x3F)))
    }
    return stringFromBytes(b, from: 0, to: b.count)
}

/// What a numeric reference stands for, as HTML's parser maps it: the
/// C1 controls as windows-1252 reads those bytes, and nothing that
/// isn't a character as U+FFFD.
func numericReference(_ n: uint32) -> uint32 {
    if n == 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) { return 0xFFFD }
    if n >= 0x80 && n <= 0x9F {
        let w1252: [uint32] = [0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
                               0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178]
        return w1252[int(n - 0x80)]
    }
    return n
}

func decodeNamedOrNumericEntity(_ name: string) -> string? {
    if let cp = namedEntities[name] { return utf8Of(cp) }

    // Numeric entity: &#123; or &#x1F;
    let b = bytesFromString(name)
    if b.count > 1 && b[0] == 35 { // '#'
        var num: uint32 = 0
        var hex = false
        var start = 1
        if b.count > 2 && (b[1] == 120 || b[1] == 88) { // 'x' or 'X'
            hex = true
            start = 2
        }
        var j = start
        while j < b.count {
            let digit = b[j]
            if hex {
                if digit >= 48 && digit <= 57 {
                    num = num * 16 + uint32(digit - 48)
                } else if digit >= 97 && digit <= 102 {
                    num = num * 16 + uint32(digit - 97 + 10)
                } else if digit >= 65 && digit <= 70 {
                    num = num * 16 + uint32(digit - 65 + 10)
                } else {
                    return nil
                }
            } else {
                if digit >= 48 && digit <= 57 {
                    num = num * 10 + uint32(digit - 48)
                } else {
                    return nil
                }
            }
            // Past the last code point it stays past it.
            if num > 0x110000 { num = 0x110000 }
            j += 1
        }
        if j == start { return nil }
        return utf8Of(numericReference(num))
    }
    return nil
}
