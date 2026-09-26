package selector

import (
    "web/css"
    "web/html"
)

public enum Combinator: Equatable {
    case none
    case descendant      // " "
    case child           // ">"
    case adjacentSibling // "+"
    case generalSibling  // "~"
}

public enum AttrMatchOp: Equatable {
    case exists          // [attr]
    case exact           // [attr=val]
    case prefix          // [attr^=val]
    case suffix          // [attr$=val]
    case contains        // [attr*=val]
}

public struct AttrSelector: Equatable {
    public var Name: string
    public var Value: string
    public var Op: AttrMatchOp

    public init(name: string, value: string = "", op: AttrMatchOp = .exists) {
        self.Name = name
        self.Value = value
        self.Op = op
    }
}

/// A pseudo-class with whatever it was given: `:hover`, `:nth-child(2n+1)`
/// (A and B), `:not(a, .b)` (the selectors inside).
public struct Pseudo {
    public var Name: string
    public var Argument: string
    public var A: int
    public var B: int
    public var Inner: [ComplexSelector]

    public init(name: string, argument: string = "") {
        self.Name = name
        self.Argument = argument
        self.A = 0
        self.B = 0
        self.Inner = []
    }
}

public struct SelectorPart {
    public var Tag: string?
    public var Id: string?
    public var Classes: [string]
    public var Attributes: [AttrSelector]
    public var Pseudos: [Pseudo]
    /// `::before`, `::after` and the like; a selector with one names
    /// something no element is, so it matches no element.
    public var PseudoElement: string?

    public init() {
        self.Tag = nil
        self.Id = nil
        self.Classes = []
        self.Attributes = []
        self.Pseudos = []
        self.PseudoElement = nil
    }

    /// The names of the pseudo-classes, for code that wants only those.
    public var PseudoClasses: [string] {
        var out: [string] = []
        var i = 0
        while i < Pseudos.count {
            out.append(Pseudos[i].Name)
            i += 1
        }
        return out
    }
}

public struct CompoundSelector {
    public var Part: SelectorPart
    public var CombinatorWithNext: Combinator // Relationship to the NEXT compound to the right

    public init(part: SelectorPart, combinator: Combinator = .none) {
        self.Part = part
        self.CombinatorWithNext = combinator
    }
}

public struct ComplexSelector {
    public var Compounds: [CompoundSelector] // Left to right, e.g. ["div", ">", "p"]

    public init(compounds: [CompoundSelector] = []) {
        self.Compounds = compounds
    }

    /// Specificity tuple: (ID count, Class/Attribute/Pseudo count, Tag count)
    public func Specificity() -> (int, int, int) {
        var ids = 0
        var classes = 0
        var tags = 0

        var i = 0
        while i < Compounds.count {
            let p = Compounds[i].Part
            if p.Id != nil { ids += 1 }
            classes += p.Classes.count + p.Attributes.count
            var k = 0
            while k < p.Pseudos.count {
                let ps = p.Pseudos[k]
                // :not(), :is() and :has() count as their most specific
                // argument; :where() counts nothing.
                if ps.Name == "not" || ps.Name == "is" || ps.Name == "has" {
                    var best = (0, 0, 0)
                    var m = 0
                    while m < ps.Inner.count {
                        let sp = ps.Inner[m].Specificity()
                        if sp.0 > best.0 || (sp.0 == best.0 && (sp.1 > best.1 || (sp.1 == best.1 && sp.2 > best.2))) {
                            best = sp
                        }
                        m += 1
                    }
                    ids += best.0
                    classes += best.1
                    tags += best.2
                } else if ps.Name != "where" {
                    classes += 1
                }
                k += 1
            }
            if p.PseudoElement != nil { tags += 1 }
            if let t = p.Tag {
                if t != "*" { tags += 1 }
            }
            i += 1
        }
        return (ids, classes, tags)
    }
}

/// Parses a selector string like "div.container > h1#title, a[href^='https']"
public func ParseSelectors(_ selectorString: string) -> [ComplexSelector] {
    let rawList = splitByComma(selectorString)
    var selectors: [ComplexSelector] = []

    var i = 0
    while i < rawList.count {
        let trimmed = trim(rawList[i])
        if !trimmed.isEmpty {
            if let complex = parseComplexSelector(trimmed) {
                selectors.append(complex)
            }
        }
        i += 1
    }
    return selectors
}

