package web

import (
    "image/draw"
    "web/dom"
    "web/edit"
    "web/html"
    "web/layout"
)

/// Something the user did to a page, in the page's coordinates. A host
/// turns its window's events into these (`ui/webview` does), or a test
/// makes them itself.
public enum Input {
    case pointerMoved(draw.Point)
    case pointerDown(Pointer)
    case pointerUp(Pointer)
    /// The pointer left the page.
    case pointerLeft
    case wheel(Wheel)
    case keyDown(Key)
    /// Text the user typed, after the keyboard layout and input method.
    case text(string)
}

/// A button pressed or released.
public struct Pointer {
    public var Position: draw.Point
    public var Button: PointerButton
    /// 2 for the press of a double click, 3 for a triple.
    public var Clicks: int32

    public init(_ position: draw.Point, button: PointerButton = PointerButton.primary, clicks: int32 = 1) {
        Position = position
        Button = button
        Clicks = clicks
    }
}

/// A scroll wheel or trackpad: `Delta` in lines, or in CSS pixels when
/// `Precise`.
public struct Wheel {
    public var Delta: draw.Point
    public var Precise: bool

    public init(_ delta: draw.Point, precise: bool = false) {
        Delta = delta
        Precise = precise
    }
}

public enum PointerButton: Equatable {
    case primary
    case secondary
    case middle
    case other
}

/// A key press, as the W3C's KeyboardEvent describes it.
public struct Key {
    /// What the key means: "a", "A", "Enter", "ArrowLeft", " ".
    public var Key: string
    /// Where the key is, whatever the layout: "KeyA", "Enter", "Space".
    public var Code: string
    public var Shift: bool
    public var Control: bool
    public var Alt: bool
    /// Command on a Mac, the Windows key elsewhere.
    public var Meta: bool

    public init(Key: string, Code: string, Shift: bool = false, Control: bool = false, Alt: bool = false, Meta: bool = false) {
        self.Key = Key
        self.Code = Code
        self.Shift = Shift
        self.Control = Control
        self.Alt = Alt
        self.Meta = Meta
    }

    /// Whether the platform's shortcut modifier is held: Command or Control.
    public var Shortcut: bool { return Meta || Control }
}

extension Page {
    /// Takes an input. Pointer input inside the viewport, scrolling, and
    /// keys while something in the page has focus are handled; the rest
    /// is ignored and left to the host.
    public func Handle(_ input: Input) -> EventResult {
        switch input {
        case .pointerMoved(let p):
            return pointerMoved(p)
        case .pointerDown(let e):
            if !isInside(e.Position) { return .ignored }
            if e.Button == .primary { return pointerDown(e.Position, clicks: e.Clicks) }
            return .handled
        case .pointerUp(let e):
            if e.Button == .primary { return pointerUp(e.Position) }
            return .ignored
        case .pointerLeft:
            pointer = nil
            setHovered(nil)
            return .handled
        case .wheel(let w):
            if let p = pointer, !isInside(p) { return .ignored }
            return wheel(w.Delta, precise: w.Precise)
        case .keyDown(let k):
            return keyDown(k)
        case .text(let t):
            return typed(t)
        }
    }

    func isInside(_ p: draw.Point) -> bool {
        return p.X >= 0 && p.Y >= 0 && p.X < size.Width && p.Y < size.Height
    }

    // MARK: - Pointer

    func pointerMoved(_ p: draw.Point) -> EventResult {
        pointer = p
        if fieldSelecting, let f = focused {
            // Dragging in a field extends its selection from the anchor.
            update()
            let anchor = fieldAnchor
            placeCaret(f, at: p)
            fieldAnchor = anchor
            return .handled
        }
        if selecting {
            // Dragging extends the selection to the text under the pointer.
            update()
            if let hit = hitAt(clampedToView(p)), let tb = hit.TextBox, let node = tb.Node {
                let focus = dom.TextPosition(Node: node, Offset: hit.TextOffset)
                if selectionFocus?.Node.Id != node.Id || selectionFocus?.Offset != hit.TextOffset {
                    selectionFocus = focus
                    needsPaint = true
                }
            }
            return .handled
        }
        if !isInside(p) {
            setHovered(nil)
            cursor = Cursor.default
            return .ignored
        }
        update()
        let hit = hitAt(p)
        setHovered(hit?.Node)
        cursor = cursorFor(hit)
        return .handled
    }

