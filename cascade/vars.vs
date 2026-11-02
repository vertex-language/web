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
    for t in tokens where t.Kind == .function {
        let name = css.lower(t.Value)
        if name == "var" || name == "if" || name.hasPrefix("--") { return true }
    }
    return false
}

/// What media() in an if() asks about: the viewport last set.
var conditionWidth: float32 = 0
var conditionHeight: float32 = 0
var conditionDark: bool = false

/// A function @function defines: its parameters, each with what it takes
/// where a call leaves it out, and its result.
struct CustomFunction {
    var params: [(name: string, fallback: [css.Token]?)]
    var result: [css.Token]
}

var customFunctions: [string: CustomFunction] = [:]

/// Reads `@function --name(--a, --b: 1) { result: ... }`.
func DefineCustomFunction(at: css.AtRule) {
    let tokens = css.Tokenize(at.Params).filter { $0.Kind != .eof }
    guard let head = tokens.first, head.Kind == .function, head.Value.hasPrefix("--") else { return }
    var params: [(name: string, fallback: [css.Token]?)] = []
    var i = 1
    var level = 1
    var part: [css.Token] = []
    func flush() {
        guard let name = part.first, name.Kind == .ident, name.Value.hasPrefix("--") else { return }
        var fallback: [css.Token]? = nil
        if let colon = part.firstIndex(where: { $0.Kind == .colon }) { fallback = Array(part[(colon + 1)...]) }
        params.append((name: name.Value, fallback: fallback))
    }
    while i < tokens.count && level > 0 {
        let t = tokens[i]
        if t.Kind == .function || t.Kind == .openParen { level += 1 }
        if t.Kind == .closeParen {
            level -= 1
            if level == 0 { break }
        }
        if t.Kind == .comma && level == 1 {
            flush()
            part = []
        } else {
            part.append(t)
        }
        i += 1
    }
    flush()
    for d in at.Declarations where d.Property == "result" {
        customFunctions[head.Value] = CustomFunction(params: params, result: d.Tokens)
    }
}

/// Tokens as text, near enough to compare two values or read a query.
func tokensText(tokens: [css.Token]) -> string {
    var out = ""
    for t in tokens {
        if t.SpaceBefore && !out.isEmpty { out += " " }
        switch t.Kind {
        case .ident, .string, .hash, .delim, .atKeyword: out += t.Value
        case .function: out += t.Value + "("
        case .number: out += "\(t.NumberVal)"
        case .dimension: out += "\(t.NumberVal)\(t.Unit)"
        case .percentage: out += "\(t.NumberVal)%"
        case .colon: out += ":"
        case .comma: out += ","
        case .openParen: out += "("
        case .closeParen: out += ")"
        default: break
        }
    }
    return out
}

/// The tokens between a function's parenthesis and the one that closes it,
/// and where it closes.
func functionArgs(tokens: [css.Token], from start: int) -> (args: [css.Token], end: int) {
    var level = 1
    var j = start
    var out: [css.Token] = []
    while j < tokens.count {
        let t = tokens[j]
        if t.Kind == .function || t.Kind == .openParen { level += 1 }
        if t.Kind == .closeParen {
            level -= 1
            if level == 0 { break }
        }
        out.append(t)
        j += 1
    }
    return (args: out, end: j)
}

/// Whether one test of an if() holds: style(--x: y), media(...),
/// supports(...), or else.
func ifTestHolds(test: [css.Token], scope: CustomScope?, depth: int, node: html.Node?) -> bool {
    guard let head = test.first else { return false }
    if head.Kind == .ident && css.lower(head.Value) == "else" { return true }
    if head.Kind != .function { return false }
    let inner = functionArgs(test, from: 1).args
    switch css.lower(head.Value) {
    case "style":
        guard let name = inner.first, name.Value.hasPrefix("--") else { return false }
        let actual = scope?.lookup(name.Value)
        guard let colon = inner.firstIndex(where: { $0.Kind == .colon }) else { return actual != nil }
        guard let have = actual else { return false }
        let wanted = substitute(Array(inner[(colon + 1)...]), scope: scope, depth: depth + 1, node: node) ?? []
        return trimSpaces(tokensText(have)) == trimSpaces(tokensText(wanted))
    case "media":
        return mediaMatches("(" + tokensText(inner) + ")", width: conditionWidth, height: conditionHeight, dark: conditionDark)
    case "supports":
        return SupportsCondition("(" + tokensText(inner) + ")")
    default:
        return false
    }
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
        if fname == "if" {
            // The first branch whose test holds; none, and nothing is there.
            let call = functionArgs(tokens, from: i + 1)
            var branch: [css.Token] = []
            var branches: [[css.Token]] = []
            var level = 0
            for a in call.args {
                if a.Kind == .function || a.Kind == .openParen { level += 1 }
                if a.Kind == .closeParen { level -= 1 }
                if a.Kind == .semicolon && level == 0 {
                    branches.append(branch)
                    branch = []
                } else {
                    branch.append(a)
                }
            }
            if !branch.isEmpty { branches.append(branch) }
            for b in branches {
                var colon = -1
                var l = 0
                var k = 0
                while k < b.count {
                    if b[k].Kind == .function || b[k].Kind == .openParen { l += 1 }
                    if b[k].Kind == .closeParen { l -= 1 }
                    if b[k].Kind == .colon && l == 0 {
                        colon = k
                        break
                    }
                    k += 1
                }
                if colon < 0 { continue }
                if ifTestHolds(Array(b[0..<colon]), scope: scope, depth: depth, node: node) {
                    guard let value = substitute(Array(b[(colon + 1)...]), scope: scope, depth: depth + 1, node: node) else { return nil }
                    out.append(contentsOf: value)
                    break
                }
            }
            i = call.end + 1
            continue
        }
        if t.Kind == .function && t.Value.hasPrefix("--"), let f = customFunctions[t.Value] {
            // The call's arguments are the result's custom properties.
            let call = functionArgs(tokens, from: i + 1)
            var args: [[css.Token]] = []
            var part: [css.Token] = []
            var level = 0
            for a in call.args {
                if a.Kind == .function || a.Kind == .openParen { level += 1 }
                if a.Kind == .closeParen { level -= 1 }
                if a.Kind == .comma && level == 0 {
                    args.append(part)
                    part = []
                } else {
                    part.append(a)
                }
            }
            if !part.isEmpty { args.append(part) }
            let inner = CustomScope(parent: scope)
            var k = 0
            while k < f.params.count {
                let given = k < args.count ? args[k] : f.params[k].fallback
                guard let g = given, let value = substitute(g, scope: scope, depth: depth + 1, node: node) else { return nil }
                inner.own[f.params[k].name] = value
                k += 1
            }
            guard let value = substitute(f.result, scope: inner, depth: depth + 1, node: node) else { return nil }
            out.append(contentsOf: value)
            i = call.end + 1
            continue
        }
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
