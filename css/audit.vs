package css

/// What the engine makes of a stylesheet: how many declarations it
/// applies, and, by name, what it drops. The list of what real pages
/// still need.
public struct Coverage {
    public var Declarations: int = 0
    /// Declarations that turned into longhands the cascade applies, and
    /// those using var() on known properties, parsed per element.
    public var Applied: int = 0
    /// Properties the engine has never heard of, by name.
    public var UnknownProperties: [string: int] = [:]
    /// Properties it knows whose value didn't parse, by name.
    public var UnparsedValues: [string: int] = [:]
    /// Custom properties (--x) declared, which nothing reads yet.
    public var CustomProperties: int = 0
    /// Declarations whose value uses var().
    public var UsesVar: int = 0
    /// At-rules the cascade doesn't read, by name, with the rules and
    /// declarations inside them that go with them.
    public var DroppedAtRules: [string: int] = [:]
    public var RulesInDroppedAtRules: int = 0
    public var Rules: int = 0

    public init() {}

    /// Adds a sheet's declarations and rules.
    public mutating func Add(_ sheet: StyleSheet) {
        for r in sheet.Rules { add(r) }
        addAtRules(sheet.AtRules)
    }

    /// At-rules the cascade reads are walked into, as deep as they nest
    /// (whether an @supports holds is the cascade's to say); the rest are
    /// counted with what they hold.
    mutating func addAtRules(_ ats: [AtRule]) {
        for at in ats {
            switch at.Name {
            case "media", "supports", "layer":
                for r in at.Rules { add(r) }
                addAtRules(at.AtRules)
            case "import", "font-face", "charset":
                break
            default:
                DroppedAtRules[at.Name] = (DroppedAtRules[at.Name] ?? 0) + 1
                RulesInDroppedAtRules += countRules(at)
            }
        }
    }

    func countRules(_ at: AtRule) -> int {
        var n = at.Rules.count
        for inner in at.AtRules { n += countRules(inner) }
        return n
    }

    mutating func add(_ r: Rule) {
        Rules += 1
        for d in r.Declarations {
            Declarations += 1
            if d.Property.hasPrefix("--") {
                CustomProperties += 1
                continue
            }
            var usesVar = false
            for t in d.Tokens where t.Kind == .function && lower(t.Value) == "var" { usesVar = true }
            if usesVar { UsesVar += 1 }
            if !Longhands(d).isEmpty || (usesVar && IsKnownProperty(d.Property)) {
                // var() is substituted per element, and parsed then.
                Applied += 1
            } else if IsKnownProperty(d.Property) {
                UnparsedValues[d.Property] = (UnparsedValues[d.Property] ?? 0) + 1
            } else {
                UnknownProperties[d.Property] = (UnknownProperties[d.Property] ?? 0) + 1
            }
        }
    }

    /// A report: the counts, then each list most frequent first, up to
    /// `top` of each.
    public func Report(top: int = 15) -> string {
        var out = "  css: \(Rules) rules, \(Declarations) declarations, \(Applied) applied (\(Declarations > 0 ? Applied * 100 / Declarations : 0)%)\n"
        out += "    custom properties declared: \(CustomProperties); declarations using var(): \(UsesVar)\n"
        if !DroppedAtRules.isEmpty {
            out += "    at-rules dropped (\(RulesInDroppedAtRules) rules inside): " + ranked(DroppedAtRules, top) + "\n"
        }
        if !UnknownProperties.isEmpty { out += "    unknown properties: " + ranked(UnknownProperties, top) + "\n" }
        if !UnparsedValues.isEmpty { out += "    values not parsed: " + ranked(UnparsedValues, top) + "\n" }
        return out
    }
}

/// The longhands a property sets: itself, or a shorthand's parts.
/// Empty for a property the engine doesn't know.
public func LonghandsOf(_ name: string) -> [Prop] {
    return longhandsOf(name)
}

/// Whether the engine knows a property: a longhand it computes, or a
/// shorthand it expands.
public func IsKnownProperty(_ name: string) -> bool {
    if propNames[name] != nil { return true }
    return !longhandsOf(name).isEmpty
}

func ranked(_ counts: [string: int], _ top: int) -> string {
    var pairs: [(name: string, count: int)] = []
    for (k, v) in counts { pairs.append((name: k, count: v)) }
    pairs.sort { a, b in a.count != b.count ? a.count > b.count : a.name < b.name }
    var out = ""
    var i = 0
    while i < pairs.count && i < top {
        if i > 0 { out += ", " }
        out += "\(pairs[i].name) \(pairs[i].count)"
        i += 1
    }
    if pairs.count > top { out += ", … \(pairs.count - top) more" }
    return out
}
