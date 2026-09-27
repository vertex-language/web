package dom

import "web/html"

/// What a mutation changed, in MutationObserver's terms.
public enum MutationKind: Equatable {
    /// An attribute of Target was set, changed or removed.
    case attributes
    /// Children were added to or removed from Target.
    case childList
    /// A text node's text changed.
    case characterData
}

/// One change to the tree. The cascade turns these into the elements to
/// restyle, and layout into the boxes to rebuild.
public struct MutationRecord {
    public let Kind: MutationKind
    public let Target: html.Node
    /// The attribute's name, lowercase, for `.attributes`.
    public let AttributeName: string
    /// What the attribute or text was before, or nil where it had none.
    public let OldValue: string?
    public let Added: [html.Node]
    public let Removed: [html.Node]

    public init(Kind: MutationKind, Target: html.Node, AttributeName: string = "", OldValue: string? = nil, Added: [html.Node] = [], Removed: [html.Node] = []) {
        self.Kind = Kind
        self.Target = Target
        self.AttributeName = AttributeName
        self.OldValue = OldValue
        self.Added = Added
        self.Removed = Removed
    }
}

/// The live document: the tree, and the journal of every change made to
/// it since the engine last looked. Mutating the tree through a Document
/// is what makes the page restyle; nothing else tells it.
///
/// A change that changes nothing -- setting an attribute to the value it
/// has -- is not recorded, so it costs no restyle.
public final class Document {
    public let Tree: html.Document
    var journal: [MutationRecord] = []

    public init(_ tree: html.Document) {
        Tree = tree
    }

    public var Root: html.Node { return Tree.Root }
    public var Title: string { return Tree.Title }

    /// The element with an id, or nil.
    public func ElementById(_ id: string) -> Element? {
        guard let n = Tree.ElementById(id) else { return nil }
        return Element(n, self)
    }

    /// A handle on a node of this document, for changing it.
    public func ElementFor(_ node: html.Node) -> Element {
        return Element(node, self)
    }

    // MARK: - The journal

    /// Whether anything changed since the last TakeRecords.
    public var HasMutations: bool { return !journal.isEmpty }

    /// The changes since the last call, oldest first, and an empty
    /// journal.
    public func TakeRecords() -> [MutationRecord] {
        let out = journal
        journal = []
        return out
    }

    // MARK: - Making nodes

    public func CreateElement(_ tagName: string) -> html.Node {
        return html.Node(kind: html.NodeKind.element, tagName: lower(tagName))
    }

    public func CreateTextNode(_ text: string) -> html.Node {
        return html.Node(kind: html.NodeKind.text, text: text)
    }

    // MARK: - Changing the tree

    /// Sets an attribute.
    public func SetAttribute(_ element: html.Node, _ name: string, _ value: string) {
        let key = lower(name)
        let old = element.GetAttribute(key)
        if let o = old, o == value { return }
        element.SetAttribute(key, value)
        journal.append(MutationRecord(Kind: .attributes, Target: element, AttributeName: key, OldValue: old))
    }

    /// Removes an attribute, if the element has it.
    public func RemoveAttribute(_ element: html.Node, _ name: string) {
        let key = lower(name)
        guard let old = element.GetAttribute(key) else { return }
        element.RemoveAttribute(key)
        journal.append(MutationRecord(Kind: .attributes, Target: element, AttributeName: key, OldValue: old))
    }

    /// Adds a boolean attribute where it is missing and removes it where
    /// present, or sets it to `force`. Answers whether it is there now.
    public func ToggleAttribute(_ element: html.Node, _ name: string, force: bool? = nil) -> bool {
        let want = force ?? !element.HasAttribute(name)
        if want {
            if !element.HasAttribute(name) { SetAttribute(element, name, "") }
        } else {
            RemoveAttribute(element, name)
        }
        return want
    }

    /// Appends a child, taking it from wherever it was first.
    public func AppendChild(_ parent: html.Node, _ child: html.Node) {
        InsertBefore(parent, child, nil)
    }

    /// Inserts a child before another of the parent's children, or last
    /// where `before` is nil.
    public func InsertBefore(_ parent: html.Node, _ child: html.Node, _ before: html.Node?) {
        if let old = child.Parent {
            RemoveChild(old, child)
        }
        parent.InsertBefore(child, before)
        journal.append(MutationRecord(Kind: .childList, Target: parent, Added: [child]))
    }

