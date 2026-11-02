package cascade

import (
    "image/draw"
    "text/font"
    "web/css"
)

/// The style an element ends up with: every property, resolved as far
/// as the cascade can without knowing the containing block. One per
/// element; text takes its parent's.
public final class ComputedStyle {
    // Box generation and placement.
    public var Display: Display = .inline
    public var Position: Position = .static
    public var Float: FloatSide = .none
    public var Clear: Clear = .none
    public var Top: css.Length = .auto
    public var Right: css.Length = .auto
    public var Bottom: css.Length = .auto
    public var Left: css.Length = .auto
    public var ZIndex: int32 = 0
    public var HasZIndex: bool = false

    // Sizing.
    public var Width: css.Length = .auto
    public var Height: css.Length = .auto
    public var MinWidth: css.Length = .px(0)
    public var MinHeight: css.Length = .px(0)
    public var MaxWidth: css.Length = .none
    public var MaxHeight: css.Length = .none
    public var BoxSizing: BoxSizing = .contentBox

    // The edges.
    public var MarginTop: css.Length = .px(0)
    public var MarginRight: css.Length = .px(0)
    public var MarginBottom: css.Length = .px(0)
    public var MarginLeft: css.Length = .px(0)
    public var PaddingTop: css.Length = .px(0)
    public var PaddingRight: css.Length = .px(0)
    public var PaddingBottom: css.Length = .px(0)
    public var PaddingLeft: css.Length = .px(0)
    public var BorderTopWidth: float32 = 0
    public var BorderRightWidth: float32 = 0
    public var BorderBottomWidth: float32 = 0
    public var BorderLeftWidth: float32 = 0
    public var BorderTopStyle: BorderStyle = .none
    public var BorderRightStyle: BorderStyle = .none
    public var BorderBottomStyle: BorderStyle = .none
    public var BorderLeftStyle: BorderStyle = .none
    public var BorderTopColor: draw.Color? = nil   // nil is currentcolor
    public var BorderRightColor: draw.Color? = nil
    public var BorderBottomColor: draw.Color? = nil
    public var BorderLeftColor: draw.Color? = nil
    public var BorderRadius: draw.Radii = draw.Radii.zero
    /// Corners given in percentages, of the box's size: resolved by
    /// Radii(width:height:) once it's known.
    public var BorderRadiusPercent: draw.Radii = draw.Radii.zero

