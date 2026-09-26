package html

/// Tokenizer that scans HTML source bytes into Token stream.
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

    /// Fetches the next token from the HTML stream.
    public func Next() -> Token {
        if pos >= len {
            return Token(kind: TokenKind.eof)
        }

        // Tag or comment or doctype starts with '<'
        if src[pos] == 60 { // '<'
            if pos + 1 < len {
                // Comment: <!--
                if src[pos + 1] == 33 && pos + 3 < len && src[pos + 2] == 45 && src[pos + 3] == 45 { // "<!--"
                    return scanComment()
                }
                // Doctype: <!DOCTYPE ...> or <!...>
                if src[pos + 1] == 33 { // "<!"
                    return scanDoctype()
                }
                // End tag: </tag>
                if src[pos + 1] == 47 { // "</"
                    return scanEndTag()
                }
                // Start tag or self-closing tag: <tag ...>
                if isTagChar(src[pos + 1]) {
                    return scanStartTag()
                }
            }
        }

        // Otherwise scan plain text until next '<'
        return scanText()
    }

    func scanComment() -> Token {
        pos += 4 // skip "<!--"
        let start = pos
        while pos + 2 < len {
            if src[pos] == 45 && src[pos + 1] == 45 && src[pos + 2] == 62 { // "-->"
                let text = stringFromBytes(src, from: start, to: pos)
                pos += 3
                return Token(kind: TokenKind.comment, data: text)
            }
            pos += 1
        }
        // Unclosed comment up to EOF
        let text = stringFromBytes(src, from: start, to: len)
        pos = len
        return Token(kind: TokenKind.comment, data: text)
    }

    func scanDoctype() -> Token {
        pos += 2 // skip "<!"
        let start = pos
        while pos < len && src[pos] != 62 { // '>'
            pos += 1
        }
        let data = stringFromBytes(src, from: start, to: pos)
        if pos < len && src[pos] == 62 {
            pos += 1
        }
        return Token(kind: TokenKind.doctype, data: data)
    }

    func scanEndTag() -> Token {
        pos += 2 // skip "</"
        skipSpace()
        let start = pos
        while pos < len && isTagChar(src[pos]) {
            pos += 1
        }
        let tagName = toLower(stringFromBytes(src, from: start, to: pos))
        // Skip until '>'
        while pos < len && src[pos] != 62 {
            pos += 1
        }
        if pos < len && src[pos] == 62 {
            pos += 1
        }
        return Token(kind: TokenKind.endTag, data: tagName)
    }

    func scanStartTag() -> Token {
        pos += 1 // skip '<'
        let start = pos
        while pos < len && isTagChar(src[pos]) {
            pos += 1
        }
        let tagName = toLower(stringFromBytes(src, from: start, to: pos))
        var attrs: [Attribute] = []
        var selfClosing = false

        while pos < len {
            skipSpace()
            if pos >= len { break }

            if src[pos] == 62 { // '>'
                pos += 1
                break
            }

            if src[pos] == 47 { // '/'
                if pos + 1 < len && src[pos + 1] == 62 { // "/>"
                    selfClosing = true
                    pos += 2
                    break
                }
                pos += 1
                continue
            }

            // Scan attribute name
            let attrStart = pos
            while pos < len && src[pos] != 61 && src[pos] != 62 && src[pos] != 47 && !isWhitespace(src[pos]) {
                pos += 1
            }
            if pos == attrStart {
                pos += 1
                continue
            }
            let attrName = toLower(stringFromBytes(src, from: attrStart, to: pos))
            var attrVal = ""

            skipSpace()
            if pos < len && src[pos] == 61 { // '='
                pos += 1 // skip '='
                skipSpace()
                if pos < len && src[pos] == 34 { // '"'
                    pos += 1
                    let valStart = pos
                    while pos < len && src[pos] != 34 {
                        pos += 1
                    }
                    attrVal = Unescape(stringFromBytes(src, from: valStart, to: pos))
                    if pos < len && src[pos] == 34 { pos += 1 }
                } else if pos < len && src[pos] == 39 { // '\''
                    pos += 1
                    let valStart = pos
                    while pos < len && src[pos] != 39 {
                        pos += 1
                    }
                    attrVal = Unescape(stringFromBytes(src, from: valStart, to: pos))
                    if pos < len && src[pos] == 39 { pos += 1 }
                } else {
                    // Unquoted value
                    let valStart = pos
                    while pos < len && src[pos] != 62 && src[pos] != 47 && !isWhitespace(src[pos]) {
                        pos += 1
                    }
                    attrVal = Unescape(stringFromBytes(src, from: valStart, to: pos))
                }
            } else {
                // A boolean attribute (`required`, `checked`) has the
                // empty string as its value, as the DOM gives it.
                attrVal = ""
            }
            attrs.append(Attribute(attrName, attrVal))
        }

        if isVoidElement(tagName) {
            selfClosing = true
        }

        let kind: TokenKind = selfClosing ? TokenKind.selfClosingTag : TokenKind.startTag
        return Token(kind: kind, data: tagName, attributes: attrs)
    }

    /// Scans raw text until the matching closing tag </tagName> for `<script>` and `<style>`.
    public func ScanRawTextUntilClose(tag: string) -> Token {
        let start = pos
        let lowerTag = toLower(tag)
        let tagBytes = bytesFromString(lowerTag)

        while pos + tagBytes.count + 2 < len {
            if src[pos] == 60 && src[pos + 1] == 47 { // "</"
                var match = true
                var j = 0
                while j < tagBytes.count {
                    let b = src[pos + 2 + j]
                    let lowerB = (b >= 65 && b <= 90) ? (b + 32) : b
                    if lowerB != tagBytes[j] {
                        match = false
                        break
                    }
                    j += 1
                }
                if match {
                    let endTagPos = pos + 2 + tagBytes.count
                    if endTagPos < len && (src[endTagPos] == 62 || isWhitespace(src[endTagPos])) {
                        // Found closing tag!
                        let text = stringFromBytes(src, from: start, to: pos)
                        return Token(kind: TokenKind.text, data: text)
                    }
                }
            }
            pos += 1
        }
        let text = stringFromBytes(src, from: start, to: len)
        pos = len
        return Token(kind: TokenKind.text, data: text)
    }

    func scanText() -> Token {
        let start = pos
        while pos < len && src[pos] != 60 { // '<'
            pos += 1
        }
        let raw = stringFromBytes(src, from: start, to: pos)
        let text = Unescape(raw)
        return Token(kind: TokenKind.text, data: text)
    }

    func skipSpace() {
        while pos < len && isWhitespace(src[pos]) {
            pos += 1
        }
    }
}
