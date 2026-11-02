package paint

import (
    "image/draw"
    "math"
    "text/bidi"
    "text/font"
    "web/cascade"
    "web/css"
    "web/dom"
    "web/html"
    "web/layout"
    "web/svg"
)

/// The size a background or mask tile takes in its area: background-
/// size's (and mask-size's) cover, contain, lengths or auto, for an
/// image w × h (an area-sized gradient where it has none of its own).
func layerSize(size: cascade.BackgroundSize, area: draw.Rect, w: float32, h: float32, intrinsic: bool) -> (float32, float32) {
    var tw = w
    var th = h
    switch size {
    case .cover:
        let k = maxf(area.Width / tw, area.Height / th)
        tw *= k
        th *= k
    case .contain:
        let k = minf(area.Width / tw, area.Height / th)
        tw *= k
        th *= k
    case .length(let lw, let lh):
        let rw = lw.Resolve(area.Width)
        let rh = lh.Resolve(area.Height)
        if let a = rw, let b = rh { tw = a; th = b }
        else if let a = rw { th = intrinsic ? th * a / tw : area.Height; tw = a }
        else if let b = rh { tw = intrinsic ? tw * b / th : area.Width; th = b }
    case .auto:
        break
    }
    return (tw, th)
}

/// A positioned box waiting its turn in a stacking context.
struct Stacked {
    var box: layout.Box
    var x: float32
    var y: float32
}

public enum PaintKind: Equatable {
    case fill
    case border
    case text
    case image
    case gradient
    case clip
    case unclip
    /// An <svg>'s shapes, fitted to Rect.
    case vector
    /// What follows, to the matching unlayer, is painted apart, then
    /// run through Filters and put back through Transform: filter and
    /// transform. Rect is the box they are on.
    /// After its filters, a layer is cut to Shape (clip-path), kept as
    /// much as Gradient or MaskImage is opaque over MaskRect
    /// (mask-image), and mixed onto what is under it by Blend.
    case layer
    case unlayer
    /// Image (or Gradient, sized to Rect) cut by Slice and drawn round
    /// Rect, Widths in from its sides: border-image.
    case borderImage
    /// What is painted so far under Rect, run through Filters and kept
    /// inside Rect's corners Radii: backdrop-filter.
    case backdrop
    /// Where an element marked data-viewport is painted: what comes after
    /// is drawn over it. Node is the element's id. Paints nothing.
    case mark
    /// What follows, to the matching untranslate, is moved by X and Y:
    /// a nested document's display list, in its own coordinates.
    case translate
    case untranslate
    /// What follows, to the matching unfix, is a box fixed to the
    /// viewport: drawn where it is whatever the page's scroll.
    case fixed
    case unfix
    /// Outline, in CSS pixels, filled with Color: a rounded box's dashed,
    /// dotted or double side.
    case path
}

/// One cell of an open panel, on the page: a select's row, a calendar's day.
public struct PanelCell {
    public var rect: draw.Rect
    public var text: string
    public var fill: draw.Color?
    public var color: draw.Color
    public var centered: bool

    public init(rect: draw.Rect, text: string, fill: draw.Color?, color: draw.Color, centered: bool) {
        self.rect = rect
        self.text = text
        self.fill = fill
        self.color = color
        self.centered = centered
    }
}

/// What a drag shows: its source, faint, moved with the pointer.
public struct DragImage {
    public var box: layout.Box
    public var dx: float32
    public var dy: float32

    public init(box: layout.Box, dx: float32, dy: float32) {
        self.box = box
        self.dx = dx
        self.dy = dy
    }
}

/// Named ranges of text and how their rules style them.
public struct Highlight {
    public var ranges: [(start: dom.TextPosition, end: dom.TextPosition)]
    public var background: draw.Color
    public var color: draw.Color
    /// The element's own color: the rule's only shows where it differs.
    public var inherited: draw.Color

    public init(ranges: [(start: dom.TextPosition, end: dom.TextPosition)], background: draw.Color, color: draw.Color, inherited: draw.Color) {
        self.ranges = ranges
        self.background = background
        self.color = color
        self.inherited = inherited
    }
}

/// Whether text holds right-to-left letters: its first character shows at
/// its right.
public func RunsRightToLeft(text: string) -> bool {
    var cps: [uint32] = []
    for u in text.unicodeScalars { cps.append(u.value) }
    return bidi.HasRightToLeft(cps)
}

/// Where a line of a text control starts: at the left of its content box,
/// or the right where the control runs right to left.
public func FieldLineStart(line: string, left: float32, right: float32, rtl: bool, face: font.Face) -> float32 {
    return rtl ? right - 1 - face.Measure(line) : left + 1
}

/// Where an offset in a line of a text control shows: measured from the
/// line's right where its text runs right to left.
public func FieldX(bytes: [uint8], from: int, to: int, at: int, left: float32, right: float32, rtl: bool, face: font.Face) -> float32 {
    let line = stringOf(bytes, from, to)
    let start = FieldLineStart(line, left: left, right: right, rtl: rtl, face: face)
    let along = face.Measure(stringOf(bytes, from, at))
    return RunsRightToLeft(line) ? start + face.Measure(line) - along : start + along
}

/// Where a media element has got to, for its controls.
public struct MediaProgress {
    public var time: float64
    public var duration: float64
    public var paused: bool

    public init(time: float64, duration: float64, paused: bool) {
        self.time = time
        self.duration = duration
        self.paused = paused
    }
}

/// Where a media element's controls are: all of an <audio>, the foot of a
/// <video>. x and y are the box's on the page.
public func MediaBar(box: layout.Box, x: float32, y: float32) -> draw.Rect {
    let inner = draw.Rect(x + box.ContentX, y + box.ContentY, box.InnerWidth, box.InnerHeight)
    if box.Replaced == .audio { return inner }
    let h = math.Min(inner.Height / 2, 40)
    return draw.Rect(inner.X, inner.Bottom - h, inner.Width, h)
}

/// The part of a bar that seeks.
public func MediaTrack(bar: draw.Rect) -> draw.Rect {
    let x = bar.X + bar.Height + 44
    return draw.Rect(x, bar.Y, bar.Right - bar.Height / 2 - x, bar.Height)
}

/// Seconds as a clock reads them: 0:07, 12:34.
func clockOf(seconds: float64) -> string {
    let t = int(seconds)
    let s = t % 60
    return "\(t / 60):\(s < 10 ? "0" : "")\(s)"
}

/// A rectangle's outline by its corners' radii and shapes, from the top
/// left round clockwise.
func cornerOutline(r: draw.Rect, radii: draw.Radii, shapes: [string]) -> [draw.Point] {
    func shapeOf(i: int) -> string {
        if shapes.isEmpty { return "1" }
        // As border-radius takes one to four.
        switch shapes.count {
        case 1: return shapes[0]
        case 2: return shapes[i % 2]
        case 3: return i == 3 ? shapes[1] : shapes[i]
        default: return shapes[i]
        }
    }
    var out: [draw.Point] = []
    // Each corner: its center, which way its two ends lie, and its radius.
    func corner(i: int, cx: float32, cy: float32, sx: float32, sy: float32, rad: float32, fromSide: bool) {
        if rad <= 0 {
            out.append(draw.Point(cx, cy))
            return
        }
        let word = shapeOf(i)
        if word == "square" {
            out.append(draw.Point(cx + sx * rad, cy + sy * rad))
            return
        }
        if word == "notch" {
            out.append(fromSide ? draw.Point(cx + sx * rad, cy) : draw.Point(cx, cy + sy * rad))
            out.append(draw.Point(cx, cy))
            out.append(fromSide ? draw.Point(cx, cy + sy * rad) : draw.Point(cx + sx * rad, cy))
            return
        }
        let k = float32(word) ?? 1
        let exponent = math.Pow(2, k)
        var n = 0
        while n <= 24 {
            let t = float32(n) / 24 * 1.5707964
            let angle = fromSide ? t : 1.5707964 - t
            let u = math.Pow(math.Abs(math.Cos(angle)), 2 / exponent)
            let v = math.Pow(math.Abs(math.Sin(angle)), 2 / exponent)
            out.append(draw.Point(cx + sx * rad * u, cy + sy * rad * v))
            n += 1
        }
    }
    let tl = radii.TopLeft
    let tr = radii.TopRight
    let br = radii.BottomRight
    let bl = radii.BottomLeft
    corner(0, cx: r.X + tl, cy: r.Y + tl, sx: -1, sy: -1, rad: tl, fromSide: true)
    corner(1, cx: r.Right - tr, cy: r.Y + tr, sx: 1, sy: -1, rad: tr, fromSide: false)
    corner(2, cx: r.Right - br, cy: r.Bottom - br, sx: 1, sy: 1, rad: br, fromSide: true)
    corner(3, cx: r.X + bl, cy: r.Bottom - bl, sx: -1, sy: 1, rad: bl, fromSide: false)
    return out
}

func pathOf(points: [draw.Point]) -> draw.Path {
    var p = draw.Path()
    var i = 0
    while i < points.count {
        if i == 0 { p.MoveTo(points[i].X, points[i].Y) } else { p.LineTo(points[i].X, points[i].Y) }
        i += 1
    }
    p.Close()
    return p
}

/// Whether a character stands upright in vertical text, as CJK does; a
/// bracket among them turns with the line, to open along it.
func standsUpright(c: uint32) -> bool {
    if (c >= 0x3008 && c <= 0x3011) || (c >= 0x3014 && c <= 0x301B) || c == 0xFF08 || c == 0xFF09 || c == 0xFF3B || c == 0xFF3D { return false }
    return (c >= 0x1100 && c <= 0x11FF) || (c >= 0x2E80 && c <= 0xA4CF) || (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF)
        || (c >= 0xFE30 && c <= 0xFE4F) || (c >= 0xFF00 && c <= 0xFFEF) || (c >= 0x1F300 && c <= 0x1FAFF) || (c >= 0x20000 && c <= 0x3FFFF)
}

/// A layer in a 3D context, waiting to be drawn in depth order.
struct Plane {
    var layer: draw.Layer
    var matrix: draw.Matrix4
    var depth: float32
    var hidden: bool
    var blend: draw.BlendMode
}

/// One thing to paint, in CSS pixels on the page: a filled rectangle, a
/// border, a run of text at a baseline, an image, or a change of clip.
public struct PaintItem {
    public var Kind: PaintKind
    public var Rect: draw.Rect
    public var Color: draw.Color
    public var Radii: draw.Radii
    /// A border's widths and its four colors.
    public var Widths: draw.Edges
    public var Colors: [draw.Color]
    /// Text: the pen's start and baseline, the run, and letter-spacing.
    public var X: float32
    public var Y: float32
    public var Run: font.Run
    public var LetterSpacing: float32
    public var Image: draw.Image?
    /// image-rendering: pixelated or crisp-edges.
    public var Pixelated: bool = false
    /// Text that stands upright in a line turned to run down the page:
    /// turned back about the middle of its TileWidth, TileHeight over its
    /// baseline.
    public var Upright: bool = false
    /// Text's outline: its width in CSS pixels and color; whether it goes
    /// under the fill.
    public var StrokeWidth: float32 = 0
    public var StrokeColor: draw.Color = draw.Color.transparent
    public var StrokeFirst: bool = false
    public var Opacity: float32
    /// An image's tile size and whether it repeats each way; the rect is
    /// the area it covers.
    public var TileWidth: float32
    public var TileHeight: float32
    public var RepeatX: bool
    public var RepeatY: bool
    public var Gradient: draw.LinearGradient?
    /// An <svg>'s shapes; Color is its current color, and Fill what its
    /// CSS fill resolved to (nil for the default, black).
    public var Vector: svg.Drawing?
    public var Fill: draw.Color?
    public var FillNone: bool
    /// A layer's or a backdrop's filters, lengths in CSS pixels.
    public var Filters: [draw.Filter] = []
    /// A layer's transform, in the page's CSS pixels.
    public var Transform: draw.Affine = draw.Affine.identity
    /// A layer's 3D matrix on the page, where it has one: whether it joins
    /// its parent's 3D context, sorted with it by depth, rather than being
    /// flattened into it; backface-visibility: hidden.
    public var Matrix: draw.Matrix4? = nil
    public var JoinsContext: bool = false
    public var BackfaceHidden: bool = false
    /// A layer's clip-path, mask and blend mode. Unbounded layers take
    /// all that shows, not just the box: what overflows it blends too.
    public var Shape: layout.ClipRegion? = nil
    public var MaskImage: draw.Image? = nil
    /// An SVG mask image, and its width in CSS pixels; whether the mask
    /// is read by luminance rather than alpha.
    public var MaskVector: svg.Drawing? = nil
    public var MaskVectorWidth: float32 = 0
    public var MaskLuminance: bool = false
    public var MaskRect: draw.Rect = draw.Rect.zero
    /// mask-clip's rectangle: nothing of the layer shows past it.
    public var MaskClip: draw.Rect? = nil
    public var Blend: draw.BlendMode = .normal
    public var Unbounded: bool = false
    /// A layer kept only where these items -- a box's text -- draw:
    /// background-clip: text.
    public var TextMask: [PaintItem] = []
    /// A background attached to the viewport (background-attachment:
    /// fixed): its Rect and tile origin are in the viewport's own
    /// coordinates, the scroll added when it is drawn.
    public var Pinned: bool = false
    /// A border image's slices (in its pixels, or a gradient's CSS
    /// pixels), whether its middle is drawn, and its repeats.
    public var Slice: draw.Edges = draw.Edges.zero
    public var SliceFill: bool = false
    public var SliceAcross: draw.SliceRepeat = .stretch
    public var SliceDown: draw.SliceRepeat = .stretch

    /// For a mark: the element's node id.
    public var Node: int64 = 0
    /// What a path item fills.
    public var Outline: draw.Path = draw.Path()

    init(kind: PaintKind) {
        Kind = kind
        Rect = draw.Rect.zero
        Color = draw.Color.transparent
        Radii = draw.Radii.zero
        Widths = draw.Edges.zero
        Colors = []
        X = 0
        Y = 0
        Run = font.Run()
        LetterSpacing = 0
        Image = nil
        Opacity = 1
        TileWidth = 0
        TileHeight = 0
        RepeatX = false
        RepeatY = false
        Gradient = nil
        Vector = nil
        Fill = nil
        FillNone = false
    }

    static func fill(r: draw.Rect, c: draw.Color, radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.fill)
        it.Rect = r
        it.Color = c
        it.Radii = radii
        return it
    }

    static func border(r: draw.Rect, widths: draw.Edges, colors: [draw.Color], radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.border)
        it.Rect = r
        it.Widths = widths
        it.Colors = colors
        it.Radii = radii
        return it
    }

    static func text(x: float32, baseline: float32, run: font.Run, c: draw.Color, letterSpacing: float32) -> PaintItem {
        var it = PaintItem(.text)
        it.X = x
        it.Y = baseline
        it.Run = run
        it.Color = c
        it.LetterSpacing = letterSpacing
        return it
    }

    static func image(r: draw.Rect, img: draw.Image, opacity: float32) -> PaintItem {
        var it = PaintItem(.image)
        it.Rect = r
        it.Image = img
        it.Opacity = opacity
        return it
    }

    static func gradient(r: draw.Rect, g: draw.LinearGradient, radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.gradient)
        it.Rect = r
        it.Gradient = g
        it.Radii = radii
        return it
    }

    static func tiles(area: draw.Rect, img: draw.Image, tileWidth: float32, tileHeight: float32,
                      originX: float32, originY: float32, repeatX: Bool, repeatY: Bool, opacity: float32, radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.image)
        it.Rect = area
        it.Radii = radii
        it.Image = img
        it.TileWidth = tileWidth
        it.TileHeight = tileHeight
        it.X = originX
        it.Y = originY
        it.RepeatX = repeatX
        it.RepeatY = repeatY
        it.Opacity = opacity
        return it
    }

    static func clip(r: draw.Rect) -> PaintItem {
        var it = PaintItem(.clip)
        it.Rect = r
        return it
    }

    static let unclip = PaintItem(.unclip)
}