    // Painting.
    public var BackgroundColor: draw.Color = draw.Color.transparent
    public var BackgroundImage: BackgroundImage? = nil
    public var Opacity: float32 = 1
    /// filter's functions in order, lengths in CSS pixels; empty for none.
    public var Filters: [draw.Filter] = []
    /// backdrop-filter's, the same.
    public var BackdropFilters: [draw.Filter] = []
    /// clip-path's basic shape, or nil for none.
    public var ClipPath: ClipPath? = nil
    /// mask-image: a gradient, or an image's URL; neither for none.
    public var MaskGradient: draw.LinearGradient? = nil
    public var MaskURL: string = ""
    /// mask-repeat, mask-size and mask-position, as a background layer
    /// keeps them; mask-mode.
    public var MaskLayer: BackgroundImage = emptyLayer()
    public var MaskMode: string = "match-source"
    public var BlendMode: draw.BlendMode = .normal
    /// isolation: isolate.
    public var Isolated: bool = false
    /// image-rendering (inherited); overflow-clip-margin in pixels;
    /// field-sizing; text-box-trim and text-box-edge; initial-letter's
    /// size in lines (0 for normal).
    public var ImageRendering: string = "auto"
    public var OverflowClipMargin: float32 = 0
    public var FieldSizing: string = "fixed"
    public var TextBoxTrim: string = "none"
    public var TextBoxEdge: string = "text"
    public var InitialLetter: float32 = 0
    /// writing-mode and text-orientation; whether the box's physical sizes
    /// have been swapped into the axes its vertical text is laid out in.
    public var WritingMode: string = "horizontal-tb"
    public var TextOrientation: string = "mixed"
    public var AxesSwapped: bool = false
    /// anchor-name's names; position-anchor; position-area's words; what
    /// inset and size properties anchor() set; position-try's fallbacks.
    public var AnchorNames: [string] = []
    public var PositionAnchor: string = ""
    public var PositionArea: [string] = []
    public var AnchorUses: [AnchorUse] = []
    public var PositionTries: [string] = []
    /// scroll-timeline-name, view-timeline-name, view-transition-name.
    public var ScrollTimelineName: string = ""
    public var ViewTimelineName: string = ""
    public var ViewTransitionName: string = ""
    /// clip-path: url(#id), and filter: url(#id).
    public var ClipURL: string = ""
    public var FilterURL: string = ""
    /// -webkit-text-stroke's width in pixels and color (nil for the text's);
    /// paint-order: the stroke before the fill. Inherited.
    public var TextStrokeWidth: float32 = 0
    public var TextStrokeColor: draw.Color? = nil
    public var StrokeBeforeFill: bool = false
    /// transform-box, timeline-scope's names, position-visibility.
    public var TransformBox: string = "border-box"
    public var TimelineScope: [string] = []
    public var PositionVisibility: string = "always"
    /// align-self: anchor-center, which AlignItems has no word for.
    public var AlignSelfWord: string = ""
    /// shape-outside as a clip shape, and shape-margin in pixels.
    public var ShapeOutside: ClipPath? = nil
    public var ShapeMargin: float32 = 0
    /// corner-shape, per corner from the top left: superellipse exponents as
    /// text, or "notch" or "square". Empty for all round.
    public var CornerShapes: [string] = []
    /// interpolate-size: allow-keywords: auto can transition (inherited).
    public var InterpolateKeywords: bool = false
    /// mask-origin and mask-clip.
    public var MaskOrigin: string = "border-box"
    public var MaskClip: string = "border-box"
    /// Whether it lays its items out as masonry, and which axes are subgrids.
    public var Masonry: bool = false
    public var SubgridColumns: bool = false
    public var SubgridRows: bool = false
    /// display: flow-root: its floats and margins stay inside it.
    public var FlowRoot: bool = false
    /// font-feature-settings and font-variation-settings as written; the
    /// font-variant longhands' words; font-kerning; font-stretch as a
    /// percentage; text-rendering. All inherited, all reaching the Face.
    public var FontFeatureSettings: string = ""
    public var FontVariationSettings: string = ""
    public var FontVariantNumeric: string = ""
    public var FontVariantLigatures: string = ""
    public var FontVariantCaps: string = ""
    public var FontVariantEastAsian: string = ""
    public var FontVariantAlternates: string = ""
    public var FontKerning: string = "auto"
    public var FontStretch: float32 = 100
    public var TextRendering: string = "auto"
    /// text-justify; hanging-punctuation's words; hyphens: auto.
    public var TextJustify: string = "auto"
    public var HangingPunctuation: string = "none"
    public var HyphensAuto: bool = false
    /// text-emphasis: its style's mark ("" for none), its color (nil for
    /// the text's), and whether it sits under the line.
    public var TextEmphasisMark: string = ""
    public var TextEmphasisColor: draw.Color? = nil
    public var TextEmphasisUnder: bool = false
    /// overflow-anchor: none: the box isn't what a scroll keeps its place by.
    public var NoScrollAnchor: bool = false
    /// perspective, in CSS pixels (0 for none), and where the viewer is
    /// over the box; backface-visibility: hidden; transform-style: preserve-3d.
    public var Perspective: float32 = 0
    public var PerspectiveOriginX: css.Length = .percent(50)
    public var PerspectiveOriginY: css.Length = .percent(50)
    public var BackfaceHidden: bool = false
    public var Preserve3D: bool = false
    /// border-image: its source (a URL or a gradient, neither for none),
    /// the four slices (numbers as pixels, or percentages of the image)
    /// and fill, the widths and outsets, and the horizontal and
    /// vertical repeats.
    public var BorderImageURL: string = ""
    public var BorderImageGradient: draw.LinearGradient? = nil
    public var BorderImageSlice: [css.Length] = [.percent(100), .percent(100), .percent(100), .percent(100)]
    public var BorderImageFill: bool = false
    public var BorderImageWidths: [BorderImageSide] = [.times(1), .times(1), .times(1), .times(1)]
    public var BorderImageOutsets: [BorderImageSide] = [.times(0), .times(0), .times(0), .times(0)]
    public var BorderImageRepeat: [string] = ["stretch", "stretch"]

    /// Multi-column: column-count (0 for auto), column-width (nil for
    /// auto), the rule between columns, whether the columns balance,
    /// and whether column-gap is normal (1em here).
    public var ColumnCount: int32 = 0
    public var ColumnWidth: float32? = nil
    public var ColumnRuleWidth: float32 = 3
    public var ColumnRuleStyle: BorderStyle = .none
    public var ColumnRuleColor: draw.Color? = nil
    public var ColumnBalance: bool = true
    public var ColumnGapNormal: bool = true
    public var ColumnSpanAll: bool = false
    /// break-inside: avoid and its kin.
    public var BreakInsideAvoid: bool = false
    /// break-before and break-after: a forced break (column, page and
    /// the rest) or avoid; orphans and widows, inherited: the fewest
    /// lines of a block a break may leave at a column's end or start.
    public var BreakBefore: string = "auto"
    public var BreakAfter: string = "auto"
    public var Orphans: int32 = 2
    public var Widows: int32 = 2
    /// box-decoration-break: clone draws the whole border and padding on
    /// each fragment of a split box; slice cuts them.
    public var DecorationClone: bool = false

