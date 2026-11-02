package cascade

import (
    "web/css"
    "web/html"
)

// Custom properties and var() (CSS Custom Properties for Cascading
// Variables 1). A custom property (--x) cascades like any property and
// inherits; its value is tokens. A declaration using var() can't be
// parsed until the element's custom properties are known, so it is kept
// as it was written and parsed per element, after substitution.

/// One custom property declaration.
struct CustomDecl {
    let name: string
    let tokens: [css.Token]
    let important: bool
}

/// A rule's declarations (or a style attribute's), split for the
/// cascade: what parses now, custom properties, and what waits for
/// var() substitution. Within one block, a later declaration of a
/// property replaces an earlier one of the same importance, as the
/// cascade would.
struct SplitDecls {
    var longhands: [css.Longhand] = []
    var customs: [CustomDecl] = []
    var pending: [css.Declaration] = []

    init() {}

    init(decls: [css.Declaration]) {
        for d in decls {
            if d.Property.hasPrefix("--") {
                customs.append(CustomDecl(name: d.Property, tokens: d.Tokens, important: d.Important))
                continue
            }
            let props = css.LonghandsOf(d.Property)
            if usesVar(d.Tokens) || usesAttr(d) || usesSiblingFunctions(d.Tokens) {
                if props.isEmpty { continue }
                longhands = longhands.filter { l in l.Important != d.Important || !props.contains(l.Prop) }
                pending = pending.filter { p in p.Important != d.Important || !overlap(css.LonghandsOf(p.Property), props) }
                pending.append(d)
            } else {
                let parsed = css.Longhands(d)
                // An invalid declaration is dropped: an earlier one stands.
                if parsed.isEmpty { continue }
                pending = pending.filter { p in p.Important != d.Important || !overlap(css.LonghandsOf(p.Property), props) }
                longhands.append(contentsOf: parsed)
            }
        }
    }

    var isEmpty: bool { return longhands.isEmpty && customs.isEmpty && pending.isEmpty }
}

func overlap(a: [css.Prop], b: [css.Prop]) -> bool {
    for x in a where b.contains(x) { return true }
    return false
}

/// Whether tokens call var().
func usesVar(tokens: [css.Token]) -> bool {
    for t in tokens where t.Kind == .function && css.lower(t.Value) == "var" { return true }
    return false
}

/// Whether a declaration calls attr() where it is substituted like var()
/// (CSS Values 5): anywhere but content, which reads its own.
func usesAttr(d: css.Declaration) -> bool {
    return d.Property != "content" && !attrNames(d.Tokens).isEmpty
}

/// Whether tokens call sibling-index() or sibling-count(), which are
/// numbers for each element, substituted as attr() is.
func usesSiblingFunctions(tokens: [css.Token]) -> bool {
    for t in tokens where t.Kind == .function {
        let f = css.lower(t.Value)
        if f == "sibling-index" || f == "sibling-count" { return true }
    }
    return false
}

/// sibling-index() (1 for the first) or sibling-count(): where an
/// element is among its parent's elements, and how many there are.
func siblingNumber(node: html.Node, count: bool) -> float32 {
    guard let parent = node.Parent else { return 1 }
    var n = 0
    var index = 1
    for c in parent.Children where c.Kind == html.NodeKind.element {
        n += 1
        if c.Id == node.Id { index = n }
    }
    return float32(count ? n : index)
}

/// The attributes the attr() calls in tokens name.
func attrNames(tokens: [css.Token]) -> [string] {
    var out: [string] = []
    var i = 0
    while i + 1 < tokens.count {
        if tokens[i].Kind == .function && css.lower(tokens[i].Value) == "attr" && tokens[i + 1].Kind == .ident {
            out.append(css.lower(tokens[i + 1].Value))
        }
        i += 1
    }
    return out
}

