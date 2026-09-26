package layout

func isSpaceByte(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12
}

func upperBytes(_ b: [uint8]) -> [uint8] {
    var out = b
    var i = 0
    while i < out.count {
        if out[i] >= 97 && out[i] <= 122 { out[i] = out[i] - 32 }
        i += 1
    }
    return out
}

func lowerBytes(_ b: [uint8]) -> [uint8] {
    var out = b
    var i = 0
    while i < out.count {
        if out[i] >= 65 && out[i] <= 90 { out[i] = out[i] + 32 }
        i += 1
    }
    return out
}

func capitalizeBytes(_ b: [uint8]) -> [uint8] {
    var out = b
    var atStart = true
    var i = 0
    while i < out.count {
        if isSpaceByte(out[i]) {
            atStart = true
        } else {
            if atStart && out[i] >= 97 && out[i] <= 122 { out[i] = out[i] - 32 }
            atStart = false
        }
        i += 1
    }
    return out
}

/// Roman numerals for list markers.
func roman(_ n: int, upper: bool) -> string {
    if n <= 0 || n >= 4000 { return "\(n)" }
    let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
    let lowerSymbols = ["m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i"]
    let upperSymbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
    var out = ""
    var rest = n
    var i = 0
    while i < values.count {
        while rest >= values[i] {
            out += upper ? upperSymbols[i] : lowerSymbols[i]
            rest -= values[i]
        }
        i += 1
    }
    return out
}

/// Letters for list markers: a, b, ... z, aa, ab.
func alpha(_ n: int, upper: bool) -> string {
    if n <= 0 { return "\(n)" }
    var bytes: [uint8] = []
    var rest = n
    while rest > 0 {
        let d = uint8((rest - 1) % 26)
        bytes.insert((upper ? 65 : 97) + d, at: 0)
        rest = (rest - 1) / 26
    }
    return stringOf(bytes, 0, bytes.count)
}

@_silgen_name("vertex_string_from_utf8")
func stringFromUtf8(_ ptr: UnsafeRawPointer, _ count: int64) -> string

/// The string bytes[start..<end] spell.
func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return bytes.withUnsafeBytes { bp in
        stringFromUtf8(bp.baseAddress! + start, int64(end - start))
    }
}
