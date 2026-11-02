package layout

import (
    "web/dom"
    "image/draw"
    "web/cascade"
    "web/css"
    "web/css/selector"
    "web/html"
    "web/svg"
)

/// What the box tree builder needs from the view: styles, the page's
/// state, and images.
public final class BoxTreeBuilder {
    let resolver: cascade.StyleResolver
    let context: selector.MatchContext
    /// Images by URL, for <img> boxes; missing ones are laid out with
    /// their attributes' size, or none.
    public var Images: [string: draw.Image] = [:]
    /// A playing <video>'s picture size, by node id.
    public var MediaSizes: [int64: draw.Size] = [:]
    /// The base-select elements whose pickers are open.
    public var PickersOpen = Set<int64>()
    /// The images that are SVG files, by the src that names them: drawn
    /// as vectors, sharp at any size.
    public var Vectors: [string: svg.Document] = [:]
    /// The text a form control holds, by node, where the user has typed
    /// into it; otherwise the DOM's value.
    public var Values: [int64: string] = [:]
    /// Every box made, by node id, for the view to find an element's box.
    public var byNode: [int64: Box] = [:]
    /// Whether the tree has a nested document's box (ReplacedKind.frame).
    public var HasFrames = false
    /// The elements in the top layer -- modal dialogs, open popovers --
    /// in the order they went there: each gets a ::backdrop box.
    public var TopLayer: [int64] = []
    /// Each text node's place in document order, for ordering selections.
    public var textOrder: [int64: int] = [:]
    var textCount = 0
    /// The counters in scope, outermost first: each made by an element
    /// at a depth, and gone when its parent's children end.
    var counters: [(name: string, value: int, depth: int)] = []
    var counterDepth = 0
    /// How deep open-quote has gone, in document order.
    var quoteDepth = 0

    public init(resolver: cascade.StyleResolver, context: selector.MatchContext) {
        self.resolver = resolver
        self.context = context
    }

    /// The box tree of a document: the root element's box, or nil for a
    /// document with no element.
    public func Build(doc: html.Document) -> Box? {
        byNode = [:]
        HasFrames = false
        resolver.StateTrace.removeAll(keepingCapacity: true)
        textOrder = [:]
        textCount = 0
        counters = []
        counterDepth = 0
        quoteDepth = 0
        var rootNode: html.Node? = nil
        for c in doc.Root.Children {
            if c.Kind == html.NodeKind.element {
                rootNode = c
                break
            }
        }
        guard let root = rootNode else { return nil }
        let style = resolver.Resolve(root, parent: nil, context: context)
        if style.Display == .none { return nil }
        let box = Box(kind: .block, style: style, node: root)
        byNode[root.Id] = box
        applyCounters(root, style)
        enterCounters()
        buildChildren(of: root, into: box, parentStyle: style)
        leaveCounters()
        // ::backdrop: a fixed box under each top-layer element, painted
        // over the rest of the page.
        for id in TopLayer {
            guard let el = byNode[id], let node = el.Node else { continue }
            guard let bs = resolver.ResolvePseudo(node, "backdrop", parent: el.Style, context: context) else { continue }
            if bs.Display == .none { continue }
            let backdrop = Box(kind: .block, style: bs, node: nil)
            backdrop.IsAnonymous = true
            box.AppendChild(backdrop)
        }
        return box
    }

    /// Makes the boxes of a node's children and places them under a
    /// parent box, wrapping inline runs in anonymous blocks where they
    /// sit beside blocks.
    func buildChildren(of node: html.Node, into parent: Box, parentStyle: cascade.ComputedStyle) {
        var made: [Box] = []
        appendChildBoxes(of: node, parentStyle: parentStyle, into: &made)
        place(made, into: parent)
    }

