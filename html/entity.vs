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

func decodeNamedOrNumericEntity(_ name: string) -> string? {
    if name == "amp" { return "&" }
    if name == "lt" { return "<" }
    if name == "gt" { return ">" }
    if name == "quot" { return "\"" }
    if name == "apos" { return "'" }
    if name == "nbsp" { return " " }
    if name == "copy" { return "\u{00A9}" }
    if name == "reg" { return "\u{00AE}" }

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
            j += 1
        }
        if num > 0 && num <= 127 {
            var c: [CChar] = [CChar(truncatingIfNeeded: num), 0]
            return string(cString: c)
        }
    }
    return nil
}