/// attr(name <type>?, <fallback>?) for an element: the attribute as a
/// string; with type(...) parsed as CSS; with a unit (px, %, em, number)
/// a number in it. Absent, the fallback; with none, an empty string
/// untyped and nothing typed (the declaration fails).
func attrTokens(args: [css.Token], node: html.Node) -> [css.Token]? {
    guard let name = args.first, name.Kind == .ident else { return nil }
    var kind = ""
    var fallback: [css.Token]? = nil
    var k = 1
    while k < args.count {
        let a = args[k]
        if a.Kind == .comma {
            fallback = Array(args[(k + 1)...])
            break
        }
        if a.Kind == .function && css.lower(a.Value) == "type" { kind = "type" }
        else if a.Kind == .ident && kind.isEmpty { kind = css.lower(a.Value) }
        else if a.Kind == .delim && a.Value == "%" { kind = "%" }
        k += 1
    }
    guard let value = node.GetAttribute(css.lower(name.Value)) else {
        if let f = fallback { return f }
        return kind.isEmpty || kind == "raw-string" || kind == "string" ? [css.Token(kind: .string, value: "")] : nil
    }
    switch kind {
    case "", "raw-string", "string":
        return [css.Token(kind: .string, value: value)]
    case "type":
        let parsed = css.Tokenize(value).filter { $0.Kind != .eof }
        return parsed.isEmpty ? fallback : parsed
    default:
        // A unit: the attribute is a number in it.
        let b = [uint8](value.utf8)
        var start = 0
        while start < b.count && b[start] == 32 { start += 1 }
        var end = b.count
        while end > start && b[end - 1] == 32 { end -= 1 }
        if start == end { return fallback }
        let n = css.parseNumber(b, start, end)
        let text = stringOf(b, start, end)
        if n == 0 && text != "0" && !text.hasPrefix("0.") && !text.hasPrefix("-0") && text != ".0" { return fallback }
        if kind == "number" { return [css.Token(kind: .number, numberVal: n)] }
        if kind == "%" { return [css.Token(kind: .percentage, numberVal: n)] }
        return [css.Token(kind: .dimension, unit: kind, numberVal: n)]
    }
}

/// The custom properties an element sees: those its own rules declare,
/// then its parent's scope. An element that declares none shares its
/// parent's, so a page's thousands of root properties are never copied.
final class CustomScope {
    let parent: CustomScope?
    var own: [string: [css.Token]] = [:]
    /// Names declared here whose value is invalid (a var() cycle, or a
    /// reference to nothing without a fallback): they hide the parent's.
    var invalid = Set<string>()

    init(parent: CustomScope?) {
        self.parent = parent
    }

    func lookup(name: string) -> [css.Token]? {
        var s: CustomScope? = self
        while let scope = s {
            if scope.invalid.contains(name) { return nil }
            if let v = scope.own[name] { return v }
            s = scope.parent
        }
        return nil
    }
}