    /// Whether children become flex items: blocks, each of its own.
    func place(made: [Box], into parent: Box) {
        if made.isEmpty { return }
        if parent.Style.Display == .table || parent.Style.Display == .inlineTable {
            // What isn't a part of a table goes in a row of its own, made
            // for it, and a cell in that.
            var loose: [Box] = []
            func flushRow() {
                if loose.isEmpty { return }
                let rowStyle = cascade.ComputedStyle(inheriting: parent.Style)
                rowStyle.Display = .tableRow
                let row = Box(kind: .block, style: rowStyle, node: nil)
                row.IsAnonymous = true
                let cellStyle = cascade.ComputedStyle(inheriting: parent.Style)
                cellStyle.Display = .tableCell
                let cell = Box(kind: .block, style: cellStyle, node: nil)
                cell.IsAnonymous = true
                place(loose, into: cell)
                row.AppendChild(cell)
                parent.AppendChild(row)
                loose = []
            }
            for b in made {
                if b.Kind == .text && IsBlank(b.Text) { continue }
                if isTableInternal(b.Style.Display) && b.Kind != .text || b.Style.Display == .tableCaption {
                    flushRow()
                    parent.AppendChild(b)
                } else {
                    loose.append(b)
                }
            }
            flushRow()
            return
        }
        if isTableInternal(parent.Style.Display) {
            // Rows and groups hold cells and rows; loose text is dropped
            // and a loose inline is wrapped as a cell would be.
            var run: [Box] = []
            for b in made {
                if b.Kind == .text && IsBlank(b.Text) { continue }
                if b.Kind == .block {
                    flushInline(&run, into: parent)
                    parent.AppendChild(b)
                } else {
                    run.append(b)
                }
            }
            flushInline(&run, into: parent)
            return
        }
        let flex = parent.Style.IsFlexContainer || parent.Style.IsGridContainer
        if flex {
            // Every child element is a flex item, blockified; a run of
            // text between them becomes an anonymous block item, and
            // whitespace-only text nothing.
            var run: [Box] = []
            for b in made {
                if b.Kind == .text {
                    if !IsBlank(b.Text) { run.append(b) }
                    continue
                }
                flushInline(&run, into: parent)
                if b.Kind == .inline || b.Kind == .inlineBlock {
                    b.Kind = .block
                    b.Style.Display = b.Style.Display.Blockified
                } else if b.Kind == .lineBreak {
                    continue
                }
                // float doesn't apply to a flex or grid item: it's an item
                // like the others.
                if b.Style.Float != .none { b.Style.Float = .none }
                parent.AppendChild(b)
            }
            flushInline(&run, into: parent)
            return
        }
        // Floats and positioned boxes go with the inline content around
        // them; only in-flow blocks split it -- a replaced element with
        // display: block among them.
        var hasBlock = false
        var hasInline = false
        for b in made {
            if b.IsBlockLevel && b.Kind != .text && !b.Style.IsOutOfFlow { hasBlock = true } else if !(b.Kind == .text && IsBlank(b.Text)) { hasInline = true }
        }
        if hasBlock && hasInline {
            var run: [Box] = []
            for b in made {
                if b.IsBlockLevel && b.Kind != .text && !b.Style.IsOutOfFlow {
                    flushInline(&run, into: parent)
                    parent.AppendChild(b)
                } else {
                    run.append(b)
                }
            }
            flushInline(&run, into: parent)
        } else if hasBlock {
            for b in made where b.IsBlockLevel && b.Kind != .text {
                parent.AppendChild(b)
            }
        } else {
            for b in made {
                parent.AppendChild(b)
            }
        }
    }

    /// Wraps a run of inline-level boxes in an anonymous block.
    func flushInline(run: inout [Box], into parent: Box) {
        if run.isEmpty { return }
        var allBlank = true
        for b in run {
            if !(b.Kind == .text && IsBlank(b.Text)) { allBlank = false }
        }
        if allBlank {
            run = []
            return
        }
        // A run that is only floats and positioned boxes, with blank
        // text: they go straight into the parent.
        var onlyOutOfFlow = true
        for b in run {
            // Text has its element's style: it's in the flow whatever that is.
            if b.Kind == .text ? !IsBlank(b.Text) : !b.Style.IsOutOfFlow { onlyOutOfFlow = false }
        }
        if onlyOutOfFlow {
            for b in run where b.Kind != .text && b.Style.IsOutOfFlow { parent.AppendChild(b) }
            run = []
            return
        }
        let style = cascade.ComputedStyle(inheriting: parent.Style)
        style.Display = .block
        let anon = Box(kind: .block, style: style, node: nil)
        anon.IsAnonymous = true
        for b in run {
            anon.AppendChild(b)
        }
        parent.AppendChild(anon)
        run = []
    }

