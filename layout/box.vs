package layout

import (
    "image/draw"
    "text/font"
    "web/cascade"
    "web/html"
    "web/svg"
)

/// What kind of box a layout box is.
public enum BoxKind: Equatable {
    /// A block-level container: its children are blocks, or lines.
    case block
    /// An inline element's box: its children flow in its parent's lines.
    case inline
    /// A run of text, which inline layout splits into fragments.
    case text
    /// An inline-level box laid out as a block inside: inline-block,
    /// inline-flex, inline-table.
    case inlineBlock
    /// An image or a form control: a box with a size of its own.
    case replaced
    /// A <br>.
    case lineBreak
}

/// What a replaced box shows.
public enum ReplacedKind: Equatable {
    case none
    case image
    case textInput
    case textArea
    case button
    case checkbox
    case radio
    case select
    case progress
    /// <input type=range>: a track and a thumb.
    case range
    case placeholder
    /// An inline <svg>, drawn from its shapes (web/svg).
    case svg
    /// A nested document: <iframe>, or an <object> or <embed> of HTML.
    /// The page lays it out and paints it in the content box.
    case frame
    /// <select multiple>, or with size: rows of options.
    case listBox
    /// <audio controls>: a bar of controls.
    case audio
    /// <video>: its newest frame or its poster, under controls if it asks.
    case video
    /// <input type=color>: a swatch of its value.
    case colorWell
    /// <input type=file>: a button and the files chosen.
    case fileInput
}

/// A box in the layout tree: an element, a run of text, or an anonymous
/// wrapper layout needs. Positions are in CSS pixels relative to the
/// parent box's border-box corner; sizes are border-box sizes.
var nextBoxId: int = 1

public final class Box {
    /// A number of its own, for telling boxes apart.
    public let Id: int
    public weak var Node: html.Node?
    public var Kind: BoxKind
    public var Style: cascade.ComputedStyle
    public var Children: [Box] = []
    public weak var Parent: Box?
    /// A box layout made with no element of its own: a block wrapping
    /// inline content beside blocks, or a list marker.
    public var IsAnonymous: bool = false

    public var X: float32 = 0
    public var Y: float32 = 0
    public var Width: float32 = 0
    public var Height: float32 = 0
    public var Margin: draw.Edges = draw.Edges.zero
    public var Border: draw.Edges = draw.Edges.zero
    public var Padding: draw.Edges = draw.Edges.zero

