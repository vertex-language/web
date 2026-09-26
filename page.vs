package web

import (
    "fs"
    "image"
    "image/draw"
    "image/format"
    "text/font"
    "web/cascade"
    "web/css"
    "web/css/selector"
    "web/dom"
    "web/fetch"
    "web/html"
    "web/layout"
    "web/paint"
)

/// How a page is set up.
public struct Config {
    /// Where relative URLs in the page are resolved from: a directory
    /// path or a file URL. Nil resolves nothing.
    public var BaseURL: string?
    /// What shows behind a page that sets no background.
    public var BackgroundColor: draw.Color
    /// Where the page's resources come from: stylesheets, images, fonts.
    /// By default, file paths under BaseURL are read from disk.
    public var Fetcher: fetch.Fetcher

    public init(baseURL: string? = nil, backgroundColor: draw.Color = draw.Color.white, fetcher: fetch.Fetcher = fetch.Fetcher()) {
        BaseURL = baseURL
        BackgroundColor = backgroundColor
        Fetcher = fetcher
    }
}

/// Whether the page took an input.
public enum EventResult: Equatable {
    case handled
    case ignored
}

/// The pointer shape the page asks for where the pointer is.
public enum Cursor: Equatable {
    case `default`
    case pointer
    case text
    case crosshair
    case ewResize
    case nsResize
}

/// The system clipboard, as the host provides it. Without one, copy and
/// paste do nothing.
public protocol Clipboard {
    func ReadText() -> string
    func WriteText(_ text: string)
}

/// An HTML page: parses, styles, lays out and paints what it is given,
/// takes input in its own coordinates, and tells its host what the user
/// did. It needs no window: a host puts it on screen (`ui/webview`), or
/// renders it into pixels itself.
///
/// Coordinates are CSS pixels from the top-left corner of the viewport.
/// Everything here runs on the main thread.
@MainActor
public final class Page {
    public var Configuration: Config
    public var Document: html.Document?
    /// Where copy and paste go. Nil keeps them inside the page.
    public var Clipboard: Clipboard? = nil

    let resolver: cascade.StyleResolver
    let context: selector.MatchContext
    var builder: layout.BoxTreeBuilder
    var laidOut: layout.Layout? = nil
    var root: layout.Box?
    var displayList: [paint.PaintItem] = []
    var images: [string: draw.Image] = [:]
    var fontFaces: [string] = []

    var size: draw.Size
    var scroll: draw.Point
    var contentWidth: float32 = 0
    var contentHeight: float32 = 0

    var needsStyle = true
    var needsLayout = true
    var needsPaint = true
    var needsRepaint = true

    var hovered: html.Node? = nil
    var focused: html.Node? = nil
    var pressed: html.Node? = nil
    var caret: int = 0
    var values: [int64: string] = [:]
    var caretVisible = true
    var caretPhase: float64 = 0
    /// The other end of the focused field's selection: the caret when
    /// nothing is selected in it.
    var fieldAnchor: int = 0
    var fieldSelecting = false
    var selectionAnchor: dom.TextPosition? = nil
    var selectionFocus: dom.TextPosition? = nil
    var selecting = false
    var cursor: Cursor = Cursor.default
    /// Where the pointer is, or nil when it is not over the page.
    var pointer: draw.Point? = nil
    var baseURL: string = ""
    var title: string = ""

    var onNavigate: ((string) -> Void)? = nil
    var onSubmit: ((dom.Submission) -> Void)? = nil
    var onAction: ((string, string) -> Void)? = nil
    var onTitle: ((string) -> Void)? = nil
    var onHoverLink: ((string?) -> Void)? = nil
    var isVisited: ((string) -> bool)? = nil

    public init(configuration: Config? = nil) {
        if let c = configuration {
            Configuration = c
        } else {
            Configuration = Config()
        }
        Document = nil
        resolver = cascade.StyleResolver(ua: cascade.UserAgentRules())
        context = selector.MatchContext()
        builder = layout.BoxTreeBuilder(resolver: resolver, context: context)
        size = draw.Size(800, 600)
        scroll = draw.Point(0, 0)
        baseURL = Configuration.BaseURL ?? ""
    }