enum PaintPhase: Equatable {
    case blockBackgrounds
    case floats
    case inlineContent
    /// The outlines of in-flow boxes, over everything else in their
    /// stacking context. A box painted whole draws its own.
    case outlines
}

/// Builds the list of what to paint from a laid-out box tree, in the
/// order CSS paints: block backgrounds and borders, then floats, then
/// inline content, with positioned boxes after their siblings.
/// What the painter needs from the page besides its boxes: focus, the
/// caret, selections and images.
public struct State {
    /// The focused element's node id, or 0.
    public var Focused: int64 = 0
    /// The caret's byte offset in the focused field, or -1.
    public var Caret: int = -1
    public var CaretVisible: bool = true
    /// What an input method is composing, shown at the caret, underlined.
    public var Composing: string = ""
    /// The focused field's selected bytes, or -1 for none.
    public var FieldSelectionStart: int = -1
    public var FieldSelectionEnd: int = -1
    /// The page's images by URL, for backgrounds; its SVG images.
    public var Images: [string: draw.Image] = [:]
    /// Each media element's newest frame and where it has got to.
    public var MediaFrames: [int64: draw.Image] = [:]
    public var MediaBars: [int64: MediaProgress] = [:]
    public var DragImage: DragImage? = nil
    /// Each list box's first row showing.
    public var ListTops: [int64: int] = [:]
    /// An open panel's frame and cells, over everything.
    public var PanelFrame: draw.Rect? = nil
    public var PanelCells: [PanelCell] = []
    public var Highlights: [Highlight] = []
    public var Vectors: [string: svg.Document] = [:]
    /// The selection, if any, and each text node's place in the document.
    public var SelectionStart: dom.TextPosition? = nil
    public var SelectionEnd: dom.TextPosition? = nil
    public var TextOrder: [int64: int] = [:]
    /// The nested documents of <iframe>s and the like, by element id.
    public var Subpages: [int64: Subpage] = [:]
    /// A validation bubble: the control's border box on the page and
    /// what the bubble says.
    public var Bubble: (rect: draw.Rect, text: string)? = nil

    public init() {}
}

/// A nested document's display list, and how far it is scrolled.
public struct Subpage {
    public var Items: [PaintItem]
    public var ScrollX: float32
    public var ScrollY: float32

    public init(items: [PaintItem], scrollX: float32, scrollY: float32) {
        Items = items
        ScrollX = scrollX
        ScrollY = scrollY
    }
}

/// The display list for a laid-out box tree: what to paint, in the
/// order CSS paints it, in page coordinates.
public func Build(root: layout.Box, state: State, viewportWidth: float32, viewportHeight: float32, background: draw.Color) -> [PaintItem] {
    let b = DisplayListBuilder()
    b.focused = state.Focused
    b.caret = state.Caret
    b.caretVisible = state.CaretVisible
    b.composing = state.Composing
    b.fieldSelectionStart = state.FieldSelectionStart
    b.fieldSelectionEnd = state.FieldSelectionEnd
    b.images = state.Images
    b.mediaFrames = state.MediaFrames
    b.mediaBars = state.MediaBars
    b.dragImage = state.DragImage
    b.listTops = state.ListTops
    b.panelFrame = state.PanelFrame
    b.panelCells = state.PanelCells
    b.highlights = state.Highlights
    b.bubble = state.Bubble
    b.vectors = state.Vectors
    b.selectionStart = state.SelectionStart
    b.selectionEnd = state.SelectionEnd
    b.textOrder = state.TextOrder
    b.subpages = state.Subpages
    return b.build(root, viewportWidth: viewportWidth, viewportHeight: viewportHeight, background: background)
}

final class DisplayListBuilder {
    var items: [PaintItem] = []
    /// The page's state the painter needs.
    var focused: int64 = 0
    var subpages: [int64: Subpage] = [:]
    var caret: int = -1
    var composing = ""
    var caretVisible: bool = true
    /// The focused field's selected bytes, or -1 for none.
    var fieldSelectionStart: int = -1
    var fieldSelectionEnd: int = -1
    var opacity: float32 = 1
    var bubble: (rect: draw.Rect, text: string)? = nil
    var viewportWidth: float32 = 0
    var viewportHeight: float32 = 0
    /// The current stacking context's positioned boxes, waiting to paint,
    /// each with the origin it paints from.
    var stacked: [Stacked] = []
    /// The page's images by URL, for backgrounds.
    var images: [string: draw.Image] = [:]
    var mediaFrames: [int64: draw.Image] = [:]
    /// The matrix of the preserve-3d box whose children are being painted.
    var context3D: draw.Matrix4? = nil
    /// The image being painted turned back upright.
    var uprightBox: layout.Box? = nil
    var mediaBars: [int64: MediaProgress] = [:]
    var dragImage: DragImage? = nil
    var listTops: [int64: int] = [:]
    var panelFrame: draw.Rect? = nil
    var panelCells: [PanelCell] = []
    var highlights: [Highlight] = []
    /// The page's SVG images by URL, for masks.
    var vectors: [string: svg.Document] = [:]
    /// The selection, if any, and each text node's place in the document.
    var selectionStart: dom.TextPosition? = nil
    var selectionEnd: dom.TextPosition? = nil
    var textOrder: [int64: int] = [:]

    init() {}

    func build(root: layout.Box, viewportWidth: float32, viewportHeight: float32, background: draw.Color) -> [PaintItem] {
        items = []
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        // The canvas takes the root's background, or the body's where the
        // root has none, over the whole viewport.
        var canvasColor = background
        var skipBackgroundOf: Int = 0
        if root.Style.BackgroundColor.A > 0 {
            canvasColor = root.Style.BackgroundColor
            skipBackgroundOf = root.Id
        } else {
            for c in root.Children where c.Node?.TagName == "body" {
                if c.Style.BackgroundColor.A > 0 {
                    canvasColor = c.Style.BackgroundColor
                    skipBackgroundOf = c.Id
                }
            }
        }
        if canvasColor.A > 0 {
            let h = viewportHeight > root.Y + root.Height + root.Margin.Bottom ? viewportHeight : root.Y + root.Height + root.Margin.Bottom
            items.append(.fill(draw.Rect(0, 0, viewportWidth, h), canvasColor, draw.Radii.zero))
        }
        paintBox(root, x: 0, y: 0, skipBackground: skipBackgroundOf)
        if let d = dragImage {
            // Over everything: painted again, as a whole, from where it is.
            let at = layout.PagePosition(d.box)
            var t = PaintItem(.translate)
            t.X = d.dx
            t.Y = d.dy
            items.append(t)
            let saved = opacity
            opacity = 0.6
            paintBox(d.box, x: at.x - d.box.X - d.box.OffsetX, y: at.y - d.box.Y - d.box.OffsetY, skipBackground: 0)
            opacity = saved
            items.append(PaintItem(.untranslate))
        }
        if let f = panelFrame {
            // A soft edge round a white card, and its cells on it.
            items.append(.fill(draw.Rect(f.X - 1, f.Y, f.Width + 2, f.Height + 3), draw.Color(0, 0, 0, 40), draw.Radii(all: 6)))
            items.append(.fill(f, draw.Color.white, draw.Radii(all: 5)))
            let edge = draw.Color(190, 190, 190)
            items.append(.border(f, draw.Edges(all: 1), [edge, edge, edge, edge], draw.Radii(all: 5)))
            let face = font.Load(font.Spec(families: ["system-ui"], size: 13, weight: 400))
            for c in panelCells {
                // A swatch fills its cell; a lit row or day has soft corners.
                if let fill = c.fill { items.append(.fill(c.rect, fill, c.text.isEmpty ? draw.Radii.zero : draw.Radii(all: 3))) }
                if c.text.isEmpty { continue }
                let run = face.Shape(c.text)
                let tx = c.centered ? c.rect.X + (c.rect.Width - run.Width) / 2 : c.rect.X + 6
                items.append(.text(tx, c.rect.Y + (c.rect.Height - face.LineHeight) / 2 + face.Ascent, run, c.color, 0))
            }
        }
        if let b = bubble { paintBubble(b.rect, b.text) }
        return items
    }

    /// A mask layer's source and tiling: mask-image over the border box
    /// (mask-origin's default), sized by mask-size, placed by
    /// mask-position, repeated by mask-repeat.
    /// A box's own rectangle by a mask-origin or mask-clip word.
    func maskArea(box: draw.Rect, border: draw.Edges, padding: draw.Edges, word: string) -> draw.Rect {
        switch word {
        case "padding-box":
            return draw.Rect(box.X + border.Left, box.Y + border.Top, box.Width - border.Left - border.Right, box.Height - border.Top - border.Bottom)
        case "content-box":
            return draw.Rect(box.X + border.Left + padding.Left, box.Y + border.Top + padding.Top,
                             box.Width - border.Left - border.Right - padding.Left - padding.Right,
                             box.Height - border.Top - border.Bottom - padding.Top - padding.Bottom)
        default:
            return box
        }
    }

    func maskTiles(layer: inout PaintItem, s: cascade.ComputedStyle) {
        let area = layer.MaskRect
        var iw = area.Width
        var ih = area.Height
        var intrinsic = false
        layer.Gradient = s.MaskGradient
        if !s.MaskURL.isEmpty {
            if let img = images[s.MaskURL], img.Width > 0 && img.Height > 0 {
                layer.MaskImage = img
                iw = float32(img.Width)
                ih = float32(img.Height)
                intrinsic = true
            } else if let doc = vectors[s.MaskURL] {
                layer.MaskVector = doc.Drawing
                if doc.Width > 0 && doc.Height > 0 {
                    iw = doc.Width
                    ih = doc.Height
                    intrinsic = true
                }
                layer.MaskVectorWidth = iw
            } else {
                // An image not loaded masks everything away, as a
                // browser's does until it arrives.
                layer.MaskImage = draw.Image(width: 0, height: 0, pixels: [])
            }
        }
        let m = s.MaskLayer
        let size = layerSize(m.Size, area, iw, ih, intrinsic: intrinsic)
        layer.TileWidth = size.0
        layer.TileHeight = size.1
        layer.X = area.X + (area.Width - size.0) * m.PositionX + m.OffsetX
        layer.Y = area.Y + (area.Height - size.1) * m.PositionY + m.OffsetY
        layer.RepeatX = m.RepeatX
        layer.RepeatY = m.RepeatY
        layer.MaskLuminance = s.MaskMode == "luminance"
    }

    /// The validation bubble under a control: a white card with a
    /// warning mark and the message, a line at a time, over everything.
    func paintBubble(control: draw.Rect, text: string) {
        let face = font.Load(font.Spec(families: ["system-ui"], size: 13, weight: 400))
        let lines = text.split(separator: "\n").map { string($0) }
        var width: float32 = 0
        var runs: [font.Run] = []
        for l in lines {
            let r = face.Shape(l)
            runs.append(r)
            if r.Width > width { width = r.Width }
        }
        let lineHeight: float32 = 18
        let pad: float32 = 10
        let mark: float32 = 16
        let w = width + pad * 3 + mark
        let h = float32(lines.count) * lineHeight + pad * 2 - 4
        var x = control.X
        if x + w > viewportWidth && viewportWidth > w { x = viewportWidth - w - 4 }
        let y = control.Y + control.Height + 6
        let card = draw.Rect(x, y, w, h)
        // A soft shadow, the card, its edge.
        items.append(.fill(draw.Rect(x + 1, y + 2, w, h), draw.Color(0, 0, 0, 40), draw.Radii(all: 5)))
        items.append(.fill(card, draw.Color(255, 255, 255), draw.Radii(all: 5)))
        styledRing(card, draw.Edges(all: 1), [draw.Color(190, 190, 190), draw.Color(190, 190, 190), draw.Color(190, 190, 190), draw.Color(190, 190, 190)],
                   draw.Radii(all: 5), ["solid", "solid", "solid", "solid"])
        // The warning mark: an orange square with a white "!".
        let m = draw.Rect(x + pad, y + pad - 1, mark, mark)
        items.append(.fill(m, draw.Color(242, 140, 0), draw.Radii(all: 3)))
        let bang = font.Load(font.Spec(families: ["system-ui"], size: 13, weight: 700)).Shape("!")
        items.append(.text(m.X + (mark - bang.Width) / 2, m.Y + 12.5, bang, draw.Color(255, 255, 255), 0))
        var i = 0
        while i < runs.count {
            items.append(.text(x + pad * 2 + mark, y + pad + 10 + float32(i) * lineHeight, runs[i], draw.Color(30, 30, 30), 0))
            i += 1
        }
    }

    /// The text a box paints, black and opaque, for masking: what
    /// background-clip: text keeps its background to.
    func textMask(box: layout.Box, x: float32, y: float32) -> [PaintItem] {
        let start = items.count
        let savedStack = stacked
        let savedOpacity = opacity
        opacity = 1
        paintPhase(box, .inlineContent, x: x - box.X - box.OffsetX, y: y - box.Y - box.OffsetY, skipBackground: 0, isRoot: false)
        var out: [PaintItem] = []
        var i = start
        while i < items.count {
            var it = items[i]
            if it.Kind == .text {
                it.Color = draw.Color(0, 0, 0)
                out.append(it)
            }
            i += 1
        }
        items.removeLast(items.count - start)
        stacked = savedStack
        opacity = savedOpacity
        return out
    }

    /// Paints a box as CSS orders a stacking context: the backgrounds
    /// and borders of it and its in-flow block descendants, then its
    /// floats, then its inline content and replaced content, then the
    /// boxes positioned against it.
    /// An image in vertical text stays upright: it is painted with its own
    /// sizes back, turned the other way about its middle.
    func paintUprightReplaced(box: layout.Box, x parentX: float32, y parentY: float32, skipBackground: Int) {
        let w = box.Width
        let h = box.Height
        let cx = parentX + box.X + box.OffsetX + w / 2
        let cy = parentY + box.Y + box.OffsetY + h / 2
        let turn: float32 = box.Style.WritingMode == "sideways-lr" ? 1.5707964 : -1.5707964
        var layer = PaintItem(.layer)
        layer.Rect = draw.Rect(cx - h / 2, cy - w / 2, h, w)
        layer.Transform = draw.Affine.translate(cx, cy).Concat(draw.Affine.rotate(turn)).Concat(draw.Affine.translate(-cx, -cy))
        items.append(layer)
        let savedX = box.X
        let savedY = box.Y
        box.Width = h
        box.Height = w
        box.X = cx - h / 2 - parentX - box.OffsetX
        box.Y = cy - w / 2 - parentY - box.OffsetY
        uprightBox = box
        paintBox(box, x: parentX, y: parentY, skipBackground: skipBackground)
        uprightBox = nil
        box.X = savedX
        box.Y = savedY
        box.Width = w
        box.Height = h
        items.append(PaintItem(.unlayer))
    }

    /// A vertical run, glyph by glyph where it matters: what stands upright
    /// in vertical text turned back, the rest left to turn with the line.
    func appendVerticalText(f: layout.Fragment, x: float32, baseline: float32, c: draw.Color, spacing: float32) {
        let style = f.Owner.Style
        var cps: [uint32] = []
        for u in f.Text.unicodeScalars { cps.append(u.value) }
        if style.TextOrientation == "sideways" || style.WritingMode.hasPrefix("sideways") || cps.count != f.Run.Glyphs.count {
            items.append(.text(x, baseline, f.Run, c, spacing))
            return
        }
        let face = style.Face
        var pen = x
        var i = 0
        while i < cps.count {
            var run = font.Run()
            let upright = style.TextOrientation == "upright" || standsUpright(cps[i])
            let start = pen
            var j = i
            while j < cps.count && (upright ? j == i : !(style.TextOrientation == "upright" || standsUpright(cps[j]))) {
                run.Glyphs.append(f.Run.Glyphs[j])
                run.Faces.append(f.Run.Faces[j])
                run.Advances.append(f.Run.Advances[j])
                run.Width += f.Run.Advances[j] + spacing
                pen += f.Run.Advances[j] + spacing
                j += 1
            }
            var item = PaintItem.text(start, baseline, run, c, spacing)
            if upright {
                item.Upright = true
                item.TileWidth = run.Width
                item.TileHeight = (face.Ascent - face.Descent) / 2
            }
            items.append(item)
            i = j
        }
    }

