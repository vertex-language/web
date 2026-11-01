package cascade

import (
    "image/draw"
    "math"
    "web/css"
    "web/html"
)

// What CSS Transitions and Animations need from the cascade: the
// transition-* and animation-* properties as lists, timing functions,
// @keyframes, and the animatable properties as values that can be read
// from a style, put back, and interpolated. web's Animator runs them.

/// A timing function: what fraction of the change has happened at a
/// fraction of the time.
public struct Easing: Equatable {
    /// "bezier", "steps" or "linear" (with Stops for linear()).
    public var Kind: string
    public var X1: float32 = 0
    public var Y1: float32 = 0
    public var X2: float32 = 1
    public var Y2: float32 = 1
    public var Steps: int32 = 1
    /// steps()'s jump: "start", "end", "none" or "both".
    public var Jump: string = "end"
    /// linear()'s points, as (input, output).
    public var Stops: [float32] = []

    public init(_ kind: string) { Kind = kind }

    public static func bezier(_ x1: float32, _ y1: float32, _ x2: float32, _ y2: float32) -> Easing {
        var e = Easing("bezier")
        e.X1 = x1
        e.Y1 = y1
        e.X2 = x2
        e.Y2 = y2
        return e
    }

    public static let linear = Easing.bezier(0, 0, 1, 1)
    public static let ease = Easing.bezier(0.25, 0.1, 0.25, 1)

    /// Parses a timing function's normalized text (css/animation.vs).
    public static func Parse(_ text: string) -> Easing {
        switch text {
        case "linear": return linear
        case "ease": return ease
        case "ease-in": return bezier(0.42, 0, 1, 1)
        case "ease-out": return bezier(0, 0, 0.58, 1)
        case "ease-in-out": return bezier(0.42, 0, 0.58, 1)
        case "step-start":
            var e = Easing("steps")
            e.Jump = "start"
            return e
        case "step-end": return Easing("steps")
        default: break
        }
        guard let open = text.firstIndex(of: "(") else { return ease }
        let name = string(text[text.startIndex..<open])
        let inner = string(text[text.index(after: open)..<text.index(before: text.endIndex)])
        let args = inner.split(separator: ",").map { string($0) }
        switch name {
        case "cubic-bezier":
            let n = args.map { css.ParseNumberText($0) }
            if n.count != 4 { return ease }
            return bezier(math.Saturate(n[0]), n[1], math.Saturate(n[2]), n[3])
        case "steps":
            var e = Easing("steps")
            e.Steps = int32(css.ParseNumberText(args[0]))
            if e.Steps < 1 { e.Steps = 1 }
            if args.count > 1 {
                switch args[1] {
                case "start", "jump-start": e.Jump = "start"
                case "jump-none": e.Jump = "none"
                case "jump-both": e.Jump = "both"
                default: e.Jump = "end"
                }
            }
            if e.Jump == "none" && e.Steps < 2 { e.Steps = 2 }
            return e
        case "linear":
            // Points with optional input percentages; missing inputs are
            // spread evenly between their neighbours.
            var e = Easing("linear")
            var outs: [float32] = []
            var ins: [float32?] = []
            for a in args {
                let words = a.split(separator: " ").map { string($0) }
                if words.isEmpty { continue }
                outs.append(css.ParseNumberText(words[0]))
                ins.append(words.count > 1 ? css.ParseNumberText(words[1]) / 100 : nil)
            }
            if outs.isEmpty { return Easing.linear }
            if ins[0] == nil { ins[0] = 0 }
            if ins[ins.count - 1] == nil { ins[ins.count - 1] = 1 }
            var i = 0
            while i < ins.count {
                if ins[i] == nil {
                    var j = i
                    while ins[j] == nil { j += 1 }
                    let from = ins[i - 1]!
                    let to = ins[j]!
                    var k = i
                    while k < j {
                        ins[k] = from + (to - from) * float32(k - i + 1) / float32(j - i + 1)
                        k += 1
                    }
                }
                i += 1
            }
            i = 0
            while i < outs.count {
                e.Stops.append(ins[i]!)
                e.Stops.append(outs[i])
                i += 1
            }
            return e
        default:
            return ease
        }
    }

