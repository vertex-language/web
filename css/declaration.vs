package css

/// A single CSS property declaration, such as `color: red !important;`.
/// `Value` is the value's text, spaced as the source spaced it; `Tokens`
/// is the same as the scanner read it, for a reader that wants the
/// structure rather than the text.
public struct Declaration {
    public var Property: string
    public var Value: string
    public var Important: bool
    public var Tokens: [Token]

    public init(property: string, value: string, important: bool = false, tokens: [Token] = []) {
        self.Property = toLower(property)
        self.Value = value
        self.Important = important
        self.Tokens = tokens
    }
}
