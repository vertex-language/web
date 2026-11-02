package dom

import (
    "web/html"
    "unicode/utf8"
)

/// A point in the document's text: a text node and a byte offset into
/// its text. One end of a selection.
public struct TextPosition {
    public var Node: html.Node
    public var Offset: int

    public init(Node: html.Node, Offset: int) {
        self.Node = Node
        self.Offset = Offset
    }
}

/// The nearest element at or above a node with a tag name, or nil.
public func Ancestor(node: html.Node?, tag: string) -> html.Node? {
    var cur = node
    while let n = cur {
        if n.Kind == html.NodeKind.element && n.TagName == tag { return n }
        cur = n.Parent
    }
    return nil
}

/// The link a node is inside: the nearest `<a>` or `<area>` with an href.
public func LinkAncestor(node: html.Node?) -> html.Node? {
    var cur = node
    while let n = cur {
        if n.Kind == html.NodeKind.element && (n.TagName == "a" || n.TagName == "area") && n.HasAttribute("href") { return n }
        cur = n.Parent
    }
    return nil
}

/// The form control a node is inside: the nearest input, textarea,
/// button or select.
public func ControlAncestor(node: html.Node?) -> html.Node? {
    var cur = node
    while let n = cur {
        if n.Kind == html.NodeKind.element {
            let t = n.TagName
            if t == "input" || t == "textarea" || t == "button" || t == "select" { return n }
        }
        cur = n.Parent
    }
    return nil
}

/// Whether a is b or one of b's ancestors.
public func Contains(a: html.Node, b: html.Node) -> bool {
    var cur: html.Node? = b
    while let n = cur {
        if n.Id == a.Id { return true }
        cur = n.Parent
    }
    return false
}

/// The elements under a node with a tag name, in document order.
public func Descendants(node: html.Node, tag: string) -> [html.Node] {
    var out: [html.Node] = []
    collectTags(node, tag, &out)
    return out
}

func collectTags(node: html.Node, tag: string, out: inout [html.Node]) {
    for c in node.Children where c.Kind == html.NodeKind.element {
        if c.TagName == tag { out.append(c) }
        collectTags(c, tag, &out)
    }
}

/// An ASCII-lowercased copy, for attribute values HTML compares
/// case-insensitively.
func lower(s: string) -> string {
    var b = [uint8](s.utf8)
    var changed = false
    var i = 0
    while i < b.count {
        if b[i] >= 65 && b[i] <= 90 {
            b[i] += 32
            changed = true
        }
        i += 1
    }
    if !changed { return s }
    return stringOf(b, 0, b.count)
}

/// Leading and trailing ASCII whitespace removed.
func trimSpaces(s: string) -> string {
    let b = [uint8](s.utf8)
    var start = 0
    var end = b.count
    while start < end && (b[start] == 32 || b[start] == 9 || b[start] == 10 || b[start] == 13) { start += 1 }
    while end > start && (b[end - 1] == 32 || b[end - 1] == 9 || b[end - 1] == 10 || b[end - 1] == 13) { end -= 1 }
    if start == 0 && end == b.count { return s }
    return stringOf(b, start, end)
}

func stringOf(bytes: [uint8], start: int, end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}