    /// background-attachment: scroll, fixed (to the viewport) or local
    /// (with a scroll container's content).
    public var BackgroundAttachment: string = "scroll"
    /// -webkit-text-fill-color, inherited: the color text is painted
    /// in, over color; nil for color itself.
    public var TextFillColor: draw.Color? = nil

    /// direction, which is inherited, and unicode-bidi, which isn't.
    public var Direction: Direction = .ltr
    public var UnicodeBidi: UnicodeBidi = .normal
    public var IsRightToLeft: bool { return Direction == .rtl }

    /// The containment a box has, from contain and from container-type
    /// (CSS Containment 3: a size container has size and layout
    /// containment, an inline-size one inline-size and layout).
    public var SizeContained: bool { return ContainSize || ContainerType == "size" }
    public var InlineSizeContained: bool { return SizeContained || ContainerType == "inline-size" }
    public var LayoutContained: bool { return ContainLayout || ContainerType == "size" || ContainerType == "inline-size" }

    /// Whether a block flows its content into columns.
    public var IsMultiColumn: bool {
        if ColumnCount == 0 && ColumnWidth == nil { return false }
        return !IsFlexContainer && !IsGridContainer && Display != .table && Display != .inlineTable && Display != .tableCell
    }

    public var HasBorderImage: bool { return !BorderImageURL.isEmpty || BorderImageGradient != nil }
    /// transform's functions, and the translate, rotate and scale
    /// properties, each empty for none; TransformMatrix puts them
    /// together about transform-origin.
    public var Transform: [TransformOp] = []
    public var Translate: [TransformOp] = []
    public var Rotate: [TransformOp] = []
    public var Scale: [TransformOp] = []
    public var TransformOriginX: css.Length = .percent(50)
    public var TransformOriginY: css.Length = .percent(50)
    /// The transition-* and animation-* lists (animation.vs).
    public var Transition: TransitionSpec = TransitionSpec()
    public var Animation: AnimationSpec = AnimationSpec()
    /// container-type ("normal", "size" or "inline-size") and
    /// container-name's names (container.vs).
    public var ContainerType: string = "normal"
    public var ContainerNames: [string] = []
    /// object-fit, and object-position as fractions of the free space
    /// and offsets, as background-position keeps them.
    public var ObjectFit: string = "fill"
    /// outline-style ("none" draws none) and outline-offset.
    public var OutlineStyle: string = "none"
    public var OutlineOffset: float32 = 0
    /// text-shadow's shadows, front first; they inherit.
    public var TextShadows: [Shadow] = []
    /// background-clip and background-origin: "border-box",
    /// "padding-box", "content-box" (and "text" for the clip).
    public var BackgroundClip: string = "border-box"
    public var BackgroundOrigin: string = "padding-box"
    /// grid-template-areas: each name's lines (1-based, end exclusive),
    /// and how many columns and rows the template has.
    public var GridAreas: [string: GridArea] = [:]
    public var GridAreaColumns: int32 = 0
    public var GridAreaRows: int32 = 0
    /// justify-items and justify-self: how an item sits across its grid
    /// area ("auto" for justify-self defers to the container's).
    public var JustifyItems: string = "normal"
    public var JustifySelf: string = "auto"
    /// text-wrap-style: "auto", "balance", "pretty" or "stable"; it
    /// inherits. line-clamp's lines, 0 for none.
    public var TextWrapStyle: string = "auto"
    public var LineClamp: int32 = 0
    /// scrollbar-color's thumb and track (nil for auto), and whether
    /// scrollbar-width asks for thin bars; scrollbar-color inherits.
    public var ScrollbarThumb: draw.Color? = nil
    public var ScrollbarTrack: draw.Color? = nil
    public var ScrollbarThin = false
    /// caret-color, nil for auto (the text's color); it inherits.
    public var CaretColor: draw.Color? = nil
    /// color-scheme's words ("normal", "light", "dark", "only"); it
    /// inherits, and light-dark() picks by it.
    public var ColorScheme: string = "normal"
    /// appearance: "auto", "none" (a control drawn as a plain box), or
    /// "base-select".
    public var Appearance: string = "auto"
    /// resize: "none", "both", "horizontal" or "vertical".
    public var Resize: string = "none"
    public var OverscrollX: string = "auto"
    public var OverscrollY: string = "auto"
    /// contain's kinds, and content-visibility, which hidden makes skip
    /// the content (sized by contain-intrinsic-size).
    public var ContainSize = false
    public var ContainLayout = false
    public var ContainPaint = false
    public var ContentVisibility: string = "visible"
    public var ContainIntrinsicWidth: css.Length? = nil
    public var ContainIntrinsicHeight: css.Length? = nil
    /// zoom: the element's own, and the product of its ancestors' and
    /// its own, which its lengths are multiplied by.
    public var Zoom: float32 = 1
    public var EffectiveZoom: float32 = 1
    /// will-change and touch-action's words, kept for the host.
    /// scroll-behavior, scroll-snap-type ("none", or an axis and
    /// strictness), scroll-snap-align (block then inline), and
    /// scroll-snap-stop.
    public var ScrollBehavior: string = "auto"
    public var SnapType: string = "none"
    public var SnapAlign: string = "none"
    public var SnapStop: string = "normal"
    /// scroll-padding (a snap container's) and scroll-margin (a snap
    /// target's), top, right, bottom, left.
    public var ScrollPadding: [css.Length] = [.px(0), .px(0), .px(0), .px(0)]
    public var ScrollMargin: [css.Length] = [.px(0), .px(0), .px(0), .px(0)]
    public var WillChange: string = "auto"
    public var TouchAction: string = "auto"
    public var ObjectPositionX: float32 = 0.5
    public var ObjectOffsetX: float32 = 0
    public var ObjectPositionY: float32 = 0.5
    public var ObjectOffsetY: float32 = 0
    public var OverflowX: Overflow = .visible
    public var OverflowY: Overflow = .visible
    public var Shadows: [Shadow] = []
    public var OutlineWidth: float32 = 0
    public var OutlineColor: draw.Color? = nil