    /// The output progress at input t, 0 to 1. `before` is whether time
    /// is before the start, which steps() with a start jump cares about.
    public func Progress(_ t: float32) -> float32 {
        switch Kind {
        case "steps":
            let n = float32(Steps)
            var step = math.Floor(t * n)
            if Jump == "start" || Jump == "both" { step += 1 }
            if t >= 1 && (Jump == "end" || Jump == "none") { step = n }
            var jumps = n
            if Jump == "none" { jumps = n - 1 }
            if Jump == "both" { jumps = n + 1 }
            if t <= 0 { return Jump == "start" || Jump == "both" ? 1 / jumps : 0 }
            return math.Min(step / jumps, 1)
        case "linear":
            if Stops.count < 4 { return t }
            if t <= Stops[0] { return Stops[1] }
            var i = 2
            while i < Stops.count {
                if t <= Stops[i] {
                    let x0 = Stops[i - 2]
                    let y0 = Stops[i - 1]
                    let x1 = Stops[i]
                    let y1 = Stops[i + 1]
                    if x1 == x0 { return y1 }
                    return y0 + (y1 - y0) * (t - x0) / (x1 - x0)
                }
                i += 2
            }
            return Stops[Stops.count - 1]
        default:
            if X1 == Y1 && X2 == Y2 { return t }
            if t <= 0 || t >= 1 { return t <= 0 ? 0 : 1 }
            // Solve x(u) = t for the curve parameter u, then take y(u).
            var u = t
            var i = 0
            while i < 8 {
                let x = bez(u, X1, X2) - t
                let dx = bezSlope(u, X1, X2)
                if math.Abs(x) < 1e-5 { break }
                if math.Abs(dx) < 1e-6 { break }
                u -= x / dx
                i += 1
            }
            if u < 0 || u > 1 || math.Abs(bez(u, X1, X2) - t) > 1e-3 {
                var lo: float32 = 0
                var hi: float32 = 1
                u = t
                var k = 0
                while k < 30 {
                    let x = bez(u, X1, X2)
                    if math.Abs(x - t) < 1e-6 { break }
                    if x < t { lo = u } else { hi = u }
                    u = (lo + hi) / 2
                    k += 1
                }
            }
            return bez(u, Y1, Y2)
        }
    }
}

func bez(_ u: float32, _ p1: float32, _ p2: float32) -> float32 {
    let v = 1 - u
    return 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u
}

func bezSlope(_ u: float32, _ p1: float32, _ p2: float32) -> float32 {
    let v = 1 - u
    return 3 * v * v * p1 + 6 * v * u * (p2 - p1) + 3 * u * u * (1 - p2)
}

/// One @keyframes block's keyframe: where it stands (0 to 1), what it
/// sets, and its own timing function, if it names one.
public struct Keyframe {
    public var Offset: float32
    public var Declarations: [css.Longhand]
    public var Easing: Easing?
}

/// A @keyframes rule's frames, sorted by offset.
func keyframesOf(_ at: css.AtRule) -> [Keyframe] {
    var out: [Keyframe] = []
    for rule in at.Rules {
        let split = SplitDecls(rule.Declarations)
        var easing: Easing? = nil
        var decls: [css.Longhand] = []
        for d in split.longhands {
            if d.Prop == .animationTimingFunction {
                if case .string(let text) = d.Value { easing = Easing.Parse(text) }
                continue
            }
            // !important in a keyframe is ignored, as are the
            // animation properties themselves.
            if d.Important { continue }
            decls.append(d)
        }
        for sel in rule.Selectors {
            let s = css.lower(trimSpaces(sel))
            var offset: float32 = -1
            if s == "from" { offset = 0 }
            else if s == "to" { offset = 1 }
            else if s.hasSuffix("%") { offset = css.ParseNumberText(string(s.dropLast())) / 100 }
            if offset < 0 || offset > 1 { continue }
            out.append(Keyframe(Offset: offset, Declarations: decls, Easing: easing))
        }
    }
    // A stable sort by offset: frames at the same offset keep their order.
    var i = 1
    while i < out.count {
        var j = i
        while j > 0 && out[j - 1].Offset > out[j].Offset {
            let t = out[j]
            out[j] = out[j - 1]
            out[j - 1] = t
            j -= 1
        }
        i += 1
    }
    return out
}

