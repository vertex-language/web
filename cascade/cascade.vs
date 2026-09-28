package cascade

import (
    "math"
    "image/draw"
    "web/css"
    "web/css/selector"
    "web/html"
)

/// One selector of one rule, with what the cascade sorts by.
/// One test of a rule that asks about hover, focus or the press.
public struct StateEntry {
    let node: html.Node
    let rule: StyleRule
    /// "" for the element, else the pseudo-element the rule is on.
    let pseudo: string
    let matched: bool
}

final class StyleRule {
    let Selector: selector.ComplexSelector
    /// Specificity packed as ids, classes, tags, high to low.
    let Specificity: int32
    /// Where the rule stands in its origin's sheets: later wins ties.
    let Order: int32
    let Declarations: [css.Longhand]
    /// Custom properties the rule declares.
    let Customs: [CustomDecl]
    /// Declarations using var(), parsed per element once substituted.
    let Pending: [css.Declaration]
    /// The media query the rule is under, or "" for none.
    let Media: [string]
    /// The cascade layer's rank: later layers beat earlier ones, and
    /// rules in no layer beat every layer (Unlayered).
    var enabled: bool = true
    /// Whether the selector asks about hover, focus or the press: its
    /// match can change without the tree changing.
    var usesState: bool = false

    let Layer: int32

    init(selector sel: selector.ComplexSelector, order: int32, declarations: SplitDecls, media: [string], layer: int32) {
        Selector = sel
        let sp = sel.Specificity()
        Specificity = int32(sp.0) * 65536 + int32(sp.1) * 256 + int32(sp.2)
        Order = order
        Declarations = declarations.longhands
        Customs = declarations.customs
        Pending = declarations.pending
        Media = media
        Layer = layer
    }
}

/// The rules of one origin, bucketed by what their rightmost compound
/// asks for, so that an element is tested against the rules that could
/// match it and not against every rule on the page.
public final class RuleSet {
    /// The rules on elements, by what their rightmost compound asks for.
    let main = Buckets()
    var all: [StyleRule] = []
    /// Rules on ::before and ::after, kept apart and bucketed the same
    /// way: they match an element's generated content, not the element.
    let before = Buckets()
    let after = Buckets()
    /// Rules on a field's ::placeholder text.
    let placeholder = Buckets()
    var order: int32 = 0
    /// Cascade layers by name ("outer.inner"), ranked in the order they
    /// are first named.
    var layers: [string: int32] = [:]
    var anonymousLayers = 0
    /// What the selectors mention, for turning changes into restyles.
    let features = Features()
    /// Whether any rule asks about pointer or keyboard state, which is
    /// what makes hovering or focusing worth a style recalculation.
    public var UsesHover: bool = false
    public var UsesFocus: bool = false
    public var UsesActive: bool = false
    public var UsesVisited: bool = false
    /// Whether any rule depends on the viewport: a media query, or a
    /// length in vw or vh, which a resize has to recompute.
    public var UsesViewport: bool = false
    /// Whether any rule declares a custom property or uses var().
    public var UsesCustomProperties: bool = false
    /// The URLs of background images the rules name, for loading.
    public var ImageURLs: [string] = []
    var mediaWidth: float32 = -1
    var mediaHeight: float32 = -1

    public init() {}

    public var IsEmpty: bool { return all.isEmpty }

    /// Adds a stylesheet's rules, including those under @media.
    /// Adds a stylesheet's rules. `media` is a query the whole sheet is
    /// under, as a <link media> or <style media> puts it.
    public func Add(_ sheet: css.StyleSheet, media: string = "") {
        let m: [string] = media.isEmpty ? [] : [css.lower(media)]
        for rule in sheet.Rules {
            add(rule, media: m, layer: Unlayered)
        }
        addAtRules(sheet.AtRules, media: m, layer: "")
    }

    /// The rules of at-rules, as deep as they nest: @media's under its
    /// query (with those around it), @supports' where its condition
    /// holds, and @layer's in their layer. @container, @keyframes and
    /// the rest aren't read yet.
    func addAtRules(_ ats: [css.AtRule], media: [string], layer: string) {
        for at in ats {
            switch at.Name {
            case "media":
                let m = media + [css.lower(at.Params)]
                let rank = layer.isEmpty ? Unlayered : layerRank(layer)
                for rule in at.Rules { add(rule, media: m, layer: rank) }
                addAtRules(at.AtRules, media: m, layer: layer)
            case "supports":
                if !SupportsCondition(at.Params) { continue }
                let rank = layer.isEmpty ? Unlayered : layerRank(layer)
                for rule in at.Rules { add(rule, media: media, layer: rank) }
                addAtRules(at.AtRules, media: media, layer: layer)
            case "layer":
                let names = at.Params.split(separator: ",").map { trimSpaces(string($0)) }.filter { !$0.isEmpty }
                if at.Rules.isEmpty && at.AtRules.isEmpty {
                    // `@layer a, b;` sets the order the layers stand in.
                    for n in names { _ = layerRank(layer.isEmpty ? n : layer + "." + n) }
                    continue
                }
                var name = names.first ?? ""
                if name.isEmpty {
                    anonymousLayers += 1
                    name = "\u{1}\(anonymousLayers)"
                }
                let full = layer.isEmpty ? name : layer + "." + name
                let rank = layerRank(full)
                for rule in at.Rules { add(rule, media: media, layer: rank) }
                addAtRules(at.AtRules, media: media, layer: full)
            default:
                continue
            }
        }
    }

    /// A layer's rank, given on first mention: the order layers are
    /// named in is the order they stand in.
    func layerRank(_ name: string) -> int32 {
        if let r = layers[name] { return r }
        let r = int32(layers.count)
        layers[name] = r
        return r
    }

    func add(_ rule: css.Rule, media: [string], layer: int32) {
        let split = SplitDecls(rule.Declarations)
        if split.isEmpty { return }
        let decls = split.longhands
        if !split.customs.isEmpty || !split.pending.isEmpty { UsesCustomProperties = true }
        if !media.isEmpty { UsesViewport = true }
        for d in decls {
            if case .length(_, let unit) = d.Value {
                if unit == .vw || unit == .vh || unit == .vmin || unit == .vmax { UsesViewport = true }
            }
            if case .url(let u) = d.Value { ImageURLs.append(u) }
        }
        features.note(decls)
        for text in rule.Selectors {
            let parsed = selector.ParseSelectors(text)
            for sel in parsed {
                order += 1
                let r = StyleRule(selector: sel, order: order, declarations: split, media: media, layer: layer)
                r.usesState = noteState(sel)
                features.note(sel)
                bucket(r)
            }
        }
    }

    /// Notes which states a selector asks about; whether it asks any.
    func noteState(_ sel: selector.ComplexSelector) -> bool {
        var uses = false
        for c in sel.Compounds {
            for p in c.Part.Pseudos {
                if p.Name == "hover" { UsesHover = true; uses = true }
                if p.Name == "focus" || p.Name == "focus-within" || p.Name == "focus-visible" { UsesFocus = true; uses = true }
                if p.Name == "active" { UsesActive = true; uses = true }
                if p.Name == "visited" { UsesVisited = true }
                for inner in p.Inner { if noteState(inner) { uses = true } }
            }
        }
        return uses
    }

    func bucket(_ r: StyleRule) {
        all.append(r)
        let last = r.Selector.Compounds[r.Selector.Compounds.count - 1].Part
        if let pe = last.PseudoElement {
            if pe == "before" { before.add(r) } else if pe == "after" { after.add(r) } else if pe == "placeholder" { placeholder.add(r) }
            return
        }
        main.add(r)
    }

    /// Re-evaluates every @media rule for a viewport.
    func setViewport(_ width: float32, _ height: float32) {
        if width == mediaWidth && height == mediaHeight { return }
        mediaWidth = width
        mediaHeight = height
        for r in all {
            if !r.Media.isEmpty {
                var on = true
                for q in r.Media where on { on = mediaMatches(q, width: width, height: height) }
                r.enabled = on
            }
        }
    }

    /// The rules that could match an element, by its tag, id, classes
    /// and attributes.
    func candidates(_ node: html.Node, into out: inout [StyleRule]) {
        main.candidates(node, into: &out)
    }
}

/// Rules bucketed by what their rightmost compound asks for -- an id, a
/// class, a tag, an attribute, :root -- so that an element is tested
/// against the rules that could match it and not against every rule on
/// the page. Only what asks for none of these is tested everywhere.
/// A class: a struct in a property is copied whole on every change, and
/// these hold thousands of rules.
final class Buckets {
    var byId: [string: [StyleRule]] = [:]
    var byClass: [string: [StyleRule]] = [:]
    var byTag: [string: [StyleRule]] = [:]
    var byAttribute: [string: [StyleRule]] = [:]
    var root: [StyleRule] = []
    var universal: [StyleRule] = []
    var count = 0

    init() {}

    var isEmpty: bool { return count == 0 }