    // Inline and flex.
    public var VerticalAlign: VerticalAlign = .baseline
    public var TextDecoration: TextDecoration = cascade.TextDecoration()
    public var TextDecorationColor: draw.Color? = nil
    public var FlexDirection: FlexDirection = .row
    public var FlexWrap: FlexWrap = .nowrap
    public var JustifyContent: JustifyContent = .flexStart
    public var AlignItems: AlignItems = .stretch
    public var AlignSelf: AlignItems = .auto
    public var AlignContent: JustifyContent = .flexStart
    public var FlexGrow: float32 = 0
    public var FlexShrink: float32 = 1
    public var FlexBasis: css.Length = .auto
    public var Order: int32 = 0
    public var RowGap: css.Length = .px(0)
    public var ColumnGap: css.Length = .px(0)
    public var TableLayout: TableLayout = .auto
    public var GridColumns: [css.GridTrack] = []
    public var GridRows: [css.GridTrack] = []
    public var GridAutoRows: css.GridTrack = .auto
    public var GridAutoColumns: css.GridTrack = .auto
    /// grid-auto-flow: column, filling each column before the next.
    public var GridAutoFlowColumn: bool = false
    /// aspect-ratio as width over height; 0 for auto.
    public var AspectRatio: float32 = 0
    public var GridColumn: css.GridPlacement = css.GridPlacement.auto
    public var GridRow: css.GridPlacement = css.GridPlacement.auto

