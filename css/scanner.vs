package css

/// Tokenizer that scans CSS source bytes into a CSS Token stream, as CSS
/// Syntax Level 3 tokenizes: numbers with their sign, unit or percent
/// sign; identifiers that may start with `-`; functions with their
/// paren; `url()` whole; strings with their escapes.
public class Scanner {
    var src: [uint8]
    var pos: int
    var len: int

    public init(bytes: [uint8]) {
        self.src = bytes
        self.pos = 0
        self.len = bytes.count
    }

    public init(source: string) {
        self.src = bytesFromString(source)
        self.pos = 0
        self.len = self.src.count
    }

    /// Fetches the next token from the CSS stream.
    public func Next() -> Token {
        let space = skipWhitespaceAndComments()
        var t = scan()
        t.SpaceBefore = space
        return t
    }

    func scan() -> Token {
        if pos >= len {
            return Token(kind: TokenKind.eof)
        }

        let b = src[pos]

        // Punctuation and brackets
        if b == 123 { pos += 1; return Token(kind: TokenKind.openBrace, value: "{") }  // '{'
        if b == 125 { pos += 1; return Token(kind: TokenKind.closeBrace, value: "}") } // '}'
        if b == 58  { pos += 1; return Token(kind: TokenKind.colon, value: ":") }      // ':'
        if b == 59  { pos += 1; return Token(kind: TokenKind.semicolon, value: ";") }  // ';'
        if b == 44  { pos += 1; return Token(kind: TokenKind.comma, value: ",") }      // ','
        if b == 40  { pos += 1; return Token(kind: TokenKind.openParen, value: "(") }  // '('
        if b == 41  { pos += 1; return Token(kind: TokenKind.closeParen, value: ")") } // ')'
        if b == 91  { pos += 1; return Token(kind: TokenKind.openBracket, value: "[") } // '['
        if b == 93  { pos += 1; return Token(kind: TokenKind.closeBracket, value: "]") } // ']'

        // Strings
        if b == 34 || b == 39 { // '"' or '\''
            return scanString(quote: b)
        }

        // At-keyword: @media, @import
        if b == 64 { // '@'
            pos += 1
            let start = pos
            while pos < len && isIdentChar(src[pos]) {
                pos += 1
            }
            let kw = stringFromBytes(src, from: start, to: pos)
            return Token(kind: TokenKind.atKeyword, value: kw)
        }

        // Hash / ID: #header, #fff
        if b == 35 { // '#'
            pos += 1
            let start = pos
            while pos < len && (isIdentChar(src[pos]) || src[pos] == 45) {
                pos += 1
            }
            let hashVal = "#" + stringFromBytes(src, from: start, to: pos)
            return Token(kind: TokenKind.hash, value: hashVal)
        }

        // Numbers, dimensions, percentages: digits, or a sign or point
        // that digits follow.
        if startsNumber(pos) {
            return scanNumberOrDimension()
        }

        // Identifiers and functions
        if startsIdent(pos) {
            return scanIdent()
        }

        // Single delimiter character (. > + ~ * ! /)
        pos += 1
        var singleChar: [CChar] = [CChar(truncatingIfNeeded: b), 0]
        return Token(kind: TokenKind.delim, value: string(cString: singleChar))
    }

    func startsNumber(_ at: int) -> bool {
        if at >= len { return false }
        let b = src[at]
        if isDigit(b) { return true }
        if b == 46 { // '.'
            return at + 1 < len && isDigit(src[at + 1])
        }
        if b == 43 || b == 45 { // '+' '-'
            if at + 1 < len && isDigit(src[at + 1]) { return true }
            return at + 2 < len && src[at + 1] == 46 && isDigit(src[at + 2])
        }
        return false
    }

    func startsIdent(_ at: int) -> bool {
        if at >= len { return false }
        let b = src[at]
        if b == 45 { // '-'
            if at + 1 >= len { return false }
            let n = src[at + 1]
            return n == 45 || isIdentStart(n) || n >= 128
        }
        return isIdentStart(b) || b >= 128
    }

    func scanString(quote: uint8) -> Token {
        pos += 1 // skip quote
        var bytes: [uint8] = []
        while pos < len && src[pos] != quote && src[pos] != 10 {
            if src[pos] == 92 && pos + 1 < len { // '\' escape
                pos += 1
                if src[pos] == 10 {
                    pos += 1
                    continue
                }
                if isHexDigit(src[pos]) {
                    var code: uint32 = 0
                    var n = 0
                    while pos < len && n < 6 && isHexDigit(src[pos]) {
                        code = code * 16 + hexDigit(src[pos])
                        pos += 1
                        n += 1
                    }
                    if pos < len && isWhitespace(src[pos]) { pos += 1 }
                    appendUTF8(&bytes, code)
                    continue
                }
                bytes.append(src[pos])
                pos += 1
                continue
            }
            bytes.append(src[pos])
            pos += 1
        }
        if pos < len && src[pos] == quote {
            pos += 1
        }
        return Token(kind: TokenKind.string, value: stringFromBytes(bytes, from: 0, to: bytes.count))
    }

