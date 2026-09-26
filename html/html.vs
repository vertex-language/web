package html

/// Parses an HTML source string into a Document tree.
public func Parse(_ source: string) -> Document {
    let scanner = Scanner(source: source)
    let parser = Parser(scanner: scanner)
    return parser.Parse()
}

/// Parses HTML bytes into a Document tree.
public func Parse(_ sourceBytes: borrowing [uint8]) -> Document {
    var bytes: [uint8] = []
    for b in sourceBytes {
        bytes.append(b)
    }
    let scanner = Scanner(bytes: bytes)
    let parser = Parser(scanner: scanner)
    return parser.Parse()
}

/// Parses an HTML fragment and returns the top-level nodes.
public func ParseFragment(_ source: string) -> [Node] {
    let doc = Parse(source)
    return doc.Root.Children
}