    func add(_ r: StyleRule) {
        count += 1
        let last = r.Selector.Compounds[r.Selector.Compounds.count - 1].Part
        // Read, append, write back: vsc copies the whole table for a
        // dict[key, default: []].append (vsc_TODO).
        if let id = last.Id {
            var list = byId[id] ?? []
            list.append(r)
            byId[id] = list
        } else if !last.Classes.isEmpty {
            var list = byClass[last.Classes[0]] ?? []
            list.append(r)
            byClass[last.Classes[0]] = list
        } else if let tag = last.Tag, tag != "*" {
            var list = byTag[tag] ?? []
            list.append(r)
            byTag[tag] = list
        } else if !last.Attributes.isEmpty {
            let name = css.lower(last.Attributes[0].Name)
            var list = byAttribute[name] ?? []
            list.append(r)
            byAttribute[name] = list
        } else if last.Pseudos.contains(where: { p in p.Name == "root" }) {
            root.append(r)
        } else {
            universal.append(r)
        }
    }

    func candidates(_ node: html.Node, into out: inout [StyleRule]) {
        for r in universal { if r.enabled { out.append(r) } }
        if node.Parent == nil || node.Parent?.Kind == html.NodeKind.document {
            for r in root { if r.enabled { out.append(r) } }
        }
        if let list = byTag[node.TagName] {
            for r in list { if r.enabled { out.append(r) } }
        }
        if !byId.isEmpty, let id = node.IdAttr(), let list = byId[id] {
            for r in list { if r.enabled { out.append(r) } }
        }
        if !byClass.isEmpty && node.HasAttribute("class") {
            for cls in node.Classes() {
                if let list = byClass[cls] {
                    for r in list { if r.enabled { out.append(r) } }
                }
            }
        }
        if !byAttribute.isEmpty {
            for a in node.Attributes {
                if let list = byAttribute[a.Name] {
                    for r in list { if r.enabled { out.append(r) } }
                }
            }
        }
    }
}

/// Whether a media query holds for a viewport: `screen`, `all`,
/// `(min-width: N)`, `(max-width: N)`, `and`, `not`, and lists.
func mediaMatches(_ query: string, width: float32, height: float32) -> bool {
    for part in splitTop(query, on: 44) {
        if mediaClauseMatches(part, width: width, height: height) { return true }
    }
    return false
}

func mediaClauseMatches(_ clause: string, width: float32, height: float32) -> bool {
    let b = [uint8](clause.utf8)
    var i = 0
    var result = true
    var negate = false
    while i < b.count {
        while i < b.count && (b[i] == 32 || b[i] == 9) { i += 1 }
        if i >= b.count { break }
        if b[i] == 40 { // '('
            var depth = 1
            let start = i + 1
            i += 1
            while i < b.count && depth > 0 {
                if b[i] == 40 { depth += 1 }
                if b[i] == 41 { depth -= 1 }
                i += 1
            }
            let inner = stringOf(b, start, i - 1)
            var ok = mediaFeature(inner, width: width, height: height)
            if negate { ok = !ok; negate = false }
            result = result && ok
            continue
        }
        let start = i
        while i < b.count && b[i] != 32 && b[i] != 40 { i += 1 }
        let word = stringOf(b, start, i)
        switch word {
        case "and", "only": break
        case "not": negate = true
        case "screen", "all": if negate { result = false; negate = false }
        case "print", "speech", "aural", "braille", "tv", "projection", "handheld":
            if negate { negate = false } else { result = false }
        default: break
        }
    }
    return result
}

/// One media feature in parentheses: `min-width: 40em`, the range
/// syntax of Media Queries 4 (`width >= 768px`, `400px <= width < 800px`),
/// or a feature on its own (`hover`). The page is on a screen with a
/// fine pointer that hovers, in light mode, with no forced colors, no
/// script, and motion allowed.
func mediaFeature(_ text: string, width: float32, height: float32) -> bool {
    let t = trimSpaces(text)
    if t.contains("<") || t.contains(">") || (t.contains("=") && !t.contains(":")) {
        return mediaRange(t, width: width, height: height)
    }
    var name = t
    var value = ""
    let b = [uint8](t.utf8)
    var i = 0
    while i < b.count && b[i] != 58 { i += 1 }
    if i < b.count {
        name = trimSpaces(stringOf(b, 0, i))
        value = css.lower(trimSpaces(stringOf(b, i + 1, b.count)))
    }
    name = css.lower(name)
    switch name {
    case "min-width": return mediaLength(value).map { width >= $0 } ?? false
    case "max-width": return mediaLength(value).map { width <= $0 } ?? false
    case "min-height": return mediaLength(value).map { height >= $0 } ?? false
    case "max-height": return mediaLength(value).map { height <= $0 } ?? false
    case "width": return value.isEmpty ? width > 0 : (mediaLength(value).map { width == $0 } ?? false)
    case "height": return value.isEmpty ? height > 0 : (mediaLength(value).map { height == $0 } ?? false)
    case "orientation": return value == (width >= height ? "landscape" : "portrait")
    case "prefers-color-scheme": return value == "light"
    // The engine runs no transitions or animations: motion is reduced,
    // and a page's reduced-motion rules show what its motion would.
    case "prefers-reduced-motion": return value.isEmpty || value == "reduce"
    case "prefers-reduced-transparency", "prefers-reduced-data", "prefers-contrast":
        return value == "no-preference"
    case "hover", "any-hover": return value.isEmpty || value == "hover"
    case "pointer", "any-pointer": return value.isEmpty || value == "fine"
    case "forced-colors", "inverted-colors": return value == "none"
    case "scripting": return value == "none"
    case "display-mode": return value == "browser"
    case "update": return value.isEmpty || value == "fast"
    case "dynamic-range", "video-dynamic-range": return value == "standard"
    case "color-gamut": return value == "srgb"
    case "color", "min-color": return true
    case "monochrome", "grid": return value == "0"
    case "min-resolution", "max-resolution", "resolution", "-webkit-min-device-pixel-ratio", "-webkit-max-device-pixel-ratio", "min--moz-device-pixel-ratio": return true
    default: return false
    }
}

/// The range syntax: `width >= 768px`, `768px <= width`, and the two-
/// sided `400px <= width < 800px`.
func mediaRange(_ text: string, width: float32, height: float32) -> bool {
    // Split into operands and operators.
    var parts: [string] = []
    var ops: [string] = []
    let b = [uint8](text.utf8)
    var start = 0
    var i = 0
    var depth = 0
    while i < b.count {
        let c = b[i]
        if c == 40 { depth += 1 }
        if c == 41 { depth -= 1 }
        if depth == 0 && (c == 60 || c == 62 || c == 61) {
            parts.append(trimSpaces(stringOf(b, start, i)))
            var op = stringOf(b, i, i + 1)
            if i + 1 < b.count && b[i + 1] == 61 && c != 61 {
                op += "="
                i += 1
            }
            ops.append(op)
            start = i + 1
        }
        i += 1
    }
    parts.append(trimSpaces(stringOf(b, start, b.count)))
    if parts.count != ops.count + 1 || ops.isEmpty { return false }
    var k = 0
    while k < ops.count {
        let left = parts[k]
        let right = parts[k + 1]
        guard let l = operand(left, width: width, height: height), let r = operand(right, width: width, height: height) else { return false }
        var ok = false
        switch ops[k] {
        case "<": ok = l < r
        case "<=": ok = l <= r
        case ">": ok = l > r
        case ">=": ok = l >= r
        case "=": ok = l == r
        default: ok = false
        }
        if !ok { return false }
        k += 1
    }
    return true
}

func operand(_ s: string, width: float32, height: float32) -> float32? {
    switch css.lower(s) {
    case "width": return width
    case "height": return height
    case "aspect-ratio": return height > 0 ? width / height : 0
    default: return mediaLength(s)
    }
}

/// A length in a media query, in CSS pixels: px, em and rem (16px, as
/// media queries measure against the initial font size), a bare number,
/// or calc() of those added and subtracted.
func mediaLength(_ text: string) -> float32? {
    let t = trimSpaces(text)
    let b = [uint8](t.utf8)
    if b.isEmpty { return nil }
    if t.hasPrefix("calc(") && t.hasSuffix(")") {
        return calcSum(stringOf(b, 5, b.count - 1))
    }
    var end = 0
    while end < b.count && ((b[end] >= 48 && b[end] <= 57) || b[end] == 46 || b[end] == 45 || b[end] == 43) { end += 1 }
    if end == 0 { return nil }
    let n = css.parseNumber(b, 0, end)
    let unit = css.lower(stringOf(b, end, b.count))
    switch unit {
    case "", "px": return n
    case "em", "rem": return n * 16
    case "vw", "vh", "vmin", "vmax": return nil
    case "pt": return n * 4 / 3
    case "cm": return n * 96 / 2.54
    case "mm": return n * 96 / 25.4
    case "in": return n * 96
    case "ch", "ex": return n * 8
    default: return nil
    }
}

