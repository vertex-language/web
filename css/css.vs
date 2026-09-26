package css

/// Parses a CSS stylesheet string into a StyleSheet struct.
public func Parse(_ source: string) -> StyleSheet {
    let scanner = Scanner(source: source)
    let parser = Parser(scanner: scanner)
    return parser.Parse()
}

/// Parses CSS bytes into a StyleSheet struct.
public func Parse(_ sourceBytes: borrowing [uint8]) -> StyleSheet {
    var bytes: [uint8] = []
    for b in sourceBytes {
        bytes.append(b)
    }
    let scanner = Scanner(bytes: bytes)
    let parser = Parser(scanner: scanner)
    return parser.Parse()
}

/// Parses an inline CSS style attribute (e.g. `color: red; font-size: 14px;`).
public func ParseDeclarations(_ inlineStyle: string) -> [Declaration] {
    let wrapped = "body { " + inlineStyle + " }"
    let sheet = Parse(wrapped)
    if !sheet.Rules.isEmpty {
        return sheet.Rules[0].Declarations
    }
    return []
}