    // Inherited.
    public var Color: draw.Color = draw.Color.black
    /// accent-color: what checked boxes, sliders and progress bars are
    /// drawn in; nil for auto (the system's accent).
    public var AccentColor: draw.Color? = nil
    public var FontFamilies: [string] = ["system-ui"]
    public var FontSize: float32 = 16
    public var FontWeight: int32 = 400
    public var FontStyle: FontStyle = .normal
    public var LineHeight: LineHeight = .normal
    public var TextAlign: TextAlign = .start
    public var TextTransform: TextTransform = .none
    public var TextIndent: css.Length = .px(0)
    public var LetterSpacing: float32 = 0
    public var WordSpacing: float32 = 0
    public var WhiteSpace: WhiteSpace = .normal
    public var OverflowWrap: OverflowWrap = .normal
    public var WordBreak: WordBreak = .normal
    public var TextOverflow: TextOverflow = .clip
    public var ListStyleType: ListStyleType = .disc
    public var ListStylePosition: ListStylePosition = .outside
    public var Cursor: CursorKind = .auto
    /// Inherited: the element and what is in it are not hit by the pointer,
    /// unless something in it sets auto again.
    public var PointerEvents: PointerEvents = .auto
    /// Not inherited; auto is what the parent's is (UsedUserSelect).
    public var UserSelect: UserSelect = .auto
    public var Visibility: Visibility = .visible
    /// scrollbar-width: none: a scroll container that scrolls without
    /// showing where it is.
    public var ScrollbarHidden = false
    public var BorderCollapse: BorderCollapse = .separate
    public var BorderSpacing: float32 = 2
    public var TabSize: int32 = 8
    /// The `content` of a pseudo-element, as its parts: text, or
    /// "\u{1}name" for attr(name). Nil is none.
    public var Content: [string]? = nil
    /// counter-reset, counter-increment and counter-set: the counters
    /// the element changes, in order. Not inherited.
    public var CounterReset: [CounterChange] = []
    public var CounterIncrement: [CounterChange] = []
    public var CounterSet: [CounterChange] = []
    /// quotes: open and close strings by nesting depth. Inherited; auto
    /// is English's curly quotes.
    public var Quotes: [string] = ["\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
    /// caption-side: bottom puts a table's captions under its rows.
    /// Inherited.
    public var CaptionBelow = false
    /// text-align-last: how the last line, and a line before a forced
    /// break, aligns; nil is auto (text-align, start for justify).
    /// Inherited.
    public var TextAlignLast: TextAlign? = nil
    /// hyphens: none: a soft hyphen is no place to break. Inherited.
    public var HyphensNone = false
    /// list-style-image's URL, empty for none. Inherited.
    public var ListStyleImage: string = ""
    /// empty-cells: hide leaves a cell with nothing in it undrawn, in
    /// separated borders. Inherited.
    public var HideEmptyCells = false
    /// SVG's fill, which inherits: a color, the element's color
    /// (currentColor, kept as that), or none.
    public var Fill: draw.Color = draw.Color(0, 0, 0)
    public var FillCurrent: bool = false
    public var FillNone: bool = false

    var face: font.Face? = nil
    /// The custom properties the element sees (vars.vs); they inherit.
    var customs: CustomScope? = nil

    public init() {}

    /// A style that inherits what inherits from a parent's, with every
    /// other property at its initial value.
    public init(inheriting parent: ComputedStyle) {
        Color = parent.Color
        AccentColor = parent.AccentColor
        FontFamilies = parent.FontFamilies
        FontSize = parent.FontSize
        FontWeight = parent.FontWeight
        FontStyle = parent.FontStyle
        LineHeight = parent.LineHeight
        TextAlign = parent.TextAlign
        TextTransform = parent.TextTransform
        TextIndent = parent.TextIndent
        LetterSpacing = parent.LetterSpacing
        WordSpacing = parent.WordSpacing
        WhiteSpace = parent.WhiteSpace
        OverflowWrap = parent.OverflowWrap
        WordBreak = parent.WordBreak
        ListStyleType = parent.ListStyleType
        ImageRendering = parent.ImageRendering
        WritingMode = parent.WritingMode
        TextStrokeWidth = parent.TextStrokeWidth
        TextStrokeColor = parent.TextStrokeColor
        StrokeBeforeFill = parent.StrokeBeforeFill
        InterpolateKeywords = parent.InterpolateKeywords
        FontFeatureSettings = parent.FontFeatureSettings
        FontVariationSettings = parent.FontVariationSettings
        FontVariantNumeric = parent.FontVariantNumeric
        FontVariantLigatures = parent.FontVariantLigatures
        FontVariantCaps = parent.FontVariantCaps
        FontVariantEastAsian = parent.FontVariantEastAsian
        FontVariantAlternates = parent.FontVariantAlternates
        FontKerning = parent.FontKerning
        FontStretch = parent.FontStretch
        TextRendering = parent.TextRendering
        TextJustify = parent.TextJustify
        HangingPunctuation = parent.HangingPunctuation
        HyphensAuto = parent.HyphensAuto
        TextEmphasisMark = parent.TextEmphasisMark
        TextEmphasisColor = parent.TextEmphasisColor
        TextEmphasisUnder = parent.TextEmphasisUnder
        TextOrientation = parent.TextOrientation
        ListStylePosition = parent.ListStylePosition
        Cursor = parent.Cursor
        PointerEvents = parent.PointerEvents
        Visibility = parent.Visibility
        BorderCollapse = parent.BorderCollapse
        BorderSpacing = parent.BorderSpacing
        TabSize = parent.TabSize
        Quotes = parent.Quotes
        CaptionBelow = parent.CaptionBelow
        TextAlignLast = parent.TextAlignLast
        HyphensNone = parent.HyphensNone
        ListStyleImage = parent.ListStyleImage
        HideEmptyCells = parent.HideEmptyCells
        TextShadows = parent.TextShadows
        TextWrapStyle = parent.TextWrapStyle
        ScrollbarThumb = parent.ScrollbarThumb
        ScrollbarTrack = parent.ScrollbarTrack
        CaretColor = parent.CaretColor
        TextFillColor = parent.TextFillColor
        Orphans = parent.Orphans
        Widows = parent.Widows
        ColorScheme = parent.ColorScheme
        EffectiveZoom = parent.EffectiveZoom
        Direction = parent.Direction
        customs = parent.customs
        Fill = parent.Fill
        FillCurrent = parent.FillCurrent
        FillNone = parent.FillNone
        face = nil
    }

    /// The face for the font properties, loaded the first time it is
    /// asked for. The font properties are settled by the time anything
    /// asks, so the face is kept.
    public var Face: font.Face {
        if let f = face { return f }
        var spec = font.Spec(families: FontFamilies, size: FontSize, weight: FontWeight, italic: FontStyle != .normal)
        spec.Features = FontFeatureSpec
        spec.Variations = FontVariationSpec
        let f = font.Load(spec)
        face = f
        return f
    }

    /// The line height in pixels: the face's for `normal`, a number
    /// times the font size, or what was given.
    public var LineHeightPx: float32 {
        switch LineHeight {
        case .normal: return Face.LineHeight
        case .px(let v): return v
        case .number(let n): return FontSize * n
        }
    }

    public var BorderWidths: draw.Edges {
        return draw.Edges(BorderTopWidth, BorderRightWidth, BorderBottomWidth, BorderLeftWidth)
    }

    /// The color a border side paints: its own, or the text color.
    public func BorderColor(side: int) -> draw.Color {
        switch side {
        case 0: return BorderTopColor ?? Color
        case 1: return BorderRightColor ?? Color
        case 2: return BorderBottomColor ?? Color
        default: return BorderLeftColor ?? Color
        }
    }

    public var IsPositioned: bool { return Position != .static }
    public var IsOutOfFlow: bool { return Position == .absolute || Position == .fixed || Float != .none }
    public var IsFlexContainer: bool { return Display == .flex || Display == .inlineFlex }
    public var IsGridContainer: bool { return Display == .grid || Display == .inlineGrid }
    public var HasBorderRadius: bool { return !BorderRadius.IsZero || !BorderRadiusPercent.IsZero }

    /// The corners' radii for a box of this size. A percentage takes the
    /// shorter side's share, round corners standing in for elliptical ones.
    public func Radii(width: float32, height: float32) -> draw.Radii {
        if BorderRadiusPercent.IsZero { return BorderRadius }
        let side = width < height ? width : height
        let p = BorderRadiusPercent
        let b = BorderRadius
        return draw.Radii(p.TopLeft > 0 ? p.TopLeft * side / 100 : b.TopLeft,
                          p.TopRight > 0 ? p.TopRight * side / 100 : b.TopRight,
                          p.BottomRight > 0 ? p.BottomRight * side / 100 : b.BottomRight,
                          p.BottomLeft > 0 ? p.BottomLeft * side / 100 : b.BottomLeft)
    }

    /// Whether the box clips or scrolls what overflows it.
    public var ClipsOverflow: bool { return OverflowX.Clips || OverflowY.Clips || ContainPaint || ContentVisibility == "hidden" }

    /// Whether light-dark() takes its dark color here: color-scheme says
    /// dark only, or allows dark and the page is dark.
    public func UsesDark(pageDark: bool) -> bool {
        let words = ColorScheme.split(separator: " ").map { string($0) }
        let light = words.contains("light")
        let dark = words.contains("dark")
        if dark && !light { return true }
        if light && !dark { return false }
        return pageDark
    }
    public var IsScrollContainer: bool { return OverflowX.Scrolls || OverflowY.Scrolls }
}

/// One 2D transform function with its lengths resolved but for
/// percentages, which are of the border box: translate (two lengths),
/// scale (two numbers), rotate (radians), skew (two, radians) or
/// matrix (six numbers).
public struct TransformOp {
    public var Name: string
    public var Lengths: [css.Length]
    public var Numbers: [float32]

