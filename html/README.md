# web/html

The HTML tokenizer and tree builder, entities, the node tree, and a serializer. Character encodings as the HTML standard detects them (a byte order mark, the HTTP charset, `<meta charset>`), decoded from UTF-8, UTF-16 and windows-1252 (`Decode`).

```vertex
import "web/html"
```

## Types

- **`NodeKind`** (enum): The kind of node in the HTML DOM tree.
- **`Node`** (class): A node in the HTML document tree.
- **`Document`** (struct): An HTML document containing a root document node.
- **`Parser`** (class): Parses HTML tokens into an HTML Document tree.
- **`Scanner`** (class): Tokenizer that scans HTML source bytes into Token stream.
- **`TokenKind`** (enum): The kind of HTML token produced by the scanner.
- **`Attribute`** (struct): An attribute on an HTML element, such as `class="btn"`.
- **`Token`** (struct): A token emitted during HTML scanning.

## Functions

- `func DetectEncoding(_ bytes: [uint8], contentType: string? = nil) -> string`: The encoding a document's bytes are in, as the HTML standard finds it: a byte order mark first, then the charset its HTTP Content-Type names, then a <meta charset> or <meta http-equiv=content-type> in its first 1024 bytes, and UTF-8 otherwise.
- `func EncodingForLabel(_ label: string) -> string?`: The encoding a label names, or nil for one not supported here.
- `func Decode(_ bytes: [uint8], contentType: string? = nil) -> string`: A document's bytes as text, in the encoding DetectEncoding finds. A byte order mark is dropped; what doesn't decode becomes U+FFFD.
- `func Escape(_ text: string) -> string`: Escapes special HTML characters (`&`, `<`, `>`, `"`, `'`).
- `func Unescape(_ text: string) -> string`: Decodes standard HTML entities in text (e.g. `&amp;`, `&lt;`, `&#65;`).
- `func Parse(_ source: string) -> Document`: Parses an HTML source string into a Document tree.
- `func Parse(_ sourceBytes: borrowing [uint8]) -> Document`: Parses HTML bytes into a Document tree.
- `func ParseFragment(_ source: string) -> [Node]`: Parses an HTML fragment and returns the top-level nodes.
- `func Render(_ node: Node) -> string`: Serializes an HTML Node or Document tree into an HTML string.

Part of the [`web`](https://github.com/vertex-language/web) repository.