    /// Puts what a box holds in an anonymous box of its own, which layout
    /// sets as if horizontal and painting turns.
    func turnVertical(box: Box) {
        if box.Kind != .block && box.Kind != .inlineBlock { return }
        let inner = Box(kind: .block, style: resolver.VerticalContentStyle(of: box.Style), node: nil)
        inner.IsAnonymous = true
        inner.QuarterTurn = box.Style.WritingMode == "sideways-lr" ? -1 : 1
        let held = box.Children
        box.Children = []
        for c in held { inner.AppendChild(c) }
        box.AppendChild(inner)
        box.VerticalContent = inner
    }

    /// A base-select's boxes: its button, or the chosen option's content
    /// where it has none, and its icon; and, open, everything else in its
    /// picker.
    func appendBaseSelect(node: html.Node, parentStyle: cascade.ComputedStyle, into out: inout [Box]) {
        var button: html.Node? = nil
        for c in node.Children where c.Kind == html.NodeKind.element && c.TagName == "button" {
            button = c
            break
        }
        var listIndex = 0
        if let b = button {
            let style = resolver.Resolve(b, parent: parentStyle, context: context)
            if style.Display != .none, let box = makeBox(b, style: style, parentStyle: parentStyle, listIndex: &listIndex) { out.append(box) }
        } else if let chosen = selectedOption(node) {
            appendChildBoxes(of: chosen, parentStyle: parentStyle, into: &out)
            if let icon = pseudoElement(node, "picker-icon", parentStyle) { out.append(icon) }
        }
        if !PickersOpen.contains(node.Id) { return }
        guard let ps = resolver.ResolvePseudo(node, "picker(select)", parent: parentStyle, context: context) else { return }
        let picker = Box(kind: .block, style: ps, node: nil)
        picker.IsAnonymous = true
        var inside: [Box] = []
        for c in node.Children {
            if c.Kind != html.NodeKind.element || c.Id == button?.Id { continue }
            let style = resolver.Resolve(c, parent: ps, context: context)
            if style.Display == .none { continue }
            if let box = makeBox(c, style: style, parentStyle: ps, listIndex: &listIndex) { inside.append(box) }
        }
        place(inside, into: picker)
        out.append(picker)
    }

    /// The option a select has chosen: the one marked, or its first.
    func selectedOption(select: html.Node) -> html.Node? {
        var first: html.Node? = nil
        var found: html.Node? = nil
        func walk(n: html.Node) {
            for c in n.Children where c.Kind == html.NodeKind.element {
                if c.TagName == "option" {
                    if first == nil { first = c }
                    if found == nil && c.HasAttribute("selected") { found = c }
                } else {
                    walk(c)
                }
            }
        }
        walk(select)
        return found ?? first
    }

    func appendChildBoxes(of node: html.Node, parentStyle: cascade.ComputedStyle, into out: inout [Box]) {
        if node.TagName == "select" && parentStyle.Appearance == "base-select" {
            appendBaseSelect(node, parentStyle: parentStyle, into: &out)
            return
        }
        // <selectedcontent> shows what its select has chosen.
        if node.TagName == "selectedcontent" {
            var up = node.Parent
            while let n = up, n.TagName != "select" { up = n.Parent }
            if let sel = up, let chosen = selectedOption(sel) {
                appendChildBoxes(of: chosen, parentStyle: parentStyle, into: &out)
            }
            return
        }
        var listIndex = 0
        for child in node.Children {
            switch child.Kind {
            case .text:
                if child.Text.isEmpty { continue }
                let t = Box(kind: .text, style: parentStyle, node: child)
                t.Text = child.Text
                textCount += 1
                textOrder[child.Id] = textCount
                out.append(t)
            case .element:
                let style = resolver.Resolve(child, parent: parentStyle, context: context)
                if style.Display == .none { continue }
                applyCounters(child, style)
                if style.Display == .contents {
                    enterCounters()
                    appendChildBoxes(of: child, parentStyle: style, into: &out)
                    leaveCounters()
                    continue
                }
                // Where text turns vertical is where the turn starts. A root
                // that says so hands it to what's in it.
                let starts = style.IsVertical && (!parentStyle.IsVertical || node.TagName == "html")
                if style.IsVertical && !starts { style.SwapAxesForVertical() }
                if let box = makeBox(child, style: style, parentStyle: parentStyle, listIndex: &listIndex) {
                    if starts { turnVertical(box) } else if box.Kind == .replaced && style.AxesSwapped {
                        let w = box.IntrinsicWidth
                        box.IntrinsicWidth = box.IntrinsicHeight
                        box.IntrinsicHeight = w
                    }
                    out.append(box)
                }
            default:
                continue
            }
        }
    }