    public init(name: string, lengths: [css.Length] = [], numbers: [float32] = []) {
        Name = name
        Lengths = lengths
        Numbers = numbers
    }

    /// The function as a matrix, for a border box of width by height.
    public func Matrix(width: float32, height: float32) -> draw.Affine {
        switch Name {
        case "translate":
            return draw.Affine.translate(Lengths[0].Resolve(width) ?? 0, Lengths[1].Resolve(height) ?? 0)
        case "scale": return draw.Affine.scale(Numbers[0], Numbers[1])
        case "rotate": return draw.Affine.rotate(Numbers[0])
        case "skew": return draw.Affine.skew(Numbers[0], Numbers[1])
        case "matrix": return draw.Affine(Numbers[0], Numbers[1], Numbers[2], Numbers[3], Numbers[4], Numbers[5])
        default: return draw.Affine.identity
        }
    }

    /// Whether the function reaches out of the plane.
    public var Is3D: bool {
        switch Name {
        case "translate3d", "scale3d", "rotate3d", "perspective", "matrix3d": return true
        default: return false
        }
    }

    /// The function as a 3D matrix, for a border box of width by height.
    public func Matrix4(width: float32, height: float32) -> draw.Matrix4 {
        switch Name {
        case "translate3d":
            return draw.Matrix4.translate(Lengths[0].Resolve(width) ?? 0, Lengths[1].Resolve(height) ?? 0, z: Lengths[2].Pixels ?? 0)
        case "scale3d": return draw.Matrix4.scale(Numbers[0], Numbers[1], Numbers[2])
        case "rotate3d": return draw.Matrix4.rotate(Numbers[0], Numbers[1], Numbers[2], radians: Numbers[3])
        case "perspective": return draw.Matrix4.perspective(Lengths[0].Pixels ?? 0)
        case "matrix3d": return draw.Matrix4(m: Numbers)
        default: return draw.Matrix4(affine: Matrix(width: width, height: height))
        }
    }
}

extension ComputedStyle {
    /// Whether any transform applies: the box paints and hits through
    /// TransformMatrix.
    /// Whether the box is painted apart and put back through a clip,
    /// a mask, a blend mode or a backdrop: it paints as a whole.
    public var HasCompositing: bool {
        return ClipPath != nil || !ClipURL.isEmpty || MaskGradient != nil || !MaskURL.isEmpty || BlendMode != .normal || Isolated || !BackdropFilters.isEmpty
    }