    func clampedToView(_ p: draw.Point) -> draw.Point {
        var q = p
        if q.X < 0 { q.X = 0 }
        if q.Y < 0 { q.Y = 0 }
        if q.X >= size.Width { q.X = size.Width - 1 }
        if q.Y >= size.Height { q.Y = size.Height - 1 }
        return q
    }

    /// The cursor an element asks for, or what its kind implies.
    func cursorFor(_ hit: layout.Hit?) -> Cursor {
        guard let h = hit else { return Cursor.default }
        var cur: layout.Box? = h.Box
        while let b = cur {
            switch b.Style.Cursor {
            case .pointer: return Cursor.pointer
            case .text: return Cursor.text
            case .crosshair: return Cursor.crosshair
            case .ewResize: return Cursor.ewResize
            case .nsResize: return Cursor.nsResize
            case .default, .none, .move, .notAllowed, .wait, .help, .grab: return Cursor.default
            case .auto: break
            }
            if b.Style.Cursor != .auto { break }
            cur = b.Parent
        }
        if h.TextBox != nil && dom.LinkAncestor(h.Node) == nil { return Cursor.text }
        if let b = h.Box.ElementBox, b.Replaced == .textInput || b.Replaced == .textArea { return Cursor.text }
        return Cursor.default
    }

    func setHovered(_ node: html.Node?) {
        if hovered?.Id == node?.Id { return }
        let oldLink = dom.LinkAncestor(hovered)
        hovered = node
        let newLink = dom.LinkAncestor(node)
        if oldLink?.Id != newLink?.Id, let cb = onHoverLink {
            if let l = newLink, let href = l.GetAttribute("href") {
                cb(Resolve(href))
            } else {
                cb(nil)
            }
        }
        stateChanged()
    }

    func pointerDown(_ p: draw.Point, clicks: int32 = 1) -> EventResult {
        update()
        ClearSelection()
        guard let hit = hitAt(p) else {
            Focus(nil)
            return .handled
        }
        let node = hit.Node
        pressed = node
        stateChanged()

        // A press on text starts a selection, unless it is a link or a
        // control; a double click takes the word, a triple the paragraph.
        if let tb = hit.TextBox, let textNode = tb.Node, dom.ControlAncestor(node) == nil && dom.LinkAncestor(node) == nil {
            if clicks >= 3 {
                selectBlock(of: tb)
                return .handled
            }
            if clicks == 2 {
                let word = edit.WordAt([uint8](tb.Text.utf8), hit.TextOffset)
                selectionAnchor = dom.TextPosition(Node: textNode, Offset: word.start)
                selectionFocus = dom.TextPosition(Node: textNode, Offset: word.end)
                needsPaint = true
                return .handled
            }
            selectionAnchor = dom.TextPosition(Node: textNode, Offset: hit.TextOffset)
            selectionFocus = selectionAnchor
            selecting = true
        }

        // A text field: focus it and put the caret where the click was.
        if let control = dom.ControlAncestor(node) {
            let tag = control.TagName
            if tag == "input" {
                let type = dom.InputType(control)
                if type == "checkbox" {
                    toggleChecked(control)
                    return .handled
                }
                if type == "radio" {
                    check(control)
                    return .handled
                }
                if type == "submit" || type == "button" || type == "reset" || type == "image" {
                    Focus(control)
                    return .handled
                }
                if !control.HasAttribute("disabled") {
                    Focus(control)
                    clickInField(control, at: p, clicks: clicks)
                }
                return .handled
            }
            if tag == "textarea" {
                if !control.HasAttribute("disabled") {
                    Focus(control)
                    clickInField(control, at: p, clicks: clicks)
                }
                return .handled
            }
            if tag == "button" || tag == "select" {
                Focus(control)
                return .handled
            }
        }
        if let label = dom.Ancestor(node, "label") {
            if let target = dom.LabelTarget(label, in: Document?.Tree) {
                let type = dom.InputType(target)
                if type == "checkbox" { toggleChecked(target) }
                else if type == "radio" { check(target) }
                else { Focus(target) }
                return .handled
            }
        }
        if let summary = dom.Ancestor(node, "summary"), let details = summary.Parent, details.TagName == "details" {
            _ = Document?.ToggleAttribute(details, "open")
            return .handled
        }
        Focus(nil)
        return .handled
    }

