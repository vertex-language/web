package css

import "image/draw"

/// The properties the engine knows, each a longhand. Shorthands are
/// expanded into these when a declaration is parsed.
public enum Prop: int32 {
    case display = 1
    case position
    case float
    case clear
    case top
    case right
    case bottom
    case left
    case zIndex
    case width
    case height
    case minWidth
    case minHeight
    case maxWidth
    case maxHeight
    case boxSizing
    case marginTop
    case marginRight
    case marginBottom
    case marginLeft
    case paddingTop
    case paddingRight
    case paddingBottom
    case paddingLeft
    case borderTopWidth
    case borderRightWidth
    case borderBottomWidth
    case borderLeftWidth
    case borderTopStyle
    case borderRightStyle
    case borderBottomStyle
    case borderLeftStyle
    case borderTopColor
    case borderRightColor
    case borderBottomColor
    case borderLeftColor
    case borderTopLeftRadius
    case borderTopRightRadius
    case borderBottomRightRadius
    case borderBottomLeftRadius
    case backgroundColor
    case backgroundImage
    case backgroundRepeat
    case backgroundSize
    case backgroundPosition
    case opacity
    case overflowX
    case overflowY
    case boxShadow
    case filter
    case backdropFilter
    case clipPath
    case maskImage
    case mixBlendMode
    case isolation
    case borderImageSource
    case borderImageSlice
    case borderImageWidth
    case borderImageOutset
    case borderImageRepeat
    case columnCount
    case columnWidth
    case columnRuleWidth
    case columnRuleStyle
    case columnRuleColor
    case columnFill
    case columnSpan
    case breakInside
    case direction
    case unicodeBidi
    case backgroundAttachment
    case transitionBehavior
    case maskRepeat
    case maskSize
    case maskPosition
    case maskMode
    case breakBefore
    case breakAfter
    case orphans
    case widows
    case boxDecorationBreak
    case textFillColor
    case outlineWidth
    case outlineColor
    case accentColor
    case verticalAlign
    case textDecorationLine
    case textDecorationColor
    case flexDirection
    case flexWrap
    case justifyContent
    case alignItems
    case alignSelf
    case alignContent
    case flexGrow
    case flexShrink
    case flexBasis
    case order
    case rowGap
    case columnGap
    case tableLayout
    case gridTemplateColumns
    case gridTemplateRows
    case gridAutoRows
    case gridColumnStart
    case gridColumnEnd
    case gridRowStart
    case gridRowEnd
    case gridAutoColumns
    case gridAutoFlow
    case aspectRatio
    case gridColumn
    case gridRow
    case color
    case fontFamily
    case fontSize
    case fontWeight
    case fontStyle
    case lineHeight
    case textAlign
    case textTransform
    case textIndent
    case letterSpacing
    case wordSpacing
    case whiteSpace
    case overflowWrap
    case wordBreak
    case textOverflow
    case listStyleType
    case listStylePosition
    case cursor
    case pointerEvents
    case userSelect
    case visibility
    case scrollbarWidth
    case borderCollapse
    case borderSpacing
    case tabSize
    case content
    case counterReset
    case counterIncrement
    case counterSet
    case quotes
    case fill
    case transform
    case transformOrigin
    case translate
    case rotate
    case scale
    case transitionProperty
    case transitionDuration
    case transitionTimingFunction
    case transitionDelay
    case animationName
    case animationDuration
    case animationTimingFunction
    case animationDelay
    case animationIterationCount
    case animationDirection
    case animationFillMode
    case animationPlayState
    case containerType
    case containerName
    case objectFit
    case objectPosition
    case outlineStyle
    case outlineOffset
    case textDecorationStyle
    case textDecorationThickness
    case textUnderlineOffset
    case textShadow
    case backgroundClip
    case backgroundOrigin
    case gridTemplateAreas
    case justifyItems
    case justifySelf
    case textWrapMode
    case textWrapStyle
    case whiteSpaceCollapse
    case lineClamp
    case scrollbarColor
    case scrollbarGutter
    case caretColor
    case colorScheme
    case appearance
    case resize
    case willChange
    case touchAction
    case overscrollBehaviorX
    case overscrollBehaviorY
    case contain
    case contentVisibility
    case containIntrinsicWidth
    case containIntrinsicHeight
    case zoom
    case scrollBehavior
    case scrollSnapType
    case scrollSnapAlign
    case scrollSnapStop
    case scrollPaddingTop
    case scrollPaddingRight
    case scrollPaddingBottom
    case scrollPaddingLeft
    case scrollMarginTop
    case scrollMarginRight
    case scrollMarginBottom
    case scrollMarginLeft
}

/// A unit a length was written in.
public enum Unit: Equatable {
    case px
    case em
    case rem
    case ex
    case ch
    case vw
    case vh
    case vmin
    case vmax
    case percent
    /// The query container's width, height, and the smaller and larger.
    case cqw
    case cqh
    case cqmin
    case cqmax
    /// The element's line height, and the root's.
    case lh
    case rlh
}

/// A declaration's value as parsed: typed, but with lengths still in
/// their units, since em and rem depend on the element it lands on.
public enum Value {
    case auto
    case none
    case normal
    case length(float32, Unit)
    /// calc(): terms in their units, summed at apply time.
    case calc([CalcTerm])
    case number(float32)
    case keyword(string)
    case color(draw.Color)
    /// light-dark(): the color for a light scheme, then a dark one.
    case lightDark(draw.Color, draw.Color)
    case currentColor
    case string(string)
    case families([string])
    case url(string)
    case gradient(draw.LinearGradient)
    case shadows([ShadowValue])
    case transforms([TransformFunction])
    case tracks([GridTrack])
    case placement(GridPlacement)
    case clipShape(ClipShape)
    /// Several values, as border-image-slice's sides and the rest.
    case list([Value])
    case inherit
    case initial
}

/// A clip-path's basic shape before its lengths are resolved: Kind is
/// inset, circle, ellipse or polygon. Args are, by kind, the four insets
/// and a corner radius; a radius and the centre's x and y; two radii
/// and the centre; or each point's x then y. A radius may be the
/// keyword closest-side or farthest-side.
public struct ClipShape {
    public var Kind: string
    public var Args: [Value]
    /// path(): its path data; shape(): its commands, SVG's letters (M L
    /// H V C Q Z, lowercase for `by`), each taking its arguments from
    /// Args in turn.
    public var Words: [string] = []
    /// nonzero or evenodd, for path(), shape() and polygon().
    public var Rule: string = "nonzero"
    /// The box the shape's percentages and position are of: border-box,
    /// padding-box, content-box or margin-box.
    public var Box: string = "border-box"
}

/// One term of a calc(): a number in a unit, or unitless.
public struct CalcTerm {
    public var Number: float32
    public var Unit: Unit?
}

/// A box-shadow before its lengths are resolved.
public struct ShadowValue {
    public var X: Value
    public var Y: Value
    public var Blur: Value
    public var Spread: Value
    public var Color: draw.Color?
    public var Inset: bool
}

/// One longhand and its value, as the cascade applies it.
public struct Longhand {
    public var Prop: Prop
    public var Value: Value
    public var Important: bool
    /// Written as an inline-start or inline-end property: Prop is its
    /// side left to right, and right to left it is the other side.
    public var FlipsInRightToLeft: bool = false

    public init(_ prop: Prop, _ value: Value, important: bool = false) {
        self.Prop = prop
        self.Value = value
        self.Important = important
    }
}

let propNames: [string: Prop] = [
    "display": .display, "position": .position, "float": .float, "clear": .clear,
    "top": .top, "right": .right, "bottom": .bottom, "left": .left, "z-index": .zIndex,
    "width": .width, "height": .height, "min-width": .minWidth, "min-height": .minHeight,
    "max-width": .maxWidth, "max-height": .maxHeight, "box-sizing": .boxSizing,
    "margin-top": .marginTop, "margin-right": .marginRight, "margin-bottom": .marginBottom, "margin-left": .marginLeft,
    "padding-top": .paddingTop, "padding-right": .paddingRight, "padding-bottom": .paddingBottom, "padding-left": .paddingLeft,
    "border-top-width": .borderTopWidth, "border-right-width": .borderRightWidth,
    "border-bottom-width": .borderBottomWidth, "border-left-width": .borderLeftWidth,
    "border-top-style": .borderTopStyle, "border-right-style": .borderRightStyle,
    "border-bottom-style": .borderBottomStyle, "border-left-style": .borderLeftStyle,
    "border-top-color": .borderTopColor, "border-right-color": .borderRightColor,
    "border-bottom-color": .borderBottomColor, "border-left-color": .borderLeftColor,
    "border-top-left-radius": .borderTopLeftRadius, "border-top-right-radius": .borderTopRightRadius,
    "border-bottom-right-radius": .borderBottomRightRadius, "border-bottom-left-radius": .borderBottomLeftRadius,
    "background-color": .backgroundColor, "background-image": .backgroundImage, "opacity": .opacity,
    "background-repeat": .backgroundRepeat, "background-size": .backgroundSize, "background-position": .backgroundPosition,
    "overflow-x": .overflowX, "overflow-y": .overflowY, "box-shadow": .boxShadow, "filter": .filter, "-webkit-filter": .filter,
    "backdrop-filter": .backdropFilter, "-webkit-backdrop-filter": .backdropFilter,
    "clip-path": .clipPath, "-webkit-clip-path": .clipPath,
    "mask-image": .maskImage, "-webkit-mask-image": .maskImage,
    "mix-blend-mode": .mixBlendMode, "isolation": .isolation,
    "border-image-source": .borderImageSource, "border-image-slice": .borderImageSlice,
    "border-image-width": .borderImageWidth, "border-image-outset": .borderImageOutset,
    "border-image-repeat": .borderImageRepeat,
    "column-count": .columnCount, "column-width": .columnWidth, "column-rule-width": .columnRuleWidth,
    "column-rule-style": .columnRuleStyle, "column-rule-color": .columnRuleColor, "column-fill": .columnFill,
    "column-span": .columnSpan, "break-inside": .breakInside, "page-break-inside": .breakInside,
    "direction": .direction, "unicode-bidi": .unicodeBidi,
    "background-attachment": .backgroundAttachment, "transition-behavior": .transitionBehavior,
    "mask-repeat": .maskRepeat, "-webkit-mask-repeat": .maskRepeat, "mask-size": .maskSize, "-webkit-mask-size": .maskSize,
    "mask-position": .maskPosition, "-webkit-mask-position": .maskPosition, "mask-mode": .maskMode,
    "break-before": .breakBefore, "break-after": .breakAfter, "page-break-before": .breakBefore, "page-break-after": .breakAfter,
    "orphans": .orphans, "widows": .widows,
    "box-decoration-break": .boxDecorationBreak, "-webkit-box-decoration-break": .boxDecorationBreak,
    "-webkit-text-fill-color": .textFillColor, "text-fill-color": .textFillColor,
    "transform": .transform, "-webkit-transform": .transform, "transform-origin": .transformOrigin,
    "-webkit-transform-origin": .transformOrigin, "translate": .translate, "rotate": .rotate, "scale": .scale,
    "transition-property": .transitionProperty, "transition-duration": .transitionDuration,
    "transition-timing-function": .transitionTimingFunction, "transition-delay": .transitionDelay,
    "animation-name": .animationName, "animation-duration": .animationDuration,
    "animation-timing-function": .animationTimingFunction, "animation-delay": .animationDelay,
    "animation-iteration-count": .animationIterationCount, "animation-direction": .animationDirection,
    "animation-fill-mode": .animationFillMode, "animation-play-state": .animationPlayState,
    "container-type": .containerType, "container-name": .containerName,
    "object-fit": .objectFit, "object-position": .objectPosition,
    "outline-style": .outlineStyle, "outline-offset": .outlineOffset,
    "text-decoration-style": .textDecorationStyle, "text-decoration-thickness": .textDecorationThickness,
    "text-underline-offset": .textUnderlineOffset, "text-shadow": .textShadow,
    "text-wrap-mode": .textWrapMode, "text-wrap-style": .textWrapStyle, "white-space-collapse": .whiteSpaceCollapse,
    "line-clamp": .lineClamp, "-webkit-line-clamp": .lineClamp,
    "scrollbar-color": .scrollbarColor, "scrollbar-gutter": .scrollbarGutter, "caret-color": .caretColor,
    "color-scheme": .colorScheme, "appearance": .appearance, "-webkit-appearance": .appearance, "resize": .resize,
    "will-change": .willChange, "touch-action": .touchAction, "overscroll-behavior-x": .overscrollBehaviorX,
    "overscroll-behavior-y": .overscrollBehaviorY, "contain": .contain, "content-visibility": .contentVisibility,
    "contain-intrinsic-width": .containIntrinsicWidth, "contain-intrinsic-height": .containIntrinsicHeight, "zoom": .zoom,
    "scroll-behavior": .scrollBehavior, "scroll-snap-type": .scrollSnapType, "scroll-snap-align": .scrollSnapAlign,
    "scroll-snap-stop": .scrollSnapStop, "scroll-padding-top": .scrollPaddingTop, "scroll-padding-right": .scrollPaddingRight,
    "scroll-padding-bottom": .scrollPaddingBottom, "scroll-padding-left": .scrollPaddingLeft,
    "scroll-margin-top": .scrollMarginTop, "scroll-margin-right": .scrollMarginRight,
    "scroll-margin-bottom": .scrollMarginBottom, "scroll-margin-left": .scrollMarginLeft,
    "grid-template-areas": .gridTemplateAreas, "justify-items": .justifyItems, "justify-self": .justifySelf,
    "background-clip": .backgroundClip, "-webkit-background-clip": .backgroundClip, "background-origin": .backgroundOrigin,
    "outline-width": .outlineWidth, "outline-color": .outlineColor, "accent-color": .accentColor,
    "vertical-align": .verticalAlign, "text-decoration-line": .textDecorationLine,
    "text-decoration-color": .textDecorationColor,
    "flex-direction": .flexDirection, "flex-wrap": .flexWrap, "justify-content": .justifyContent,
    "align-items": .alignItems, "align-self": .alignSelf, "align-content": .alignContent,
    "flex-grow": .flexGrow, "flex-shrink": .flexShrink, "flex-basis": .flexBasis, "order": .order,
    "row-gap": .rowGap, "column-gap": .columnGap, "table-layout": .tableLayout,
    "grid-template-columns": .gridTemplateColumns, "grid-template-rows": .gridTemplateRows,
    "grid-auto-rows": .gridAutoRows, "grid-column-start": .gridColumnStart, "grid-column-end": .gridColumnEnd, "grid-row-start": .gridRowStart, "grid-row-end": .gridRowEnd, "grid-auto-columns": .gridAutoColumns, "grid-auto-flow": .gridAutoFlow, "aspect-ratio": .aspectRatio, "grid-column": .gridColumn, "grid-row": .gridRow,
    "color": .color, "font-family": .fontFamily, "font-size": .fontSize, "font-weight": .fontWeight,
    "font-style": .fontStyle, "line-height": .lineHeight, "text-align": .textAlign,
    "text-transform": .textTransform, "text-indent": .textIndent, "letter-spacing": .letterSpacing,
    "word-spacing": .wordSpacing, "white-space": .whiteSpace, "list-style-type": .listStyleType,
    "overflow-wrap": .overflowWrap, "word-wrap": .overflowWrap, "word-break": .wordBreak, "text-overflow": .textOverflow,
    "list-style-position": .listStylePosition, "cursor": .cursor, "pointer-events": .pointerEvents, "user-select": .userSelect, "-webkit-user-select": .userSelect, "visibility": .visibility, "scrollbar-width": .scrollbarWidth,
    "border-collapse": .borderCollapse, "border-spacing": .borderSpacing, "tab-size": .tabSize,
    "content": .content, "counter-reset": .counterReset, "counter-increment": .counterIncrement,
    "counter-set": .counterSet, "quotes": .quotes, "fill": .fill,
]

/// Parses a declaration from a stylesheet into the longhands it sets.
/// A property the engine does not know, or a value it cannot read,
/// sets nothing, which is how a browser treats them too.
public func Longhands(_ d: Declaration) -> [Longhand] {
    var out = longhands(d)
    if isInlineLogical(d.Property) {
        var i = 0
        while i < out.count {
            out[i].FlipsInRightToLeft = true
            i += 1
        }
    }
    return out
}

