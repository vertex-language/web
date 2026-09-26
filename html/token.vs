package html

/// The kind of HTML token produced by the scanner.
public enum TokenKind: Equatable {
    case eof
    case doctype
    case startTag
    case endTag
    case selfClosingTag
    case text
    case comment
}

/// An attribute on an HTML element, such as `class="btn"`.
public struct Attribute: Equatable {
    public var Name: string
    public var Value: string

    public init(_ name: string, _ value: string = "") {
        self.Name = name
        self.Value = value
    }
}

/// A token emitted during HTML scanning.
public struct Token {
    public var Kind: TokenKind
    public var Data: string
    public var Attributes: [Attribute]

    public init(kind: TokenKind, data: string = "", attributes: [Attribute] = []) {
        self.Kind = kind
        self.Data = data
        self.Attributes = attributes
    }
}