    /// The box for an element, with its children's boxes under it.
    func makeBox(node: html.Node, style: cascade.ComputedStyle, parentStyle: cascade.ComputedStyle, listIndex: inout int) -> Box? {
        // A base-select is what its picker hangs from.
        if node.TagName == "select" && style.Appearance == "base-select" && style.Position == .static { style.Position = .relative }
        let tag = node.TagName
        var box: Box
        switch tag {
        case "img":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .image
            if !showImage(box, node.GetAttribute("src")) {
                box.IntrinsicWidth = 0
                box.IntrinsicHeight = 0
            }
        case "input":
            let type = css.lower(node.GetAttribute("type") ?? "text")
            box = Box(kind: .replaced, style: style, node: node)
            switch type {
            case "checkbox":
                box.Replaced = .checkbox
                box.IntrinsicWidth = 13
                box.IntrinsicHeight = 13
            case "radio":
                box.Replaced = .radio
                box.IntrinsicWidth = 13
                box.IntrinsicHeight = 13
            case "submit", "button", "reset", "image":
                box.Replaced = .button
                box.Text = node.GetAttribute("value") ?? (type == "submit" ? "Submit" : (type == "reset" ? "Reset" : ""))
                let face = style.Face
                box.IntrinsicWidth = face.Measure(box.Text) + 20
                box.IntrinsicHeight = face.LineHeight + 6
            case "range":
                box.Replaced = .range
                box.Text = Values[node.Id] ?? (node.GetAttribute("value") ?? "")
                box.IntrinsicWidth = 150
                box.IntrinsicHeight = 20
            case "color":
                box.Replaced = .colorWell
                box.Text = dom.SanitizedValue("color", Values[node.Id] ?? (node.GetAttribute("value") ?? ""))
                box.IntrinsicWidth = 50
                box.IntrinsicHeight = 27
            case "file":
                box.Replaced = .fileInput
                box.FileButtonStyle = resolver.ResolvePseudo(node, "file-selector-button", parent: style, context: context)
                let chosen = Values[node.Id] ?? ""
                box.Text = chosen.isEmpty ? (node.HasAttribute("multiple") ? "No files chosen" : "No file chosen") : chosen
                let face = style.Face
                box.IntrinsicWidth = face.Measure("Choose File") + 16 + 8 + face.Measure(box.Text)
                box.IntrinsicHeight = face.LineHeight + 6
            default:
                box.Replaced = .textInput
                box.Text = Values[node.Id] ?? (node.GetAttribute("value") ?? "")
                if node.HasAttribute("placeholder") {
                    box.PlaceholderStyle = resolver.ResolvePseudo(node, "placeholder", parent: style, context: context)
                }
                // A line of text: the height grows with the font and with
                // the padding around it, as a browser's input does.
                box.IntrinsicWidth = 150
                box.IntrinsicHeight = style.Face.LineHeight
            }
        case "textarea":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .textArea
            box.Text = Values[node.Id] ?? node.InnerText()
            if node.HasAttribute("placeholder") {
                box.PlaceholderStyle = resolver.ResolvePseudo(node, "placeholder", parent: style, context: context)
            }
            box.IntrinsicWidth = 200
            box.IntrinsicHeight = 60
            // field-sizing: content: as big as what it holds.
            if style.FieldSizing == "content" {
                let lines = box.Text.split(separator: "\n", omittingEmptySubsequences: false)
                var widest: float32 = 0
                for l in lines { widest = widest > style.Face.Measure(string(l)) ? widest : style.Face.Measure(string(l)) }
                box.IntrinsicWidth = widest + 4
                box.IntrinsicHeight = style.LineHeightPx * float32(lines.count > 0 ? lines.count : 1)
            }
        case "select" where style.Appearance != "base-select":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .select
            box.Text = selectedOptionText(node)
            box.IntrinsicWidth = style.Face.Measure(box.Text) + 34
            box.IntrinsicHeight = 24
        case "progress", "meter":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .progress
            box.IntrinsicWidth = 160
            box.IntrinsicHeight = 16
        case "svg":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .svg
            box.Vector = svg.Parse(node)
            let size = svg.IntrinsicSize(node)
            box.IntrinsicWidth = size.width
            box.IntrinsicHeight = size.height
            box.RatioOnly = svg.HasRatioOnly(node)
        case "video":
            // Its picture's size once known; its poster until a frame comes.
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .video
            box.IntrinsicWidth = 300
            box.IntrinsicHeight = 150
            if let poster = node.GetAttribute("poster"), let img = Images[poster] {
                box.Image = img
                box.IntrinsicWidth = float32(img.Width)
                box.IntrinsicHeight = float32(img.Height)
            }
            if let size = MediaSizes[node.Id] {
                box.IntrinsicWidth = size.Width
                box.IntrinsicHeight = size.Height
            }
        case "audio":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .audio
            box.IntrinsicWidth = 300
            box.IntrinsicHeight = 54
        case "iframe":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .frame
            HasFrames = true
            box.IntrinsicWidth = 300
            box.IntrinsicHeight = 150
        case "embed", "object" where embedsSomething(node):
            box = Box(kind: .replaced, style: style, node: node)
            box.IntrinsicWidth = 300
            box.IntrinsicHeight = 150
            let src = tag == "object" ? node.GetAttribute("data") : node.GetAttribute("src")
            if showImage(box, src) {
                box.Replaced = box.Replaced == .svg ? .svg : .image
            } else {
                box.Replaced = EmbedsDocument(node) ? .frame : .placeholder
                if box.Replaced == .frame { HasFrames = true }
            }
        case "br":
            box = Box(kind: .lineBreak, style: style, node: node)
        default:
            let kind = kindFor(style.Display)
            box = Box(kind: kind, style: style, node: node)
            if style.Display == .listItem {
                listIndex += 1
                if let start = node.Parent?.GetAttribute("start") {
                    let b = [uint8](start.utf8)
                    let n = int(css.parseNumber(b, 0, b.count))
                    if listIndex == 1 && n > 0 { listIndex = n }
                }
                if let value = node.GetAttribute("value") {
                    let b = [uint8](value.utf8)
                    let n = int(css.parseNumber(b, 0, b.count))
                    if n > 0 { listIndex = n }
                }
                // The list-item counter is the item's number, unless the
                // page counts it itself.
                var counted = false
                for c in style.CounterIncrement + style.CounterSet where c.Name == "list-item" { counted = true }
                if counted { listIndex = counterValue("list-item") } else { setCounter("list-item", listIndex) }
                box.Marker = markerText(style.ListStyleType, listIndex, node: node)
                if !style.ListStyleImage.isEmpty { markerImage(box, style.ListStyleImage) }
                if resolver.HasPseudo("marker"), let ms = resolver.ResolvePseudo(node, "marker", parent: style, context: context) {
                    box.MarkerStyle = ms
                    if let content = ms.Content { box.Marker = contentText(node, content, quotes: ms.Quotes) }
                }
            }
            if resolver.HasPseudo("selection") {
                box.SelectionStyle = resolver.ResolvePseudo(node, "selection", parent: style, context: context)
            }
            if resolver.HasPseudo("first-line") && (kind == .block || kind == .inlineBlock) {
                box.FirstLineStyle = resolver.ResolvePseudo(node, "first-line", parent: style, context: context)
            }
            byNode[node.Id] = box
            // content-visibility: hidden skips the content: it isn't laid
            // out or drawn, and the box keeps its own size.
            if style.ContentVisibility != "hidden" {
                // ::before comes first among the children, so it counts
                // and quotes before them.
                enterCounters()
                let before = pseudoElement(node, "before", style)
                buildChildren(of: node, into: box, parentStyle: style)
                addPseudoElements(node, box, style, before: before)
                leaveCounters()
            }
            if resolver.HasPseudo("first-letter") && (kind == .block || kind == .inlineBlock || style.Display == .listItem) {
                if let fl = resolver.ResolvePseudo(node, "first-letter", parent: style, context: context) {
                    splitFirstLetter(box, fl)
                }
            }
            return box
        }
        byNode[node.Id] = box
        return box
    }