/// Whether a property name is one of the inline-start and inline-end
/// ones, whose sides swap right to left.
func isInlineLogical(_ name: string) -> bool {
    if name.hasSuffix("inline-size") { return false }
    return name.contains("inline") || name.hasPrefix("border-start-") || name.hasPrefix("border-end-")
}

/// The other side of a physical property, as right to left puts an
/// inline-start one: left for right, a top-left corner for a top-right.
public func MirroredProp(_ p: Prop) -> Prop {
    switch p {
    case .marginLeft: return .marginRight
    case .marginRight: return .marginLeft
    case .paddingLeft: return .paddingRight
    case .paddingRight: return .paddingLeft
    case .left: return .right
    case .right: return .left
    case .borderLeftWidth: return .borderRightWidth
    case .borderRightWidth: return .borderLeftWidth
    case .borderLeftStyle: return .borderRightStyle
    case .borderRightStyle: return .borderLeftStyle
    case .borderLeftColor: return .borderRightColor
    case .borderRightColor: return .borderLeftColor
    case .borderTopLeftRadius: return .borderTopRightRadius
    case .borderTopRightRadius: return .borderTopLeftRadius
    case .borderBottomLeftRadius: return .borderBottomRightRadius
    case .borderBottomRightRadius: return .borderBottomLeftRadius
    default: return p
    }
}

func longhands(_ d: Declaration) -> [Longhand] {
    guard let tokens = substituteEnv(d.Tokens) else { return [] }
    if tokens.isEmpty { return [] }
    let important = d.Important
    let name = d.Property

    // The keywords every property takes.
    if tokens.count == 1 && tokens[0].Kind == .ident {
        let kw = lower(tokens[0].Value)
        var wide: Value? = nil
        if kw == "inherit" { wide = .inherit }
        if kw == "initial" || kw == "unset" || kw == "revert" { wide = .initial }
        if let w = wide {
            var out: [Longhand] = []
            for p in longhandsOf(name) {
                out.append(Longhand(p, w, important: important))
            }
            return out
        }
    }

    if let prop = propNames[name] {
        if let v = parseValue(prop, tokens) {
            return [Longhand(prop, v, important: important)]
        }
        return []
    }

    var out: [Longhand] = []
    func set(_ p: Prop, _ v: Value) { out.append(Longhand(p, v, important: important)) }

    switch name {
    case "margin":
        guard let four = fourSides(tokens, allowAuto: true) else { return [] }
        set(.marginTop, four[0]); set(.marginRight, four[1]); set(.marginBottom, four[2]); set(.marginLeft, four[3])
    case "padding":
        guard let four = fourSides(tokens, allowAuto: false) else { return [] }
        set(.paddingTop, four[0]); set(.paddingRight, four[1]); set(.paddingBottom, four[2]); set(.paddingLeft, four[3])
    case "inset":
        guard let four = fourSides(tokens, allowAuto: true) else { return [] }
        set(.top, four[0]); set(.right, four[1]); set(.bottom, four[2]); set(.left, four[3])
    case "grid-area" where tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) != "auto":
        // A template area's name: both axes.
        var p = GridPlacement.auto
        p.Area = tokens[0].Value
        set(.gridRow, .placement(p))
        set(.gridColumn, .placement(p))
    case "grid-template", "grid":
        guard let parts = parseGridTemplate(tokens) else { return [] }
        for (p, v) in parts { set(p, v) }
    case "place-self":
        guard let a = parseValue(.alignSelf, [tokens[0]]) else { return [] }
        set(.alignSelf, a)
        if let j = parseValue(.justifySelf, [tokens.count > 1 ? tokens[1] : tokens[0]]) { set(.justifySelf, j) }
    case "place-content":
        guard let a = parseValue(.alignContent, [tokens[0]]) else { return [] }
        set(.alignContent, a)
        if let j = parseValue(.justifyContent, [tokens.count > 1 ? tokens[1] : tokens[0]]) { set(.justifyContent, j) }
    case "grid-area":
        // row-start / column-start / row-end / column-end, by line
        // number or span.
        var parts: [[Token]] = [[]]
        for t in tokens {
            if t.Kind == .delim && t.Value == "/" { parts.append([]) } else { parts[parts.count - 1].append(t) }
        }
        var row = gridAreaSide(parts, 0, end: false)
        var column = gridAreaSide(parts, 1, end: false)
        let rowEnd = gridAreaSide(parts, 2, end: true)
        let columnEnd = gridAreaSide(parts, 3, end: true)
        row.End = rowEnd.End
        if rowEnd.Span > 0 { row.Span = rowEnd.Span }
        column.End = columnEnd.End
        if columnEnd.Span > 0 { column.Span = columnEnd.Span }
        if row.Span == 0 { row.Span = 1 }
        if column.Span == 0 { column.Span = 1 }
        set(.gridRow, .placement(row))
        set(.gridColumn, .placement(column))
    case "margin-inline", "margin-block", "padding-inline", "padding-block", "inset-inline", "inset-block":
        // A start and an end, one value for both, in a left-to-right,
        // top-to-bottom world.
        let sides = logicalPair(name)
        guard let two = fourSides(tokens, allowAuto: !name.hasPrefix("padding")) else { return [] }
        set(sides[0], two[0]); set(sides[1], two[1])
    case "border-width":
        guard let four = fourValues(tokens, parseBorderWidth) else { return [] }
        set(.borderTopWidth, four[0]); set(.borderRightWidth, four[1]); set(.borderBottomWidth, four[2]); set(.borderLeftWidth, four[3])
    case "border-style":
        guard let four = fourValues(tokens, parseBorderStyle) else { return [] }
        set(.borderTopStyle, four[0]); set(.borderRightStyle, four[1]); set(.borderBottomStyle, four[2]); set(.borderLeftStyle, four[3])
    case "border-color":
        guard let four = fourValues(tokens, parseColorValue) else { return [] }
        set(.borderTopColor, four[0]); set(.borderRightColor, four[1]); set(.borderBottomColor, four[2]); set(.borderLeftColor, four[3])
    case "border", "border-top", "border-right", "border-bottom", "border-left", "border-inline", "border-block",
         "border-inline-start", "border-inline-end", "border-block-start", "border-block-end":
        let parts = parseBorderShorthand(tokens)
        var sides: [int] = [0, 1, 2, 3]
        if name == "border-top" || name == "border-block-start" { sides = [0] } else if name == "border-right" || name == "border-inline-end" { sides = [1] }
        else if name == "border-bottom" || name == "border-block-end" { sides = [2] } else if name == "border-left" || name == "border-inline-start" { sides = [3] }
        else if name == "border-inline" { sides = [3, 1] } else if name == "border-block" { sides = [0, 2] }
        for s in sides {
            set(borderWidthProps[s], parts.width)
            set(borderStyleProps[s], parts.style)
            set(borderColorProps[s], parts.color)
        }
    case "border-radius":
        // Horizontal radii only; what follows a slash is the same for
        // the round corners pages draw.
        var horizontal: [Token] = []
        for t in tokens {
            if t.Kind == .delim && t.Value == "/" { break }
            horizontal.append(t)
        }
        guard let four = fourSides(horizontal, allowAuto: false) else { return [] }
        set(.borderTopLeftRadius, four[0]); set(.borderTopRightRadius, four[1])
        set(.borderBottomRightRadius, four[2]); set(.borderBottomLeftRadius, four[3])
    case "background":
        // The first layer only: a color, an image or gradient, how it
        // repeats, where it sits, and after a slash how big it is.
        var i = 0
        var sawColor = false
        var sawImage = false
        var sawRepeat = false
        var sawSize = false
        var sawAttachment = false
        var positions: [Token] = []
        var afterSlash = false
        while i < tokens.count {
            let t = tokens[i]
            if t.Kind == .comma { break }
            if t.Kind == .delim && t.Value == "/" { afterSlash = true; i += 1; continue }
            if let m = parseColorAt(tokens, i) {
                set(.backgroundColor, m.0)
                sawColor = true
                i += m.1
                continue
            }
            if t.Kind == .url {
                set(.backgroundImage, .url(t.Value))
                sawImage = true
            } else if t.Kind == .function && isImageSetName(lower(t.Value)) {
                if let v = imageSetValue(tokens, i) {
                    set(.backgroundImage, v)
                    sawImage = true
                }
                i = closeParen(tokens, from: i + 1) + 1
                continue
            } else if t.Kind == .function && isGradientName(lower(t.Value)) {
                let end = closeParen(tokens, from: i + 1)
                if let g = parseGradient(tokens, i + 1, end) {
                    set(.backgroundImage, .gradient(g))
                    sawImage = true
                }
                i = end + 1
                continue
            } else if t.Kind == .ident {
                let kw = lower(t.Value)
                if kw == "no-repeat" || kw == "repeat" || kw == "repeat-x" || kw == "repeat-y" || kw == "space" || kw == "round" {
                    set(.backgroundRepeat, .keyword(kw))
                    sawRepeat = true
                } else if kw == "fixed" || kw == "local" || kw == "scroll" {
                    set(.backgroundAttachment, .keyword(kw))
                    sawAttachment = true
                } else if afterSlash && (kw == "cover" || kw == "contain" || kw == "auto") {
                    set(.backgroundSize, .keyword(kw))
                    sawSize = true
                } else if kw == "center" || kw == "left" || kw == "right" || kw == "top" || kw == "bottom" {
                    positions.append(t)
                }
            } else if t.Kind == .percentage || t.Kind == .dimension || t.Kind == .number {
                if afterSlash {
                    var sizeTokens: [Token] = [t]
                    if i + 1 < tokens.count && (tokens[i + 1].Kind == .percentage || tokens[i + 1].Kind == .dimension || (tokens[i + 1].Kind == .ident && lower(tokens[i + 1].Value) == "auto")) {
                        sizeTokens.append(tokens[i + 1])
                        i += 1
                    }
                    if let v = parseBackgroundSize(sizeTokens) { set(.backgroundSize, v); sawSize = true }
                } else {
                    positions.append(t)
                }
            }
            i += 1
        }
        if !positions.isEmpty, let pos = parseBackgroundPosition(positions) { set(.backgroundPosition, pos) }
        else { set(.backgroundPosition, .initial) }
        if !sawColor { set(.backgroundColor, .initial) }
        if !sawImage { set(.backgroundImage, .none) }
        if !sawRepeat { set(.backgroundRepeat, .initial) }
        if !sawSize { set(.backgroundSize, .initial) }
        if !sawAttachment { set(.backgroundAttachment, .initial) }
    case "overflow":
        guard let first = parseOverflow(tokens[0]) else { return [] }
        set(.overflowX, first)
        set(.overflowY, tokens.count > 1 ? (parseOverflow(tokens[1]) ?? first) : first)
    case "font":
        parseFontShorthand(tokens, &out, important)
    case "flex":
        parseFlexShorthand(tokens, &out, important)
    case "flex-flow":
        for t in tokens {
            if let d = parseValue(.flexDirection, [t]) { set(.flexDirection, d) }
            else if let w = parseValue(.flexWrap, [t]) { set(.flexWrap, w) }
        }
    case "gap", "grid-gap":
        guard let first = parseLengthValue(tokens[0], allowAuto: false) else { return [] }
        set(.rowGap, first)
        set(.columnGap, tokens.count > 1 ? (parseLengthValue(tokens[1], allowAuto: false) ?? first) : first)
    case "list-style":
        for t in tokens {
            if let ty = parseValue(.listStyleType, [t]) { set(.listStyleType, ty) }
            else if let pos = parseValue(.listStylePosition, [t]) { set(.listStylePosition, pos) }
        }
    case "text-decoration":
        var i = 0
        var lines: [string] = []
        while i < tokens.count {
            if let m = parseColorAt(tokens, i) {
                set(.textDecorationColor, m.0)
                i += m.1
                continue
            }
            if tokens[i].Kind == .ident {
                let kw = lower(tokens[i].Value)
                switch kw {
                case "solid", "double", "dotted", "dashed", "wavy": set(.textDecorationStyle, .keyword(kw))
                case "auto", "from-font": set(.textDecorationThickness, .auto)
                default: lines.append(kw)
                }
            } else if let l = parseLengthValue(tokens[i], allowAuto: false) {
                set(.textDecorationThickness, l)
            }
            i += 1
        }
        if lines.isEmpty { lines = ["none"] }
        set(.textDecorationLine, .keyword(joinWords(lines)))
    case "outline":
        // `outline: none` takes away a focus ring: its style, and its
        // width with it.
        var style: Value = .keyword("none")
        var width: Value = .length(3, .px)
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t.Kind == .ident, let st = parseValue(.outlineStyle, [t]) { style = st }
            else if let w = parseBorderWidth(t) { width = w }
            else if let m = parseColorAt(tokens, i) {
                set(.outlineColor, m.0)
                i += m.1
                continue
            }
            i += 1
        }
        if case .keyword(let k) = style, k == "none" || k == "hidden" { width = .length(0, .px) }
        set(.outlineStyle, style)
        set(.outlineWidth, width)
    case "container":
        // `container: <name>+ [/ <type>]?`
        var names: [Token] = []
        var i = 0
        while i < tokens.count && !(tokens[i].Kind == .delim && tokens[i].Value == "/") { names.append(tokens[i]); i += 1 }
        guard let n = parseContainerName(names) else { return [] }
        var type = Value.keyword("normal")
        if i < tokens.count {
            guard i + 2 == tokens.count, let t = parseValue(.containerType, [tokens[i + 1]]) else { return [] }
            type = t
        }
        set(.containerName, n)
        set(.containerType, type)
    case "scroll-padding", "scroll-margin", "scroll-padding-block", "scroll-padding-inline", "scroll-margin-block", "scroll-margin-inline":
        let pad = name.hasPrefix("scroll-padding")
        let sides: [Prop] = pad ? [.scrollPaddingTop, .scrollPaddingRight, .scrollPaddingBottom, .scrollPaddingLeft]
                                : [.scrollMarginTop, .scrollMarginRight, .scrollMarginBottom, .scrollMarginLeft]
        guard let four = fourSides(tokens, allowAuto: true) else { return [] }
        if name.hasSuffix("-block") {
            set(sides[0], four[0]); set(sides[2], four.count > 2 ? four[2] : four[0])
        } else if name.hasSuffix("-inline") {
            set(sides[3], four[0]); set(sides[1], four[0])
            if tokens.count > 1 { set(sides[1], four[1]) }
        } else {
            set(sides[0], four[0]); set(sides[1], four[1]); set(sides[2], four[2]); set(sides[3], four[3])
        }
    case "overscroll-behavior":
        guard let x = parseValue(.overscrollBehaviorX, [tokens[0]]) else { return [] }
        set(.overscrollBehaviorX, x)
        set(.overscrollBehaviorY, tokens.count > 1 ? (parseValue(.overscrollBehaviorY, [tokens[1]]) ?? x) : x)
    case "contain-intrinsic-size":
        let lengths = tokens.filter { !($0.Kind == .ident && lower($0.Value) == "auto") }
        guard !lengths.isEmpty, let w = parseValue(.containIntrinsicWidth, [lengths[0]]) else { return [] }
        set(.containIntrinsicWidth, w)
        set(.containIntrinsicHeight, lengths.count > 1 ? (parseValue(.containIntrinsicHeight, [lengths[1]]) ?? w) : w)
    case "text-wrap":
        // text-wrap-mode and text-wrap-style, either or both.
        for tok in tokens where tok.Kind == .ident {
            let w = lower(tok.Value)
            if w == "wrap" || w == "nowrap" { set(.textWrapMode, .keyword(w)) }
            else if let st = parseValue(.textWrapStyle, [tok]) { set(.textWrapStyle, st) }
        }
    case "transition", "-webkit-transition":
        guard let parts = parseTransitionShorthand(tokens) else { return [] }
        for (p, v) in parts { set(p, v) }
    case "animation", "-webkit-animation":
        guard let parts = parseAnimationShorthand(tokens) else { return [] }
        for (p, v) in parts { set(p, v) }
    case "place-items":
        if let v = parseValue(.alignItems, [tokens[0]]) { set(.alignItems, v) }
        if let j = parseValue(.justifyItems, [tokens.count > 1 ? tokens[1] : tokens[0]]) { set(.justifyItems, j) }
    case "perspective", "perspective-origin", "backface-visibility",
         "transform-style", "transform-box",
         "font-variant", "font-stretch", "font-feature-settings", "src", "unicode-range",
         "text-rendering", "-webkit-font-smoothing", "-moz-osx-font-smoothing",
         "hyphens",
         "writing-mode", "caption-side",
         "empty-cells", "speak",
         "font-display",
         "text-size-adjust", "-webkit-text-size-adjust", "-webkit-tap-highlight-color",
         "list-style-image", "font-kerning",
         "text-align-last", "text-justify", "font-variant-numeric", "font-variant-ligatures",
         "font-optical-sizing",
         "unused-placeholder-property":
        break
    case "columns":
        // A count and a width, in either order, either auto.
        var count: Value = .auto
        var width: Value = .auto
        for t in tokens {
            if t.Kind == .number && t.NumberVal >= 1 { count = .number(t.NumberVal.rounded(.down)); continue }
            if t.Kind == .ident && lower(t.Value) == "auto" { continue }
            guard let w = parseLengthValue(t, allowAuto: false) else { return [] }
            width = w
        }
        set(.columnCount, count)
        set(.columnWidth, width)
    case "column-rule":
        let parts = parseBorderShorthand(tokens)
        set(.columnRuleWidth, parts.width)
        set(.columnRuleStyle, parts.style)
        set(.columnRuleColor, parts.color)
    case "border-image", "-webkit-border-image":
        // An image, slices with fill, then / widths and / outsets, and
        // the repeats, in any order around the slices.
        var source: Value = .none
        var repeats: [Token] = []
        var groups: [[Token]] = [[]]
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let w = t.Kind == .ident ? lower(t.Value) : ""
            if t.Kind == .url {
                source = .url(t.Value)
            } else if t.Kind == .function && isGradientName(lower(t.Value)) {
                let end = closeParen(tokens, from: i + 1)
                if let v = parseValue(.borderImageSource, Array(tokens[i..<(end < tokens.count ? end + 1 : tokens.count)])) { source = v }
                i = end
            } else if w == "stretch" || w == "repeat" || w == "round" || w == "space" {
                repeats.append(t)
            } else if t.Kind == .delim && t.Value == "/" {
                groups.append([])
            } else {
                groups[groups.count - 1].append(t)
            }
            i += 1
        }
        set(.borderImageSource, source)
        set(.borderImageSlice, groups[0].isEmpty ? .list([.length(100, .percent)]) : (parseValue(.borderImageSlice, groups[0]) ?? .list([.length(100, .percent)])))
        set(.borderImageWidth, groups.count > 1 && !groups[1].isEmpty ? (parseValue(.borderImageWidth, groups[1]) ?? .list([.number(1)])) : .list([.number(1)]))
        set(.borderImageOutset, groups.count > 2 && !groups[2].isEmpty ? (parseValue(.borderImageOutset, groups[2]) ?? .list([.number(0)])) : .list([.number(0)]))
        set(.borderImageRepeat, repeats.isEmpty ? .list([.keyword("stretch")]) : (parseValue(.borderImageRepeat, repeats) ?? .list([.keyword("stretch")])))
    case "mask", "-webkit-mask":
        // The background shorthand's syntax but for color, with a mode:
        // read as background, and its longhands renamed.
        let bg = longhands(Declaration(property: "background", value: d.Value, important: important, tokens: tokens))
        var sawImage = false
        for l in bg {
            switch l.Prop {
            case .backgroundImage:
                set(.maskImage, l.Value)
                sawImage = true
            case .backgroundRepeat: set(.maskRepeat, l.Value)
            case .backgroundSize: set(.maskSize, l.Value)
            case .backgroundPosition: set(.maskPosition, l.Value)
            default: break
            }
        }
        if !sawImage { set(.maskImage, .none) }
        var mode: Value = .initial
        for t in tokens where t.Kind == .ident {
            let w = lower(t.Value)
            if w == "alpha" || w == "luminance" || w == "match-source" { mode = .keyword(w) }
        }
        set(.maskMode, mode)
    default:
        // margin-inline-start and friends, in a left-to-right, top-to-bottom world.
        if let mapped = logicalProp(name) {
            if let v = parseValue(mapped, tokens) { set(mapped, v) }
        }
    }
    return out
}