    /// The lines of a block container holding inline content.
    public var Lines: [Line] = []
    /// The text of a text box, whitespace as the source has it.
    public var Text: string = ""
    public var Replaced: ReplacedKind = .none
    /// The marker text of a list item: "•", "3.", "iv.".
    public var Marker: string = ""
    /// list-style-image: the marker is this image (or SVG drawing),
    /// MarkerImageSize big, in place of Marker's text.
    public var MarkerImage: draw.Image? = nil
    public var MarkerVector: svg.Drawing? = nil
    public var MarkerImageSize: draw.Size = draw.Size(0, 0)
    /// A replaced box's own size, before CSS: an image's pixels, a
    /// control's default.
    /// An <svg> box's shapes.
    public var Vector: svg.Drawing? = nil
    /// Whether Vector is an SVG file an <img> shows, which the page's CSS
    /// doesn't style, rather than an inline <svg>.
    public var VectorIsDocument: bool = false
    public var IntrinsicWidth: float32 = 0
    public var IntrinsicHeight: float32 = 0
    /// A replaced box with a ratio but no size of its own (an <svg> with
    /// only a viewBox): its automatic width is the room it has.
    public var RatioOnly: bool = false
    /// A field's ::placeholder style, for the text shown while it's empty.
    public var PlaceholderStyle: cascade.ComputedStyle? = nil
    /// ::marker's style for a list item, ::selection's for an element's
    /// text, ::first-line's for a block's first line; nil where no rule
    /// gives one.
    public var MarkerStyle: cascade.ComputedStyle? = nil
    public var SelectionStyle: cascade.ComputedStyle? = nil
    public var FirstLineStyle: cascade.ComputedStyle? = nil
    /// An <input type=file>'s ::file-selector-button, where rules give one.
    public var FileButtonStyle: cascade.ComputedStyle? = nil
    /// position-visibility has hidden it.
    public var AnchorHidden: bool = false
    /// What clip-path or mask: url(#id) names in the document, and which.
    public var EffectContent: svg.Drawing? = nil
    public var EffectIsMask: bool = false
    /// A subgrid's parent's tracks over its span, and gaps.
    public var ParentColumnTracks: [float32]? = nil
    public var ParentRowTracks: [float32]? = nil
    public var ParentColumnGap: float32 = 0
    public var ParentRowGap: float32 = 0
    /// A box that turns to vertical: the anonymous box its content is laid
    /// out in, as if horizontal. That box's turn: 1 a quarter clockwise,
    /// -1 anticlockwise, and how long it is across its lines.
    public var VerticalContent: Box? = nil
    public var QuarterTurn: int = 0
    public var BlockAxisSize: float32 = 0
    /// Where a text box's text starts in its node's, in bytes: not 0 for
    /// what follows a ::first-letter.
    public var TextStart: int = 0
    /// The image a replaced image box shows, once loaded.
    public var Image: draw.Image? = nil
    /// The baseline of the box's first line, from its top, for aligning
    /// it in a line of its parent's; nil where it has no line.
    public var Baseline: float32? = nil
    /// How far the box's content reaches past its padding box, for
    /// scrolling: the far edges of what it holds.
    public var ContentWidth: float32 = 0
    public var ContentHeight: float32 = 0
    /// Where a scroll container is scrolled to.
    public var ScrollX: float32 = 0
    public var ScrollY: float32 = 0
    /// The offset position: relative gives, sticky gives, the rest is 0.
    public var OffsetX: float32 = 0
    public var OffsetY: float32 = 0
    /// Boxes positioned absolutely against this one, laid out after it.
    public var Positioned: [Box] = []
    /// The content height known before the content is laid out, when
    /// the height is given: what children's percentages measure against.
    public var DefiniteInnerHeight: float32? = nil
    /// A multi-column box's columns as laid out: how many hold content,
    /// their width, the gap between them, and how tall they are.
    public var ColumnsUsed: int = 0
    /// Whether the box's lines were ordered by the bidi algorithm, and
    /// whether their base direction is right to left: the paragraph's
    /// direction, or for unicode-bidi: plaintext its first strong
    /// character's.
    /// A position: fixed box placed against the viewport: it stays put
    /// as the page scrolls.
    public var FixedToViewport: bool = false
    /// On the root: how far the page is scrolled, which fixed boxes
    /// undo. The page keeps it current.
    public var ViewportScrollX: float32 = 0
    public var ViewportScrollY: float32 = 0
    public var BidiLines: bool = false
    public var LinesRightToLeft: bool = false
    public var ColumnWidthUsed: float32 = 0
    public var ColumnGapUsed: float32 = 0
    public var ColumnHeightUsed: float32 = 0
    /// Where a column-rule goes, relative to the box: x down the middle
    /// of a gap, from y, Height tall (Width unused).
    public var ColumnRules: [draw.Rect] = []
    /// A block split between columns: a rectangle for each column it
    /// shows in, relative to its border box's corner, where its
    /// background and border are drawn. Empty where it is whole.
    public var ColumnFragments: [draw.Rect] = []
    /// text-box-trim from a block above whose first or last formatted line
    /// is in this box, and that block's text-box-edge.
    public var TrimFromAbove: (start: bool, end: bool, edge: string) = (start: false, end: false, edge: "")

    /// Whether the box draws something of its own: a border, padding,
    /// a background or a shadow.
    public var HasDecoration: bool {
        let s = Style
        return Border.Vertical > 0 || Border.Horizontal > 0 || Padding.Vertical > 0 || Padding.Horizontal > 0 ||
            s.BackgroundColor.A > 0 || s.BackgroundImage != nil || !s.Shadows.isEmpty
    }

    public init(kind: BoxKind, style: cascade.ComputedStyle, node: html.Node?) {
        Id = nextBoxId
        nextBoxId += 1
        Kind = kind
        Style = style
        Node = node
    }

    /// A block box, or a replaced element displayed as a block: an
    /// <img style="display:block"> takes a line of its own.
    public var IsBlockLevel: bool {
        return Kind == .block || (Kind == .replaced && !Style.Display.IsInlineLevel)
    }
    public var IsInlineLevel: bool { return !IsBlockLevel }
    public var IsReplaced: bool { return Kind == .replaced }
    public var IsAtomicInline: bool { return Kind == .inlineBlock || (Kind == .replaced && !IsBlockLevel) }