    /// A list item's marker image, where the page has it; until then the
    /// list-style-type marker stands in.
    func markerImage(box: Box, src: string) {
        if let img = Images[src], img.Width > 0 {
            box.MarkerImage = img
            box.MarkerImageSize = draw.Size(float32(img.Width), float32(img.Height))
        } else if let doc = Vectors[src] {
            box.MarkerVector = doc.Drawing
            box.MarkerImageSize = draw.Size(doc.Width > 0 ? doc.Width : 8, doc.Height > 0 ? doc.Height : 8)
        } else {
            return
        }
        box.Marker = "\u{FFFC}"
    }

    /// Puts an image the page has for src in a replaced box, an SVG as
    /// shapes; answers whether there was one.
    func showImage(box: Box, src: string?) -> bool {
        guard let src = src else { return false }
        if let doc = Vectors[src] {
            box.Replaced = .svg
            box.Vector = doc.Drawing
            box.VectorIsDocument = true
            box.IntrinsicWidth = doc.Width
            box.IntrinsicHeight = doc.Height
            return true
        }
        if let img = Images[src] {
            box.Replaced = .image
            box.Image = img
            box.IntrinsicWidth = float32(img.Width)
            box.IntrinsicHeight = float32(img.Height)
            return true
        }
        return false
    }