let borderWidthProps: [Prop] = [.borderTopWidth, .borderRightWidth, .borderBottomWidth, .borderLeftWidth]
let borderStyleProps: [Prop] = [.borderTopStyle, .borderRightStyle, .borderBottomStyle, .borderLeftStyle]
let borderColorProps: [Prop] = [.borderTopColor, .borderRightColor, .borderBottomColor, .borderLeftColor]

func logicalProp(_ name: string) -> Prop? {
    switch name {
    case "margin-inline-start": return .marginLeft
    case "margin-inline-end": return .marginRight
    case "margin-block-start": return .marginTop
    case "margin-block-end": return .marginBottom
    case "padding-inline-start": return .paddingLeft
    case "padding-inline-end": return .paddingRight
    case "padding-block-start": return .paddingTop
    case "padding-block-end": return .paddingBottom
    case "border-inline-start-width": return .borderLeftWidth
    case "border-inline-end-width": return .borderRightWidth
    case "border-start-start-radius": return .borderTopLeftRadius
    case "border-start-end-radius": return .borderTopRightRadius
    case "border-end-start-radius": return .borderBottomLeftRadius
    case "border-end-end-radius": return .borderBottomRightRadius
    case "inset-inline-start": return .left
    case "inset-inline-end": return .right
    case "inset-block-start": return .top
    case "inset-block-end": return .bottom
    // Flow-relative sizes, in horizontal writing.
    case "inline-size": return .width
    case "block-size": return .height
    case "min-inline-size": return .minWidth
    case "max-inline-size": return .maxWidth
    case "min-block-size": return .minHeight
    case "max-block-size": return .maxHeight
    case "border-inline-end-width": return .borderRightWidth
    case "border-block-start-width": return .borderTopWidth
    case "border-block-end-width": return .borderBottomWidth
    default: return nil
    }
}

/// The start and end sides a two-sided logical shorthand sets.
func logicalPair(_ name: string) -> [Prop] {
    switch name {
    case "margin-inline": return [.marginLeft, .marginRight]
    case "margin-block": return [.marginTop, .marginBottom]
    case "padding-inline": return [.paddingLeft, .paddingRight]
    case "padding-block": return [.paddingTop, .paddingBottom]
    case "inset-inline": return [.left, .right]
    case "inset-block": return [.top, .bottom]
    default: return []
    }
}

/// The longhands a property name stands for, for `inherit` and `initial`.
func longhandsOf(_ name: string) -> [Prop] {
    if let p = propNames[name] { return [p] }
    switch name {
    case "margin": return [.marginTop, .marginRight, .marginBottom, .marginLeft]
    case "padding": return [.paddingTop, .paddingRight, .paddingBottom, .paddingLeft]
    case "border-width": return borderWidthProps
    case "border-style": return borderStyleProps
    case "border-color": return borderColorProps
    case "mask", "-webkit-mask": return [.maskImage, .maskRepeat, .maskSize, .maskPosition, .maskMode]
    case "columns": return [.columnCount, .columnWidth]
    case "column-rule": return [.columnRuleWidth, .columnRuleStyle, .columnRuleColor]
    case "border-image", "-webkit-border-image": return [.borderImageSource, .borderImageSlice, .borderImageWidth, .borderImageOutset, .borderImageRepeat]
    case "border": return borderWidthProps + borderStyleProps + borderColorProps
    // One side's width, style and color: what var() in border-top waits
    // to expand into.
    case "border-top", "border-block-start": return [borderWidthProps[0], borderStyleProps[0], borderColorProps[0]]
    case "border-inline-start": return [borderWidthProps[3], borderStyleProps[3], borderColorProps[3]]
    case "border-inline-end": return [borderWidthProps[1], borderStyleProps[1], borderColorProps[1]]
    case "border-block-end": return [borderWidthProps[2], borderStyleProps[2], borderColorProps[2]]
    case "border-inline": return [borderWidthProps[3], borderStyleProps[3], borderColorProps[3], borderWidthProps[1], borderStyleProps[1], borderColorProps[1]]
    case "border-block": return [borderWidthProps[0], borderStyleProps[0], borderColorProps[0], borderWidthProps[2], borderStyleProps[2], borderColorProps[2]]
    case "border-right": return [borderWidthProps[1], borderStyleProps[1], borderColorProps[1]]
    case "border-bottom": return [borderWidthProps[2], borderStyleProps[2], borderColorProps[2]]
    case "border-left": return [borderWidthProps[3], borderStyleProps[3], borderColorProps[3]]
    case "border-radius": return [.borderTopLeftRadius, .borderTopRightRadius, .borderBottomRightRadius, .borderBottomLeftRadius]
    case "background": return [.backgroundColor, .backgroundImage, .backgroundRepeat, .backgroundSize, .backgroundPosition, .backgroundAttachment]
    case "overflow": return [.overflowX, .overflowY]
    case "outline": return [.outlineWidth, .outlineColor, .outlineStyle]
    case "container": return [.containerName, .containerType]
    case "text-wrap": return [.textWrapMode, .textWrapStyle]
    case "overscroll-behavior": return [.overscrollBehaviorX, .overscrollBehaviorY]
    case "scroll-padding", "scroll-padding-block", "scroll-padding-inline": return [.scrollPaddingTop, .scrollPaddingRight, .scrollPaddingBottom, .scrollPaddingLeft]
    case "scroll-margin", "scroll-margin-block", "scroll-margin-inline": return [.scrollMarginTop, .scrollMarginRight, .scrollMarginBottom, .scrollMarginLeft]
    case "contain-intrinsic-size": return [.containIntrinsicWidth, .containIntrinsicHeight]
    case "transition", "-webkit-transition": return transitionProps
    case "animation", "-webkit-animation": return animationProps
    case "font": return [.fontFamily, .fontSize, .fontWeight, .fontStyle, .lineHeight]
    case "flex": return [.flexGrow, .flexShrink, .flexBasis]
    case "gap": return [.rowGap, .columnGap]
    case "grid-area": return [.gridRow, .gridColumn]
    case "grid-template": return [.gridTemplateRows, .gridTemplateColumns, .gridTemplateAreas]
    case "grid": return [.gridTemplateRows, .gridTemplateColumns, .gridTemplateAreas, .gridAutoRows, .gridAutoColumns, .gridAutoFlow]
    case "place-self": return [.alignSelf, .justifySelf]
    case "place-content": return [.alignContent, .justifyContent]
    case "list-style": return [.listStyleType, .listStylePosition]
    case "text-decoration": return [.textDecorationLine, .textDecorationColor, .textDecorationStyle, .textDecorationThickness]
    case "margin-inline", "margin-block", "padding-inline", "padding-block", "inset-inline", "inset-block":
        return logicalPair(name)
    default:
        if let p = logicalProp(name) { return [p] }
        return []
    }
}

// MARK: - Values

package func lower(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var i = 0
    var needs = false
    while i < b.count {
        if b[i] >= 65 && b[i] <= 90 { needs = true; break }
        i += 1
    }
    if !needs { return s }
    var out = b
    i = 0
    while i < out.count {
        if out[i] >= 65 && out[i] <= 90 { out[i] = out[i] + 32 }
        i += 1
    }
    return stringOf(out, 0, out.count)
}

func joinWords(_ words: [string]) -> string {
    var out = ""
    var i = 0
    while i < words.count {
        if i > 0 { out += " " }
        out += words[i]
        i += 1
    }
    return out
}

func unitOf(_ s: string) -> Unit? {
    switch s {
    case "px": return .px
    case "em": return .em
    case "rem": return .rem
    case "ex": return .ex
    case "ch": return .ch
    case "vw": return .vw
    case "vh": return .vh
    case "vmin": return .vmin
    case "vmax": return .vmax
    // The small, large and dynamic viewports are the one viewport: the
    // engine has no browser chrome that comes and goes. vi and vb are
    // horizontal writing's.
    case "svw", "lvw", "dvw", "vi", "svi", "lvi", "dvi": return .vw
    case "svh", "lvh", "dvh", "vb", "svb", "lvb", "dvb": return .vh
    case "svmin", "lvmin", "dvmin": return .vmin
    case "svmax", "lvmax", "dvmax": return .vmax
    case "cqw", "cqi": return .cqw
    case "cqh", "cqb": return .cqh
    case "cqmin": return .cqmin
    case "cqmax": return .cqmax
    case "lh": return .lh
    case "rlh": return .rlh
    default: return nil
    }
}

/// A length token as a value: px, relative units, absolute units scaled
/// to px, percentages, and unitless zero.
func parseLengthValue(_ t: Token, allowAuto: Bool) -> Value? {
    switch t.Kind {
    case .dimension:
        if let u = unitOf(t.Unit) { return .length(t.NumberVal, u) }
        switch t.Unit {
        case "pt": return .length(t.NumberVal * 4 / 3, .px)
        case "pc": return .length(t.NumberVal * 16, .px)
        case "in": return .length(t.NumberVal * 96, .px)
        case "cm": return .length(t.NumberVal * 96 / 2.54, .px)
        case "mm": return .length(t.NumberVal * 96 / 25.4, .px)
        case "q": return .length(t.NumberVal * 96 / 101.6, .px)
        default: return nil
        }
    case .percentage:
        return .length(t.NumberVal, .percent)
    case .number:
        if t.NumberVal == 0 { return .length(0, .px) }
        return nil
    case .ident:
        let kw = lower(t.Value)
        if kw == "auto" && allowAuto { return .auto }
        if kw == "min-content" || kw == "max-content" || kw == "fit-content" { return .keyword(kw) }
        return nil
    case .function:
        return nil
    default:
        return nil
    }
}

/// calc(...): a sum of terms, each a length or a number times a
/// length; min(), max() and clamp() of lengths in one unit are folded.
func parseCalc(_ tokens: [Token], _ start: int, _ end: int) -> Value? {
    var terms: [CalcTerm] = []
    if !calcSum(tokens, start, end, &terms, sign: 1) { return nil }
    if terms.isEmpty { return nil }
    return .calc(terms)
}

func calcSum(_ tokens: [Token], _ start: int, _ end: int, _ terms: inout [CalcTerm], sign: float32) -> bool {
    var p = start
    guard let sum = calcExpr(tokens, &p, end), p == end else { return false }
    for t in sum { terms.append(CalcTerm(Number: t.Number * sign, Unit: t.Unit)) }
    return true
}

// calc() as the grammar has it: sums of products of values, where a
// product has a plain number on one side and a quotient a plain number
// below. Each part is a sum of terms, one per unit.

/// A sum: products joined by + and -.
func calcExpr(_ tokens: [Token], _ p: inout int, _ end: int) -> [CalcTerm]? {
    guard var sum = calcProduct(tokens, &p, end) else { return nil }
    while p < end {
        let t = tokens[p]
        if t.Kind == .delim && (t.Value == "+" || t.Value == "-") {
            let negate = t.Value == "-"
            p += 1
            guard let rhs = calcProduct(tokens, &p, end) else { return nil }
            sum = calcAdd(sum, negate ? calcScale(rhs, -1) : rhs)
        } else if (t.Kind == .number || t.Kind == .dimension || t.Kind == .percentage) && t.NumberVal < 0 {
            // "a -1px", its space lost to the tokens: a sum still.
            guard let rhs = calcProduct(tokens, &p, end) else { return nil }
            sum = calcAdd(sum, rhs)
        } else {
            return nil
        }
    }
    return sum
}

/// A product: values joined by * and /.
func calcProduct(_ tokens: [Token], _ p: inout int, _ end: int) -> [CalcTerm]? {
    guard var value = calcValueTerm(tokens, &p, end) else { return nil }
    while p < end && tokens[p].Kind == .delim && (tokens[p].Value == "*" || tokens[p].Value == "/") {
        let divide = tokens[p].Value == "/"
        p += 1
        guard let rhs = calcValueTerm(tokens, &p, end) else { return nil }
        if divide {
            guard let n = calcPlainNumber(rhs), n != 0 else { return nil }
            value = calcScale(value, 1 / n)
        } else if let n = calcPlainNumber(value) {
            value = calcScale(rhs, n)
        } else if let n = calcPlainNumber(rhs) {
            value = calcScale(value, n)
        } else {
            return nil
        }
    }
    return value
}

