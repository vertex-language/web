package cascade

import "unicode/utf8"

/// The string bytes[start..<end] spell.
func stringOf(bytes: [uint8], start: int, end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}
