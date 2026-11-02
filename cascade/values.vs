package cascade

import (
    "image/draw"
    "web/css"
)

public enum Display: Equatable {
    case none
    case block
    case inline
    case inlineBlock
    case flex
    case inlineFlex
    case grid
    case inlineGrid
    case listItem
    case table
    case inlineTable
    case tableRow
    case tableCell
    case tableRowGroup
    case tableHeaderGroup
    case tableFooterGroup
    case tableCaption
    case tableColumn
    case tableColumnGroup
    case contents

    /// Whether boxes of this display sit in a line with text.
    public var IsInlineLevel: bool {
        switch self {
        case .inline, .inlineBlock, .inlineFlex, .inlineGrid, .inlineTable: return true
        default: return false
        }
    }

    /// The display a float, an absolutely positioned box or a flex item
    /// takes: the block-level counterpart.
    public var Blockified: Display {
        switch self {
        case .inline, .inlineBlock: return .block
        case .inlineFlex: return .flex
        case .inlineGrid: return .grid
        case .inlineTable: return .table
        default: return self
        }
    }
}

public enum Position: Equatable {
    case `static`
    case relative
    case absolute
    case fixed
    case sticky
}

public enum FloatSide: Equatable {
    case none
    case left
    case right
}

public enum Clear: Equatable {
    case none
    case left
    case right
    case both
}

public enum BoxSizing: Equatable {
    case contentBox
    case borderBox
}

public enum BorderStyle: Equatable {
    case none
    case hidden
    case solid
    case dashed
    case dotted
    case double
    case groove
    case ridge
    case inset
    case outset

    public var Draws: bool { return self != .none && self != .hidden }
}

public enum Overflow: Equatable {
    case visible
    case hidden
    case scroll
    case auto
    case clip

    public var Clips: bool { return self != .visible }
    public var Scrolls: bool { return self == .scroll || self == .auto }
}

public enum TextAlign: Equatable {
    case start
    case end
    case left
    case right
    case center
    case justify
}

public enum WhiteSpace: Equatable {
    case normal
    case nowrap
    case pre
    case preWrap
    case preLine

    public var Collapses: bool { return self == .normal || self == .nowrap || self == .preLine }
    public var Wraps: bool { return self == .normal || self == .preWrap || self == .preLine }
    public var KeepsNewlines: bool { return self == .pre || self == .preWrap || self == .preLine }
}

public enum OverflowWrap: Equatable {
    case normal
    case breakWord
    case anywhere
}

public enum WordBreak: Equatable {
    case normal
    case breakAll
    case keepAll
}

public enum TextOverflow: Equatable {
    case clip
    case ellipsis
}

public enum TextTransform: Equatable {
    case none
    case uppercase
    case lowercase
    case capitalize
}

public enum VerticalAlign: Equatable {
    case baseline
    case middle
    case top
    case bottom
    case textTop
    case textBottom
    case sub
    case `super`
    case length(css.Length)
}

public enum ListStyleType: Equatable {
    case none
    case disc
    case circle
    case square
    case decimal
    case decimalLeadingZero
    case lowerAlpha
    case upperAlpha
    case lowerRoman
    case upperRoman
    /// A name @counter-style gave.
    case custom(string)
}

public enum ListStylePosition: Equatable {
    case outside
    case inside
}

public enum Visibility: Equatable {
    case visible
    case hidden
    case collapse
}

public enum FlexDirection: Equatable {
    case row
    case rowReverse
    case column
    case columnReverse

    public var IsRow: bool { return self == .row || self == .rowReverse }
    public var IsReverse: bool { return self == .rowReverse || self == .columnReverse }
}

public enum FlexWrap: Equatable {
    case nowrap
    case wrap
    case wrapReverse
}

public enum JustifyContent: Equatable {
    case flexStart
    case flexEnd
    case center
    case spaceBetween
    case spaceAround
    case spaceEvenly
}

public enum AlignItems: Equatable {
    case stretch
    case flexStart
    case flexEnd
    case center
    case baseline
    case auto
}