/// The `transition` and `animation` longhands' lists, as they compute.
public struct TransitionSpec {
    public var Properties: [string] = ["all"]
    public var Durations: [float32] = [0]
    public var Timings: [Easing] = [Easing.ease]
    public var Delays: [float32] = [0]
    /// transition-behavior: allow-discrete lets display and the other
    /// discrete properties transition.
    public var Behaviors: [string] = ["normal"]

    public init() {}

    /// Whether any transition has time to run.
    public var Runs: bool {
        for d in Durations where d > 0 { return true }
        return false
    }
}

public struct AnimationSpec {
    public var Names: [string] = ["none"]
    public var Durations: [float32] = [0]
    public var Timings: [Easing] = [Easing.ease]
    public var Delays: [float32] = [0]
    /// Iteration counts; infinite is -1.
    public var Counts: [float32] = [1]
    public var Directions: [string] = ["normal"]
    public var FillModes: [string] = ["none"]
    public var PlayStates: [string] = ["running"]

    public init() {}

    public var HasAnimations: bool {
        for n in Names where n != "none" { return true }
        return false
    }
}

/// The i'th item of a list, repeating the list as the spec does where
/// it is shorter.
public func Cycled<T>(_ list: [T], _ i: int) -> T {
    return list[i % list.count]
}

func listOf(_ v: css.Value) -> [string]? {
    guard case .string(let text) = v else { return nil }
    return text.split(separator: "|").map { string($0) }
}

/// Applies a transition-* or animation-* longhand.
func applyAnimationProperty(_ prop: css.Prop, _ v: css.Value, _ s: ComputedStyle) {
    guard let items = listOf(v), !items.isEmpty else { return }
    let numbers = items.map { $0 == "infinite" ? float32(-1) : css.ParseNumberText($0) }
    switch prop {
    case .transitionProperty: s.Transition.Properties = items
    case .transitionDuration: s.Transition.Durations = numbers
    case .transitionTimingFunction: s.Transition.Timings = items.map { Easing.Parse($0) }
    case .transitionDelay: s.Transition.Delays = numbers
    case .transitionBehavior: s.Transition.Behaviors = items
    case .animationName: s.Animation.Names = items
    case .animationDuration: s.Animation.Durations = numbers
    case .animationTimingFunction: s.Animation.Timings = items.map { Easing.Parse($0) }
    case .animationDelay: s.Animation.Delays = numbers
    case .animationIterationCount: s.Animation.Counts = numbers
    case .animationDirection: s.Animation.Directions = items
    case .animationFillMode: s.Animation.FillModes = items
    case .animationPlayState: s.Animation.PlayStates = items
    default: break
    }
}

func copyAnimationProperty(_ prop: css.Prop, from a: ComputedStyle, to b: ComputedStyle) {
    switch prop {
    case .transitionProperty: b.Transition.Properties = a.Transition.Properties
    case .transitionDuration: b.Transition.Durations = a.Transition.Durations
    case .transitionTimingFunction: b.Transition.Timings = a.Transition.Timings
    case .transitionDelay: b.Transition.Delays = a.Transition.Delays
    case .transitionBehavior: b.Transition.Behaviors = a.Transition.Behaviors
    case .animationName: b.Animation.Names = a.Animation.Names
    case .animationDuration: b.Animation.Durations = a.Animation.Durations
    case .animationTimingFunction: b.Animation.Timings = a.Animation.Timings
    case .animationDelay: b.Animation.Delays = a.Animation.Delays
    case .animationIterationCount: b.Animation.Counts = a.Animation.Counts
    case .animationDirection: b.Animation.Directions = a.Animation.Directions
    case .animationFillMode: b.Animation.FillModes = a.Animation.FillModes
    case .animationPlayState: b.Animation.PlayStates = a.Animation.PlayStates
    default: break
    }
}