    func pointerUp(_ p: draw.Point) -> EventResult {
        let was = pressed
        pressed = nil
        if selecting {
            selecting = false
            if selectionRange() == nil { ClearSelection() }
        }
        fieldSelecting = false
        stateChanged()
        guard let hit = hitAt(p) else { return .ignored }
        // A click is a press and release on the same element.
        if let w = was, let n = hit.Node, dom.Contains(w, n) || dom.Contains(n, w) {
            return clicked(hit)
        }
        return .handled
    }

    func clicked(_ hit: layout.Hit) -> EventResult {
        let node = hit.Node
        if let control = dom.ControlAncestor(node) {
            if control.TagName == "button" || (control.TagName == "input" && dom.IsButtonInput(control)) {
                if !control.HasAttribute("disabled") { activateButton(control) }
                return .handled
            }
        }
        if let link = dom.LinkAncestor(node), let href = link.GetAttribute("href") {
            navigate(href)
            return .handled
        }
        return .handled
    }

    func navigate(_ href: string) {
        if href.hasPrefix("#") {
            let b = [uint8](href.utf8)
            let id = stringOf(b, 1, b.count)
            if let target = Document?.Tree.ElementById(id) {
                ScrollTo(target)
            } else if id.isEmpty || id == "top" {
                SetScrollOffset(draw.Point(0, 0))
            }
            return
        }
        if let cb = onNavigate {
            cb(Resolve(href))
        }
    }

    func activateButton(_ button: html.Node) {
        let type = lower(button.GetAttribute("type") ?? (button.TagName == "button" ? "submit" : "button"))
        if type == "reset" {
            if let form = dom.Ancestor(button, "form") { resetForm(form) }
            return
        }
        if type == "submit", let form = dom.Ancestor(button, "form") {
            submit(form, submitter: button)
            return
        }
        if let cb = onAction {
            let name = button.GetAttribute("name") ?? (button.GetAttribute("id") ?? "button")
            cb(name, dom.ButtonValue(button))
        }
    }

    // MARK: - Scrolling

    func wheel(_ delta: draw.Point, precise: bool) -> EventResult {
        update()
        let step: float32 = precise ? 1 : 40
        let dy = -delta.Y * step
        let dx = -delta.X * step
        // The innermost scroll container under the pointer takes the
        // scroll while it can; then the page.
        if let p = pointer, let hit = hitAt(p) {
            var cur: layout.Box? = hit.Box
            while let b = cur {
                if b.Style.IsScrollContainer && b.Kind == .block {
                    let maxY = b.ContentHeight - b.InnerHeight
                    if maxY > 0 && ((dy > 0 && b.ScrollY < maxY) || (dy < 0 && b.ScrollY > 0)) {
                        b.ScrollY = clampf(b.ScrollY + dy, 0, maxY)
                        needsPaint = true
                        return .handled
                    }
                }
                cur = b.Parent
            }
        }
        let before = scroll
        scroll.Y += dy
        scroll.X += dx
        clampScroll()
        if scroll.Y != before.Y || scroll.X != before.X {
            needsRepaint = true
            // What is under the pointer changed.
            if let p = pointer { _ = pointerMoved(p) }
        }
        return .handled
    }

    // MARK: - Keys