/// One value: a number, length or percentage, a parenthesized or
/// nested calc(), or min(), max() or clamp().
func calcValueTerm(_ tokens: [Token], _ p: inout int, _ end: int) -> [CalcTerm]? {
    if p >= end { return nil }
    let t = tokens[p]
    if t.Kind == .delim && (t.Value == "-" || t.Value == "+") {
        p += 1
        guard let v = calcValueTerm(tokens, &p, end) else { return nil }
        return t.Value == "-" ? calcScale(v, -1) : v
    }
    if t.Kind == .number {
        p += 1
        return [CalcTerm(Number: t.NumberVal, Unit: nil)]
    }
    if t.Kind == .percentage {
        p += 1
        return [CalcTerm(Number: t.NumberVal, Unit: .percent)]
    }
    if t.Kind == .dimension {
        // An angle is a number of radians here, for the trigonometric
        // functions.
        if let a = angleRadians(t.NumberVal, lower(t.Unit)) {
            p += 1
            return [CalcTerm(Number: a, Unit: nil)]
        }
        guard let parsed = parseLengthValue(t, allowAuto: false), case .length(let n, let unit) = parsed else { return nil }
        p += 1
        return [CalcTerm(Number: n, Unit: unit)]
    }
    if t.Kind == .ident {
        var constant: float32 = 0
        switch lower(t.Value) {
        case "pi": constant = 3.14159265
        case "e": constant = 2.71828183
        case "infinity": constant = 3.4e38
        case "-infinity": constant = -3.4e38
        default: return nil
        }
        p += 1
        return [CalcTerm(Number: constant, Unit: nil)]
    }
    if t.Kind == .openParen || t.Kind == .function {
        let close = closeParen(tokens, from: p + 1)
        let name = t.Kind == .function ? lower(t.Value) : ""
        if mathFunctions.contains(name) {
            guard let folded = foldMinMax(name, tokens, p + 1, close) else { return nil }
            p = close + 1
            return [folded]
        }
        if t.Kind == .function && name != "calc" && name != "-webkit-calc" { return nil }
        var q = p + 1
        guard let inner = calcExpr(tokens, &q, close), q == close else { return nil }
        p = close + 1
        return inner
    }
    return nil
}

/// The number a sum is when it has no units, or nil.
func calcPlainNumber(_ v: [CalcTerm]) -> float32? {
    var n: float32 = 0
    for t in v {
        if t.Unit != nil { return nil }
        n += t.Number
    }
    return n
}

func calcScale(_ v: [CalcTerm], _ k: float32) -> [CalcTerm] {
    var out: [CalcTerm] = []
    for t in v { out.append(CalcTerm(Number: t.Number * k, Unit: t.Unit)) }
    return out
}

/// Two sums as one, like units added together.
func calcAdd(_ a: [CalcTerm], _ b: [CalcTerm]) -> [CalcTerm] {
    var out = a
    for t in b {
        var merged = false
        var i = 0
        while i < out.count {
            if out[i].Unit == t.Unit {
                out[i].Number += t.Number
                merged = true
                break
            }
            i += 1
        }
        if !merged { out.append(t) }
    }
    return out
}

/// min(), max() or clamp() of arguments that are all one unit, as one term.
/// The math functions folded where their arguments share a unit:
/// comparison, stepped values, sign, trigonometry and exponents.
let mathFunctions: [string] = [
    "min", "max", "clamp", "round", "mod", "rem", "abs", "sign", "sin", "cos", "tan", "asin", "acos",
    "atan", "atan2", "pow", "sqrt", "hypot", "log", "exp",
]

/// A math function's value where its arguments are each one term in one
/// unit (or unitless), or nil.
func foldMinMax(_ name: string, _ tokens: [Token], _ start0: int, _ end: int) -> CalcTerm? {
    var start = start0
    // round()'s strategy comes first, as a keyword.
    var strategy = "nearest"
    if name == "round" && start < end && tokens[start].Kind == .ident {
        let kw = lower(tokens[start].Value)
        if kw == "nearest" || kw == "up" || kw == "down" || kw == "to-zero" {
            strategy = kw
            start += 1
            while start < end && tokens[start].Kind == .comma { start += 1 }
        }
    }
    var args: [[CalcTerm]] = []
    var current: [CalcTerm] = []
    var i = start
    var argStart = start
    var depth = 0
    while i <= end {
        if i == end || (tokens[i].Kind == .comma && depth == 0) {
            current = []
            if !calcSum(tokens, argStart, i, &current, sign: 1) { return nil }
            args.append(current)
            argStart = i + 1
        } else if tokens[i].Kind == .function || tokens[i].Kind == .openParen {
            depth += 1
        } else if tokens[i].Kind == .closeParen {
            depth -= 1
        }
        i += 1
    }
    if args.isEmpty { return nil }
    var values: [float32] = []
    var unit: Unit? = nil
    for a in args {
        if a.count != 1 { return nil }
        if values.isEmpty { unit = a[0].Unit } else if a[0].Unit != unit { return nil }
        values.append(a[0].Number)
    }
    let a = values[0]
    let b: float32 = values.count > 1 ? values[1] : 1
    let n = values.count
    switch name {
    case "min":
        var out = a
        for v in values where v < out { out = v }
        return CalcTerm(Number: out, Unit: unit)
    case "max":
        var out = a
        for v in values where v > out { out = v }
        return CalcTerm(Number: out, Unit: unit)
    case "clamp":
        if n != 3 { return nil }
        var out = values[1]
        if out < values[0] { out = values[0] }
        if out > values[2] { out = values[2] }
        return CalcTerm(Number: out, Unit: unit)
    case "round":
        if n > 2 || b == 0 { return nil }
        if n == 1 && unit != nil { return nil }
        let q = a / b
        var r = math.Floor(q + 0.5)
        switch strategy {
        case "up": r = math.Ceil(q)
        case "down": r = math.Floor(q)
        case "to-zero": r = q < 0 ? math.Ceil(q) : math.Floor(q)
        default: break
        }
        return CalcTerm(Number: r * b, Unit: unit)
    case "mod", "rem":
        if n != 2 || b == 0 { return nil }
        let q = a / b
        let k = name == "mod" ? math.Floor(q) : (q < 0 ? math.Ceil(q) : math.Floor(q))
        return CalcTerm(Number: a - b * k, Unit: unit)
    case "abs":
        if n != 1 { return nil }
        return CalcTerm(Number: a < 0 ? -a : a, Unit: unit)
    case "sign":
        if n != 1 { return nil }
        return CalcTerm(Number: a > 0 ? 1 : (a < 0 ? -1 : 0), Unit: nil)
    case "hypot":
        var sum: float32 = 0
        for v in values { sum += v * v }
        return CalcTerm(Number: math.Sqrt(sum), Unit: unit)
    case "atan2":
        // Two of the same unit: an angle, in radians.
        if n != 2 { return nil }
        return CalcTerm(Number: math.Atan2(a, b), Unit: nil)
    default:
        break
    }
    // The rest take and give plain numbers (angles in radians).
    if unit != nil { return nil }
    var out: float32 = 0
    switch name {
    case "sin": out = math.Sin(a)
    case "cos": out = math.Cos(a)
    case "tan": out = math.Tan(a)
    case "asin": out = math.Asin(a)
    case "acos": out = math.Acos(a)
    case "atan": out = math.Atan(a)
    case "pow":
        if n != 2 { return nil }
        out = math.Pow(a, b)
    case "sqrt": out = math.Sqrt(a)
    case "exp": out = math.Exp(a)
    case "log": out = n == 2 ? math.Log(a) / math.Log(b) : math.Log(a)
    default: return nil
    }
    return CalcTerm(Number: out, Unit: nil)
}

/// A calc(), min(), max() or clamp() at the start of a value.
func calcValue(_ tokens: [Token]) -> Value? {
    if tokens.isEmpty || tokens[0].Kind != .function { return nil }
    let name = lower(tokens[0].Value)
    let end = closeParen(tokens, from: 1)
    if name == "calc" || name == "-webkit-calc" {
        return parseCalc(tokens, 1, end)
    }
    if mathFunctions.contains(name) {
        if let t = foldMinMax(name, tokens, 1, end) {
            if let u = t.Unit { return .length(t.Number, u) }
            return .number(t.Number)
        }
    }
    return nil
}

/// One to four lengths, as the sides shorthands take them.
func fourSides(_ tokens: [Token], allowAuto: Bool) -> [Value]? {
    return fourValues(tokens) { t in parseLengthValue(t, allowAuto: allowAuto) }
}

func fourValues(_ tokens: [Token], _ parse: (Token) -> Value?) -> [Value]? {
    var vals: [Value] = []
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind == .function {
            // A calc() among the sides.
            let end = closeParen(tokens, from: i + 1)
            var slice: [Token] = []
            var k = i
            while k <= end && k < tokens.count { slice.append(tokens[k]); k += 1 }
            guard let v = calcValue(slice) else { return nil }
            vals.append(v)
            i = end + 1
            if vals.count == 4 { break }
            continue
        }
        guard let v = parse(t) else { return nil }
        vals.append(v)
        i += 1
        if vals.count == 4 { break }
    }
    switch vals.count {
    case 1: return [vals[0], vals[0], vals[0], vals[0]]
    case 2: return [vals[0], vals[1], vals[0], vals[1]]
    case 3: return [vals[0], vals[1], vals[2], vals[1]]
    case 4: return vals
    default: return nil
    }
}

func parseBorderWidth(_ t: Token) -> Value? {
    if t.Kind == .ident {
        switch lower(t.Value) {
        case "thin": return .length(1, .px)
        case "medium": return .length(3, .px)
        case "thick": return .length(5, .px)
        default: return nil
        }
    }
    if t.Kind == .percentage { return nil }
    return parseLengthValue(t, allowAuto: false)
}

func parseBorderStyle(_ t: Token) -> Value? {
    if t.Kind != .ident { return nil }
    switch lower(t.Value) {
    case "none", "hidden", "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset":
        return .keyword(lower(t.Value))
    default:
        return nil
    }
}

/// A color at tokens[i], and how many tokens it took; nil where there
/// is none there.
func parseColorAt(_ tokens: [Token], _ i: int) -> (Value, int)? {
    let t = tokens[i]
    switch t.Kind {
    case .hash:
        if let c = ParseColor(t.Value) { return (Value.color(c), 1) }
        return nil
    case .ident:
        let kw = lower(t.Value)
        if kw == "currentcolor" { return (Value.currentColor, 1) }
        if kw == "transparent" { return (Value.color(draw.Color.transparent), 1) }
        if let c = ParseColor(kw) { return (Value.color(c), 1) }
        return nil
    case .function:
        let name = lower(t.Value)
        if !colorFunctionNames.contains(name) { return nil }
        var j = i + 1
        var depth = 1
        var inner: [Token] = []
        while j < tokens.count {
            if tokens[j].Kind == .function || tokens[j].Kind == .openParen { depth += 1 }
            if tokens[j].Kind == .closeParen {
                depth -= 1
                if depth == 0 { break }
            }
            inner.append(tokens[j])
            j += 1
        }
        let text = name + "(" + Serialize(inner) + ")"
        if name == "light-dark" {
            let b = asciiLower([uint8](text.utf8))
            let parts = commaArgs(b, 11, b.count - 1)
            if parts.count != 2 { return nil }
            guard let light = ParseColor(parts[0]), let dark = ParseColor(parts[1]) else { return nil }
            return (Value.lightDark(light, dark), j - i + 1)
        }
        if let c = ParseColor(text) { return (Value.color(c), j - i + 1) }
        return nil
    default:
        return nil
    }
}

let colorFunctionNames: [string] = [
    "rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch", "color",
    "color-mix", "light-dark", "contrast-color",
]

/// container-name: none, or names (not the CSS-wide keywords, `and`,
/// `or`, `not`), kept space-separated.
func parseContainerName(_ tokens: [Token]) -> Value? {
    if tokens.isEmpty { return nil }
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return .string("") }
    var names: [string] = []
    for t in tokens {
        if t.Kind != .ident { return nil }
        let k = lower(t.Value)
        if k == "none" || k == "and" || k == "or" || k == "not" || k == "default" { return nil }
        names.append(t.Value)
    }
    return .string(names.joined(separator: " "))
}

func parseColorValue(_ t: Token) -> Value? {
    if let m = parseColorAt([t], 0) { return m.0 }
    return nil
}

func parseOverflow(_ t: Token) -> Value? {
    if t.Kind != .ident { return nil }
    switch lower(t.Value) {
    case "visible", "hidden", "scroll", "auto", "clip", "overlay":
        return .keyword(lower(t.Value) == "overlay" ? "auto" : lower(t.Value))
    default: return nil
    }
}

struct BorderParts {
    var width: Value = .initial
    var style: Value = .initial
    var color: Value = .initial
}

func parseBorderShorthand(_ tokens: [Token]) -> BorderParts {
    var parts = BorderParts()
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if let s = parseBorderStyle(t) {
            parts.style = s
        } else if let w = parseBorderWidth(t) {
            parts.width = w
        } else if let m = parseColorAt(tokens, i) {
            parts.color = m.0
            i += m.1
            continue
        }
        i += 1
    }
    return parts
}

func parseFontShorthand(_ tokens: [Token], _ out: inout [Longhand], _ important: Bool) {
    // [style || weight]* size [/ line-height]? family
    var i = 0
    var style: Value = .initial
    var weight: Value = .initial
    var size: Value? = nil
    var lineHeight: Value = .initial
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind == .ident {
            let kw = lower(t.Value)
            if kw == "italic" || kw == "oblique" { style = .keyword(kw); i += 1; continue }
            if kw == "bold" || kw == "bolder" || kw == "lighter" { weight = .keyword(kw); i += 1; continue }
            if kw == "normal" || kw == "small-caps" { i += 1; continue }
            if let s = parseFontSizeValue(t) { size = s; i += 1; break }
            // A bare family name is where the family list starts.
            break
        }
        if t.Kind == .number && (t.NumberVal == 100 || t.NumberVal == 200 || t.NumberVal == 300 || t.NumberVal == 400 ||
            t.NumberVal == 500 || t.NumberVal == 600 || t.NumberVal == 700 || t.NumberVal == 800 || t.NumberVal == 900) {
            weight = .number(t.NumberVal)
            i += 1
            continue
        }
        if let s = parseFontSizeValue(t) { size = s; i += 1; break }
        i += 1
    }
    guard let sz = size else { return }
    if i < tokens.count && tokens[i].Kind == .delim && tokens[i].Value == "/" {
        i += 1
        if i < tokens.count {
            if let lh = parseLineHeightValue(tokens[i]) { lineHeight = lh }
            i += 1
        }
    }
    var rest: [Token] = []
    while i < tokens.count {
        rest.append(tokens[i])
        i += 1
    }
    out.append(Longhand(.fontStyle, style, important: important))
    out.append(Longhand(.fontWeight, weight, important: important))
    out.append(Longhand(.fontSize, sz, important: important))
    out.append(Longhand(.lineHeight, lineHeight, important: important))
    if !rest.isEmpty {
        out.append(Longhand(.fontFamily, .families(parseFamilies(rest)), important: important))
    }
}

func parseFlexShorthand(_ tokens: [Token], _ out: inout [Longhand], _ important: Bool) {
    var grow: Value = .number(1)
    var shrink: Value = .number(1)
    var basis: Value = .length(0, .px)
    if tokens.count == 1 && tokens[0].Kind == .ident {
        switch lower(tokens[0].Value) {
        case "none": grow = .number(0); shrink = .number(0); basis = .auto
        case "auto": grow = .number(1); shrink = .number(1); basis = .auto
        case "initial": grow = .number(0); shrink = .number(1); basis = .auto
        default: return
        }
    } else {
        var numbers: [float32] = []
        for t in tokens {
            if t.Kind == .number {
                numbers.append(t.NumberVal)
            } else if let l = parseLengthValue(t, allowAuto: true) {
                basis = l
            }
        }
        if numbers.count >= 1 { grow = .number(numbers[0]) }
        if numbers.count >= 2 { shrink = .number(numbers[1]) }
    }
    out.append(Longhand(.flexGrow, grow, important: important))
    out.append(Longhand(.flexShrink, shrink, important: important))
    out.append(Longhand(.flexBasis, basis, important: important))
}

