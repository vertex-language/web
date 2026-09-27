package cascade

import "web/css"

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

    init(_ decls: [css.Declaration]) {
        for d in decls {
            if d.Property.hasPrefix("--") {
                customs.append(CustomDecl(name: d.Property, tokens: d.Tokens, important: d.Important))
                continue
            }
            let props = css.LonghandsOf(d.Property)
            if usesVar(d.Tokens) {
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

func overlap(_ a: [css.Prop], _ b: [css.Prop]) -> bool {
    for x in a where b.contains(x) { return true }
    return false
}

/// Whether tokens call var().
func usesVar(_ tokens: [css.Token]) -> bool {
    for t in tokens where t.Kind == .function && css.lower(t.Value) == "var" { return true }
    return false
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

    func lookup(_ name: string) -> [css.Token]? {
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
func substitute(_ tokens: [css.Token], _ scope: CustomScope?, _ depth: int = 0) -> [css.Token]? {
    if depth > 24 { return nil }
    if !usesVar(tokens) { return tokens }
    var out: [css.Token] = []
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind != .function || css.lower(t.Value) != "var" {
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
            value = substitute(v, scope, depth + 1)
        }
        if value == nil, let f = fallback {
            value = substitute(f, scope, depth + 1)
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
func customScope(_ decls: [CustomDecl], parent: CustomScope?) -> CustomScope? {
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
func expand(_ d: css.Declaration, _ scope: CustomScope?) -> [css.Longhand] {
    var tokens = substitute(d.Tokens, scope) ?? [css.Token(kind: .ident, value: "unset")]
    if tokens.isEmpty { tokens = [css.Token(kind: .ident, value: "unset")] }
    let parsed = css.Longhands(css.Declaration(property: d.Property, value: css.Serialize(tokens), important: d.Important, tokens: tokens))
    if !parsed.isEmpty { return parsed }
    let unset = [css.Token(kind: .ident, value: "unset")]
    return css.Longhands(css.Declaration(property: d.Property, value: "unset", important: d.Important, tokens: unset))
}