// MARK: - Animatable values

/// A property's computed value, as animations read, interpolate and
/// write it.
public enum AnimValue {
    case number(float32)
    case color(draw.Color)
    /// A length; auto and the other keywords interpolate discretely.
    case length(css.Length)
    case transforms([TransformOp])
    case radii(draw.Radii)
    /// A keyword that interpolates discretely: visibility's, display's.
    case keyword(string)
}

/// The properties that animate, by name, each with its css.Prop.
public struct AnimatableProperty {
    public var Name: string
    public var Prop: css.Prop
}

public let AnimatableProperties: [AnimatableProperty] = [
    AnimatableProperty(Name: "opacity", Prop: .opacity),
    AnimatableProperty(Name: "visibility", Prop: .visibility),
    AnimatableProperty(Name: "display", Prop: .display),
    AnimatableProperty(Name: "color", Prop: .color),
    AnimatableProperty(Name: "background-color", Prop: .backgroundColor),
    AnimatableProperty(Name: "border-top-color", Prop: .borderTopColor),
    AnimatableProperty(Name: "border-right-color", Prop: .borderRightColor),
    AnimatableProperty(Name: "border-bottom-color", Prop: .borderBottomColor),
    AnimatableProperty(Name: "border-left-color", Prop: .borderLeftColor),
    AnimatableProperty(Name: "outline-color", Prop: .outlineColor),
    AnimatableProperty(Name: "border-top-width", Prop: .borderTopWidth),
    AnimatableProperty(Name: "border-right-width", Prop: .borderRightWidth),
    AnimatableProperty(Name: "border-bottom-width", Prop: .borderBottomWidth),
    AnimatableProperty(Name: "border-left-width", Prop: .borderLeftWidth),
    AnimatableProperty(Name: "outline-width", Prop: .outlineWidth),
    AnimatableProperty(Name: "border-radius", Prop: .borderTopLeftRadius),
    AnimatableProperty(Name: "filter", Prop: .filter),
    AnimatableProperty(Name: "transform", Prop: .transform),
    AnimatableProperty(Name: "translate", Prop: .translate),
    AnimatableProperty(Name: "rotate", Prop: .rotate),
    AnimatableProperty(Name: "scale", Prop: .scale),
    AnimatableProperty(Name: "width", Prop: .width),
    AnimatableProperty(Name: "height", Prop: .height),
    AnimatableProperty(Name: "min-width", Prop: .minWidth),
    AnimatableProperty(Name: "min-height", Prop: .minHeight),
    AnimatableProperty(Name: "max-width", Prop: .maxWidth),
    AnimatableProperty(Name: "max-height", Prop: .maxHeight),
    AnimatableProperty(Name: "top", Prop: .top),
    AnimatableProperty(Name: "right", Prop: .right),
    AnimatableProperty(Name: "bottom", Prop: .bottom),
    AnimatableProperty(Name: "left", Prop: .left),
    AnimatableProperty(Name: "margin-top", Prop: .marginTop),
    AnimatableProperty(Name: "margin-right", Prop: .marginRight),
    AnimatableProperty(Name: "margin-bottom", Prop: .marginBottom),
    AnimatableProperty(Name: "margin-left", Prop: .marginLeft),
    AnimatableProperty(Name: "padding-top", Prop: .paddingTop),
    AnimatableProperty(Name: "padding-right", Prop: .paddingRight),
    AnimatableProperty(Name: "padding-bottom", Prop: .paddingBottom),
    AnimatableProperty(Name: "padding-left", Prop: .paddingLeft),
    AnimatableProperty(Name: "row-gap", Prop: .rowGap),
    AnimatableProperty(Name: "column-gap", Prop: .columnGap),
    AnimatableProperty(Name: "flex-grow", Prop: .flexGrow),
    AnimatableProperty(Name: "flex-shrink", Prop: .flexShrink),
    AnimatableProperty(Name: "font-size", Prop: .fontSize),
    AnimatableProperty(Name: "letter-spacing", Prop: .letterSpacing),
    AnimatableProperty(Name: "word-spacing", Prop: .wordSpacing),
]

