package css

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
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12
}

func isIdentStart(_ b: uint8) -> bool {
    return (b >= 97 && b <= 122) || // 'a'...'z'
           (b >= 65 && b <= 90) ||  // 'A'...'Z'
           b == 95 || b == 45       // '_', '-'
}

func isIdentChar(_ b: uint8) -> bool {
    return isIdentStart(b) || (b >= 48 && b <= 57) // '0'...'9'
}

func isDigit(_ b: uint8) -> bool {
    return b >= 48 && b <= 57
}

func trimString(_ s: string) -> string {
    let bytes = bytesFromString(s)
    if bytes.isEmpty { return "" }
    var start = 0
    while start < bytes.count && isWhitespace(bytes[start]) {
        start += 1
    }
    var end = bytes.count
    while end > start && isWhitespace(bytes[end - 1]) {
        end -= 1
    }
    return stringFromBytes(bytes, from: start, to: end)
}
