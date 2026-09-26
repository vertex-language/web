package html

@_silgen_name("vertex_string_from_utf8")
func stringFromUtf8(_ ptr: UnsafeRawPointer, _ count: int64) -> string

func stringFromBytes(_ bytes: [uint8], from start: int, to end: int) -> string {
    if start >= end { return "" }
    return bytes.withUnsafeBytes { bp in
        stringFromUtf8(bp.baseAddress! + start, int64(end - start))
    }
}

func bytesFromString(_ text: string) -> [uint8] {
    return [uint8](text.utf8)
}

func toLower(_ s: string) -> string {
    var b = [uint8](s.utf8)
    var i = 0
    var changed = false
    while i < b.count {
        if b[i] >= 65 && b[i] <= 90 {
            b[i] = b[i] + 32
            changed = true
        }
        i += 1
    }
    if !changed { return s }
    return stringFromBytes(b, from: 0, to: b.count)
}




func isWhitespace(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12 // space, tab, LF, CR, FF
}

func isTagChar(_ b: uint8) -> bool {
    return (b >= 97 && b <= 122) || // 'a'...'z'
           (b >= 65 && b <= 90) ||  // 'A'...'Z'
           (b >= 48 && b <= 57) ||  // '0'...'9'
           b == 45 || b == 95 || b == 58 // '-', '_', ':'
}

func isVoidElement(_ tag: string) -> bool {
    let lower = toLower(tag)
    return lower == "area" || lower == "base" || lower == "br" || lower == "col" ||
           lower == "embed" || lower == "hr" || lower == "img" || lower == "input" ||
           lower == "link" || lower == "meta" || lower == "source" || lower == "track" ||
           lower == "wbr"
}

func isRawTextElement(_ tag: string) -> bool {
    return tag == "script" || tag == "style" || tag == "textarea" || tag == "title"
}

// The raw text elements whose text still has character references:
// RCDATA, in the standard's term.
func isEscapableRawText(_ tag: string) -> bool {
    return tag == "textarea" || tag == "title"
}