    // MARK: - Loading

    /// Shows an HTML page. Its <style> elements and <link rel=stylesheet>
    /// references are read; relative references resolve against baseURL
    /// or the configuration's.
    public func LoadHTML(_ source: string, baseURL: string? = nil) {
        if let b = baseURL { self.baseURL = b }
        let doc = html.Parse(source)
        load(doc)
    }

    /// Shows an HTML file from disk; its folder is the base for what it
    /// refers to.
    public func LoadFile(_ path: string) throws {
        let bytes = try fs.ReadFile(fs.Path(path))
        LoadHTML(stringOf(bytes, 0, bytes.count), baseURL: fetch.Directory(of: path))
    }

    func load(_ doc: html.Document) {
        Document = doc
        resolver.Author = cascade.RuleSet()
        fontFaces = []
        images = [:]
        // <base href> moves the base for everything that follows.
        for base in doc.ElementsByTagName("base") {
            if let href = base.GetAttribute("href"), !href.isEmpty {
                baseURL = Resolve(href)
            }
        }
        values = [:]
        focused = nil
        hovered = nil
        pressed = nil
        scroll = draw.Point(0, 0)
        for head in doc.ElementsByTagName("head") {
            for child in head.Children where child.Kind == html.NodeKind.element {
                if child.TagName == "style" {
                    addSheet(css.Parse(child.InnerText()))
                } else if child.TagName == "link" {
                    let rel = lower(child.GetAttribute("rel") ?? "")
                    if rel == "stylesheet", let href = child.GetAttribute("href") {
                        if let bytes = Configuration.Fetcher.Fetch(Resolve(href)) {
                            addSheet(css.Parse(stringOf(bytes, 0, bytes.count)))
                        }
                    }
                }
            }
        }
        // Styles in the body count too, as browsers allow.
        for body in doc.ElementsByTagName("body") {
            for style in dom.Descendants(body, tag: "style") {
                addSheet(css.Parse(style.InnerText()))
            }
        }
        var wanted: [string] = []
        for img in doc.ElementsByTagName("img") {
            if let src = img.GetAttribute("src") { wanted.append(src) }
        }
        for url in resolver.Author.ImageURLs { wanted.append(url) }
        for src in wanted {
            if images[src] == nil {
                if src.hasPrefix("data:") {
                    if let decoded = format.DecodeDataURL(src) { images[src] = drawable(decoded) }
                } else if let bytes = Configuration.Fetcher.Fetch(Resolve(src)), let decoded = decodeImage(bytes) {
                    images[src] = decoded
                }
            }
        }
        title = doc.Title
        if let cb = onTitle { cb(title) }
        needsStyle = true
        needsRepaint = true
    }

    /// Adds a stylesheet: its rules, and the fonts its @font-face rules
    /// name, registered from the files they point at.
    func addSheet(_ sheet: css.StyleSheet, depth: int = 0) {
        // @import brings another sheet in first, as it precedes the rules.
        if depth < 8 {
            for at in sheet.AtRules where at.Name == "import" {
                let url = importURL(at.Params)
                if url.isEmpty { continue }
                if let bytes = Configuration.Fetcher.Fetch(Resolve(url)) {
                    addSheet(css.Parse(stringOf(bytes, 0, bytes.count)), depth: depth + 1)
                }
            }
        }
        resolver.Author.Add(sheet)
        for at in sheet.AtRules where at.Name == "font-face" {
            var family = ""
            var sources: [string] = []
            for d in at.Declarations {
                if d.Property == "font-family" {
                    for t in d.Tokens where t.Kind == .string || t.Kind == .ident {
                        family = family.isEmpty ? t.Value : family + " " + t.Value
                    }
                } else if d.Property == "src" {
                    for t in d.Tokens where t.Kind == .url { sources.append(t.Value) }
                }
            }
            if family.isEmpty { continue }
            for src in sources {
                let path = fetch.FilePath(Resolve(src))
                if path.contains("://") { continue }
                if font.Register(path: path, as: family) {
                    fontFaces.append(family)
                    break
                }
            }
        }
    }