    /// filter: blur()'s radius, in CSS pixels; 0 for none.
    public var FilterBlur: float32 {
        for f in Filters {
            if case .blur(let r) = f { return r }
        }
        return 0
    }

    public var HasTransform: bool {
        return !Transform.isEmpty || !Translate.isEmpty || !Rotate.isEmpty || !Scale.isEmpty
    }

    /// What font-kerning, the font-variant longhands, text-rendering and
    /// font-feature-settings ask of the font, the last having the last word.
    public var FontFeatureSpec: string {
        var out: [string] = []
        func add(words: string, table: [string: string]) {
            for w in words.split(separator: " ") {
                if let tags = table[string(w)] { out.append(tags) }
            }
        }
        if FontKerning == "none" { out.append("kern=0") }
        if FontKerning == "normal" { out.append("kern=1") }
        if TextRendering == "optimizespeed" { out.append("kern=0,liga=0,clig=0") }
        add(FontVariantNumeric, table: fontNumericTags)
        add(FontVariantLigatures, table: fontLigatureTags)
        add(FontVariantCaps, table: fontCapsTags)
        add(FontVariantEastAsian, table: fontEastAsianTags)
        if !FontVariantAlternates.isEmpty {
            let spec = fontAlternatesSpec(FontVariantAlternates)
            if !spec.isEmpty { out.append(spec) }
        }
        if !FontFeatureSettings.isEmpty { out.append(FontFeatureSettings) }
        return out.joined(separator: ",")
    }

    /// font-stretch and font-variation-settings for the font's axes.
    public var FontVariationSpec: string {
        var out: [string] = []
        if FontStretch != 100 { out.append("wdth=\(FontStretch)") }
        if !FontVariationSettings.isEmpty { out.append(FontVariationSettings) }
        return out.joined(separator: ",")
    }

    /// will-change on what would make a containing block and stacking
    /// context: the box acts as though it already had one.
    public var WillChangeContains: bool {
        if WillChange == "auto" { return false }
        return WillChange.contains("transform") || WillChange.contains("perspective") || WillChange.contains("filter")
    }

    public var WillChangeStacks: bool {
        if WillChange == "auto" { return false }
        return WillChangeContains || WillChange.contains("opacity") || WillChange.contains("clip-path") || WillChange.contains("mask") || WillChange.contains("mix-blend-mode") || WillChange.contains("isolation")
    }

    /// Whether anchor positioning has anything to do with the box.
    public var IsAnchored: bool {
        return !AnchorUses.isEmpty || !PositionArea.isEmpty
    }

    /// Whether its lines run down the page.
    public var IsVertical: bool { return WritingMode != "horizontal-tb" }

    /// A vertical box is laid out as if horizontal and then turned, so
    /// what the page wrote physically goes on the side that turns to it.
    public func SwapAxesForVertical() {
        if AxesSwapped { return }
        AxesSwapped = true
        let w = Width
        Width = Height
        Height = w
        let minW = MinWidth
        MinWidth = MinHeight
        MinHeight = minW
        let maxW = MaxWidth
        MaxWidth = MaxHeight
        MaxHeight = maxW
        // Turned a quarter clockwise, the top ends up at the right; the other
        // way for sideways-lr, whose top ends up at the left.
        if WritingMode == "sideways-lr" {
            let mt = MarginTop; MarginTop = MarginLeft; MarginLeft = MarginBottom; MarginBottom = MarginRight; MarginRight = mt
            let pt = PaddingTop; PaddingTop = PaddingLeft; PaddingLeft = PaddingBottom; PaddingBottom = PaddingRight; PaddingRight = pt
            let bt = BorderTopWidth; BorderTopWidth = BorderLeftWidth; BorderLeftWidth = BorderBottomWidth; BorderBottomWidth = BorderRightWidth; BorderRightWidth = bt
            let t = Top; Top = Left; Left = Bottom; Bottom = Right; Right = t
        } else {
            let mt = MarginTop; MarginTop = MarginRight; MarginRight = MarginBottom; MarginBottom = MarginLeft; MarginLeft = mt
            let pt = PaddingTop; PaddingTop = PaddingRight; PaddingRight = PaddingBottom; PaddingBottom = PaddingLeft; PaddingLeft = pt
            let bt = BorderTopWidth; BorderTopWidth = BorderRightWidth; BorderRightWidth = BorderBottomWidth; BorderBottomWidth = BorderLeftWidth; BorderLeftWidth = bt
            let t = Top; Top = Right; Right = Bottom; Bottom = Left; Left = t
        }
    }

