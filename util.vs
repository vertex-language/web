package web

import (
    "web/css"
    "unicode/utf8"
)

func lower(_ s: string) -> string {
    return css.lower(s)
}

func trimSpaces(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var start = 0
    var end = b.count
    while start < end && (b[start] == 32 || b[start] == 9 || b[start] == 10 || b[start] == 13) { start += 1 }
    while end > start && (b[end - 1] == 32 || b[end - 1] == 9 || b[end - 1] == 10 || b[end - 1] == 13) { end -= 1 }
    if start == 0 && end == b.count { return s }
    return stringOf(b, start, end)
}

func parseNumber(_ b: [uint8], _ start: int, _ end: int) -> float32 {
    return css.parseNumber(b, start, end)
}

func startsWithBytes(_ b: [uint8], _ prefix: string) -> bool {
    let p = [uint8](prefix.utf8)
    if b.count < p.count { return false }
    var i = 0
    while i < p.count {
        if b[i] != p[i] { return false }
        i += 1
    }
    return true
}

/// The string bytes[start..<end] spell.
func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}