func parseFontSizeValue(_ t: Token) -> Value? {
    if t.Kind == .ident {
        switch lower(t.Value) {
        case "xx-small": return .length(9, .px)
        case "x-small": return .length(10, .px)
        case "small": return .length(13, .px)
        case "medium": return .length(16, .px)
        case "large": return .length(18, .px)
        case "x-large": return .length(24, .px)
        case "xx-large": return .length(32, .px)
        case "xxx-large": return .length(48, .px)
        case "smaller": return .length(0.8333, .em)
        case "larger": return .length(1.2, .em)
        default: return nil
        }
    }
    if t.Kind == .number && t.NumberVal != 0 { return nil }
    return parseLengthValue(t, allowAuto: false)
}

func parseLineHeightValue(_ t: Token) -> Value? {
    if t.Kind == .ident && lower(t.Value) == "normal" { return .normal }
    if t.Kind == .number { return .number(t.NumberVal) }
    return parseLengthValue(t, allowAuto: false)
}

/// Family names, comma-separated; a quoted name is one token, an
/// unquoted one may be several.
func parseFamilies(_ tokens: [Token]) -> [string] {
    var out: [string] = []
    var current: [string] = []
    for t in tokens {
        if t.Kind == .comma {
            if !current.isEmpty { out.append(joinWords(current)) }
            current = []
        } else if t.Kind == .string {
            current.append(t.Value)
        } else if t.Kind == .ident {
            current.append(t.Value)
        }
    }
    if !current.isEmpty { out.append(joinWords(current)) }
    return out
}

func parseShadows(_ tokens: [Token]) -> Value? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return .none }
    var shadows: [ShadowValue] = []
    var lengths: [Value] = []
    var color: draw.Color? = nil
    var inset = false
    func flush() {
        if lengths.count >= 2 {
            shadows.append(ShadowValue(X: lengths[0], Y: lengths[1],
                                       Blur: lengths.count > 2 ? lengths[2] : .length(0, .px),
                                       Spread: lengths.count > 3 ? lengths[3] : .length(0, .px),
                                       Color: color, Inset: inset))
        }
        lengths = []
        color = nil
        inset = false
    }
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind == .comma {
            flush()
            i += 1
            continue
        }
        if t.Kind == .ident && lower(t.Value) == "inset" {
            inset = true
            i += 1
            continue
        }
        if let m = parseColorAt(tokens, i) {
            if case .color(let cc) = m.0 { color = cc }
            i += m.1
            continue
        }
        if let l = parseLengthValue(t, allowAuto: false) {
            lengths.append(l)
        }
        i += 1
    }
    flush()
    if shadows.isEmpty { return nil }
    return .shadows(shadows)
}

/// The value of one longhand, read from its tokens.
func parseValue(_ prop: Prop, _ tokens: [Token]) -> Value? {
    let t = tokens[0]
    let kw = t.Kind == .ident ? lower(t.Value) : ""
    switch prop {
    case .display:
        switch kw {
        case "none", "block", "inline", "inline-block", "flex", "inline-flex", "list-item", "table",
             "inline-table", "table-row", "table-cell", "table-row-group", "table-header-group",
             "table-footer-group", "table-caption", "table-column", "table-column-group", "contents",
             "grid", "inline-grid", "flow-root":
            return .keyword(kw)
        // The old flexbox's names, which line-clamp goes with.
        case "-webkit-box": return .keyword("flow-root")
        case "-webkit-inline-box": return .keyword("inline-block")
        default: return nil
        }
    case .position:
        switch kw {
        case "static", "relative", "absolute", "fixed", "sticky": return .keyword(kw)
        default: return nil
        }
    case .float:
        switch kw {
        case "none", "left", "right", "inline-start", "inline-end": return .keyword(kw)
        default: return nil
        }
    case .clear:
        switch kw {
        case "none", "left", "right", "both", "inline-start", "inline-end": return .keyword(kw)
        default: return nil
        }
    case .top, .right, .bottom, .left, .width, .height, .flexBasis:
        if let c = calcValue(tokens) { return c }
        return parseLengthValue(t, allowAuto: true)
    case .minWidth, .minHeight:
        if kw == "auto" { return .auto }
        if let c = calcValue(tokens) { return c }
        return parseLengthValue(t, allowAuto: false)
    case .maxWidth, .maxHeight:
        if kw == "none" { return .none }
        if let c = calcValue(tokens) { return c }
        return parseLengthValue(t, allowAuto: false)
    case .marginTop, .marginRight, .marginBottom, .marginLeft:
        if let c = calcValue(tokens) { return c }
        return parseLengthValue(t, allowAuto: true)
    case .direction:
        return kw == "ltr" || kw == "rtl" ? .keyword(kw) : nil
    case .backgroundAttachment:
        return kw == "scroll" || kw == "fixed" || kw == "local" ? .keyword(kw) : nil
    case .textFillColor:
        if kw == "currentcolor" { return .currentColor }
        return parseColorAt(tokens, 0)?.0
    case .unicodeBidi:
        switch kw {
        case "normal", "embed", "isolate", "bidi-override", "isolate-override", "plaintext": return .keyword(kw)
        default: return nil
        }
    case .columnCount:
        if kw == "auto" { return .auto }
        if t.Kind == .number && t.NumberVal >= 1 { return .number(t.NumberVal.rounded(.down)) }
        return nil
    case .columnWidth:
        if kw == "auto" { return .auto }
        return calcValue(tokens) ?? parseLengthValue(t, allowAuto: false)
    case .columnRuleWidth:
        return parseBorderWidth(t)
    case .columnRuleStyle:
        return parseBorderStyle(t)
    case .columnRuleColor:
        return parseColorValue(t)
    case .columnFill:
        return kw == "balance" || kw == "auto" || kw == "balance-all" ? .keyword(kw) : nil
    case .columnSpan:
        return kw == "none" || kw == "all" ? .keyword(kw) : nil
    case .breakInside:
        switch kw {
        case "auto", "avoid", "avoid-column", "avoid-page", "avoid-region": return .keyword(kw)
        default: return nil
        }
    case .paddingTop, .paddingRight, .paddingBottom, .paddingLeft, .textIndent, .rowGap, .columnGap:
        if (prop == .rowGap || prop == .columnGap) && kw == "normal" { return .normal }
        if let c = calcValue(tokens) { return c }
        return parseLengthValue(t, allowAuto: false)
    case .borderTopWidth, .borderRightWidth, .borderBottomWidth, .borderLeftWidth, .outlineWidth:
        return parseBorderWidth(t)
    case .borderTopStyle, .borderRightStyle, .borderBottomStyle, .borderLeftStyle:
        return parseBorderStyle(t)
    case .borderTopColor, .borderRightColor, .borderBottomColor, .borderLeftColor,
         .backgroundColor, .color, .textDecorationColor, .outlineColor, .accentColor:
        if let m = parseColorAt(tokens, 0) { return m.0 }
        return nil
    case .fill:
        // SVG's paint: none, a color, or currentColor; a url() paint
        // server stands for the color until gradients fill.
        if kw == "none" { return .none }
        if let m = parseColorAt(tokens, 0) { return m.0 }
        if !tokens.isEmpty && tokens[0].Kind == .url { return .currentColor }
        return nil
    case .borderTopLeftRadius, .borderTopRightRadius, .borderBottomRightRadius, .borderBottomLeftRadius:
        return parseLengthValue(t, allowAuto: false)
    case .backgroundImage:
        if kw == "none" { return .none }
        if t.Kind == .url { return .url(t.Value) }
        if t.Kind == .function && isImageSetName(lower(t.Value)) { return imageSetValue(tokens, 0) }
        if t.Kind == .function && isGradientName(lower(t.Value)) {
            if let g = parseGradient(tokens, 1, closeParen(tokens, from: 1)) { return .gradient(g) }
        }
        return nil
    case .maskMode:
        return kw == "alpha" || kw == "luminance" || kw == "match-source" ? .keyword(kw) : nil
    case .breakBefore, .breakAfter:
        switch kw {
        case "auto", "avoid", "avoid-page", "avoid-column", "avoid-region", "page", "column", "region", "left", "right", "recto", "verso", "all":
            return .keyword(kw)
        // page-break-before and -after's word for a forced break.
        case "always": return .keyword("page")
        default: return nil
        }
    case .orphans, .widows:
        if t.Kind == .number && t.NumberVal >= 1 { return .number(t.NumberVal) }
        return nil
    case .boxDecorationBreak:
        return kw == "slice" || kw == "clone" ? .keyword(kw) : nil
    case .backgroundRepeat, .maskRepeat:
        switch kw {
        case "no-repeat", "repeat", "repeat-x", "repeat-y", "space", "round": return .keyword(kw)
        default: return nil
        }
    case .backgroundSize, .maskSize:
        if kw == "cover" || kw == "contain" || kw == "auto" { return .keyword(kw) }
        return parseBackgroundSize(tokens)
    case .backgroundPosition, .objectPosition, .maskPosition:
        return parseBackgroundPosition(tokens)
    case .outlineStyle:
        switch kw {
        case "none", "hidden", "auto", "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset": return .keyword(kw)
        default: return nil
        }
    case .outlineOffset:
        return parseLengthValue(t, allowAuto: false) ?? calcValue(tokens)
    case .textDecorationStyle:
        switch kw {
        case "solid", "double", "dotted", "dashed", "wavy": return .keyword(kw)
        default: return nil
        }
    case .textDecorationThickness, .textUnderlineOffset:
        if kw == "auto" || kw == "from-font" { return .auto }
        return parseLengthValue(t, allowAuto: false) ?? calcValue(tokens)
    case .textShadow:
        if kw == "none" { return Value.none }
        return parseShadows(tokens)
    case .gridTemplateAreas:
        return parseTemplateAreas(tokens)
    case .textWrapMode:
        return kw == "wrap" || kw == "nowrap" ? .keyword(kw) : nil
    case .textWrapStyle:
        switch kw {
        case "auto", "balance", "pretty", "stable": return .keyword(kw)
        default: return nil
        }
    case .whiteSpaceCollapse:
        switch kw {
        case "collapse", "preserve", "preserve-breaks", "break-spaces", "preserve-spaces": return .keyword(kw)
        default: return nil
        }
    case .scrollbarColor:
        // auto, or the thumb's color then the track's.
        if kw == "auto" { return .string("") }
        guard let thumb = parseColorAt(tokens, 0), thumb.1 < tokens.count, let track = parseColorAt(tokens, thumb.1) else { return nil }
        if case .color(let a) = thumb.0, case .color(let b) = track.0 { return .shadows([ShadowValue(X: .color(a), Y: .color(b), Blur: .none, Spread: .none, Color: a, Inset: false)]) }
        return nil
    case .caretColor:
        if kw == "auto" { return .auto }
        return parseColorAt(tokens, 0)?.0
    case .colorScheme, .willChange, .touchAction, .contain, .scrollbarGutter:
        // Space-separated keywords, kept as words.
        var words: [string] = []
        for tok in tokens {
            guard tok.Kind == .ident else { if tok.Kind == .comma { continue }; return nil }
            words.append(lower(tok.Value))
        }
        return words.isEmpty ? nil : .keyword(joinWords(words))
    case .appearance:
        switch kw {
        case "none", "auto", "menulist-button", "textfield", "base-select", "button", "checkbox", "radio", "listbox",
             "menulist", "meter", "progress-bar", "searchfield", "textarea", "push-button", "slider-horizontal", "square-button":
            return .keyword(kw == "none" ? "none" : (kw == "base-select" ? "base-select" : "auto"))
        default: return nil
        }
    case .resize:
        switch kw {
        case "none", "both", "horizontal", "vertical", "block", "inline": return .keyword(kw == "block" ? "vertical" : (kw == "inline" ? "horizontal" : kw))
        default: return nil
        }
    case .overscrollBehaviorX, .overscrollBehaviorY:
        switch kw {
        case "auto", "contain", "none": return .keyword(kw)
        default: return nil
        }
    case .contentVisibility:
        switch kw {
        case "visible", "auto", "hidden": return .keyword(kw)
        default: return nil
        }
    case .containIntrinsicWidth, .containIntrinsicHeight:
        // `auto <length>` remembers a size; the length is what is used.
        if kw == "none" { return Value.none }
        for tok in tokens { if let l = parseLengthValue(tok, allowAuto: false) { return l } }
        return nil
    case .scrollBehavior:
        return kw == "auto" || kw == "smooth" ? .keyword(kw) : nil
    case .scrollSnapType, .scrollSnapAlign, .scrollSnapStop:
        var words: [string] = []
        for tok in tokens {
            guard tok.Kind == .ident else { return nil }
            words.append(lower(tok.Value))
        }
        return words.isEmpty ? nil : .keyword(joinWords(words))
    case .scrollPaddingTop, .scrollPaddingRight, .scrollPaddingBottom, .scrollPaddingLeft,
         .scrollMarginTop, .scrollMarginRight, .scrollMarginBottom, .scrollMarginLeft:
        return parseLengthValue(t, allowAuto: true) ?? calcValue(tokens)
    case .zoom:
        if kw == "normal" || kw == "reset" { return .number(1) }
        if t.Kind == .number && t.NumberVal > 0 { return .number(t.NumberVal) }
        if t.Kind == .percentage && t.NumberVal > 0 { return .number(t.NumberVal / 100) }
        return nil
    case .lineClamp:
        if kw == "none" { return .number(0) }
        if t.Kind == .number && t.NumberVal >= 1 { return .number(t.NumberVal) }
        return nil
    case .justifyItems, .justifySelf:
        // The leading `legacy`, `safe` and `unsafe` say nothing here.
        for tok in tokens where tok.Kind == .ident {
            let w = lower(tok.Value)
            switch w {
            case "auto", "normal", "stretch", "start", "end", "center", "left", "right", "self-start", "self-end",
                 "flex-start", "flex-end", "baseline":
                if w == "auto" && prop == .justifyItems { return nil }
                return .keyword(w)
            default: continue
            }
        }
        return nil
    case .backgroundClip, .backgroundOrigin:
        switch kw {
        case "border-box", "padding-box", "content-box": return .keyword(kw)
        case "text": return prop == .backgroundClip ? .keyword(kw) : nil
        default: return nil
        }
    case .objectFit:
        switch kw {
        case "fill", "contain", "cover", "none", "scale-down": return .keyword(kw)
        default: return nil
        }
    case .opacity, .flexGrow, .flexShrink:
        if t.Kind == .number { return .number(t.NumberVal) }
        if t.Kind == .percentage && prop == .opacity { return .number(t.NumberVal / 100) }
        return nil
    case .zIndex, .order, .tabSize:
        if kw == "auto" { return .auto }
        if t.Kind == .number { return .number(t.NumberVal) }
        return nil
    case .overflowX, .overflowY:
        return parseOverflow(t)
    case .boxShadow:
        return parseShadows(tokens)
    case .transitionProperty, .transitionDuration, .transitionTimingFunction, .transitionDelay, .transitionBehavior,
         .animationName, .animationDuration, .animationTimingFunction, .animationDelay,
         .animationIterationCount, .animationDirection, .animationFillMode, .animationPlayState:
        return parseAnimationLonghand(prop, tokens)
    case .containerType:
        switch kw {
        case "normal", "size", "inline-size": return .keyword(kw)
        default: return nil
        }
    case .containerName:
        return parseContainerName(tokens)
    case .transform:
        return parseTransformList(tokens)
    case .transformOrigin:
        return parseTransformOrigin(tokens)
    case .translate:
        return parseTranslateProperty(tokens)
    case .rotate:
        return parseRotateProperty(tokens)
    case .scale:
        return parseScaleProperty(tokens)
    case .clipPath:
        if kw == "none" { return Value.none }
        // A basic shape and a geometry box, in either order, or a box
        // alone (its border radius kept).
        var shape: ClipShape? = nil
        var box = ""
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t.Kind == .function {
                let end = closeParen(tokens, from: i + 1)
                guard let s = parseClipShape(lower(t.Value), Array(tokens[(i + 1)..<end])) else { return nil }
                shape = s
                i = end + 1
                continue
            }
            if t.Kind == .ident {
                switch lower(t.Value) {
                case "border-box", "padding-box", "content-box", "margin-box": box = lower(t.Value)
                case "fill-box", "stroke-box", "view-box": box = "border-box"
                default: return nil
                }
            } else if t.Kind == .url {
                // A url() to an SVG <clipPath>: not drawn.
                return Value.none
            }
            i += 1
        }
        if var s = shape {
            if !box.isEmpty { s.Box = box }
            return .clipShape(s)
        }
        if !box.isEmpty {
            var s = ClipShape(Kind: "box", Args: [])
            s.Box = box
            return .clipShape(s)
        }
        return Value.none
    case .borderImageSlice:
        // One to four numbers or percentages, and fill.
        var sides: [Value] = []
        var fill = false
        for tk in tokens {
            if tk.Kind == .ident && lower(tk.Value) == "fill" { fill = true; continue }
            if tk.Kind == .number && tk.NumberVal >= 0 { sides.append(.number(tk.NumberVal)); continue }
            if tk.Kind == .percentage && tk.NumberVal >= 0 { sides.append(.length(tk.NumberVal, .percent)); continue }
            return nil
        }
        if sides.isEmpty || sides.count > 4 { return nil }
        if fill { sides.append(.keyword("fill")) }
        return .list(sides)
    case .borderImageWidth, .borderImageOutset:
        // One to four lengths or numbers (multiples of the border's
        // width); widths may be auto or percentages too.
        var sides: [Value] = []
        for tk in tokens {
            if tk.Kind == .number && tk.NumberVal >= 0 { sides.append(.number(tk.NumberVal)); continue }
            if prop == .borderImageWidth && tk.Kind == .ident && lower(tk.Value) == "auto" { sides.append(.auto); continue }
            if prop == .borderImageOutset && tk.Kind == .percentage { return nil }
            if let v = parseLengthValue(tk, allowAuto: false) { sides.append(v); continue }
            return nil
        }
        if sides.isEmpty || sides.count > 4 { return nil }
        return .list(sides)
    case .borderImageRepeat:
        var modes: [Value] = []
        for tk in tokens {
            let w = tk.Kind == .ident ? lower(tk.Value) : ""
            if w != "stretch" && w != "repeat" && w != "round" && w != "space" { return nil }
            modes.append(.keyword(w))
        }
        if modes.isEmpty || modes.count > 2 { return nil }
        return .list(modes)
    case .maskImage, .borderImageSource:
        if kw == "none" { return Value.none }
        if t.Kind == .url { return .url(t.Value) }
        if t.Kind == .function && isImageSetName(lower(t.Value)) {
            // A mask or border image is drawn at its pixels: the url alone.
            if case .list(let parts) = imageSetValue(tokens, 0) ?? .none { return parts[0] }
            return imageSetValue(tokens, 0)
        }
        if t.Kind == .function && isGradientName(lower(t.Value)) {
            if let g = parseGradient(tokens, 1, closeParen(tokens, from: 1)) { return .gradient(g) }
        }
        return nil
    case .mixBlendMode:
        switch kw {
        case "normal", "multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn",
             "hard-light", "soft-light", "difference", "exclusion", "plus-lighter",
             "hue", "saturation", "color", "luminosity":
            return .keyword(kw)
        default: return nil
        }
    case .isolation:
        return kw == "auto" || kw == "isolate" ? .keyword(kw) : nil
    case .filter, .backdropFilter:
        // Only blur() is drawn; the other filter functions are dropped.
        if kw == "none" { return Value.none }
        var i = 0
        while i < tokens.count {
            if tokens[i].Kind == .function && lower(tokens[i].Value) == "blur" {
                let end = closeParen(tokens, from: i + 1)
                var j = i + 1
                while j < end {
                    if let v = parseLengthValue(tokens[j], allowAuto: false) { return v }
                    j += 1
                }
                return .length(0, .px)
            }
            i += 1
        }
        return nil
    case .verticalAlign:
        switch kw {
        case "baseline", "middle", "top", "bottom", "text-top", "text-bottom", "sub", "super": return .keyword(kw)
        default: return parseLengthValue(t, allowAuto: false)
        }
    case .textDecorationLine:
        var words: [string] = []
        for tok in tokens {
            if tok.Kind == .ident { words.append(lower(tok.Value)) }
        }
        return .keyword(joinWords(words))
    case .flexDirection:
        switch kw {
        case "row", "row-reverse", "column", "column-reverse": return .keyword(kw)
        default: return nil
        }
    case .flexWrap:
        switch kw {
        case "nowrap", "wrap", "wrap-reverse": return .keyword(kw)
        default: return nil
        }
    case .justifyContent, .alignContent:
        switch kw {
        case "flex-start", "flex-end", "center", "space-between", "space-around", "space-evenly",
             "start", "end", "left", "right", "normal", "stretch":
            return .keyword(kw)
        default: return nil
        }
    case .alignItems, .alignSelf:
        switch kw {
        case "stretch", "flex-start", "flex-end", "center", "baseline", "auto", "start", "end", "normal", "self-start", "self-end":
            return .keyword(kw)
        default: return nil
        }
    case .tableLayout:
        if kw == "auto" || kw == "fixed" { return .keyword(kw) }
        return nil
    case .gridTemplateColumns, .gridTemplateRows:
        if kw == "none" { return .none }
        let tracks = parseTracks(tokens, 0, tokens.count)
        return tracks.isEmpty ? nil : .tracks(tracks)
    case .gridAutoRows, .gridAutoColumns:
        let tracks = parseTracks(tokens, 0, tokens.count)
        return tracks.isEmpty ? nil : .tracks(tracks)
    case .aspectRatio:
        // auto, or a width / height ratio (after auto: the ratio used
        // where the box has none of its own, which is here always).
        var nums: [float32] = []
        for tok in tokens where tok.Kind == .number { nums.append(tok.NumberVal) }
        if nums.isEmpty { return kw == "auto" ? Value.auto : nil }
        let ratio = nums.count >= 2 ? (nums[1] > 0 ? nums[0] / nums[1] : 0) : nums[0]
        return .number(ratio)
    case .gridAutoFlow:
        // row or column; dense packing isn't done.
        for tok in tokens where tok.Kind == .ident {
            let w = lower(tok.Value)
            if w == "row" || w == "column" { return .keyword(w) }
        }
        if kw == "dense" { return .keyword("row") }
        return nil
    case .gridColumn, .gridRow:
        return .placement(parsePlacement(tokens))
    case .gridColumnStart, .gridRowStart:
        return .placement(parsePlacementSide(tokens, end: false))
    case .gridColumnEnd, .gridRowEnd:
        return .placement(parsePlacementSide(tokens, end: true))
    case .boxSizing:
        if kw == "content-box" || kw == "border-box" { return .keyword(kw) }
        return nil
    case .fontFamily:
        let fams = parseFamilies(tokens)
        return fams.isEmpty ? nil : .families(fams)
    case .fontSize:
        return parseFontSizeValue(t)
    case .fontWeight:
        if t.Kind == .number { return .number(t.NumberVal) }
        switch kw {
        case "normal", "bold", "bolder", "lighter": return .keyword(kw)
        default: return nil
        }
    case .fontStyle:
        switch kw {
        case "normal", "italic", "oblique": return .keyword(kw)
        default: return nil
        }
    case .lineHeight:
        return parseLineHeightValue(t)
    case .textAlign:
        switch kw {
        case "left", "right", "center", "justify", "start", "end", "-webkit-center": return .keyword(kw == "-webkit-center" ? "center" : kw)
        default: return nil
        }
    case .textTransform:
        switch kw {
        case "none", "uppercase", "lowercase", "capitalize": return .keyword(kw)
        default: return nil
        }
    case .letterSpacing, .wordSpacing:
        if kw == "normal" { return .normal }
        return parseLengthValue(t, allowAuto: false)
    case .whiteSpace:
        switch kw {
        case "normal", "nowrap", "pre", "pre-wrap", "pre-line", "break-spaces": return .keyword(kw == "break-spaces" ? "pre-wrap" : kw)
        default: return nil
        }
    case .overflowWrap:
        switch kw {
        case "normal", "break-word", "anywhere": return .keyword(kw)
        default: return nil
        }
    case .wordBreak:
        switch kw {
        case "normal", "break-all", "keep-all", "break-word": return .keyword(kw)
        default: return nil
        }
    case .textOverflow:
        switch kw {
        case "clip", "ellipsis": return .keyword(kw)
        default: return nil
        }
    case .listStyleType:
        switch kw {
        case "none", "disc", "circle", "square", "decimal", "decimal-leading-zero", "lower-alpha", "upper-alpha",
             "lower-latin", "upper-latin", "lower-roman", "upper-roman":
            return .keyword(kw)
        default: return nil
        }
    case .listStylePosition:
        if kw == "inside" || kw == "outside" { return .keyword(kw) }
        return nil
    case .cursor:
        // `url(hand.png) 4 4, pointer`: the keyword the list falls back to.
        // (Images as cursors are not drawn yet: the fallback is.)
        var last = ""
        for tok in tokens where tok.Kind == .ident { last = lower(tok.Value) }
        switch last {
        case "auto", "default", "none", "context-menu", "help", "pointer", "progress", "wait", "cell", "crosshair", "text", "vertical-text", "alias", "copy", "move", "no-drop", "not-allowed", "grab", "grabbing", "all-scroll", "col-resize", "row-resize", "n-resize", "e-resize", "s-resize", "w-resize", "ne-resize", "nw-resize", "se-resize", "sw-resize", "ew-resize", "ns-resize", "nesw-resize", "nwse-resize", "zoom-in", "zoom-out":
            return .keyword(last)
        default: return nil
        }
    case .pointerEvents:
        // SVG's values are all "the element takes the pointer" here.
        switch kw {
        case "auto", "none", "visiblepainted", "visiblefill", "visiblestroke", "visible", "painted", "fill",
             "stroke", "all", "bounding-box":
            return .keyword(kw)
        default: return nil
        }
    case .userSelect:
        switch kw {
        case "auto", "text", "none", "contain", "all": return .keyword(kw)
        default: return nil
        }
    case .visibility:
        switch kw {
        case "visible", "hidden", "collapse": return .keyword(kw)
        default: return nil
        }
    case .scrollbarWidth:
        if kw == "auto" || kw == "thin" || kw == "none" { return .keyword(kw) }
        return nil
    case .borderCollapse:
        if kw == "collapse" || kw == "separate" { return .keyword(kw) }
        return nil
    case .borderSpacing:
        return parseLengthValue(t, allowAuto: false)
    case .counterReset, .counterIncrement, .counterSet:
        // Names, each with an optional number: "name\u{1F}n".
        if kw == "none" { return .none }
        var names: [string] = []
        var numbers: [int] = []
        for tok in tokens {
            if tok.Kind == .ident {
                names.append(tok.Value)
                numbers.append(prop == .counterIncrement ? 1 : 0)
            } else if tok.Kind == .number && !numbers.isEmpty {
                numbers[numbers.count - 1] = int(tok.NumberVal)
            } else {
                return nil
            }
        }
        var parts: [string] = []
        var k = 0
        while k < names.count {
            parts.append(names[k] + "\u{1F}" + "\(numbers[k])")
            k += 1
        }
        return parts.isEmpty ? nil : .families(parts)
    case .quotes:
        // Pairs of strings; auto is the language's, none none.
        if kw == "none" { return .none }
        if kw == "auto" { return .auto }
        var parts: [string] = []
        for tok in tokens where tok.Kind == .string { parts.append(tok.Value) }
        return parts.isEmpty || parts.count % 2 != 0 ? nil : .families(parts)
    case .content:
        // Strings, attr(), counter() as "\u{2}name\u{1F}style",
        // counters() as "\u{3}name\u{1F}separator\u{1F}style", and the
        // quote keywords as "\u{4}keyword".
        if kw == "none" || kw == "normal" { return .none }
        var parts: [string] = []
        var i = 0
        while i < tokens.count {
            let tok = tokens[i]
            if tok.Kind == .string {
                parts.append(tok.Value)
            } else if tok.Kind == .function && lower(tok.Value) == "attr" {
                let end = closeParen(tokens, from: i + 1)
                if i + 1 < end && tokens[i + 1].Kind == .ident {
                    parts.append("\u{1}" + lower(tokens[i + 1].Value))
                }
                i = end
            } else if tok.Kind == .function && (lower(tok.Value) == "counter" || lower(tok.Value) == "counters") {
                let end = closeParen(tokens, from: i + 1)
                var names: [string] = []
                var separator = ""
                var k = i + 1
                while k < end {
                    if tokens[k].Kind == .ident { names.append(tokens[k].Value) }
                    if tokens[k].Kind == .string { separator = tokens[k].Value }
                    k += 1
                }
                if !names.isEmpty {
                    let style = names.count > 1 ? lower(names[1]) : "decimal"
                    if lower(tok.Value) == "counter" {
                        parts.append("\u{2}" + names[0] + "\u{1F}" + style)
                    } else {
                        parts.append("\u{3}" + names[0] + "\u{1F}" + separator + "\u{1F}" + style)
                    }
                }
                i = end
            } else if tok.Kind == .function {
                i = closeParen(tokens, from: i + 1)
            } else if tok.Kind == .ident {
                let word = lower(tok.Value)
                if word == "open-quote" || word == "close-quote" || word == "no-open-quote" || word == "no-close-quote" {
                    parts.append("\u{4}" + word)
                }
            }
            i += 1
        }
        return .families(parts)
    }
}

