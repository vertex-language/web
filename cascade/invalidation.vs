package cascade

import (
    "web/css"
    "web/css/selector"
    "web/dom"
    "web/html"
)

/// The ids, classes and attribute names some selectors mention.
final class Mentions {
    var ids: Set<string> = []
    var classes: Set<string> = []
    var attributes: Set<string> = []

    init() {}

    func add(_ other: Mentions) {
        for x in other.ids { ids.insert(x) }
        for x in other.classes { classes.insert(x) }
        for x in other.attributes { attributes.insert(x) }
    }
}

/// What a rule set's selectors can tell elements apart by. A change to
/// an element that touches nothing in `all` can't change which rules
/// match anything. What `siblings` mentions (selectors with `+` or `~`)
/// can change how the element's later siblings match; what `has`
/// mentions (selectors with `:has()`) how its ancestors do.
///
/// Pseudo-classes that count siblings (`:first-child`, `:nth-of-type`)
/// depend on where children are, which only a child-list change moves,
/// and that restyles the parent's children anyway.
final class Features {
    let all = Mentions()
    let siblings = Mentions()
    let has = Mentions()
    /// Any :has() at all: a child-list or text change can change how an
    /// ancestor matches.
    var usesHas = false

    init() {}

    func note(_ sel: selector.ComplexSelector) {
        let m = Mentions()
        var sibling = false
        var hasPseudo = false
        noteComplex(sel, m, &sibling, &hasPseudo)
        all.add(m)
        if sibling { siblings.add(m) }
        if hasPseudo {
            has.add(m)
            usesHas = true
        }
    }

    func noteComplex(_ sel: selector.ComplexSelector, _ m: Mentions, _ sibling: inout bool, _ hasPseudo: inout bool) {
        for c in sel.Compounds {
            if c.CombinatorWithNext == .adjacentSibling || c.CombinatorWithNext == .generalSibling { sibling = true }
            notePart(c.Part, m, &sibling, &hasPseudo)
        }
    }

    func notePart(_ part: selector.SelectorPart, _ m: Mentions, _ sibling: inout bool, _ hasPseudo: inout bool) {
        if let id = part.Id { m.ids.insert(id) }
        for c in part.Classes { m.classes.insert(c) }
        for a in part.Attributes { m.attributes.insert(css.lower(a.Name)) }
        for p in part.Pseudos {
            switch p.Name {
            case "checked":
                m.attributes.insert("checked")
                m.attributes.insert("selected")
            case "disabled", "enabled":
                m.attributes.insert("disabled")
            case "required", "optional":
                m.attributes.insert("required")
            case "placeholder-shown":
                m.attributes.insert("placeholder")
                m.attributes.insert("value")
            case "link", "any-link", "visited":
                m.attributes.insert("href")
            case "lang", "dir":
                m.attributes.insert(p.Name)
            case "has":
                hasPseudo = true
            default:
                break
            }
            for inner in p.Inner { noteComplex(inner, m, &sibling, &hasPseudo) }
        }
    }

    /// The attributes `content: attr(name)` reads.
    func note(_ decls: [css.Longhand]) {
        for d in decls where d.Prop == .content {
            if case .families(let parts) = d.Value {
                for part in parts {
                    let b = [uint8](part.utf8)
                    if !b.isEmpty && b[0] == 1 { all.attributes.insert(stringOf(b, 1, b.count)) }
                }
            }
        }
    }
}

/// Whether the cascade reads an attribute itself, outside any selector:
/// inline style, and the presentational hints.
public func ReadsAttribute(_ name: string) -> bool {
    switch name {
    case "style", "hidden", "width", "height", "align", "bgcolor", "color", "size", "border", "cellspacing", "type":
        return true
    default:
        return false
    }
}

/// How far one change reaches.
enum Reach: int {
    case nothing = 0
    case element = 1
    case siblings = 2
    case document = 3
}

