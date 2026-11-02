package paint

import (
    "image/draw"
    "math"
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
func layerSize(_ size: cascade.BackgroundSize, _ area: draw.Rect, _ w: float32, _ h: float32, intrinsic: bool) -> (float32, float32) {
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
    /// blurred by Blur and put back through Transform: filter: blur()
    /// and transform. Rect is the box they are on.
    /// After the blur, a layer is cut to Shape (clip-path), kept as
    /// much as Gradient or MaskImage is opaque over MaskRect
    /// (mask-image), and mixed onto what is under it by Blend.
    case layer
    case unlayer
    /// Image (or Gradient, sized to Rect) cut by Slice and drawn round
    /// Rect, Widths in from its sides: border-image.
    case borderImage
    /// What is painted so far under Rect, blurred by Blur and kept
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
    /// A layer's blur radius, in CSS pixels.
    public var Blur: float32
    /// A layer's transform, in the page's CSS pixels.
    public var Transform: draw.Affine = draw.Affine.identity
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

    init(_ kind: PaintKind) {
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
        Blur = 0
    }

    static func fill(_ r: draw.Rect, _ c: draw.Color, _ radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.fill)
        it.Rect = r
        it.Color = c
        it.Radii = radii
        return it
    }

    static func border(_ r: draw.Rect, _ widths: draw.Edges, _ colors: [draw.Color], _ radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.border)
        it.Rect = r
        it.Widths = widths
        it.Colors = colors
        it.Radii = radii
        return it
    }

    static func text(_ x: float32, _ baseline: float32, _ run: font.Run, _ c: draw.Color, _ letterSpacing: float32) -> PaintItem {
        var it = PaintItem(.text)
        it.X = x
        it.Y = baseline
        it.Run = run
        it.Color = c
        it.LetterSpacing = letterSpacing
        return it
    }

    static func image(_ r: draw.Rect, _ img: draw.Image, _ opacity: float32) -> PaintItem {
        var it = PaintItem(.image)
        it.Rect = r
        it.Image = img
        it.Opacity = opacity
        return it
    }

    static func gradient(_ r: draw.Rect, _ g: draw.LinearGradient, _ radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.gradient)
        it.Rect = r
        it.Gradient = g
        it.Radii = radii
        return it
    }

    static func tiles(_ area: draw.Rect, _ img: draw.Image, tileWidth: float32, tileHeight: float32,
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

    static func clip(_ r: draw.Rect) -> PaintItem {
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
public func Build(_ root: layout.Box, state: State, viewportWidth: float32, viewportHeight: float32, background: draw.Color) -> [PaintItem] {
    let b = DisplayListBuilder()
    b.focused = state.Focused
    b.caret = state.Caret
    b.caretVisible = state.CaretVisible
    b.composing = state.Composing
    b.fieldSelectionStart = state.FieldSelectionStart
    b.fieldSelectionEnd = state.FieldSelectionEnd
    b.images = state.Images
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
    /// The page's SVG images by URL, for masks.
    var vectors: [string: svg.Document] = [:]
    /// The selection, if any, and each text node's place in the document.
    var selectionStart: dom.TextPosition? = nil
    var selectionEnd: dom.TextPosition? = nil
    var textOrder: [int64: int] = [:]

    init() {}

    func build(_ root: layout.Box, viewportWidth: float32, viewportHeight: float32, background: draw.Color) -> [PaintItem] {
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
        if let b = bubble { paintBubble(b.rect, b.text) }
        return items
    }

    /// A mask layer's source and tiling: mask-image over the border box
    /// (mask-origin's default), sized by mask-size, placed by
    /// mask-position, repeated by mask-repeat.
    func maskTiles(_ layer: inout PaintItem, _ s: cascade.ComputedStyle) {
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
    func paintBubble(_ control: draw.Rect, _ text: string) {
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
    func textMask(_ box: layout.Box, x: float32, y: float32) -> [PaintItem] {
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
    func paintBox(_ box: layout.Box, x parentX: float32, y parentY: float32, skipBackground: Int) {
        let s = box.Style
        if s.Visibility != .visible && !hasVisibleDescendant(box) { return }
        // Nothing of a fully transparent box or its content shows.
        if s.Opacity <= 0 { return }
        let x = parentX + box.X + box.OffsetX
        let y = parentY + box.Y + box.OffsetY
        let savedOpacity = opacity
        if s.Opacity < 1 { opacity = opacity * s.Opacity }
        let transform = s.HasTransform
            ? draw.Affine.translate(x, y).Concat(s.TransformMatrix(width: box.Width, height: box.Height)).Concat(draw.Affine.translate(-x, -y))
            : draw.Affine.identity
        // A transform that flattens the box shows nothing of it.
        if transform.Determinant == 0 { opacity = savedOpacity; return }
        if box.FixedToViewport { items.append(PaintItem(.fixed)) }
        if s.BackdropBlur > 0 {
            var b = PaintItem(.backdrop)
            b.Rect = draw.Rect(x, y, box.Width, box.Height)
            b.Radii = s.HasBorderRadius ? s.Radii(width: box.Width, height: box.Height) : draw.Radii.zero
            b.Blur = s.BackdropBlur
            items.append(b)
        }
        let blurred = s.FilterBlur > 0 || !transform.IsIdentity || s.HasCompositing
        if blurred {
            var layer = PaintItem(.layer)
            layer.Rect = draw.Rect(x, y, box.Width, box.Height)
            layer.Blur = s.FilterBlur
            layer.Transform = transform
            if s.ClipPath != nil { layer.Shape = layout.ClipRegionOf(box, x: x, y: y) }
            layer.MaskRect = layer.Rect
            if s.MaskGradient != nil || !s.MaskURL.isEmpty { maskTiles(&layer, s) }
            layer.Blend = s.BlendMode
            layer.Unbounded = s.BlendMode != .normal || s.Isolated
            items.append(layer)
        }
        let clips = s.ClipsOverflow
        if clips {
            paintBackgroundAndBorderIfVisible(box, x: x, y: y, skipBackground: skipBackground)
            items.append(.clip(draw.Rect(x + box.Border.Left, y + box.Border.Top, box.PaddingBoxWidth, box.PaddingBoxHeight)))
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
                let barX = x + box.Width - box.Border.Right - barWidth - 3
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
    }

    /// empty-cells: hide on a cell with nothing in it, borders separate.
    func isHiddenEmptyCell(_ box: layout.Box) -> bool {
        let s = box.Style
        if !s.HideEmptyCells || s.Display != .tableCell || s.BorderCollapse == .collapse { return false }
        return isEmptyContent(box)
    }

    func isEmptyContent(_ box: layout.Box) -> bool {
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

        func paintBackgroundAndBorderIfVisible(_ box: layout.Box, x: float32, y: float32, skipBackground: Int) {
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
    func paintPhase(_ box: layout.Box, _ phase: PaintPhase, x parentX: float32, y parentY: float32, skipBackground: Int, isRoot: Bool) {
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
            if phase == .inlineContent && visible { paintReplaced(box, x: x, y: y) }
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
            if child.Style.IsPositioned || child.Style.HasTransform {
                // A relative or sticky box paints as a whole, with what
                // is positioned against it, among the stacking context's
                // positioned boxes.
                if phase == .inlineContent { stacked.append(Stacked(box: child, x: sx, y: sy)) }
                continue
            }
            if child.Style.ClipsOverflow || child.Style.Opacity < 1 || child.Style.FilterBlur > 0 || child.Style.HasCompositing {
                // A clipping or translucent box paints as a whole, in
                // the phase its background would go in.
                if phase == .blockBackgrounds { paintBox(child, x: sx, y: sy, skipBackground: skipBackground) }
                continue
            }
            paintPhase(child, phase, x: sx, y: sy, skipBackground: skipBackground, isRoot: false)
        }
    }

    func paintOutline(_ box: layout.Box, x: float32, y: float32) {
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
    func paintFloatsWithin(_ box: layout.Box, x: float32, y: float32, skipBackground: Int) {
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

    func color(_ c: draw.Color) -> draw.Color {
        return opacity < 1 ? c.Faded(opacity) : c
    }

    func hasVisibleDescendant(_ box: layout.Box) -> bool {
        for c in box.Children {
            if c.Style.Visibility == .visible || hasVisibleDescendant(c) { return true }
        }
        return false
    }

    func paintBackgroundAndBorder(_ box: layout.Box, x: float32, y: float32) {
        let s = box.Style
        if !box.ColumnFragments.isEmpty {
            paintFragments(box, x: x, y: y)
            return
        }
        let rect = draw.Rect(x, y, box.Width, box.Height)
        var radii = s.Radii(width: box.Width, height: box.Height)
        if !radii.IsZero { radii = radii.Fitted(box.Width, box.Height) }
        // Shadows go under the box: each drawn as rings from the blur's
        // outer edge inward, which fades like a blur near enough.
        for sh in s.Shadows where !sh.Inset && sh.Color.A > 0 {
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
        func area(_ which: string) -> (rect: draw.Rect, radii: draw.Radii) {
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
        func background(_ clip: (rect: draw.Rect, radii: draw.Radii), textClip: bool) {
            if s.BackgroundColor.A > 0 {
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
    func borderImage(_ box: layout.Box, x: float32, y: float32) -> PaintItem? {
        let s = box.Style
        let bw = box.Border
        let border: [float32] = [bw.Top, bw.Right, bw.Bottom, bw.Left]
        func side(_ v: cascade.BorderImageSide, _ i: int, _ base: float32, _ auto: float32) -> float32 {
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

    func sliceRepeat(_ k: string) -> draw.SliceRepeat {
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
    func paintFragments(_ box: layout.Box, x: float32, y: float32) {
        let s = box.Style
        let n = box.ColumnFragments.count
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

    func styleName(_ b: cascade.BorderStyle) -> string {
        switch b {
        case .dashed: return "dashed"
        case .dotted: return "dotted"
        case .double: return "double"
        default: return "solid"
        }
    }

    /// A border or outline whose sides may be dashed, dotted or double:
    /// the solid sides as one ring, the others drawn side by side.
    func styledRing(_ rect: draw.Rect, _ widths: draw.Edges, _ colors: [draw.Color], _ radii: draw.Radii, _ styles: [string]) {
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
    func roundedStyledRing(_ rect: draw.Rect, _ widths: draw.Edges, _ colors: [draw.Color], _ radii: draw.Radii, _ styles: [string]) {
        let w = [widths.Top, widths.Right, widths.Bottom, widths.Left]
        // Corners too big for the box shrink to fit, as a solid ring's do.
        let fit = radii.Fitted(rect.Width, rect.Height)
        let corner = [fit.TopLeft, fit.TopRight, fit.BottomRight, fit.BottomLeft]
        // A side's line, `inset` in from the box's edge.
        func sideLine(_ side: int, _ inset: float32) -> [draw.Point] {
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
        func lengths(_ pts: [draw.Point]) -> [float32] {
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
        func pointAt(_ pts: [draw.Point], _ len: [float32], _ at: float32) -> draw.Point {
            var i = 1
            while i < pts.count - 1 && len[i] < at { i += 1 }
            let span = len[i] - len[i - 1]
            let f = span > 0 ? (at - len[i - 1]) / span : 0
            return draw.Point(pts[i - 1].X + (pts[i].X - pts[i - 1].X) * f, pts[i - 1].Y + (pts[i].Y - pts[i - 1].Y) * f)
        }
        // The stretch of the line from `a` to `b`, stroked `width` wide.
        func stroke(_ pts: [draw.Point], _ len: [float32], _ a: float32, _ b: float32, _ width: float32, _ c: draw.Color) {
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
    func borderSideColor(_ s: cascade.ComputedStyle, _ side: Int) -> draw.Color {
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

    func shade(_ c: draw.Color, _ f: float32) -> draw.Color {
        if f >= 1 { return c }
        return draw.Color(uint8(float32(c.R) * f), uint8(float32(c.G) * f), uint8(float32(c.B) * f), c.A)
    }

    func paintLine(_ container: layout.Box, _ line: layout.Line, x: float32, y: float32, visible: Bool, firstLine: bool = false) {
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
                            layer.Blur = sh.Blur / 2
                            items.append(layer)
                        }
                        items.append(.text(x + f.X + sh.X, y + f.Y + f.Ascent + sh.Y, f.Run, color(sh.Color), f.Owner.Style.LetterSpacing))
                        if sh.Blur > 0 { items.append(PaintItem(.unlayer)) }
                    }
                    items.append(.text(x + f.X, y + f.Y + f.Ascent, f.Run, textColor, f.Owner.Style.LetterSpacing))
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
    func decorationLine(_ x: float32, _ y: float32, _ width: float32, _ t: float32, _ c: draw.Color, _ style: string) {
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
    func selectionStyle(_ box: layout.Box) -> cascade.ComputedStyle? {
        var cur: layout.Box? = box
        while let b = cur {
            if let s = b.SelectionStyle { return s }
            cur = b.Parent
        }
        return nil
    }

    /// Where a replaced element's image goes in its content box, as
    /// object-fit and object-position say.
    func objectRect(_ s: cascade.ComputedStyle, _ inner: draw.Rect, _ iw: float32, _ ih: float32) -> draw.Rect {
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
    func paintReplaced(_ box: layout.Box, x: float32, y: float32) {
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
                                    let x0 = textX + face.Measure(stringOf(bytes, lineStart, from))
                                    var x1 = textX + face.Measure(stringOf(bytes, lineStart, to))
                                    // A selected line break shows as a sliver.
                                    if fieldSelectionEnd > i && i < bytes.count { x1 += face.SpaceWidth }
                                    items.append(.fill(draw.Rect(x0, lineY - face.Ascent, x1 - x0, face.Ascent + face.Descent), highlight, draw.Radii.zero))
                                }
                            }
                            if run.Count > 0 { items.append(.text(textX, lineY, run, color(s.Color), 0)) }
                            if isFocused && caret >= lineStart && caret <= i && !caretPlaced {
                                caretX = textX + face.Measure(stringOf(bytes, lineStart, caret))
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
                        let x0 = textX + face.Measure(stringOf(bytes, 0, min(fieldSelectionStart, bytes.count)))
                        let x1 = textX + face.Measure(stringOf(bytes, 0, min(fieldSelectionEnd, bytes.count)))
                        items.append(.fill(draw.Rect(x0, textY - face.Ascent, x1 - x0, face.Ascent + face.Descent), highlight, draw.Radii.zero))
                    }
                    items.append(.text(textX, textY, run, color(s.Color), 0))
                    if composedFrom >= 0 {
                        let bytes = [uint8](value.utf8)
                        let x0 = textX + face.Measure(stringOf(bytes, 0, composedFrom))
                        let x1 = textX + face.Measure(stringOf(bytes, 0, composedTo))
                        items.append(.fill(draw.Rect(x0, textY + 2, x1 - x0, 1), color(s.Color), draw.Radii.zero))
                    }
                    if isFocused {
                        let bytes = [uint8](value.utf8)
                        let upto = caret < 0 ? 0 : (caret > bytes.count ? bytes.count : caret)
                        caretX = textX + face.Measure(stringOf(bytes, 0, upto))
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
            // A video without a poster, and an embed of something the
            // engine can't show, draw nothing, as a browser's do before
            // loading.
            break
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
            let label = face.Shape("Choose File")
            let bw = label.Width + 16
            let button = draw.Rect(inner.X, inner.Y, bw, inner.Height)
            items.append(.fill(button, color(draw.Color(239, 239, 239)), draw.Radii(all: 3)))
            let edge = color(draw.Color(118, 118, 118))
            items.append(.border(button, draw.Edges(all: 1), [edge, edge, edge, edge], draw.Radii(all: 3)))
            let ty = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            items.append(.text(button.X + 8, ty, label, color(draw.Color.black), 0))
            items.append(.clip(inner))
            items.append(.text(button.Right + 8, ty, face.Shape(box.Text), color(s.Color), 0))
            items.append(PaintItem.unclip)
        case .audio:
            // The controls a browser shows, at rest: a play button, a
            // track, and the time.
            let bar = inner
            let h = bar.Height
            items.append(.fill(bar, color(draw.Color(241, 243, 244)), draw.Radii(all: h / 2)))
            let d = math.Min(h * 0.6, 32)
            let cx = bar.X + h / 2
            let cy = bar.Y + h / 2
            items.append(.fill(draw.Rect(cx - d / 2, cy - d / 2, d, d), color(s.AccentColor ?? css.SystemAccent), draw.Radii(all: d / 2)))
            // The play triangle, as steps of a narrowing bar.
            let tri = d * 0.36
            var k: float32 = 0
            while k < tri {
                let half = tri / 2 * (1 - k / tri)
                items.append(.fill(draw.Rect(cx - tri * 0.3 + k, cy - half, 1, half * 2), color(draw.Color.white), draw.Radii.zero))
                k += 1
            }
            let label = face.Shape("0:00")
            let tx = bar.X + h + 4
            items.append(.text(tx, cy + (face.Ascent - face.Descent) / 2, label, color(draw.Color(60, 64, 67)), 0))
            let trackX = tx + face.Measure("0:00") + 10
            let trackW = bar.Right - h / 2 - trackX
            if trackW > 8 {
                items.append(.fill(draw.Rect(trackX, cy - 2, trackW, 4), color(draw.Color(0, 0, 0, 60)), draw.Radii(all: 2)))
            }
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
    func sortStacked(_ list: inout [Stacked]) {
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
public func Rasterize(_ items: [PaintItem], on base: draw.Canvas, scale: float32, originX: float32, originY: float32,
               scrollX: float32, scrollY: float32) {
    var canvas = base
    var clips: [draw.IRect] = []
    var dx = originX - scrollX * scale
    var dy = originY - scrollY * scale
    var offsets: [(float32, float32)] = []
    func device(_ r: draw.Rect) -> draw.IRect {
        let x0 = draw.RoundToInt(r.X * scale + dx)
        let y0 = draw.RoundToInt(r.Y * scale + dy)
        let x1 = draw.RoundToInt((r.X + r.Width) * scale + dx)
        let y1 = draw.RoundToInt((r.Y + r.Height) * scale + dy)
        return draw.IRect(x0, y0, x1 - x0, y1 - y0)
    }
    var layers: [draw.Layer?] = []
    var layerCanvases: [draw.Canvas] = []
    var layerBlurs: [float32] = []
    var layerTransforms: [draw.Affine] = []
    var layerItems: [PaintItem] = []
    func inflate(_ r: draw.IRect, _ by: float32) -> draw.IRect {
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
            if letterSpacing == 0 {
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
                canvas.DrawImage(img, into: dr, opacity: item.Opacity)
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
            let reach = item.Blur * scale * 3
            var shows = canvas.Clip
            var bounds = item.Unbounded ? shows : inflate(device(item.Rect), reach)
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
            layerBlurs.append(item.Blur * scale)
            layerTransforms.append(t)
            layerItems.append(item)
            canvas = layer.Canvas
        case .unlayer:
            guard let parent = layerCanvases.popLast() else { continue }
            let made = layers.popLast() ?? nil
            canvas = parent
            if let layer = made {
                let sigma = layerBlurs.popLast() ?? 0
                let t = layerTransforms.popLast() ?? draw.Affine.identity
                layer.Blur(sigma)
                var blend = draw.BlendMode.normal
                if let effects = layerItems.popLast() {
                    applyClipAndMask(layer, effects, scale: scale, dx: dx, dy: dy)
                    blend = effects.Blend
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
            let sigma = item.Blur * scale
            // What shows under the box, and as far round it as the blur
            // reaches, so its edges blur with what is beside them.
            let area = inflate(box, sigma * 3).Intersect(canvas.Clip)
            if area.IsEmpty || box.Intersect(canvas.Clip).IsEmpty { continue }
            let under = draw.Layer(area)
            under.CopyFrom(canvas)
            under.Blur(sigma)
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
func applyClipAndMask(_ layer: draw.Layer, _ item: PaintItem, scale: float32, dx: float32, dy: float32) {
    func px(_ v: float32, _ d: float32) -> float32 { return v * scale + d }
    func device(_ r: draw.Rect) -> draw.IRect {
        let x0 = draw.RoundToInt(px(r.X, dx))
        let y0 = draw.RoundToInt(px(r.Y, dy))
        return draw.IRect(x0, y0, draw.RoundToInt(px(r.X + r.Width, dx)) - x0, draw.RoundToInt(px(r.Y + r.Height, dy)) - y0)
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
public func SelectedPart(_ f: layout.Fragment, _ node: html.Node, _ range: (start: dom.TextPosition, end: dom.TextPosition),
                  _ order: [int64: int]) -> (from: int, to: int)? {
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
public func ReadsAttribute(_ name: string) -> bool {
    switch name {
    case "alt", "max", "min", "step", "placeholder", "value", "checked", "data-viewport":
        return true
    default:
        return false
    }
}