    /// Removes a child, if it is one.
    public func RemoveChild(_ parent: html.Node, _ child: html.Node) {
        guard let p = child.Parent, p.Id == parent.Id else { return }
        parent.RemoveChild(child)
        journal.append(MutationRecord(Kind: .childList, Target: parent, Removed: [child]))
    }

    /// Replaces a text node's text.
    public func SetText(_ node: html.Node, _ text: string) {
        if node.Text == text { return }
        let old = node.Text
        node.SetText(text)
        journal.append(MutationRecord(Kind: .characterData, Target: node, OldValue: old))
    }

    /// Replaces a node's children with one text node holding text, or
    /// with nothing for empty text. A lone text child is changed in place.
    public func SetTextContent(_ node: html.Node, _ text: string) {
        if node.Kind == html.NodeKind.text || node.Kind == html.NodeKind.comment {
            SetText(node, text)
            return
        }
        if node.Children.count == 1 && node.Children[0].Kind == html.NodeKind.text && !text.isEmpty {
            SetText(node.Children[0], text)
            return
        }
        let removed = node.Children
        if removed.isEmpty && text.isEmpty { return }
        for c in removed { node.RemoveChild(c) }
        var added: [html.Node] = []
        if !text.isEmpty {
            let t = CreateTextNode(text)
            node.AppendChild(t)
            added.append(t)
        }
        journal.append(MutationRecord(Kind: .childList, Target: node, Added: added, Removed: removed))
    }
}

/// An element of a live document: reads go to the node, changes go
/// through the document's journal. A handle: two for one node are the
/// same element.
public final class Element {
    public let Node: html.Node
    public let Owner: Document

    public init(_ node: html.Node, _ owner: Document) {
        Node = node
        Owner = owner
    }

    public var TagName: string { return Node.TagName }
    public var Id: string { return Node.GetAttribute("id") ?? "" }

    public func GetAttribute(_ name: string) -> string? { return Node.GetAttribute(name) }
    public func HasAttribute(_ name: string) -> bool { return Node.HasAttribute(name) }
    public func SetAttribute(_ name: string, _ value: string) { Owner.SetAttribute(Node, name, value) }
    public func RemoveAttribute(_ name: string) { Owner.RemoveAttribute(Node, name) }
    public func ToggleAttribute(_ name: string, force: bool? = nil) -> bool {
        return Owner.ToggleAttribute(Node, name, force: force)
    }

    /// The element's text, all of it, in document order.
    public var TextContent: string {
        get { return Node.InnerText() }
        set { Owner.SetTextContent(Node, newValue) }
    }

    public var ClassList: dom.ClassList { return dom.ClassList(self) }

    public var Parent: Element? {
        guard let p = Node.Parent else { return nil }
        return Element(p, Owner)
    }

    public func AppendChild(_ child: html.Node) { Owner.AppendChild(Node, child) }
    public func InsertBefore(_ child: html.Node, _ before: html.Node?) { Owner.InsertBefore(Node, child, before) }

    /// Takes the element out of the tree.
    public func Remove() {
        if let p = Node.Parent { Owner.RemoveChild(p, Node) }
    }
}

/// An element's classes, as the `class` attribute lists them.
public struct ClassList {
    let element: Element

    public init(_ element: Element) {
        self.element = element
    }

    public var Values: [string] { return element.Node.Classes() }
    public func Contains(_ name: string) -> bool { return element.Node.HasClass(name) }

    public func Add(_ name: string) {
        if name.isEmpty || Contains(name) { return }
        var names = Values
        names.append(name)
        write(names)
    }

    public func Remove(_ name: string) {
        if !Contains(name) { return }
        var names: [string] = []
        for n in Values where n != name { names.append(n) }
        write(names)
    }

    /// Adds the class where it is missing and removes it where present,
    /// or adds or removes it as `force` says. Answers whether it is there
    /// now.
    public func Toggle(_ name: string, force: bool? = nil) -> bool {
        let want = force ?? !Contains(name)
        if want { Add(name) } else { Remove(name) }
        return want
    }

    func write(_ names: [string]) {
        var s = ""
        for n in names {
            if !s.isEmpty { s += " " }
            s += n
        }
        element.SetAttribute("class", s)
    }
}