/// `48rem - .02px`: terms added and subtracted, left to right.
func calcSum(_ text: string) -> float32? {
    let b = [uint8](text.utf8)
    var total: float32 = 0
    var sign: float32 = 1
    var i = 0
    while i < b.count {
        while i < b.count && b[i] == 32 { i += 1 }
        if i >= b.count { break }
        if (b[i] == 43 || b[i] == 45) && i + 1 < b.count && b[i + 1] == 32 {
            sign = b[i] == 45 ? -1 : 1
            i += 1
            continue
        }
        let start = i
        while i < b.count && b[i] != 32 { i += 1 }
        guard let v = mediaLength(stringOf(b, start, i)) else { return nil }
        total += sign * v
        sign = 1
    }
    return total
}

/// The layer rank of rules in no layer: above every layer.
let Unlayered: int32 = 1 << 30

/// The candidates sorted by layer, then specificity, then order, so that
/// later, more specific rules apply last and win. (For !important
/// declarations layers should stand in the reverse order; they don't
/// yet.)
func sortRules(_ rules: inout [StyleRule]) {
    var i = 1
    while i < rules.count {
        let r = rules[i]
        var j = i - 1
        while j >= 0 && (rules[j].Layer > r.Layer ||
                         (rules[j].Layer == r.Layer && rules[j].Specificity > r.Specificity) ||
                         (rules[j].Layer == r.Layer && rules[j].Specificity == r.Specificity && rules[j].Order > r.Order)) {
            rules[j + 1] = rules[j]
            j -= 1
        }
        rules[j + 1] = r
        i += 1
    }
}

/// Computes styles: the user agent's rules, the page's, the element's
/// own attribute, in that order, sorted as the cascade sorts them.
public final class StyleResolver {
    public let UA: RuleSet
    public var Author: RuleSet
    public var ViewportWidth: float32 = 800
    public var ViewportHeight: float32 = 600
    public var RootFontSize: float32 = 16
    var inlineByText: [string: SplitDecls] = [:]
    var scratch: [StyleRule] = []
    var matchedScratch: [StyleRule] = []
    var declScratch: [css.Longhand] = []

    public init(ua: RuleSet) {
        UA = ua
        Author = RuleSet()
    }

    /// Every test of a state-dependent rule against an element since the
    /// trace was last cleared, with its outcome. A change of hover, focus
    /// or press can only alter styles where one of these outcomes turns.
    public var StateTrace: [StateEntry] = []

    /// Whether any rule that asks about hover, focus or the press matches
    /// differently under a context than it did when the styles were last
    /// built: the question a pointer move asks before restyling.
    public func StateMatchesChanged(_ context: selector.MatchContext) -> bool {
        for e in StateTrace {
            let m = e.pseudo.isEmpty
                ? selector.MatchComplexIn(e.rule.Selector, e.node, context)
                : selector.MatchComplexIn(e.rule.Selector, e.node, context, pseudoElement: e.pseudo)
            if m != e.matched { return true }
        }
        return false
    }

    /// Whether the page's rules react to the pointer or keyboard.
    public var UsesHover: bool { return Author.UsesHover || UA.UsesHover }
    public var UsesFocus: bool { return Author.UsesFocus || UA.UsesFocus }
    public var UsesActive: bool { return Author.UsesActive || UA.UsesActive }
    public var UsesVisited: bool { return Author.UsesVisited || UA.UsesVisited }

    /// Whether any rule generates content before or after elements.
    public var HasPseudoElements: bool { return !UA.before.isEmpty || !UA.after.isEmpty || !Author.before.isEmpty || !Author.after.isEmpty }


    /// The style of an element's ::before or ::after, or nil where no
    /// rule gives it content.
    public func ResolvePseudo(_ node: html.Node, _ which: string, parent: ComputedStyle, context: selector.MatchContext) -> ComputedStyle? {
        let uaBuckets = which == "before" ? UA.before : (which == "after" ? UA.after : UA.placeholder)
        let authorBuckets = which == "before" ? Author.before : (which == "after" ? Author.after : Author.placeholder)
        if uaBuckets.isEmpty && authorBuckets.isEmpty { return nil }
        var uaList: [StyleRule] = []
        uaBuckets.candidates(node, into: &uaList)
        var authorList: [StyleRule] = []
        authorBuckets.candidates(node, into: &authorList)
        if uaList.isEmpty && authorList.isEmpty { return nil }
        var matched: [StyleRule] = []
        for r in uaList where r.enabled {
            let m = selector.MatchComplexIn(r.Selector, node, context, pseudoElement: which)
            if r.usesState { StateTrace.append(StateEntry(node: node, rule: r, pseudo: which, matched: m)) }
            if m { matched.append(r) }
        }
        for r in authorList where r.enabled {
            let m = selector.MatchComplexIn(r.Selector, node, context, pseudoElement: which)
            if r.usesState { StateTrace.append(StateEntry(node: node, rule: r, pseudo: which, matched: m)) }
            if m { matched.append(r) }
        }
        if matched.isEmpty { return nil }
        sortRules(&matched)
        let style = ComputedStyle(inheriting: parent)
        let ctx = ApplyContext(parent: parent, rootFontSize: RootFontSize, viewportWidth: ViewportWidth, viewportHeight: ViewportHeight)
        var customs: [CustomDecl] = []
        for r in matched {
            for c in r.Customs where !c.important { customs.append(c) }
        }
        for r in matched {
            for c in r.Customs where c.important { customs.append(c) }
        }
        style.customs = customScope(customs, parent: parent.customs)
        let scope = style.customs
        var declarations: [css.Longhand] = []
        for r in matched {
            for d in r.Declarations where !d.Important { declarations.append(d) }
            for p in r.Pending where !p.Important { declarations.append(contentsOf: expand(p, scope)) }
        }
        for r in matched {
            for d in r.Declarations where d.Important { declarations.append(d) }
            for p in r.Pending where p.Important { declarations.append(contentsOf: expand(p, scope)) }
        }
        for d in declarations where d.Prop == .fontSize { apply(d, style, ctx) }
        for d in declarations where d.Prop != .fontSize { apply(d, style, ctx) }
        // ::before and ::after exist only with content; ::placeholder
        // is the field's own.
        if which != "placeholder" && style.Content == nil { return nil }
        finish(style, node: node, root: false)
        return style
    }

    /// The style of an element, given its parent's.
    public func Resolve(_ node: html.Node, parent: ComputedStyle?, context: selector.MatchContext) -> ComputedStyle {
        UA.setViewport(ViewportWidth, ViewportHeight)
        Author.setViewport(ViewportWidth, ViewportHeight)
        let root = parent == nil
        let base = parent ?? defaultStyle
        let style = ComputedStyle(inheriting: base)
        let ctx = ApplyContext(parent: base, rootFontSize: root ? 16 : RootFontSize,
                               viewportWidth: ViewportWidth, viewportHeight: ViewportHeight)

        // Every declaration that applies, in cascade order: UA rules,
        // presentational attributes, author rules, the style attribute,
        // then the !important ones in the same order over again.
        declScratch.removeAll(keepingCapacity: true)
        var declarations = declScratch
        scratch.removeAll(keepingCapacity: true)
        UA.candidates(node, into: &scratch)
        matchedScratch.removeAll(keepingCapacity: true)
        var matched = matchedScratch
        for r in scratch {
            let m = selector.MatchComplexIn(r.Selector, node, context)
            if r.usesState { StateTrace.append(StateEntry(node: node, rule: r, pseudo: "", matched: m)) }
            if m { matched.append(r) }
        }
        sortRules(&matched)
        var uaImportantCount = 0
        for r in matched {
            for d in r.Declarations {
                if !d.Important { declarations.append(d) } else { uaImportantCount += 1 }
            }
        }
        var uaImportant: [StyleRule] = []
        if uaImportantCount > 0 { uaImportant = matched }

        presentationalHints(node, into: &declarations)

        scratch.removeAll(keepingCapacity: true)
        Author.candidates(node, into: &scratch)
        matched.removeAll(keepingCapacity: true)
        for r in scratch {
            let m = selector.MatchComplexIn(r.Selector, node, context)
            if r.usesState { StateTrace.append(StateEntry(node: node, rule: r, pseudo: "", matched: m)) }
            if m { matched.append(r) }
        }
        sortRules(&matched)

        var inline = SplitDecls()
        if let text = node.GetAttribute("style") {
            inline = inlineDeclarations(node, text)
        }

        // Custom properties first, in cascade order: what var() in the
        // element's declarations reads.
        var customs: [CustomDecl] = []
        for r in matched {
            for c in r.Customs where !c.important { customs.append(c) }
        }
        for c in inline.customs where !c.important { customs.append(c) }
        for r in matched {
            for c in r.Customs where c.important { customs.append(c) }
        }
        for c in inline.customs where c.important { customs.append(c) }
        style.customs = customScope(customs, parent: base.customs)
        let scope = style.customs

        for r in matched {
            for d in r.Declarations where !d.Important { declarations.append(d) }
            for p in r.Pending where !p.Important { declarations.append(contentsOf: expand(p, scope)) }
        }
        for d in inline.longhands where !d.Important { declarations.append(d) }
        for p in inline.pending where !p.Important { declarations.append(contentsOf: expand(p, scope)) }
        for r in matched {
            for d in r.Declarations where d.Important { declarations.append(d) }
            for p in r.Pending where p.Important { declarations.append(contentsOf: expand(p, scope)) }
        }
        for d in inline.longhands where d.Important { declarations.append(d) }
        for p in inline.pending where p.Important { declarations.append(contentsOf: expand(p, scope)) }
        for r in uaImportant {
            for d in r.Declarations where d.Important { declarations.append(d) }
        }

        // Font size first, since em lengths in the same element measure
        // against it whatever order the declarations came in.
        for d in declarations where d.Prop == .fontSize {
            apply(d, style, ctx)
        }
        for d in declarations where d.Prop != .fontSize {
            apply(d, style, ctx)
        }

        finish(style, node: node, root: root)
        // The same font as the parent's is the same face.
        if let p = parent, style.FontSize == p.FontSize && style.FontWeight == p.FontWeight && style.FontStyle == p.FontStyle && sameFamilies(style.FontFamilies, p.FontFamilies) {
            style.face = p.face
        }
        if root {
            RootFontSize = style.FontSize
        }
        declScratch = declarations
        matchedScratch = matched
        return style
    }

