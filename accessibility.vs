package web

import (
    "image/draw"
    "web/cascade"
    "web/dom"
    "web/html"
    "web/layout"
)

/// One thing in the page's accessibility tree: what an assistive technology
/// is told of an element, or a run of text.
public final class AccessibleNode {
    /// The element or text node's id, what an action names it by.
    public let Id: int64
    /// An ARIA role, or "text" for a run of text.
    public let Role: string
    public var Name: string = ""
    public var Value: string = ""
    /// Where it shows, in the page's view.
    public var Bounds: draw.Rect = draw.Rect.zero
    public var Focused: bool = false
    public var Disabled: bool = false
    public var Checked: bool = false
    public var Expanded: bool = false
    /// A heading's level, 0 for anything else.
    public var Level: int = 0
    public var Children: [AccessibleNode] = []

    init(id: int64, role: string) {
        Id = id
        Role = role
    }
}

extension Page {
    /// The page's accessibility tree: what has a role, or text, and shows.
    /// What holds only that (a div) isn't in it; its children are.
    public func AccessibilityTree() -> AccessibleNode? {
        update()
        guard let doc = Document, let r = root, let top = r.Node else { return nil }
        let out = AccessibleNode(id: top.Id, role: "document")
        out.Name = title
        out.Bounds = draw.Rect(0, 0, size.Width, size.Height)
        // While a modal dialog is open, what is behind it is out of reach.
        if let m = topModal {
            accessibleChildren(m, into: &out.Children, doc: doc.Tree)
            let dialog = AccessibleNode(id: m.Id, role: "dialog")
            dialog.Name = dom.AccessibleName(m, in: doc.Tree)
            dialog.Bounds = BoundsOf(m) ?? draw.Rect.zero
            dialog.Children = out.Children
            out.Children = [dialog]
            return out
        }
        accessibleChildren(top, into: &out.Children, doc: doc.Tree)
        return out
    }

    func accessibleChildren(node: html.Node, into out: inout [AccessibleNode], doc: html.Document) {
        var previousWasText = false
        for c in node.Children {
            if c.Kind == html.NodeKind.text {
                let text = dom.CollapseSpace(c.Text)
                if text.isEmpty { continue }
                // Text next to text is read as one.
                if let last = out.last, last.Role == "text", previousWasText {
                    last.Name += " " + text
                    continue
                }
                let t = AccessibleNode(id: c.Id, role: "text")
                t.Name = text
                t.Bounds = BoundsOf(node) ?? draw.Rect.zero
                out.append(t)
                previousWasText = true
                continue
            }
            if c.Kind != html.NodeKind.element { continue }
            previousWasText = false
            // Not there: display: none, hidden, or aria-hidden.
            if c.GetAttribute("aria-hidden") == "true" { continue }
            guard let box = builder.byNode[c.Id] else { continue }
            if box.Style.Visibility != .visible && !hasShowingChild(box) { continue }
            let role = dom.RoleOf(c)
            if role.isEmpty || role == "none" || role == "presentation" {
                accessibleChildren(c, into: &out, doc: doc)
                continue
            }
            let a = AccessibleNode(id: c.Id, role: role)
            a.Name = dom.AccessibleName(c, in: doc)
            a.Bounds = BoundsOf(c) ?? draw.Rect.zero
            a.Focused = focused?.Id == c.Id
            a.Disabled = c.HasAttribute("disabled") || c.GetAttribute("aria-disabled") == "true"
            a.Checked = c.HasAttribute("checked") || c.GetAttribute("aria-checked") == "true"
            a.Expanded = c.GetAttribute("aria-expanded") == "true" || context.PickerOpen.contains(c.Id) || picker?.node.Id == c.Id || (c.TagName == "details" && c.HasAttribute("open"))
            if c.TagName.count == 2 && c.TagName.hasPrefix("h"), let level = int(c.TagName.dropFirst()) { a.Level = level }
            if let l = c.GetAttribute("aria-level"), let level = int(l) { a.Level = level }
            switch c.TagName {
            case "input", "textarea": a.Value = dom.InputType(c) == "password" ? "" : valueOf(c)
            case "select": a.Value = selectedText(c)
            case "progress", "meter": a.Value = c.GetAttribute("value") ?? ""
            default: a.Value = c.GetAttribute("aria-valuenow") ?? ""
            }
            // A control says all it has to say itself; a picture too.
            if !leafRoles.contains(role) { accessibleChildren(c, into: &a.Children, doc: doc) }
            // A role named by what it holds says that text already.
            if namedByContent.contains(role) { a.Children.removeAll { $0.Role == "text" } }
            out.append(a)
        }
    }

    func hasShowingChild(box: layout.Box) -> bool {
        for c in box.Children {
            if c.Style.Visibility == .visible || hasShowingChild(c) { return true }
        }
        return false
    }

    /// The text of a select's chosen option.
    func selectedText(select: html.Node) -> string {
        let options = dom.Descendants(select, tag: "option")
        for o in options where o.HasAttribute("selected") { return dom.CollapseSpace(o.InnerText()) }
        return options.first.map { dom.CollapseSpace($0.InnerText()) } ?? ""
    }

    func accessibleTarget(id: int64) -> html.Node? {
        guard let doc = Document else { return nil }
        return nodeWithId(id, in: doc.Tree.Root)
    }

    func nodeWithId(id: int64, in node: html.Node) -> html.Node? {
        if node.Id == id { return node }
        for c in node.Children {
            if let n = nodeWithId(id, in: c) { return n }
        }
        return nil
    }

    /// Presses what the id names, as the pointer would at its middle, after
    /// bringing it into view. Answers whether it was there.
    @discardableResult
    public func AccessibilityPress(id: int64) -> bool {
        guard let n = accessibleTarget(id) else { return false }
        ScrollIntoViewIfNeeded(n)
        guard let b = BoundsOf(n) else { return false }
        let at = draw.Point(b.X + b.Width / 2, b.Y + b.Height / 2)
        _ = Handle(.pointerMoved(at))
        _ = Handle(.pointerDown(Pointer(at)))
        _ = Handle(.pointerUp(Pointer(at)))
        return true
    }

    /// Gives what the id names the focus.
    @discardableResult
    public func AccessibilityFocus(id: int64) -> bool {
        guard let n = accessibleTarget(id) else { return false }
        ScrollIntoViewIfNeeded(n)
        Focus(n)
        return true
    }

    /// Sets a control's value, as typing it would.
    @discardableResult
    public func AccessibilitySetValue(id: int64, value: string) -> bool {
        guard let n = accessibleTarget(id), n.TagName == "input" || n.TagName == "textarea" else { return false }
        if n.HasAttribute("disabled") || n.HasAttribute("readonly") { return false }
        setValue(n, value)
        _ = dispatch(dom.InputEvent("input", Value: value), to: n)
        _ = dispatch(dom.Event("change"), to: n)
        needsStyle = true
        return true
    }
}

let namedByContent: Set<string> = ["button", "link", "heading", "listitem", "option", "cell", "columnheader", "menuitem", "tab", "row"]
let leafRoles: Set<string> = ["img", "textbox", "searchbox", "spinbutton", "slider", "combobox", "progressbar", "separator", "checkbox", "radio"]
