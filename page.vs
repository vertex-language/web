package web

import (
    "fs"
    "image"
    "image/draw"
    "image/format"
    "sync"
    "text/font"
    "web/cascade"
    "web/css"
    "web/css/selector"
    "web/dom"
    "web/fetch"
    "web/html"
    "web/layout"
    "web/paint"
    "web/svg"
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
    /// Whether loading leaves the page's images for LoadImages, which
    /// decodes them off the main thread, instead of decoding each as it
    /// loads -- which a window's page wants, and a headless render
    /// doesn't need.
    public var DefersImages: bool

    public init(baseURL: string? = nil, backgroundColor: draw.Color = draw.Color.white, fetcher: fetch.Fetcher = fetch.Fetcher(),
                defersImages: bool = false) {
        BaseURL = baseURL
        BackgroundColor = backgroundColor
        Fetcher = fetcher
        DefersImages = defersImages
    }
}

/// Whether the page took an input.
public enum EventResult: Equatable {
    case handled
    case ignored
}

/// The pointer shape the page asks for where the pointer is: CSS's
/// cursor keywords (auto resolved). CSSName is its keyword.
public enum Cursor: Equatable {
    case `default`
    case none
    case contextMenu
    case help
    case pointer
    case progress
    case wait
    case cell
    case crosshair
    case text
    case verticalText
    case alias
    case copy
    case move
    case noDrop
    case notAllowed
    case grab
    case grabbing
    case allScroll
    case colResize
    case rowResize
    case nResize
    case eResize
    case sResize
    case wResize
    case neResize
    case nwResize
    case seResize
    case swResize
    case ewResize
    case nsResize
    case neswResize
    case nwseResize
    case zoomIn
    case zoomOut
}

extension Cursor {
    /// The CSS keyword for the cursor: "pointer", "nwse-resize".
    public var CSSName: string {
        switch self {
        case .`default`: return "default"
        case .none: return "none"
        case .contextMenu: return "context-menu"
        case .help: return "help"
        case .pointer: return "pointer"
        case .progress: return "progress"
        case .wait: return "wait"
        case .cell: return "cell"
        case .crosshair: return "crosshair"
        case .text: return "text"
        case .verticalText: return "vertical-text"
        case .alias: return "alias"
        case .copy: return "copy"
        case .move: return "move"
        case .noDrop: return "no-drop"
        case .notAllowed: return "not-allowed"
        case .grab: return "grab"
        case .grabbing: return "grabbing"
        case .allScroll: return "all-scroll"
        case .colResize: return "col-resize"
        case .rowResize: return "row-resize"
        case .nResize: return "n-resize"
        case .eResize: return "e-resize"
        case .sResize: return "s-resize"
        case .wResize: return "w-resize"
        case .neResize: return "ne-resize"
        case .nwResize: return "nw-resize"
        case .seResize: return "se-resize"
        case .swResize: return "sw-resize"
        case .ewResize: return "ew-resize"
        case .nsResize: return "ns-resize"
        case .neswResize: return "nesw-resize"
        case .nwseResize: return "nwse-resize"
        case .zoomIn: return "zoom-in"
        case .zoomOut: return "zoom-out"
        }
    }
}

/// The system clipboard, as the host provides it. Without one, copy and
/// paste do nothing.
public protocol Clipboard {
    func ReadText() -> string
    func WriteText(text: string)
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
    /// The live document. Change it through its methods (or an
    /// `Element`'s), which journal what they do: the next frame restyles
    /// from the journal.
    public internal(set) var Document: dom.Document?
    /// Where copy and paste go. Nil keeps them inside the page.
    public var Clipboard: Clipboard? = nil

    let resolver: cascade.StyleResolver
    /// Transitions and @keyframes animations (animate.vs).
    let animator: Animator
    let context: selector.MatchContext
    var builder: layout.BoxTreeBuilder
    var laidOut: layout.Layout? = nil
    var root: layout.Box?
    var displayList: [paint.PaintItem] = []
    var images: [string: draw.Image] = [:]
    /// The images that are SVG files, drawn as vectors.
    var vectors: [string: svg.Document] = [:]
    /// The images the page names and hasn't decoded: LoadImages's.
    var pendingImages: [string] = []
    /// Images styles name that loading was tried for, found or not:
    /// what loadStyleImages doesn't ask for again.
    var triedImages: [string: bool] = [:]
    /// The validation bubble a stopped submit shows: the control, what
    /// it says, and when it went up (-1 until a frame's time is known).
    var bubbleNode: html.Node? = nil
    var bubbleText: string = ""
    var bubbleSince: float64 = -1
    var fontFaces: [string] = []

    var size: draw.Size
    var scroll: draw.Point
    var contentWidth: float32 = 0
    var contentHeight: float32 = 0

    var needsStyle = true
    /// Restyles in a row for container queries (update).
    var containerPasses = 0
    /// Nested documents by element id (frames.vs), and which of them the
    /// pointer is over, pressed in, and clicked into.
    var frames: [int64: Frame] = [:]
    var framePass = 0
    var lastPointer = draw.Point(0, 0)
    var pressedFrame: int64? = nil
    var hoveredFrame: Frame? = nil
    var focusedFrame: Frame? = nil
    var needsLayout = true
    var needsPaint = true
    var needsRepaint = true

    var hovered: html.Node? = nil
    var focused: html.Node? = nil
    var pressed: html.Node? = nil
    /// The <input type=range> being dragged, if one is.
    var sliding: html.Node? = nil
    /// The element a press began on: pointermove and pointerup go to it
    /// until the release, wherever the pointer goes.
    var captured: html.Node? = nil
    var caret: int = 0
    var values: [int64: string] = [:]
    /// Whether the last input was the keyboard's: focus it gives shows
    /// :focus-visible.
    var keyboardInput = false
    var focusVisible = false
    /// The element the last jump to a fragment named: :target.
    var target: html.Node? = nil
    /// The controls the user has changed: :user-valid and :user-invalid.
    var userEdited = Set<int64>()
    /// What file inputs hold, by element.
    var files: [int64: [string]] = [:]
    /// A resize grip being dragged: the element, where the drag began,
    /// the element's size then, and its style attribute then.
    var resizing: (node: html.Node, start: draw.Point, width: float32, height: float32, style: string)? = nil
    /// Elements' scroll offsets by element, which outlive the box tree;
    /// a smooth scroll under way; a wheel scroll waiting to snap
    /// (scrolling.vs).
    var elementScroll: [int64: draw.Point] = [:]
    /// The top layer, in order, with which of its elements are modal
    /// dialogs and which open popovers; dialogs' return values
    /// (dialogs.vs).
    var topLayer: [int64] = []
    var modal = Set<int64>()
    var popovers = Set<int64>()
    var dialogReturnValues: [int64: string] = [:]
    /// A drag under way, or a press that may become one (dragdrop.vs).
    var dragging: DragState? = nil
    var scrollAnimation: ScrollAnimation? = nil
    var pendingSnap: (node: int64, at: float64)? = nil
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
    /// Where the pointer is over the page, for the cursor: what the
    /// handlers of a move changed (a viewport source's cursor, a class)
    /// shows on that move, not the next.
    var cursorPoint: draw.Point? = nil
    /// Where the pointer is, or nil when it is not over the page.
    var pointer: draw.Point? = nil
    /// The modifier keys held, as the last input said: what mouse and
    /// wheel events report.
    var modifiers = Modifiers()
    /// What an input method is composing and has not committed, shown at
    /// the focused field's caret; "" when nothing is.
    public internal(set) var Composing = ""
    /// Whether the primary press in progress was taken by a pointerdown
    /// listener: the mouse events that follow it are not sent, as the
    /// Pointer Events standard has it.
    var mouseSuppressed = false
    var baseURL: string = ""
    var title: string = ""