    /// The style text takes: its parent's, which is what inherits.
    public func ResolveText(parent: ComputedStyle) -> ComputedStyle {
        return parent
    }

    func inlineDeclarations(_ node: html.Node, _ text: string) -> SplitDecls {
        // By text: pages repeat the same style attribute on many elements.
        if let cached = inlineByText[text] {
            return cached
        }
        let decls = SplitDecls(css.ParseDeclarations(text))
        inlineByText[text] = decls
        return decls
    }

    /// What HTML attributes say about presentation, as the standard maps
    /// them to CSS: `hidden`, `width` and `height` on images and cells,
    /// `align`, `bgcolor`, `<font color>`, `<center>`.
    func presentationalHints(_ node: html.Node, into out: inout [css.Longhand]) {
        let tag = node.TagName
        if node.HasAttribute("hidden") {
            out.append(css.Longhand(.display, .keyword("none")))
        }
        if tag == "img" || tag == "video" || tag == "iframe" || tag == "canvas" || tag == "embed" || tag == "object" ||
            tag == "td" || tag == "th" || tag == "table" || tag == "col" || tag == "hr" {
            if let w = node.GetAttribute("width"), let v = dimensionAttribute(w) { out.append(css.Longhand(.width, v)) }
            if let h = node.GetAttribute("height"), let v = dimensionAttribute(h) { out.append(css.Longhand(.height, v)) }
        }
        if let align = node.GetAttribute("align") {
            let a = css.lower(align)
            if tag == "table" || tag == "img" {
                if a == "center" {
                    out.append(css.Longhand(.marginLeft, .auto))
                    out.append(css.Longhand(.marginRight, .auto))
                } else if a == "left" || a == "right" {
                    out.append(css.Longhand(.float, .keyword(a)))
                }
            } else if a == "left" || a == "right" || a == "center" || a == "justify" {
                out.append(css.Longhand(.textAlign, .keyword(a)))
            }
        }
        if let bg = node.GetAttribute("bgcolor"), let c = css.ParseColor(bg) {
            out.append(css.Longhand(.backgroundColor, .color(c)))
        }
        if tag == "font" {
            if let c = node.GetAttribute("color"), let col = css.ParseColor(c) {
                out.append(css.Longhand(.color, .color(col)))
            }
            if let s = node.GetAttribute("size") {
                let sizes: [float32] = [10, 13, 16, 18, 24, 32, 48]
                let b = [uint8](s.utf8)
                var n = int(css.parseNumber(b, 0, b.count))
                if !b.isEmpty && (b[0] == 43 || b[0] == 45) { n = 3 + n }
                if n >= 1 && n <= 7 { out.append(css.Longhand(.fontSize, .length(sizes[n - 1], .px))) }
            }
        }
        if tag == "table" {
            if let border = node.GetAttribute("border"), !border.isEmpty && border != "0" {
                let b = [uint8](border.utf8)
                let w = css.parseNumber(b, 0, b.count)
                for p in tableBorderWidths { out.append(css.Longhand(p, .length(w > 0 ? w : 1, .px))) }
                for p in tableBorderStyles { out.append(css.Longhand(p, .keyword("outset"))) }
            }
            if let spacing = node.GetAttribute("cellspacing") {
                let b = [uint8](spacing.utf8)
                out.append(css.Longhand(.borderSpacing, .length(css.parseNumber(b, 0, b.count), .px)))
            }
        }
        if tag == "input" {
            if let type = node.GetAttribute("type"), css.lower(type) == "hidden" {
                out.append(css.Longhand(.display, .keyword("none")))
            }
        }
        if tag == "ol" {
            if let type = node.GetAttribute("type") {
                switch type {
                case "a": out.append(css.Longhand(.listStyleType, .keyword("lower-alpha")))
                case "A": out.append(css.Longhand(.listStyleType, .keyword("upper-alpha")))
                case "i": out.append(css.Longhand(.listStyleType, .keyword("lower-roman")))
                case "I": out.append(css.Longhand(.listStyleType, .keyword("upper-roman")))
                default: break
                }
            }
        }
    }

    func dimensionAttribute(_ text: string) -> css.Value? {
        let b = [uint8](trimSpaces(text).utf8)
        if b.isEmpty { return nil }
        let n = css.parseNumber(b, 0, b.count)
        if b[b.count - 1] == 37 { return .length(n, .percent) }
        if n <= 0 && b[0] != 48 { return nil }
        return .length(n, .px)
    }

    /// What follows the cascade: borders without a style have no width,
    /// floats and positioned boxes are blocks, the root is a block.
    func finish(_ s: ComputedStyle, node: html.Node, root: bool) {
        if !s.BorderTopStyle.Draws { s.BorderTopWidth = 0 }
        if !s.BorderRightStyle.Draws { s.BorderRightWidth = 0 }
        if !s.BorderBottomStyle.Draws { s.BorderBottomWidth = 0 }
        if !s.BorderLeftStyle.Draws { s.BorderLeftWidth = 0 }
        if s.Display != .none {
            if s.Position == .absolute || s.Position == .fixed || s.Float != .none {
                s.Display = s.Display.Blockified
            }
            if root && s.Display.IsInlineLevel {
                s.Display = s.Display.Blockified
            }
        }
        if s.Position == .absolute || s.Position == .fixed {
            s.Float = .none
        }
        if s.OverflowX == .visible && s.OverflowY != .visible { s.OverflowX = .auto }
        if s.OverflowY == .visible && s.OverflowX != .visible { s.OverflowY = .auto }
    }
}

let defaultStyle = ComputedStyle()

/// What a declaration is applied against: the parent's style for
/// inheritance, the root font size for rem, the viewport for vw and vh.
struct ApplyContext {
    let parent: ComputedStyle
    let rootFontSize: float32
    let viewportWidth: float32
    let viewportHeight: float32
}

// MARK: - Applying declarations