func parseComplexSelector(_ selStr: string) -> ComplexSelector? {
    let bytes = bytesFrom(selStr)
    var pos = 0
    let len = bytes.count
    var compounds: [CompoundSelector] = []

    while pos < len {
        // Skip whitespace
        while pos < len && isSpace(bytes[pos]) {
            pos += 1
        }
        if pos >= len { break }

        // Check for combinator
        if bytes[pos] == 62 { // '>'
            if !compounds.isEmpty {
                compounds[compounds.count - 1].CombinatorWithNext = Combinator.child
            }
            pos += 1
            continue
        }
        if bytes[pos] == 43 { // '+'
            if !compounds.isEmpty {
                compounds[compounds.count - 1].CombinatorWithNext = Combinator.adjacentSibling
            }
            pos += 1
            continue
        }
        if bytes[pos] == 126 { // '~'
            if !compounds.isEmpty {
                compounds[compounds.count - 1].CombinatorWithNext = Combinator.generalSibling
            }
            pos += 1
            continue
        }

        // Parse compound part
        var part = SelectorPart()
        var readAny = false

        while pos < len && !isSpace(bytes[pos]) && bytes[pos] != 62 && bytes[pos] != 43 && bytes[pos] != 126 && bytes[pos] != 44 {
            let b = bytes[pos]

            if b == 35 { // '#' ID
                pos += 1
                let start = pos
                while pos < len && isIdent(bytes[pos]) { pos += 1 }
                part.Id = strFrom(bytes, start, pos)
                readAny = true
            } else if b == 46 { // '.' Class
                pos += 1
                let start = pos
                while pos < len && isIdent(bytes[pos]) { pos += 1 }
                part.Classes.append(strFrom(bytes, start, pos))
                readAny = true
            } else if b == 58 { // ':' Pseudo
                pos += 1
                var isElement = false
                if pos < len && bytes[pos] == 58 {
                    pos += 1
                    isElement = true
                }
                let start = pos
                while pos < len && isIdent(bytes[pos]) { pos += 1 }
                let name = toLower(strFrom(bytes, start, pos))
                var argument = ""
                if pos < len && bytes[pos] == 40 { // '('
                    pos += 1
                    let argStart = pos
                    var depth = 1
                    while pos < len && depth > 0 {
                        if bytes[pos] == 40 { depth += 1 }
                        if bytes[pos] == 41 { depth -= 1 }
                        if depth > 0 { pos += 1 }
                    }
                    argument = trim(strFrom(bytes, argStart, pos))
                    if pos < len { pos += 1 }
                }
                if isElement || name == "before" || name == "after" || name == "first-line" || name == "first-letter" {
                    part.PseudoElement = name
                } else {
                    var pseudo = Pseudo(name: name, argument: argument)
                    if name == "nth-child" || name == "nth-last-child" || name == "nth-of-type" || name == "nth-last-of-type" {
                        let ab = parseNth(argument)
                        pseudo.A = ab.a
                        pseudo.B = ab.b
                    } else if name == "not" || name == "is" || name == "where" || name == "has" {
                        pseudo.Inner = ParseSelectors(argument)
                    }
                    part.Pseudos.append(pseudo)
                }
                readAny = true
            } else if b == 91 { // '[' Attribute
                pos += 1
                let attr = parseAttrSelector(bytes, &pos)
                part.Attributes.append(attr)
                readAny = true
            } else if isIdent(b) || b == 42 { // Tag name or '*'
                let start = pos
                while pos < len && (isIdent(bytes[pos]) || bytes[pos] == 42) { pos += 1 }
                part.Tag = toLower(strFrom(bytes, start, pos))
                readAny = true
            } else {
                pos += 1
            }
        }

        if readAny {
            compounds.append(CompoundSelector(part: part, combinator: Combinator.descendant))
        }
    }

    if compounds.isEmpty {
        return nil
    }

    // The last compound has no next compound
    compounds[compounds.count - 1].CombinatorWithNext = Combinator.none

    return ComplexSelector(compounds: compounds)
}

