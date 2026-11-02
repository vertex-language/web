package web

import (
    "web/css/selector"
    "web/dom"
    "web/html"
)

// <dialog> and the Popover API: the top layer they go to, modal dialogs
// (the rest of the page inert behind a ::backdrop, focus kept inside),
// popovers (auto ones closing each other and on a click outside), the
// buttons that open and close them declaratively (popovertarget,
// commandfor), Escape, closedby, and <form method=dialog>.

extension Page {
    /// Opens a dialog as a modal: in the top layer, the page behind it
    /// inert; the first focusable element in it takes focus.
    public func ShowModal(dialog: html.Node) {
        guard dialog.TagName == "dialog", !modal.contains(dialog.Id) else { return }
        Document?.SetAttribute(dialog, "open", "")
        modal.insert(dialog.Id)
        enterTopLayer(dialog)
        focusInside(dialog)
        topLayerChanged()
    }

    /// Opens a dialog in place, not modal.
    public func Show(dialog: html.Node) {
        guard dialog.TagName == "dialog", !dialog.HasAttribute("open") else { return }
        Document?.SetAttribute(dialog, "open", "")
        topLayerChanged()
    }

    /// Closes a dialog, with a return value where one is given; close
    /// fires at it.
    public func Close(dialog: html.Node, returnValue: string? = nil) {
        guard dialog.TagName == "dialog", dialog.HasAttribute("open") else { return }
        if let v = returnValue { dialogReturnValues[dialog.Id] = v }
        Document?.RemoveAttribute(dialog, "open")
        modal.remove(dialog.Id)
        leaveTopLayer(dialog)
        if let f = focused, isInside(f, dialog) { Focus(nil) }
        topLayerChanged()
        _ = dispatch(dom.Event("close", bubbles: false), to: dialog)
    }

    /// What the dialog was last closed with: a <form method=dialog>'s
    /// submitter's value, or Close's.
    public func ReturnValue(of dialog: html.Node) -> string {
        return dialogReturnValues[dialog.Id] ?? ""
    }

    /// Asks a dialog to close, as Escape does: cancel fires first, and a
    /// listener may keep it open.
    public func RequestClose(dialog: html.Node) {
        guard dialog.HasAttribute("open") else { return }
        if !dispatch(dom.Event("cancel", bubbles: false), to: dialog) { return }
        Close(dialog)
    }

    /// Whether a popover is showing.
    public func IsPopoverOpen(el: html.Node) -> bool { return popovers.contains(el.Id) }

    /// Shows a popover: in the top layer; an auto popover first closes
    /// the auto popovers it isn't inside.
    public func ShowPopover(el: html.Node) {
        guard el.HasAttribute("popover"), !popovers.contains(el.Id) else { return }
        if !dispatch(dom.ToggleEvent("beforetoggle", OldState: "closed", NewState: "open"), to: el) { return }
        if popoverKind(el) == "auto" {
            for id in topLayer where popovers.contains(id) {
                guard let other = node(byId: id), popoverKind(other) == "auto", !isInside(el, other) else { continue }
                HidePopover(other)
            }
        }
        popovers.insert(el.Id)
        enterTopLayer(el)
        topLayerChanged()
        _ = dispatch(dom.ToggleEvent("toggle", OldState: "closed", NewState: "open"), to: el)
    }

    public func HidePopover(el: html.Node) {
        guard popovers.contains(el.Id) else { return }
        _ = dispatch(dom.ToggleEvent("beforetoggle", OldState: "open", NewState: "closed"), to: el)
        popovers.remove(el.Id)
        leaveTopLayer(el)
        if let f = focused, isInside(f, el) { Focus(nil) }
        topLayerChanged()
        _ = dispatch(dom.ToggleEvent("toggle", OldState: "open", NewState: "closed"), to: el)
    }

    public func TogglePopover(el: html.Node) {
        if popovers.contains(el.Id) { HidePopover(el) } else { ShowPopover(el) }
    }

    /// popover's kind: "auto" (the default), "manual" or "hint".
    func popoverKind(el: html.Node) -> string {
        let v = lower(el.GetAttribute("popover") ?? "")
        if v == "manual" || v == "hint" { return v }
        return "auto"
    }

    func enterTopLayer(el: html.Node) {
        topLayer.removeAll(where: { $0 == el.Id })
        topLayer.append(el.Id)
    }

    func leaveTopLayer(el: html.Node) {
        topLayer.removeAll(where: { $0 == el.Id })
    }

    func topLayerChanged() {
        builder.TopLayer = topLayer
        context.Modal = modal
        context.PopoverOpen = popovers
        needsStyle = true
        needsRepaint = true
    }

    /// The modal dialog on top, if one is open.
    var topModal: html.Node? {
        var i = topLayer.count - 1
        while i >= 0 {
            if modal.contains(topLayer[i]) { return node(byId: topLayer[i]) }
            i -= 1
        }
        return nil
    }