    /// Whether an <object> or <embed> shows what it points at: an image
    /// the page has, or a document. An <object> that doesn't shows its
    /// fallback content, as an ordinary element; an <embed> always takes
    /// its box.
    func embedsSomething(node: html.Node) -> bool {
        if node.TagName == "embed" { return true }
        if let data = node.GetAttribute("data"), Images[data] != nil || Vectors[data] != nil { return true }
        return EmbedsDocument(node)
    }

    /// ::first-letter: the block's first letter, with the punctuation
    /// before it, moved into an inline box of its own style. It looks
    /// through inline boxes to the first text, and not into blocks.
    func splitFirstLetter(block: Box, style: cascade.ComputedStyle) {
        var container = block
        var i = 0
        while i < container.Children.count {
            let c = container.Children[i]
            if c.Kind == .text {
                let bytes = [uint8](c.Text.utf8)
                var j = 0
                while j < bytes.count && (bytes[j] == 32 || bytes[j] == 10 || bytes[j] == 9 || bytes[j] == 13) { j += 1 }
                if j == bytes.count { i += 1; continue }
                let start = j
                // Opening punctuation, then one letter (a whole UTF-8
                // sequence), then closing punctuation.
                while j < bytes.count && isPunctuation(bytes[j]) { j += 1 }
                if j < bytes.count {
                    j += 1
                    while j < bytes.count && (bytes[j] & 0xC0) == 0x80 { j += 1 }
                }
                while j < bytes.count && isPunctuation(bytes[j]) { j += 1 }
                let letter = Box(kind: .text, style: style, node: c.Node)
                letter.Text = stringOf(bytes, start, j)
                letter.TextStart = c.TextStart + start
                let span = Box(kind: style.Float != .none ? .block : .inline, style: style, node: nil)
                span.IsAnonymous = true
                span.AppendChild(letter)
                let rest = Box(kind: .text, style: c.Style, node: c.Node)
                rest.Text = stringOf(bytes, j, bytes.count)
                rest.TextStart = c.TextStart + j
                container.Children.remove(at: i)
                var at = i
                if start > 0 {
                    let lead = Box(kind: .text, style: c.Style, node: c.Node)
                    lead.Text = stringOf(bytes, 0, start)
                    lead.TextStart = c.TextStart
                    lead.Parent = container
                    container.Children.insert(lead, at: at)
                    at += 1
                }
                span.Parent = container
                container.Children.insert(span, at: at)
                if !rest.Text.isEmpty {
                    rest.Parent = container
                    container.Children.insert(rest, at: at + 1)
                }
                return
            }
            if c.Kind == .inline || (c.Kind == .block && c.IsAnonymous) {
                container = c
                i = 0
                continue
            }
            return
        }
    }