    /// A URL made absolute against the page's base: absolute ones and
    /// fragments are left alone.
    public func Resolve(_ url: string) -> string {
        return fetch.Resolve(url, against: baseURL)
    }

    /// The page's title, from <title>.
    public var Title: string { return title }

    /// Adds an image the page may refer to by URL, as when the host
    /// fetches it; the page is laid out again with it.
    public func SetImage(_ url: string, _ image: draw.Image) {
        images[url] = image
        needsStyle = true
    }

    // MARK: - Geometry

    /// How big the viewport is, in CSS pixels.
    public var ViewportSize: draw.Size { return size }

    /// Resizes the viewport.
    public func SetViewportSize(_ size: draw.Size) {
        let widthChanged = self.size.Width != size.Width
        let heightChanged = self.size.Height != size.Height
        self.size = size
        if widthChanged || heightChanged {
            resolver.ViewportWidth = size.Width
            resolver.ViewportHeight = size.Height
            if resolver.Author.UsesViewport || resolver.UA.UsesViewport {
                needsStyle = true
            } else {
                needsLayout = true
            }
        }
        needsRepaint = true
    }

    public func ScrollOffset() -> draw.Point { return scroll }

    public func SetScrollOffset(_ offset: draw.Point) {
        scroll = offset
        clampScroll()
        needsRepaint = true
    }

    /// The size of the whole page.
    public func ContentSize() -> draw.Size {
        update()
        return draw.Size(contentWidth, contentHeight)
    }

    public func NeedsRepaint() -> bool { return needsRepaint || needsStyle || needsLayout || needsPaint }

    /// Whether the page has something moving on its own -- a blinking
    /// caret -- and wants frames while it does. A host that gets true
    /// calls `Advance` with each frame's time and keeps requesting frames.
    public func NeedsAnimation() -> bool {
        if let f = focused { return dom.IsTextControl(f) }
        return false
    }

    /// Moves the page's own animation to a time in seconds: the caret
    /// blinks at a second per cycle. Answers whether a repaint is needed.
    public func Advance(time: float64) -> bool {
        guard NeedsAnimation() else { return false }
        if caretPhase < 0 { caretPhase = time }
        let phase = time - caretPhase
        let cycles = phase - float64(int64(phase))
        let visible = cycles < 0.5
        if visible != caretVisible {
            caretVisible = visible
            needsPaint = true
            return true
        }
        return false
    }

    /// The pointer shape for where the pointer is.
    public func DesiredCursor() -> Cursor { return cursor }

    // MARK: - Callbacks

    /// Called with the resolved URL when the user follows a link.
    public func OnNavigate(_ handler: (string) -> Void) { onNavigate = handler }
    /// Called when a form is submitted: by its button, or Enter in a field.
    public func OnSubmit(_ handler: (dom.Submission) -> Void) { onSubmit = handler }
    /// Called when a button outside a form is pressed, with its name and value.
    public func OnAction(_ handler: (string, string) -> Void) { onAction = handler }
    public func OnTitleChanged(_ handler: (string) -> Void) { onTitle = handler }
    /// Called with a link's URL as the pointer moves onto it, and nil off it.
    public func OnHoverLink(_ handler: (string?) -> Void) { onHoverLink = handler }
    /// Asked whether a resolved URL has been visited, for `:visited`.
    /// Call `Invalidate()` when the answer changes.
    public func IsVisited(_ handler: (string) -> bool) { isVisited = handler; needsStyle = true }

    // MARK: - The pipeline