    func keyDown(_ k: Key) -> EventResult {
        if let f = focused, dom.IsTextControl(f) {
            return editKey(f, k)
        }
        if let f = focused, f.TagName == "select" {
            return selectKey(f, k)
        }
        if k.Code == "Tab" {
            moveFocus(backwards: k.Shift)
            return .handled
        }
        if let f = focused, k.Code == "Enter" || k.Code == "Space" {
            if f.TagName == "button" || (f.TagName == "input" && dom.IsButtonInput(f)) {
                activateButton(f)
                return .handled
            }
            if f.TagName == "a", let href = f.GetAttribute("href"), k.Code == "Enter" {
                navigate(href)
                return .handled
            }
        }
        if k.Shortcut {
            if k.Code == "KeyC" {
                let text = SelectedText()
                if !text.isEmpty, let c = Clipboard { c.WriteText(text) }
                return .handled
            }
            if k.Code == "KeyA" {
                SelectAll()
                return .handled
            }
        }
        let page = size.Height
        switch k.Code {
        case "ArrowDown": scrollBy(0, 40)
        case "ArrowUp": scrollBy(0, -40)
        case "ArrowLeft": scrollBy(-40, 0)
        case "ArrowRight": scrollBy(40, 0)
        case "PageDown": scrollBy(0, page * 0.9)
        case "PageUp": scrollBy(0, -page * 0.9)
        case "Space": scrollBy(0, k.Shift ? -page * 0.9 : page * 0.9)
        case "Home": SetScrollOffset(draw.Point(scroll.X, 0))
        case "End": SetScrollOffset(draw.Point(scroll.X, contentHeight))
        default: return .ignored
        }
        return .handled
    }

    /// Keys on a focused select: up and down move through the options;
    /// Home and End go to the ends; a letter jumps to the next option
    /// starting with it.
    func selectKey(_ f: html.Node, _ k: Key) -> EventResult {
        let options = dom.Descendants(f, tag: "option")
        if options.isEmpty { return .ignored }
        var current = -1
        var i = 0
        while i < options.count {
            if options[i].HasAttribute("selected") && current < 0 { current = i }
            i += 1
        }
        if current < 0 { current = 0 }
        var next = current
        switch k.Code {
        case "ArrowDown", "ArrowRight": next = current + 1 < options.count ? current + 1 : current
        case "ArrowUp", "ArrowLeft": next = current > 0 ? current - 1 : 0
        case "Home": next = 0
        case "End": next = options.count - 1
        case "Tab":
            moveFocus(backwards: k.Shift)
            return .handled
        case "Escape":
            Focus(nil)
            return .handled
        default:
            let key = [uint8](lower(k.Key).utf8)
            if key.count != 1 { return .ignored }
            var j = 1
            while j <= options.count {
                let idx = (current + j) % options.count
                let text = [uint8](lower(trimSpaces(options[idx].InnerText())).utf8)
                if !text.isEmpty && text[0] == key[0] { next = idx; break }
                j += 1
            }
        }
        if next != current {
            if let doc = Document {
                for o in options { doc.RemoveAttribute(o, "selected") }
                doc.SetAttribute(options[next], "selected", "")
            }
        }
        return .handled
    }

    func scrollBy(_ dx: float32, _ dy: float32) {
        update()
        SetScrollOffset(draw.Point(scroll.X + dx, scroll.Y + dy))
    }

    func typed(_ text: string) -> EventResult {
        guard let f = focused, dom.IsTextControl(f), !f.HasAttribute("disabled"), !f.HasAttribute("readonly") else { return .ignored }
        if text.isEmpty { return .ignored }
        let bytes = [uint8](text.utf8)
        // Control characters arrive as keys, not text.
        if bytes.count == 1 && bytes[0] < 32 && bytes[0] != 10 { return .ignored }
        var value = deleteFieldSelection(f)
        if f.TagName == "input", let max = f.GetAttribute("maxlength") {
            let mb = [uint8](max.utf8)
            let n = int(parseNumber(mb, 0, mb.count))
            if n > 0 && value.utf8.count + bytes.count > n { return .handled }
        }
        value = edit.Insert(value, at: caret, bytes)
        caret += bytes.count
        fieldAnchor = caret
        setValue(f, value)
        return .handled
    }