public enum LineHeight: Equatable {
    case normal
    case px(float32)
    case number(float32)
}

public enum FontStyle: Equatable {
    case normal
    case italic
    case oblique
}

/// The cursor property: CSS Basic User Interface 4's keywords.
/// pointer-events: whether the element is a target of the pointer.
public enum PointerEvents: Equatable {
    case auto
    case none
}

/// user-select: whether the user can select the element's text.
public enum UserSelect: Equatable {
    case auto
    case text
    case none
    case contain
    case all
}

public enum CursorKind: Equatable {
    case auto
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

public enum TableLayout: Equatable {
    case auto
    case fixed
}

public enum BorderCollapse: Equatable {
    case separate
    case collapse
}

/// Which lines text-decoration draws, as bits.
public struct TextDecoration: Equatable {
    public var Underline: bool = false
    public var Overline: bool = false
    public var LineThrough: bool = false
    /// text-decoration-style: solid, double, dotted, dashed or wavy.
    public var Style: string = "solid"
    /// text-decoration-thickness and text-underline-offset in pixels;
    /// negative thickness, and NaN-free -1000 offset, for auto.
    public var Thickness: float32 = -1
    public var UnderlineOffset: float32 = -1000

    public init() {}

    public static let none = TextDecoration()

    public var IsNone: bool { return !Underline && !Overline && !LineThrough }

    public func Union(o: TextDecoration) -> TextDecoration {
        var out = self
        // The decorating box's own look wins where it draws lines.
        if !o.IsNone {
            out.Style = o.Style
            out.Thickness = o.Thickness
            out.UnderlineOffset = o.UnderlineOffset
        }
        if o.Underline { out.Underline = true }
        if o.Overline { out.Overline = true }
        if o.LineThrough { out.LineThrough = true }
        return out
    }
}

public enum BackgroundSize: Equatable {
    case auto
    case cover
    case contain
    case length(css.Length, css.Length)
}

/// A background image: a picture by URL, drawn once a loader has
/// answered, or a gradient. How it repeats, where it sits and how big
/// it is come from the other background properties.
public struct BackgroundImage {
    public var URL: string
    public var Gradient: draw.LinearGradient?
    public var RepeatX: bool
    public var RepeatY: bool
    public var Size: BackgroundSize
    /// Position as fractions of the free space: 0 left/top, 0.5 centre, 1 right/bottom.
    public var PositionX: float32
    public var PositionY: float32
    /// Then moved by lengths, in CSS pixels: `0 -261px` is a sprite's
    /// slice 261 pixels down; `right 10px` is 10 pixels in from the right.
    public var OffsetX: float32 = 0
    public var OffsetY: float32 = 0
    /// Image pixels to a CSS pixel: 2 for image-set()'s `2x` candidate,
    /// which draws at half its pixel size.
    public var Density: float32 = 1

    public init(url: string) {
        URL = url
        Gradient = nil
        RepeatX = true
        RepeatY = true
        Size = .auto
        PositionX = 0
        PositionY = 0
    }

    public init(gradient: draw.LinearGradient) {
        URL = ""
        Gradient = gradient
        RepeatX = false
        RepeatY = false
        Size = .auto
        PositionX = 0
        PositionY = 0
    }

    public var IsGradient: bool { return Gradient != nil }
}

/// One shadow of box-shadow.
public struct Shadow: Equatable {
    public var X: float32
    public var Y: float32
    public var Blur: float32
    public var Spread: float32
    public var Color: draw.Color
    public var Inset: bool

    public init(x: float32, y: float32, blur: float32, spread: float32, color: draw.Color, inset: bool) {
        X = x
        Y = y
        Blur = blur
        Spread = spread
        self.Color = color
        Inset = inset
    }
}

/// direction: the inline base direction.
public enum Direction: Equatable {
    case ltr
    case rtl
}

/// unicode-bidi: how an element takes part in ordering bidirectional
/// text -- as an embedding, an isolate, an override of its characters'
/// own directions, or (plaintext) a paragraph that finds its direction
/// from its text.
public enum UnicodeBidi: Equatable {
    case normal
    case embed
    case isolate
    case bidiOverride
    case isolateOverride
    case plaintext
}

/// An inset or a size set by anchor(): its property's name, which anchor
/// ("" for position-anchor), which edge or size or percentage across, and
/// what is added.
public struct AnchorUse {
    public var Property: string
    public var Name: string
    public var Edge: string
    public var Percent: float32
    public var Offset: float32

