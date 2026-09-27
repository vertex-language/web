package html

// Character encodings (the Encoding Standard, and HTML's section 13.2.3):
// how a document's bytes become its text.

/// The encoding a document's bytes are in, as the HTML standard finds it:
/// a byte order mark first, then the charset its HTTP Content-Type names,
/// then a <meta charset> or <meta http-equiv=content-type> in its first
/// 1024 bytes, and UTF-8 otherwise. One of "utf-8", "utf-16le",
/// "utf-16be" and "windows-1252" -- the labels the web uses map onto
/// those (iso-8859-1, latin1 and ascii are windows-1252).
public func DetectEncoding(_ bytes: [uint8], contentType: string? = nil) -> string {
    if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF { return "utf-8" }
    if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE { return "utf-16le" }
    if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF { return "utf-16be" }
    if let ct = contentType, let label = charsetParameter(ct), let e = EncodingForLabel(label) { return e }
    if let label = prescanMeta(bytes), let e = EncodingForLabel(label) {
        // A <meta> that says UTF-16 means UTF-8: the bytes read as ASCII.
        return e.hasPrefix("utf-16") ? "utf-8" : e
    }
    return "utf-8"
}

/// The encoding a label names, or nil for one not supported here.
public func EncodingForLabel(_ label: string) -> string? {
    switch toLower(trimASCII(label)) {
    case "utf-8", "utf8", "unicode-1-1-utf-8", "unicode11utf8", "unicode20utf8", "x-unicode20utf8":
        return "utf-8"
    case "utf-16le", "utf-16", "ucs-2", "unicode", "csunicode", "iso-10646-ucs-2", "unicodefeff":
        return "utf-16le"
    case "utf-16be", "unicodefffe":
        return "utf-16be"
    case "windows-1252", "iso-8859-1", "iso8859-1", "iso_8859-1", "latin1", "l1", "ascii", "us-ascii", "cp1252",
         "cp819", "csisolatin1", "ibm819", "iso-ir-100", "iso88591", "iso_8859-1:1987", "x-cp1252", "ansi_x3.4-1968":
        return "windows-1252"
    default:
        return nil
    }
}

/// A document's bytes as text, in the encoding DetectEncoding finds. A
/// byte order mark is dropped; what doesn't decode becomes U+FFFD.
public func Decode(_ bytes: [uint8], contentType: string? = nil) -> string {
    switch DetectEncoding(bytes, contentType: contentType) {
    case "utf-16le": return decodeUTF16(bytes, littleEndian: true)
    case "utf-16be": return decodeUTF16(bytes, littleEndian: false)
    case "windows-1252": return decodeWindows1252(bytes)
    default:
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return string(decoding: bytes[3...], as: UTF8.self)
        }
        return string(decoding: bytes, as: UTF8.self)
    }
}

/// windows-1252's 0x80 to 0x9F; the rest of its high half is Latin-1.
let windows1252High: [uint32] = [
    0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
    0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
]

func decodeWindows1252(_ bytes: [uint8]) -> string {
    var out: [uint8] = []
    out.reserveCapacity(bytes.count + bytes.count / 8)
    for b in bytes {
        if b < 0x80 {
            out.append(b)
        } else {
            appendUTF8(&out, b < 0xA0 ? windows1252High[int(b) - 0x80] : uint32(b))
        }
    }
    return string(decoding: out, as: UTF8.self)
}

func decodeUTF16(_ bytes: [uint8], littleEndian: bool) -> string {
    var out: [uint8] = []
    var i = 0
    // A byte order mark is not text.
    if bytes.count >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF)) { i = 2 }
    func unit(_ k: int) -> uint32 {
        return littleEndian ? uint32(bytes[k]) | uint32(bytes[k + 1]) << 8 : uint32(bytes[k]) << 8 | uint32(bytes[k + 1])
    }
    while i + 1 < bytes.count {
        let u = unit(i)
        i += 2
        if u >= 0xD800 && u < 0xDC00 && i + 1 < bytes.count {
            let low = unit(i)
            if low >= 0xDC00 && low < 0xE000 {
                appendUTF8(&out, 0x10000 + ((u - 0xD800) << 10) + (low - 0xDC00))
                i += 2
                continue
            }
            appendUTF8(&out, 0xFFFD)
        } else if u >= 0xD800 && u < 0xE000 {
            appendUTF8(&out, 0xFFFD)
        } else {
            appendUTF8(&out, u)
        }
    }
    return string(decoding: out, as: UTF8.self)
}