/// The animatable properties a name in transition-property covers: one,
/// a shorthand's, or all of them.
public func AnimatablePropertiesNamed(_ name: string) -> [AnimatableProperty] {
    if name == "all" { return AnimatableProperties }
    var prefixes: [string] = []
    switch name {
    case "margin": prefixes = ["margin-"]
    case "padding": prefixes = ["padding-"]
    case "inset": prefixes = ["top", "right", "bottom", "left"]
    case "border-color": return AnimatableProperties.filter { $0.Name.hasPrefix("border-") && $0.Name.hasSuffix("-color") }
    case "border-width": return AnimatableProperties.filter { $0.Name.hasPrefix("border-") && $0.Name.hasSuffix("-width") }
    case "border": return AnimatableProperties.filter { $0.Name.hasPrefix("border-") && $0.Name != "border-radius" }
    case "outline": prefixes = ["outline-"]
    case "background": prefixes = ["background-color"]
    case "gap": prefixes = ["row-gap", "column-gap"]
    case "flex": prefixes = ["flex-grow", "flex-shrink"]
    case "font": prefixes = ["font-size"]
    case "-webkit-transform": prefixes = ["transform"]
    default:
        return AnimatableProperties.filter { $0.Name == name }
    }
    return AnimatableProperties.filter { p in prefixes.contains { p.Name == $0 || ($0.hasSuffix("-") && p.Name.hasPrefix($0)) } }
}

/// A property's value in a style.
/// Whether a property transitions only with transition-behavior:
/// allow-discrete.
public func IsDiscreteProperty(_ p: css.Prop) -> bool {
    return p == .display
}

public func AnimatedValue(_ p: css.Prop, of s: ComputedStyle) -> AnimValue? {
    switch p {
    case .visibility: return .keyword(s.Visibility == .visible ? "visible" : (s.Visibility == .hidden ? "hidden" : "collapse"))
    case .display: return .keyword(displayName(s.Display))
    case .opacity: return .number(s.Opacity)
    case .color: return .color(s.Color)
    case .backgroundColor: return .color(s.BackgroundColor)
    case .borderTopColor: return .color(s.BorderTopColor ?? s.Color)
    case .borderRightColor: return .color(s.BorderRightColor ?? s.Color)
    case .borderBottomColor: return .color(s.BorderBottomColor ?? s.Color)
    case .borderLeftColor: return .color(s.BorderLeftColor ?? s.Color)
    case .outlineColor: return .color(s.OutlineColor ?? s.Color)
    case .borderTopWidth: return .number(s.BorderTopWidth)
    case .borderRightWidth: return .number(s.BorderRightWidth)
    case .borderBottomWidth: return .number(s.BorderBottomWidth)
    case .borderLeftWidth: return .number(s.BorderLeftWidth)
    case .outlineWidth: return .number(s.OutlineWidth)
    case .borderTopLeftRadius: return .radii(s.BorderRadius)
    case .filter: return .number(s.FilterBlur)
    case .transform: return .transforms(s.Transform)
    case .translate: return .transforms(s.Translate)
    case .rotate: return .transforms(s.Rotate)
    case .scale: return .transforms(s.Scale)
    case .width: return .length(s.Width)
    case .height: return .length(s.Height)
    case .minWidth: return .length(s.MinWidth)
    case .minHeight: return .length(s.MinHeight)
    case .maxWidth: return .length(s.MaxWidth)
    case .maxHeight: return .length(s.MaxHeight)
    case .top: return .length(s.Top)
    case .right: return .length(s.Right)
    case .bottom: return .length(s.Bottom)
    case .left: return .length(s.Left)
    case .marginTop: return .length(s.MarginTop)
    case .marginRight: return .length(s.MarginRight)
    case .marginBottom: return .length(s.MarginBottom)
    case .marginLeft: return .length(s.MarginLeft)
    case .paddingTop: return .length(s.PaddingTop)
    case .paddingRight: return .length(s.PaddingRight)
    case .paddingBottom: return .length(s.PaddingBottom)
    case .paddingLeft: return .length(s.PaddingLeft)
    case .rowGap: return .length(s.RowGap)
    case .columnGap: return .length(s.ColumnGap)
    case .flexGrow: return .number(s.FlexGrow)
    case .flexShrink: return .number(s.FlexShrink)
    case .fontSize: return .number(s.FontSize)
    case .letterSpacing: return .number(s.LetterSpacing)
    case .wordSpacing: return .number(s.WordSpacing)
    default: return nil
    }
}