    /// The content box, relative to the border-box corner.
    public var ContentX: float32 { return Border.Left + Padding.Left }
    public var ContentY: float32 { return Border.Top + Padding.Top }
    public var InnerWidth: float32 { return Width - Border.Horizontal - Padding.Horizontal }
    public var InnerHeight: float32 { return Height - Border.Vertical - Padding.Vertical }
    public var PaddingBoxX: float32 { return Border.Left }
    public var PaddingBoxY: float32 { return Border.Top }
    public var PaddingBoxWidth: float32 { return Width - Border.Horizontal }
    public var PaddingBoxHeight: float32 { return Height - Border.Vertical }

    /// The border box as a rect at the box's position.
    public var Rect: draw.Rect { return draw.Rect(X, Y, Width, Height) }
    /// The margin box's height: what the box takes up in a block flow.
    public var OuterHeight: float32 { return Height + Margin.Vertical }
    public var OuterWidth: float32 { return Width + Margin.Horizontal }

    /// Whether the box establishes a new block formatting context: its
    /// margins do not collapse through it and floats stay inside.
    public var IsFormattingRoot: bool {
        if Kind != .block { return true }
        if Style.IsOutOfFlow || Style.ClipsOverflow || Style.IsFlexContainer || Style.IsGridContainer || Style.LayoutContained || Style.IsMultiColumn { return true }
        if Style.FlowRoot || Style.Display == .table || Style.Display == .tableCell || Style.Display == .inlineBlock { return true }
        return false
    }

    /// Whether the children flow as lines rather than blocks.
    public var HasInlineChildren: bool {
        // Floats and positioned boxes go with either; the first box in
        // the flow says which it is.
        for c in Children where c.Kind == .text || !c.Style.IsOutOfFlow {
            return c.IsInlineLevel
        }
        return false
    }

    public func AppendChild(child: Box) {
        child.Parent = self
        Children.append(child)
    }

    /// The nearest ancestor that is an element's box, for text and
    /// anonymous boxes.
    public var ElementBox: Box? {
        var cur: Box? = self
        while let b = cur {
            if !b.IsAnonymous && b.Kind != .text && b.Node != nil { return b }
            cur = b.Parent
        }
        return nil
    }

    /// The element node the box or its nearest non-anonymous ancestor
    /// belongs to.
    public var Element: html.Node? {
        return ElementBox?.Node
    }
}

/// One line of a block container's inline content.
public struct Line {
    /// The line box, relative to the container's border-box corner.
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32
    /// The baseline, from the line's top.
    public var Baseline: float32
    /// Text and atomic boxes on the line, in order.
    public var Fragments: [Fragment]
    /// The stretch of each inline element on the line, for its
    /// background and border, in tree order: outer before inner.
    public var Spans: [Span]

    public init(x: float32, y: float32, width: float32) {
        X = x
        Y = y
        Width = width
        Height = 0
        Baseline = 0
        Fragments = []
        Spans = []
    }
}

public enum FragmentKind: Equatable {
    case text
    case atomic
    case marker
}

/// A piece of a line: a run of text in one style, or an atomic box.
public struct Fragment {
    public var Kind: FragmentKind
    /// The text box, or the atomic box.
    public var Box: Box
    /// The nearest element box, whose style the text is set in.
    public var Owner: Box
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32
    /// The baseline from the fragment's top.
    public var Ascent: float32
    public var Text: string
    public var Run: font.Run
    /// Where the fragment's text starts in the box's text, in bytes,
    /// for editing and hit testing.
    public var Offset: int
    public var Decoration: cascade.TextDecoration
    public var DecorationColor: draw.Color
    /// Text set right to left: its first character is at its right.
    public var RightToLeft: bool = false

    public init(kind: FragmentKind, box: Box, owner: Box) {
        Kind = kind
        Box = box
        Owner = owner
        X = 0
        Y = 0
        Width = 0
        Height = 0
        Ascent = 0
        Text = ""
        Run = font.Run()
        Offset = 0
        Decoration = cascade.TextDecoration()
        DecorationColor = draw.Color.black
    }
}

/// The stretch of an inline element's box along one line.
public struct Span {
    public var Box: Box
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32
    /// Whether this is the element's first or last line, which is where
    /// its left and right padding, border and margin go.
    public var IsFirst: bool
    public var IsLast: bool
}