    /// Adds the boxes of ::before and ::after where rules give them
    /// content: first and last among the element's children.
    func addPseudoElements(node: html.Node, box: Box, style: cascade.ComputedStyle, before: Box?) {
        if let made = before {
            made.Parent = box
            box.Children.insert(made, at: 0)
            if box.Children.count > 1 { regroup(box) }
        }
        if let made = pseudoElement(node, "after", style) {
            box.AppendChild(made)
            if box.Children.count > 1 { regroup(box) }
        }
    }

    /// The box of ::before or ::after, if rules give it content.
    func pseudoElement(node: html.Node, which: string, style: cascade.ComputedStyle) -> Box? {
        if !resolver.HasPseudoElements { return nil }
        guard let ps = resolver.ResolvePseudo(node, which, parent: style, context: context) else { return nil }
        if ps.Display == .none { return nil }
        applyCounters(nil, ps)
        return pseudoBox(node, ps)
    }

    // Counters (CSS Lists 3): an element's counter-reset makes a counter
    // that it, what is in it, and its later siblings see; -increment and
    // -set change the innermost of the name, making one where there is
    // none. Lists reset list-item, and their items count it.

    func enterCounters() { counterDepth += 1 }

    func leaveCounters() {
        while let last = counters.last, last.depth >= counterDepth { counters.removeLast() }
        counterDepth -= 1
    }

    func applyCounters(node: html.Node?, style: cascade.ComputedStyle) {
        var resetsList = false
        for c in style.CounterReset {
            resetCounter(c.Name, c.Value)
            if c.Name == "list-item" { resetsList = true }
        }
        if let n = node, !resetsList, n.TagName == "ol" || n.TagName == "ul" || n.TagName == "menu" {
            resetCounter("list-item", 0)
        }
        for c in style.CounterIncrement { setCounter(c.Name, counterValue(c.Name) + c.Value) }
        for c in style.CounterSet { setCounter(c.Name, c.Value) }
    }

    /// A new counter, or a new value for one a sibling made.
    func resetCounter(name: string, value: int) {
        var i = counters.count - 1
        while i >= 0 && counters[i].depth == counterDepth {
            if counters[i].name == name { counters[i].value = value; return }
            i -= 1
        }
        counters.append((name: name, value: value, depth: counterDepth))
    }

    func innermost(name: string) -> int? {
        var i = counters.count - 1
        while i >= 0 {
            if counters[i].name == name { return i }
            i -= 1
        }
        return nil
    }

    func counterValue(name: string) -> int {
        if let i = innermost(name) { return counters[i].value }
        resetCounter(name, 0)
        return 0
    }

    func setCounter(name: string, value: int) {
        if let i = innermost(name) { counters[i].value = value } else { resetCounter(name, value) }
    }

    /// What `content`'s parts spell: text, attr(), counters and quotes.
    func contentText(node: html.Node, parts: [string], quotes: [string]) -> string {
        var text = ""
        for part in parts {
            let b = [uint8](part.utf8)
            if b.isEmpty { continue }
            switch b[0] {
            case 1:
                text += node.GetAttribute(stringOf(b, 1, b.count)) ?? ""
            case 2, 3:
                var fields: [string] = []
                var start = 1
                var j = 1
                while j <= b.count {
                    if j == b.count || b[j] == 31 { fields.append(stringOf(b, start, j)); start = j + 1 }
                    j += 1
                }
                let name = fields[0]
                let style = fields[fields.count - 1]
                if b[0] == 2 {
                    text += counterText(counterValue(name), style)
                } else {
                    _ = counterValue(name)
                    var all: [string] = []
                    for c in counters where c.name == name { all.append(counterText(c.value, style)) }
                    text += all.joined(separator: fields[1])
                }
            case 4:
                let word = stringOf(b, 1, b.count)
                if word == "open-quote" || word == "no-open-quote" {
                    if word == "open-quote" && !quotes.isEmpty {
                        let pair = quoteDepth < quotes.count / 2 ? quoteDepth : quotes.count / 2 - 1
                        text += quotes[pair * 2]
                    }
                    quoteDepth += 1
                } else if quoteDepth > 0 {
                    quoteDepth -= 1
                    if word == "close-quote" && !quotes.isEmpty {
                        let pair = quoteDepth < quotes.count / 2 ? quoteDepth : quotes.count / 2 - 1
                        text += quotes[pair * 2 + 1]
                    }
                }
            default:
                text += part
            }
        }
        return text
    }