    /// Whether any of the box's transforms reaches out of the plane.
    public var Is3D: bool {
        for list in [Translate, Rotate, Scale, Transform] {
            for op in list where op.Is3D { return true }
        }
        return false
    }

    /// Whether the box's children keep their place in 3D: what would
    /// flatten them (a clip, a filter, opacity, a blend) wins.
    public var UsedPreserve3D: bool {
        return Preserve3D && !ClipsOverflow && Filters.isEmpty && Opacity >= 1 && !HasCompositing
    }

    /// TransformMatrix in 3D.
    public func Matrix3D(width: float32, height: float32, box: draw.Rect? = nil) -> draw.Matrix4 {
        let ox = (box?.X ?? 0) + (TransformOriginX.Resolve(box?.Width ?? width) ?? (box?.Width ?? width) / 2)
        let oy = (box?.Y ?? 0) + (TransformOriginY.Resolve(box?.Height ?? height) ?? (box?.Height ?? height) / 2)
        var m = draw.Matrix4.translate(ox, oy)
        for list in [Translate, Rotate, Scale, Transform] {
            for op in list { m = m.Concat(op.Matrix4(width: width, height: height)) }
        }
        return m.Concat(draw.Matrix4.translate(-ox, -oy))
    }

    /// The box's transform, in coordinates whose origin is its border
    /// box's top left: translate, rotate, scale and then transform, all
    /// about transform-origin.
    public func TransformMatrix(width: float32, height: float32, box: draw.Rect? = nil) -> draw.Affine {
        // transform-box: the origin's percentages are of it, from its corner.
        let ox = (box?.X ?? 0) + (TransformOriginX.Resolve(box?.Width ?? width) ?? (box?.Width ?? width) / 2)
        let oy = (box?.Y ?? 0) + (TransformOriginY.Resolve(box?.Height ?? height) ?? (box?.Height ?? height) / 2)
        var m = draw.Affine.translate(ox, oy)
        for list in [Translate, Rotate, Scale, Transform] {
            for op in list { m = m.Concat(op.Matrix(width: width, height: height)) }
        }
        return m.Concat(draw.Affine.translate(-ox, -oy))
    }
}

/// A named grid area's lines: columns ColumnStart..<ColumnEnd and rows
/// RowStart..<RowEnd, 1-based.
public struct GridArea: Equatable {
    public var RowStart: int32
    public var RowEnd: int32
    public var ColumnStart: int32
    public var ColumnEnd: int32
}

/// The areas of grid-template-areas' rows (css's "|"-joined form).
func gridAreasOf(text: string) -> (areas: [string: GridArea], columns: int32, rows: int32) {
    var areas: [string: GridArea] = [:]
    if text.isEmpty { return (areas: areas, columns: 0, rows: 0) }
    let rows = text.split(separator: "|").map { $0.split(separator: " ").map { string($0) } }
    var y: int32 = 0
    for r in rows {
        var x: int32 = 0
        for name in r {
            if name != "." {
                if var a = areas[name] {
                    if y + 2 > a.RowEnd { a.RowEnd = y + 2 }
                    if x + 2 > a.ColumnEnd { a.ColumnEnd = x + 2 }
                    areas[name] = a
                } else {
                    areas[name] = GridArea(RowStart: y + 1, RowEnd: y + 2, ColumnStart: x + 1, ColumnEnd: x + 2)
                }
            }
            x += 1
        }
        y += 1
    }
    return (areas: areas, columns: int32(rows.isEmpty ? 0 : rows[0].count), rows: int32(rows.count))
}

/// A clip-path's basic shape, its lengths resolved but for percentages,
/// which are of the box's size: Kind and Args as css.ClipShape has them,
/// with closest-side as auto and farthest-side as none.
public struct ClipPath: Equatable {
    public var Kind: string
    public var Args: [css.Length]
    /// css.ClipShape's: path data or shape() commands, the fill rule, and
    /// the reference box.
    public var Words: [string] = []
    public var Rule: string = "nonzero"
    public var Box: string = "border-box"
}

/// One side of border-image-width or border-image-outset: a length, a
/// multiple of the border's width, or (widths only) the slice's own
/// size.
public enum BorderImageSide: Equatable {
    case length(css.Length)
    case times(float32)
    case auto
}

/// A layer with no image: what mask-repeat, -size and -position start from.
func emptyLayer() -> BackgroundImage {
    return BackgroundImage(url: "")
}

/// One counter a counter-reset, -increment or -set names, and its number.
public struct CounterChange: Equatable {
    public var Name: string
    public var Value: int

    public init(name: string, value: int) {
        Name = name
        Value = value
    }
}
