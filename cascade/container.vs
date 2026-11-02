package cascade

import (
    "web/css"
    "web/html"
)

// Container queries (CSS Conditional 5): `@container [name] <condition>`.
// A rule under one applies to an element when its nearest ancestor that
// is a container -- of the name, where one is given -- meets the
// condition. Size features need a size container (container-type size or
// inline-size), measured by the page after layout (Page passes the sizes
// back through ContainerSizes and restyles); style() needs none, since
// every element is a style container.

/// One @container prelude.
public struct ContainerQuery {
    public var Name: string
    public var Condition: string

    /// Parses `card (width > 400px)`, `(min-width: 30em) and style(--x: y)`.
    static func parse(params: string) -> ContainerQuery {
        let t = trimSpaces(params)
        let b = [uint8](t.utf8)
        var i = 0
        while i < b.count && b[i] != 32 && b[i] != 40 { i += 1 }
        let first = stringOf(b, 0, i)
        let lowered = css.lower(first)
        if !first.isEmpty && lowered != "not" && !first.hasPrefix("style") {
            return ContainerQuery(Name: first, Condition: trimSpaces(stringOf(b, i, b.count)))
        }
        return ContainerQuery(Name: "", Condition: t)
    }
}

/// A container's content box, as last laid out.
public struct ContainerSize {
    public var Width: float32
    public var Height: float32
    /// Whether the height is contained, so that it can be queried.
    public var HasHeight: bool

    public init(Width: float32, Height: float32, HasHeight: bool) {
        self.Width = Width
        self.Height = Height
        self.HasHeight = HasHeight
    }
}

extension StyleResolver {
    /// Whether the page's sheets query containers or use cq units, so
    /// that the page measures containers after layout.
    public var UsesContainers: bool {
        return Author.UsesContainerQueries || Author.UsesContainerUnits || UA.UsesContainerQueries
    }

    /// Whether every query holds for a node.
    func containersHold(queries: [ContainerQuery], node: html.Node) -> bool {
        for q in queries where !containerHolds(q, node) { return false }
        return true
    }

    func containerHolds(q: ContainerQuery, node: html.Node) -> bool {
        // The nearest ancestor of the name that is a size container -- or,
        // for a query of style() only, any element of the name.
        let sizeQuery = conditionAsksSize(q.Condition)
        var p = node.Parent
        while let a = p {
            p = a.Parent
            if a.Kind != html.NodeKind.element { continue }
            guard let s = stylesById[a.Id] else { continue }
            if !q.Name.isEmpty && !s.ContainerNames.contains(q.Name) { continue }
            if sizeQuery && s.ContainerType == "normal" { continue }
            let size = ContainerSizes[a.Id]
            return conditionHolds(q.Condition, size, s)
        }
        return false
    }

    /// The nearest size container's content box above node: what cq
    /// units are of, the viewport where there is none.
    func nearestContainerSize(node: html.Node) -> (w: float32, h: float32) {
        var p = node.Parent
        while let a = p {
            p = a.Parent
            if let s = stylesById[a.Id], s.ContainerType != "normal", let size = ContainerSizes[a.Id] {
                return (w: size.Width, h: size.HasHeight ? size.Height : ViewportHeight)
            }
        }
        return (w: ViewportWidth, h: ViewportHeight)
    }

    /// Forgets the last pass's styles: called before a restyle.
    public func BeginStylePass() {
        stylesById = [:]
    }

    /// Records the content boxes of the size containers once laid out;
    /// answers whether any changed, which means a restyle.
    public func SetContainerSizes(sizes: [int64: ContainerSize]) -> bool {
        var changed = sizes.count != ContainerSizes.count
        if !changed {
            for (id, s) in sizes {
                guard let old = ContainerSizes[id] else { changed = true; break }
                if old.Width != s.Width || old.HasHeight != s.HasHeight || (s.HasHeight && old.Height != s.Height) { changed = true; break }
            }
        }
        ContainerSizes = sizes
        return changed
    }

    /// The elements that are size containers in the last pass, and their
    /// styles, for the page to measure.
    public var SizeContainers: [(id: int64, style: ComputedStyle)] {
        var out: [(id: int64, style: ComputedStyle)] = []
        for (id, s) in stylesById where s.ContainerType != "normal" { out.append((id: id, style: s)) }
        return out
    }
}

/// Whether a condition asks about size (anything but style()).
func conditionAsksSize(cond: string) -> bool {
    var rest = css.lower(cond)
    // Drop every style(...) and see whether a feature is left.
    while let start = indexOf(rest, "style(") {
        let b = [uint8](rest.utf8)
        var i = start + 6
        var depth = 1
        while i < b.count && depth > 0 {
            if b[i] == 40 { depth += 1 }
            if b[i] == 41 { depth -= 1 }
            i += 1
        }
        rest = stringOf(b, 0, start) + stringOf(b, i, b.count)
    }
    return rest.contains("(")
}