    /// The box of a pseudo-element: its display, holding its content
    /// as text. attr() reads the element's attribute.
    func pseudoBox(node: html.Node, style: cascade.ComputedStyle) -> Box? {
        guard let parts = style.Content else { return nil }
        let text = contentText(node, parts, quotes: style.Quotes)
        if style.Display == .none { return nil }
        let kind = kindFor(style.Display)
        let box = Box(kind: kind, style: style, node: nil)
        box.IsAnonymous = true
        if !text.isEmpty {
            let t = Box(kind: .text, style: style, node: nil)
            t.Text = text
            box.AppendChild(t)
        }
        return box
    }

    /// Wraps inline runs again after a pseudo-element joined the
    /// children, so blocks and inlines stay apart.
    func regroup(box: Box) {
        var made: [Box] = []
        for c in box.Children {
            if c.IsAnonymous && c.Kind == .block && c.Node == nil && c.Style.Content == nil {
                // An anonymous wrapper from before: unwrap it.
                for inner in c.Children { made.append(inner) }
            } else {
                made.append(c)
            }
        }
        box.Children = []
        place(made, into: box)
    }

    func kindFor(display: cascade.Display) -> BoxKind {
        switch display {
        case .inline: return .inline
        case .inlineBlock, .inlineFlex, .inlineGrid, .inlineTable: return .inlineBlock
        default: return .block
        }
    }

    /// Whether a box is a part of a table other than a cell: a row, a
    /// row group, a column. Text in one is not content.
    func isTableInternal(display: cascade.Display) -> bool {
        switch display {
        case .table, .inlineTable, .tableRow, .tableRowGroup, .tableHeaderGroup, .tableFooterGroup, .tableColumn, .tableColumnGroup:
            return true
        default:
            return false
        }
    }

    func selectedOptionText(select: html.Node) -> string {
        var first = ""
        var found = ""
        walkOptions(select, &first, &found)
        return found.isEmpty ? first : found
    }

    func walkOptions(n: html.Node, first: inout string, found: inout string) {
        for c in n.Children {
            if c.Kind == html.NodeKind.element {
                if c.TagName == "option" {
                    let text = cascade.trimSpaces(c.InnerText())
                    if first.isEmpty { first = text }
                    if c.HasAttribute("selected") && found.isEmpty { found = text }
                } else {
                    walkOptions(c, &first, &found)
                }
            }
        }
    }
}

public func IsBlank(s: string) -> bool {
    for b in s.utf8 {
        if !isSpaceByte(b) { return false }
    }
    return true
}

/// The marker a list item shows for its list-style-type and index.
func markerText(type: cascade.ListStyleType, index: int, node: html.Node) -> string {
    switch type {
    case .none: return ""
    case .disc: return "•"
    case .circle: return "◦"
    case .square: return "▪"
    case .decimal: return "\(index)."
    case .decimalLeadingZero: return index < 10 ? "0\(index)." : "\(index)."
    case .lowerAlpha: return alpha(index, upper: false) + "."
    case .upperAlpha: return alpha(index, upper: true) + "."
    case .lowerRoman: return roman(index, upper: false) + "."
    case .upperRoman: return roman(index, upper: true) + "."
    case .custom(let name): return cascade.CounterStyleText(name, n: index, marker: true) ?? "\(index)."
    }
}

/// Whether an <object> or <embed> points at an HTML document, by its
/// type or its URL's extension: what the page shows as a nested frame.
public func EmbedsDocument(node: html.Node) -> bool {
    let type = css.lower(node.GetAttribute("type") ?? "")
    if type.contains("html") { return true }
    if !type.isEmpty { return false }
    let src = css.lower(node.GetAttribute(node.TagName == "object" ? "data" : "src") ?? "")
    return src.hasSuffix(".html") || src.hasSuffix(".htm") || src.hasSuffix("/")
}

/// ASCII punctuation that ::first-letter takes with the letter.
func isPunctuation(b: uint8) -> bool {
    switch b {
    case 33, 34, 35, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 58, 59, 63, 64, 91, 92, 93, 95, 123, 125: return true
    default: return false
    }
}