    var onNavigate: ((string) -> Void)? = nil
    var onSubmit: ((dom.Submission) -> Void)? = nil
    var onAction: ((string, string) -> Void)? = nil
    /// The host's pickers: a color well, a file input, a date or time
    /// field asking for one (the element, and what it holds now).
    var onPickColor: ((html.Node, string) -> Void)? = nil
    var onPickFiles: ((html.Node, bool, string) -> Void)? = nil
    var onPickDate: ((html.Node, string, string) -> Void)? = nil
    /// How many clicks the last primary press was: 2 on a double click.
    var downClicks: int32 = 1
    /// The document's <style> and <link rel=stylesheet> elements, and the
    /// sheets the program set.
    var docSheets: [html.Node] = []
    var programSheets: [string] = []
    var onTitle: ((string) -> Void)? = nil
    var onHoverLink: ((string?) -> Void)? = nil
    var mediaOpener: ((string) -> (any MediaPlayer)?)? = nil
    var media: [int64: MediaState] = [:]
    var mediaFrames: [int64: draw.Image] = [:]
    var snapFrom: draw.Point? = nil
    /// Laying out for paper: no scroll bar on the sheets.
    var printing = false
    /// A list box's first row showing, by select.
    var listTop: [int64: int] = [:]
    var listAnchor: [int64: int] = [:]
    /// Escape put a field's suggestions away until it's typed in again.
    var suggestionsDismissed = false
    /// The images with frames of their own, and which each shows.
    var animatedImages: [string: format.AnimatedImage] = [:]
    var animatedStart: float64 = -1
    var shownFrame: [string: int] = [:]
    /// The page's size when timelines were last styled.
    var timelineSizedFor = draw.Point(0, 0)
    var previousBoxes: [int64: layout.Box] = [:]
    /// A view transition: the old picture and how much of it still shows,
    /// the named boxes moving, when it began; the scale last drawn at.
    var oldPicture: draw.Image? = nil
    var oldGroups: [string: (node: int64, rect: draw.Rect)] = [:]
    var transitionMoves: [TransitionMove] = []
    var transitionFade: float32 = 0
    /// How long it all runs, the last group's end; the page's own fade's
    /// timing; and how far in it is.
    var transitionLength: float64 = 0.25
    var rootTiming = TransitionTiming()
    var transitionElapsed: float64 = 0
    var transitionAt: float64 = -1
    var drawnScale: float32 = 0
    /// The text on each sheet the last Print made.
    var printedText: [[SheetText]] = []
    /// The panel open over the page, if any.
    var picker: Picker? = nil
    /// Whether a precise scroll past the page's end stretches it, and how
    /// far it is stretched now, in CSS pixels; when it last eased back.
    public var Bounces: bool = false
    var overscroll: float32 = 0
    var overscrollAt: float64 = -1
    /// Named ranges of text ::highlight() styles, and ::target-text's.
    var highlights: [string: [(start: dom.TextPosition, end: dom.TextPosition)]] = [:]
    /// The URLs an opener turned down, and whom to tell.
    var mediaRefused: [int64: string] = [:]
    var mediaErrors: [html.Node] = []
    /// What each element with a layout listener was last told; whether
    /// layout has run since.
    var layoutTold: [int64: draw.Rect] = [:]
    var layoutRan = false
    /// The <img>s yet to be told their image loaded or failed.
    var pendingImageEvents: [html.Node] = []
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
        animator = Animator(resolver: resolver)
        size = draw.Size(800, 600)
        scroll = draw.Point(0, 0)
        baseURL = Configuration.BaseURL ?? ""
        let a = animator
        resolver.Animate = { node, style, parent in a.apply(node, style, parent) }
        a.measureAuto = { node, height in self.measureAutoSize(node, height: height) }
        a.timelineProgress = { node, timeline, range in self.timelineProgress(node, timeline: timeline, range: range) }
        a.startingStyle = { node, style, parent in self.resolver.ResolveStarting(node, style: style, parent: parent, context: self.context) }
        context.Interacted = { node in self.userEdited.contains(node.Id) }
        context.ValueOf = { node in self.valueOf(node) }
    }

    // MARK: - Loading

    /// Shows an HTML page. Its <style> elements and <link rel=stylesheet>
    /// references are read; relative references resolve against baseURL
    /// or the configuration's.
    public func LoadHTML(source: string, baseURL: string? = nil) {
        if let b = baseURL { self.baseURL = b }
        let doc = html.Parse(source)
        // A page may ask to fade in over the one before.
        cascade.ViewTransitionOnNavigation = false
        takeTransitionPicture()
        load(doc)
        update()
        if cascade.ViewTransitionOnNavigation { beginTransition() } else { oldPicture = nil }
    }

    /// Shows an HTML file from disk; its folder is the base for what it
    /// refers to.
    public func LoadFile(path: string) throws {
        let bytes = try fs.ReadFile(fs.Path(path))
        LoadBytes(bytes, baseURL: fetch.Directory(of: path))
    }

    /// Shows an HTML page from its bytes, decoded as the HTML standard
    /// says: by a byte order mark, the Content-Type's charset, a <meta
    /// charset>, or as UTF-8.
    public func LoadBytes(bytes: [uint8], contentType: string? = nil, baseURL: string? = nil) {
        LoadHTML(html.Decode(bytes, contentType: contentType), baseURL: baseURL)
    }

    func load(doc: html.Document) {
        layoutTold = [:]
        listTop = [:]
        animatedImages = [:]
        animatedStart = -1
        cascade.PageRule = nil
        cascade.PageRulesFor = [:]
        picker = nil
        context.PickerOpen = Set<int64>()
        builder.PickersOpen = context.PickerOpen
        highlights = [:]
        frames = [:]
        files = [:]
        target = nil
        elementScroll = [:]
        topLayer = []
        modal = []
        popovers = []
        dialogReturnValues = [:]
        builder.TopLayer = []
        context.Modal = []
        context.PopoverOpen = []
        scrollAnimation = nil
        pendingSnap = nil
        userEdited = []
        pressedFrame = nil
        hoveredFrame = nil
        focusedFrame = nil
        animator.elements = [:]
        animator.events = []
        Document = dom.Document(doc)
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
        // Stylesheets in document order, in the head or the body: a page
        // may link a component's sheet beside the component.
        docSheets = []
        collectSheets(doc.Root, &docSheets)
        addSheets()
        var wanted: [string] = []
        for img in doc.ElementsByTagName("img") {
            if let src = img.GetAttribute("src") { wanted.append(src) }
        }
        // A video's poster, and what an <object> or <embed> points at,
        // where it may be an image.
        for v in doc.ElementsByTagName("video") {
            if let poster = v.GetAttribute("poster") { wanted.append(poster) }
        }
        for o in doc.ElementsByTagName("object") where !layout.EmbedsDocument(o) {
            if let data = o.GetAttribute("data") { wanted.append(data) }
        }
        for e in doc.ElementsByTagName("embed") where !layout.EmbedsDocument(e) {
            if let src = e.GetAttribute("src") { wanted.append(src) }
        }
        for url in resolver.Author.ImageURLs { wanted.append(url) }
        pendingImages = []
        triedImages = [:]
        for src in wanted {
            triedImages[src] = true
            if images[src] == nil && vectors[src] == nil { loadImage(src) }
        }
        pendingImageEvents = doc.ElementsByTagName("img")
        title = doc.Title
        if let cb = onTitle { cb(title) }
        closeMedia()
        syncMedia(doc)
        needsStyle = true
        needsRepaint = true
    }

    /// The document's own sheets, then the program's (SetStyleSheets).
    func addSheets() {
        for node in docSheets {
            let media = node.GetAttribute("media") ?? ""
            if node.TagName == "style" {
                addSheet(css.Parse(node.InnerText()), media: media)
            } else if let href = node.GetAttribute("href"), let bytes = Configuration.Fetcher.Fetch(Resolve(href)) {
                addSheet(css.Parse(stringOf(bytes, 0, bytes.count)), media: media)
            }
        }
        for text in programSheets { addSheet(css.Parse(text)) }
    }

    /// Sets the stylesheets the program gives the page, after the
    /// document's own: a .vsx app's compiled .vss, in cascade order. The
    /// page restyles; setting the sheets it has costs nothing.
    public func SetStyleSheets(sheets: [string]) {
        if sheets == programSheets { return }
        programSheets = sheets
        resolver.Author = cascade.RuleSet()
        addSheets()
        needsStyle = true
        needsRepaint = true
    }

    /// The stylesheets the program gave (SetStyleSheets), in order.
    public var ProgramStyleSheets: [string] { return programSheets }

    /// Adds a stylesheet: its rules, and the fonts its @font-face rules
    /// name, registered from the files they point at.
    func addSheet(sheet: css.StyleSheet, media: string = "", depth: int = 0) {
        // @import brings another sheet in first, as it precedes the rules.
        if depth < 8 {
            for at in sheet.AtRules where at.Name == "import" {
                let url = importURL(at.Params)
                if url.isEmpty { continue }
                if let bytes = Configuration.Fetcher.Fetch(Resolve(url)) {
                    addSheet(css.Parse(stringOf(bytes, 0, bytes.count)), media: media, depth: depth + 1)
                }
            }
        }
        resolver.Author.Add(sheet, media: media)
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
            // The first source the platform can read: a local file by
            // path, anything else fetched. WOFF and WOFF2 aren't unpacked
            // yet, so a TrueType or OpenType source after them is taken.
            for src in sources {
                let url = Resolve(src)
                let path = fetch.FilePath(url)
                if !path.contains("://") {
                    if font.Register(path: path, as: family) {
                        fontFaces.append(family)
                        break
                    }
                    continue
                }
                guard let bytes = Configuration.Fetcher.Fetch(url), bytes.count > 4 else { continue }
                if bytes[0] == 119 && bytes[1] == 79 && bytes[2] == 70 { continue } // "wOF": WOFF or WOFF2
                if font.RegisterData(bytes, as: family) {
                    fontFaces.append(family)
                    break
                }
            }
        }
    }

    /// A URL made absolute against the page's base: absolute ones and
    /// fragments are left alone.
    public func Resolve(url: string) -> string {
        return fetch.Resolve(url, against: baseURL)
    }

    /// Names ranges of text, as CSS.highlights does: ::highlight(name)
    /// styles them. No ranges takes the name away.
    public func SetHighlight(name: string, ranges: [(start: dom.TextPosition, end: dom.TextPosition)]) {
        highlights[name] = ranges.isEmpty ? nil : ranges
        needsPaint = true
        needsRepaint = true
    }

    /// The highlights with the style each name's rules give it, where a rule
    /// does: a highlight with none draws nothing, as CSS's does.
    func paintHighlights() -> [paint.Highlight] {
        var out: [paint.Highlight] = []
        for (name, ranges) in highlights {
            let which = name == "target-text" ? name : "highlight(\(name))"
            guard let first = ranges.first else { continue }
            let owner = first.start.Node.Kind == html.NodeKind.element ? first.start.Node : first.start.Node.Parent
            guard let node = owner, let box = builder.byNode[node.Id],
                  let style = resolver.ResolvePseudo(node, which, parent: box.Style, context: context) else { continue }
            out.append(paint.Highlight(ranges: ranges, background: style.BackgroundColor, color: style.Color, inherited: box.Style.Color))
        }
        return out
    }

    /// A fragment directive's text (#:~:text=word), found and named for
    /// ::target-text: its first place in the document, scrolled to. Answers
    /// whether it was there.
    @discardableResult
    func goToTextFragment(text: string) -> bool {
        guard let doc = Document else { return false }
        highlights["target-text"] = nil
        guard let hit = findText(text, in: doc.Tree.Root) else { return false }
        highlights["target-text"] = [hit]
        needsPaint = true
        needsRepaint = true
        if let p = hit.start.Node.Parent { ScrollIntoViewIfNeeded(p) }
        return true
    }

    func findText(text: string, in node: html.Node) -> (start: dom.TextPosition, end: dom.TextPosition)? {
        if node.Kind == html.NodeKind.text {
            let hay = [uint8](node.Text.utf8)
            let needle = [uint8](text.utf8)
            if needle.isEmpty || hay.count < needle.count { return nil }
            var i = 0
            while i + needle.count <= hay.count {
                var k = 0
                while k < needle.count && hay[i + k] == needle[k] { k += 1 }
                if k == needle.count {
                    return (start: dom.TextPosition(Node: node, Offset: i), end: dom.TextPosition(Node: node, Offset: i + k))
                }
                i += 1
            }
            return nil
        }
        for c in node.Children {
            if let r = findText(text, in: c) { return r }
        }
        return nil
    }

    /// A scroll has moved what anchored boxes hang from, or a timeline's
    /// progress: they are placed, or styled, again.
    func scrollMovedThings() {
        if laidOut?.HasAnchored ?? false { needsLayout = true; needsRepaint = true }
        if animator.HasTimelines {
            needsStyle = true
            needsRepaint = true
        }
    }

    /// Moves animated images on. Answers whether one changed.
    func advanceAnimatedImages(time: float64) -> Bool {
        if animatedImages.isEmpty { return false }
        if animatedStart < 0 { animatedStart = time }
        var changed = false
        for (src, a) in animatedImages {
            let t = time - animatedStart
            let frame = a.FrameIndex(at: t)
            if frame == shownFrame[src] { continue }
            shownFrame[src] = frame
            let img = drawable(a.Frames[frame])
            images[src] = img
            // What has it as its picture shows the new one.
            for (_, b) in builder.byNode where b.Replaced == .image && b.Node?.GetAttribute("src") == src { b.Image = img }
            changed = true
        }
        if changed {
            needsPaint = true
            needsRepaint = true
        }
        return changed
    }

    /// Says a host filled a field, for :autofill.
    public func SetAutofilled(node: html.Node, on: bool) {
        if on { context.Autofilled.insert(node.Id) } else { context.Autofilled.remove(node.Id) }
        needsStyle = true
    }

    /// Says which element fills the screen, nil for none: :fullscreen.
    public func SetFullscreenElement(node: html.Node?) {
        context.FullscreenElement = node?.Id ?? 0
        needsStyle = true
    }

    /// Sets or clears a custom state on an element: :state(name).
    public func SetCustomState(node: html.Node, name: string, on: bool) {
        var names = context.CustomStates[node.Id] ?? Set<string>()
        if on { names.insert(name) } else { names.remove(name) }
        context.CustomStates[node.Id] = names
        needsStyle = true
    }

    /// The page's title, from <title>.
    public var Title: string { return title }

    /// Adds an image the page may refer to by URL, as when the host
    /// fetches it; the page is laid out again with it.
    public func SetImage(url: string, image: draw.Image) {
        images[url] = image
        needsStyle = true
    }

    /// The images the page names that it hasn't decoded yet (see
    /// Config.DefersImages), as the page writes them.
    public var PendingImages: [string] { pendingImages }

    /// Decodes the images loading left (Config.DefersImages) on
    /// sync.ThreadPoolExecutor.Shared, several at once, and gives them to
    /// the page: a big image decodes without holding the main thread, or
    /// a worker of the pool. Answers the URLs, resolved, of those that
    /// didn't decode.
    public func LoadImages() async -> [string] {
        var jobs: [ImageJob] = []
        for src in pendingImages where images[src] == nil && vectors[src] == nil {
            let url = Resolve(src)
            if let bytes = Configuration.Fetcher.Fetch(url) {
                jobs.append(ImageJob(src: src, url: url, bytes: bytes))
            }
        }
        pendingImages = []
        if jobs.isEmpty { return [] }
        let decoded = await withTaskGroup(of: DecodedImage.self) { group in
            for job in jobs {
                group.addTask(executorPreference: sync.ThreadPoolExecutor.Shared) { await decodeOffMain(job) }
            }
            var out: [DecodedImage] = []
            for await d in group { out.append(d) }
            return out
        }
        var failed: [string] = []
        for d in decoded {
            if let img = d.image {
                SetImage(d.src, img)
            } else if let doc = d.vector {
                vectors[d.src] = doc
                needsStyle = true
            } else {
                failed.append(d.url)
            }
        }
        return failed
    }

    // MARK: - Geometry

    /// How big the viewport is, in CSS pixels.
    public var ViewportSize: draw.Size { return size }

    /// Shows the page in a dark or a light color scheme, which is what
    /// `@media (prefers-color-scheme: dark)` asks: the host sets it from
    /// the system's appearance, and again when that changes.
    public func SetColorScheme(dark: bool) {
        if resolver.Dark == dark { return }
        resolver.Dark = dark
        needsStyle = true
        needsRepaint = true
    }

    /// Whether the user asked for less motion, as the system says:
    /// what `@media (prefers-reduced-motion)` asks.
    public func SetReducedMotion(reduce: bool) {
        if cascade.PrefersReducedMotion == reduce { return }
        cascade.PrefersReducedMotion = reduce
        needsStyle = true
        needsRepaint = true
    }

    /// Whether the page is shown in a dark color scheme.
    public var IsDark: bool { return resolver.Dark }

    /// Resizes the viewport.
    public func SetViewportSize(size: draw.Size) {
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

    public func SetScrollOffset(offset: draw.Point) {
        // Laid out first: before the first layout the page has no height,
        // and the offset would be clamped to nothing.
        update()
        let before = scroll
        scroll = offset
        clampScroll()
        root?.ViewportScrollX = scroll.X
        root?.ViewportScrollY = scroll.Y
        needsRepaint = true
        if scroll.X != before.X || scroll.Y != before.Y { pageScrolled() }
    }

    /// The size of the whole page.
    public func ContentSize() -> draw.Size {
        update()
        return draw.Size(contentWidth, contentHeight)
    }

    public func NeedsRepaint() -> bool {
        takeJournal()
        if !frames.isEmpty && framesNeedPaint { needsPaint = true }
        return needsRepaint || needsStyle || needsLayout || needsPaint
    }

    /// Reads the journal: what the host or the page itself changed in the
    /// tree since the last frame. Changes nothing depends on -- an
    /// attribute no rule and no stage reads, a class no rule names --
    /// are dropped, and cost no frame.
    /// A field's value attribute set by the program is its value: what the
    /// user typed before gives way to it, as a controlled input's does.
    /// Reads the journal without taking it.
    func syncValues() {
        guard let doc = Document, doc.HasMutations, !values.isEmpty else { return }
        for r in doc.PendingRecords where r.Kind == .attributes && r.AttributeName == "value" {
            if let typed = values[r.Target.Id], typed != (r.Target.GetAttribute("value") ?? "") {
                values.removeValue(forKey: r.Target.Id)
                if focused?.Id == r.Target.Id {
                    caret = valueOf(r.Target).utf8.count
                    fieldAnchor = caret
                }
            }
        }
    }

    func takeJournal() {
        guard let doc = Document, doc.HasMutations else { return }
        syncValues()
        let records = doc.TakeRecords()
        if needsStyle { return }
        let roots = resolver.Invalidate(records, reads: { name in layout.ReadsAttribute(name) || paint.ReadsAttribute(name) })
        if !roots.isEmpty { needsStyle = true }
    }

    /// Whether the page has something moving on its own -- a blinking
    /// caret -- and wants frames while it does. A host that gets true
    /// calls `Advance` with each frame's time and keeps requesting frames.
    public func NeedsAnimation() -> bool {
        if animator.Active || !animator.events.isEmpty { return true }
        if bubbleNode != nil { return true }
        if scrollAnimation != nil || pendingSnap != nil { return true }
        if mediaPlaying || overscroll != 0 || oldPicture != nil || !animatedImages.isEmpty { return true }
        // Only what someone is listening for is worth a frame.
        if let doc = Document, doc.HasEventListeners {
            if !pendingImageEvents.isEmpty { return true }
            if layoutRan && !doc.NodesListening("layout").isEmpty { return true }
        }
        for (_, f) in frames where f.page.NeedsAnimation() { return true }
        if let f = focused { return dom.IsTextControl(f) }
        return false
    }

    /// Moves the page's own animation to a time in seconds: CSS
    /// transitions and animations, and the caret, which blinks at a
    /// second per cycle. Answers whether a repaint is needed.
    public func Advance(time: float64) -> bool {
        var repaint = false
        // The validation bubble goes after five seconds.
        if bubbleNode != nil {
            if bubbleSince < 0 { bubbleSince = time }
            if time - bubbleSince > 5 {
                hideValidationBubble()
                repaint = true
            }
        }
        let running = animator.Active
        _ = animator.advance(time)
        if running {
            // Each frame of a transition or animation is a restyle.
            needsStyle = true
            needsRepaint = true
            repaint = true
        }
        dispatchAnimationEvents()
        dispatchImageEvents()
        dispatchLayoutEvents()
        if easeOverscroll(time) { repaint = true }
        if advanceTransition(time: time) { repaint = true }
        if advanceAnimatedImages(time) { repaint = true }
        if advanceMedia(time: time) { repaint = true }
        if advanceScroll(time) { repaint = true }
        for (_, frame) in frames where frame.page.NeedsAnimation() {
            if frame.page.Advance(time: time) {
                needsPaint = true
                repaint = true
            }
        }
        guard let f = focused, dom.IsTextControl(f) else { return repaint }
        if caretPhase < 0 { caretPhase = time }
        let phase = time - caretPhase
        let cycles = phase - float64(int64(phase))
        let visible = cycles < 0.5
        if visible != caretVisible {
            caretVisible = visible
            needsPaint = true
            return true
        }
        return repaint
    }

    /// A layout event to each element whose box has changed since it was
    /// last told, the first layout included: what ResizeObserver tells.
    func dispatchLayoutEvents() {
        if !layoutRan { return }
        layoutRan = false
        guard let doc = Document else { return }
        for id in doc.NodesListening("layout") {
            guard let box = builder.byNode[id], let node = box.Node else { continue }
            let p = layout.PagePosition(box)
            let now = draw.Rect(p.x, p.y, box.Width, box.Height)
            if let old = layoutTold[id], old.X == now.X, old.Y == now.Y, old.Width == now.Width, old.Height == now.Height { continue }
            layoutTold[id] = now
            _ = doc.Dispatch(dom.LayoutEvent("layout", X: now.X, Y: now.Y, Width: now.Width, Height: now.Height), to: node)
        }
    }

    /// An <img>'s load or error, once its bytes have come. Those still
    /// deferred to the host wait for it.
    func dispatchImageEvents() {
        if pendingImageEvents.isEmpty { return }
        var waiting: [html.Node] = []
        for n in pendingImageEvents {
            guard let src = n.GetAttribute("src") else { continue }
            if images[src] != nil || vectors[src] != nil {
                _ = dispatch(dom.Event("load", bubbles: false), to: n)
            } else if pendingImages.contains(src) {
                waiting.append(n)
            } else {
                _ = dispatch(dom.Event("error", bubbles: false), to: n)
            }
        }
        pendingImageEvents = waiting
    }

    /// Hands the transition and animation events of the last frames to
    /// their elements.
    func dispatchAnimationEvents() {
        let events = animator.takeEvents()
        guard let doc = Document else { return }
        for e in events { _ = doc.Dispatch(e.event, to: e.node) }
    }

    /// The pointer shape for where the pointer is.
    public func DesiredCursor() -> Cursor {
        if let p = cursorPoint {
            update()
            cursor = cursorFor(hitAt(p))
        }
        return cursor
    }

    // MARK: - Callbacks

    /// Called with the resolved URL when the user follows a link.
    public func OnNavigate(handler: (string) -> Void) { onNavigate = handler }
    /// Called when a form is submitted: by its button, or Enter in a field.
    public func OnSubmit(handler: (dom.Submission) -> Void) { onSubmit = handler }
    /// Called when a button outside a form is pressed, with its name and value.
    public func OnAction(handler: (string, string) -> Void) { onAction = handler }
    public func OnTitleChanged(handler: (string) -> Void) { onTitle = handler }
    /// Called with a link's URL as the pointer moves onto it, and nil off it.
    public func OnHoverLink(handler: (string?) -> Void) { onHoverLink = handler }
    /// Asked whether a resolved URL has been visited, for `:visited`.
    /// Call `VisitedChanged()` when an answer changes.
    public func IsVisited(handler: (string) -> bool) { isVisited = handler; needsStyle = true }
    /// The host's visited set changed: links are matched again.
    public func VisitedChanged() {
        if resolver.UsesVisited { needsStyle = true }
    }

    // MARK: - The pipeline

    /// Brings the page up to date: boxes, layout and the display list,
    /// whichever are stale.
    func update() {
        takeJournal()
        // Layout is coming: what the scroll keeps its place by, where it is.
        var anchor: (node: int64, y: float32)? = nil
        if needsStyle || needsLayout { anchor = scrollAnchor() }
        updateStages()
        keepScrollAnchor(anchor)
    }

    func updateStages() {
        root?.ViewportScrollX = scroll.X
        root?.ViewportScrollY = scroll.Y
        if needsStyle {
            if let doc = Document { syncMedia(doc.Tree) }
            builder.Images = images
            builder.Vectors = vectors
            builder.Values = values
            builder.MediaSizes = [:]
            for (id, m) in media where m.ready && m.player.VideoWidth > 0 {
                builder.MediaSizes[id] = draw.Size(float32(m.player.VideoWidth), float32(m.player.VideoHeight))
            }
            context.Reset()
            context.Hovered = hovered
            context.Focused = focused
            context.FocusVisible = focusVisible
            context.Target = target
            context.Active = pressed
            if let v = isVisited, resolver.UsesVisited {
                context.Visited = { node in
                    if let href = node.GetAttribute("href") { return v(self.Resolve(href)) }
                    return false
                }
            } else {
                context.Visited = nil
            }
            animator.beginPass()
            resolver.BeginStylePass()
            if let doc = Document {
                // Where things were: a view() timeline is styled from it.
                previousBoxes = builder.byNode
                root = builder.Build(doc.Tree)
            } else {
                root = nil
            }
            animator.endPass()
            needsStyle = false
            needsLayout = true
        }
        if needsLayout {
            if let r = root {
                let run = layout.Layout(viewportWidth: size.Width, viewportHeight: size.Height)
                run.Images = images
                run.Run(r)
                r.ViewportScrollX = scroll.X
                r.ViewportScrollY = scroll.Y
                laidOut = run
                restoreElementScrolls()
                contentHeight = r.Y + r.Height + r.Margin.Bottom
                contentWidth = r.X + r.Width + r.Margin.Right
                if r.ContentWidth + r.X + r.ContentX > contentWidth { contentWidth = r.ContentWidth + r.X + r.ContentX }
            } else {
                contentHeight = 0
                contentWidth = 0
            }
            clampScroll()
            needsLayout = false
            layoutRan = true
            // A timeline's length is the page's: known now, it is styled again.
            if animator.HasTimelines && (timelineSizedFor.X != contentWidth || timelineSizedFor.Y != contentHeight) {
                timelineSizedFor = draw.Point(contentWidth, contentHeight)
                needsStyle = true
                updateStages()
                return
            }
            needsPaint = true
            // Container queries ask about sizes only layout knows: once
            // laid out, measure the containers, and while that changes
            // which rules hold, style and lay out again (a few times at
            // most, so that a query that flips its own answer settles).
            if resolver.UsesContainers && containerPasses < 3 && measureContainers() {
                containerPasses += 1
                needsStyle = true
                update()
                return
            }
            containerPasses = 0
        }
        if needsPaint {
            // A list item's marker image is laid out: one that has just
            // loaded builds the boxes again.
            if let r = root, loadStyleImages(r) {
                needsStyle = true
                update()
                return
            }
            if let r = root {
                var state = paint.State()
                state.Focused = focused?.Id ?? 0
                state.Caret = caret
                state.CaretVisible = caretVisible
                state.Composing = Composing
                if let r = fieldRange() {
                    state.FieldSelectionStart = r.start
                    state.FieldSelectionEnd = r.end
                }
                state.Images = images
                state.MediaFrames = mediaFrames
                state.ListTops = listTop
                if let k = picker {
                    state.PanelFrame = k.frame
                    state.PanelCells = k.cells
                }
                if let d = dragging, d.started, let b = builder.byNode[d.source.Id] {
                    state.DragImage = paint.DragImage(box: b, dx: d.at.X - d.start.X, dy: d.at.Y - d.start.Y)
                }
                if !highlights.isEmpty {
                    state.Highlights = paintHighlights()
                    state.TextOrder = builder.textOrder
                }
                for (id, m) in media {
                    state.MediaBars[id] = paint.MediaProgress(time: m.player.CurrentTime, duration: m.player.Duration, paused: m.player.Paused)
                }
                // Looked up directly: BoundsOf would update again.
                if let b = bubbleNode, let box = builder.byNode[b.Id] {
                    let p = layout.PagePosition(box)
                    state.Bubble = (rect: draw.Rect(p.x, p.y, box.Width, box.Height), text: bubbleText)
                }
                state.Vectors = vectors
                if !frames.isEmpty || builder.HasFrames { state.Subpages = syncFrames() }
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

    /// Hands the size containers' content boxes to the cascade; answers
    /// whether any changed.
    func measureContainers() -> bool {
        var sizes: [int64: cascade.ContainerSize] = [:]
        for c in resolver.SizeContainers {
            guard let box = builder.byNode[c.id] else { continue }
            let w = box.Width - box.Border.Horizontal - box.Padding.Horizontal
            let h = box.Height - box.Border.Vertical - box.Padding.Vertical
            sizes[c.id] = cascade.ContainerSize(Width: w > 0 ? w : 0, Height: h > 0 ? h : 0, HasHeight: c.style.ContainerType == "size")
        }
        return resolver.SetContainerSizes(sizes)
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

    /// DrawOver paints only what the page paints over an element marked
    /// data-viewport (what comes after it in paint order), clipped to
    /// `clip` in device pixels: after a program has drawn into that
    /// element's box, this puts the page's overlays back on top. Answers
    /// false when the element isn't in the display list.
    @discardableResult
    public func DrawOver(node: html.Node, into pixels: inout [uint8], width: int32, height: int32, scale: float32,
                         clip: draw.IRect, at origin: draw.Point = draw.Point.zero) -> bool {
        update()
        let list = displayList
        var at = -1
        for i in 0..<list.count where list[i].Kind == .mark && list[i].Node == node.Id {
            at = i
            break
        }
        if at < 0 { return false }
        var rest: [paint.PaintItem] = []
        for i in (at + 1)..<list.count { rest.append(list[i]) }
        if rest.isEmpty { return true }
        let viewRect = draw.Rect(origin.X, origin.Y, size.Width, size.Height).Snapped(scale: scale)
        let sx = scroll.X
        let sy = scroll.Y
        draw.WithCanvas(&pixels, width: width, height: height) { c in
            var canvas = c
            canvas.ClipTo(viewRect)
            canvas.ClipTo(clip)
            paint.Rasterize(rest, on: canvas, scale: scale, originX: float32(viewRect.X), originY: float32(viewRect.Y) - overscroll * scale, scrollX: sx, scrollY: sy)
        }
        return true
    }

    /// Paints the page into premultiplied RGBA pixels, `width` by `height`
    /// device pixels, with its viewport's top-left corner at `origin` (in
    /// CSS pixels) and `scale` device pixels to the CSS pixel.
    public func Draw(into pixels: inout [uint8], width: int32, height: int32, scale: float32, at origin: draw.Point = draw.Point.zero) {
        update()
        let viewRect = draw.Rect(origin.X, origin.Y, size.Width, size.Height).Snapped(scale: scale)
        let list = displayList
        let sx = scroll.X
        let sy = scroll.Y
        let stretch = overscroll
        drawnScale = scale
        let fade = oldPicture != nil
        let bg = Configuration.BackgroundColor
        let showBar = contentHeight > size.Height && !printing
        let barHeight = size.Height * size.Height / (contentHeight > 0 ? contentHeight : 1)
        let barY = size.Height > barHeight ? (size.Height - barHeight) * (sy / (contentHeight - size.Height)) : 0
        let viewWidth = size.Width
        draw.WithCanvas(&pixels, width: width, height: height) { c in
            var canvas = c
            canvas.ClipTo(viewRect)
            if bg.A > 0 { canvas.Fill(viewRect, bg) }
            paint.Rasterize(list, on: canvas, scale: scale, originX: float32(viewRect.X), originY: float32(viewRect.Y) - stretch * scale, scrollX: sx, scrollY: sy)
            if fade { self.drawTransition(on: canvas, view: viewRect, scale: scale) }
            if showBar {
                let track = draw.Rect(origin.X + viewWidth - 10, origin.Y + barY + 2, 6, barHeight - 4).Snapped(scale: scale)
                canvas.FillRounded(track, radii: draw.Radii(all: 3 * scale), draw.Color(0, 0, 0, 90))
            }
        }
        needsRepaint = false
    }

    // MARK: - Finding things

    /// The element under a point in the viewport, or nil.
    public func ElementAt(p: draw.Point) -> html.Node? {
        update()
        return hitAt(p)?.Node
    }

    func hitAt(p: draw.Point) -> layout.Hit? {
        guard let r = root else { return nil }
        // An open picker paints over everything, so it is asked first.
        for id in context.PickerOpen {
            guard let b = builder.byNode[id] else { continue }
            let at = layout.PagePosition(b)
            for picker in b.Positioned {
                if let h = layout.HitTest(picker, p.X + scroll.X, p.Y + scroll.Y, originX: at.x - b.ScrollX, originY: at.y - b.ScrollY) { return h }
            }
        }
        return layout.HitTest(r, p.X + scroll.X, p.Y + scroll.Y, originX: 0, originY: 0)
    }

    /// The layout box of an element, once laid out.
    public func BoxFor(node: html.Node) -> layout.Box? {
        update()
        return builder.byNode[node.Id]
    }

    /// Where an element's border box is in the page's view, scrolled as
    /// it is shown; nil before it is laid out, or when it isn't.
    public func BoundsOf(node: html.Node) -> draw.Rect? {
        guard let box = BoxFor(node) else { return nil }
        let r = layout.VisualBounds(box)
        return draw.Rect(r.X - scroll.X, r.Y - scroll.Y, r.Width, r.Height)
    }

    /// The root of the layout tree.
    public var RootBox: layout.Box? {
        update()
        return root
    }

    public func QuerySelector(sel: string) -> html.Node? {
        guard let doc = Document else { return nil }
        return selector.QuerySelector(sel, in: doc.Root)
    }

    public func QuerySelectorAll(sel: string) -> [html.Node] {
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

    func collectSelectedText(box: layout.Box, range: (start: dom.TextPosition, end: dom.TextPosition), out: inout string, lineBroken: inout bool) {
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
            // Boxes taken out of the lines -- absolutely positioned and
            // fixed -- are children still, and have text of their own.
            for child in box.Children where child.Style.Position == .absolute || child.Style.Position == .fixed {
                collectSelectedText(child, range, &out, &lineBroken)
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

    func findTextBoxes(box: layout.Box, first: inout layout.Box?, last: inout layout.Box?) {
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
    public func Focus(node: html.Node?) {
        if focused?.Id == node?.Id { return }
        let before = focused
        focused = node
        focusVisible = keyboardInput
        // blur to what had focus, focus to what has it: neither bubbles.
        if let b = before { _ = dispatch(dom.FocusEvent("blur"), to: b) }
        if let n = node { _ = dispatch(dom.FocusEvent("focus"), to: n) }
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
        context.FocusVisible = focusVisible
        context.Target = target
        context.Active = pressed
        if resolver.StateMatchesChanged(context) {
            needsStyle = true
        }
    }

    /// Scrolls so that an element is at the top of the viewport.
    public func ScrollTo(node: html.Node) {
        update()
        guard let b = builder.byNode[node.Id] else { return }
        let pos = layout.PagePosition(b)
        // scroll-margin-top keeps room above it, as a sticky header needs.
        let margin = b.Style.ScrollMargin[0].Resolve(size.Height) ?? 0
        let pad = root?.Style.ScrollPadding[0].Resolve(size.Height) ?? 0
        scrollPage(to: draw.Point(scroll.X, pos.y - margin - pad), smooth: smoothScrolling)
    }

    /// Scrolls just enough to show an element.
    public func ScrollIntoViewIfNeeded(node: html.Node) {
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

    /// The text a form control holds now.
    public func ValueOf(node: html.Node) -> string {
        syncValues()
        return valueOf(node)
    }

    func valueOf(node: html.Node) -> string {
        if let v = values[node.Id] { return v }
        if node.TagName == "textarea" { return node.InnerText() }
        let raw = node.GetAttribute("value") ?? ""
        if node.TagName == "input" {
            let type = dom.InputType(node)
            if dom.IsDateTimeType(type) || type == "color" { return dom.SanitizedValue(type, raw) }
            if type == "file" { return "" }
        }
        return raw
    }

    /// Sets a form control's value as the user would: input and change
    /// fire at it. What a host's picker answers with.
    public func SetControlValue(node: html.Node, value: string) {
        var v = value
        if node.TagName == "input" {
            let type = dom.InputType(node)
            if dom.IsDateTimeType(type) || type == "color" { v = dom.SanitizedValue(type, value) }
        }
        setValue(node, v)
        _ = dispatch(dom.Event("change"), to: node)
        needsStyle = true
    }

    /// The files a file input holds, as its picker chose them: their
    /// names show, and change fires.
    public func SetFiles(node: html.Node, paths: [string]) {
        files[node.Id] = paths
        let names = paths.map { p -> string in
            let parts = p.split(separator: "/")
            return parts.isEmpty ? p : string(parts[parts.count - 1])
        }
        values[node.Id] = names.count > 1 ? "\(names.count) files" : (names.first ?? "")
        userEdited.insert(node.Id)
        needsStyle = true
        _ = dispatch(dom.Event("input"), to: node)
        _ = dispatch(dom.Event("change"), to: node)
    }

    /// The paths a file input holds.
    public func FilesOf(node: html.Node) -> [string] { return files[node.Id] ?? [] }

    /// Called when a color well is clicked, with the element and its
    /// color; the host shows a picker and answers with SetControlValue.
    public func OnPickColor(handler: (html.Node, string) -> Void) { onPickColor = handler }
    /// Called when a file input's button is clicked, with the element,
    /// whether it takes several and its accept; answer with SetFiles.
    public func OnPickFiles(handler: (html.Node, bool, string) -> Void) { onPickFiles = handler }
    /// Called when a date or time field is clicked, with the element, its
    /// type and its value; answer with SetControlValue.
    public func OnPickDate(handler: (html.Node, string, string) -> Void) { onPickDate = handler }

    func setValue(node: html.Node, value: string) {
        values[node.Id] = value
        userEdited.insert(node.Id)
        showCaret()
        needsStyle = true
        // The user changed the control: its listeners hear of it.
        _ = Document?.Dispatch(dom.InputEvent("input", Value: value), to: node)
    }

    /// Dispatches an event to a node's element -- a text node's parent --
    /// and answers whether the default action should be taken.
    func dispatch(event: dom.Event, to node: html.Node?) -> bool {
        guard let doc = Document, doc.HasEventListeners else { return true }
        var cur = node
        while let n = cur, n.Kind != html.NodeKind.element { cur = n.Parent }
        guard let target = cur else { return true }
        return doc.Dispatch(event, to: target)
    }

    /// The selected bytes of the focused text control, if any.
    func fieldRange() -> (start: int, end: int)? {
        guard let f = focused, dom.IsTextControl(f), fieldAnchor != caret else { return nil }
        return fieldAnchor < caret ? (start: fieldAnchor, end: caret) : (start: caret, end: fieldAnchor)
    }

    /// Puts the caret somewhere, extending the field's selection from
    /// its anchor or collapsing it there.
    func moveCaret(to: int, extend: bool) {
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

/// The <style> elements and <link rel=stylesheet> elements under a
/// node, in document order; not those inside <template>.
func collectSheets(node: html.Node, out: inout [html.Node]) {
    for c in node.Children where c.Kind == html.NodeKind.element {
        if c.TagName == "template" { continue }
        if c.TagName == "style" {
            out.append(c)
        } else if c.TagName == "link" {
            let rel = " " + lower(c.GetAttribute("rel") ?? "") + " "
            if rel.contains(" stylesheet ") && !rel.contains(" alternate ") && c.GetAttribute("href") != nil { out.append(c) }
        }
        collectSheets(c, &out)
    }
}

/// The URL an @import names: its first string or url().
func importURL(params: string) -> string {
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

/// An image to decode: as the page names it, resolved, and its bytes.
struct ImageJob {
    var src: string
    var url: string
    var bytes: [uint8]
}

/// An image decoded, or not, for the page.
struct DecodedImage {
    var src: string
    var url: string
    var image: draw.Image?
    /// Where the bytes were an SVG file instead.
    var vector: svg.Document? = nil
}

/// Decodes a job's bytes. Isolated to no actor: it runs where its task
/// prefers, which LoadImages makes the thread pool.
func decodeOffMain(job: ImageJob) async -> DecodedImage {
    if let doc = svg.ParseDocument(job.bytes) {
        return DecodedImage(src: job.src, url: job.url, image: nil, vector: doc)
    }
    return DecodedImage(src: job.src, url: job.url, image: decodeImage(job.bytes))
}

func decodeImage(bytes: [uint8]) -> draw.Image? {
    guard let decoded = format.Decode(bytes) else { return nil }
    return drawable(decoded)
}

func drawable(img: image.RGBA) -> draw.Image {
    return draw.Image(width: int32(img.Width), height: int32(img.Height), pixels: img.Pixels)
}

extension Page {
    /// Loads the images laid-out boxes' styles name and the page hasn't
    /// tried yet: a background, mask, border or list image in an inline
    /// style, or one a .vsx component's style gives after the page
    /// loaded. Answers whether a list image loaded, which layout needs.
    func loadStyleImages(box: layout.Box) -> bool {
        var wanted: [string] = []
        var markers: [string] = []
        func visit(b: layout.Box) {
            let s = b.Style
            if let bg = s.BackgroundImage, !bg.URL.isEmpty { wanted.append(bg.URL) }
            if !s.MaskURL.isEmpty { wanted.append(s.MaskURL) }
            if !s.BorderImageURL.isEmpty { wanted.append(s.BorderImageURL) }
            // A float's shape is laid out, so its image is a marker's kind.
            if !s.ShapeOutsideURL.isEmpty && b.Kind != .text { wanted.append(s.ShapeOutsideURL); markers.append(s.ShapeOutsideURL) }
            if !s.ListStyleImage.isEmpty && s.Display == .listItem { wanted.append(s.ListStyleImage); markers.append(s.ListStyleImage) }
            for c in b.Children { visit(c) }
            for p in b.Positioned where p.Parent?.Id != b.Id { visit(p) }
        }
        visit(box)
        var relayout = false
        for src in wanted where triedImages[src] == nil && images[src] == nil && vectors[src] == nil {
            triedImages[src] = true
            loadImage(src)
            if markers.contains(src) && (images[src] != nil || vectors[src] != nil) { relayout = true }
        }
        return relayout
    }

    /// Loads an image: a data: URL here and now (an SVG one as a
    /// drawing), else through the fetcher, or later where images defer.
    func loadImage(src: string) {
        if src.hasPrefix("data:") {
            guard let bytes = format.DataURLBytes(src) else { return }
            if let doc = svg.ParseDocument(bytes) {
                vectors[src] = doc
            } else if let decoded = format.Decode(bytes) {
                images[src] = drawable(decoded)
                if let moving = format.DecodeAnimated(bytes) { animatedImages[src] = moving }
            }
        } else if Configuration.DefersImages {
            pendingImages.append(src)
        } else if let bytes = Configuration.Fetcher.Fetch(Resolve(src)) {
            if let doc = svg.ParseDocument(bytes) {
                vectors[src] = doc
            } else if let decoded = decodeImage(bytes) {
                images[src] = decoded
                if let moving = format.DecodeAnimated(bytes) { animatedImages[src] = moving }
            }
        }
    }
}

extension Page {
    /// What a control's validation would say, as a browser's bubble
    /// does: "Please fill out this field.", and the like; empty where it
    /// meets its constraints.
    public func ValidationMessage(node: html.Node) -> string {
        return selector.ValidationMessage(node, context)
    }

    func showValidationBubble(node: html.Node) {
        bubbleNode = node
        bubbleText = selector.ValidationMessage(node, context)
        bubbleSince = -1
        needsPaint = true
        needsRepaint = true
    }

    func hideValidationBubble() {
        if bubbleNode == nil { return }
        bubbleNode = nil
        bubbleText = ""
        needsPaint = true
        needsRepaint = true
    }
}