    /// Brings the page up to date: boxes, layout and the display list,
    /// whichever are stale.
    func update() {
        if needsStyle {
            builder.Images = images
            builder.Values = values
            context.Reset()
            context.Hovered = hovered
            context.Focused = focused
            context.Active = pressed
            if let v = isVisited, resolver.UsesVisited {
                context.Visited = { node in
                    if let href = node.GetAttribute("href") { return v(self.Resolve(href)) }
                    return false
                }
            } else {
                context.Visited = nil
            }
            if let doc = Document {
                root = builder.Build(doc)
            } else {
                root = nil
            }
            needsStyle = false
            needsLayout = true
        }
        if needsLayout {
            if let r = root {
                let run = layout.Layout(viewportWidth: size.Width, viewportHeight: size.Height)
                run.Run(r)
                laidOut = run
                contentHeight = r.Y + r.Height + r.Margin.Bottom
                contentWidth = r.X + r.Width + r.Margin.Right
                if r.ContentWidth + r.X + r.ContentX > contentWidth { contentWidth = r.ContentWidth + r.X + r.ContentX }
            } else {
                contentHeight = 0
                contentWidth = 0
            }
            clampScroll()
            needsLayout = false
            needsPaint = true
        }
        if needsPaint {
            if let r = root {
                var state = paint.State()
                state.Focused = focused?.Id ?? 0
                state.Caret = caret
                state.CaretVisible = caretVisible
                if let r = fieldRange() {
                    state.FieldSelectionStart = r.start
                    state.FieldSelectionEnd = r.end
                }
                state.Images = images
                if let range = selectionRange() {
                    state.SelectionStart = range.start
                    state.SelectionEnd = range.end
                    state.TextOrder = builder.textOrder
                }
                displayList = paint.Build(r, state: state, viewportWidth: size.Width, viewportHeight: size.Height, background: Configuration.BackgroundColor)
            } else {
                displayList = []
            }
            needsPaint = false
            needsRepaint = true
        }
    }

    func clampScroll() {
        let maxY = contentHeight > size.Height ? contentHeight - size.Height : 0
        let maxX = contentWidth > size.Width ? contentWidth - size.Width : 0
        if scroll.Y > maxY { scroll.Y = maxY }
        if scroll.Y < 0 { scroll.Y = 0 }
        if scroll.X > maxX { scroll.X = maxX }
        if scroll.X < 0 { scroll.X = 0 }
        // Sticky boxes follow the scroll, which repaints them.
        if let l = laidOut, !l.Sticky.isEmpty {
            if l.UpdateSticky(scrollY: scroll.Y, viewportHeight: size.Height) {
                needsPaint = true
            }
        }
    }

    // MARK: - Drawing

    /// Paints the page into premultiplied RGBA pixels, `width` by `height`
    /// device pixels, with its viewport's top-left corner at `origin` (in
    /// CSS pixels) and `scale` device pixels to the CSS pixel.
    public func Draw(into pixels: inout [uint8], width: int32, height: int32, scale: float32, at origin: draw.Point = draw.Point.zero) {
        update()
        let viewRect = draw.Rect(origin.X, origin.Y, size.Width, size.Height).Snapped(scale: scale)
        let list = displayList
        let sx = scroll.X
        let sy = scroll.Y
        let bg = Configuration.BackgroundColor
        let showBar = contentHeight > size.Height
        let barHeight = size.Height * size.Height / (contentHeight > 0 ? contentHeight : 1)
        let barY = size.Height > barHeight ? (size.Height - barHeight) * (sy / (contentHeight - size.Height)) : 0
        let viewWidth = size.Width
        draw.WithCanvas(&pixels, width: width, height: height) { c in
            var canvas = c
            canvas.ClipTo(viewRect)
            if bg.A > 0 { canvas.Fill(viewRect, bg) }
            paint.Rasterize(list, on: canvas, scale: scale, originX: float32(viewRect.X), originY: float32(viewRect.Y), scrollX: sx, scrollY: sy)
            if showBar {
                let track = draw.Rect(origin.X + viewWidth - 10, origin.Y + barY + 2, 6, barHeight - 4).Snapped(scale: scale)
                canvas.FillRounded(track, radii: draw.Radii(all: 3 * scale), draw.Color(0, 0, 0, 90))
            }
        }
        needsRepaint = false
    }

    // MARK: - Finding things

    /// The element under a point in the viewport, or nil.
    public func ElementAt(_ p: draw.Point) -> html.Node? {
        update()
        return hitAt(p)?.Node
    }

    func hitAt(_ p: draw.Point) -> layout.Hit? {
        guard let r = root else { return nil }
        return layout.HitTest(r, p.X + scroll.X, p.Y + scroll.Y, originX: 0, originY: 0)
    }

    /// The layout box of an element, once laid out.
    public func BoxFor(_ node: html.Node) -> layout.Box? {
        update()
        return builder.byNode[node.Id]
    }