/// A basic shape's arguments: inset(), circle(), ellipse() or
/// polygon(), with the shapes' "at" positions and inset's "round".
func parseClipShape(_ name: string, _ tokens: [Token]) -> ClipShape? {
    var i = 0
    // One length or percentage, calc() too, or nil.
    func length() -> Value? {
        if i >= tokens.count { return nil }
        let t = tokens[i]
        if t.Kind == .function {
            let end = closeParen(tokens, from: i + 1)
            let v = calcValue(Array(tokens[i..<(end < tokens.count ? end + 1 : tokens.count)]))
            if v != nil { i = end + 1 }
            return v
        }
        if let v = parseLengthValue(t, allowAuto: false) {
            i += 1
            return v
        }
        return nil
    }
    func word() -> string {
        return i < tokens.count && tokens[i].Kind == .ident ? lower(tokens[i].Value) : ""
    }
    // "at x y", the centre, which defaults to the box's.
    func position() -> [Value]? {
        var x: Value = .length(50, .percent)
        var y: Value = .length(50, .percent)
        if word() != "at" { return [x, y] }
        i += 1
        var got: [Value] = []
        var sawY = false
        while i < tokens.count && got.count < 2 {
            switch word() {
            case "left": got.append(.length(0, .percent)); i += 1
            case "right": got.append(.length(100, .percent)); i += 1
            case "top": got.append(.length(0, .percent)); sawY = got.count == 1; i += 1
            case "bottom": got.append(.length(100, .percent)); sawY = got.count == 1; i += 1
            case "center": got.append(.length(50, .percent)); i += 1
            default:
                guard let v = length() else { return nil }
                got.append(v)
            }
        }
        if got.count == 1 {
            if sawY { y = got[0] } else { x = got[0] }
        } else if got.count == 2 {
            // "top left" names y first.
            if sawY { y = got[0]; x = got[1] } else { x = got[0]; y = got[1] }
        }
        return [x, y]
    }
    switch name {
    case "inset":
        var sides: [Value] = []
        while sides.count < 4, let v = length() { sides.append(v) }
        if sides.isEmpty { return nil }
        while sides.count < 4 {
            // As margin takes one to four.
            switch sides.count {
            case 1: sides.append(sides[0])
            case 2: sides.append(sides[0])
            default: sides.append(sides[1])
            }
        }
        var radius: Value = .length(0, .px)
        if word() == "round" {
            i += 1
            radius = length() ?? radius
        }
        return ClipShape(Kind: "inset", Args: sides + [radius])
    case "circle", "ellipse":
        var radii: [Value] = []
        let wanted = name == "circle" ? 1 : 2
        while radii.count < wanted {
            let w = word()
            if w == "closest-side" || w == "farthest-side" {
                radii.append(.keyword(w))
                i += 1
            } else if let v = length() {
                radii.append(v)
            } else {
                break
            }
        }
        while radii.count < wanted { radii.append(.keyword("closest-side")) }
        guard let at = position() else { return nil }
        return ClipShape(Kind: name, Args: radii + at)
    case "path":
        // An optional fill rule, then the path data as a string.
        var rule = "nonzero"
        if word() == "nonzero" || word() == "evenodd" {
            rule = word()
            i += 1
            if i < tokens.count && tokens[i].Kind == .comma { i += 1 }
        }
        guard i < tokens.count, tokens[i].Kind == .string else { return nil }
        var shape = ClipShape(Kind: "path", Args: [])
        shape.Words = [tokens[i].Value]
        shape.Rule = rule
        return shape
    case "shape":
        // shape(<fill-rule>? from x y, <command>#): commands as SVG's
        // letters with their arguments.
        var shape = ClipShape(Kind: "shape", Args: [])
        if word() == "nonzero" || word() == "evenodd" {
            shape.Rule = word()
            i += 1
        }
        guard word() == "from" else { return nil }
        i += 1
        guard let fx = length(), let fy = length() else { return nil }
        shape.Words.append("M")
        shape.Args += [fx, fy]
        while i < tokens.count {
            if tokens[i].Kind == .comma { i += 1; continue }
            let command = word()
            i += 1
            if command == "close" {
                shape.Words.append("Z")
                continue
            }
            let relative = word() == "by"
            guard word() == "to" || word() == "by" else { return nil }
            i += 1
            func letter(_ l: string) -> string { return relative ? l.lowercased() : l }
            switch command {
            case "move", "line", "smooth", "arc":
                guard let x = length(), let y = length() else { return nil }
                shape.Words.append(letter(command == "move" ? "M" : "L"))
                shape.Args += [x, y]
                // The rest of an arc or smooth curve: drawn straight.
                while i < tokens.count && tokens[i].Kind != .comma { i += 1 }
            case "hline", "vline":
                guard let v = length() else { return nil }
                shape.Words.append(letter(command == "hline" ? "H" : "V"))
                shape.Args.append(v)
            case "curve":
                guard let x = length(), let y = length(), word() == "with" else { return nil }
                i += 1
                guard let c1x = length(), let c1y = length() else { return nil }
                if i < tokens.count && tokens[i].Kind == .delim && tokens[i].Value == "/" {
                    i += 1
                    guard let c2x = length(), let c2y = length() else { return nil }
                    shape.Words.append(letter("C"))
                    shape.Args += [c1x, c1y, c2x, c2y, x, y]
                } else {
                    shape.Words.append(letter("Q"))
                    shape.Args += [c1x, c1y, x, y]
                }
            default:
                return nil
            }
        }
        return shape
    case "polygon":
        // An optional fill rule, then points split by commas.
        var rule = "nonzero"
        if word() == "nonzero" || word() == "evenodd" {
            rule = word()
            i += 1
            if i < tokens.count && tokens[i].Kind == .comma { i += 1 }
        }
        var points: [Value] = []
        while i < tokens.count {
            guard let x = length(), let y = length() else { return nil }
            points.append(x)
            points.append(y)
            if i < tokens.count && tokens[i].Kind == .comma { i += 1 }
        }
        if points.count < 6 { return nil }
        var shape = ClipShape(Kind: "polygon", Args: points)
        shape.Rule = rule
        return shape
    default:
        return nil
    }
}

