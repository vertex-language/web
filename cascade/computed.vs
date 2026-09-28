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
    /// filter: blur()'s radius, in CSS pixels; 0 for none.
    public var FilterBlur: float32 = 0
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
    public var Visibility: Visibility = .visible
    public var BorderCollapse: BorderCollapse = .separate
    public var BorderSpacing: float32 = 2
    public var TabSize: int32 = 8
    /// The `content` of a pseudo-element, as its parts: text, or
    /// "\u{1}name" for attr(name). Nil is none.
    public var Content: [string]? = nil
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
        ListStylePosition = parent.ListStylePosition
        Cursor = parent.Cursor
        Visibility = parent.Visibility
        BorderCollapse = parent.BorderCollapse
        BorderSpacing = parent.BorderSpacing
        TabSize = parent.TabSize
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
        let f = font.Load(font.Spec(families: FontFamilies, size: FontSize, weight: FontWeight, italic: FontStyle != .normal))
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
    public func BorderColor(_ side: int) -> draw.Color {
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
    public var ClipsOverflow: bool { return OverflowX.Clips || OverflowY.Clips }
    public var IsScrollContainer: bool { return OverflowX.Scrolls || OverflowY.Scrolls }
}