func apply(_ d: css.Longhand, _ s: ComputedStyle, _ ctx: ApplyContext) {
    switch d.Value {
    case .inherit:
        copyProperty(d.Prop, from: ctx.parent, to: s)
        return
    case .initial:
        copyProperty(d.Prop, from: defaultStyle, to: s)
        return
    default:
        break
    }
    let v = d.Value
    switch d.Prop {
    case .display:
        if let k = keywordOf(v) { s.Display = displayOf(k) }
    case .position:
        if let k = keywordOf(v) {
            switch k {
            case "relative": s.Position = .relative
            case "absolute": s.Position = .absolute
            case "fixed": s.Position = .fixed
            case "sticky": s.Position = .sticky
            default: s.Position = .static
            }
        }
    case .float:
        if let k = keywordOf(v) {
            if k == "left" || k == "inline-start" { s.Float = .left }
            else if k == "right" || k == "inline-end" { s.Float = .right }
            else { s.Float = .none }
        }
    case .clear:
        if let k = keywordOf(v) {
            switch k {
            case "left", "inline-start": s.Clear = .left
            case "right", "inline-end": s.Clear = .right
            case "both": s.Clear = .both
            default: s.Clear = .none
            }
        }
    case .top: if let l = length(v, s, ctx) { s.Top = l }
    case .right: if let l = length(v, s, ctx) { s.Right = l }
    case .bottom: if let l = length(v, s, ctx) { s.Bottom = l }
    case .left: if let l = length(v, s, ctx) { s.Left = l }
    case .zIndex:
        if case .number(let n) = v { s.ZIndex = int32(n); s.HasZIndex = true }
        else { s.HasZIndex = false; s.ZIndex = 0 }
    case .width: if let l = length(v, s, ctx) { s.Width = l }
    case .height: if let l = length(v, s, ctx) { s.Height = l }
    case .minWidth: if let l = length(v, s, ctx) { s.MinWidth = l == .auto ? .px(0) : l }
    case .minHeight: if let l = length(v, s, ctx) { s.MinHeight = l == .auto ? .px(0) : l }
    case .maxWidth: if let l = length(v, s, ctx) { s.MaxWidth = l }
    case .maxHeight: if let l = length(v, s, ctx) { s.MaxHeight = l }
    case .boxSizing:
        if let k = keywordOf(v) { s.BoxSizing = k == "border-box" ? .borderBox : .contentBox }
    case .marginTop: if let l = length(v, s, ctx) { s.MarginTop = l }
    case .marginRight: if let l = length(v, s, ctx) { s.MarginRight = l }
    case .marginBottom: if let l = length(v, s, ctx) { s.MarginBottom = l }
    case .marginLeft: if let l = length(v, s, ctx) { s.MarginLeft = l }
    case .paddingTop: if let l = length(v, s, ctx) { s.PaddingTop = nonNegative(l) }
    case .paddingRight: if let l = length(v, s, ctx) { s.PaddingRight = nonNegative(l) }
    case .paddingBottom: if let l = length(v, s, ctx) { s.PaddingBottom = nonNegative(l) }
    case .paddingLeft: if let l = length(v, s, ctx) { s.PaddingLeft = nonNegative(l) }
    case .borderTopWidth: if let p = pixels(v, s, ctx) { s.BorderTopWidth = p }
    case .borderRightWidth: if let p = pixels(v, s, ctx) { s.BorderRightWidth = p }
    case .borderBottomWidth: if let p = pixels(v, s, ctx) { s.BorderBottomWidth = p }
    case .borderLeftWidth: if let p = pixels(v, s, ctx) { s.BorderLeftWidth = p }
    case .borderTopStyle: if let k = keywordOf(v) { s.BorderTopStyle = borderStyleOf(k) }
    case .borderRightStyle: if let k = keywordOf(v) { s.BorderRightStyle = borderStyleOf(k) }
    case .borderBottomStyle: if let k = keywordOf(v) { s.BorderBottomStyle = borderStyleOf(k) }
    case .borderLeftStyle: if let k = keywordOf(v) { s.BorderLeftStyle = borderStyleOf(k) }
    case .borderTopColor: s.BorderTopColor = colorOf(v)
    case .borderRightColor: s.BorderRightColor = colorOf(v)
    case .borderBottomColor: s.BorderBottomColor = colorOf(v)
    case .borderLeftColor: s.BorderLeftColor = colorOf(v)
    case .borderTopLeftRadius:
        if case .length(let n, .percent) = v { s.BorderRadiusPercent.TopLeft = n; s.BorderRadius.TopLeft = 0 }
        else if let p = pixels(v, s, ctx) { s.BorderRadius.TopLeft = p; s.BorderRadiusPercent.TopLeft = 0 }
    case .borderTopRightRadius:
        if case .length(let n, .percent) = v { s.BorderRadiusPercent.TopRight = n; s.BorderRadius.TopRight = 0 }
        else if let p = pixels(v, s, ctx) { s.BorderRadius.TopRight = p; s.BorderRadiusPercent.TopRight = 0 }
    case .borderBottomRightRadius:
        if case .length(let n, .percent) = v { s.BorderRadiusPercent.BottomRight = n; s.BorderRadius.BottomRight = 0 }
        else if let p = pixels(v, s, ctx) { s.BorderRadius.BottomRight = p; s.BorderRadiusPercent.BottomRight = 0 }
    case .borderBottomLeftRadius:
        if case .length(let n, .percent) = v { s.BorderRadiusPercent.BottomLeft = n; s.BorderRadius.BottomLeft = 0 }
        else if let p = pixels(v, s, ctx) { s.BorderRadius.BottomLeft = p; s.BorderRadiusPercent.BottomLeft = 0 }
    case .backgroundColor:
        if case .currentColor = v { s.BackgroundColor = s.Color }
        else if let c = colorOf(v) { s.BackgroundColor = c }
    case .backgroundImage:
        var layer: BackgroundImage? = nil
        if case .url(let u) = v { layer = BackgroundImage(url: u) }
        if case .gradient(let g) = v { layer = BackgroundImage(gradient: g) }
        if let old = s.BackgroundImage, var made = layer {
            made.RepeatX = old.RepeatX
            made.RepeatY = old.RepeatY
            made.Size = old.Size
            made.PositionX = old.PositionX
            made.PositionY = old.PositionY
            made.OffsetX = old.OffsetX
            made.OffsetY = old.OffsetY
            layer = made
        }
        s.BackgroundImage = layer
    case .backgroundRepeat:
        if let k = keywordOf(v) {
            var layer = s.BackgroundImage ?? BackgroundImage(url: "")
            layer.RepeatX = k == "repeat" || k == "repeat-x" || k == "space" || k == "round"
            layer.RepeatY = k == "repeat" || k == "repeat-y" || k == "space" || k == "round"
            s.BackgroundImage = layer
        }
    case .backgroundSize:
        if let k = keywordOf(v) {
            var layer = s.BackgroundImage ?? BackgroundImage(url: "")
            if k == "cover" { layer.Size = .cover }
            else if k == "contain" { layer.Size = .contain }
            else if k == "auto" { layer.Size = .auto }
            else {
                let parts = words(k)
                let w = lengthFromWord(parts[0], s, ctx)
                let h = parts.count > 1 ? lengthFromWord(parts[1], s, ctx) : css.Length.auto
                layer.Size = .length(w, h)
            }
            s.BackgroundImage = layer
        }
    case .backgroundPosition:
        if let k = keywordOf(v) {
            var layer = s.BackgroundImage ?? BackgroundImage(url: "")
            let p = backgroundPosition(words(k), s)
            layer.PositionX = p.fx
            layer.OffsetX = p.ox
            layer.PositionY = p.fy
            layer.OffsetY = p.oy
            s.BackgroundImage = layer
        }
    case .opacity:
        if case .number(let n) = v { s.Opacity = n < 0 ? 0 : (n > 1 ? 1 : n) }
    case .filter:
        if case .none = v { s.FilterBlur = 0 } else if let r = pixels(v, s, ctx), r > 0 { s.FilterBlur = r } else { s.FilterBlur = 0 }
    case .overflowX: if let k = keywordOf(v) { s.OverflowX = overflowOf(k) }
    case .overflowY: if let k = keywordOf(v) { s.OverflowY = overflowOf(k) }
    case .boxShadow:
        if case .shadows(let list) = v {
            var out: [Shadow] = []
            for sh in list {
                out.append(Shadow(x: pixels(sh.X, s, ctx) ?? 0, y: pixels(sh.Y, s, ctx) ?? 0,
                                  blur: pixels(sh.Blur, s, ctx) ?? 0, spread: pixels(sh.Spread, s, ctx) ?? 0,
                                  color: sh.Color ?? s.Color, inset: sh.Inset))
            }
            s.Shadows = out
        } else {
            s.Shadows = []
        }
    case .outlineWidth: if let p = pixels(v, s, ctx) { s.OutlineWidth = p }
    case .outlineColor: s.OutlineColor = colorOf(v)
    case .fill:
        s.FillNone = false
        s.FillCurrent = false
        if case .none = v {
            s.FillNone = true
        } else if case .currentColor = v {
            s.FillCurrent = true
        } else if let c = colorOf(v) {
            s.Fill = c
        }
    case .verticalAlign:
        if let k = keywordOf(v) {
            switch k {
            case "middle": s.VerticalAlign = .middle
            case "top": s.VerticalAlign = .top
            case "bottom": s.VerticalAlign = .bottom
            case "text-top": s.VerticalAlign = .textTop
            case "text-bottom": s.VerticalAlign = .textBottom
            case "sub": s.VerticalAlign = .sub
            case "super": s.VerticalAlign = .super
            default: s.VerticalAlign = .baseline
            }
        } else if let l = length(v, s, ctx) {
            s.VerticalAlign = .length(l)
        }
    case .textDecorationLine:
        if let k = keywordOf(v) {
            var td = TextDecoration()
            for word in words(k) {
                if word == "underline" { td.Underline = true }
                if word == "overline" { td.Overline = true }
                if word == "line-through" { td.LineThrough = true }
            }
            s.TextDecoration = td
        }
    case .textDecorationColor: s.TextDecorationColor = colorOf(v)
    case .flexDirection:
        if let k = keywordOf(v) {
            switch k {
            case "row-reverse": s.FlexDirection = .rowReverse
            case "column": s.FlexDirection = .column
            case "column-reverse": s.FlexDirection = .columnReverse
            default: s.FlexDirection = .row
            }
        }
    case .flexWrap:
        if let k = keywordOf(v) {
            s.FlexWrap = k == "wrap" ? .wrap : (k == "wrap-reverse" ? .wrapReverse : .nowrap)
        }
    case .justifyContent: if let k = keywordOf(v) { s.JustifyContent = justifyOf(k) }
    case .alignContent: if let k = keywordOf(v) { s.AlignContent = justifyOf(k) }
    case .alignItems: if let k = keywordOf(v) { s.AlignItems = alignOf(k) }
    case .alignSelf: if let k = keywordOf(v) { s.AlignSelf = alignOf(k) }
    case .flexGrow: if case .number(let n) = v { s.FlexGrow = n < 0 ? 0 : n }
    case .flexShrink: if case .number(let n) = v { s.FlexShrink = n < 0 ? 0 : n }
    case .flexBasis: if let l = length(v, s, ctx) { s.FlexBasis = l }
    case .order: if case .number(let n) = v { s.Order = int32(n) } else { s.Order = 0 }
    case .rowGap: if let l = length(v, s, ctx) { s.RowGap = l }
    case .columnGap: if let l = length(v, s, ctx) { s.ColumnGap = l }
    case .tableLayout: if let k = keywordOf(v) { s.TableLayout = k == "fixed" ? .fixed : .auto }
    case .gridTemplateColumns:
        if case .tracks(let t) = v { s.GridColumns = resolveTracks(t, s, ctx) } else { s.GridColumns = [] }
    case .gridTemplateRows:
        if case .tracks(let t) = v { s.GridRows = resolveTracks(t, s, ctx) } else { s.GridRows = [] }
    case .gridAutoRows:
        if case .tracks(let t) = v, !t.isEmpty { s.GridAutoRows = resolveTracks(t, s, ctx)[0] }
    case .gridAutoColumns:
        if case .tracks(let t) = v, !t.isEmpty { s.GridAutoColumns = resolveTracks(t, s, ctx)[0] }
    case .gridAutoFlow:
        if let k = keywordOf(v) { s.GridAutoFlowColumn = k == "column" }
    case .aspectRatio:
        if case .number(let r) = v, r > 0 { s.AspectRatio = r } else { s.AspectRatio = 0 }
    case .gridColumn:
        if case .placement(let p) = v { s.GridColumn = p }
    case .gridRow:
        if case .placement(let p) = v { s.GridRow = p }
    case .gridColumnStart, .gridColumnEnd, .gridRowStart, .gridRowEnd:
        // One side of grid-column or grid-row, merged into it.
        if case .placement(let side) = v {
            var p = (d.Prop == .gridColumnStart || d.Prop == .gridColumnEnd) ? s.GridColumn : s.GridRow
            if d.Prop == .gridColumnStart || d.Prop == .gridRowStart {
                p.Start = side.Start
                if side.Span > 0 { p.Span = side.Span }
            } else {
                p.End = side.End
                if side.Span > 0 { p.Span = side.Span }
            }
            if d.Prop == .gridColumnStart || d.Prop == .gridColumnEnd { s.GridColumn = p } else { s.GridRow = p }
        }
    case .color:
        if case .currentColor = v { s.Color = ctx.parent.Color }
        else if let c = colorOf(v) { s.Color = c }
    case .fontFamily:
        if case .families(let list) = v { s.FontFamilies = list }
    case .fontSize:
        // em here is the parent's size: an element's own is what is
        // being decided.
        if case .length(let n, let unit) = v {
            switch unit {
            case .px: s.FontSize = n
            case .em: s.FontSize = ctx.parent.FontSize * n
            case .percent: s.FontSize = ctx.parent.FontSize * n / 100
            case .rem: s.FontSize = ctx.rootFontSize * n
            case .ex, .ch: s.FontSize = ctx.parent.FontSize * n * 0.5
            case .vw: s.FontSize = ctx.viewportWidth * n / 100
            case .vh: s.FontSize = ctx.viewportHeight * n / 100
            case .vmin: s.FontSize = math.Min(ctx.viewportWidth, ctx.viewportHeight) * n / 100
            case .vmax: s.FontSize = math.Max(ctx.viewportWidth, ctx.viewportHeight) * n / 100
            }
            if s.FontSize < 0 { s.FontSize = 0 }
        }
    case .fontWeight:
        if case .number(let n) = v {
            s.FontWeight = int32(n)
        } else if let k = keywordOf(v) {
            switch k {
            case "bold": s.FontWeight = 700
            case "bolder": s.FontWeight = ctx.parent.FontWeight < 400 ? 400 : (ctx.parent.FontWeight < 600 ? 700 : 900)
            case "lighter": s.FontWeight = ctx.parent.FontWeight < 600 ? 100 : (ctx.parent.FontWeight < 800 ? 400 : 700)
            default: s.FontWeight = 400
            }
        }
    case .fontStyle:
        if let k = keywordOf(v) { s.FontStyle = k == "italic" ? .italic : (k == "oblique" ? .oblique : .normal) }
    case .lineHeight:
        switch v {
        case .normal: s.LineHeight = .normal
        case .number(let n): s.LineHeight = .number(n)
        default:
            if let p = pixels(v, s, ctx) { s.LineHeight = .px(p) }
        }
    case .textAlign:
        if let k = keywordOf(v) {
            switch k {
            case "left": s.TextAlign = .left
            case "right": s.TextAlign = .right
            case "center": s.TextAlign = .center
            case "justify": s.TextAlign = .justify
            case "end": s.TextAlign = .end
            default: s.TextAlign = .start
            }
        }
    case .textTransform:
        if let k = keywordOf(v) {
            switch k {
            case "uppercase": s.TextTransform = .uppercase
            case "lowercase": s.TextTransform = .lowercase
            case "capitalize": s.TextTransform = .capitalize
            default: s.TextTransform = .none
            }
        }
    case .textIndent: if let l = length(v, s, ctx) { s.TextIndent = l }
    case .letterSpacing:
        if case .normal = v { s.LetterSpacing = 0 } else if let p = pixels(v, s, ctx) { s.LetterSpacing = p }
    case .wordSpacing:
        if case .normal = v { s.WordSpacing = 0 } else if let p = pixels(v, s, ctx) { s.WordSpacing = p }
    case .whiteSpace:
        if let k = keywordOf(v) {
            switch k {
            case "nowrap": s.WhiteSpace = .nowrap
            case "pre": s.WhiteSpace = .pre
            case "pre-wrap": s.WhiteSpace = .preWrap
            case "pre-line": s.WhiteSpace = .preLine
            default: s.WhiteSpace = .normal
            }
        }
    case .overflowWrap:
        if let k = keywordOf(v) { s.OverflowWrap = k == "break-word" ? .breakWord : (k == "anywhere" ? .anywhere : .normal) }
    case .wordBreak:
        if let k = keywordOf(v) {
            s.WordBreak = k == "break-all" ? .breakAll : (k == "keep-all" ? .keepAll : .normal)
            if k == "break-word" { s.OverflowWrap = .breakWord }
        }
    case .textOverflow:
        if let k = keywordOf(v) { s.TextOverflow = k == "ellipsis" ? .ellipsis : .clip }
    case .listStyleType:
        if let k = keywordOf(v) {
            switch k {
            case "none": s.ListStyleType = .none
            case "circle": s.ListStyleType = .circle
            case "square": s.ListStyleType = .square
            case "decimal": s.ListStyleType = .decimal
            case "decimal-leading-zero": s.ListStyleType = .decimalLeadingZero
            case "lower-alpha", "lower-latin": s.ListStyleType = .lowerAlpha
            case "upper-alpha", "upper-latin": s.ListStyleType = .upperAlpha
            case "lower-roman": s.ListStyleType = .lowerRoman
            case "upper-roman": s.ListStyleType = .upperRoman
            default: s.ListStyleType = .disc
            }
        }
    case .listStylePosition:
        if let k = keywordOf(v) { s.ListStylePosition = k == "inside" ? .inside : .outside }
    case .cursor:
        if let k = keywordOf(v) {
            switch k {
            case "default": s.Cursor = .default
            case "pointer": s.Cursor = .pointer
            case "text": s.Cursor = .text
            case "crosshair": s.Cursor = .crosshair
            case "move", "grab", "grabbing": s.Cursor = k == "move" ? .move : .grab
            case "not-allowed": s.Cursor = .notAllowed
            case "ew-resize", "col-resize": s.Cursor = .ewResize
            case "ns-resize", "row-resize": s.Cursor = .nsResize
            case "wait", "progress": s.Cursor = .wait
            case "help": s.Cursor = .help
            case "none": s.Cursor = .none
            default: s.Cursor = .auto
            }
        }
    case .visibility:
        if let k = keywordOf(v) { s.Visibility = k == "hidden" ? .hidden : (k == "collapse" ? .collapse : .visible) }
    case .borderCollapse:
        if let k = keywordOf(v) { s.BorderCollapse = k == "collapse" ? .collapse : .separate }
    case .borderSpacing: if let p = pixels(v, s, ctx) { s.BorderSpacing = p }
    case .tabSize: if case .number(let n) = v { s.TabSize = int32(n) }
    case .content:
        if case .families(let parts) = v { s.Content = parts } else { s.Content = nil }
    }
}

