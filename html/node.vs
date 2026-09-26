package html

var nextNodeId: int64 = 1

func getNextNodeId() -> int64 {
    let id = nextNodeId
    nextNodeId += 1
    return id
}

/// The kind of node in the HTML DOM tree.
public enum NodeKind: Equatable {
    case document
    case element
    case text
    case comment
}

/// A node in the HTML document tree.
public class Node {
    public let Id: int64
    public var Kind: NodeKind
    public var TagName: string
    public var Attributes: [Attribute]
    public var Text: string
    public var Children: [Node]
    public weak var Parent: Node?

    public init(kind: NodeKind, tagName: string = "", text: string = "", attributes: [Attribute] = []) {
        self.Id = getNextNodeId()
        self.Kind = kind
        self.TagName = tagName
        self.Text = text
        self.Attributes = attributes
        self.Children = []
        self.Parent = nil
    }

    // MARK: - Attributes & Classes

    /// Looks up an attribute value by name. Names are lowercase as the
    /// parser stores them, and a name asked for in any case is found.
    public func GetAttribute(_ name: string) -> string? {
        let lower = toLower(name)
        var i = 0
        while i < Attributes.count {
            if Attributes[i].Name == lower {
                return Attributes[i].Value
            }
            i += 1
        }
        return nil
    }

    /// Sets or updates an attribute.
    public func SetAttribute(_ name: string, _ value: string) {
        let lower = toLower(name)
        var i = 0
        while i < Attributes.count {
            if Attributes[i].Name == lower {
                Attributes[i].Value = value
                return
            }
            i += 1
        }
        Attributes.append(Attribute(lower, value))
    }

    /// Removes an attribute, if it has it.
    public func RemoveAttribute(_ name: string) {
        let lower = toLower(name)
        var i = 0
        while i < Attributes.count {
            if Attributes[i].Name == lower {
                Attributes.remove(at: i)
                return
            }
            i += 1
        }
    }

    /// Whether the element has the specified attribute.
    public func HasAttribute(_ name: string) -> bool {
        return GetAttribute(name) != nil
    }

    /// The `id` attribute of this element if present.
    public func IdAttr() -> string? {
        return GetAttribute("id")
    }

    /// All class names specified on this element.
    public func Classes() -> [string] {
        guard let classAttr = GetAttribute("class") else {
            return []
        }
        var list: [string] = []
        var current: [uint8] = []
        for b in classAttr.utf8 {
            if b == 32 || b == 9 || b == 10 || b == 13 { // whitespace
                if !current.isEmpty {
                    list.append(stringFromBytes(current, from: 0, to: current.count))
                    current = []
                }
            } else {
                current.append(b)
            }
        }
        if !current.isEmpty {
            list.append(stringFromBytes(current, from: 0, to: current.count))
        }
        return list
    }

    /// Returns true if this element contains the specified class.
    public func HasClass(_ className: string) -> bool {
        guard let classAttr = GetAttribute("class") else { return false }
        if classAttr == className { return true }
        // A word of the attribute, without making the words.
        let b = [uint8](classAttr.utf8)
        let want = [uint8](className.utf8)
        if want.isEmpty { return false }
        var i = 0
        while i < b.count {
            while i < b.count && isWhitespace(b[i]) { i += 1 }
            let start = i
            while i < b.count && !isWhitespace(b[i]) { i += 1 }
            if i - start == want.count {
                var k = 0
                var same = true
                while k < want.count {
                    if b[start + k] != want[k] { same = false; break }
                    k += 1
                }
                if same { return true }
            }
        }
        return false
    }

    // MARK: - Tree Navigation & Mutation

    /// Appends a child node to this node's children.
    public func AppendChild(_ child: Node) {
        child.Parent = self
        Children.append(child)
    }

    /// Removes a child node.
    public func RemoveChild(_ child: Node) {
        var i = 0
        while i < Children.count {
            if Children[i].Id == child.Id {
                child.Parent = nil
                Children.remove(at: i)
                return
            }
            i += 1
        }
    }

    /// Returns the first child node, or nil.
    public func FirstChild() -> Node? {
        return Children.isEmpty ? nil : Children[0]
    }

