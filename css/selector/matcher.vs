package selector

import (
    "web/css"
    "web/html"
)

/// What a page's state says about its elements, which the dynamic
/// pseudo-classes ask: which element the pointer is over, which has the
/// keyboard, which is being pressed. An element is hovered when it or a
/// descendant is under the pointer, as `:hover` applies to ancestors.
public final class MatchContext {
    public var Hovered: html.Node?
    public var Focused: html.Node?
    public var Active: html.Node?
    /// Whether a link has been visited, asked with its element: the
    /// host knows its history. Nothing is visited without it.
    public var Visited: ((html.Node) -> bool)?
    // Each element's 1-based place among its parent's element children,
    // and each parent's count of them, filled in a parent at a time: the
    // nth-child family asks for every element on a page.
    var indexOf: [int64: int] = [:]
    var countOf: [int64: int] = [:]

    public init() {
        Hovered = nil
        Focused = nil
        Active = nil
        Visited = nil
    }

    /// An empty context: nothing hovered, focused or active.
    public static let none = MatchContext()

    /// Forgets what was learned about the tree's shape: call after
    /// elements are added or removed.
    public func Reset() {
        indexOf = [:]
        countOf = [:]
    }

    func siblingIndex(_ node: html.Node) -> (index: int, count: int) {
        guard let p = node.Parent else { return (index: 1, count: 1) }
        if let i = indexOf[node.Id], let n = countOf[p.Id] {
            return (index: i, count: n)
        }
        var n = 0
        for c in p.Children where c.Kind == html.NodeKind.element {
            n += 1
            indexOf[c.Id] = n
        }
        countOf[p.Id] = n
        return (index: indexOf[node.Id] ?? 1, count: n)
    }

    func isHovered(_ node: html.Node) -> bool {
        var cur = Hovered
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    }

    func isActive(_ node: html.Node) -> bool {
        var cur = Active
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    }
}

/// Matches a single compound part against an HTML element node.
public func MatchPart(_ part: SelectorPart, _ node: html.Node) -> bool {
    return MatchPartIn(part, node, MatchContext.none)
}

public func MatchPartIn(_ part: SelectorPart, _ node: html.Node, _ ctx: MatchContext) -> bool {
    return matchPart(part, node, ctx, pseudoElement: nil)
}

func matchPart(_ part: SelectorPart, _ node: html.Node, _ ctx: MatchContext, pseudoElement: string?) -> bool {
    if node.Kind != html.NodeKind.element {
        return false
    }

    // A pseudo-element is not an element, unless that is what is asked
    // about: `p::before` matches p's ::before.
    if part.PseudoElement != pseudoElement {
        return false
    }

    // Tag name check; tag names are lowercase on both sides.
    if let tag = part.Tag {
        if tag != "*" && node.TagName != tag {
            return false
        }
    }

    // ID check (#id)
    if let id = part.Id {
        if node.IdAttr() != id {
            return false
        }
    }

    // Classes check (.class)
    var i = 0
    while i < part.Classes.count {
        if !node.HasClass(part.Classes[i]) {
            return false
        }
        i += 1
    }

    // Attribute selectors ([attr], [attr=val], [attr^=val], etc.)
    var j = 0
    while j < part.Attributes.count {
        let attrSel = part.Attributes[j]
        guard let val = node.GetAttribute(attrSel.Name) else {
            return false
        }
        switch attrSel.Op {
        case .exists:
            break
        case .exact:
            if val != attrSel.Value { return false }
        case .prefix:
            if !hasPrefix(val, attrSel.Value) { return false }
        case .suffix:
            if !hasSuffix(val, attrSel.Value) { return false }
        case .contains:
            if !contains(val, attrSel.Value) { return false }
        }
        j += 1
    }

    // Pseudo-classes
    var k = 0
    while k < part.Pseudos.count {
        if !matchPseudo(part.Pseudos[k], node, ctx) { return false }
        k += 1
    }

    return true
}