    func paintBox(box: layout.Box, x parentX: float32, y parentY: float32, skipBackground: Int) {
        if box.Kind == .replaced && box.Style.AxesSwapped && uprightBox?.Id != box.Id {
            paintUprightReplaced(box, x: parentX, y: parentY, skipBackground: skipBackground)
            return
        }
        let s = box.Style
        if s.Visibility != .visible && !hasVisibleDescendant(box) { return }
        // Nothing of a fully transparent box or its content shows.
        if s.Opacity <= 0 { return }
        let x = parentX + box.X + box.OffsetX
        let y = parentY + box.Y + box.OffsetY
        let savedOpacity = opacity
        if s.Opacity < 1 { opacity = opacity * s.Opacity }
        if box.AnchorHidden {
            opacity = savedOpacity
            return
        }
        var transform = s.HasTransform
            ? draw.Affine.translate(x, y).Concat(s.TransformMatrix(width: box.Width, height: box.Height, box: layout.TransformBoxOf(box))).Concat(draw.Affine.translate(-x, -y))
            : draw.Affine.identity
        if box.QuarterTurn != 0 { transform = transform.Concat(layout.QuarterMatrix(box, x: x, y: y)) }
        // A plane in 3D: its matrix, on top of its context's.
        var matrix3D = layout.ThreeDMatrix(box, x: x, y: y)
        let joins = matrix3D != nil && (box.Parent?.Style.UsedPreserve3D ?? false)
        if joins, let local = matrix3D, let c = context3D { matrix3D = c.Concat(local) }
        let savedContext3D = context3D
        context3D = s.UsedPreserve3D ? matrix3D : nil
        // A transform that flattens the box shows nothing of it.
        if matrix3D == nil && transform.Determinant == 0 {
            opacity = savedOpacity
            context3D = savedContext3D
            return
        }
        if box.FixedToViewport { items.append(PaintItem(.fixed)) }
        if !s.BackdropFilters.isEmpty {
            var b = PaintItem(.backdrop)
            b.Rect = draw.Rect(x, y, box.Width, box.Height)
            b.Radii = s.HasBorderRadius ? s.Radii(width: box.Width, height: box.Height) : draw.Radii.zero
            b.Filters = s.BackdropFilters
            items.append(b)
        }
        let blurred = !s.Filters.isEmpty || !transform.IsIdentity || s.HasCompositing || matrix3D != nil
        if blurred {
            var layer = PaintItem(.layer)
            layer.Rect = draw.Rect(x, y, box.Width, box.Height)
            layer.Filters = s.Filters
            layer.Transform = matrix3D != nil ? draw.Affine.identity : transform
            layer.Matrix = matrix3D
            layer.JoinsContext = joins
            layer.BackfaceHidden = s.BackfaceHidden
            if s.ClipPath != nil { layer.Shape = layout.ClipRegionOf(box, x: x, y: y) }
            layer.MaskRect = maskArea(box: layer.Rect, border: box.Border, padding: box.Padding, word: s.MaskOrigin)
            if let content = box.EffectContent {
                // clip-path or mask: url(#id), over the box.
                layer.MaskVector = content
                layer.MaskVectorWidth = box.Width
                layer.MaskLuminance = box.EffectIsMask
                layer.X = x
                layer.Y = y
                layer.TileWidth = box.Width
                layer.TileHeight = box.Height
            } else if !s.ClipURL.isEmpty || s.MaskURL.hasPrefix("#") {
                // Names nothing: per the spec a clip with no element doesn't
                // clip, and a mask with none doesn't mask.
            } else if s.MaskGradient != nil || !s.MaskURL.isEmpty {
                maskTiles(&layer, s)
                if s.MaskClip != "no-clip" {
                    layer.MaskClip = maskArea(box: layer.Rect, border: box.Border, padding: box.Padding, word: s.MaskClip)
                }
            }
            layer.Blend = s.BlendMode
            layer.Unbounded = s.BlendMode != .normal || s.Isolated
            items.append(layer)
        }
        let clips = s.ClipsOverflow
        if clips {
            paintBackgroundAndBorderIfVisible(box, x: x, y: y, skipBackground: skipBackground)
            // overflow: clip keeps what overflows by overflow-clip-margin.
            let reachX = s.OverflowX == .clip ? s.OverflowClipMargin : 0
            let reachY = s.OverflowY == .clip ? s.OverflowClipMargin : 0
            items.append(.clip(draw.Rect(x + box.Border.Left - reachX, y + box.Border.Top - reachY, box.PaddingBoxWidth + 2 * reachX, box.PaddingBoxHeight + 2 * reachY)))
            paintPhase(box, .blockBackgrounds, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: true)
        } else {
            paintPhase(box, .blockBackgrounds, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: false)
        }
        let sx = x - box.ScrollX
        let sy = y - box.ScrollY
        // The positioned boxes of this stacking context -- relative ones
        // met in its flow and the ones positioned against it -- paint
        // after its in-flow content, by z-index and then in tree order;
        // those below zero right after its backgrounds.
        let savedStack = stacked
        stacked = []
        for p in box.Positioned {
            stacked.append(Stacked(box: p, x: sx, y: sy))
        }
        var below: [Stacked] = []
        var i = 0
        while i < stacked.count {
            if stacked[i].box.Style.ZIndex < 0 { below.append(stacked[i]); stacked.remove(at: i) } else { i += 1 }
        }
        sortStacked(&below)
        for st in below { paintBox(st.box, x: st.x, y: st.y, skipBackground: skipBackground) }
        paintPhase(box, .floats, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: false)
        paintPhase(box, .inlineContent, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: false)
        var list = stacked
        stacked = savedStack
        sortStacked(&list)
        for st in list {
            paintBox(st.box, x: st.x, y: st.y, skipBackground: skipBackground)
        }
        paintPhase(box, .outlines, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: true)
        if clips {
            items.append(PaintItem.unclip)
            // A scroll container whose content overflows shows a thin bar
            // where it is scrolled to.
            if s.IsScrollContainer && !s.ScrollbarHidden && box.ContentHeight > box.InnerHeight + 0.5 && box.InnerHeight > 20 {
                let trackTop = y + box.Border.Top + 2
                let trackHeight = box.PaddingBoxHeight - 4
                let thumb = trackHeight * box.InnerHeight / box.ContentHeight
                let maxScroll = box.ContentHeight - box.InnerHeight
                let thumbY = trackTop + (trackHeight - thumb) * (maxScroll > 0 ? box.ScrollY / maxScroll : 0)
                // scrollbar-width: thin, and scrollbar-color's thumb and
                // track.
                let barWidth: float32 = s.ScrollbarThin ? 3 : 5
                // Right to left, the bar is on the left.
                let barX = s.Direction == .rtl ? x + box.Border.Left + 3 : x + box.Width - box.Border.Right - barWidth - 3
                if let track = s.ScrollbarTrack, track.A > 0 {
                    items.append(.fill(draw.Rect(barX, trackTop, barWidth, trackHeight), color(track), draw.Radii(all: barWidth / 2)))
                }
                let bar = draw.Rect(barX, thumbY, barWidth, thumb)
                items.append(.fill(bar, color(s.ScrollbarThumb ?? draw.Color(0, 0, 0, 80)), draw.Radii(all: barWidth / 2)))
            }
        }
        paintOutline(box, x: x, y: y)
        if blurred { items.append(PaintItem(.unlayer)) }
        if box.FixedToViewport { items.append(PaintItem(.unfix)) }
        opacity = savedOpacity
        context3D = savedContext3D
    }

    /// empty-cells: hide on a cell with nothing in it, borders separate.
    func isHiddenEmptyCell(box: layout.Box) -> bool {
        let s = box.Style
        if !s.HideEmptyCells || s.Display != .tableCell || s.BorderCollapse == .collapse { return false }
        return isEmptyContent(box)
    }

    func isEmptyContent(box: layout.Box) -> bool {
        for c in box.Children {
            if c.Kind == .text {
                if !layout.IsBlank(c.Text) { return false }
            } else if c.IsAnonymous && (c.Kind == .block || c.Kind == .inline) {
                if !isEmptyContent(c) { return false }
            } else {
                return false
            }
        }
        return true
    }

        func paintBackgroundAndBorderIfVisible(box: layout.Box, x: float32, y: float32, skipBackground: Int) {
        if box.Style.Visibility == .visible && box.Id != skipBackground && !isHiddenEmptyCell(box) {
            paintBackgroundAndBorder(box, x: x, y: y)
        }
        // A box a program draws into itself (ui/viewport): what the page
        // paints after this goes over the program's pixels.
        if let n = box.Node, n.HasAttribute("data-viewport") {
            var m = PaintItem(.mark)
            m.Rect = draw.Rect(x, y, box.Width, box.Height)
            m.Node = n.Id
            items.append(m)
        }
    }