/// Tokens with every var() replaced by its custom property's value, or
/// its fallback; nil where one refers to nothing and has no fallback, or
/// the references run too deep (a cycle).
func substitute(tokens: [css.Token], scope: CustomScope?, depth: int = 0, node: html.Node? = nil) -> [css.Token]? {
    if depth > 24 { return nil }
    let attrs = node != nil && (!attrNames(tokens).isEmpty || usesSiblingFunctions(tokens))
    if !usesVar(tokens) && !attrs { return tokens }
    var out: [css.Token] = []
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        let fname = t.Kind == .function ? css.lower(t.Value) : ""
        if fname == "sibling-index" || fname == "sibling-count", let n = node {
            var j = i + 1
            while j < tokens.count && tokens[j].Kind != .closeParen { j += 1 }
            var num = css.Token(kind: .number, numberVal: siblingNumber(n, count: fname == "sibling-count"))
            num.SpaceBefore = t.SpaceBefore
            out.append(num)
            i = j + 1
            continue
        }
        if fname == "attr", let n = node {
            // attr()'s arguments, to the matching parenthesis.
            var args: [css.Token] = []
            var level = 1
            var j = i + 1
            while j < tokens.count {
                let a = tokens[j]
                if a.Kind == .function || a.Kind == .openParen { level += 1 }
                if a.Kind == .closeParen {
                    level -= 1
                    if level == 0 { break }
                }
                args.append(a)
                j += 1
            }
            guard var sub = attrTokens(args, n) else { return nil }
            if let resolved = substitute(sub, scope, depth + 1, node: node) { sub = resolved }
            if !sub.isEmpty { sub[0].SpaceBefore = t.SpaceBefore }
            out.append(contentsOf: sub)
            i = j + 1
            continue
        }
        if fname != "var" {
            out.append(t)
            i += 1
            continue
        }
        // The arguments, to the matching parenthesis.
        var args: [css.Token] = []
        var level = 1
        var j = i + 1
        while j < tokens.count {
            let a = tokens[j]
            if a.Kind == .function || a.Kind == .openParen { level += 1 }
            if a.Kind == .closeParen {
                level -= 1
                if level == 0 { break }
            }
            args.append(a)
            j += 1
        }
        guard let name = args.first, name.Kind == .ident, name.Value.hasPrefix("--") else { return nil }
        var fallback: [css.Token]? = nil
        var k = 1
        var inner = 0
        while k < args.count {
            let a = args[k]
            if a.Kind == .function || a.Kind == .openParen { inner += 1 }
            if a.Kind == .closeParen { inner -= 1 }
            if a.Kind == .comma && inner == 0 {
                var f: [css.Token] = []
                var m = k + 1
                while m < args.count {
                    f.append(args[m])
                    m += 1
                }
                fallback = f
                break
            }
            k += 1
        }
        var value: [css.Token]? = nil
        if let v = scope?.lookup(name.Value) {
            value = substitute(v, scope, depth + 1, node: node)
        }
        if value == nil, let f = fallback {
            value = substitute(f, scope, depth + 1, node: node)
        }
        guard var sub = value else { return nil }
        if !sub.isEmpty { sub[0].SpaceBefore = t.SpaceBefore }
        out.append(contentsOf: sub)
        i = j + 1
    }
    return out
}

/// The scope an element's custom declarations make over its parent's,
/// in cascade order; the parent's own where it declares none.
func customScope(decls: [CustomDecl], parent: CustomScope?) -> CustomScope? {
    if decls.isEmpty { return parent }
    let scope = CustomScope(parent: parent)
    for d in decls { scope.own[d.name] = d.tokens }
    // Values that refer to others are substituted now, against this
    // scope: what inherits is the computed value.
    var names: [string] = []
    for (name, tokens) in scope.own where usesVar(tokens) { names.append(name) }
    for name in names {
        guard let raw = scope.own[name] else { continue }
        if let v = substitute(raw, scope) {
            scope.own[name] = v
        } else {
            scope.own.removeValue(forKey: name)
            scope.invalid.insert(name)
        }
    }
    return scope
}

/// A declaration that waited for var(), substituted and parsed. One
/// whose substitution fails is `unset`, as the spec has it.
func expand(d: css.Declaration, scope: CustomScope?, node: html.Node? = nil) -> [css.Longhand] {
    var tokens = substitute(d.Tokens, scope, node: node) ?? [css.Token(kind: .ident, value: "unset")]
    if tokens.isEmpty { tokens = [css.Token(kind: .ident, value: "unset")] }
    let parsed = css.Longhands(css.Declaration(property: d.Property, value: css.Serialize(tokens), important: d.Important, tokens: tokens))
    if !parsed.isEmpty { return parsed }
    let unset = [css.Token(kind: .ident, value: "unset")]
    return css.Longhands(css.Declaration(property: d.Property, value: "unset", important: d.Important, tokens: unset))
}