    /// Removes the field's selected text, if any, leaving the caret at
    /// its start; the value that remains.
    func deleteFieldSelection(_ f: html.Node) -> string {
        let value = valueOf(f)
        guard let r = fieldRange() else { return value }
        let rest = edit.Remove(value, from: r.start, to: r.end)
        let start = min(r.start, value.utf8.count)
        caret = start
        fieldAnchor = start
        setValue(f, rest)
        return rest
    }

    func editKey(_ f: html.Node, _ k: Key) -> EventResult {
        let value = valueOf(f)
        let bytes = [uint8](value.utf8)
        let editable = !f.HasAttribute("disabled") && !f.HasAttribute("readonly")
        let shift = k.Shift
        let hasSelection = fieldRange() != nil
        switch k.Code {
        case "Backspace":
            if !editable { return .handled }
            if hasSelection {
                _ = deleteFieldSelection(f)
            } else if caret > 0 {
                let start = k.Alt ? edit.WordStart(bytes, before: caret) : edit.PreviousChar(bytes, caret)
                setValue(f, edit.Remove(value, from: start, to: caret))
                caret = start
                fieldAnchor = start
            }
        case "Delete":
            if !editable { return .handled }
            if hasSelection {
                _ = deleteFieldSelection(f)
            } else if caret < bytes.count {
                setValue(f, edit.Remove(value, from: caret, to: edit.NextChar(bytes, caret)))
            }
        case "ArrowLeft":
            if let r = fieldRange(), !shift && !k.Alt && !k.Meta {
                moveCaret(r.start, extend: false)
            } else {
                moveCaret(k.Alt ? edit.WordStart(bytes, before: caret) : (k.Meta ? 0 : edit.PreviousChar(bytes, caret)), extend: shift)
            }
        case "ArrowRight":
            if let r = fieldRange(), !shift && !k.Alt && !k.Meta {
                moveCaret(r.end, extend: false)
            } else {
                moveCaret(k.Alt ? edit.WordEnd(bytes, after: caret) : (k.Meta ? bytes.count : edit.NextChar(bytes, caret)), extend: shift)
            }
        case "Home":
            moveCaret(0, extend: shift)
        case "End":
            moveCaret(bytes.count, extend: shift)
        case "ArrowUp", "ArrowDown":
            if f.TagName == "textarea" {
                moveCaret(edit.LineMove(bytes, caret, up: k.Code == "ArrowUp"), extend: shift)
            } else {
                moveCaret(k.Code == "ArrowUp" ? 0 : bytes.count, extend: shift)
            }
        case "Enter":
            if f.TagName == "textarea" {
                if editable {
                    let rest = deleteFieldSelection(f)
                    setValue(f, edit.Insert(rest, at: caret, [10]))
                    caret += 1
                    fieldAnchor = caret
                }
            } else if let form = dom.Ancestor(f, "form") {
                submit(form, submitter: nil)
            } else if let cb = onAction {
                cb(f.GetAttribute("name") ?? (f.GetAttribute("id") ?? "input"), value)
            }
        case "Tab":
            moveFocus(backwards: shift)
        case "Escape":
            Focus(nil)
        case "KeyA":
            if k.Shortcut {
                fieldAnchor = 0
                caret = bytes.count
                needsPaint = true
            } else {
                return .ignored
            }
        case "KeyC", "KeyX":
            if k.Shortcut {
                guard let r = fieldRange() else { return .handled }
                if let c = Clipboard { c.WriteText(stringOf(bytes, r.start, min(r.end, bytes.count))) }
                if k.Code == "KeyX" && editable {
                    _ = deleteFieldSelection(f)
                }
            } else {
                return .ignored
            }
        case "KeyV":
            if k.Shortcut && editable {
                let pasted = Clipboard?.ReadText() ?? ""
                if !pasted.isEmpty {
                    var text = [uint8](pasted.utf8)
                    if f.TagName != "textarea" {
                        // A single-line field takes the first line.
                        text = edit.FirstLine(text)
                    }
                    let rest = deleteFieldSelection(f)
                    setValue(f, edit.Insert(rest, at: caret, text))
                    caret += text.count
                    fieldAnchor = caret
                }
            } else {
                return .ignored
            }
        default:
            return .ignored
        }
        return .handled
    }