    /// The root of the layout tree.
    public var RootBox: layout.Box? {
        update()
        return root
    }

    public func QuerySelector(_ sel: string) -> html.Node? {
        guard let doc = Document else { return nil }
        return selector.QuerySelector(sel, in: doc.Root)
    }

    public func QuerySelectorAll(_ sel: string) -> [html.Node] {
        guard let doc = Document else { return [] }
        return selector.QuerySelectorAll(sel, in: doc.Root)
    }

    /// The element with keyboard focus.
    public var FocusedElement: html.Node? { return focused }

    /// The selection's ends in document order, or nil for none.
    func selectionRange() -> (start: dom.TextPosition, end: dom.TextPosition)? {
        guard let a = selectionAnchor, let f = selectionFocus else { return nil }
        let ao = builder.textOrder[a.Node.Id] ?? 0
        let fo = builder.textOrder[f.Node.Id] ?? 0
        if ao < fo || (ao == fo && a.Offset <= f.Offset) {
            if ao == fo && a.Offset == f.Offset { return nil }
            return (start: a, end: f)
        }
        return (start: f, end: a)
    }

    /// Whether any text is selected.
    public var HasSelection: bool { return selectionRange() != nil || fieldRange() != nil }

    /// The selected text, with a line break where the selection spans lines.
    public func SelectedText() -> string {
        update()
        if let f = focused, let r = fieldRange() {
            let bytes = [uint8](valueOf(f).utf8)
            return stringOf(bytes, min(r.start, bytes.count), min(r.end, bytes.count))
        }
        guard let range = selectionRange(), let r = root else { return "" }
        var out = ""
        var pastLine = false
        collectSelectedText(r, range, &out, &pastLine)
        return out
    }

    func collectSelectedText(_ box: layout.Box, _ range: (start: dom.TextPosition, end: dom.TextPosition), _ out: inout string, _ lineBroken: inout bool) {
        if box.Kind == .replaced { return }
        if !box.Lines.isEmpty {
            for line in box.Lines {
                var tookSomething = false
                for f in line.Fragments {
                    if f.Kind == .atomic {
                        collectSelectedText(f.Box, range, &out, &lineBroken)
                        continue
                    }
                    if f.Kind != .text { continue }
                    guard let node = f.Box.Node else { continue }
                    if let part = paint.SelectedPart(f, node, range, builder.textOrder) {
                        if lineBroken && !out.isEmpty { out += "\n" }
                        lineBroken = false
                        let bytes = [uint8](f.Text.utf8)
                        out += stringOf(bytes, part.from, part.to)
                        tookSomething = true
                    }
                }
                if tookSomething { lineBroken = true }
            }
            return
        }
        for child in box.Children {
            if child.Kind == .text || child.Kind == .inline || child.Kind == .lineBreak { continue }
            collectSelectedText(child, range, &out, &lineBroken)
        }
    }

    /// Clears the selection.
    public func ClearSelection() {
        if selectionAnchor != nil || selectionFocus != nil {
            selectionAnchor = nil
            selectionFocus = nil
            needsPaint = true
        }
    }

    /// Selects all the text on the page.
    public func SelectAll() {
        update()
        guard let r = root else { return }
        selectText(in: r)
    }

    /// Selects the text of the block a text box is in.
    func selectBlock(of text: layout.Box) {
        var block: layout.Box = text
        while let p = block.Parent, block.Kind != .block && block.Kind != .inlineBlock { block = p }
        selectText(in: block)
    }

    func selectText(in box: layout.Box) {
        var first: layout.Box? = nil
        var last: layout.Box? = nil
        findTextBoxes(box, &first, &last)
        guard let f = first, let l = last, let fn = f.Node, let ln = l.Node else { return }
        selectionAnchor = dom.TextPosition(Node: fn, Offset: 0)
        selectionFocus = dom.TextPosition(Node: ln, Offset: l.Text.utf8.count)
        needsPaint = true
    }