    func node(byId id: int64) -> html.Node? {
        if let n = builder.byNode[id]?.Node { return n }
        guard let doc = Document else { return nil }
        return findNode(doc.Tree.Root, id)
    }

    func isInside(n: html.Node, ancestor: html.Node) -> bool {
        var cur: html.Node? = n
        while let c = cur {
            if c.Id == ancestor.Id { return true }
            cur = c.Parent
        }
        return false
    }

    /// Focuses the first focusable element in a dialog: autofocus first.
    func focusInside(dialog: html.Node) {
        let order = dom.FocusOrder(dialog)
        for n in order where n.HasAttribute("autofocus") {
            Focus(n)
            return
        }
        if let first = order.first, first.Id != dialog.Id { Focus(first) }
    }

    /// A button's popovertarget or commandfor, acted on; answers whether
    /// it had one.
    func invoke(button: html.Node) -> bool {
        guard let doc = Document else { return false }
        if let id = button.GetAttribute("commandfor"), let target = doc.Tree.ElementById(id) {
            let command = lower(button.GetAttribute("command") ?? "")
            switch command {
            case "show-modal": ShowModal(target)
            case "close": Close(target, returnValue: button.GetAttribute("value"))
            case "request-close": RequestClose(target)
            case "show-popover": ShowPopover(target)
            case "hide-popover": HidePopover(target)
            case "toggle-popover": TogglePopover(target)
            default:
                // A custom command: command fires at the target.
                _ = dispatch(dom.Event("command", bubbles: false), to: target)
            }
            return true
        }
        if let id = button.GetAttribute("popovertarget"), let target = doc.Tree.ElementById(id) {
            switch lower(button.GetAttribute("popovertargetaction") ?? "toggle") {
            case "show": ShowPopover(target)
            case "hide": HidePopover(target)
            default: TogglePopover(target)
            }
            return true
        }
        return false
    }

    /// Escape: the top modal dialog's cancel, else the top auto popover
    /// hides. Answers whether something closed.
    func escapeTopLayer() -> bool {
        var i = topLayer.count - 1
        while i >= 0 {
            guard let el = node(byId: topLayer[i]) else { i -= 1; continue }
            if modal.contains(el.Id) {
                if lower(el.GetAttribute("closedby") ?? "closerequest") != "none" { RequestClose(el) }
                return true
            }
            if popovers.contains(el.Id) && popoverKind(el) != "manual" {
                HidePopover(el)
                return true
            }
            i -= 1
        }
        return false
    }

    /// A press somewhere: auto popovers it is outside of close, and a
    /// modal dialog with closedby=any closes when the press is on its
    /// backdrop. Answers whether the press was taken by that.
    func lightDismiss(target: html.Node?) -> bool {
        if let m = topModal {
            if let t = target, isInside(t, m) { return false }
            if lower(m.GetAttribute("closedby") ?? "") == "any" { RequestClose(m) }
            // The page behind a modal dialog is inert.
            return true
        }
        var closed = false
        for id in topLayer.reversed() where popovers.contains(id) {
            guard let p = node(byId: id), popoverKind(p) != "manual" else { continue }
            if let t = target, isInside(t, p) { break }
            // Its own button toggles it; that is not a click outside.
            if let t = target, let b = dom.Ancestor(t, "button") ?? (t.TagName == "button" ? t : nil),
               b.GetAttribute("popovertarget") == p.GetAttribute("id") || b.GetAttribute("commandfor") == p.GetAttribute("id") { continue }
            HidePopover(p)
            closed = true
        }
        _ = closed
        return false
    }

    /// Constraint validation before a submit: invalid fires at each
    /// control that fails, the first takes focus, and the form isn't
    /// sent. Answers whether it may be.
    func validate(form: html.Node, submitter: html.Node?) -> bool {
        if form.HasAttribute("novalidate") { return true }
        if let s = submitter, s.HasAttribute("formnovalidate") { return true }
        var first: html.Node? = nil
        for c in allElements(form) where selector.IsValidatable(c) {
            if !selector.IsValid(c, context) {
                _ = dispatch(dom.Event("invalid", bubbles: false), to: c)
                if first == nil { first = c }
            }
        }
        if let f = first {
            Focus(f)
            showValidationBubble(f)
            return false
        }
        return true
    }
}

func findNode(n: html.Node, id: int64) -> html.Node? {
    if n.Id == id { return n }
    for c in n.Children {
        if let f = findNode(c, id) { return f }
    }
    return nil
}

/// Every element under a node, in tree order.
func allElements(n: html.Node) -> [html.Node] {
    var out: [html.Node] = []
    for c in n.Children where c.Kind == html.NodeKind.element {
        out.append(c)
        out.append(contentsOf: allElements(c))
    }
    return out
}
