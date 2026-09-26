package css

/// The kind of CSS token produced by the scanner.
public enum TokenKind: Equatable {
    case eof
    case ident
    /// An identifier followed by `(`: `rgb(`, `calc(`. The value is the
    /// name; the arguments follow as tokens up to the closing paren.
    case function
    /// `url(...)` with an unquoted argument; the value is the URL.
    case url
    case hash
    case string
    case number
    case dimension
    case percentage
    case colon
    case semicolon
    case comma
    case openBrace
    case closeBrace
    case openParen
    case closeParen
    case openBracket
    case closeBracket
    case atKeyword
    case delim
}

/// A CSS token emitted by the scanner.
public struct Token {
    public var Kind: TokenKind
    public var Value: string
    public var Unit: string
    public var NumberVal: float32
    /// Whether whitespace or a comment came before it: what separates
    /// `a b` from `ab` and `1px 2px` from `1px2px`.
    public var SpaceBefore: bool

    public init(kind: TokenKind, value: string = "", unit: string = "", numberVal: float32 = 0.0, spaceBefore: bool = false) {
        self.Kind = kind
        self.Value = value
        self.Unit = unit
        self.NumberVal = numberVal
        self.SpaceBefore = spaceBefore
    }
}

/// The text a run of tokens spells, with a space wherever the source had
/// one and strings quoted again.
public func Serialize(_ tokens: [Token]) -> string {
    var out = ""
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if i > 0 && t.SpaceBefore {
            out += " "
        }
        switch t.Kind {
        case .string:
            out += "\"" + t.Value + "\""
        case .function:
            out += t.Value + "("
        case .url:
            out += "url(\"" + t.Value + "\")"
        default:
            out += t.Value
        }
        i += 1
    }
    return out
}