func parseAttrSelector(_ bytes: [uint8], _ pos: inout int) -> AttrSelector {
    let len = bytes.count
    // Skip spaces
    while pos < len && isSpace(bytes[pos]) { pos += 1 }
    let nameStart = pos
    while pos < len && isIdent(bytes[pos]) { pos += 1 }
    let attrName = strFrom(bytes, nameStart, pos)

    while pos < len && isSpace(bytes[pos]) { pos += 1 }

    if pos >= len || bytes[pos] == 93 { // ']'
        if pos < len { pos += 1 }
        return AttrSelector(name: attrName, value: "", op: AttrMatchOp.exists)
    }

    var op = AttrMatchOp.exact
    if bytes[pos] == 94 && pos + 1 < len && bytes[pos + 1] == 61 { // '^='
        op = AttrMatchOp.prefix
        pos += 2
    } else if bytes[pos] == 36 && pos + 1 < len && bytes[pos + 1] == 61 { // '$='
        op = AttrMatchOp.suffix
        pos += 2
    } else if bytes[pos] == 42 && pos + 1 < len && bytes[pos + 1] == 61 { // '*='
        op = AttrMatchOp.contains
        pos += 2
    } else if bytes[pos] == 61 { // '='
        op = AttrMatchOp.exact
        pos += 1
    }

    while pos < len && isSpace(bytes[pos]) { pos += 1 }

    var val = ""
    if pos < len && (bytes[pos] == 34 || bytes[pos] == 39) { // quoted
        let q = bytes[pos]
        pos += 1
        let valStart = pos
        while pos < len && bytes[pos] != q { pos += 1 }
        val = strFrom(bytes, valStart, pos)
        if pos < len { pos += 1 }
    } else {
        let valStart = pos
        while pos < len && bytes[pos] != 93 && !isSpace(bytes[pos]) { pos += 1 }
        val = strFrom(bytes, valStart, pos)
    }

    while pos < len && bytes[pos] != 93 { pos += 1 }
    if pos < len { pos += 1 } // skip ']'

    return AttrSelector(name: attrName, value: val, op: op)
}

func bytesFrom(_ s: string) -> [uint8] {
    return [uint8](s.utf8)
}

@_silgen_name("vertex_string_from_utf8")
func stringFromUtf8(_ ptr: UnsafeRawPointer, _ count: int64) -> string

func strFrom(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return bytes.withUnsafeBytes { bp in
        stringFromUtf8(bp.baseAddress! + start, int64(end - start))
    }
}

func isSpace(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13
}

func isIdent(_ b: uint8) -> bool {
    return (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 45 || b == 95
}

func trim(_ s: string) -> string {
    let b = bytesFrom(s)
    if b.isEmpty { return "" }
    var st = 0
    while st < b.count && isSpace(b[st]) { st += 1 }
    var en = b.count
    while en > st && isSpace(b[en - 1]) { en -= 1 }
    return strFrom(b, st, en)
}

func splitByComma(_ s: string) -> [string] {
    var out: [string] = []
    var current: [uint8] = []
    var inQuotes = false
    var quoteChar: uint8 = 0
    var depth = 0

    for b in s.utf8 {
        if (b == 34 || b == 39) && (!inQuotes || b == quoteChar) {
            inQuotes = !inQuotes
            quoteChar = inQuotes ? b : 0
            current.append(b)
        } else if b == 44 && !inQuotes && depth == 0 { // ','
            out.append(strFrom(current, 0, current.count))
            current = []
        } else {
            if !inQuotes {
                if b == 40 || b == 91 { depth += 1 }
                if (b == 41 || b == 93) && depth > 0 { depth -= 1 }
            }
            current.append(b)
        }
    }
    if !current.isEmpty {
        out.append(strFrom(current, 0, current.count))
    }
    return out
}

/// The A and B of An+B: `2n+1`, `odd`, `even`, `3`, `-n+2`, `n`.
func parseNth(_ text: string) -> (a: int, b: int) {
    let lower = toLower(trim(text))
    if lower == "odd" { return (a: 2, b: 1) }
    if lower == "even" { return (a: 2, b: 0) }
    let bytes = bytesFrom(lower)
    var i = 0
    var a = 0
    var b = 0
    var hasN = false
    // The A part: a signed number, or a bare sign, before an n.
    var sign = 1
    var digits = 0
    var value = 0
    var sawDigit = false
    while i < bytes.count && isSpace(bytes[i]) { i += 1 }
    if i < bytes.count && (bytes[i] == 43 || bytes[i] == 45) {
        if bytes[i] == 45 { sign = -1 }
        i += 1
    }
    while i < bytes.count && bytes[i] >= 48 && bytes[i] <= 57 {
        value = value * 10 + int(bytes[i] - 48)
        i += 1
        digits += 1
        sawDigit = true
    }
    if i < bytes.count && bytes[i] == 110 { // 'n'
        hasN = true
        i += 1
        a = sawDigit ? sign * value : sign
    } else {
        return (a: 0, b: sign * value)
    }
    // The B part.
    while i < bytes.count && isSpace(bytes[i]) { i += 1 }
    if i < bytes.count && (bytes[i] == 43 || bytes[i] == 45) {
        let bsign = bytes[i] == 45 ? -1 : 1
        i += 1
        while i < bytes.count && isSpace(bytes[i]) { i += 1 }
        var bv = 0
        while i < bytes.count && bytes[i] >= 48 && bytes[i] <= 57 {
            bv = bv * 10 + int(bytes[i] - 48)
            i += 1
        }
        b = bsign * bv
    }
    _ = hasN
    return (a: a, b: b)
}
