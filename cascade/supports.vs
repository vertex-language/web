package cascade

import (
    "web/css"
    "web/css/selector"
)

// @supports (CSS Conditional Rules 3): whether the engine supports a
// declaration or a selector, combined with not, and, or.

/// Whether an @supports condition holds here: `(display: grid)` where
/// the engine parses the declaration, `selector(:has(a))` where it
/// parses and matches the selector, and those combined with `not`,
/// `and` and `or`. Anything else (`font-tech()`) doesn't hold.
public func SupportsCondition(_ text: string) -> bool {
    return supportsCondition(trimSpaces(text), depth: 0)
}

func supportsCondition(_ text: string, depth: int) -> bool {
    if depth > 16 { return false }
    let t = trimSpaces(text)
    let lowered = css.lower(t)
    if lowered.hasPrefix("not ") || lowered.hasPrefix("not(") {
        let b = [uint8](t.utf8)
        return !supportsInParens(stringOf(b, 3, b.count), depth: depth + 1)
    }
    let ands = splitKeyword(t, "and")
    if ands.count > 1 {
        for part in ands where !supportsInParens(part, depth: depth + 1) { return false }
        return true
    }
    let ors = splitKeyword(t, "or")
    if ors.count > 1 {
        for part in ors where supportsInParens(part, depth: depth + 1) { return true }
        return false
    }
    return supportsInParens(t, depth: depth + 1)
}

func supportsInParens(_ text: string, depth: int) -> bool {
    let t = trimSpaces(text)
    let b = [uint8](t.utf8)
    let lowered = css.lower(t)
    if lowered.hasPrefix("selector(") && t.hasSuffix(")") {
        return supportsSelector(stringOf(b, 9, b.count - 1))
    }
    guard b.count >= 2 && b[0] == 40 && b[b.count - 1] == 41 && closesAtEnd(b) else { return false }
    let inner = trimSpaces(stringOf(b, 1, b.count - 1))
    let ib = [uint8](inner.utf8)
    // A declaration: a name, a colon at the top level.
    if !ib.isEmpty && ib[0] != 40 && !css.lower(inner).hasPrefix("not ") {
        var i = 0
        var level = 0
        while i < ib.count {
            if ib[i] == 40 { level += 1 }
            if ib[i] == 41 { level -= 1 }
            if ib[i] == 58 && level == 0 { return supportsDeclaration(inner) }
            i += 1
        }
    }
    return supportsCondition(inner, depth: depth + 1)
}

/// Whether the engine parses a declaration: a custom property always, a
/// value with var() where it knows the property.
func supportsDeclaration(_ text: string) -> bool {
    let decls = css.ParseDeclarations(text)
    guard let d = decls.first else { return false }
    if d.Property.hasPrefix("--") { return true }
    if usesVar(d.Tokens) { return css.IsKnownProperty(d.Property) }
    return !css.Longhands(d).isEmpty
}

/// The pseudo-classes the matcher implements.
let knownPseudoClasses: Set<string> = [
    "active", "any-link", "checked", "defined", "dir", "disabled", "empty", "enabled", "first-child", "first-of-type",
    "focus", "focus-visible", "focus-within", "has", "hover", "is", "lang", "last-child", "last-of-type", "link",
    "matches", "not", "nth-child", "nth-last-child", "nth-last-of-type", "nth-of-type", "only-child", "only-of-type",
    "optional", "placeholder-shown", "required", "root", "target", "visited", "where",
]

/// Whether a selector parses and asks only what the matcher answers.
func supportsSelector(_ text: string) -> bool {
    let parsed = selector.ParseSelectors(text)
    if parsed.isEmpty { return false }
    for sel in parsed {
        for c in sel.Compounds {
            for p in c.Part.Pseudos where !knownPseudoClasses.contains(p.Name) { return false }
        }
    }
    return true
}

/// Whether the parenthesis at b[0] closes at the end, not before.
func closesAtEnd(_ b: [uint8]) -> bool {
    var level = 0
    var i = 0
    while i < b.count {
        if b[i] == 40 { level += 1 }
        if b[i] == 41 {
            level -= 1
            if level == 0 && i != b.count - 1 { return false }
        }
        i += 1
    }
    return level == 0
}

/// A condition split at a keyword (and, or) standing between
/// parenthesized parts; one part where it doesn't.
func splitKeyword(_ text: string, _ word: string) -> [string] {
    let b = [uint8](text.utf8)
    let w = [uint8](word.utf8)
    var parts: [string] = []
    var start = 0
    var level = 0
    var i = 0
    while i < b.count {
        if b[i] == 40 { level += 1 }
        if b[i] == 41 { level -= 1 }
        if level == 0 && (b[i] == 32 || b[i] == 41) && i + w.count + 1 < b.count {
            // " and (" or ")and(" forms: the word between spaces or parens.
            var j = b[i] == 32 ? i + 1 : i + 1
            var k = 0
            var same = true
            while k < w.count {
                let c = b[j + k] | 0x20
                if c != w[k] { same = false; break }
                k += 1
            }
            j += w.count
            if same && j < b.count && (b[j] == 32 || b[j] == 40) {
                let end = b[i] == 41 ? i + 1 : i
                parts.append(stringOf(b, start, end))
                start = j
                i = j
                continue
            }
        }
        i += 1
    }
    parts.append(stringOf(b, start, b.count))
    return parts.count > 1 ? parts : [text]
}
