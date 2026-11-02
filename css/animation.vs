package css

// CSS Transitions 1 and Animations 1: the transition-* and animation-*
// longhands and their shorthands. Each longhand is a comma list, kept as
// `.string` of its items normalized and joined by "|": times in seconds,
// timing functions as their text (`cubic-bezier(0.2,0,0,1)`), names and
// keywords as written. The cascade reads them back (cascade/animation.vs).

let transitionProps: [Prop] = [.transitionProperty, .transitionDuration, .transitionTimingFunction, .transitionDelay, .transitionBehavior]
let animationProps: [Prop] = [
    .animationName, .animationDuration, .animationTimingFunction, .animationDelay,
    .animationIterationCount, .animationDirection, .animationFillMode, .animationPlayState,
]

/// A time in seconds: `200ms`, `.3s`, or 0.
func timeOf(t: Token) -> float32? {
    if t.Kind == .number && t.NumberVal == 0 { return 0 }
    if t.Kind != .dimension { return nil }
    switch lower(t.Unit) {
    case "s": return t.NumberVal
    case "ms": return t.NumberVal / 1000
    default: return nil
    }
}

/// A timing function at tokens[i] as normalized text, and how many
/// tokens it took; nil where none starts there.
func timingAt(tokens: [Token], i: int) -> (string, int)? {
    let t = tokens[i]
    if t.Kind == .ident {
        switch lower(t.Value) {
        case "linear", "ease", "ease-in", "ease-out", "ease-in-out", "step-start", "step-end": return (lower(t.Value), 1)
        default: return nil
        }
    }
    if t.Kind != .function { return nil }
    let name = lower(t.Value)
    if name != "cubic-bezier" && name != "steps" && name != "linear" { return nil }
    let end = closeParen(tokens, from: i + 1)
    if end >= tokens.count { return nil }
    var parts: [string] = []
    for arg in splitArgs(tokens, i + 1, end) {
        var words: [string] = []
        for a in arg {
            switch a.Kind {
            case .number: words.append("\(a.NumberVal)")
            case .percentage: words.append("\(a.NumberVal)%")
            case .ident: words.append(lower(a.Value))
            default: return nil
            }
        }
        parts.append(words.joined(separator: " "))
    }
    if name == "cubic-bezier" && parts.count != 4 { return nil }
    if name == "steps" && (parts.count < 1 || parts.count > 2) { return nil }
    return (name + "(" + parts.joined(separator: ",") + ")", end - i + 1)
}

/// The items of a comma list, each its tokens.
func commaItems(tokens: [Token]) -> [[Token]] {
    return splitArgs(tokens, 0, tokens.count)
}

/// One transition-* or animation-* longhand.
func parseAnimationLonghand(prop: Prop, tokens: [Token]) -> Value? {
    var items: [string] = []
    for item in commaItems(tokens) {
        if item.isEmpty { return nil }
        switch prop {
        case .transitionDuration, .transitionDelay, .animationDuration, .animationDelay:
            guard item.count == 1, let s = timeOf(item[0]) else { return nil }
            if s < 0 && (prop == .transitionDuration || prop == .animationDuration) { return nil }
            items.append("\(s)")
        case .transitionTimingFunction, .animationTimingFunction:
            guard let m = timingAt(item, 0), m.1 == item.count else { return nil }
            items.append(m.0)
        case .animationIterationCount:
            guard item.count == 1 else { return nil }
            if item[0].Kind == .ident && lower(item[0].Value) == "infinite" { items.append("infinite") }
            else if item[0].Kind == .number && item[0].NumberVal >= 0 { items.append("\(item[0].NumberVal)") }
            else { return nil }
        default:
            // Names and keywords: one identifier each.
            guard item.count == 1, item[0].Kind == .ident || item[0].Kind == .string else { return nil }
            let word = item[0].Kind == .string ? item[0].Value : item[0].Value
            if prop == .transitionBehavior && lower(word) != "normal" && lower(word) != "allow-discrete" { return nil }
            if prop == .transitionProperty || prop == .transitionBehavior || prop == .animationDirection || prop == .animationFillMode || prop == .animationPlayState {
                items.append(lower(word))
            } else {
                items.append(word)
            }
        }
    }
    if items.isEmpty { return nil }
    return .string(items.joined(separator: "|"))
}

/// `transition: [property || duration || timing || delay]#`.
func parseTransitionShorthand(tokens: [Token]) -> [(Prop, Value)]? {
    var props: [string] = []
    var durations: [string] = []
    var timings: [string] = []
    var delays: [string] = []
    var behaviors: [string] = []
    for item in commaItems(tokens) {
        var property = "all"
        var times: [float32] = []
        var timing = "ease"
        var behavior = "normal"
        var i = 0
        while i < item.count {
            if let s = timeOf(item[i]) { times.append(s); i += 1; continue }
            if let m = timingAt(item, i) { timing = m.0; i += m.1; continue }
            if item[i].Kind == .ident && (lower(item[i].Value) == "allow-discrete" || lower(item[i].Value) == "normal") {
                behavior = lower(item[i].Value)
                i += 1
                continue
            }
            if item[i].Kind == .ident { property = lower(item[i].Value); i += 1; continue }
            return nil
        }
        if times.count > 2 { return nil }
        props.append(property)
        durations.append("\(times.count > 0 ? times[0] : 0)")
        delays.append("\(times.count > 1 ? times[1] : 0)")
        timings.append(timing)
        behaviors.append(behavior)
    }
    if props.isEmpty { return nil }
    return [
        (.transitionProperty, .string(props.joined(separator: "|"))),
        (.transitionDuration, .string(durations.joined(separator: "|"))),
        (.transitionTimingFunction, .string(timings.joined(separator: "|"))),
        (.transitionDelay, .string(delays.joined(separator: "|"))),
        (.transitionBehavior, .string(behaviors.joined(separator: "|"))),
    ]
}

/// `animation: [duration || timing || delay || count || direction ||
/// fill-mode || play-state || name]#`.
func parseAnimationShorthand(tokens: [Token]) -> [(Prop, Value)]? {
    var lists: [[string]] = [[], [], [], [], [], [], [], []]
    for item in commaItems(tokens) {
        var name = "none"
        var times: [float32] = []
        var timing = "ease"
        var count = "1"
        var direction = "normal"
        var fill = "none"
        var state = "running"
        var i = 0
        while i < item.count {
            let t = item[i]
            if let s = timeOf(t) { times.append(s); i += 1; continue }
            if let m = timingAt(item, i) { timing = m.0; i += m.1; continue }
            if t.Kind == .number { count = "\(t.NumberVal)"; i += 1; continue }
            if t.Kind == .string { name = t.Value; i += 1; continue }
            if t.Kind != .ident { return nil }
            let kw = lower(t.Value)
            switch kw {
            case "infinite": count = "infinite"
            case "normal", "reverse", "alternate", "alternate-reverse": direction = kw
            case "forwards", "backwards", "both": fill = kw
            case "running", "paused": state = kw
            default: name = t.Value
            }
            i += 1
        }
        if times.count > 2 { return nil }
        lists[0].append(name)
        lists[1].append("\(times.count > 0 ? times[0] : 0)")
        lists[2].append(timing)
        lists[3].append("\(times.count > 1 ? times[1] : 0)")
        lists[4].append(count)
        lists[5].append(direction)
        lists[6].append(fill)
        lists[7].append(state)
    }
    if lists[0].isEmpty { return nil }
    var out: [(Prop, Value)] = []
    var k = 0
    while k < animationProps.count {
        out.append((animationProps[k], .string(lists[k].joined(separator: "|"))))
        k += 1
    }
    return out
}
