package selector

import (
    "text/bidi"
    "text/regexp"
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
    /// Whether focus came from the keyboard, so that :focus-visible
    /// shows a ring (a text field shows one however it was focused).
    public var FocusVisible: bool = false
    /// The element the URL's fragment names: :target.
    public var Target: html.Node? = nil
    /// A form control's value as the user left it; its attribute where
    /// this is nil.
    public var ValueOf: ((html.Node) -> string)? = nil
    /// Whether the user has changed a control: :user-valid and
    /// :user-invalid wait for that.
    public var Interacted: ((html.Node) -> bool)? = nil
    /// What :scope is: the root where nothing says.
    public var Scope: html.Node? = nil
    /// The modal dialogs and the open popovers, by element id: :modal
    /// and :popover-open.
    public var Modal = Set<int64>()
    public var PopoverOpen = Set<int64>()
    /// The media elements playing, by node id.
    public var Playing = Set<int64>()
    /// The base-select elements whose pickers are open, by node id.
    public var PickerOpen = Set<int64>()
    /// What a host says: fields it filled, the fullscreen element (0 none),
    /// :state()'s names by element. And the media elements in each state.
    public var Autofilled = Set<int64>()
    public var FullscreenElement: int64 = 0
    public var CustomStates: [int64: Set<string>] = [:]
    public var MediaSeeking = Set<int64>()
    public var MediaBuffering = Set<int64>()
    public var MediaStalled = Set<int64>()
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

    func siblingIndex(node: html.Node) -> (index: int, count: int) {
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

    func isHovered(node: html.Node) -> bool {
        var cur = Hovered
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    }

    func isActive(node: html.Node) -> bool {
        var cur = Active
        while let n = cur {
            if n.Id == node.Id { return true }
            cur = n.Parent
        }
        return false
    }
}

/// Matches a single compound part against an HTML element node.
public func MatchPart(part: SelectorPart, node: html.Node) -> bool {
    return MatchPartIn(part, node, MatchContext.none)
}

public func MatchPartIn(part: SelectorPart, node: html.Node, ctx: MatchContext) -> bool {
    return matchPart(part, node, ctx, pseudoElement: nil)
}

func matchPart(part: SelectorPart, node: html.Node, ctx: MatchContext, pseudoElement: string?) -> bool {
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

func matchPseudo(p: Pseudo, node: html.Node, ctx: MatchContext) -> bool {
    switch p.Name {
    case "only-child":
        return node.PreviousElementSibling() == nil && node.NextElementSibling() == nil
    case "first-of-type":
        return previousOfType(node) == nil
    case "last-of-type":
        return nextOfType(node) == nil
    case "only-of-type":
        return previousOfType(node) == nil && nextOfType(node) == nil
    case "nth-child", "nth-last-child":
        if !p.Inner.isEmpty {
            // Counted among the siblings the "of" list matches.
            if !matchesAny(p.Inner, node, ctx) { return false }
            guard let parent = node.Parent else { return nthMatches(p.A, p.B, 1) }
            var index = 0
            var count = 0
            for c in parent.Children where c.Kind == html.NodeKind.element && matchesAny(p.Inner, c, ctx) {
                count += 1
                if c.Id == node.Id { index = count }
            }
            return nthMatches(p.A, p.B, p.Name == "nth-child" ? index : count - index + 1)
        }
        let s = ctx.siblingIndex(node)
        return nthMatches(p.A, p.B, p.Name == "nth-child" ? s.index : s.count - s.index + 1)
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
    case "focus":
        if let f = ctx.Focused { return f.Id == node.Id }
        return false
    case "focus-visible":
        guard let f = ctx.Focused, f.Id == node.Id else { return false }
        return ctx.FocusVisible || isTextEntry(node)
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
    case "target":
        if let t = ctx.Target { return t.Id == node.Id }
        return false
    case "lang":
        return langMatches(p.Argument, node)
    case "dir":
        return css.lower(trimSpace(p.Argument)) == directionOf(node)
    case "defined":
        return true
    case "scope":
        if let s = ctx.Scope { return s.Id == node.Id }
        return node.Parent == nil || node.Parent?.Kind == html.NodeKind.document
    case "valid", "invalid", "user-valid", "user-invalid":
        if !isValidatable(node) && node.TagName != "form" && node.TagName != "fieldset" { return false }
        if p.Name.hasPrefix("user-") {
            guard let i = ctx.Interacted, i(node) else { return false }
        }
        let valid = isValid(node, ctx)
        return p.Name.hasSuffix("invalid") ? !valid : valid
    case "in-range", "out-of-range":
        guard let inRange = rangeState(node, ctx) else { return false }
        return p.Name == "in-range" ? inRange : !inRange
    case "read-write":
        return isReadWrite(node)
    case "read-only":
        return !isReadWrite(node)
    case "default":
        return isDefault(node)
    case "indeterminate":
        return isIndeterminate(node)
    case "open":
        let t = node.TagName
        if t == "select" { return ctx.PickerOpen.contains(node.Id) }
        return (t == "details" || t == "dialog") && node.HasAttribute("open")
    case "paused":
        return (node.TagName == "video" || node.TagName == "audio") && !ctx.Playing.contains(node.Id)
    case "playing":
        return ctx.Playing.contains(node.Id)
    case "muted":
        return (node.TagName == "video" || node.TagName == "audio") && node.HasAttribute("muted")
    case "modal":
        return ctx.Modal.contains(node.Id)
    case "popover-open":
        return ctx.PopoverOpen.contains(node.Id)
    case "autofill", "-webkit-autofill":
        return ctx.Autofilled.contains(node.Id)
    case "fullscreen":
        return ctx.FullscreenElement == node.Id
    case "seeking":
        return ctx.MediaSeeking.contains(node.Id)
    case "buffering":
        return ctx.MediaBuffering.contains(node.Id)
    case "stalled":
        return ctx.MediaStalled.contains(node.Id)
    case "state":
        return ctx.CustomStates[node.Id]?.contains(p.Argument) ?? false
    case "picture-in-picture", "volume-locked":
        return false
    default:
        return false
    }
}

func isFormControl(node: html.Node) -> bool {
    let t = node.TagName
    return t == "input" || t == "button" || t == "select" || t == "textarea" || t == "option" || t == "fieldset"
}

func hasDescendantMatching(node: html.Node, sel: ComplexSelector, ctx: MatchContext) -> bool {
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

func previousOfType(node: html.Node) -> html.Node? {
    var cur = node.PreviousElementSibling()
    while let n = cur {
        if n.TagName == node.TagName { return n }
        cur = n.PreviousElementSibling()
    }
    return nil
}

func nextOfType(node: html.Node) -> html.Node? {
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
func indexAmongSiblings(node: html.Node, ofType: bool, fromEnd: bool) -> int {
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
func nthMatches(a: int, b: int, index: int) -> bool {
    if a == 0 { return index == b }
    let diff = index - b
    if diff % a != 0 { return false }
    return diff / a >= 0
}

/// Matches a complex selector (e.g. `div.menu > ul li a`) against an element node.
public func MatchComplex(complex: ComplexSelector, node: html.Node) -> bool {
    return MatchComplexIn(complex, node, MatchContext.none)
}

/// Matches a complex selector against an element, with the page's state
/// for the dynamic pseudo-classes.
public func MatchComplexIn(complex: ComplexSelector, node: html.Node, ctx: MatchContext) -> bool {
    return MatchComplexIn(complex, node, ctx, pseudoElement: nil)
}

/// Matches a selector that ends in a pseudo-element -- `a::before` --
/// against an element's pseudo-element of that name; with nil, a
/// selector ending in a pseudo-element matches nothing.
public func MatchComplexIn(complex: ComplexSelector, node: html.Node, ctx: MatchContext, pseudoElement: string?) -> bool {
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
func toLower(s: string) -> string {
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

func hasPrefix(str: string, prefix: string) -> bool {
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

func hasSuffix(str: string, suffix: string) -> bool {
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

func contains(str: string, needle: string) -> bool {
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

func matchesAny(list: [ComplexSelector], node: html.Node, ctx: MatchContext) -> bool {
    for sel in list where MatchComplexIn(sel, node, ctx) { return true }
    return false
}

func trimSpace(s: string) -> string {
    let b = [uint8](s.utf8)
    var i = 0
    var j = b.count
    while i < j && (b[i] == 32 || b[i] == 9 || b[i] == 10) { i += 1 }
    while j > i && (b[j - 1] == 32 || b[j - 1] == 9 || b[j - 1] == 10) { j -= 1 }
    return strFrom(b, i, j)
}

/// A field one types into: what shows :focus-visible however focused.
func isTextEntry(node: html.Node) -> bool {
    if node.TagName == "textarea" { return true }
    if node.TagName != "input" { return false }
    switch inputType(node) {
    case "checkbox", "radio", "button", "submit", "reset", "image", "range", "color", "file", "hidden": return false
    default: return true
    }
}

func inputType(node: html.Node) -> string {
    return css.lower(node.GetAttribute("type") ?? "text")
}

/// :lang(): the element's language, from the nearest lang attribute,
/// matches a range: equal, or a prefix before a hyphen; `*` matches any.
func langMatches(arg: string, node: html.Node) -> bool {
    var lang: string? = nil
    var cur: html.Node? = node
    while let n = cur {
        if let l = n.GetAttribute("lang") ?? n.GetAttribute("xml:lang") { lang = css.lower(l); break }
        cur = n.Parent
    }
    guard let have = lang else { return false }
    for raw in arg.split(separator: ",") {
        var want = css.lower(trimSpace(string(raw)))
        if want.hasPrefix("\"") && want.hasSuffix("\"") && want.count >= 2 { want = string(want.dropFirst().dropLast()) }
        if want == "*" { if !have.isEmpty { return true }; continue }
        if want.hasPrefix("*-") { want = string(want.dropFirst(2)); if have.contains(want) { return true }; continue }
        if have == want || have.hasPrefix(want + "-") { return true }
    }
    return false
}

/// The element's direction, from the nearest dir attribute: ltr where
/// none says. dir=auto takes the direction of the first strong
/// character of the element's text, as HTML has it (ltr where there is
/// none; a textarea's or input's from its value).
func directionOf(node: html.Node) -> string {
    var cur: html.Node? = node
    while let n = cur {
        if let d = n.GetAttribute("dir") {
            let v = css.lower(d)
            if v == "rtl" { return "rtl" }
            if v == "ltr" { return "ltr" }
            if v == "auto" {
                let text = n.TagName == "input" ? (n.GetAttribute("value") ?? "") : n.InnerText()
                var cps: [uint32] = []
                for u in text.unicodeScalars { cps.append(u.value) }
                return bidi.FirstStrong(cps) == .rtl ? "rtl" : "ltr"
            }
        }
        cur = n.Parent
    }
    return "ltr"
}

func valueFor(node: html.Node, ctx: MatchContext) -> string {
    if let v = ctx.ValueOf { return v(node) }
    if node.TagName == "textarea" { return node.InnerText() }
    return node.GetAttribute("value") ?? ""
}

/// Whether constraint validation looks at a control: barred are the
/// disabled, the read-only, buttons, hidden inputs, and what is in a
/// <datalist>.
/// Whether a control meets its constraints, as :valid asks; true for
/// what constraint validation doesn't look at.
public func IsValid(node: html.Node, ctx: MatchContext) -> bool {
    return !isValidatable(node) || isValid(node, ctx)
}

/// Whether constraint validation looks at a control.
public func IsValidatable(node: html.Node) -> bool { return isValidatable(node) }

func isValidatable(node: html.Node) -> bool {
    let t = node.TagName
    if t != "input" && t != "textarea" && t != "select" { return false }
    if node.HasAttribute("disabled") { return false }
    if t != "select" && node.HasAttribute("readonly") { return false }
    if t == "input" {
        switch inputType(node) {
        case "hidden", "button", "submit", "reset", "image": return false
        default: break
        }
    }
    var cur = node.Parent
    while let n = cur {
        if n.TagName == "datalist" { return false }
        if n.TagName == "fieldset" && n.HasAttribute("disabled") { return false }
        cur = n.Parent
    }
    return true
}

/// Whether a control meets its constraints -- required, type, length,
/// range and pattern -- or, for a form or fieldset, whether everything
/// in it does.
func isValid(node: html.Node, ctx: MatchContext) -> bool {
    if node.TagName == "form" || node.TagName == "fieldset" {
        for c in node.Children where c.Kind == html.NodeKind.element {
            if isValidatable(c) && !isValid(c, ctx) { return false }
            if !isValidatable(c) && c.TagName != "form" && !isValid(c, ctx) { return false }
        }
        return true
    }
    return ValidationMessage(node, ctx).isEmpty
}

/// What a control that fails its constraints says about it, as a
/// browser's validation bubble does; empty where it meets them (or
/// isn't validated).
public func ValidationMessage(node: html.Node, ctx: MatchContext) -> string {
    if !isValidatable(node) { return "" }
    let type = node.TagName == "input" ? inputType(node) : node.TagName
    let required = node.HasAttribute("required")
    if type == "checkbox" { return !required || node.HasAttribute("checked") ? "" : "Please check this box if you want to proceed." }
    if type == "radio" {
        if !required && !groupRequired(node) { return "" }
        return radioGroupChecked(node) ? "" : "Please select one of these options."
    }
    if type == "select" {
        if !required { return "" }
        for o in descendants(node) where o.TagName == "option" && o.HasAttribute("selected") {
            return !(o.GetAttribute("value") ?? o.InnerText()).isEmpty ? "" : "Please select an item in the list."
        }
        return "Please select an item in the list."
    }
    let value = valueFor(node, ctx)
    if value.isEmpty { return required ? "Please fill out this field." : "" }
    let chars = value.count
    if let n = intAttr(node, "minlength"), chars < n {
        return "Please lengthen this text to \(n) characters or more (you are currently using \(chars) characters)."
    }
    if let n = intAttr(node, "maxlength"), chars > n {
        return "Please shorten this text to \(n) characters or less (you are currently using \(chars) characters)."
    }
    switch type {
    case "email":
        let list = node.HasAttribute("multiple") ? value.split(separator: ",").map { trimSpace(string($0)) } : [value]
        for e in list where !looksLikeEmail(e) {
            return e.contains("@") ? "Please enter an email address." : "Please include an '@' in the email address. '\(e)' is missing an '@'."
        }
    case "url":
        if !value.contains(":") { return "Please enter a URL." }
    case "number", "range":
        guard let n = numberOf(value) else { return "Please enter a number." }
        if let lo = numberAttr(node, "min"), n < lo { return "Value must be greater than or equal to \(node.GetAttribute("min") ?? "")." }
        if let hi = numberAttr(node, "max"), n > hi { return "Value must be less than or equal to \(node.GetAttribute("max") ?? "")." }
    default:
        break
    }
    // pattern: the whole value (each address of a multiple email)
    // matches it, compiled with the v flag; a pattern that doesn't
    // compile is ignored.
    if let pattern = node.GetAttribute("pattern"), takesPattern(type), let re = compiledPattern(pattern) {
        let list = type == "email" && node.HasAttribute("multiple") ? value.split(separator: ",").map { trimSpace(string($0)) } : [value]
        for v in list where !re.MatchesWhole(v) {
            if let title = node.GetAttribute("title"), !title.isEmpty { return "Please match the requested format.\n" + title }
            return "Please match the requested format."
        }
    }
    return ""
}

func takesPattern(type: string) -> bool {
    switch type {
    case "text", "search", "url", "tel", "email", "password": return true
    default: return false
    }
}

// Compiled patterns by their text, and the texts that don't compile.
var patterns: [string: regexp.Regexp] = [:]
var badPatterns: [string: bool] = [:]

func compiledPattern(p: string) -> regexp.Regexp? {
    if let re = patterns[p] { return re }
    if badPatterns[p] != nil { return nil }
    if let re = regexp.Regexp.Compile(p, flags: "v") {
        patterns[p] = re
        return re
    }
    badPatterns[p] = true
    return nil
}

func looksLikeEmail(s: string) -> bool {
    let parts = s.split(separator: "@", omittingEmptySubsequences: false)
    if parts.count != 2 || parts[0].isEmpty || parts[1].isEmpty { return false }
    for c in s.utf8 where c == 32 { return false }
    return true
}

/// :in-range or not, for a number or range input with a min or max;
/// nil where it has no range.
func rangeState(node: html.Node, ctx: MatchContext) -> bool? {
    if node.TagName != "input" { return nil }
    let type = inputType(node)
    if type != "number" && type != "range" { return nil }
    let lo = numberAttr(node, "min")
    let hi = numberAttr(node, "max")
    if lo == nil && hi == nil && type != "range" { return nil }
    guard let n = numberOf(valueFor(node, ctx)) else { return true }
    if let l = lo, n < l { return false }
    if let h = hi, n > h { return false }
    return true
}

func isReadWrite(node: html.Node) -> bool {
    if node.TagName == "textarea" { return !node.HasAttribute("readonly") && !node.HasAttribute("disabled") }
    if node.TagName == "input" {
        if !isTextEntry(node) && inputType(node) != "number" { return false }
        return !node.HasAttribute("readonly") && !node.HasAttribute("disabled")
    }
    var cur: html.Node? = node
    while let n = cur {
        if let ce = n.GetAttribute("contenteditable") {
            let v = css.lower(ce)
            return v == "" || v == "true" || v == "plaintext-only"
        }
        cur = n.Parent
    }
    return false
}

func isDefault(node: html.Node) -> bool {
    switch node.TagName {
    case "option": return node.HasAttribute("selected")
    case "input":
        let type = inputType(node)
        if type == "checkbox" || type == "radio" { return node.HasAttribute("checked") }
        if type == "submit" || type == "image" { return isDefaultButton(node) }
        return false
    case "button":
        let type = css.lower(node.GetAttribute("type") ?? "submit")
        return type == "submit" && isDefaultButton(node)
    default:
        return false
    }
}

/// Whether a submit button is the first of its form's.
func isDefaultButton(node: html.Node) -> bool {
    var form = node.Parent
    while let f = form, f.TagName != "form" { form = f.Parent }
    guard let f = form else { return false }
    for d in descendants(f) {
        let isSubmit = (d.TagName == "button" && css.lower(d.GetAttribute("type") ?? "submit") == "submit")
            || (d.TagName == "input" && (inputType(d) == "submit" || inputType(d) == "image"))
        if isSubmit { return d.Id == node.Id }
    }
    return false
}

func isIndeterminate(node: html.Node) -> bool {
    if node.TagName == "progress" { return !node.HasAttribute("value") }
    if node.TagName != "input" { return false }
    let type = inputType(node)
    if type == "checkbox" { return node.HasAttribute("indeterminate") }
    if type == "radio" { return !radioGroupChecked(node) }
    return false
}

/// The radio buttons of node's group: the same name in the same form.
func radioGroup(node: html.Node) -> [html.Node] {
    guard let name = node.GetAttribute("name"), !name.isEmpty else { return [node] }
    var top: html.Node = node
    while let p = top.Parent {
        top = p
        if p.TagName == "form" { break }
    }
    return descendants(top).filter { $0.TagName == "input" && inputType($0) == "radio" && $0.GetAttribute("name") == name }
}

func radioGroupChecked(node: html.Node) -> bool {
    for r in radioGroup(node) where r.HasAttribute("checked") { return true }
    return false
}

func groupRequired(node: html.Node) -> bool {
    for r in radioGroup(node) where r.HasAttribute("required") { return true }
    return false
}

func descendants(node: html.Node) -> [html.Node] {
    var out: [html.Node] = []
    for c in node.Children where c.Kind == html.NodeKind.element {
        out.append(c)
        out.append(contentsOf: descendants(c))
    }
    return out
}

func numberOf(s: string) -> float64? {
    let t = trimSpace(s)
    if t.isEmpty { return nil }
    let b = [uint8](t.utf8)
    var digits = 0
    for c in b {
        if c >= 48 && c <= 57 { digits += 1; continue }
        if c == 45 || c == 43 || c == 46 || c == 101 || c == 69 { continue }
        return nil
    }
    if digits == 0 { return nil }
    return float64(css.ParseNumberText(t))
}

func numberAttr(node: html.Node, name: string) -> float64? {
    guard let v = node.GetAttribute(name) else { return nil }
    return numberOf(v)
}

func intAttr(node: html.Node, name: string) -> int? {
    guard let v = numberAttr(node, name), v >= 0 else { return nil }
    return int(v)
}