func keywordOf(_ v: css.Value) -> string? {
    switch v {
    case .keyword(let k): return k
    case .auto: return "auto"
    case .none: return "none"
    case .normal: return "normal"
    default: return nil
    }
}

func colorOf(_ v: css.Value) -> draw.Color? {
    if case .color(let c) = v { return c }
    return nil
}

func words(_ s: string) -> [string] {
    var out: [string] = []
    let b = [uint8](s.utf8)
    var i = 0
    while i < b.count {
        while i < b.count && b[i] == 32 { i += 1 }
        let start = i
        while i < b.count && b[i] != 32 { i += 1 }
        if i > start { out.append(stringOf(b, start, i)) }
    }
    return out
}

/// A length value resolved as far as the element allows: em, rem and
/// the viewport units to pixels; percentages left for layout.
func length(_ v: css.Value, _ s: ComputedStyle, _ ctx: ApplyContext) -> css.Length? {
    switch v {
    case .auto: return .auto
    case .none: return .none
    case .keyword(let k):
        switch k {
        case "min-content": return .minContent
        case "max-content": return .maxContent
        case "fit-content": return .fitContent
        default: return nil
        }
    case .length(let n, let unit):
        switch unit {
        case .px: return .px(n)
        case .percent: return .percent(n)
        case .em: return .px(n * s.FontSize)
        case .rem: return .px(n * ctx.rootFontSize)
        case .ex: return .px(n * s.FontSize * 0.5)
        case .ch: return .px(n * s.FontSize * 0.5)
        case .vw: return .px(n * ctx.viewportWidth / 100)
        case .vh: return .px(n * ctx.viewportHeight / 100)
        case .vmin: return .px(n * math.Min(ctx.viewportWidth, ctx.viewportHeight) / 100)
        case .vmax: return .px(n * math.Max(ctx.viewportWidth, ctx.viewportHeight) / 100)
        }
    case .number(let n):
        return n == 0 ? .px(0) : nil
    case .calc(let terms):
        var px: float32 = 0
        var percent: float32 = 0
        for t in terms {
            guard let unit = t.Unit else { px += t.Number; continue }
            if unit == .percent {
                percent += t.Number
            } else if let l = length(.length(t.Number, unit), s, ctx), case .px(let v) = l {
                px += v
            }
        }
        if percent == 0 { return .px(px) }
        if px == 0 { return .percent(percent) }
        return .calc(px, percent)
    default:
        return nil
    }
}