/// Puts an animated value into a style.
public func SetAnimatedValue(_ p: css.Prop, _ v: AnimValue, on s: ComputedStyle) {
    switch v {
    case .keyword(let k):
        if p == .visibility { s.Visibility = k == "hidden" ? .hidden : (k == "collapse" ? .collapse : .visible) }
        if p == .display { s.Display = displayOf(k) }
    case .number(let n):
        switch p {
        case .opacity: s.Opacity = math.Saturate(n)
        case .borderTopWidth: s.BorderTopWidth = math.Max(n, 0)
        case .borderRightWidth: s.BorderRightWidth = math.Max(n, 0)
        case .borderBottomWidth: s.BorderBottomWidth = math.Max(n, 0)
        case .borderLeftWidth: s.BorderLeftWidth = math.Max(n, 0)
        case .outlineWidth: s.OutlineWidth = math.Max(n, 0)
        case .filter: s.FilterBlur = math.Max(n, 0)
        case .flexGrow: s.FlexGrow = math.Max(n, 0)
        case .flexShrink: s.FlexShrink = math.Max(n, 0)
        case .fontSize:
            s.FontSize = math.Max(n, 0)
            s.face = nil
        case .letterSpacing: s.LetterSpacing = n
        case .wordSpacing: s.WordSpacing = n
        default: break
        }
    case .color(let c):
        switch p {
        case .color: s.Color = c
        case .backgroundColor: s.BackgroundColor = c
        case .borderTopColor: s.BorderTopColor = c
        case .borderRightColor: s.BorderRightColor = c
        case .borderBottomColor: s.BorderBottomColor = c
        case .borderLeftColor: s.BorderLeftColor = c
        case .outlineColor: s.OutlineColor = c
        default: break
        }
    case .length(let l):
        switch p {
        case .width: s.Width = l
        case .height: s.Height = l
        case .minWidth: s.MinWidth = l
        case .minHeight: s.MinHeight = l
        case .maxWidth: s.MaxWidth = l
        case .maxHeight: s.MaxHeight = l
        case .top: s.Top = l
        case .right: s.Right = l
        case .bottom: s.Bottom = l
        case .left: s.Left = l
        case .marginTop: s.MarginTop = l
        case .marginRight: s.MarginRight = l
        case .marginBottom: s.MarginBottom = l
        case .marginLeft: s.MarginLeft = l
        case .paddingTop: s.PaddingTop = l
        case .paddingRight: s.PaddingRight = l
        case .paddingBottom: s.PaddingBottom = l
        case .paddingLeft: s.PaddingLeft = l
        case .rowGap: s.RowGap = l
        case .columnGap: s.ColumnGap = l
        default: break
        }
    case .transforms(let ops):
        switch p {
        case .transform: s.Transform = ops
        case .translate: s.Translate = ops
        case .rotate: s.Rotate = ops
        case .scale: s.Scale = ops
        default: break
        }
    case .radii(let r):
        if p == .borderTopLeftRadius { s.BorderRadius = r }
    }
}