    func findTextBoxes(_ box: layout.Box, _ first: inout layout.Box?, _ last: inout layout.Box?) {
        if box.Kind == .text {
            if !layout.IsBlank(box.Text) {
                if first == nil { first = box }
                last = box
            }
            return
        }
        for c in box.Children { findTextBoxes(c, &first, &last) }
    }

    /// Gives an element focus, as clicking it or tabbing to it would.
    public func Focus(_ node: html.Node?) {
        if focused?.Id == node?.Id { return }
        focused = node
        if let n = node {
            let value = valueOf(n)
            caret = value.utf8.count
            fieldAnchor = caret
        }
        showCaret()
        stateChanged()
        needsPaint = true
    }

    /// Hover, focus or the press moved: styles need recomputing only
    /// where a rule asking about them matches differently now, which
    /// the trace of the last build tells without a rebuild.
    func stateChanged() {
        if needsStyle || root == nil { return }
        if resolver.StateTrace.isEmpty { return }
        context.Hovered = hovered
        context.Focused = focused
        context.Active = pressed
        if resolver.StateMatchesChanged(context) {
            needsStyle = true
        }
    }

    /// Scrolls so that an element is at the top of the viewport.
    public func ScrollTo(_ node: html.Node) {
        update()
        guard let b = builder.byNode[node.Id] else { return }
        let pos = layout.PagePosition(b)
        scroll.Y = pos.y
        clampScroll()
        needsRepaint = true
    }

    /// Scrolls just enough to show an element.
    public func ScrollIntoViewIfNeeded(_ node: html.Node) {
        update()
        guard let b = builder.byNode[node.Id] else { return }
        let pos = layout.PagePosition(b)
        if pos.y < scroll.Y {
            scroll.Y = pos.y
        } else if pos.y + b.Height > scroll.Y + size.Height {
            scroll.Y = pos.y + b.Height - size.Height
        }
        clampScroll()
        needsRepaint = true
    }

    /// Marks the page as changed: the host edited the DOM.
    public func Invalidate() {
        needsStyle = true
    }

    /// The text a form control holds now.
    public func ValueOf(_ node: html.Node) -> string {
        return valueOf(node)
    }

    func valueOf(_ node: html.Node) -> string {
        if let v = values[node.Id] { return v }
        if node.TagName == "textarea" { return node.InnerText() }
        return node.GetAttribute("value") ?? ""
    }

    func setValue(_ node: html.Node, _ value: string) {
        values[node.Id] = value
        showCaret()
        needsStyle = true
    }

    /// The selected bytes of the focused text control, if any.
    func fieldRange() -> (start: int, end: int)? {
        guard let f = focused, dom.IsTextControl(f), fieldAnchor != caret else { return nil }
        return fieldAnchor < caret ? (start: fieldAnchor, end: caret) : (start: caret, end: fieldAnchor)
    }

    /// Puts the caret somewhere, extending the field's selection from
    /// its anchor or collapsing it there.
    func moveCaret(_ to: int, extend: bool) {
        caret = to
        if !extend { fieldAnchor = to }
        showCaret()
        needsPaint = true
    }

    /// Shows the caret now, as typing or moving does, restarting its blink.
    func showCaret() {
        caretVisible = true
        caretPhase = -1
    }
}

/// The URL an @import names: its first string or url().
func importURL(_ params: string) -> string {
    let b = [uint8](params.utf8)
    if b.count > 4 && startsWithBytes(b, "url(") {
        var j = 4
        while j < b.count && (b[j] == 34 || b[j] == 39 || b[j] == 32) { j += 1 }
        let start = j
        while j < b.count && b[j] != 41 && b[j] != 34 && b[j] != 39 { j += 1 }
        return stringOf(b, start, j)
    }
    if !b.isEmpty && (b[0] == 34 || b[0] == 39) {
        var i = 1
        while i < b.count && b[i] != b[0] { i += 1 }
        return stringOf(b, 1, i)
    }
    return ""
}

func decodeImage(_ bytes: [uint8]) -> draw.Image? {
    guard let decoded = format.Decode(bytes) else { return nil }
    return drawable(decoded)
}

func drawable(_ img: image.RGBA) -> draw.Image {
    return draw.Image(width: int32(img.Width), height: int32(img.Height), pixels: img.Pixels)
}