/// The density image-set() picks for: the device's pixels to a CSS
/// pixel, 2 for the Retina displays the engine mostly draws on. A host
/// may set it.
public var ImageSetDensity: float32 = 2

/// image-set() (and -webkit-image-set()) at tokens[i], its function
/// token: the candidate for ImageSetDensity -- the least dense at or
/// above it, else the densest -- as `.list([.url, .number(density)])`,
/// or a gradient candidate as itself.
func imageSetValue(_ tokens: [Token], _ i: int) -> Value? {
    let end = closeParen(tokens, from: i + 1)
    var best: Value? = nil
    var bestDensity: float32 = -1
    for item in splitArgs(tokens, i + 1, end) {
        if item.isEmpty { continue }
        var image: Value? = nil
        var density: float32 = 1
        var k = 0
        if item[0].Kind == .string || item[0].Kind == .url {
            image = .url(item[0].Value)
            k = 1
        } else if item[0].Kind == .function && isGradientName(lower(item[0].Value)) {
            let close = closeParen(item, from: 1)
            if let g = parseGradient(item, 1, close) { image = .gradient(g) }
            k = close + 1
        }
        while k < item.count {
            let t = item[k]
            if t.Kind == .dimension {
                switch lower(t.Unit) {
                case "x", "dppx": density = t.NumberVal
                case "dpi": density = t.NumberVal / 96
                case "dpcm": density = t.NumberVal * 2.54 / 96
                default: break
                }
            }
            k += 1
        }
        guard let img = image, density > 0 else { continue }
        let better = bestDensity < 0
            || (density >= ImageSetDensity && (bestDensity < ImageSetDensity || density < bestDensity))
            || (bestDensity < ImageSetDensity && density > bestDensity)
        if better {
            best = img
            bestDensity = density
        }
    }
    guard let b = best else { return nil }
    if case .url(_) = b { return .list([b, .number(bestDensity)]) }
    return b
}

func isImageSetName(_ name: string) -> bool {
    return name == "image-set" || name == "-webkit-image-set"
}

func isGradientName(_ name: string) -> bool {
    return name == "linear-gradient" || name == "-webkit-linear-gradient" || name == "repeating-linear-gradient" ||
        name == "radial-gradient" || name == "-webkit-radial-gradient" || name == "repeating-radial-gradient" ||
        name == "conic-gradient" || name == "repeating-conic-gradient"
}

/// The index of the paren closing a function whose arguments start at
/// `from`, or the token count.
func closeParen(_ tokens: [Token], from: int) -> int {
    var depth = 1
    var i = from
    while i < tokens.count {
        if tokens[i].Kind == .function || tokens[i].Kind == .openParen { depth += 1 }
        if tokens[i].Kind == .closeParen {
            depth -= 1
            if depth == 0 { return i }
        }
        i += 1
    }
    return tokens.count
}

/// A linear-gradient's arguments: an angle or a direction, then color
/// stops with optional positions. A radial gradient is drawn as a
/// linear one from its centre color outward, which is near enough.
func parseGradient(_ tokens: [Token], _ start: int, _ end: int) -> draw.LinearGradient? {
    // Split the arguments at top-level commas.
    var args: [[Token]] = []
    var current: [Token] = []
    var depth = 0
    var i = start
    while i < end {
        let t = tokens[i]
        if t.Kind == .function || t.Kind == .openParen { depth += 1 }
        if t.Kind == .closeParen { depth -= 1 }
        if t.Kind == .comma && depth == 0 {
            args.append(current)
            current = []
        } else {
            current.append(t)
        }
        i += 1
    }
    if !current.isEmpty { args.append(current) }
    if args.isEmpty { return nil }
    // `in <space> [<method> hue]`, with the direction or shape or on its
    // own: the colors between stops are mixed in that space.
    var space = ""
    var hueMethod = "shorter"
    var h = 0
    while h < args[0].count {
        if args[0][h].Kind == .ident && lower(args[0][h].Value) == "in" && h + 1 < args[0].count && args[0][h + 1].Kind == .ident {
            space = lower(args[0][h + 1].Value)
            if space == "xyz" { space = "xyz-d65" }
            var take = 2
            if h + 3 < args[0].count && args[0][h + 3].Kind == .ident && lower(args[0][h + 3].Value) == "hue" {
                hueMethod = lower(args[0][h + 2].Value)
                take = 4
            }
            args[0].removeSubrange(h..<(h + take))
            if args[0].isEmpty { args.removeFirst() }
            break
        }
        h += 1
    }
    if !space.isEmpty && (space == "rgb" || !colorSpaces.contains(space)) { return nil }
    if args.isEmpty { return nil }
    var angle: float32 = 180
    var firstStop = 0
    let head = args[0]
    if head.count == 1 && head[0].Kind == .dimension {
        let unit = head[0].Unit
        if unit == "deg" { angle = head[0].NumberVal }
        else if unit == "turn" { angle = head[0].NumberVal * 360 }
        else if unit == "rad" { angle = head[0].NumberVal * 57.29578 }
        else if unit == "grad" { angle = head[0].NumberVal * 0.9 }
        firstStop = 1
    } else if head.count >= 2 && head[0].Kind == .ident && lower(head[0].Value) == "to" {
        var dx: float32 = 0
        var dy: float32 = 0
        var k = 1
        while k < head.count {
            switch lower(head[k].Value) {
            case "left": dx = -1
            case "right": dx = 1
            case "top": dy = -1
            case "bottom": dy = 1
            default: break
            }
            k += 1
        }
        if dx == 0 && dy == 0 { dy = 1 }
        // The angle whose direction is (dx, dy), with 0 pointing up.
        if dx == 0 { angle = dy > 0 ? 180 : 0 }
        else if dy == 0 { angle = dx > 0 ? 90 : 270 }
        else if dx > 0 { angle = dy > 0 ? 135 : 45 }
        else { angle = dy > 0 ? 225 : 315 }
        firstStop = 1
    }
    let fname = start > 0 && tokens[start - 1].Kind == .function ? lower(tokens[start - 1].Value) : ""
    let radial = fname.hasSuffix("radial-gradient")
    let conic = fname.hasSuffix("conic-gradient")
    var conicShape: draw.ConicShape? = nil
    if conic {
        // `from <angle>` and `at <position>`, either or both, before the
        // stops.
        angle = 0
        firstStop = 0
        var c = draw.ConicShape()
        if parseColorAt(head, 0) == nil {
            var k = 0
            while k < head.count {
                let word = head[k].Kind == .ident ? lower(head[k].Value) : ""
                if word == "from" && k + 1 < head.count {
                    if let a = angleRadians(head[k + 1].NumberVal, lower(head[k + 1].Unit)) { angle = a * 57.29578 }
                    k += 2
                    continue
                }
                if word == "at" {
                    var axis = 0
                    var j = k + 1
                    while j < head.count && axis < 2 {
                        let p = head[j]
                        let kw = p.Kind == .ident ? lower(p.Value) : ""
                        var frac: float32 = -1
                        var px: float32 = 0
                        switch kw {
                        case "left": frac = 0; axis = 0
                        case "right": frac = 1; axis = 0
                        case "top": frac = 0; axis = 1
                        case "bottom": frac = 1; axis = 1
                        case "center": frac = 0.5
                        default:
                            if p.Kind == .percentage { frac = p.NumberVal / 100 }
                            else if case .length(let n, .px) = parseLengthValue(p, allowAuto: false) ?? .none { frac = 0; px = n }
                        }
                        if axis == 0 { c.CenterX = frac; c.OffsetX = px } else { c.CenterY = frac; c.OffsetY = px }
                        axis += 1
                        j += 1
                    }
                    k = j
                    continue
                }
                k += 1
            }
            firstStop = 1
        }
        conicShape = c
    }
    var shape: draw.RadialShape? = nil
    if radial {
        var r = draw.RadialShape()
        if let (parsed, isHead) = parseRadialHead(head) {
            r = parsed
            if isHead { firstStop = 1 }
        }
        shape = r
    }
    var stops: [draw.GradientStop] = []
    var positions: [float32] = []
    var lengths = false
    var k = firstStop
    while k < args.count {
        let arg = args[k]
        if arg.isEmpty { k += 1; continue }
        guard let m = parseColorAt(arg, 0) else { k += 1; continue }
        var color = draw.Color.black
        if case .color(let c) = m.0 { color = c }
        // Up to two positions: a fraction of the line, and pixels along
        // it (a length, or calc()'s length part), resolved when drawn.
        var places: [(frac: float32, px: float32)] = []
        var p = m.1
        while p < arg.count && places.count < 2 {
            let pt = arg[p]
            if pt.Kind == .percentage {
                places.append((frac: pt.NumberVal / 100, px: 0))
            } else if pt.Kind == .number {
                places.append((frac: pt.NumberVal, px: 0))
            } else if conic && pt.Kind == .dimension, let a = angleRadians(pt.NumberVal, lower(pt.Unit)) {
                places.append((frac: a / 6.2831853, px: 0))
            } else if !conic, pt.Kind == .dimension, let len = stopLength(pt.NumberVal, lower(pt.Unit)) {
                places.append((frac: 0, px: len))
            } else if !conic && pt.Kind == .function {
                let end = closeParen(arg, from: p + 1)
                guard case .calc(let terms) = calcValue(Array(arg[p..<(end < arg.count ? end + 1 : arg.count)])) ?? .none else { break }
                var frac: float32 = 0
                var px: float32 = 0
                for t in terms {
                    if t.Unit == .percent { frac += t.Number / 100 }
                    else if let u = t.Unit, let len = stopLength(t.Number, unitName(u)) { px += len }
                }
                places.append((frac: frac, px: px))
                p = end
            } else {
                break
            }
            p += 1
        }
        for place in places {
            var stop = draw.GradientStop(color, at: place.frac)
            stop.Length = place.px
            if place.px != 0 { lengths = true }
            stops.append(stop)
            positions.append(place.frac)
        }
        // `red 10% 20%` gives a stop at each, one color between; no
        // position, a stop placed later.
        if places.isEmpty {
            stops.append(draw.GradientStop(color, at: -1))
            positions.append(-1)
        }
        k += 1
    }
    if stops.isEmpty { return nil }
    if lengths {
        if !space.isEmpty && space != "srgb" { stops = interpolatedStops(stops, space, hueMethod) }
        // Placed once the line's length is known (draw's FixStops).
        var g = draw.LinearGradient(angle: angle, stops: stops)
        g.Radial = shape
        g.Conic = conicShape
        g.Repeating = fname.hasPrefix("repeating-")
        g.Unresolved = true
        return g
    }
    // Missing positions: the first is 0, the last 1, the rest spread
    // evenly between the ones given.
    if stops[0].Position < 0 { stops[0].Position = 0 }
    if stops[stops.count - 1].Position < 0 { stops[stops.count - 1].Position = 1 }
    var i2 = 1
    while i2 < stops.count - 1 {
        if stops[i2].Position < 0 {
            var j = i2 + 1
            while j < stops.count && stops[j].Position < 0 { j += 1 }
            let from = stops[i2 - 1].Position
            let to = stops[j].Position
            let n = float32(j - i2 + 1)
            var m2 = i2
            while m2 < j {
                stops[m2].Position = from + (to - from) * float32(m2 - i2 + 1) / n
                m2 += 1
            }
            i2 = j
        } else {
            i2 += 1
        }
    }
    var i3 = 1
    while i3 < stops.count {
        if stops[i3].Position < stops[i3 - 1].Position { stops[i3].Position = stops[i3 - 1].Position }
        i3 += 1
    }
    if !space.isEmpty && space != "srgb" { stops = interpolatedStops(stops, space, hueMethod) }
    var g = draw.LinearGradient(angle: angle, stops: stops)
    g.Radial = shape
    g.Conic = conicShape
    g.Repeating = fname.hasPrefix("repeating-")
    return g
}

/// A gradient's stops with the colors between each pair mixed in a
/// color space: sixteen steps a pair, drawn as sRGB between them. Stops
/// whose positions wait on the line's length get steps without one,
/// which FixStops spreads evenly between them.
func interpolatedStops(_ stops: [draw.GradientStop], _ space: string, _ hueMethod: string) -> [draw.GradientStop] {
    if stops.count < 2 { return stops }
    let steps = 16
    var out: [draw.GradientStop] = [stops[0]]
    var i = 1
    while i < stops.count {
        let a = stops[i - 1]
        let b = stops[i]
        let known = a.Length == 0 && b.Length == 0 && a.Position >= 0 && b.Position >= 0
        if a.Color != b.Color && (!known || b.Position > a.Position) {
            var k = 1
            while k < steps {
                let t = float64(k) / float64(steps)
                let pos: float32 = known ? a.Position + (b.Position - a.Position) * float32(t) : -1
                out.append(draw.GradientStop(mixIn(space, hueMethod, a.Color, b.Color, t), at: pos))
                k += 1
            }
        }
        out.append(b)
        i += 1
    }
    return out
}

/// A gradient stop's length in pixels: absolute units, and em and rem
/// at the default 16px (a stop knows no font size).
func stopLength(_ n: float32, _ unit: string) -> float32? {
    switch unit {
    case "px": return n
    case "pt": return n * 4 / 3
    case "pc": return n * 16
    case "in": return n * 96
    case "cm": return n * 96 / 2.54
    case "mm": return n * 96 / 25.4
    case "q": return n * 96 / 101.6
    case "em", "rem": return n * 16
    default: return nil
    }
}

func unitName(_ u: Unit) -> string {
    switch u {
    case .px: return "px"
    case .em: return "em"
    case .rem: return "rem"
    default: return ""
    }
}