func matchPseudo(_ p: Pseudo, _ node: html.Node, _ ctx: MatchContext) -> bool {
    switch p.Name {
    case "only-child":
        return node.PreviousElementSibling() == nil && node.NextElementSibling() == nil
    case "first-of-type":
        return previousOfType(node) == nil
    case "last-of-type":
        return nextOfType(node) == nil
    case "only-of-type":
        return previousOfType(node) == nil && nextOfType(node) == nil
    case "nth-child":
        return nthMatches(p.A, p.B, ctx.siblingIndex(node).index)
    case "nth-last-child":
        let s = ctx.siblingIndex(node)
        return nthMatches(p.A, p.B, s.count - s.index + 1)
    case "first-child":
        return ctx.siblingIndex(node).index == 1
    case "last-child":
        let s = ctx.siblingIndex(node)
        return s.index == s.count
    case "nth-of-type":
        return nthMatches(p.A, p.B, indexAmongSiblings(node, ofType: true, fromEnd: false))
    case "nth-last-of-type":
        return nthMatches(p.A, p.B, indexAmongSiblings(node, ofType: true, fromEnd: true))
    case "root":
        return node.Parent == nil || node.Parent?.Kind == html.NodeKind.document
    case "empty":
        var i = 0
        while i < node.Children.count {
            let c = node.Children[i]
            if c.Kind == html.NodeKind.element { return false }
            if c.Kind == html.NodeKind.text && !c.Text.isEmpty { return false }
            i += 1
        }
        return true
    case "hover":
        return ctx.isHovered(node)
    case "active":
        return ctx.isActive(node)
    case "focus", "focus-visible":
        if let f = ctx.Focused { return f.Id == node.Id }
        return false
    case "focus-within":
        var cur = ctx.Focused
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    case "link", "any-link":
        return (node.TagName == "a" || node.TagName == "area") && node.HasAttribute("href")
    case "visited":
        guard (node.TagName == "a" || node.TagName == "area") && node.HasAttribute("href") else { return false }
        if let v = ctx.Visited { return v(node) }
        return false
    case "checked":
        if node.TagName == "option" { return node.HasAttribute("selected") }
        return node.HasAttribute("checked")
    case "disabled":
        return node.HasAttribute("disabled")
    case "enabled":
        return isFormControl(node) && !node.HasAttribute("disabled")
    case "required":
        return node.HasAttribute("required")
    case "optional":
        return isFormControl(node) && !node.HasAttribute("required")
    case "placeholder-shown":
        return node.HasAttribute("placeholder") && (node.GetAttribute("value") ?? "").isEmpty
    case "not":
        var i = 0
        while i < p.Inner.count {
            if MatchComplexIn(p.Inner[i], node, ctx) { return false }
            i += 1
        }
        return true
    case "is", "where", "matches":
        var i = 0
        while i < p.Inner.count {
            if MatchComplexIn(p.Inner[i], node, ctx) { return true }
            i += 1
        }
        return false
    case "has":
        var i = 0
        while i < p.Inner.count {
            if hasDescendantMatching(node, p.Inner[i], ctx) { return true }
            i += 1
        }
        return false
    case "lang", "dir", "target", "defined":
        return p.Name == "defined"
    default:
        return false
    }
}

func isFormControl(_ node: html.Node) -> bool {
    let t = node.TagName
    return t == "input" || t == "button" || t == "select" || t == "textarea" || t == "option" || t == "fieldset"
}

func hasDescendantMatching(_ node: html.Node, _ sel: ComplexSelector, _ ctx: MatchContext) -> bool {
    var i = 0
    while i < node.Children.count {
        let c = node.Children[i]
        if c.Kind == html.NodeKind.element {
            if MatchComplexIn(sel, c, ctx) { return true }
            if hasDescendantMatching(c, sel, ctx) { return true }
        }
        i += 1
    }
    return false
}

func previousOfType(_ node: html.Node) -> html.Node? {
    var cur = node.PreviousElementSibling()
    while let n = cur {
        if n.TagName == node.TagName { return n }
        cur = n.PreviousElementSibling()
    }
    return nil
}

func nextOfType(_ node: html.Node) -> html.Node? {
    var cur = node.NextElementSibling()
    while let n = cur {
        if n.TagName == node.TagName { return n }
        cur = n.NextElementSibling()
    }
    return nil
}

/// The 1-based position of an element among its parent's element
/// children, counting only those of its type when asked, from the end
/// when asked.
func indexAmongSiblings(_ node: html.Node, ofType: bool, fromEnd: bool) -> int {
    guard let p = node.Parent else { return 1 }
    var index = 0
    var i = fromEnd ? p.Children.count - 1 : 0
    while i >= 0 && i < p.Children.count {
        let c = p.Children[i]
        if c.Kind == html.NodeKind.element && (!ofType || c.TagName == node.TagName) {
            index += 1
            if c.Id == node.Id { return index }
        }
        i += fromEnd ? -1 : 1
    }
    return index
}