    /// Returns the last child node, or nil.
    public func LastChild() -> Node? {
        return Children.isEmpty ? nil : Children[Children.count - 1]
    }

    /// Returns the previous sibling node in the parent's children list.
    public func PreviousSibling() -> Node? {
        guard let p = Parent else { return nil }
        var i = 0
        while i < p.Children.count {
            if p.Children[i].Id == self.Id {
                if i > 0 { return p.Children[i - 1] }
                return nil
            }
            i += 1
        }
        return nil
    }

    /// Returns the next sibling node in the parent's children list.
    public func NextSibling() -> Node? {
        guard let p = Parent else { return nil }
        var i = 0
        while i < p.Children.count {
            if p.Children[i].Id == self.Id {
                if i + 1 < p.Children.count { return p.Children[i + 1] }
                return nil
            }
            i += 1
        }
        return nil
    }

    /// Returns the previous sibling element, skipping text and comment nodes.
    public func PreviousElementSibling() -> Node? {
        guard let p = Parent else { return nil }
        var idx = -1
        var i = 0
        while i < p.Children.count {
            if p.Children[i].Id == self.Id {
                idx = i
                break
            }
            i += 1
        }
        if idx <= 0 { return nil }
        var j = idx - 1
        while j >= 0 {
            if p.Children[j].Kind == NodeKind.element {
                return p.Children[j]
            }
            j -= 1
        }
        return nil
    }

    /// Returns the next sibling element, skipping text and comment nodes.
    public func NextElementSibling() -> Node? {
        guard let p = Parent else { return nil }
        var idx = -1
        var i = 0
        while i < p.Children.count {
            if p.Children[i].Id == self.Id {
                idx = i
                break
            }
            i += 1
        }
        if idx < 0 { return nil }
        var j = idx + 1
        while j < p.Children.count {
            if p.Children[j].Kind == NodeKind.element {
                return p.Children[j]
            }
            j += 1
        }
        return nil
    }

    /// Extracts all text content recursively from this node and its descendants.
    public func InnerText() -> string {
        if Kind == NodeKind.text {
            return Text
        }
        var out = ""
        var i = 0
        while i < Children.count {
            out += Children[i].InnerText()
            i += 1
        }
        return out
    }
}

/// An HTML document containing a root document node.
public struct Document {
    public let Root: Node

    public init(root: Node) {
        self.Root = root
    }

    /// The page title from `<title>`, or empty string if not found.
    public var Title: string {
        let titles = ElementsByTagName("title")
        if !titles.isEmpty {
            return titles[0].InnerText()
        }
        return ""
    }

    /// Finds the first element with the given ID.
    public func ElementById(_ id: string) -> Node? {
        return findById(Root, id)
    }

    /// Finds all elements with the given tag name (case-insensitive).
    public func ElementsByTagName(_ tag: string) -> [Node] {
        var results: [Node] = []
        let lower = toLower(tag)
        findTags(Root, lower, &results)
        return results
    }

    /// Finds all elements containing the specified class name.
    public func ElementsByClassName(_ className: string) -> [Node] {
        var results: [Node] = []
        findClasses(Root, className, &results)
        return results
    }
}

// Internal recursive search helpers
func findById(_ node: Node, _ id: string) -> Node? {
    if node.Kind == NodeKind.element && node.IdAttr() == id {
        return node
    }
    var i = 0
    while i < node.Children.count {
        if let match = findById(node.Children[i], id) {
            return match
        }
        i += 1
    }
    return nil
}

func findTags(_ node: Node, _ lowerTag: string, _ out: inout [Node]) {
    if node.Kind == NodeKind.element && (lowerTag == "*" || toLower(node.TagName) == lowerTag) {
        out.append(node)
    }
    var i = 0
    while i < node.Children.count {
        findTags(node.Children[i], lowerTag, &out)
        i += 1
    }
}

func findClasses(_ node: Node, _ className: string, _ out: inout [Node]) {
    if node.Kind == NodeKind.element && node.HasClass(className) {
        out.append(node)
    }
    var i = 0
    while i < node.Children.count {
        findClasses(node.Children[i], className, &out)
        i += 1
    }
}