/// The farther of two reaches.
func wider(_ a: Reach, _ b: Reach) -> Reach {
    return a.rawValue >= b.rawValue ? a : b
}

extension StyleResolver {
    /// The elements a batch of changes may restyle: each is the root of
    /// a subtree to restyle, as inherited values flow down. Empty where
    /// no rule, no hint and nothing `reads` names depends on what
    /// changed -- the page can skip the frame.
    ///
    /// `reads` answers for the attributes later stages read themselves
    /// (an image's src, a cell's colspan).
    public func Invalidate(_ records: [dom.MutationRecord], reads: (string) -> bool) -> [html.Node] {
        var roots: [html.Node] = []
        var seen = Set<int64>()
        let usesHas = UA.features.usesHas || Author.features.usesHas

        for r in records {
            var reach = Reach.nothing
            var target: html.Node? = r.Target
            switch r.Kind {
            case .attributes:
                reach = attributeReach(r, reads: reads)
            case .childList:
                reach = usesHas ? .document : .element
            case .characterData:
                // A text node's element lays out its text again.
                target = r.Target.Parent
                reach = usesHas ? .document : .element
            }
            guard var t = target, reach != .nothing else { continue }
            if reach == .document {
                // Anything above can match differently: restyle from the top.
                return [rootElement(t)]
            }
            if reach == .siblings, let p = t.Parent, p.Kind == html.NodeKind.element { t = p }
            if !seen.contains(t.Id) {
                seen.insert(t.Id)
                roots.append(t)
            }
        }
        return roots
    }

    /// How far an attribute change reaches: nothing, where no selector,
    /// hint or stage looks at what changed.
    func attributeReach(_ r: dom.MutationRecord, reads: (string) -> bool) -> Reach {
        let name = r.AttributeName
        var reach = Reach.nothing
        if ReadsAttribute(name) || reads(name) { reach = .element }
        if name == "id" {
            var changed: [string] = []
            if let old = r.OldValue { changed.append(old) }
            if let now = r.Target.GetAttribute("id") { changed.append(now) }
            for id in changed {
                reach = wider(reach, reachOf({ m in m.ids.contains(id) }))
            }
        } else if name == "class" {
            // Only the classes that came or went matter.
            let before = classesOf(r.OldValue ?? "")
            let after = r.Target.Classes()
            for c in before where !after.contains(c) {
                reach = wider(reach, reachOf({ m in m.classes.contains(c) }))
            }
            for c in after where !before.contains(c) {
                reach = wider(reach, reachOf({ m in m.classes.contains(c) }))
            }
        }
        // Attribute selectors can name id and class too.
        reach = wider(reach, reachOf({ m in m.attributes.contains(name) }))
        return reach
    }

    /// How far a change to something the test picks out reaches, by
    /// which selectors mention it.
    func reachOf(_ mentioned: (Mentions) -> bool) -> Reach {
        if mentioned(UA.features.has) || mentioned(Author.features.has) { return .document }
        if mentioned(UA.features.siblings) || mentioned(Author.features.siblings) { return .siblings }
        if mentioned(UA.features.all) || mentioned(Author.features.all) { return .element }
        return .nothing
    }
}

/// The element at the top of a node's tree.
func rootElement(_ node: html.Node) -> html.Node {
    var top = node
    while let p = top.Parent, p.Kind == html.NodeKind.element { top = p }
    return top
}

/// The words of a class attribute.
func classesOf(_ s: string) -> [string] {
    var out: [string] = []
    let b = [uint8](s.utf8)
    var i = 0
    while i < b.count {
        while i < b.count && (b[i] == 32 || b[i] == 9 || b[i] == 10 || b[i] == 13 || b[i] == 12) { i += 1 }
        let start = i
        while i < b.count && !(b[i] == 32 || b[i] == 9 || b[i] == 10 || b[i] == 13 || b[i] == 12) { i += 1 }
        if i > start { out.append(stringOf(b, start, i)) }
    }
    return out
}