    /// A click in a text control: the caret goes there and a drag
    /// selects from it; a double click takes the word, a triple all.
    func clickInField(_ control: html.Node, at p: draw.Point, clicks: int32) {
        placeCaret(control, at: p)
        let bytes = [uint8](valueOf(control).utf8)
        if clicks >= 3 {
            fieldAnchor = 0
            caret = bytes.count
        } else if clicks == 2 {
            let word = edit.WordAt(bytes, caret)
            fieldAnchor = word.start
            caret = word.end
        } else {
            fieldAnchor = caret
            fieldSelecting = true
        }
        needsPaint = true
    }

    /// Moves the caret to where a click landed in a text control.
    func placeCaret(_ control: html.Node, at p: draw.Point) {
        guard let box = builder.byNode[control.Id] else { return }
        let pos = layout.PagePosition(box)
        let px = p.X + scroll.X - (pos.x + box.ContentX + 1)
        let py = p.Y + scroll.Y - (pos.y + box.ContentY)
        let face = box.Style.Face
        let bytes = [uint8](valueOf(control).utf8)
        var lineStart = 0
        var lineEnd = bytes.count
        if control.TagName == "textarea" {
            var row = int(py / face.LineHeight)
            if row < 0 { row = 0 }
            let line = edit.LineRange(bytes, row: row)
            lineStart = line.start
            lineEnd = line.end
        }
        var best = lineStart
        var bestDist: float32 = 1e9
        var i = lineStart
        while i <= lineEnd {
            if edit.IsCharStart(bytes, i) {
                let w = face.Measure(stringOf(bytes, lineStart, i))
                let d = w > px ? w - px : px - w
                if d < bestDist {
                    bestDist = d
                    best = i
                }
            }
            i += 1
        }
        moveCaret(best, extend: false)
    }

    // MARK: - Focus

    func moveFocus(backwards: bool) {
        guard let doc = Document else { return }
        let order = dom.FocusOrder(doc.Root)
        if order.isEmpty { return }
        var index = -1
        if let f = focused {
            var i = 0
            while i < order.count {
                if order[i].Id == f.Id { index = i }
                i += 1
            }
        }
        var next = backwards ? index - 1 : index + 1
        if next >= order.count { next = 0 }
        if next < 0 { next = order.count - 1 }
        Focus(order[next])
        if let f = focused {
            // Tabbing into a field selects its text, as browsers do.
            caret = valueOf(f).utf8.count
            fieldAnchor = dom.IsTextControl(f) ? 0 : caret
            ScrollIntoViewIfNeeded(f)
        }
    }

    // MARK: - Forms

    func toggleChecked(_ input: html.Node) {
        if input.HasAttribute("disabled") { return }
        _ = Document?.ToggleAttribute(input, "checked")
        Focus(input)
    }

    func check(_ radio: html.Node) {
        if radio.HasAttribute("disabled") { return }
        guard let doc = Document else { return }
        if let name = radio.GetAttribute("name") {
            for other in doc.Tree.ElementsByTagName("input") {
                if other.Id != radio.Id && other.GetAttribute("name") == name && lower(other.GetAttribute("type") ?? "") == "radio" {
                    doc.RemoveAttribute(other, "checked")
                }
            }
        }
        doc.SetAttribute(radio, "checked", "")
        Focus(radio)
    }

    func resetForm(_ form: html.Node) {
        for c in dom.Controls(form) {
            values.removeValue(forKey: c.Id)
        }
        needsStyle = true
    }

    func submit(_ form: html.Node, submitter: html.Node?) {
        let fields = dom.FormData(form, submitter: submitter, value: { c in self.valueOf(c) })
        let action = form.GetAttribute("action") ?? ""
        let method = lower(form.GetAttribute("method") ?? "get")
        if let cb = onSubmit {
            cb(dom.Submission(Action: Resolve(action), Method: method, Fields: fields))
        } else if let cb = onAction {
            cb(form.GetAttribute("name") ?? (form.GetAttribute("id") ?? "form"), action)
        }
    }
}
