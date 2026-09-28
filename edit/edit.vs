package edit

import "unicode/utf8"

// Editing text by byte offsets into UTF-8: where the caret goes when it
// moves by a character, a word or a line, and the text after an insert.
// Characters are code points for now; grapheme clusters come with
// text/segment.

/// The text with bytes inserted at an offset, clamped to the text.
public func Insert(_ s: string, at index: int, _ insertion: [uint8]) -> string {
    let b = [uint8](s.utf8)
    let at = index < 0 ? 0 : (index > b.count ? b.count : index)
    var out: [uint8] = []
    var i = 0
    while i < at { out.append(b[i]); i += 1 }
    for x in insertion { out.append(x) }
    while i < b.count { out.append(b[i]); i += 1 }
    return stringOf(out, 0, out.count)
}

/// The text with bytes[start..<end] removed.
public func Remove(_ s: string, from start: int, to end: int) -> string {
    let b = [uint8](s.utf8)
    let lo = min(start, b.count)
    let hi = min(end, b.count)
    return stringOf(b, 0, lo) + stringOf(b, hi, b.count)
}

/// The offset of the character before i.
public func PreviousChar(_ b: [uint8], _ i: int) -> int {
    var j = i - 1
    while j > 0 && (b[j] & 0xC0) == 0x80 { j -= 1 }
    return j < 0 ? 0 : j
}

/// The offset of the character after i.
public func NextChar(_ b: [uint8], _ i: int) -> int {
    var j = i + 1
    while j < b.count && (b[j] & 0xC0) == 0x80 { j += 1 }
    return j > b.count ? b.count : j
}

/// Whether i starts a character rather than continuing one.
public func IsCharStart(_ b: [uint8], _ i: int) -> bool {
    return i == b.count || (b[i] & 0xC0) != 0x80
}

/// The start of the word before i, skipping the spaces before it.
public func WordStart(_ b: [uint8], before i: int) -> int {
    var j = i
    while j > 0 && isSpaceByte(b[j - 1]) { j -= 1 }
    while j > 0 && !isSpaceByte(b[j - 1]) { j -= 1 }
    return j
}

/// The end of the word after i, skipping the spaces after it.
public func WordEnd(_ b: [uint8], after i: int) -> int {
    var j = i
    while j < b.count && isSpaceByte(b[j]) { j += 1 }
    while j < b.count && !isSpaceByte(b[j]) { j += 1 }
    return j
}

/// The word, or the run of spaces, at an offset: what a double click
/// selects.
public func WordAt(_ b: [uint8], _ offset: int) -> (start: int, end: int) {
    var start = min(offset, b.count)
    var end = start
    if start < b.count && isSpaceByte(b[start]) {
        while start > 0 && isSpaceByte(b[start - 1]) { start -= 1 }
        while end < b.count && isSpaceByte(b[end]) { end += 1 }
    } else {
        while start > 0 && !isSpaceByte(b[start - 1]) { start -= 1 }
        while end < b.count && !isSpaceByte(b[end]) { end += 1 }
    }
    return (start: start, end: end)
}

/// The caret moved a line up or down in multi-line text, keeping its
/// column where the line allows.
public func LineMove(_ b: [uint8], _ caret: int, up: bool) -> int {
    var lineStart = caret
    while lineStart > 0 && b[lineStart - 1] != 10 { lineStart -= 1 }
    let column = caret - lineStart
    if up {
        if lineStart == 0 { return 0 }
        var prevStart = lineStart - 1
        while prevStart > 0 && b[prevStart - 1] != 10 { prevStart -= 1 }
        let prevLen = lineStart - 1 - prevStart
        return prevStart + (column < prevLen ? column : prevLen)
    }
    var lineEnd = caret
    while lineEnd < b.count && b[lineEnd] != 10 { lineEnd += 1 }
    if lineEnd >= b.count { return b.count }
    let nextStart = lineEnd + 1
    var nextEnd = nextStart
    while nextEnd < b.count && b[nextEnd] != 10 { nextEnd += 1 }
    let nextLen = nextEnd - nextStart
    return nextStart + (column < nextLen ? column : nextLen)
}

/// The line of multi-line text a row index falls on: its byte range.
public func LineRange(_ b: [uint8], row: int) -> (start: int, end: int) {
    var i = 0
    var current = 0
    var lineStart = 0
    while i < b.count && current < row {
        if b[i] == 10 {
            current += 1
            lineStart = i + 1
        }
        i += 1
    }
    var lineEnd = lineStart
    while lineEnd < b.count && b[lineEnd] != 10 { lineEnd += 1 }
    return (start: lineStart, end: lineEnd)
}

/// The first line of text, for a single-line field taking a paste.
public func FirstLine(_ b: [uint8]) -> [uint8] {
    var i = 0
    while i < b.count && b[i] != 10 && b[i] != 13 { i += 1 }
    var out = b
    while out.count > i { out.removeLast() }
    return out
}

func isSpaceByte(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12
}

func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}
