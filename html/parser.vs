package html

/// Parses HTML tokens into an HTML Document tree.
///
/// Tags that the standard lets a page leave out are closed as the
/// standard closes them: a `<p>` ends at the next block, an `<li>` at the
/// next `<li>`, a cell at the next cell. A document without `<html>`,
/// `<head>` and `<body>` gets them, with what belongs in the head moved
/// there, as a browser's tree builder does.
public class Parser {
    var scanner: Scanner
    var root: Node
    var stack: [Node]

    public init(scanner: Scanner) {
        self.scanner = scanner
        self.root = Node(kind: NodeKind.document)
        self.stack = [self.root]
    }

    var current: Node { return stack[stack.count - 1] }

    /// Parses the entire HTML stream and returns the Document.
    public func Parse() -> Document {
        while true {
            let token = scanner.Next()
            if token.Kind == TokenKind.eof {
                break
            }

            switch token.Kind {
            case .text:
                if !token.Data.isEmpty {
                    let textNode = Node(kind: NodeKind.text, text: token.Data)
                    current.AppendChild(textNode)
                }

            case .comment:
                let commentNode = Node(kind: NodeKind.comment, text: token.Data)
                current.AppendChild(commentNode)

            case .doctype:
                break

            case .selfClosingTag:
                impliedEnds(before: token.Data)
                let elem = Node(kind: NodeKind.element, tagName: token.Data, attributes: token.Attributes)
                current.AppendChild(elem)

            case .startTag:
                impliedEnds(before: token.Data)
                let elem = Node(kind: NodeKind.element, tagName: token.Data, attributes: token.Attributes)
                current.AppendChild(elem)

                // Inside <script>, <style>, <textarea> and <title> the text is
                // not markup: it runs to the closing tag.
                if isRawTextElement(token.Data) {
                    let rawTextToken = scanner.ScanRawTextUntilClose(tag: token.Data)
                    if !rawTextToken.Data.isEmpty {
                        let text = isEscapableRawText(token.Data) ? Unescape(rawTextToken.Data) : rawTextToken.Data
                        let textNode = Node(kind: NodeKind.text, text: text)
                        elem.AppendChild(textNode)
                    }
                    // Scanner is now positioned at </script> or </style>, let loop consume it
                } else {
                    stack.append(elem)
                }

            case .endTag:
                // Find matching tag in the stack from top down
                var i = stack.count - 1
                while i > 0 {
                    if stack[i].TagName == token.Data {
                        // Pop stack down to this element
                        while stack.count > i {
                            _ = stack.remove(at: stack.count - 1)
                        }
                        break
                    }
                    i -= 1
                }

            case .eof:
                break
            }
        }

        normalize()
        return Document(root: root)
    }

    // impliedEnds closes what a start tag ends without saying so.
    func impliedEnds(before tag: string) {
        if closesParagraph(tag) {
            closeIfOpen("p", within: ["p"])
        }
        if tag == "li" {
            closeIfOpen("li", within: ["ul", "ol", "menu"])
        } else if tag == "dt" || tag == "dd" {
            closeIfOpen("dt", within: ["dl"])
            closeIfOpen("dd", within: ["dl"])
        } else if tag == "option" {
            closeIfOpen("option", within: ["select", "datalist", "optgroup"])
        } else if tag == "optgroup" {
            closeIfOpen("option", within: ["select"])
            closeIfOpen("optgroup", within: ["select"])
        } else if tag == "tr" {
            closeIfOpen("td", within: ["table"])
            closeIfOpen("th", within: ["table"])
            closeIfOpen("tr", within: ["table"])
        } else if tag == "td" || tag == "th" {
            closeIfOpen("td", within: ["tr", "table"])
            closeIfOpen("th", within: ["tr", "table"])
        } else if tag == "thead" || tag == "tbody" || tag == "tfoot" {
            closeIfOpen("td", within: ["table"])
            closeIfOpen("th", within: ["table"])
            closeIfOpen("tr", within: ["table"])
            closeIfOpen("thead", within: ["table"])
            closeIfOpen("tbody", within: ["table"])
            closeIfOpen("tfoot", within: ["table"])
        } else if tag == "body" || tag == "head" {
            // A second <body> or <head> is the first one's attributes.
        }
    }

    // closeIfOpen pops the stack to below the nearest open `tag`, unless
    // one of the scopes is nearer, in which case nothing is open to close.
    func closeIfOpen(_ tag: string, within scopes: [string]) {
        var i = stack.count - 1
        while i > 0 {
            let name = stack[i].TagName
            if name == tag {
                while stack.count > i {
                    _ = stack.remove(at: stack.count - 1)
                }
                return
            }
            var s = 0
            while s < scopes.count {
                if name == scopes[s] { return }
                s += 1
            }
            i -= 1
        }
    }

    // normalize gives the document its html, head and body where the
    // source left them out.
    func normalize() {
        var html: Node? = nil
        var i = 0
        while i < root.Children.count {
            let c = root.Children[i]
            if c.Kind == NodeKind.element && c.TagName == "html" {
                html = c
                break
            }
            i += 1
        }
        if html == nil {
            let made = Node(kind: NodeKind.element, tagName: "html")
            let moved = root.Children
            root.Children = []
            var j = 0
            while j < moved.count {
                let c = moved[j]
                if c.Kind == NodeKind.comment {
                    root.AppendChild(c)
                } else {
                    made.AppendChild(c)
                }
                j += 1
            }
            root.AppendChild(made)
            html = made
        }
        guard let h = html else { return }
        var head: Node? = nil
        var body: Node? = nil
        i = 0
        while i < h.Children.count {
            let c = h.Children[i]
            if c.Kind == NodeKind.element {
                if c.TagName == "head" && head == nil { head = c }
                if c.TagName == "body" && body == nil { body = c }
            }
            i += 1
        }
        if head != nil && body != nil { return }
        let newHead = head ?? Node(kind: NodeKind.element, tagName: "head")
        let newBody = body ?? Node(kind: NodeKind.element, tagName: "body")
        let moved = h.Children
        h.Children = []
        var j = 0
        while j < moved.count {
            let c = moved[j]
            if c.Id == newHead.Id || c.Id == newBody.Id {
                j += 1
                continue
            }
            if c.Kind == NodeKind.element && belongsInHead(c.TagName) && body == nil {
                newHead.AppendChild(c)
            } else if c.Kind == NodeKind.text && isBlank(c.Text) && newBody.Children.isEmpty {
                // Whitespace between the head's elements is not content.
                newHead.AppendChild(c)
            } else {
                newBody.AppendChild(c)
            }
            j += 1
        }
        h.AppendChild(newHead)
        h.AppendChild(newBody)
    }
}

// The elements whose start tag ends an open paragraph (HTML 13.2.6.4.7).
func closesParagraph(_ tag: string) -> bool {
    switch tag {
    case "address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl",
         "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
         "hgroup", "hr", "main", "menu", "nav", "ol", "p", "pre", "section", "summary", "table", "ul",
         "li", "dt", "dd", "plaintext", "xmp", "listing":
        return true
    default:
        return false
    }
}

func belongsInHead(_ tag: string) -> bool {
    return tag == "title" || tag == "meta" || tag == "link" || tag == "style" || tag == "script" ||
        tag == "base" || tag == "noscript"
}

func isBlank(_ s: string) -> bool {
    for b in s.utf8 {
        if !isWhitespace(b) { return false }
    }
    return true
}