func appendUTF8(_ out: inout [uint8], _ c: uint32) {
    if c < 0x80 {
        out.append(uint8(c))
    } else if c < 0x800 {
        out.append(uint8(0xC0 | (c >> 6)))
        out.append(uint8(0x80 | (c & 0x3F)))
    } else if c < 0x10000 {
        out.append(uint8(0xE0 | (c >> 12)))
        out.append(uint8(0x80 | ((c >> 6) & 0x3F)))
        out.append(uint8(0x80 | (c & 0x3F)))
    } else {
        out.append(uint8(0xF0 | (c >> 18)))
        out.append(uint8(0x80 | ((c >> 12) & 0x3F)))
        out.append(uint8(0x80 | ((c >> 6) & 0x3F)))
        out.append(uint8(0x80 | (c & 0x3F)))
    }
}

/// The charset parameter of a Content-Type: `text/html; charset=UTF-8`.
func charsetParameter(_ contentType: string) -> string? {
    let lower = toLower(contentType)
    let b = [uint8](lower.utf8)
    let key = [uint8]("charset".utf8)
    var i = 0
    while i + key.count < b.count {
        var same = true
        var k = 0
        while k < key.count {
            if b[i + k] != key[k] { same = false; break }
            k += 1
        }
        if same {
            var j = i + key.count
            while j < b.count && b[j] == 32 { j += 1 }
            if j < b.count && b[j] == 61 {
                j += 1
                while j < b.count && (b[j] == 32 || b[j] == 34 || b[j] == 39) { j += 1 }
                let start = j
                while j < b.count && b[j] != 59 && b[j] != 34 && b[j] != 39 && b[j] != 32 { j += 1 }
                if j > start { return stringFromBytes(b, from: start, to: j) }
            }
        }
        i += 1
    }
    return nil
}

/// The charset a <meta> in the first 1024 bytes names: its charset
/// attribute, or an http-equiv content-type's content. A plain reading
/// of HTML's prescan, enough for the <meta>s pages write.
func prescanMeta(_ bytes: [uint8]) -> string? {
    let n = bytes.count < 1024 ? bytes.count : 1024
    var head: [uint8] = []
    head.reserveCapacity(n)
    var i = 0
    while i < n {
        let c = bytes[i]
        head.append(c >= 65 && c <= 90 ? c + 32 : c)
        i += 1
    }
    let text = stringFromBytes(head, from: 0, to: head.count)
    var start = 0
    while true {
        guard let at = find(head, [uint8]("<meta".utf8), from: start) else { return nil }
        var end = at
        while end < head.count && head[end] != 62 { end += 1 }
        let tag = stringFromBytes(head, from: at, to: end)
        if let v = attributeIn(tag, "charset"), EncodingForLabel(v) != nil { return v }
        if let equiv = attributeIn(tag, "http-equiv"), equiv == "content-type", let content = attributeIn(tag, "content"),
           let cs = charsetParameter(content) {
            return cs
        }
        start = end
        if text.isEmpty { return nil }
    }
}

func find(_ hay: [uint8], _ needle: [uint8], from: int) -> int? {
    var i = from
    while i + needle.count <= hay.count {
        var k = 0
        while k < needle.count && hay[i + k] == needle[k] { k += 1 }
        if k == needle.count { return i }
        i += 1
    }
    return nil
}

/// An attribute's value in a tag's text: name=value, quoted or not.
func attributeIn(_ tag: string, _ name: string) -> string? {
    let b = [uint8](tag.utf8)
    let key = [uint8](name.utf8)
    var i = 0
    while i + key.count < b.count {
        let before = i == 0 ? 32 : b[i - 1]
        if (before == 32 || before == 9 || before == 10 || before == 47 || before == 34 || before == 39), find(b, key, from: i) == i {
            var j = i + key.count
            while j < b.count && b[j] == 32 { j += 1 }
            if j < b.count && b[j] == 61 {
                j += 1
                while j < b.count && b[j] == 32 { j += 1 }
                var quote: uint8 = 0
                if j < b.count && (b[j] == 34 || b[j] == 39) {
                    quote = b[j]
                    j += 1
                }
                let s = j
                while j < b.count && (quote != 0 ? b[j] != quote : (b[j] != 32 && b[j] != 62 && b[j] != 47 && b[j] != 34 && b[j] != 39)) { j += 1 }
                return trimASCII(stringFromBytes(b, from: s, to: j))
            }
        }
        i += 1
    }
    return nil
}

func trimASCII(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var i = 0
    var j = b.count
    while i < j && (b[i] == 32 || b[i] == 9 || b[i] == 10 || b[i] == 13 || b[i] == 12) { i += 1 }
    while j > i && (b[j - 1] == 32 || b[j - 1] == 9 || b[j - 1] == 10 || b[j - 1] == 13 || b[j - 1] == 12) { j -= 1 }
    return stringFromBytes(b, from: i, to: j)
}
