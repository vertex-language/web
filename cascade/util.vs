package cascade

import "unicode/utf8"

/// The string bytes[start..<end] spell.
func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}