/// A length that must be pixels: borders, radii, spacing.
func pixels(_ v: css.Value, _ s: ComputedStyle, _ ctx: ApplyContext) -> float32? {
    guard let l = length(v, s, ctx) else { return nil }
    switch l {
    case .px(let p): return p
    case .percent(let p): return p * s.FontSize / 100
    case .calc(let p, _): return p
    default: return nil
    }
}

/// A background position's words -- keywords, percentages, lengths, and
/// `right 10px`-style edge offsets -- as each axis's fraction of the free
/// space and offset in pixels. One value is x unless it's top or bottom;
/// what's left out is centered.
func backgroundPosition(_ w: [string], _ s: ComputedStyle) -> (fx: float32, ox: float32, fy: float32, oy: float32) {
    // Each item: which axis a keyword ties it to (0 either, 1 x, 2 y),
    // its fraction and its offset.
    var items: [(axis: int, f: float32, o: float32)] = []
    var i = 0
    while i < w.count {
        let word = w[i]
        var item: (axis: int, f: float32, o: float32)
        switch word {
        case "left": item = (axis: 1, f: 0, o: 0)
        case "right": item = (axis: 1, f: 1, o: 0)
        case "top": item = (axis: 2, f: 0, o: 0)
        case "bottom": item = (axis: 2, f: 1, o: 0)
        case "center": item = (axis: 0, f: 0.5, o: 0)
        default:
            item = (axis: 0, f: 0, o: 0)
            let b = [uint8](word.utf8)
            if !b.isEmpty && b[b.count - 1] == 37 {
                item.f = css.parseNumber(b, 0, b.count - 1) / 100
            } else {
                item.o = positionLength(word, s)
            }
        }
        // An edge keyword and the length after it: an offset from that edge.
        if item.axis != 0 && i + 1 < w.count && isPositionAmount(w[i + 1]) {
            let next = [uint8](w[i + 1].utf8)
            let fromFar = item.f == 1
            if next[next.count - 1] == 37 {
                let pct = css.parseNumber(next, 0, next.count - 1) / 100
                item.f = fromFar ? 1 - pct : pct
            } else {
                let len = positionLength(w[i + 1], s)
                item.o = fromFar ? -len : len
            }
            i += 1
        }
        items.append(item)
        i += 1
    }
    var x: (f: float32, o: float32)? = nil
    var y: (f: float32, o: float32)? = nil
    for it in items where it.axis == 1 && x == nil { x = (f: it.f, o: it.o) }
    for it in items where it.axis == 2 && y == nil { y = (f: it.f, o: it.o) }
    for it in items where it.axis == 0 {
        if x == nil { x = (f: it.f, o: it.o) } else if y == nil { y = (f: it.f, o: it.o) }
    }
    let rx = x ?? (f: 0.5, o: 0)
    let ry = y ?? (f: 0.5, o: 0)
    return (fx: rx.f, ox: rx.o, fy: ry.f, oy: ry.o)
}