/// Whether two values are the same, as a transition decides whether a
/// value changed.
public func SameValue(_ a: AnimValue, _ b: AnimValue) -> bool {
    switch (a, b) {
    case (.number(let x), .number(let y)): return x == y
    case (.color(let x), .color(let y)): return x == y
    case (.length(let x), .length(let y)): return x == y
    case (.radii(let x), .radii(let y)): return x == y
    case (.keyword(let x), .keyword(let y)): return x == y
    case (.transforms(let x), .transforms(let y)):
        if x.count != y.count { return false }
        var i = 0
        while i < x.count {
            if x[i].Name != y[i].Name || x[i].Numbers != y[i].Numbers || x[i].Lengths != y[i].Lengths { return false }
            i += 1
        }
        return true
    default: return false
    }
}

func lerp(_ a: float32, _ b: float32, _ t: float32) -> float32 { return a + (b - a) * t }

/// A length as pixels plus a percentage, or nil for a keyword.
func lengthParts(_ l: css.Length) -> (px: float32, pct: float32)? {
    switch l {
    case .px(let p): return (px: p, pct: 0)
    case .percent(let p): return (px: 0, pct: p)
    case .calc(let p, let q): return (px: p, pct: q)
    default: return nil
    }
}

func lerpLength(_ a: css.Length, _ b: css.Length, _ t: float32) -> css.Length {
    guard let x = lengthParts(a), let y = lengthParts(b) else { return t < 0.5 ? a : b }
    let px = lerp(x.px, y.px, t)
    let pct = lerp(x.pct, y.pct, t)
    if pct == 0 && x.pct == 0 && y.pct == 0 { return .px(px) }
    if px == 0 && x.px == 0 && y.px == 0 { return .percent(pct) }
    return .calc(px, pct)
}

/// The op that does nothing in a function's place: what a shorter
/// transform list is padded with.
func identityOp(like op: TransformOp) -> TransformOp {
    switch op.Name {
    case "translate": return TransformOp("translate", lengths: [.px(0), .px(0)])
    case "scale": return TransformOp("scale", numbers: [1, 1])
    case "rotate": return TransformOp("rotate", numbers: [0])
    case "skew": return TransformOp("skew", numbers: [0, 0])
    default: return TransformOp("matrix", numbers: [1, 0, 0, 1, 0, 0])
    }
}