/// A radial gradient's first argument -- its shape, size and `at`
/// position -- or nil with isHead false where it's already a stop.
func parseRadialHead(_ head: [Token]) -> (draw.RadialShape, bool)? {
    var r = draw.RadialShape()
    if head.isEmpty { return nil }
    if parseColorAt(head, 0) != nil { return (r, false) }
    var sizes: [float32] = []
    var k = 0
    while k < head.count {
        let t = head[k]
        let word = t.Kind == .ident ? lower(t.Value) : ""
        if word == "at" {
            // One or two positions: keywords, percentages or lengths.
            var xs: [Token] = []
            var j = k + 1
            while j < head.count { xs.append(head[j]); j += 1 }
            var axis = 0
            var m = 0
            while m < xs.count && m < 2 {
                let p = xs[m]
                let kw = p.Kind == .ident ? lower(p.Value) : ""
                var frac: float32 = -1
                var px: float32 = 0
                var isY = axis == 1
                switch kw {
                case "left": frac = 0; isY = false
                case "right": frac = 1; isY = false
                case "top": frac = 0; isY = true
                case "bottom": frac = 1; isY = true
                case "center": frac = 0.5
                default:
                    if p.Kind == .percentage { frac = p.NumberVal / 100 }
                    else if p.Kind == .number && p.NumberVal == 0 { frac = 0 }
                    else if p.Kind == .dimension && p.Unit == "px" { frac = 0; px = p.NumberVal }
                }
                if frac >= 0 {
                    if isY { r.CenterY = frac; r.OffsetY = px } else { r.CenterX = frac; r.OffsetX = px }
                    axis = isY ? 0 : 1
                }
                m += 1
            }
            break
        }
        switch word {
        case "circle": r.Circle = true
        case "ellipse": r.Circle = false
        case "closest-side": r.Extent = .closestSide
        case "closest-corner": r.Extent = .closestCorner
        case "farthest-side": r.Extent = .farthestSide
        case "farthest-corner": r.Extent = .farthestCorner
        default:
            if t.Kind == .dimension && t.Unit == "px" { sizes.append(t.NumberVal) }
        }
        k += 1
    }
    if !sizes.isEmpty {
        r.Extent = .sized
        r.SizeX = sizes[0]
        r.SizeY = sizes.count > 1 ? sizes[1] : sizes[0]
        if sizes.count == 1 { r.Circle = true }
    }
    return (r, true)
}

func parseBackgroundSize(_ tokens: [Token]) -> Value? {
    if tokens.isEmpty { return nil }
    if tokens[0].Kind == .ident {
        let kw = lower(tokens[0].Value)
        if kw == "cover" || kw == "contain" || kw == "auto" { return .keyword(kw) }
        return nil
    }
    var words: [string] = []
    for t in tokens {
        if t.Kind == .ident { words.append(lower(t.Value)) }
        else if t.Kind == .percentage || t.Kind == .dimension || t.Kind == .number { words.append(t.Value) }
    }
    return .keyword(joinWords(words))
}

func parseBackgroundPosition(_ tokens: [Token]) -> Value? {
    var words: [string] = []
    for t in tokens {
        if t.Kind == .ident { words.append(lower(t.Value)) }
        else if t.Kind == .percentage || t.Kind == .dimension || t.Kind == .number { words.append(t.Value) }
    }
    if words.isEmpty { return nil }
    return .keyword(joinWords(words))
}

/// Grid tracks: lengths, fr, auto, minmax(), repeat(n, ...) and
/// repeat(auto-fill|auto-fit, ...) written as a negative repeat count.
func parseTracks(_ tokens: [Token], _ start: int, _ end: int) -> [GridTrack] {
    var out: [GridTrack] = []
    var i = start
    while i < end {
        let t = tokens[i]
        if t.Kind == .function {
            let name = lower(t.Value)
            let close = closeParen(tokens, from: i + 1)
            if name == "repeat" {
                // The count, then a comma, then the tracks.
                var j = i + 1
                var count = 0
                var autoFill = false
                if j < close && tokens[j].Kind == .number { count = int(tokens[j].NumberVal) }
                if j < close && tokens[j].Kind == .ident { autoFill = true }
                while j < close && tokens[j].Kind != .comma { j += 1 }
                let inner = parseTracks(tokens, j + 1, close)
                if autoFill {
                    // Marked for layout to count: as many as fit, the
                    // marker being a negative fr after them.
                    for tr in inner { out.append(tr) }
                    out.append(.fr(-1))
                } else {
                    var k = 0
                    while k < count && k < 1000 {
                        for tr in inner { out.append(tr) }
                        k += 1
                    }
                }
            } else if name == "minmax" {
                var minValue: float32 = 0
                var maxValue: float32 = 0
                var maxFr: float32 = 0
                var j = i + 1
                var parts: [GridTrack] = []
                while j < close {
                    if tokens[j].Kind != .comma {
                        let one = parseTracks(tokens, j, j + 1)
                        if !one.isEmpty { parts.append(one[0]) }
                    }
                    j += 1
                }
                if parts.count >= 1, case .length(let l) = parts[0], case .px(let v) = l { minValue = v }
                if parts.count >= 2 {
                    if case .length(let l) = parts[1], case .px(let v) = l { maxValue = v }
                    if case .fr(let f) = parts[1] { maxFr = f }
                }
                out.append(.minmax(minValue, maxValue, maxFr))
            } else if name == "fit-content" {
                out.append(.auto)
            } else if name == "calc" || name == "-webkit-calc" || name == "min" || name == "max" || name == "clamp" {
                // A length computed: pixels plus a share of the grid.
                var slice: [Token] = []
                var k = i
                while k <= close && k < end { slice.append(tokens[k]); k += 1 }
                if let track = trackOfCalc(calcValue(slice)) { out.append(track) }
            }
            i = close + 1
            continue
        }
        if t.Kind == .dimension && t.Unit == "fr" {
            out.append(.fr(t.NumberVal))
        } else if t.Kind == .ident {
            let kw = lower(t.Value)
            if kw == "auto" || kw == "min-content" || kw == "max-content" { out.append(.auto) }
        } else if t.Kind == .openBracket {
            // Line names: skipped.
            while i < end && tokens[i].Kind != .closeBracket { i += 1 }
        } else if let l = parseLengthValue(t, allowAuto: false), case .length(let n, let unit) = l {
            if unit == .percent { out.append(.length(.percent(n))) }
            else if unit == .px { out.append(.length(.px(n))) }
            else { out.append(.length(.px(n * 16))) }
        }
        i += 1
    }
    return out
}

/// A calc()'s value as a track: pixels and a percentage of the grid,
/// font-relative units taken at 16px as the other track lengths are.
func trackOfCalc(_ v: Value?) -> GridTrack? {
    guard let v = v else { return nil }
    var px: float32 = 0
    var pct: float32 = 0
    switch v {
    case .length(let n, let unit):
        if unit == .percent { pct = n } else if unit == .px { px = n } else { px = n * 16 }
    case .calc(let terms):
        for t in terms {
            guard let u = t.Unit else { return nil }
            if u == .percent { pct += t.Number } else if u == .px { px += t.Number } else { px += t.Number * 16 }
        }
    default:
        return nil
    }
    if pct == 0 { return .length(.px(px)) }
    if px == 0 { return .length(.percent(pct)) }
    return .length(.calc(px, pct))
}

/// grid-column / grid-row: `2`, `span 2`, `1 / 3`, `1 / span 2`, `auto`.
func parsePlacement(_ tokens: [Token]) -> GridPlacement {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) != "auto" {
        // An area's name: its lines on this axis.
        var p = GridPlacement.auto
        p.Area = tokens[0].Value
        return p
    }
    var start: int32 = 0
    var end: int32 = 0
    var span: int32 = 0
    var afterSlash = false
    var spanNext = false
    for t in tokens {
        if t.Kind == .delim && t.Value == "/" { afterSlash = true; spanNext = false; continue }
        if t.Kind == .ident && lower(t.Value) == "span" { spanNext = true; continue }
        if t.Kind == .number {
            let n = int32(t.NumberVal)
            if spanNext {
                span = n
                spanNext = false
            } else if afterSlash {
                end = n
            } else {
                start = n
            }
        }
    }
    var p = GridPlacement(start: start, span: 1)
    if span > 0 { p.Span = span }
    if end != 0 { p.End = end }
    return p
}

/// One of grid-area's slash-separated parts, or an auto side.
func gridAreaSide(_ parts: [[Token]], _ k: int, end: bool) -> GridPlacement {
    return k < parts.count ? parsePlacementSide(parts[k], end: end) : GridPlacement(start: 0, span: 0)
}

/// grid-column-start and the like: a line, or `span n`; for the end
/// side the line is the placement's End.
func parsePlacementSide(_ tokens: [Token], end: bool) -> GridPlacement {
    var p = GridPlacement(start: 0, span: 0)
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) != "auto" {
        p.Span = 1
        p.Area = tokens[0].Value
        return p
    }
    var spanNext = false
    for t in tokens {
        if t.Kind == .ident && lower(t.Value) == "span" { spanNext = true; continue }
        if t.Kind == .number {
            let n = int32(t.NumberVal)
            if spanNext { p.Span = n } else if end { p.End = n } else { p.Start = n }
            spanNext = false
        }
    }
    return p
}

/// env()'s variables, by name, as the host sets them: the safe area's
/// insets and the like. A name not here takes env()'s fallback; the
/// safe-area, keyboard and title-bar areas are 0 where nothing is set.
public var EnvironmentVariables: [string: string] = [:]

/// The tokens of a piece of CSS.
public func Tokenize(_ text: string) -> [Token] {
    let scanner = Scanner(source: text)
    var out: [Token] = []
    while true {
        let t = scanner.Next()
        if t.Kind == .eof { break }
        out.append(t)
    }
    return out
}

/// Tokens with every env(name, fallback) replaced by its value; nil
/// where one names nothing and has no fallback.
func substituteEnv(_ tokens: [Token]) -> [Token]? {
    var has = false
    for t in tokens where t.Kind == .function && lower(t.Value) == "env" { has = true }
    if !has { return tokens }
    var out: [Token] = []
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind == .function && lower(t.Value) == "env" {
            let close = closeParen(tokens, from: i + 1)
            let args = splitArgs(tokens, i + 1, close)
            var name = ""
            if let first = args.first, let n = first.first, n.Kind == .ident { name = n.Value }
            var value: [Token]? = nil
            if let text = EnvironmentVariables[name] {
                value = Tokenize(text)
            } else if name.hasPrefix("safe-area-inset-") || name.hasPrefix("keyboard-inset-") || name.hasPrefix("titlebar-area-") {
                // Defined, as 0: the fallback is for names that aren't.
                value = [Token(kind: .number, value: "0", numberVal: 0)]
            } else if args.count > 1 {
                value = args[1]
            }
            guard var v = value else { return nil }
            if !v.isEmpty { v[0].SpaceBefore = t.SpaceBefore }
            out.append(contentsOf: v)
            i = close + 1
            continue
        }
        out.append(t)
        i += 1
    }
    return out
}

/// grid-template-areas: none, or one string a row, each cell a name or a
/// run of dots (no area); kept as the rows' cells, space-separated and
/// joined by "|". Nil where the rows differ in length or an area isn't
/// a rectangle.
func parseTemplateAreas(_ tokens: [Token]) -> Value? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return .string("") }
    var rows: [[string]] = []
    for t in tokens {
        guard t.Kind == .string else { return nil }
        var cells: [string] = []
        for w in t.Value.split(separator: " ") {
            let cell = string(w)
            if cell.isEmpty { continue }
            var dots = true
            for c in cell.utf8 where c != 46 { dots = false }
            cells.append(dots ? "." : cell)
        }
        if cells.isEmpty { return nil }
        rows.append(cells)
    }
    if rows.isEmpty { return nil }
    for r in rows where r.count != rows[0].count { return nil }
    // Each name's cells must fill the rectangle they span.
    var seen: [string] = []
    for r in rows {
        for name in r where name != "." && !seen.contains(name) {
            seen.append(name)
            var r0 = 1000
            var r1 = -1
            var c0 = 1000
            var c1 = -1
            var count = 0
            var y = 0
            while y < rows.count {
                var x = 0
                while x < rows[y].count {
                    if rows[y][x] == name {
                        count += 1
                        if y < r0 { r0 = y }
                        if y > r1 { r1 = y }
                        if x < c0 { c0 = x }
                        if x > c1 { c1 = x }
                    }
                    x += 1
                }
                y += 1
            }
            if count != (r1 - r0 + 1) * (c1 - c0 + 1) { return nil }
        }
    }
    return .string(rows.map { $0.joined(separator: " ") }.joined(separator: "|"))
}

/// grid-template (and grid's template forms): none; rows / columns; or
/// rows of area strings, each with its height, then / columns.
func parseGridTemplate(_ tokens: [Token]) -> [(Prop, Value)]? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" {
        return [(.gridTemplateRows, Value.none), (.gridTemplateColumns, Value.none), (.gridTemplateAreas, .string(""))]
    }
    var slash = -1
    var i = 0
    var depth = 0
    while i < tokens.count {
        if tokens[i].Kind == .function || tokens[i].Kind == .openParen { depth += 1 }
        if tokens[i].Kind == .closeParen { depth -= 1 }
        if depth == 0 && tokens[i].Kind == .delim && tokens[i].Value == "/" { slash = i }
        i += 1
    }
    let rowPart = slash >= 0 ? Array(tokens[0..<slash]) : tokens
    let colPart = slash >= 0 ? Array(tokens[(slash + 1)...]) : []
    var out: [(Prop, Value)] = []
    // grid: auto-flow forms.
    var flowRow = false
    var flowColumn = false
    for t in rowPart where t.Kind == .ident && lower(t.Value) == "auto-flow" { flowRow = true }
    for t in colPart where t.Kind == .ident && lower(t.Value) == "auto-flow" { flowColumn = true }
    if flowRow || flowColumn {
        let tracksOf: ([Token]) -> [Token] = { list in list.filter { !($0.Kind == .ident && (lower($0.Value) == "auto-flow" || lower($0.Value) == "dense")) } }
        if flowRow {
            out.append((.gridAutoFlow, .keyword("row")))
            let rows = parseTracks(tracksOf(rowPart), 0, tracksOf(rowPart).count)
            if !rows.isEmpty { out.append((.gridAutoRows, .tracks(rows))) }
            let cols = parseTracks(colPart, 0, colPart.count)
            if !cols.isEmpty { out.append((.gridTemplateColumns, .tracks(cols))) }
        } else {
            out.append((.gridAutoFlow, .keyword("column")))
            let cols = parseTracks(tracksOf(colPart), 0, tracksOf(colPart).count)
            if !cols.isEmpty { out.append((.gridAutoColumns, .tracks(cols))) }
            let rows = parseTracks(rowPart, 0, rowPart.count)
            if !rows.isEmpty { out.append((.gridTemplateRows, .tracks(rows))) }
        }
        return out
    }
    var hasStrings = false
    for t in rowPart where t.Kind == .string { hasStrings = true }
    if hasStrings {
        var areaTokens: [Token] = []
        var rowTracks: [GridTrack] = []
        var j = 0
        while j < rowPart.count {
            let t = rowPart[j]
            if t.Kind == .string {
                areaTokens.append(t)
                // The row's height follows its string, or it is auto.
                var k = j + 1
                var size: [Token] = []
                while k < rowPart.count && rowPart[k].Kind != .string { size.append(rowPart[k]); k += 1 }
                let tracks = parseTracks(size, 0, size.count)
                rowTracks.append(tracks.isEmpty ? GridTrack.auto : tracks[0])
                j = k
                continue
            }
            j += 1
        }
        guard let areas = parseTemplateAreas(areaTokens) else { return nil }
        out.append((.gridTemplateAreas, areas))
        out.append((.gridTemplateRows, .tracks(rowTracks)))
    } else {
        let rows = parseTracks(rowPart, 0, rowPart.count)
        if rows.isEmpty { return nil }
        out.append((.gridTemplateRows, .tracks(rows)))
        out.append((.gridTemplateAreas, .string("")))
    }
    if !colPart.isEmpty {
        let cols = parseTracks(colPart, 0, colPart.count)
        if cols.isEmpty { return nil }
        out.append((.gridTemplateColumns, .tracks(cols)))
    } else {
        out.append((.gridTemplateColumns, Value.none))
    }
    return out
}