/// A container condition: `not`, `and`, `or` over parenthesized
/// features, nested conditions, and style() queries.
func conditionHolds(cond: string, size: ContainerSize?, style: ComputedStyle) -> bool {
    let t = trimSpaces(cond)
    if t.isEmpty { return true }
    let lowered = css.lower(t)
    if lowered.hasPrefix("not ") || lowered.hasPrefix("not(") {
        return !conditionHolds(stringOf([uint8](t.utf8), 3, t.utf8.count), size, style)
    }
    let (terms, joiners) = splitCondition(t)
    if terms.count > 1 {
        let any = joiners.contains("or")
        var result = !any
        for term in terms {
            let ok = conditionHolds(term, size, style)
            if any { result = result || ok } else { result = result && ok }
        }
        return result
    }
    // A single term: style(...), or (...) holding a feature or a
    // condition of its own.
    if lowered.hasPrefix("style(") && t.hasSuffix(")") {
        return styleQueryHolds(stringOf([uint8](t.utf8), 6, t.utf8.count - 1), style)
    }
    if t.hasPrefix("(") && t.hasSuffix(")") {
        let inner = trimSpaces(stringOf([uint8](t.utf8), 1, t.utf8.count - 1))
        let li = css.lower(inner)
        if inner.hasPrefix("(") || li.hasPrefix("not ") || li.hasPrefix("style(") {
            return conditionHolds(inner, size, style)
        }
        guard let s = size else { return false }
        if !s.HasHeight && (li.contains("height") || li.contains("block-size") || li.contains("aspect-ratio") || li.contains("orientation")) {
            return false
        }
        let normalized = replaceAll(replaceAll(inner, "inline-size", "width"), "block-size", "height")
        if css.lower(normalized).hasPrefix("aspect-ratio") || css.lower(normalized).contains("aspect-ratio") {
            return aspectRatioHolds(normalized, s)
        }
        return mediaFeature(normalized, width: s.Width, height: s.Height)
    }
    return false
}

/// Splits `a and b and c` / `a or b` at the top level: the terms and the
/// words between them.
func splitCondition(t: string) -> ([string], [string]) {
    let b = [uint8](t.utf8)
    var terms: [string] = []
    var joiners: [string] = []
    var depth = 0
    var start = 0
    var i = 0
    while i < b.count {
        let c = b[i]
        if c == 40 { depth += 1 }
        if c == 41 { depth -= 1 }
        if depth == 0 && c == 32 {
            var j = i
            while j < b.count && b[j] == 32 { j += 1 }
            var k = j
            while k < b.count && b[k] != 32 && b[k] != 40 { k += 1 }
            let word = css.lower(stringOf(b, j, k))
            if (word == "and" || word == "or") && k < b.count {
                terms.append(trimSpaces(stringOf(b, start, i)))
                joiners.append(word)
                start = k
                i = k
                continue
            }
        }
        i += 1
    }
    terms.append(trimSpaces(stringOf(b, start, b.count)))
    return (terms, joiners)
}

/// `aspect-ratio > 1`, `aspect-ratio: 16/9`, `min-aspect-ratio: 1/1`.
func aspectRatioHolds(text: string, s: ContainerSize) -> bool {
    if s.Height <= 0 { return false }
    let ratio = s.Width / s.Height
    let t = css.lower(text)
    func value(v: string) -> float32 {
        let parts = v.split(separator: "/").map { css.ParseNumberText(trimSpaces(string($0))) }
        if parts.count == 2 && parts[1] != 0 { return parts[0] / parts[1] }
        return parts.isEmpty ? 0 : parts[0]
    }
    let tb = [uint8](t.utf8)
    for op in [">=", "<=", ">", "<", "="] {
        if let at = indexOf(t, op) {
            let rhs = value(trimSpaces(stringOf(tb, at + op.utf8.count, tb.count)))
            switch op {
            case ">=": return ratio >= rhs
            case "<=": return ratio <= rhs
            case ">": return ratio > rhs
            case "<": return ratio < rhs
            default: return abs(ratio - rhs) < 0.001
            }
        }
    }
    if let at = indexOf(t, ":") {
        let name = trimSpaces(stringOf(tb, 0, at))
        let rhs = value(trimSpaces(stringOf(tb, at + 1, tb.count)))
        if name == "min-aspect-ratio" { return ratio >= rhs }
        if name == "max-aspect-ratio" { return ratio <= rhs }
        return abs(ratio - rhs) < 0.001
    }
    return false
}

/// `style(--theme: dark)`: the container's custom property is that
/// value; `style(--theme)`: it has one.
func styleQueryHolds(text: string, style: ComputedStyle) -> bool {
    let t = trimSpaces(text)
    let b = [uint8](t.utf8)
    var i = 0
    while i < b.count && b[i] != 58 { i += 1 }
    let name = trimSpaces(stringOf(b, 0, i))
    if !name.hasPrefix("--") { return false }
    guard let tokens = style.customs?.lookup(name) else { return false }
    if i >= b.count { return true }
    let want = stringOf(b, i + 1, b.count)
    return collapsedSpaces(css.Serialize(tokens)) == collapsedSpaces(want)
}

/// Where needle first starts in s, in bytes; nil where it doesn't.
func indexOf(s: string, needle: string) -> int? {
    let b = [uint8](s.utf8)
    let n = [uint8](needle.utf8)
    if n.isEmpty || n.count > b.count { return nil }
    var i = 0
    while i + n.count <= b.count {
        var k = 0
        while k < n.count && b[i + k] == n[k] { k += 1 }
        if k == n.count { return i }
        i += 1
    }
    return nil
}

/// s with every `from` replaced by `to`.
func replaceAll(s: string, from: string, to: string) -> string {
    var out = ""
    var rest = s
    while let at = indexOf(rest, from) {
        let b = [uint8](rest.utf8)
        out += stringOf(b, 0, at) + to
        rest = stringOf(b, at + from.utf8.count, b.count)
    }
    return out + rest
}

/// s trimmed, with each run of white space one space.
func collapsedSpaces(s: string) -> string {
    var out: [uint8] = []
    var space = false
    for c in s.utf8 {
        if c == 32 || c == 9 || c == 10 || c == 13 {
            space = !out.isEmpty
            continue
        }
        if space { out.append(32); space = false }
        out.append(c)
    }
    return stringOf(out, 0, out.count)
}
