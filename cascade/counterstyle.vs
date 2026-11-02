package cascade

import "web/css"

/// A style @counter-style defines.
public struct CounterStyle {
    var system: string = "symbolic"
    var symbols: [string] = []
    var additive: [(weight: int, symbol: string)] = []
    var prefix: string = ""
    var suffix: string = ". "
    /// `system: extends name`, or what to use where this one can't say.
    var base: string = ""
}

public var CounterStyles: [string: CounterStyle] = [:]

/// The words of a descriptor: strings and idents.
func symbolWords(tokens: [css.Token]) -> [string] {
    var out: [string] = []
    for t in tokens {
        if t.Kind == .string || t.Kind == .ident { out.append(t.Value) }
    }
    return out
}

/// Reads `@counter-style name { system: ...; symbols: ...; }`.
func DefineCounterStyle(at: css.AtRule) {
    let name = css.lower(trimSpaces(at.Params))
    if name.isEmpty { return }
    var c = CounterStyle()
    for d in at.Declarations {
        switch d.Property {
        case "system":
            let words = symbolWords(d.Tokens)
            if let first = words.first {
                c.system = css.lower(first)
                if c.system == "extends" && words.count > 1 { c.base = css.lower(words[1]) }
            }
        case "symbols":
            c.symbols = symbolWords(d.Tokens)
        case "additive-symbols":
            var weight = -1
            for t in d.Tokens {
                if t.Kind == .number { weight = int(t.NumberVal) }
                if (t.Kind == .string || t.Kind == .ident) && weight >= 0 {
                    c.additive.append((weight: weight, symbol: t.Value))
                    weight = -1
                }
            }
        case "prefix":
            c.prefix = symbolWords(d.Tokens).first ?? ""
        case "suffix":
            c.suffix = symbolWords(d.Tokens).first ?? ""
        case "fallback":
            if c.base.isEmpty { c.base = css.lower(symbolWords(d.Tokens).first ?? "") }
        default:
            break
        }
    }
    CounterStyles[name] = c
}

/// A number's text in a defined style, with its prefix and, for a marker,
/// its suffix; nil where it isn't one, or the style has no way to write
/// the number and no style of its own to fall back on.
public func CounterStyleText(name: string, n: int, marker: bool) -> string? {
    guard let c = CounterStyles[name] else { return nil }
    guard let body = counterBody(c, n) else { return nil }
    return c.prefix + body + (marker ? c.suffix : "")
}

func counterBody(c: CounterStyle, n: int) -> string? {
    let count = c.symbols.count
    switch c.system {
    case "cyclic":
        if count == 0 { return nil }
        return c.symbols[((n - 1) % count + count) % count]
    case "fixed":
        if n < 1 || n > count { return nil }
        return c.symbols[n - 1]
    case "symbolic":
        if count == 0 || n < 1 { return nil }
        return string(repeating: c.symbols[(n - 1) % count], count: (n - 1) / count + 1)
    case "alphabetic":
        if count < 2 || n < 1 { return nil }
        var v = n
        var out = ""
        while v > 0 {
            v -= 1
            out = c.symbols[v % count] + out
            v /= count
        }
        return out
    case "numeric":
        if count < 2 { return nil }
        var v = n < 0 ? -n : n
        if v == 0 { return c.symbols[0] }
        var out = ""
        while v > 0 {
            out = c.symbols[v % count] + out
            v /= count
        }
        return (n < 0 ? "-" : "") + out
    case "additive":
        if n < 0 || c.additive.isEmpty { return nil }
        var left = n
        var out = ""
        for a in c.additive where a.weight > 0 {
            while left >= a.weight {
                out += a.symbol
                left -= a.weight
            }
        }
        if left != 0 { return nil }
        if n == 0 {
            for a in c.additive where a.weight == 0 { return a.symbol }
            return nil
        }
        return out
    default:
        return nil
    }
}