    public init(property: string, name: string, edge: string, percent: float32, offset: float32) {
        Property = property
        Name = name
        Edge = edge
        Percent = percent
        Offset = offset
    }
}

/// An @position-try rule: what a box uses instead where it fits.
public struct PositionTry {
    public var Uses: [AnchorUse] = []
    public var Area: [string] = []
}

public var PositionTryRules: [string: PositionTry] = [:]

let fontNumericTags: [string: string] = ["lining-nums": "lnum=1", "oldstyle-nums": "onum=1", "proportional-nums": "pnum=1", "tabular-nums": "tnum=1",
    "diagonal-fractions": "frac=1", "stacked-fractions": "afrc=1", "ordinal": "ordn=1", "slashed-zero": "zero=1"]
let fontLigatureTags: [string: string] = ["none": "liga=0,clig=0,dlig=0,hlig=0,calt=0", "common-ligatures": "liga=1,clig=1", "no-common-ligatures": "liga=0,clig=0",
    "discretionary-ligatures": "dlig=1", "no-discretionary-ligatures": "dlig=0", "historical-ligatures": "hlig=1", "no-historical-ligatures": "hlig=0",
    "contextual": "calt=1", "no-contextual": "calt=0"]
let fontCapsTags: [string: string] = ["small-caps": "smcp=1", "all-small-caps": "smcp=1,c2sc=1", "petite-caps": "pcap=1", "all-petite-caps": "pcap=1,c2pc=1",
    "unicase": "unic=1", "titling-caps": "titl=1"]
let fontEastAsianTags: [string: string] = ["jis78": "jp78=1", "jis83": "jp83=1", "jis90": "jp90=1", "jis04": "jp04=1", "simplified": "smpl=1", "traditional": "trad=1",
    "full-width": "fwid=1", "proportional-width": "pwid=1", "ruby": "ruby=1"]

/// @font-feature-values' names: "stylistic/name" to its number.
public var FontFeatureValues: [string: int] = [:]

/// font-variant-alternates as tags: historical-forms, and names from
/// @font-feature-values for the functions.
func fontAlternatesSpec(words: string) -> string {
    var out: [string] = []
    for w in words.split(separator: " ").map({ string($0) }) {
        if w == "historical-forms" {
            out.append("hist=1")
            continue
        }
        let parts = w.split(separator: "(").map { string($0) }
        if parts.count != 2 { continue }
        let name = string(parts[1].dropLast())
        guard let n = FontFeatureValues["\(parts[0])/\(name)"] else { continue }
        switch parts[0] {
        case "stylistic": out.append("salt=\(n)")
        case "styleset": out.append("ss\(n < 10 ? "0" : "")\(n)=1")
        case "character-variant": out.append("cv\(n < 10 ? "0" : "")\(n)=1")
        case "swash": out.append("swsh=\(n)")
        case "ornaments": out.append("ornm=\(n)")
        case "annotation": out.append("nalt=\(n)")
        default: break
        }
    }
    return out.joined(separator: ",")
}

/// Whether the page is being laid out for paper: @media print holds, and
/// @media screen doesn't.
public var MediaIsPrint = false

/// A sheet's size and margins (top, right, bottom, left) as @page gives them;
/// 0 and empty where it says nothing.
public struct PageDescriptor {
    public var Width: float32 = 0
    public var Height: float32 = 0
    public var Margins: [float32] = []
    /// Margin boxes' text by slot ("top-center"): strings, and counter names
    /// after a mark of \u{1}.
    public var MarginBoxes: [string: [string]] = [:]
}

public var PageRule: PageDescriptor? = nil