/// Whether index is An+B for some n >= 0.
func nthMatches(_ a: int, _ b: int, _ index: int) -> bool {
    if a == 0 { return index == b }
    let diff = index - b
    if diff % a != 0 { return false }
    return diff / a >= 0
}

/// Matches a complex selector (e.g. `div.menu > ul li a`) against an element node.
public func MatchComplex(_ complex: ComplexSelector, _ node: html.Node) -> bool {
    return MatchComplexIn(complex, node, MatchContext.none)
}

/// Matches a complex selector against an element, with the page's state
/// for the dynamic pseudo-classes.
public func MatchComplexIn(_ complex: ComplexSelector, _ node: html.Node, _ ctx: MatchContext) -> bool {
    return MatchComplexIn(complex, node, ctx, pseudoElement: nil)
}

/// Matches a selector that ends in a pseudo-element -- `a::before` --
/// against an element's pseudo-element of that name; with nil, a
/// selector ending in a pseudo-element matches nothing.
public func MatchComplexIn(_ complex: ComplexSelector, _ node: html.Node, _ ctx: MatchContext, pseudoElement: string?) -> bool {
    if node.Kind != html.NodeKind.element {
        return false
    }

    let compounds = complex.Compounds
    if compounds.isEmpty { return false }

    let lastIdx = compounds.count - 1
    // The target element must match the rightmost compound selector
    if !matchPart(compounds[lastIdx].Part, node, ctx, pseudoElement: pseudoElement) {
        return false
    }

    var curCompoundIdx = lastIdx - 1
    var currentNode: html.Node? = node

    while curCompoundIdx >= 0 {
        let comb = compounds[curCompoundIdx].CombinatorWithNext

        switch comb {
        case .child:
            currentNode = currentNode?.Parent
            guard let cur = currentNode else { return false }
            if !MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
                return false
            }

        case .descendant, .none:
            currentNode = currentNode?.Parent
            var matched = false
            while let cur = currentNode {
                if MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
                    matched = true
                    currentNode = cur
                    break
                }
                currentNode = cur.Parent
            }
            if !matched { return false }

        case .adjacentSibling:
            currentNode = currentNode?.PreviousElementSibling()
            guard let cur = currentNode else { return false }
            if !MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
                return false
            }

        case .generalSibling:
            currentNode = currentNode?.PreviousElementSibling()
            var matched = false
            while let cur = currentNode {
                if MatchPartIn(compounds[curCompoundIdx].Part, cur, ctx) {
                    matched = true
                    currentNode = cur
                    break
                }
                currentNode = cur.PreviousElementSibling()
            }
            if !matched { return false }
        }

        curCompoundIdx -= 1
    }

    return true
}

// String helpers for attribute matching
func toLower(_ s: string) -> string {
    var b = [uint8](s.utf8)
    var i = 0
    var changed = false
    while i < b.count {
        if b[i] >= 65 && b[i] <= 90 {
            b[i] = b[i] + 32
            changed = true
        }
        i += 1
    }
    if !changed { return s }
    return strFrom(b, 0, b.count)
}

func hasPrefix(_ str: string, _ prefix: string) -> bool {
    let sb = bytesFrom(str)
    let pb = bytesFrom(prefix)
    if pb.count > sb.count { return false }
    var i = 0
    while i < pb.count {
        if sb[i] != pb[i] { return false }
        i += 1
    }
    return true
}

func hasSuffix(_ str: string, _ suffix: string) -> bool {
    let sb = bytesFrom(str)
    let pb = bytesFrom(suffix)
    if pb.count > sb.count { return false }
    let offset = sb.count - pb.count
    var i = 0
    while i < pb.count {
        if sb[offset + i] != pb[i] { return false }
        i += 1
    }
    return true
}

func contains(_ str: string, _ needle: string) -> bool {
    let sb = bytesFrom(str)
    let nb = bytesFrom(needle)
    if nb.isEmpty { return true }
    if nb.count > sb.count { return false }
    var i = 0
    while i <= sb.count - nb.count {
        var match = true
        var j = 0
        while j < nb.count {
            if sb[i + j] != nb[j] {
                match = false
                break
            }
            j += 1
        }
        if match { return true }
        i += 1
    }
    return false
}