    /// One phase of a box and its in-flow descendants. Descendants that
    /// start a stacking context of their own -- positioned boxes,
    /// floats, atomic inlines -- are painted whole in the phase that
    /// owns them, and skipped in the others.
    func paintPhase(box: layout.Box, phase: PaintPhase, x parentX: float32, y parentY: float32, skipBackground: Int, isRoot: Bool) {
        let s = box.Style
        let x = parentX + box.X + box.OffsetX
        let y = parentY + box.Y + box.OffsetY
        let visible = s.Visibility == .visible
        if phase == .blockBackgrounds && !isRoot {
            paintBackgroundAndBorderIfVisible(box, x: x, y: y, skipBackground: skipBackground)
        }
        if phase == .outlines && !isRoot { paintOutline(box, x: x, y: y) }
        let sx = x - box.ScrollX
        let sy = y - box.ScrollY
        if box.Kind == .replaced {
            if phase == .inlineContent && visible {
                // Upright in vertical text; there, painted as a whole.
                if s.AxesSwapped && uprightBox?.Id != box.Id {
                    paintUprightReplaced(box, x: parentX, y: parentY, skipBackground: skipBackground)
                } else {
                    paintReplaced(box, x: x, y: y)
                }
            }
            return
        }
        if !box.Lines.isEmpty {
            // Floats among the lines belong to the float phase; the
            // lines themselves to the inline phase.
            if phase == .floats {
                for child in box.Children {
                    paintFloatsWithin(child, x: sx, y: sy, skipBackground: skipBackground)
                }
            } else if phase == .inlineContent {
                var first = true
                for line in box.Lines {
                    paintLine(box, line, x: sx, y: sy, visible: visible, firstLine: first)
                    first = false
                }
            }
            return
        }
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed { continue }
            if child.Kind == .text || child.Kind == .inline || child.Kind == .lineBreak { continue }
            if child.Style.Float != .none {
                if phase == .floats { paintBox(child, x: sx, y: sy, skipBackground: skipBackground) }
                continue
            }
            if child.Style.IsPositioned || child.Style.HasTransform || child.Style.Perspective > 0 || child.Style.Preserve3D || child.QuarterTurn != 0 || child.Style.WillChangeStacks {
                // A relative or sticky box paints as a whole, with what
                // is positioned against it, among the stacking context's
                // positioned boxes.
                if phase == .inlineContent { stacked.append(Stacked(box: child, x: sx, y: sy)) }
                continue
            }
            if child.Style.ClipsOverflow || child.Style.Opacity < 1 || !child.Style.Filters.isEmpty || child.Style.HasCompositing {
                // A clipping or translucent box paints as a whole, in
                // the phase its background would go in.
                if phase == .blockBackgrounds { paintBox(child, x: sx, y: sy, skipBackground: skipBackground) }
                continue
            }
            paintPhase(child, phase, x: sx, y: sy, skipBackground: skipBackground, isRoot: false)
        }
    }

    func paintOutline(box: layout.Box, x: float32, y: float32) {
        let s = box.Style
        if s.Visibility == .visible && s.OutlineWidth > 0 && s.OutlineStyle != "none" && s.OutlineStyle != "hidden" {
            let w = s.OutlineWidth
            let o = s.OutlineOffset
            let ring = draw.Rect(x - w - o, y - w - o, box.Width + 2 * (w + o), box.Height + 2 * (w + o))
            let c = color(s.OutlineColor ?? draw.Color(0, 95, 204))
            // auto follows the box's corners; the rest are square
            // unless the box is round, as browsers draw them.
            let radii = !s.HasBorderRadius ? draw.Radii.zero : draw.Radii(all: s.Radii(width: box.Width, height: box.Height).TopLeft + w + o)
            let style = s.OutlineStyle == "auto" ? "solid" : s.OutlineStyle
            styledRing(ring, draw.Edges(all: w), [c, c, c, c], radii, [style, style, style, style])
        }
    }

    /// Floats that inline layout placed among a box's inline content.
    func paintFloatsWithin(box: layout.Box, x: float32, y: float32, skipBackground: Int) {
        if box.Kind == .text || box.Kind == .lineBreak { return }
        if box.Style.Float != .none {
            paintBox(box, x: x, y: y, skipBackground: skipBackground)
            return
        }
        if box.Kind == .inline {
            for child in box.Children {
                paintFloatsWithin(child, x: x, y: y, skipBackground: skipBackground)
            }
        }
    }

    func color(c: draw.Color) -> draw.Color {
        return opacity < 1 ? c.Faded(opacity) : c
    }

    func hasVisibleDescendant(box: layout.Box) -> bool {
        for c in box.Children {
            if c.Style.Visibility == .visible || hasVisibleDescendant(c) { return true }
        }
        return false
    }

    /// With imageOnly, just the background image, for a fragment of a split
    /// block to show.
    func paintBackgroundAndBorder(box: layout.Box, x: float32, y: float32, imageOnly: bool = false) {
        let s = box.Style
        if !box.ColumnFragments.isEmpty && !imageOnly {
            paintFragments(box, x: x, y: y)
            return
        }
        let rect = draw.Rect(x, y, box.Width, box.Height)
        var radii = s.Radii(width: box.Width, height: box.Height)
        if !radii.IsZero { radii = radii.Fitted(box.Width, box.Height) }
        // corner-shape: the box drawn as the outline its corners make.
        if !s.CornerShapes.isEmpty && !radii.IsZero && !imageOnly {
            let outer = cornerOutline(rect, radii, s.CornerShapes)
            if s.BackgroundColor.A > 0 {
                var fill = PaintItem(.path)
                fill.Outline = pathOf(outer)
                fill.Color = color(s.BackgroundColor)
                items.append(fill)
            }
            // The image, in a layer cut to the outline.
            if s.BackgroundImage != nil {
                var layer = PaintItem(.layer)
                layer.Rect = rect
                layer.MaskRect = rect
                layer.Shape = layout.PolygonRegion(outer)
                items.append(layer)
                paintBackgroundAndBorder(box, x: x, y: y, imageOnly: true)
                items.append(PaintItem(.unlayer))
            }
            let b = box.Border
            if b.Top > 0 || b.Right > 0 || b.Bottom > 0 || b.Left > 0 {
                let inner = cornerOutline(draw.Rect(x + b.Left, y + b.Top, box.Width - b.Left - b.Right, box.Height - b.Top - b.Bottom),
                                          radii.Inset(b), s.CornerShapes)
                var ring = pathOf(outer)
                var i = inner.count - 1
                while i >= 0 {
                    if i == inner.count - 1 { ring.MoveTo(inner[i].X, inner[i].Y) } else { ring.LineTo(inner[i].X, inner[i].Y) }
                    i -= 1
                }
                ring.Close()
                var sides: [draw.Color] = []
                var side = 0
                while side < 4 {
                    sides.append(color(borderSideColor(s, side)))
                    side += 1
                }
                if sides[1] == sides[0] && sides[2] == sides[0] && sides[3] == sides[0] {
                    var edge = PaintItem(.path)
                    edge.Outline = ring
                    edge.Color = sides[0]
                    items.append(edge)
                } else {
                    // A color a side: the ring in each side's wedge, from its
                    // corners to the middle.
                    let mid = draw.Point(x + box.Width / 2, y + box.Height / 2)
                    let tl = draw.Point(x, y)
                    let tr = draw.Point(x + box.Width, y)
                    let br = draw.Point(x + box.Width, y + box.Height)
                    let bl = draw.Point(x, y + box.Height)
                    let wedges = [[tl, tr, mid], [tr, br, mid], [br, bl, mid], [bl, tl, mid]]
                    var i = 0
                    while i < 4 {
                        if sides[i].A > 0 {
                            var layer = PaintItem(.layer)
                            layer.Rect = rect
                            layer.MaskRect = rect
                            layer.Shape = layout.PolygonRegion(wedges[i])
                            items.append(layer)
                            var edge = PaintItem(.path)
                            edge.Outline = ring
                            edge.Color = sides[i]
                            items.append(edge)
                            items.append(PaintItem(.unlayer))
                        }
                        i += 1
                    }
                }
            }
            return
        }
        // Shadows go under the box: each drawn as rings from the blur's
        // outer edge inward, which fades like a blur near enough.
        for sh in s.Shadows where !sh.Inset && sh.Color.A > 0 && !imageOnly {
            let steps = sh.Blur > 1 ? (sh.Blur > 12 ? 12 : int(sh.Blur)) : 1
            let each = color(sh.Color).Faded(1 / float32(steps))
            var i = 0
            while i < steps {
                let grow = sh.Spread + sh.Blur / 2 - sh.Blur * float32(i) / float32(steps)
                let r = draw.Rect(x + sh.X - grow, y + sh.Y - grow, box.Width + 2 * grow, box.Height + 2 * grow)
                if r.Width > 0 && r.Height > 0 {
                    items.append(.fill(r, each, draw.Radii(all: (radii.IsZero ? 0 : radii.TopLeft) + grow)))
                }
                i += 1
            }
        }
        // background-clip: where the background shows; background-origin:
        // what the image is positioned and sized in.
        func area(which: string) -> (rect: draw.Rect, radii: draw.Radii) {
            switch which {
            case "padding-box":
                return (rect: draw.Rect(x + box.Border.Left, y + box.Border.Top, box.PaddingBoxWidth, box.PaddingBoxHeight), radii: radii.Inset(box.Border))
            case "content-box":
                let inset = draw.Edges(box.Border.Top + box.Padding.Top, box.Border.Right + box.Padding.Right,
                                       box.Border.Bottom + box.Padding.Bottom, box.Border.Left + box.Padding.Left)
                return (rect: draw.Rect(x + inset.Left, y + inset.Top, box.Width - inset.Horizontal, box.Height - inset.Vertical), radii: radii.Inset(inset))
            default:
                return (rect: rect, radii: radii)
            }
        }
        // The background: its color and its image, in a clip area.
        func background(clip: (rect: draw.Rect, radii: draw.Radii), textClip: bool) {
            if s.BackgroundColor.A > 0 && !imageOnly {
                items.append(.fill(clip.rect, color(s.BackgroundColor), clip.radii))
            }
            guard let bg = s.BackgroundImage else { return }
            var paddingBox = area(s.BackgroundOrigin).rect
            let shown = textClip ? clip.rect : clip.rect.Intersect(s.BackgroundClip == "border-box" ? area("padding-box").rect.Union(clip.rect) : clip.rect)
            // background-attachment: fixed positions and sizes the image
            // against the viewport (in its own coordinates, the scroll
            // added when drawn); local, against a scroll container's
            // content, so that it scrolls with it.
            let pinned = s.BackgroundAttachment == "fixed"
            if pinned {
                paddingBox = draw.Rect(0, 0, viewportWidth, viewportHeight)
            } else if s.BackgroundAttachment == "local" && s.IsScrollContainer {
                paddingBox = draw.Rect(paddingBox.X - box.ScrollX, paddingBox.Y - box.ScrollY,
                                       maxf(paddingBox.Width, box.ContentWidth + box.Padding.Horizontal),
                                       maxf(paddingBox.Height, box.ContentHeight + box.Padding.Vertical))
            }
            if var g = bg.Gradient {
                if opacity < 1 {
                    var i = 0
                    while i < g.Stops.count {
                        g.Stops[i].Color = color(g.Stops[i].Color)
                        i += 1
                    }
                }
                if pinned || s.BackgroundAttachment == "local" && s.IsScrollContainer {
                    // The gradient over its positioning area, shown in
                    // the box's.
                    items.append(.clip(shown))
                    var it = PaintItem.gradient(paddingBox, g, draw.Radii.zero)
                    it.Pinned = pinned
                    items.append(it)
                    items.append(PaintItem.unclip)
                } else {
                    items.append(.gradient(shown, g, clip.radii))
                }
            } else if !bg.URL.isEmpty, let img = images[bg.URL], img.Width > 0 && img.Height > 0 {
                var tw = float32(img.Width) / bg.Density
                var th = float32(img.Height) / bg.Density
                switch bg.Size {
                case .cover:
                    let scale = maxf(paddingBox.Width / tw, paddingBox.Height / th)
                    tw *= scale
                    th *= scale
                case .contain:
                    let scale = minf(paddingBox.Width / tw, paddingBox.Height / th)
                    tw *= scale
                    th *= scale
                case .length(let w, let h):
                    let rw = w.Resolve(paddingBox.Width)
                    let rh = h.Resolve(paddingBox.Height)
                    if let a = rw, let b = rh { tw = a; th = b }
                    else if let a = rw { th = th * a / tw; tw = a }
                    else if let b = rh { tw = tw * b / th; th = b }
                case .auto:
                    break
                }
                let ox = paddingBox.X + (paddingBox.Width - tw) * bg.PositionX + bg.OffsetX
                let oy = paddingBox.Y + (paddingBox.Height - th) * bg.PositionY + bg.OffsetY
                var it = PaintItem.tiles(shown, img, tileWidth: tw, tileHeight: th, originX: ox, originY: oy,
                                         repeatX: bg.RepeatX, repeatY: bg.RepeatY, opacity: opacity, radii: clip.radii)
                it.Pinned = pinned
                items.append(it)
            }
        }
        if s.BackgroundClip == "text" {
            // The background only where the box's text is: drawn in a
            // layer kept by the text's glyphs.
            let mask = textMask(box, x: x, y: y)
            if !mask.isEmpty && (s.BackgroundColor.A > 0 || s.BackgroundImage != nil) {
                var layer = PaintItem(.layer)
                layer.Rect = rect
                layer.MaskRect = rect
                layer.TextMask = mask
                items.append(layer)
                background(area("border-box"), textClip: true)
                items.append(PaintItem(.unlayer))
            }
        } else {
            background(area(s.BackgroundClip), textClip: false)
        }
        if imageOnly { return }
        let widths = box.Border
        if s.HasBorderImage, let bi = borderImage(box, x: x, y: y) {
            items.append(bi)
        } else if widths.Top > 0 || widths.Right > 0 || widths.Bottom > 0 || widths.Left > 0 {
            var colors: [draw.Color] = []
            var side = 0
            while side < 4 {
                colors.append(color(borderSideColor(s, side)))
                side += 1
            }
            styledRing(rect, widths, colors, radii, [styleName(s.BorderTopStyle), styleName(s.BorderRightStyle),
                                                     styleName(s.BorderBottomStyle), styleName(s.BorderLeftStyle)])
        }
        // column-rule: down the middle of each gap between columns
        // that hold content, as tall as the columns.
        if s.IsMultiColumn && !box.ColumnRules.isEmpty && s.ColumnRuleWidth > 0 && s.ColumnRuleStyle != .none && s.ColumnRuleStyle != .hidden {
            let w = s.ColumnRuleWidth
            let c = color(s.ColumnRuleColor ?? s.Color)
            let style = styleName(s.ColumnRuleStyle)
            for r in box.ColumnRules where r.Height > 0 {
                let rule = draw.Rect(x + r.X - w / 2, y + r.Y, w, r.Height)
                styledRing(rule, draw.Edges(0, 0, 0, w), [c, c, c, c], draw.Radii.zero, [style, style, style, style])
            }
        }
    }

    /// A box's border-image, or nil where its image isn't loaded: the
    /// border's own style shows then.
    func borderImage(box: layout.Box, x: float32, y: float32) -> PaintItem? {
        let s = box.Style
        let bw = box.Border
        let border: [float32] = [bw.Top, bw.Right, bw.Bottom, bw.Left]
        func side(v: cascade.BorderImageSide, i: int, base: float32, auto: float32) -> float32 {
            switch v {
            case .times(let n): return n * border[i]
            case .length(let l): return l.Or(0, base: base)
            case .auto: return auto
            }
        }
        let o = s.BorderImageOutsets
        let area = draw.Rect(x - side(o[3], 3, 0, 0), y - side(o[0], 0, 0, 0),
                             box.Width + side(o[1], 1, 0, 0) + side(o[3], 3, 0, 0), box.Height + side(o[0], 0, 0, 0) + side(o[2], 2, 0, 0))
        var it = PaintItem(.borderImage)
        it.Rect = area
        // The image's size: its own, or for a gradient the area's.
        var iw = area.Width
        var ih = area.Height
        if var g = s.BorderImageGradient {
            if opacity < 1 {
                var i = 0
                while i < g.Stops.count {
                    g.Stops[i].Color = color(g.Stops[i].Color)
                    i += 1
                }
            }
            it.Gradient = g
        } else if let img = images[s.BorderImageURL], img.Width > 0 && img.Height > 0 {
            it.Image = img
            it.Opacity = opacity
            iw = float32(img.Width)
            ih = float32(img.Height)
        } else if let doc = vectors[s.BorderImageURL] {
            // An SVG image: drawn at its own size, or the area's where
            // it has none, then cut as a raster one is.
            it.Vector = doc.Drawing
            it.Opacity = opacity
            if doc.Width > 0 && doc.Height > 0 {
                iw = doc.Width
                ih = doc.Height
            }
            it.TileWidth = iw
            it.TileHeight = ih
        } else {
            return nil
        }
        let sl = s.BorderImageSlice
        it.Slice = draw.Edges(sl[0].Or(0, base: ih), sl[1].Or(0, base: iw), sl[2].Or(0, base: ih), sl[3].Or(0, base: iw))
        it.SliceFill = s.BorderImageFill
        let w = s.BorderImageWidths
        it.Widths = draw.Edges(side(w[0], 0, area.Height, it.Slice.Top), side(w[1], 1, area.Width, it.Slice.Right),
                               side(w[2], 2, area.Height, it.Slice.Bottom), side(w[3], 3, area.Width, it.Slice.Left))
        it.SliceAcross = sliceRepeat(s.BorderImageRepeat[0])
        it.SliceDown = sliceRepeat(s.BorderImageRepeat[1])
        return it
    }

    func sliceRepeat(k: string) -> draw.SliceRepeat {
        switch k {
        case "repeat": return .tile
        case "round": return .round
        case "space": return .space
        default: return .stretch
        }
    }

    /// A block split between columns: its background and border in each
    /// column's fragment. Sliced, the top edge is the first fragment's
    /// and the bottom the last's; cloned, each has all four.
    func paintFragments(box: layout.Box, x: float32, y: float32) {
        let s = box.Style
        let n = box.ColumnFragments.count
        // How far down the whole box this fragment starts, the fragments
        // stacked as if never split.
        var stitched: float32 = 0
        var i = 0
        while i < n {
            let f = box.ColumnFragments[i]
            let r = draw.Rect(x + f.X, y + f.Y, f.Width, f.Height)
            let first = i == 0 || s.DecorationClone
            let last = i == n - 1 || s.DecorationClone
            var radii = s.HasBorderRadius ? s.Radii(width: r.Width, height: r.Height) : draw.Radii.zero
            if !first { radii.TopLeft = 0; radii.TopRight = 0 }
            if !last { radii.BottomLeft = 0; radii.BottomRight = 0 }
            if !radii.IsZero { radii = radii.Fitted(r.Width, r.Height) }
            if s.BackgroundColor.A > 0 { items.append(.fill(r, color(s.BackgroundColor), radii)) }
            // The image: sliced, the whole box's seen through this fragment;
            // cloned, the fragment's own as if it were the box.
            if s.BackgroundImage != nil {
                items.append(.clip(r))
                if s.DecorationClone {
                    let whole = box.Height
                    box.Height = f.Height
                    paintBackgroundAndBorder(box, x: r.X, y: r.Y, imageOnly: true)
                    box.Height = whole
                } else {
                    paintBackgroundAndBorder(box, x: r.X, y: r.Y - stitched, imageOnly: true)
                }
                items.append(PaintItem.unclip)
            }
            stitched += f.Height
            let w = draw.Edges(first ? box.Border.Top : 0, box.Border.Right, last ? box.Border.Bottom : 0, box.Border.Left)
            if w.Top > 0 || w.Right > 0 || w.Bottom > 0 || w.Left > 0 {
                var colors: [draw.Color] = []
                var side = 0
                while side < 4 {
                    colors.append(color(borderSideColor(s, side)))
                    side += 1
                }
                styledRing(r, w, colors, radii, [styleName(s.BorderTopStyle), styleName(s.BorderRightStyle),
                                                 styleName(s.BorderBottomStyle), styleName(s.BorderLeftStyle)])
            }
            i += 1
        }
    }

    func styleName(b: cascade.BorderStyle) -> string {
        switch b {
        case .dashed: return "dashed"
        case .dotted: return "dotted"
        case .double: return "double"
        default: return "solid"
        }
    }

    /// A border or outline whose sides may be dashed, dotted or double:
    /// the solid sides as one ring, the others drawn side by side.
    func styledRing(rect: draw.Rect, widths: draw.Edges, colors: [draw.Color], radii: draw.Radii, styles: [string]) {
        var plain = true
        for st in styles where st != "solid" { plain = false }
        if plain {
            items.append(.border(rect, widths, colors, radii))
            return
        }
        if !radii.IsZero {
            roundedStyledRing(rect, widths, colors, radii, styles)
            return
        }
        let w = [widths.Top, widths.Right, widths.Bottom, widths.Left]
        var solid = widths
        if styles[0] != "solid" { solid.Top = 0 }
        if styles[1] != "solid" { solid.Right = 0 }
        if styles[2] != "solid" { solid.Bottom = 0 }
        if styles[3] != "solid" { solid.Left = 0 }
        if solid.Top > 0 || solid.Right > 0 || solid.Bottom > 0 || solid.Left > 0 {
            items.append(.border(rect, solid, colors, draw.Radii.zero))
        }
        var side = 0
        while side < 4 {
            let st = styles[side]
            let t = w[side]
            if st == "solid" || t <= 0 { side += 1; continue }
            // The side's strip, along its length.
            var strip = draw.Rect.zero
            var horizontal = true
            switch side {
            case 0: strip = draw.Rect(rect.X, rect.Y, rect.Width, t)
            case 1: strip = draw.Rect(rect.Right - t, rect.Y, t, rect.Height); horizontal = false
            case 2: strip = draw.Rect(rect.X, rect.Bottom - t, rect.Width, t)
            default: strip = draw.Rect(rect.X, rect.Y, t, rect.Height); horizontal = false
            }
            let c = colors[side]
            if st == "double" {
                let third = t / 3
                if horizontal {
                    items.append(.fill(draw.Rect(strip.X, strip.Y, strip.Width, third), c, draw.Radii.zero))
                    items.append(.fill(draw.Rect(strip.X, strip.Bottom - third, strip.Width, third), c, draw.Radii.zero))
                } else {
                    items.append(.fill(draw.Rect(strip.X, strip.Y, third, strip.Height), c, draw.Radii.zero))
                    items.append(.fill(draw.Rect(strip.Right - third, strip.Y, third, strip.Height), c, draw.Radii.zero))
                }
                side += 1
                continue
            }
            // Dashes three widths long, dots one, with gaps between,
            // spaced so that the side starts and ends with one.
            let length = horizontal ? strip.Width : strip.Height
            let mark = st == "dotted" ? t : t * 3
            var n = int((length + mark) / (2 * mark))
            if n < 1 { n = 1 }
            let gap = n > 1 ? (length - float32(n) * mark) / float32(n - 1) : 0
            var k = 0
            while k < n {
                let at = float32(k) * (mark + gap)
                let r = horizontal ? draw.Rect(strip.X + at, strip.Y, mark, t) : draw.Rect(strip.X, strip.Y + at, t, mark)
                items.append(.fill(r, c, st == "dotted" ? draw.Radii(all: t / 2) : draw.Radii.zero))
                k += 1
            }
            side += 1
        }
    }

    /// styledRing on a rounded box: each side drawn along its own line,
    /// from the middle of the corner before it to the middle of the corner
    /// after, so dashes and dots follow the curve. Dashes are three widths
    /// long and dots one, spaced so that one sits on each corner's middle.
    func roundedStyledRing(rect: draw.Rect, widths: draw.Edges, colors: [draw.Color], radii: draw.Radii, styles: [string]) {
        let w = [widths.Top, widths.Right, widths.Bottom, widths.Left]
        // Corners too big for the box shrink to fit, as a solid ring's do.
        let fit = radii.Fitted(rect.Width, rect.Height)
        let corner = [fit.TopLeft, fit.TopRight, fit.BottomRight, fit.BottomLeft]
        // A side's line, `inset` in from the box's edge.
        func sideLine(side: int, inset: float32) -> [draw.Point] {
            var pts: [draw.Point] = []
            var half = 0
            while half < 2 {
                let k = (side + half) % 4
                let reach = math.Max(corner[k], inset)
                let r = reach - inset
                let cx = k == 0 || k == 3 ? rect.X + reach : rect.Right - reach
                let cy = k < 2 ? rect.Y + reach : rect.Bottom - reach
                // Corner k runs from 180 + 90k degrees to 270 + 90k; the
                // side takes the second half of the first and the first
                // half of the second.
                let from = float32(math.Pi) * (float32(k) / 2 + (half == 0 ? 1.25 : 1.0))
                var steps = int(math.Ceil(r * 0.8)) + 1
                if steps > 32 { steps = 32 }
                var i = 0
                while i <= steps {
                    let a = from + float32(math.Pi) / 4 * float32(i) / float32(steps)
                    pts.append(draw.Point(cx + r * math.Cos(a), cy + r * math.Sin(a)))
                    i += 1
                }
                half += 1
            }
            return pts
        }
        func lengths(pts: [draw.Point]) -> [float32] {
            var out: [float32] = [0]
            var i = 1
            while i < pts.count {
                let dx = pts[i].X - pts[i - 1].X
                let dy = pts[i].Y - pts[i - 1].Y
                out.append(out[i - 1] + math.Sqrt(dx * dx + dy * dy))
                i += 1
            }
            return out
        }
        // The point `at` along the line.
        func pointAt(pts: [draw.Point], len: [float32], at: float32) -> draw.Point {
            var i = 1
            while i < pts.count - 1 && len[i] < at { i += 1 }
            let span = len[i] - len[i - 1]
            let f = span > 0 ? (at - len[i - 1]) / span : 0
            return draw.Point(pts[i - 1].X + (pts[i].X - pts[i - 1].X) * f, pts[i - 1].Y + (pts[i].Y - pts[i - 1].Y) * f)
        }
        // The stretch of the line from `a` to `b`, stroked `width` wide.
        func stroke(pts: [draw.Point], len: [float32], a: float32, b: float32, width: float32, c: draw.Color) {
            var line = draw.Path()
            let p0 = pointAt(pts, len, a)
            line.MoveTo(p0.X, p0.Y)
            var i = 0
            while i < pts.count {
                if len[i] > a && len[i] < b { line.LineTo(pts[i].X, pts[i].Y) }
                i += 1
            }
            let p1 = pointAt(pts, len, b)
            line.LineTo(p1.X, p1.Y)
            var it = PaintItem(.path)
            it.Outline = line.Stroked(draw.Stroke(width: width))
            it.Color = c
            items.append(it)
        }
        var side = 0
        while side < 4 {
            let st = styles[side]
            let t = w[side]
            let c = colors[side]
            if t <= 0 { side += 1; continue }
            // An opaque side runs half a pixel into the next, so no seam
            // shows where their smoothed ends meet.
            let over: float32 = c.A == 255 ? 0.5 : 0
            switch st {
            case "double":
                for inset in [t / 6, t * 5 / 6] {
                    let pts = sideLine(side, inset)
                    let len = lengths(pts)
                    stroke(pts, len, -over, len[len.count - 1] + over, t / 3, c)
                }
            case "dashed", "dotted":
                let pts = sideLine(side, t / 2)
                let len = lengths(pts)
                let total = len[len.count - 1]
                let dotted = st == "dotted"
                let mark = dotted ? t : t * 3
                var n = int(math.Round(total / (2 * mark)))
                if n < 1 { n = 1 }
                let period = total / float32(n)
                // The mark on the corner after belongs to the next side
                // when it is drawn the same way.
                let last = styles[(side + 1) % 4] == st && w[(side + 1) % 4] > 0 ? n - 1 : n
                var k = 0
                while k <= last {
                    let at = float32(k) * period
                    if dotted {
                        let p = pointAt(pts, len, at)
                        items.append(.fill(draw.Rect(p.X - t / 2, p.Y - t / 2, t, t), c, draw.Radii(all: t / 2)))
                    } else {
                        let a = math.Max(at - mark / 2, -over)
                        let b = math.Min(at + mark / 2, total + over)
                        if b > a { stroke(pts, len, a, b, t, c) }
                    }
                    k += 1
                }
            default:
                let pts = sideLine(side, t / 2)
                let len = lengths(pts)
                stroke(pts, len, -over, len[len.count - 1] + over, t, c)
            }
            side += 1
        }
    }

    /// A side's color, with inset, outset, groove and ridge shaded the
    /// way browsers shade them: top and left light for outset, dark for
    /// inset.
    func borderSideColor(s: cascade.ComputedStyle, side: Int) -> draw.Color {
        let base = s.BorderColor(side)
        var style = s.BorderTopStyle
        if side == 1 { style = s.BorderRightStyle } else if side == 2 { style = s.BorderBottomStyle } else if side == 3 { style = s.BorderLeftStyle }
        let topLeft = side == 0 || side == 3
        switch style {
        case .inset: return topLeft ? shade(base, 0.6) : shade(base, 1.0)
        case .outset: return topLeft ? shade(base, 1.0) : shade(base, 0.6)
        case .groove: return topLeft ? shade(base, 0.6) : shade(base, 1.0)
        case .ridge: return topLeft ? shade(base, 1.0) : shade(base, 0.6)
        default: return base
        }
    }

    func shade(c: draw.Color, f: float32) -> draw.Color {
        if f >= 1 { return c }
        return draw.Color(uint8(float32(c.R) * f), uint8(float32(c.G) * f), uint8(float32(c.B) * f), c.A)
    }

    func paintLine(container: layout.Box, line: layout.Line, x: float32, y: float32, visible: Bool, firstLine: bool = false) {
        let firstLineStyle = firstLine ? container.FirstLineStyle : nil
        // Selected text drawn again in ::selection's color, clipped to
        // where it is selected.
        var reselected: [(rect: draw.Rect, color: draw.Color)] = []
        // Inline elements' backgrounds and borders, outer first.
        for sp in line.Spans {
            let b = sp.Box
            let s = b.Style
            if b.Style.Visibility != .visible { continue }
            let rect = draw.Rect(x + sp.X, y + sp.Y, sp.Width, sp.Height)
            if s.BackgroundColor.A > 0 {
                items.append(.fill(rect, color(s.BackgroundColor), draw.Radii.zero))
            }
            var widths = b.Border
            if !sp.IsFirst { widths.Left = 0 }
            if !sp.IsLast { widths.Right = 0 }
            if widths.Top > 0 || widths.Bottom > 0 || widths.Left > 0 || widths.Right > 0 {
                var colors: [draw.Color] = []
                var side = 0
                while side < 4 {
                    colors.append(color(borderSideColor(s, side)))
                    side += 1
                }
                items.append(.border(rect, widths, colors, draw.Radii.zero))
            }
        }
        // Named highlights go under the text, and over it what they recolor.
        for h in highlights {
            for range in h.ranges {
                for f in line.Fragments where f.Kind == .text {
                    guard let node = f.Box.Node, let part = SelectedPart(f, node, range, textOrder) else { continue }
                    let face = f.Owner.Style.Face
                    let bytes = [uint8](f.Text.utf8)
                    let x0 = x + f.X + face.Measure(stringOf(bytes, 0, part.from))
                    let x1 = part.to >= bytes.count ? x + f.X + f.Width : x + f.X + face.Measure(stringOf(bytes, 0, part.to))
                    let rect = draw.Rect(x0, y + line.Y, x1 - x0, line.Height)
                    if h.background.A > 0 { items.append(.fill(rect, color(h.background), draw.Radii.zero)) }
                    if h.color != h.inherited { reselected.append((rect: rect, color: h.color)) }
                }
            }
        }
        // The selection's highlight goes under the text.
        if let start = selectionStart, let end = selectionEnd {
            for f in line.Fragments where f.Kind == .text {
                guard let node = f.Box.Node else { continue }
                if let part = SelectedPart(f, node, (start: start, end: end), textOrder) {
                    let face = f.Owner.Style.Face
                    let bytes = [uint8](f.Text.utf8)
                    var x0 = x + f.X + face.Measure(stringOf(bytes, 0, part.from))
                    var x1 = part.to >= bytes.count ? x + f.X + f.Width : x + f.X + face.Measure(stringOf(bytes, 0, part.to))
                    if f.RightToLeft {
                        // Measured from the right, where the text starts.
                        let right = x + f.X + f.Width
                        let a = right - (x0 - x - f.X)
                        let b = right - (x1 - x - f.X)
                        x0 = b
                        x1 = a
                    }
                    let rect = draw.Rect(x0, y + line.Y, x1 - x0, line.Height)
                    var highlight = draw.Color(179, 212, 252)
                    if let ss = selectionStyle(f.Owner) {
                        if ss.BackgroundColor.A > 0 { highlight = ss.BackgroundColor }
                        if ss.Color != f.Owner.Style.Color { reselected.append((rect: rect, color: ss.Color)) }
                    }
                    items.append(.fill(rect, color(highlight), draw.Radii.zero))
                }
            }
        }
        for f in line.Fragments {
            switch f.Kind {
            case .text, .marker:
                if f.Owner.Style.Visibility != .visible { continue }
                if f.Kind == .marker && (f.Box.MarkerImage != nil || f.Box.MarkerVector != nil) {
                    let size = f.Box.MarkerImageSize
                    let r = draw.Rect(x + f.X, y + f.Y, size.Width, size.Height)
                    if let img = f.Box.MarkerImage {
                        items.append(.image(r, img, opacity))
                    } else {
                        var item = PaintItem(.vector)
                        item.Rect = r
                        item.Vector = f.Box.MarkerVector
                        item.Color = color(f.Owner.Style.Color)
                        items.append(item)
                    }
                    continue
                }
                var ownColor = f.Owner.Style.Color
                if f.Kind == .marker, let ms = f.Box.MarkerStyle { ownColor = ms.Color }
                // ::first-line recolors what of the line inherits the
                // block's color.
                if let fl = firstLineStyle, f.Owner.Style.Color == container.Style.Color { ownColor = fl.Color }
                // -webkit-text-fill-color paints the glyphs over color.
                let textColor = color(f.Kind == .text ? (f.Owner.Style.TextFillColor ?? ownColor) : ownColor)
                if f.Run.Count > 0 {
                    // text-shadow: behind the text, the last listed
                    // furthest back, each blurred in a layer of its own.
                    let shadows = f.Owner.Style.TextShadows
                    var k = shadows.count - 1
                    while k >= 0 {
                        let sh = shadows[k]
                        k -= 1
                        if sh.Color.A == 0 { continue }
                        if sh.Blur > 0 {
                            var layer = PaintItem(.layer)
                            layer.Rect = draw.Rect(x + f.X + sh.X - sh.Blur, y + f.Y + sh.Y - sh.Blur, f.Width + 2 * sh.Blur, f.Height + 2 * sh.Blur)
                            layer.Filters = [.blur(sh.Blur / 2)]
                            items.append(layer)
                        }
                        items.append(.text(x + f.X + sh.X, y + f.Y + f.Ascent + sh.Y, f.Run, color(sh.Color), f.Owner.Style.LetterSpacing))
                        if sh.Blur > 0 { items.append(PaintItem(.unlayer)) }
                    }
                    if f.Owner.Style.IsVertical {
                        appendVerticalText(f, x: x + f.X, baseline: y + f.Y + f.Ascent, c: textColor, spacing: f.Owner.Style.LetterSpacing)
                    } else {
                        var item = PaintItem.text(x + f.X, y + f.Y + f.Ascent, f.Run, textColor, f.Owner.Style.LetterSpacing)
                        // -webkit-text-stroke: its outline, in its color.
                        if f.Kind == .text && f.Owner.Style.TextStrokeWidth > 0 {
                            item.StrokeWidth = f.Owner.Style.TextStrokeWidth
                            item.StrokeColor = color(f.Owner.Style.TextStrokeColor ?? ownColor)
                            item.StrokeFirst = f.Owner.Style.StrokeBeforeFill
                        }
                        items.append(item)
                    }
                }
                // text-emphasis: a mark over each character, half its size.
                if f.Kind == .text && !f.Owner.Style.TextEmphasisMark.isEmpty {
                    let st = f.Owner.Style
                    let markFace = font.Load(font.Spec(families: st.FontFamilies, size: st.FontSize / 2, weight: 400))
                    let mark = markFace.Shape(st.TextEmphasisMark)
                    let baseline = y + f.Y + f.Ascent
                    let my = st.TextEmphasisUnder ? baseline + st.Face.Descent + markFace.Ascent : baseline - st.Face.Ascent - markFace.Descent
                    var pen = x + f.X
                    var gi = 0
                    while gi < f.Run.Glyphs.count {
                        let adv = f.Run.Advances[gi]
                        if f.Run.Glyphs[gi] != 0 {
                            items.append(.text(pen + (adv - mark.Width) / 2, my, mark, color(st.TextEmphasisColor ?? st.Color), 0))
                        }
                        pen += adv + st.LetterSpacing
                        gi += 1
                    }
                }
                if !f.Decoration.IsNone {
                    let face = f.Owner.Style.Face
                    let d = f.Decoration
                    let thickness = d.Thickness >= 0 ? math.Max(d.Thickness, 1) : (face.Size / 14 > 1 ? face.Size / 14 : 1)
                    let c = color(f.DecorationColor)
                    let baseline = y + f.Y + f.Ascent
                    if d.Underline {
                        let under = d.UnderlineOffset > -999 ? baseline + d.UnderlineOffset : baseline + face.Descent * 0.4
                        decorationLine(x + f.X, under, f.Width, thickness, c, d.Style)
                    }
                    if d.LineThrough {
                        decorationLine(x + f.X, baseline - face.XHeight / 2, f.Width, thickness, c, d.Style)
                    }
                    if d.Overline {
                        decorationLine(x + f.X, baseline - face.Ascent, f.Width, thickness, c, d.Style)
                    }
                }
            case .atomic:
                paintBox(f.Box, x: x, y: y, skipBackground: 0)
            }
        }
        for r in reselected {
            items.append(.clip(r.rect))
            for f in line.Fragments where f.Kind == .text && f.Run.Count > 0 {
                items.append(.text(x + f.X, y + f.Y + f.Ascent, f.Run, color(r.color), f.Owner.Style.LetterSpacing))
            }
            items.append(PaintItem.unclip)
        }
    }

    /// A line of text decoration from (x, y) along width, in a style:
    /// double as two lines, dotted and dashed as marks, wavy as a wave.
    func decorationLine(x: float32, y: float32, width: float32, t: float32, c: draw.Color, style: string) {
        switch style {
        case "double":
            items.append(.fill(draw.Rect(x, y, width, t), c, draw.Radii.zero))
            items.append(.fill(draw.Rect(x, y + t * 2, width, t), c, draw.Radii.zero))
        case "dotted", "dashed":
            let mark = style == "dotted" ? t : t * 3
            var at: float32 = 0
            while at < width {
                items.append(.fill(draw.Rect(x + at, y, math.Min(mark, width - at), t), c, style == "dotted" ? draw.Radii(all: t / 2) : draw.Radii.zero))
                at += mark * 2
            }
        case "wavy":
            // A sine of period 4t and height 2t, a column at a time.
            let amp = t
            let period = t * 4
            var at: float32 = 0
            while at < width {
                let phase = at / period * 2 * float32(math.Pi)
                items.append(.fill(draw.Rect(x + at, y + amp + amp * math.Sin(phase), 1, t), c, draw.Radii.zero))
                at += 1
            }
        default:
            items.append(.fill(draw.Rect(x, y, width, t), c, draw.Radii.zero))
        }
    }

    /// The ::selection style text in a box takes: its own element's, or
    /// the nearest ancestor's that has one.
    func selectionStyle(box: layout.Box) -> cascade.ComputedStyle? {
        var cur: layout.Box? = box
        while let b = cur {
            if let s = b.SelectionStyle { return s }
            cur = b.Parent
        }
        return nil
    }

    /// Where a replaced element's image goes in its content box, as
    /// object-fit and object-position say.
    func objectRect(s: cascade.ComputedStyle, inner: draw.Rect, iw: float32, ih: float32) -> draw.Rect {
        if iw <= 0 || ih <= 0 { return inner }
        var w = inner.Width
        var h = inner.Height
        switch s.ObjectFit {
        case "contain", "cover", "scale-down":
            let sx = inner.Width / iw
            let sy = inner.Height / ih
            var k = s.ObjectFit == "cover" ? math.Max(sx, sy) : math.Min(sx, sy)
            if s.ObjectFit == "scale-down" && k > 1 { k = 1 }
            w = iw * k
            h = ih * k
        case "none":
            w = iw
            h = ih
        default:
            return inner
        }
        let x = inner.X + (inner.Width - w) * s.ObjectPositionX + s.ObjectOffsetX
        let y = inner.Y + (inner.Height - h) * s.ObjectPositionY + s.ObjectOffsetY
        return draw.Rect(x, y, w, h)
    }

    /// Paints what a control or image shows inside its box.
    /// The controls a browser shows: a play or pause button, the time, and
    /// a track with how far it has got.
    func paintMediaBar(box: layout.Box, bar: draw.Rect, face: font.Face, accent: draw.Color?) {
        var progress = MediaProgress(time: 0, duration: 0, paused: true)
        if let n = box.Node, let p = mediaBars[n.Id] { progress = p }
        let h = bar.Height
        items.append(.fill(bar, color(draw.Color(241, 243, 244)), draw.Radii(all: h / 2)))
        let d = math.Min(h * 0.6, 32)
        let cx = bar.X + h / 2
        let cy = bar.Y + h / 2
        items.append(.fill(draw.Rect(cx - d / 2, cy - d / 2, d, d), color(accent ?? css.SystemAccent), draw.Radii(all: d / 2)))
        let tri = d * 0.36
        if progress.paused {
            // The play triangle, as steps of a narrowing bar.
            var k: float32 = 0
            while k < tri {
                let half = tri / 2 * (1 - k / tri)
                items.append(.fill(draw.Rect(cx - tri * 0.3 + k, cy - half, 1, half * 2), color(draw.Color.white), draw.Radii.zero))
                k += 1
            }
        } else {
            items.append(.fill(draw.Rect(cx - tri * 0.5, cy - tri / 2, tri * 0.33, tri), color(draw.Color.white), draw.Radii.zero))
            items.append(.fill(draw.Rect(cx + tri * 0.17, cy - tri / 2, tri * 0.33, tri), color(draw.Color.white), draw.Radii.zero))
        }
        let text = clockOf(progress.time)
        items.append(.text(bar.X + h + 4, cy + (face.Ascent - face.Descent) / 2, face.Shape(text), color(draw.Color(60, 64, 67)), 0))
        let track = MediaTrack(bar)
        if track.Width > 8 {
            items.append(.fill(draw.Rect(track.X, cy - 2, track.Width, 4), color(draw.Color(0, 0, 0, 60)), draw.Radii(all: 2)))
            if progress.duration > 0 {
                let k = float32(math.Min(progress.time / progress.duration, 1))
                items.append(.fill(draw.Rect(track.X, cy - 2, track.Width * k, 4), color(accent ?? css.SystemAccent), draw.Radii(all: 2)))
            }
        }
    }

    func paintReplaced(box: layout.Box, x: float32, y: float32) {
        let s = box.Style
        // appearance: none: a checkbox, radio, range or progress bar draws
        // nothing of its own, only what CSS gives it (its box, ::before).
        if s.Appearance == "none" {
            switch box.Replaced {
            case .checkbox, .radio, .range, .progress: return
            default: break
            }
        }
        // A box that can be resized shows a grip in its corner.
        if s.Resize != "none" && (s.ClipsOverflow || box.Replaced == .textArea) && box.Width > 12 && box.Height > 12 {
            let gx = x + box.Width - box.Border.Right - 2
            let gy = y + box.Height - box.Border.Bottom - 2
            let c = color(draw.Color(0, 0, 0, 90))
            var k: float32 = 0
            while k < 3 {
                let d = 3 + k * 3
                items.append(.fill(draw.Rect(gx - d, gy - 1, d, 1), c, draw.Radii.zero))
                k += 1
            }
        }
        let inner = draw.Rect(x + box.ContentX, y + box.ContentY, box.InnerWidth, box.InnerHeight)
        let face = s.Face
        let isFocused = box.Node != nil && box.Node!.Id == focused
        switch box.Replaced {
        case .image:
            if let img = box.Image {
                let fitted = objectRect(s, inner, float32(img.Width), float32(img.Height))
                let spills = fitted.X < inner.X || fitted.Y < inner.Y || fitted.Right > inner.Right || fitted.Bottom > inner.Bottom
                if spills { items.append(.clip(inner)) }
                items.append(.image(fitted, img, opacity))
                items[items.count - 1].Pixelated = s.ImageRendering == "pixelated" || s.ImageRendering == "crisp-edges"
                if spills { items.append(PaintItem.unclip) }
            } else {
                // No image: a faint frame, as browsers show a broken image.
                let c = color(draw.Color(200, 200, 200))
                items.append(.border(inner, draw.Edges(all: 1), [c, c, c, c], draw.Radii.zero))
                if let alt = box.Node?.GetAttribute("alt"), !alt.isEmpty {
                    let run = face.Shape(alt)
                    items.append(.clip(inner))
                    items.append(.text(inner.X + 2, inner.Y + face.Ascent + 2, run, color(s.Color), 0))
                    items.append(PaintItem.unclip)
                }
            }
        case .textInput, .textArea:
            items.append(.clip(inner))
            let textX = inner.X + 1
            var textY = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            if box.Replaced == .textArea { textY = inner.Y + face.Ascent + (face.LineHeight - face.Ascent - face.Descent) / 2 }
            var value = box.Text
            var caretX = textX
            // What an input method is composing is shown at the caret, as
            // if typed, underlined; the caret after it.
            var caret = self.caret
            var composedFrom = -1
            var composedTo = -1
            if isFocused && !composing.isEmpty {
                let bytes = [uint8](value.utf8)
                let at = caret < 0 ? bytes.count : (caret > bytes.count ? bytes.count : caret)
                value = stringOf(bytes, 0, at) + composing + stringOf(bytes, at, bytes.count)
                composedFrom = at
                composedTo = at + composing.utf8.count
                caret = composedTo
            }
            let selected = isFocused && fieldSelectionStart >= 0 && fieldSelectionEnd > fieldSelectionStart
            let highlight = draw.Color(179, 212, 252)
            // A control right to left starts its lines at the right.
            let fieldRTL = s.Direction == .rtl
            if fieldRTL { caretX = inner.Right - 1 }
            if !value.isEmpty {
                if box.Replaced == .textArea {
                    var lineY = textY
                    var lineStart = 0
                    let bytes = [uint8](value.utf8)
                    var i = 0
                    var caretPlaced = false
                    while i <= bytes.count {
                        if i == bytes.count || bytes[i] == 10 {
                            let lineText = stringOf(bytes, lineStart, i)
                            let run = face.Shape(lineText)
                            if selected {
                                // The part of this line inside the selection.
                                let from = max(fieldSelectionStart, lineStart)
                                let to = min(fieldSelectionEnd, i)
                                if from <= to && (from < to || (fieldSelectionEnd > i && i < bytes.count)) {
                                    let a = FieldX(bytes, from: lineStart, to: i, at: from, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                                    let b = FieldX(bytes, from: lineStart, to: i, at: to, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                                    let x0 = a < b ? a : b
                                    var x1 = a < b ? b : a
                                    // A selected line break shows as a sliver.
                                    if fieldSelectionEnd > i && i < bytes.count { x1 += face.SpaceWidth }
                                    items.append(.fill(draw.Rect(x0, lineY - face.Ascent, x1 - x0, face.Ascent + face.Descent), highlight, draw.Radii.zero))
                                }
                            }
                            if run.Count > 0 { items.append(.text(FieldLineStart(lineText, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face), lineY, run, color(s.Color), 0)) }
                            if isFocused && caret >= lineStart && caret <= i && !caretPlaced {
                                caretX = FieldX(bytes, from: lineStart, to: i, at: caret, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                                caretPlaced = true
                                if caretVisible {
                                    items.append(.fill(draw.Rect(caretX, lineY - face.Ascent, 1, face.Ascent + face.Descent), color(s.CaretColor ?? s.Color), draw.Radii.zero))
                                }
                            }
                            lineY += face.LineHeight
                            lineStart = i + 1
                        }
                        i += 1
                    }
                } else {
                    let run = face.Shape(value)
                    if selected {
                        let bytes = [uint8](value.utf8)
                        let a = FieldX(bytes, from: 0, to: bytes.count, at: min(fieldSelectionStart, bytes.count), left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                        let b = FieldX(bytes, from: 0, to: bytes.count, at: min(fieldSelectionEnd, bytes.count), left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                        let x0 = a < b ? a : b
                        let x1 = a < b ? b : a
                        items.append(.fill(draw.Rect(x0, textY - face.Ascent, x1 - x0, face.Ascent + face.Descent), highlight, draw.Radii.zero))
                    }
                    items.append(.text(FieldLineStart(value, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face), textY, run, color(s.Color), 0))
                    if composedFrom >= 0 {
                        let bytes = [uint8](value.utf8)
                        let a = FieldX(bytes, from: 0, to: bytes.count, at: composedFrom, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                        let b = FieldX(bytes, from: 0, to: bytes.count, at: composedTo, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                        let x0 = a < b ? a : b
                        let x1 = a < b ? b : a
                        items.append(.fill(draw.Rect(x0, textY + 2, x1 - x0, 1), color(s.Color), draw.Radii.zero))
                    }
                    if isFocused {
                        let bytes = [uint8](value.utf8)
                        let upto = caret < 0 ? 0 : (caret > bytes.count ? bytes.count : caret)
                        caretX = FieldX(bytes, from: 0, to: bytes.count, at: upto, left: inner.X, right: inner.Right, rtl: fieldRTL, face: face)
                    }
                }
            } else if let node = box.Node, value.isEmpty, dom.IsDateTimeType(dom.InputType(node)) && !node.HasAttribute("placeholder") {
                // An empty date or time field shows its format.
                let run = face.Shape(dom.FormatHint(dom.InputType(node)))
                items.append(.text(textX, textY, run, color(draw.Color(117, 117, 117)), 0))
            } else if let placeholder = box.Node?.GetAttribute("placeholder"), !placeholder.isEmpty {
                // As ::placeholder styles it: its color, and its opacity.
                let ps = box.PlaceholderStyle
                let shown = ps?.Opacity ?? 1
                if shown > 0 {
                    let run = face.Shape(placeholder)
                    var c = color(ps?.Color ?? draw.Color(117, 117, 117))
                    if shown < 1 { c = c.Faded(shown) }
                    items.append(.text(textX, textY, run, c, 0))
                }
            }
            if isFocused && caretVisible && (value.isEmpty || box.Replaced == .textInput) {
                items.append(.fill(draw.Rect(caretX, textY - face.Ascent, 1, face.Ascent + face.Descent), color(s.CaretColor ?? s.Color), draw.Radii.zero))
            }
            items.append(PaintItem.unclip)
            // A number field's spinner: up and down, at its right.
            if let node = box.Node, dom.InputType(node) == "number" && s.Appearance != "none" && inner.Width > 30 {
                let w: float32 = 11
                let sx = inner.Right - w
                let mid = inner.Y + inner.Height / 2
                let c = color(draw.Color(90, 90, 90))
                var k: float32 = 0
                while k < 4 {
                    // Rows of a triangle up above the middle, down below.
                    items.append(.fill(draw.Rect(sx + 5.5 - k, mid - 2 - (3 - k), 1 + 2 * k, 1), c, draw.Radii.zero))
                    items.append(.fill(draw.Rect(sx + 5.5 - k, mid + 2 + (3 - k), 1 + 2 * k, 1), c, draw.Radii.zero))
                    k += 1
                }
            }
        case .button:
            let run = face.Shape(box.Text)
            let tx = inner.X + (inner.Width - run.Width) / 2
            let ty = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            items.append(.clip(inner))
            items.append(.text(tx, ty, run, color(s.Color), 0))
            items.append(PaintItem.unclip)
        case .checkbox, .radio:
            let checked = box.Node?.HasAttribute("checked") ?? false
            let radius = box.Replaced == .radio ? box.Width / 2 : s.Radii(width: box.Width, height: box.Height).TopLeft
            let rect = draw.Rect(x, y, box.Width, box.Height)
            if checked {
                let accent = color(draw.Color(0, 117, 255))
                items.append(.fill(rect, accent, draw.Radii(all: radius)))
                if box.Replaced == .radio {
                    let dot = draw.Rect(x + box.Width * 0.3, y + box.Height * 0.3, box.Width * 0.4, box.Height * 0.4)
                    items.append(.fill(dot, color(draw.Color.white), draw.Radii(all: box.Width * 0.2)))
                } else {
                    let mark = font.Load(font.Spec(family: "system-ui", size: box.Height * 0.85, weight: 700)).Shape("✓")
                    items.append(.text(x + (box.Width - mark.Width) / 2, y + box.Height * 0.8, mark, color(draw.Color.white), 0))
                }
            }
        case .listBox:
            // Its rows, the chosen ones lit, from where it has scrolled to.
            guard let node = box.Node else { break }
            let rows = layout.ListBoxItems(node)
            let rowH = layout.ListBoxRowHeight(s)
            let top = listTops[node.Id] ?? 0
            items.append(.clip(inner))
            var i = top
            var rowY = inner.Y
            while i < rows.count && rowY < inner.Bottom {
                let o = rows[i]
                if o.TagName == "optgroup" {
                    // A group's label: not a choice, and bold.
                    let boldFace = font.Load(font.Spec(families: s.FontFamilies, size: s.FontSize, weight: 700))
                    items.append(.text(inner.X + 4, rowY + 1 + face.Ascent, boldFace.Shape(o.GetAttribute("label") ?? ""), color(s.Color), 0))
                } else {
                    let off = o.HasAttribute("disabled") || (o.Parent?.TagName == "optgroup" && o.Parent!.HasAttribute("disabled"))
                    if o.HasAttribute("selected") {
                        items.append(.fill(draw.Rect(inner.X, rowY, inner.Width, rowH), color(s.AccentColor ?? css.SystemAccent), draw.Radii.zero))
                    }
                    let c = off ? draw.Color(160, 160, 160) : (o.HasAttribute("selected") ? draw.Color.white : s.Color)
                    let inset: float32 = o.Parent?.TagName == "optgroup" ? 16 : 4
                    items.append(.text(inner.X + inset, rowY + 1 + face.Ascent, face.Shape(dom.CollapseSpace(o.InnerText())), color(c), 0))
                }
                rowY += rowH
                i += 1
            }
            items.append(PaintItem.unclip)
            // A bar, where there's more than shows.
            let shown = layout.ListBoxRows(node)
            if rows.count > shown {
                let span = inner.Height * float32(shown) / float32(rows.count)
                let at = (inner.Height - span) * float32(top) / float32(rows.count - shown)
                items.append(.fill(draw.Rect(inner.Right - 5, inner.Y + at, 4, span), color(draw.Color(0, 0, 0, 80)), draw.Radii(all: 2)))
            }
        case .select:
            let run = face.Shape(box.Text)
            let ty = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            items.append(.clip(inner))
            items.append(.text(inner.X, ty, run, color(s.Color), 0))
            items.append(PaintItem.unclip)
            let arrow = face.Shape("▾")
            items.append(.text(x + box.Width - box.Border.Right - 16, ty, arrow, color(s.Color), 0))
        case .progress:
            let track = draw.Rect(x, y, box.Width, box.Height)
            items.append(.fill(track, color(draw.Color(230, 230, 230)), draw.Radii(all: box.Height / 2)))
            var fraction: float32 = 0
            if let v = box.Node?.GetAttribute("value") {
                let vb = [uint8](v.utf8)
                var max: float32 = 1
                if let m = box.Node?.GetAttribute("max") {
                    let mb = [uint8](m.utf8)
                    max = css.parseNumber(mb, 0, mb.count)
                }
                if max > 0 { fraction = clampf(css.parseNumber(vb, 0, vb.count) / max, 0, 1) }
            }
            if fraction > 0 {
                items.append(.fill(draw.Rect(x, y, box.Width * fraction, box.Height), color(draw.Color(0, 117, 255)), draw.Radii(all: box.Height / 2)))
            }
        case .range:
            guard let node = box.Node else { break }
            let rg = dom.Range(node)
            let f = float32(rg.Fraction(rg.Value(box.Text)))
            let accent = color(s.AccentColor ?? draw.Color(0, 117, 255))
            let thumb: float32 = min(16, box.Height)
            let cy = y + box.Height / 2
            let x0 = x + thumb / 2, w = box.Width - thumb
            let track = draw.Rect(x0, cy - 2, w, 4)
            items.append(.fill(track, color(draw.Color(128, 128, 140, 90)), draw.Radii(all: 2)))
            if f > 0 { items.append(.fill(draw.Rect(x0, cy - 2, w * f, 4), accent, draw.Radii(all: 2))) }
            let tx = x0 + w * f - thumb / 2
            let knob = draw.Rect(tx, cy - thumb / 2, thumb, thumb)
            let ring = draw.Rect(tx - 1, cy - thumb / 2 - 1, thumb + 2, thumb + 2)
            items.append(.fill(ring, color(draw.Color(0, 0, 0, isFocused ? 90 : 50)), draw.Radii(all: thumb / 2 + 1)))
            items.append(.fill(knob, color(draw.Color.white), draw.Radii(all: thumb / 2)))
            let dot = draw.Rect(tx + thumb * 0.3, cy - thumb * 0.2, thumb * 0.4, thumb * 0.4)
            items.append(.fill(dot, accent, draw.Radii(all: thumb * 0.2)))
        case .placeholder:
            // An embed of something the engine can't show draws nothing.
            break
        case .video:
            // The newest frame, or the poster; nothing before either.
            var picture = box.Image
            if let node = box.Node, let frame = mediaFrames[node.Id] { picture = frame }
            if let img = picture {
                let fitted = objectRect(s, inner, float32(img.Width), float32(img.Height))
                let spills = fitted.X < inner.X || fitted.Y < inner.Y || fitted.Right > inner.Right || fitted.Bottom > inner.Bottom
                if spills { items.append(.clip(inner)) }
                items.append(.image(fitted, img, opacity))
                items[items.count - 1].Pixelated = s.ImageRendering == "pixelated" || s.ImageRendering == "crisp-edges"
                if spills { items.append(PaintItem.unclip) }
            }
            if box.Node?.HasAttribute("controls") ?? false {
                paintMediaBar(box, MediaBar(box, x: x, y: y), face: face, accent: s.AccentColor)
            }
        case .frame:
            guard let node = box.Node, let sub = subpages[node.Id] else { break }
            items.append(.clip(inner))
            var t = PaintItem(.translate)
            t.X = inner.X - sub.ScrollX
            t.Y = inner.Y - sub.ScrollY
            items.append(t)
            items.append(contentsOf: sub.Items)
            items.append(PaintItem(.untranslate))
            items.append(PaintItem.unclip)
        case .colorWell:
            // A swatch of the color, inset in the box.
            let swatch = draw.Rect(inner.X + 3, inner.Y + 3, inner.Width - 6, inner.Height - 6)
            if swatch.Width > 0 && swatch.Height > 0 {
                let c = css.ParseColor(box.Text) ?? draw.Color.black
                items.append(.fill(swatch, color(c), draw.Radii(all: 2)))
                let edge = color(draw.Color(0, 0, 0, 60))
                items.append(.border(swatch, draw.Edges(all: 1), [edge, edge, edge, edge], draw.Radii(all: 2)))
            }
        case .fileInput:
            // "Choose File", as a button, then what is chosen.
            // ::file-selector-button restyles the button, where rules do.
            let bs = box.FileButtonStyle
            let bface = bs?.Face ?? face
            let label = bface.Shape("Choose File")
            let bw = label.Width + 16
            let button = draw.Rect(inner.X, inner.Y, bw, inner.Height)
            let radius = bs != nil && bs!.HasBorderRadius ? bs!.Radii(width: bw, height: inner.Height) : draw.Radii(all: 3)
            let fillColor = bs?.BackgroundColor ?? draw.Color(239, 239, 239)
            items.append(.fill(button, color(fillColor), radius))
            let edge = color(bs != nil ? borderSideColor(bs!, 0) : draw.Color(118, 118, 118))
            let edgeWidth = bs != nil ? bs!.BorderTopWidth : 1
            if edgeWidth > 0 { items.append(.border(button, draw.Edges(all: edgeWidth), [edge, edge, edge, edge], radius)) }
            let ty = inner.Y + (inner.Height - bface.LineHeight) / 2 + bface.Ascent
            items.append(.text(button.X + 8, ty, label, color(bs?.Color ?? draw.Color.black), 0))
            let ty2 = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            items.append(.clip(inner))
            items.append(.text(button.Right + 8, ty2, face.Shape(box.Text), color(s.Color), 0))
            items.append(PaintItem.unclip)
        case .audio:
            paintMediaBar(box, inner, face: face, accent: s.AccentColor)
        case .svg:
            guard let v = box.Vector, !v.IsEmpty else { break }
            let st = box.Style
            var item = PaintItem(.vector)
            item.Rect = draw.Rect(x + box.Padding.Left + box.Border.Left, y + box.Padding.Top + box.Border.Top,
                                  box.Width - box.Padding.Left - box.Padding.Right - box.Border.Left - box.Border.Right,
                                  box.Height - box.Padding.Top - box.Padding.Bottom - box.Border.Top - box.Border.Bottom)
            item.Vector = v
            if box.VectorIsDocument {
                // An SVG file is its own document: black is its currentColor,
                // and its fills are what it says.
                item.Color = draw.Color(0, 0, 0)
            } else {
                item.Color = color(st.Color)
                item.FillNone = st.FillNone
                if st.FillCurrent { item.Fill = color(st.Color) } else if st.Fill != draw.Color(0, 0, 0) { item.Fill = color(st.Fill) }
            }
            items.append(item)
        case .none:
            break
        }
    }

    /// Stacked boxes by z-index, then in tree order (box ids go in the
    /// order boxes were made).
    func sortStacked(list: inout [Stacked]) {
        var i = 1
        while i < list.count {
            let b = list[i]
            var j = i - 1
            while j >= 0 && (list[j].box.Style.ZIndex > b.box.Style.ZIndex || (list[j].box.Style.ZIndex == b.box.Style.ZIndex && list[j].box.Id > b.box.Id)) {
                list[j + 1] = list[j]
                j -= 1
            }
            list[j + 1] = b
            i += 1
        }
    }

}

/// Paints a display list onto a canvas: page coordinates are scaled by
/// the device scale and shifted by the view's origin and scroll.
public func Rasterize(items: [PaintItem], on base: draw.Canvas, scale: float32, originX: float32, originY: float32,
               scrollX: float32, scrollY: float32) {
    var canvas = base
    var clips: [draw.IRect] = []
    var dx = originX - scrollX * scale
    var dy = originY - scrollY * scale
    var offsets: [(float32, float32)] = []
    func device(r: draw.Rect) -> draw.IRect {
        let x0 = draw.RoundToInt(r.X * scale + dx)
        let y0 = draw.RoundToInt(r.Y * scale + dy)
        let x1 = draw.RoundToInt((r.X + r.Width) * scale + dx)
        let y1 = draw.RoundToInt((r.Y + r.Height) * scale + dy)
        return draw.IRect(x0, y0, x1 - x0, y1 - y0)
    }
    var layers: [draw.Layer?] = []
    var layerCanvases: [draw.Canvas] = []
    var layerTransforms: [draw.Affine] = []
    var layerItems: [PaintItem] = []
    var layerPlanes: [[Plane]] = []
    func inflate(r: draw.IRect, by: float32) -> draw.IRect {
        let d = int32(by + 0.5)
        return draw.IRect(r.X - d, r.Y - d, r.Width + 2 * d, r.Height + 2 * d)
    }
    for item in items {
        switch item.Kind {
        case .fill:
            let r = item.Rect
            let c = item.Color
            let radii = item.Radii
            let dr = device(r)
            if dr.IsEmpty {
                // A hairline that rounded away: keep it a pixel.
                if r.Width > 0 && r.Height > 0 && (dr.Width <= 0 || dr.Height <= 0) {
                    canvas.Fill(draw.IRect(dr.X, dr.Y, dr.Width > 0 ? dr.Width : 1, dr.Height > 0 ? dr.Height : 1), c)
                }
                continue
            }
            if radii.IsZero {
                canvas.Fill(dr, c)
            } else {
                canvas.FillRounded(dr, radii: radii.Scaled(scale), c)
            }
        case .border:
            let r = item.Rect
            let widths = item.Widths
            let colors = item.Colors
            let radii = item.Radii
            let dr = device(r)
            if dr.IsEmpty { continue }
            var w = draw.Edges(roundf(widths.Top * scale), roundf(widths.Right * scale), roundf(widths.Bottom * scale), roundf(widths.Left * scale))
            if widths.Top > 0 && w.Top < 1 { w.Top = 1 }
            if widths.Right > 0 && w.Right < 1 { w.Right = 1 }
            if widths.Bottom > 0 && w.Bottom < 1 { w.Bottom = 1 }
            if widths.Left > 0 && w.Left < 1 { w.Left = 1 }
            canvas.FillRing(dr, radii: radii.Scaled(scale), widths: w, colors: colors)
        case .text:
            let x = item.X
            let baseline = item.Y
            let run = item.Run
            let c = item.Color
            let letterSpacing = item.LetterSpacing
            if item.StrokeWidth > 0 {
                let outline = font.RunOutline(run, x: x * scale + dx, baseline: baseline * scale + dy, scale: scale, letterSpacing: letterSpacing)
                let line = outline.Stroked(draw.Stroke(width: item.StrokeWidth * scale, join: .round))
                if item.StrokeFirst { canvas.FillPath(line, item.StrokeColor) }
                canvas.FillPath(outline, c)
                if !item.StrokeFirst { canvas.FillPath(line, item.StrokeColor) }
            } else if item.Upright {
                let cx = (x + item.TileWidth / 2) * scale + dx
                let cy = (baseline - item.TileHeight) * scale + dy
                let reach = int32(item.TileWidth * scale * 1.5) + 4
                let cell = draw.IRect(int32(cx) - reach, int32(cy) - reach, reach * 2, reach * 2)
                let layer = draw.Layer(cell)
                font.DrawRun(layer.Canvas, run, x: x * scale + dx, baseline: baseline * scale + dy, scale: scale, color: c)
                let t = draw.Affine.translate(cx, cy).Concat(draw.Affine.rotate(-1.5707964)).Concat(draw.Affine.translate(-cx, -cy))
                layer.Composite(onto: canvas, transform: t)
                layer.Free()
            } else if letterSpacing == 0 {
                font.DrawRun(canvas, run, x: x * scale + dx, baseline: baseline * scale + dy, scale: scale, color: c)
            } else {
                var pen = x * scale + dx
                var i = 0
                while i < run.Glyphs.count {
                    let g = font.GlyphMask(face: run.Faces[i], glyph: run.Glyphs[i], scale: scale)
                    if !g.IsEmpty {
                        canvas.DrawMask(g.Mask, x: draw.RoundToInt(pen) + g.Left, y: draw.RoundToInt(baseline * scale + dy) - g.Top, c)
                    }
                    pen += (run.Advances[i] + letterSpacing) * scale
                    i += 1
                }
            }
        case .image:
            guard let img = item.Image else { continue }
            if item.TileWidth <= 0 {
                let dr = device(item.Rect)
                if dr.IsEmpty { continue }
                canvas.DrawImage(img, into: dr, opacity: item.Opacity, nearest: item.Pixelated)
                continue
            }
            // A background: tiles from the origin across the area, only
            // the ones that show, kept inside the box's curves.
            let area = device(item.Rect)
            if area.IsEmpty { continue }
            var tiled = canvas
            tiled.ClipTo(area)
            if tiled.Clip.IsEmpty { continue }
            let shapeRadii = item.Radii.Scaled(scale)
            let tw = item.TileWidth * scale
            let th = item.TileHeight * scale
            if tw < 1 || th < 1 { continue }
            let ox = (item.X + (item.Pinned ? scrollX : 0)) * scale + dx
            let oy = (item.Y + (item.Pinned ? scrollY : 0)) * scale + dy
            var startX = ox
            var startY = oy
            if item.RepeatX { startX = ox - c_ceilf((ox - float32(tiled.Clip.X)) / tw) * tw }
            if item.RepeatY { startY = oy - c_ceilf((oy - float32(tiled.Clip.Y)) / th) * th }
            var ty = startY
            var rows = 0
            while ty < float32(tiled.Clip.Bottom) && rows < 4096 {
                var tx = startX
                var cols = 0
                while tx < float32(tiled.Clip.Right) && cols < 4096 {
                    let x0 = draw.RoundToInt(tx)
                    let y0 = draw.RoundToInt(ty)
                    let x1 = draw.RoundToInt(tx + tw)
                    let y1 = draw.RoundToInt(ty + th)
                    tiled.DrawImage(img, into: draw.IRect(x0, y0, x1 - x0, y1 - y0), opacity: item.Opacity, shape: area, radii: shapeRadii)
                    if !item.RepeatX { break }
                    tx += tw
                    cols += 1
                }
                if !item.RepeatY { break }
                ty += th
                rows += 1
            }
        case .gradient:
            var gr = item.Rect
            if item.Pinned { gr = draw.Rect(gr.X + scrollX, gr.Y + scrollY, gr.Width, gr.Height) }
            let dr = device(gr)
            if dr.IsEmpty { continue }
            if var g = item.Gradient {
                g = g.Scaled(scale)
                canvas.FillGradient(dr, radii: item.Radii.Scaled(scale), g)
            }
        case .layer:
            // The box and as far as its blur reaches, within reach of
            // what shows.
            var reach: float32 = 0
            let filtered = device(item.Rect)
            for f in item.Filters { reach += f.Scaled(scale).ReachOver(box: filtered, originX: float32(filtered.X), originY: float32(filtered.Y)) }
            var shows = canvas.Clip
            var bounds = item.Unbounded ? shows : inflate(device(item.Rect), reach)
            if item.Matrix != nil {
                // In 3D it can land anywhere: the box and what overflows.
                let plane = inflate(device(item.Rect), reach + 256 * scale)
                let layer = draw.Layer(plane)
                layers.append(layer)
                layerCanvases.append(canvas)
                layerTransforms.append(draw.Affine.identity)
                layerItems.append(item)
                layerPlanes.append([])
                canvas = layer.Canvas
                continue
            }
            // CSS pixels to the canvas's, where the layer is: what its
            // transform is conjugated by.
            let toDevice = draw.Affine(scale, 0, 0, scale, dx, dy)
            let fromDevice = toDevice.Inverted() ?? draw.Affine.identity
            let t = toDevice.Concat(item.Transform).Concat(fromDevice)
            if !t.IsIdentity {
                // What of the untransformed content lands in the clip,
                // and of what overflows the box, up to 512 pixels out.
                guard let inv = t.Inverted() else { continue }
                let c = canvas.Clip
                let r = inv.Bounds(draw.Rect(float32(c.X), float32(c.Y), float32(c.Width), float32(c.Height)))
                shows = draw.IRect(int32(r.X) - 1, int32(r.Y) - 1, int32(r.Width) + 2, int32(r.Height) + 2)
                bounds = inflate(bounds, 512)
            }
            let area = bounds.Intersect(inflate(shows, reach))
            if area.IsEmpty {
                layers.append(nil)
                layerCanvases.append(canvas)
                // Nothing of it can show: paint into an empty clip.
                canvas.Clip = draw.IRect(0, 0, 0, 0)
                continue
            }
            let layer = draw.Layer(area)
            layers.append(layer)
            layerCanvases.append(canvas)
            layerTransforms.append(t)
            layerItems.append(item)
            layerPlanes.append([])
            canvas = layer.Canvas
        case .unlayer:
            guard let parent = layerCanvases.popLast() else { continue }
            let made = layers.popLast() ?? nil
            canvas = parent
            if let layer = made {
                let t = layerTransforms.popLast() ?? draw.Affine.identity
                var blend = draw.BlendMode.normal
                let inside = layerPlanes.popLast() ?? []
                if let effects = layerItems.popLast() {
                    let filtered = device(effects.Rect)
                    layer.Apply(effects.Filters.map { $0.Scaled(scale) }, box: filtered, originX: float32(filtered.X), originY: float32(filtered.Y))
                    applyClipAndMask(layer, effects, scale: scale, dx: dx, dy: dy)
                    blend = effects.Blend
                    if let m = effects.Matrix {
                        let toDevice = draw.Matrix4(affine: draw.Affine(scale, 0, 0, scale, dx, dy))
                        let fromDevice = draw.Matrix4(affine: draw.Affine(1 / scale, 0, 0, 1 / scale, -dx / scale, -dy / scale))
                        let onDevice = toDevice.Concat(m).Concat(fromDevice)
                        let r = device(effects.Rect)
                        let center = onDevice.Apply(float32(r.X) + float32(r.Width) / 2, float32(r.Y) + float32(r.Height) / 2)
                        var planes = [Plane(layer: layer, matrix: onDevice, depth: center.z, hidden: effects.BackfaceHidden, blend: blend)]
                        planes.append(contentsOf: inside)
                        if effects.JoinsContext && !layerPlanes.isEmpty {
                            layerPlanes[layerPlanes.count - 1].append(contentsOf: planes)
                            continue
                        }
                        // The context's planes, the farthest first.
                        var i = 1
                        while i < planes.count {
                            var j = i
                            while j > 0 && planes[j - 1].depth > planes[j].depth {
                                planes.swapAt(j - 1, j)
                                j -= 1
                            }
                            i += 1
                        }
                        var shown: [draw.DepthPlane] = []
                        for p in planes where !p.hidden || p.matrix.FacesViewer {
                            shown.append(draw.DepthPlane(plane: p.layer, matrix: p.matrix, blend: p.blend))
                        }
                        draw.CompositePlanes(shown, onto: canvas)
                        for p in planes { p.layer.Free() }
                        continue
                    }
                }
                layer.Composite(onto: canvas, transform: t, blend: blend)
                layer.Free()
            }
        case .borderImage:
            let r = item.Rect
            let area = draw.Rect(r.X * scale + dx, r.Y * scale + dy, r.Width * scale, r.Height * scale)
            let w = item.Widths
            let widths = draw.Edges(w.Top * scale, w.Right * scale, w.Bottom * scale, w.Left * scale)
            if let img = item.Image {
                canvas.DrawNineSlice(img, into: area, slice: item.Slice, widths: widths, fill: item.SliceFill,
                                     horizontal: item.SliceAcross, vertical: item.SliceDown, opacity: item.Opacity)
            } else if let v = item.Vector {
                let gw = draw.RoundToInt(item.TileWidth * scale)
                let gh = draw.RoundToInt(item.TileHeight * scale)
                if gw <= 0 || gh <= 0 { continue }
                var pixels = [uint8](repeating: 0, count: int(gw) * int(gh) * 4)
                draw.WithCanvas(&pixels, width: gw, height: gh) { gc in
                    v.Render(on: gc, into: draw.Rect(0, 0, float32(gw), float32(gh)), scale: scale,
                             currentColor: draw.Color(0, 0, 0), fill: nil, fillNone: false)
                }
                let sl = item.Slice
                canvas.DrawNineSlice(draw.Image(width: gw, height: gh, pixels: pixels), into: area,
                                     slice: draw.Edges(sl.Top * scale, sl.Right * scale, sl.Bottom * scale, sl.Left * scale),
                                     widths: widths, fill: item.SliceFill, horizontal: item.SliceAcross, vertical: item.SliceDown,
                                     opacity: item.Opacity)
            } else if var g = item.Gradient {
                // The gradient drawn at the canvas's scale, then cut as
                // an image is.
                let gw = draw.RoundToInt(area.Width)
                let gh = draw.RoundToInt(area.Height)
                if gw <= 0 || gh <= 0 { continue }
                g = g.Scaled(scale)
                var pixels = [uint8](repeating: 0, count: int(gw) * int(gh) * 4)
                draw.WithCanvas(&pixels, width: gw, height: gh) { gc in
                    gc.FillGradient(draw.IRect(0, 0, gw, gh), radii: draw.Radii.zero, g)
                }
                let sl = item.Slice
                canvas.DrawNineSlice(draw.Image(width: gw, height: gh, pixels: pixels), into: area,
                                     slice: draw.Edges(sl.Top * scale, sl.Right * scale, sl.Bottom * scale, sl.Left * scale),
                                     widths: widths, fill: item.SliceFill, horizontal: item.SliceAcross, vertical: item.SliceDown)
            }
        case .backdrop:
            let box = device(item.Rect)
            let filters = item.Filters.map { $0.Scaled(scale) }
            var reach: float32 = 0
            for f in filters { reach += f.ReachOver(box: box, originX: float32(box.X), originY: float32(box.Y)) }
            // What shows under the box, and as far round it as the blur
            // reaches, so its edges blur with what is beside them.
            let area = inflate(box, reach).Intersect(canvas.Clip)
            if area.IsEmpty || box.Intersect(canvas.Clip).IsEmpty { continue }
            let under = draw.Layer(area)
            under.CopyFrom(canvas)
            under.Apply(filters, box: box, originX: float32(box.X), originY: float32(box.Y))
            under.MaskRounded(box, radii: item.Radii.Scaled(scale))
            under.Composite(onto: canvas, transform: draw.Affine.identity)
            under.Free()
        case .mark:
            break
        case .translate:
            offsets.append((dx, dy))
            dx += item.X * scale
            dy += item.Y * scale
        case .fixed:
            // The scroll the page was drawn at, undone.
            offsets.append((dx, dy))
            dx += scrollX * scale
            dy += scrollY * scale
        case .unfix:
            if let o = offsets.popLast() {
                dx = o.0
                dy = o.1
            }
        case .untranslate:
            if let o = offsets.popLast() {
                dx = o.0
                dy = o.1
            }
        case .clip:
            clips.append(canvas.Clip)
            canvas.ClipTo(device(item.Rect))
        case .unclip:
            if let saved = clips.popLast() {
                canvas.Clip = saved
            }
        case .path:
            var outline = item.Outline
            var i = 0
            while i < outline.Points.count {
                outline.Points[i] = draw.Point(outline.Points[i].X * scale + dx, outline.Points[i].Y * scale + dy)
                i += 1
            }
            canvas.FillPath(outline, item.Color)
        case .vector:
            guard let v = item.Vector else { continue }
            let r = item.Rect
            v.Render(on: canvas, into: draw.Rect(r.X * scale + dx, r.Y * scale + dy, r.Width * scale, r.Height * scale),
                     scale: scale, currentColor: item.Color, fill: item.Fill, fillNone: item.FillNone)
        }
    }
}

/// Cuts a layer to its item's clip-path and keeps it as much as its
/// mask is opaque, in the canvas's pixels.
func applyClipAndMask(layer: draw.Layer, item: PaintItem, scale: float32, dx: float32, dy: float32) {
    func px(v: float32, d: float32) -> float32 { return v * scale + d }
    func device(r: draw.Rect) -> draw.IRect {
        let x0 = draw.RoundToInt(px(r.X, dx))
        let y0 = draw.RoundToInt(px(r.Y, dy))
        return draw.IRect(x0, y0, draw.RoundToInt(px(r.X + r.Width, dx)) - x0, draw.RoundToInt(px(r.Y + r.Height, dy)) - y0)
    }
    if let keep = item.MaskClip {
        let k = device(keep)
        layer.Mask { x, y in k.Contains(x, y) ? 255 : 0 }
    }
    if let shape = item.Shape {
        switch shape.Kind {
        case "inset":
            layer.MaskRounded(device(shape.Rect), radii: shape.Radii.Scaled(scale))
        case "ellipse":
            layer.MaskEllipse(cx: px(shape.CX, dx), cy: px(shape.CY, dy), rx: shape.RX * scale, ry: shape.RY * scale)
        case "polygon":
            var points: [draw.Point] = []
            for p in shape.Points { points.append(draw.Point(px(p.X, dx), px(p.Y, dy))) }
            layer.MaskPolygon(points)
        default:
            // path() and shape(): the contours in the canvas's pixels,
            // filled into a layer of their own that keeps this one.
            var path = draw.Path()
            let pts = shape.Path.Points
            let starts = shape.Path.Starts
            var c = 0
            while c < starts.count {
                let from = starts[c]
                let to = c + 1 < starts.count ? starts[c + 1] : pts.count
                var i = from
                while i < to {
                    if i == from { path.MoveTo(px(pts[i].X, dx), px(pts[i].Y, dy)) } else { path.LineTo(px(pts[i].X, dx), px(pts[i].Y, dy)) }
                    i += 1
                }
                path.Close()
                c += 1
            }
            let alpha = draw.Layer(layer.Rect)
            alpha.Canvas.FillPath(path, rule: shape.EvenOdd ? .evenOdd : .nonZero, draw.Color(0, 0, 0))
            layer.MaskBy(alpha)
            alpha.Free()
        }
    }
    let box = device(item.MaskRect)
    if !item.TextMask.isEmpty {
        // background-clip: text: kept where the text's glyphs are.
        let alpha = draw.Layer(layer.Rect)
        Rasterize(item.TextMask, on: alpha.Canvas, scale: scale, originX: dx, originY: dy, scrollX: 0, scrollY: 0)
        layer.MaskBy(alpha)
        alpha.Free()
    }
    if item.Gradient != nil || item.MaskImage != nil || item.MaskVector != nil {
        // The mask's tiles over its area, into a layer whose alpha (or
        // luminance) keeps this one.
        let area = box.Intersect(layer.Rect)
        let tw = item.TileWidth * scale
        let th = item.TileHeight * scale
        if area.IsEmpty || tw < 0.5 || th < 0.5 || (item.MaskImage != nil && item.MaskImage!.Width <= 0) {
            layer.Mask { _, _ in 0 }
            return
        }
        let alpha = draw.Layer(area)
        let ox = px(item.X, dx)
        let oy = px(item.Y, dy)
        var startX = ox
        var startY = oy
        if item.RepeatX { startX = ox - math.Ceil((ox - float32(area.X)) / tw) * tw }
        if item.RepeatY { startY = oy - math.Ceil((oy - float32(area.Y)) / th) * th }
        let g = item.Gradient?.Scaled(scale)
        var ty = startY
        var rows = 0
        while ty < float32(area.Bottom) && rows < 4096 {
            var tx = startX
            var cols = 0
            while tx < float32(area.Right) && cols < 4096 {
                let x0 = draw.RoundToInt(tx)
                let y0 = draw.RoundToInt(ty)
                let tile = draw.IRect(x0, y0, draw.RoundToInt(tx + tw) - x0, draw.RoundToInt(ty + th) - y0)
                if let img = item.MaskImage {
                    alpha.Canvas.DrawImage(img, into: tile)
                } else if let v = item.MaskVector {
                    v.Render(on: alpha.Canvas, into: draw.Rect(tx, ty, tw, th), scale: tw / (item.MaskVectorWidth > 0 ? item.MaskVectorWidth : 1),
                             currentColor: draw.Color(0, 0, 0), fill: nil, fillNone: false)
                } else if let gg = g {
                    alpha.Canvas.FillGradient(tile, radii: draw.Radii.zero, gg)
                }
                if !item.RepeatX { break }
                tx += tw
                cols += 1
            }
            if !item.RepeatY { break }
            ty += th
            rows += 1
        }
        if item.MaskLuminance { layer.MaskByLuminance(alpha) } else { layer.MaskBy(alpha) }
        alpha.Free()
    }
}

/// The part of a text fragment inside a selection, as byte offsets
/// into the fragment's text, or nil for none.
public func SelectedPart(f: layout.Fragment, node: html.Node, range: (start: dom.TextPosition, end: dom.TextPosition),
                  order: [int64: int]) -> (from: int, to: int)? {
    let o = order[node.Id] ?? 0
    let so = order[range.start.Node.Id] ?? 0
    let eo = order[range.end.Node.Id] ?? 0
    if o < so || o > eo { return nil }
    let length = f.Text.utf8.count
    // Fragment offsets count the box's original text; a fragment's
    // text may be shorter where spaces collapsed, so the end is
    // clamped to its length.
    var from = 0
    var to = length
    if o == so {
        from = range.start.Offset - f.Offset
        if from < 0 { from = 0 }
    }
    if o == eo {
        to = range.end.Offset - f.Offset
        if to > length { to = length }
    }
    if from >= to { return nil }
    return (from: from, to: to)
}

/// Whether painting reads an attribute itself, as a checkbox's check
/// or a field's placeholder. `web/cmd/check-deps` keeps this in step
/// with the code.
public func ReadsAttribute(name: string) -> bool {
    switch name {
    case "controls", "disabled", "selected", "label", "alt", "max", "min", "step", "placeholder", "value", "checked", "data-viewport":
        return true
    default:
        return false
    }
}