/// The value a fraction t of the way from a to b. Lengths that can't
/// mix (auto) and lists whose functions differ switch halfway.
public func Interpolate(_ a: AnimValue, _ b: AnimValue, _ t: float32) -> AnimValue {
    switch (a, b) {
    case (.keyword(let x), .keyword(let y)):
        // Visible all the way while either end is (visibility), and the
        // shown display all the way to or from none; else halfway.
        if t <= 0 { return a }
        if t >= 1 { return b }
        if x == "visible" || y == "visible" { return .keyword("visible") }
        if x == "none" { return b }
        if y == "none" { return a }
        return t < 0.5 ? a : b
    case (.number(let x), .number(let y)): return .number(lerp(x, y, t))
    case (.color(let x), .color(let y)):
        // Mixed with premultiplied alpha, as CSS interpolates colors.
        let xa = float32(x.A) / 255
        let ya = float32(y.A) / 255
        let alpha = lerp(xa, ya, t)
        if alpha <= 0 { return .color(draw.Color(0, 0, 0, 0)) }
        func ch(_ p: uint8, _ q: uint8) -> uint8 {
            let v = lerp(float32(p) * xa, float32(q) * ya, t) / alpha
            return uint8(math.Clamp(v, 0, 255) + 0.5)
        }
        return .color(draw.Color(ch(x.R, y.R), ch(x.G, y.G), ch(x.B, y.B), uint8(math.Clamp(alpha * 255, 0, 255) + 0.5)))
    case (.length(let x), .length(let y)): return .length(lerpLength(x, y, t))
    case (.radii(let x), .radii(let y)):
        return .radii(draw.Radii(lerp(x.TopLeft, y.TopLeft, t), lerp(x.TopRight, y.TopRight, t),
                                 lerp(x.BottomRight, y.BottomRight, t), lerp(x.BottomLeft, y.BottomLeft, t)))
    case (.transforms(let x0), .transforms(let y0)):
        var x = x0
        var y = y0
        while x.count < y.count { x.append(identityOp(like: y[x.count])) }
        while y.count < x.count { y.append(identityOp(like: x[y.count])) }
        var out: [TransformOp] = []
        var i = 0
        while i < x.count {
            if x[i].Name != y[i].Name || x[i].Numbers.count != y[i].Numbers.count || x[i].Lengths.count != y[i].Lengths.count {
                return t < 0.5 ? a : b
            }
            var op = TransformOp(x[i].Name)
            var k = 0
            while k < x[i].Numbers.count { op.Numbers.append(lerp(x[i].Numbers[k], y[i].Numbers[k], t)); k += 1 }
            k = 0
            while k < x[i].Lengths.count { op.Lengths.append(lerpLength(x[i].Lengths[k], y[i].Lengths[k], t)); k += 1 }
            out.append(op)
            i += 1
        }
        return .transforms(out)
    default:
        return t < 0.5 ? a : b
    }
}

extension StyleResolver {
    /// The keyframes of a @keyframes rule by name, the page's over the
    /// user agent's; nil where there is none.
    public func Keyframes(_ name: string) -> [Keyframe]? {
        if let k = Author.keyframes[name] { return k }
        return UA.keyframes[name]
    }

    /// The values a keyframe's declarations give an element whose own
    /// style is base: each declaration applied over it, as computed.
    public func KeyframeValues(_ decls: [css.Longhand], over base: ComputedStyle, parent: ComputedStyle?) -> [string: AnimValue] {
        let p = parent ?? defaultStyle
        let s = ComputedStyle(inheriting: p)
        s.FontSize = base.FontSize
        s.Color = base.Color
        let ctx = ApplyContext(parent: p, rootFontSize: RootFontSize,
                               viewportWidth: ViewportWidth, viewportHeight: ViewportHeight, dark: Dark)
        var out: [string: AnimValue] = [:]
        for d in decls where d.Prop == .fontSize { apply(d, s, ctx) }
        for d in decls where d.Prop != .fontSize { apply(d, s, ctx) }
        for d in decls {
            for ap in AnimatableProperties where ap.Prop == d.Prop {
                if let v = AnimatedValue(ap.Prop, of: s) { out[ap.Name] = v }
            }
        }
        return out
    }
}

/// A display's keyword, as displayOf reads it.
func displayName(_ d: Display) -> string {
    switch d {
    case .none: return "none"
    case .block: return "block"
    case .inline: return "inline"
    case .inlineBlock: return "inline-block"
    case .flex: return "flex"
    case .inlineFlex: return "inline-flex"
    case .grid: return "grid"
    case .inlineGrid: return "inline-grid"
    case .listItem: return "list-item"
    case .table: return "table"
    case .inlineTable: return "inline-table"
    case .tableRow: return "table-row"
    case .tableCell: return "table-cell"
    case .tableRowGroup: return "table-row-group"
    case .tableHeaderGroup: return "table-header-group"
    case .tableFooterGroup: return "table-footer-group"
    case .tableCaption: return "table-caption"
    case .tableColumn: return "table-column"
    case .tableColumnGroup: return "table-column-group"
    case .contents: return "contents"
    }
}