    func scanIdent() -> Token {
        var bytes: [uint8] = []
        while pos < len {
            let b = src[pos]
            if isIdentChar(b) || b >= 128 {
                bytes.append(b)
                pos += 1
            } else if b == 92 && pos + 1 < len { // '\' escape
                pos += 1
                if isHexDigit(src[pos]) {
                    var code: uint32 = 0
                    var n = 0
                    while pos < len && n < 6 && isHexDigit(src[pos]) {
                        code = code * 16 + hexDigit(src[pos])
                        pos += 1
                        n += 1
                    }
                    if pos < len && isWhitespace(src[pos]) { pos += 1 }
                    appendUTF8(&bytes, code)
                } else {
                    bytes.append(src[pos])
                    pos += 1
                }
            } else {
                break
            }
        }
        let val = stringFromBytes(bytes, from: 0, to: bytes.count)
        if pos < len && src[pos] == 40 { // '('
            pos += 1
            if toLower(val) == "url" {
                return scanURL()
            }
            return Token(kind: TokenKind.function, value: val)
        }
        return Token(kind: TokenKind.ident, value: val)
    }

    // scanURL reads the rest of url(...): an unquoted URL up to the
    // closing paren, or a quoted string, which is the same token.
    func scanURL() -> Token {
        while pos < len && isWhitespace(src[pos]) { pos += 1 }
        if pos < len && (src[pos] == 34 || src[pos] == 39) {
            let str = scanString(quote: src[pos])
            while pos < len && isWhitespace(src[pos]) { pos += 1 }
            if pos < len && src[pos] == 41 { pos += 1 }
            return Token(kind: TokenKind.url, value: str.Value)
        }
        let start = pos
        while pos < len && src[pos] != 41 && !isWhitespace(src[pos]) {
            pos += 1
        }
        let val = stringFromBytes(src, from: start, to: pos)
        while pos < len && src[pos] != 41 { pos += 1 }
        if pos < len { pos += 1 }
        return Token(kind: TokenKind.url, value: val)
    }

    func scanNumberOrDimension() -> Token {
        let start = pos
        if src[pos] == 43 || src[pos] == 45 { pos += 1 }
        while pos < len && isDigit(src[pos]) {
            pos += 1
        }
        if pos < len && src[pos] == 46 && pos + 1 < len && isDigit(src[pos + 1]) { // '.'
            pos += 1
            while pos < len && isDigit(src[pos]) {
                pos += 1
            }
        }
        // An exponent: e5, E-2, but not the `em` of `1em`.
        if pos < len && (src[pos] == 101 || src[pos] == 69) {
            var q = pos + 1
            if q < len && (src[q] == 43 || src[q] == 45) { q += 1 }
            if q < len && isDigit(src[q]) {
                pos = q
                while pos < len && isDigit(src[pos]) { pos += 1 }
            }
        }

        let numStr = stringFromBytes(src, from: start, to: pos)
        let numVal = parseNumber(numStr)

        if pos < len && src[pos] == 37 { // '%'
            pos += 1
            return Token(kind: TokenKind.percentage, value: numStr + "%", unit: "%", numberVal: numVal)
        }

        if startsIdent(pos) {
            let unitStart = pos
            while pos < len && (isIdentChar(src[pos]) || src[pos] >= 128) {
                pos += 1
            }
            let unitStr = toLower(stringFromBytes(src, from: unitStart, to: pos))
            return Token(kind: TokenKind.dimension, value: numStr + unitStr, unit: unitStr, numberVal: numVal)
        }

        return Token(kind: TokenKind.number, value: numStr, unit: "", numberVal: numVal)
    }

    func parseNumber(_ s: string) -> float32 {
        let bytes = bytesFromString(s)
        var i = 0
        var negative = false
        if i < bytes.count && (bytes[i] == 45 || bytes[i] == 43) {
            negative = bytes[i] == 45
            i += 1
        }
        var value: float32 = 0.0
        while i < bytes.count && isDigit(bytes[i]) {
            value = value * 10.0 + float32(bytes[i] - 48)
            i += 1
        }
        if i < bytes.count && bytes[i] == 46 {
            i += 1
            var scale: float32 = 0.1
            while i < bytes.count && isDigit(bytes[i]) {
                value += float32(bytes[i] - 48) * scale
                scale *= 0.1
                i += 1
            }
        }
        if i < bytes.count && (bytes[i] == 101 || bytes[i] == 69) {
            i += 1
            var expNegative = false
            if i < bytes.count && (bytes[i] == 45 || bytes[i] == 43) {
                expNegative = bytes[i] == 45
                i += 1
            }
            var exp = 0
            while i < bytes.count && isDigit(bytes[i]) {
                exp = exp * 10 + int(bytes[i] - 48)
                i += 1
            }
            var k = 0
            while k < exp {
                if expNegative { value *= 0.1 } else { value *= 10 }
                k += 1
            }
        }
        return negative ? -value : value
    }

    // skipWhitespaceAndComments moves past both and says whether there
    // were any.
    func skipWhitespaceAndComments() -> bool {
        var skipped = false
        while pos < len {
            if isWhitespace(src[pos]) {
                pos += 1
                skipped = true
                continue
            }
            // Comment: /* ... */
            if src[pos] == 47 && pos + 1 < len && src[pos + 1] == 42 { // "/*"
                pos += 2
                skipped = true
                while pos + 1 < len {
                    if src[pos] == 42 && src[pos + 1] == 47 { // "*/"
                        pos += 2
                        break
                    }
                    pos += 1
                }
                continue
            }
            break
        }
        return skipped
    }
}

func isHexDigit(_ b: uint8) -> bool {
    return isDigit(b) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70)
}

func hexDigit(_ b: uint8) -> uint32 {
    if isDigit(b) { return uint32(b - 48) }
    if b >= 97 && b <= 102 { return uint32(b - 97 + 10) }
    return uint32(b - 65 + 10)
}

func appendUTF8(_ out: inout [uint8], _ code: uint32) {
    var c = code
    if c == 0 || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF) { c = 0xFFFD }
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