func isPositionAmount(_ word: string) -> bool {
    guard let c = word.utf8.first else { return false }
    return (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46
}

/// A length in a position: px, em, rem; 0 for what isn't one.
func positionLength(_ word: string, _ s: ComputedStyle) -> float32 {
    let b = [uint8](word.utf8)
    var end = 0
    while end < b.count && ((b[end] >= 48 && b[end] <= 57) || b[end] == 45 || b[end] == 43 || b[end] == 46) { end += 1 }
    if end == 0 { return 0 }
    let n = css.parseNumber(b, 0, end)
    switch css.lower(css.stringOf(b, end, b.count)) {
    case "", "px": return n
    case "em": return n * s.FontSize
    case "rem": return n * 16
    default: return n
    }
}

func nonNegative(_ l: css.Length) -> css.Length {
    switch l {
    case .px(let v): return v < 0 ? .px(0) : l
    case .percent(let p): return p < 0 ? .percent(0) : l
    default: return l
    }
}

func displayOf(_ k: string) -> Display {
    switch k {
    case "none": return .none
    case "block", "flow-root": return .block
    case "inline-block": return .inlineBlock
    case "flex": return .flex
    case "inline-flex": return .inlineFlex
    case "grid": return .grid
    case "inline-grid": return .inlineGrid
    case "list-item": return .listItem
    case "table": return .table
    case "inline-table": return .inlineTable
    case "table-row": return .tableRow
    case "table-cell": return .tableCell
    case "table-row-group": return .tableRowGroup
    case "table-header-group": return .tableHeaderGroup
    case "table-footer-group": return .tableFooterGroup
    case "table-caption": return .tableCaption
    case "table-column": return .tableColumn
    case "table-column-group": return .tableColumnGroup
    case "contents": return .contents
    default: return .inline
    }
}

func borderStyleOf(_ k: string) -> BorderStyle {
    switch k {
    case "hidden": return .hidden
    case "solid": return .solid
    case "dashed": return .dashed
    case "dotted": return .dotted
    case "double": return .double
    case "groove": return .groove
    case "ridge": return .ridge
    case "inset": return .inset
    case "outset": return .outset
    default: return .none
    }
}

func overflowOf(_ k: string) -> Overflow {
    switch k {
    case "hidden": return .hidden
    case "scroll": return .scroll
    case "auto": return .auto
    case "clip": return .clip
    default: return .visible
    }
}

func justifyOf(_ k: string) -> JustifyContent {
    switch k {
    case "flex-end", "end", "right": return .flexEnd
    case "center": return .center
    case "space-between": return .spaceBetween
    case "space-around": return .spaceAround
    case "space-evenly": return .spaceEvenly
    default: return .flexStart
    }
}

func alignOf(_ k: string) -> AlignItems {
    switch k {
    case "flex-start", "start", "self-start": return .flexStart
    case "flex-end", "end", "self-end": return .flexEnd
    case "center": return .center
    case "baseline": return .baseline
    case "auto": return .auto
    default: return .stretch
    }
}

/// Copies one property from one style to another: what `inherit` and
/// `initial` do.
func copyProperty(_ p: css.Prop, from a: ComputedStyle, to b: ComputedStyle) {
    switch p {
    case .display: b.Display = a.Display
    case .position: b.Position = a.Position
    case .float: b.Float = a.Float
    case .clear: b.Clear = a.Clear
    case .top: b.Top = a.Top
    case .right: b.Right = a.Right
    case .bottom: b.Bottom = a.Bottom
    case .left: b.Left = a.Left
    case .zIndex: b.ZIndex = a.ZIndex; b.HasZIndex = a.HasZIndex
    case .width: b.Width = a.Width
    case .height: b.Height = a.Height
    case .minWidth: b.MinWidth = a.MinWidth
    case .minHeight: b.MinHeight = a.MinHeight
    case .maxWidth: b.MaxWidth = a.MaxWidth
    case .maxHeight: b.MaxHeight = a.MaxHeight
    case .boxSizing: b.BoxSizing = a.BoxSizing
    case .marginTop: b.MarginTop = a.MarginTop
    case .marginRight: b.MarginRight = a.MarginRight
    case .marginBottom: b.MarginBottom = a.MarginBottom
    case .marginLeft: b.MarginLeft = a.MarginLeft
    case .paddingTop: b.PaddingTop = a.PaddingTop
    case .paddingRight: b.PaddingRight = a.PaddingRight
    case .paddingBottom: b.PaddingBottom = a.PaddingBottom
    case .paddingLeft: b.PaddingLeft = a.PaddingLeft
    case .borderTopWidth: b.BorderTopWidth = a.BorderTopWidth
    case .borderRightWidth: b.BorderRightWidth = a.BorderRightWidth
    case .borderBottomWidth: b.BorderBottomWidth = a.BorderBottomWidth
    case .borderLeftWidth: b.BorderLeftWidth = a.BorderLeftWidth
    case .borderTopStyle: b.BorderTopStyle = a.BorderTopStyle
    case .borderRightStyle: b.BorderRightStyle = a.BorderRightStyle
    case .borderBottomStyle: b.BorderBottomStyle = a.BorderBottomStyle
    case .borderLeftStyle: b.BorderLeftStyle = a.BorderLeftStyle
    case .borderTopColor: b.BorderTopColor = a.BorderTopColor
    case .borderRightColor: b.BorderRightColor = a.BorderRightColor
    case .borderBottomColor: b.BorderBottomColor = a.BorderBottomColor
    case .borderLeftColor: b.BorderLeftColor = a.BorderLeftColor
    case .borderTopLeftRadius: b.BorderRadius.TopLeft = a.BorderRadius.TopLeft; b.BorderRadiusPercent.TopLeft = a.BorderRadiusPercent.TopLeft
    case .borderTopRightRadius: b.BorderRadius.TopRight = a.BorderRadius.TopRight; b.BorderRadiusPercent.TopRight = a.BorderRadiusPercent.TopRight
    case .borderBottomRightRadius: b.BorderRadius.BottomRight = a.BorderRadius.BottomRight; b.BorderRadiusPercent.BottomRight = a.BorderRadiusPercent.BottomRight
    case .borderBottomLeftRadius: b.BorderRadius.BottomLeft = a.BorderRadius.BottomLeft; b.BorderRadiusPercent.BottomLeft = a.BorderRadiusPercent.BottomLeft
    case .backgroundColor: b.BackgroundColor = a.BackgroundColor
    case .backgroundImage: b.BackgroundImage = a.BackgroundImage
    case .backgroundRepeat, .backgroundSize, .backgroundPosition:
        if let src = a.BackgroundImage, var dst = b.BackgroundImage {
            dst.RepeatX = src.RepeatX
            dst.RepeatY = src.RepeatY
            dst.Size = src.Size
            dst.PositionX = src.PositionX
            dst.PositionY = src.PositionY
            dst.OffsetX = src.OffsetX
            dst.OffsetY = src.OffsetY
            b.BackgroundImage = dst
        } else if p != .backgroundImage {
            if let src = a.BackgroundImage, b.BackgroundImage == nil {
                var dst = BackgroundImage(url: "")
                dst.RepeatX = src.RepeatX
                dst.RepeatY = src.RepeatY
                dst.Size = src.Size
                b.BackgroundImage = dst
            }
        }
    case .opacity: b.Opacity = a.Opacity
    case .filter: b.FilterBlur = a.FilterBlur
    case .overflowX: b.OverflowX = a.OverflowX
    case .overflowY: b.OverflowY = a.OverflowY
    case .boxShadow: b.Shadows = a.Shadows
    case .outlineWidth: b.OutlineWidth = a.OutlineWidth
    case .outlineColor: b.OutlineColor = a.OutlineColor
    case .verticalAlign: b.VerticalAlign = a.VerticalAlign
    case .textDecorationLine: b.TextDecoration = a.TextDecoration
    case .textDecorationColor: b.TextDecorationColor = a.TextDecorationColor
    case .flexDirection: b.FlexDirection = a.FlexDirection
    case .flexWrap: b.FlexWrap = a.FlexWrap
    case .justifyContent: b.JustifyContent = a.JustifyContent
    case .alignItems: b.AlignItems = a.AlignItems
    case .alignSelf: b.AlignSelf = a.AlignSelf
    case .alignContent: b.AlignContent = a.AlignContent
    case .flexGrow: b.FlexGrow = a.FlexGrow
    case .flexShrink: b.FlexShrink = a.FlexShrink
    case .flexBasis: b.FlexBasis = a.FlexBasis
    case .order: b.Order = a.Order
    case .rowGap: b.RowGap = a.RowGap
    case .columnGap: b.ColumnGap = a.ColumnGap
    case .tableLayout: b.TableLayout = a.TableLayout
    case .gridTemplateColumns: b.GridColumns = a.GridColumns
    case .gridTemplateRows: b.GridRows = a.GridRows
    case .gridAutoRows: b.GridAutoRows = a.GridAutoRows
    case .gridAutoColumns: b.GridAutoColumns = a.GridAutoColumns
    case .gridAutoFlow: b.GridAutoFlowColumn = a.GridAutoFlowColumn
    case .aspectRatio: b.AspectRatio = a.AspectRatio
    case .gridColumn, .gridColumnStart, .gridColumnEnd: b.GridColumn = a.GridColumn
    case .gridRow, .gridRowStart, .gridRowEnd: b.GridRow = a.GridRow
    case .color: b.Color = a.Color
    case .fontFamily: b.FontFamilies = a.FontFamilies
    case .fontSize: b.FontSize = a.FontSize
    case .fontWeight: b.FontWeight = a.FontWeight
    case .fontStyle: b.FontStyle = a.FontStyle
    case .lineHeight: b.LineHeight = a.LineHeight
    case .textAlign: b.TextAlign = a.TextAlign
    case .textTransform: b.TextTransform = a.TextTransform
    case .textIndent: b.TextIndent = a.TextIndent
    case .letterSpacing: b.LetterSpacing = a.LetterSpacing
    case .wordSpacing: b.WordSpacing = a.WordSpacing
    case .whiteSpace: b.WhiteSpace = a.WhiteSpace
    case .overflowWrap: b.OverflowWrap = a.OverflowWrap
    case .wordBreak: b.WordBreak = a.WordBreak
    case .textOverflow: b.TextOverflow = a.TextOverflow
    case .listStyleType: b.ListStyleType = a.ListStyleType
    case .listStylePosition: b.ListStylePosition = a.ListStylePosition
    case .cursor: b.Cursor = a.Cursor
    case .visibility: b.Visibility = a.Visibility
    case .borderCollapse: b.BorderCollapse = a.BorderCollapse
    case .borderSpacing: b.BorderSpacing = a.BorderSpacing
    case .tabSize: b.TabSize = a.TabSize
    case .content: b.Content = a.Content
    case .fill:
        b.Fill = a.Fill
        b.FillCurrent = a.FillCurrent
        b.FillNone = a.FillNone
    }
}


package func trimSpaces(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var start = 0
    var end = b.count
    while start < end && (b[start] == 32 || b[start] == 9 || b[start] == 10 || b[start] == 13) { start += 1 }
    while end > start && (b[end - 1] == 32 || b[end - 1] == 9 || b[end - 1] == 10 || b[end - 1] == 13) { end -= 1 }
    if start == 0 && end == b.count { return s }
    return stringOf(b, start, end)
}

func endsWith(_ s: string, _ suffix: string) -> bool {
    return s.hasSuffix(suffix)
}

/// Splits on a byte outside parentheses.
func splitTop(_ s: string, on sep: uint8) -> [string] {
    var out: [string] = []
    let b = [uint8](s.utf8)
    var depth = 0
    var start = 0
    var i = 0
    while i < b.count {
        if b[i] == 40 { depth += 1 }
        if b[i] == 41 && depth > 0 { depth -= 1 }
        if b[i] == sep && depth == 0 {
            out.append(trimSpaces(stringOf(b, start, i)))
            start = i + 1
        }
        i += 1
    }
    out.append(trimSpaces(stringOf(b, start, b.count)))
    return out
}

func sameFamilies(_ a: [string], _ b: [string]) -> bool {
    if a.count != b.count { return false }
    var i = 0
    while i < a.count {
        if a[i] != b[i] { return false }
        i += 1
    }
    return true
}

/// A length written as a word of a keyword value: "50%", "10px", "auto".
func lengthFromWord(_ word: string, _ s: ComputedStyle, _ ctx: ApplyContext) -> css.Length {
    if word == "auto" { return .auto }
    let b = [uint8](word.utf8)
    if b.isEmpty { return .auto }
    let n = css.parseNumber(b, 0, b.count)
    if b[b.count - 1] == 37 { return .percent(n) }
    if word.hasSuffix("em") && !word.hasSuffix("rem") { return .px(n * s.FontSize) }
    if word.hasSuffix("rem") { return .px(n * ctx.rootFontSize) }
    return .px(n)
}

/// Tracks with their em lengths resolved against the element.
func resolveTracks(_ tracks: [css.GridTrack], _ s: ComputedStyle, _ ctx: ApplyContext) -> [css.GridTrack] {
    return tracks
}

let tableBorderWidths: [css.Prop] = [.borderTopWidth, .borderRightWidth, .borderBottomWidth, .borderLeftWidth]
let tableBorderStyles: [css.Prop] = [.borderTopStyle, .borderRightStyle, .borderBottomStyle, .borderLeftStyle]
