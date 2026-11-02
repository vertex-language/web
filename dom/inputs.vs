package dom

import "web/html"

// The input types beyond text: number's stepping, and the date and time
// types' values -- their formats, checking them, and stepping them by a
// day, a minute, a month or a week as the arrow keys do.

/// The input types whose value is a date or a time.
public func IsDateTimeType(type: string) -> bool {
    return type == "date" || type == "time" || type == "datetime-local" || type == "month" || type == "week"
}

/// What an empty date or time field shows: its format.
public func FormatHint(type: string) -> string {
    switch type {
    case "date": return "yyyy-mm-dd"
    case "time": return "--:--"
    case "datetime-local": return "yyyy-mm-ddT--:--"
    case "month": return "yyyy-mm"
    case "week": return "yyyy-W--"
    default: return ""
    }
}

/// A value as its type allows it: a date or time in its format, a color
/// as #rrggbb, a number that parses; "" (or the color black) where it
/// doesn't.
public func SanitizedValue(type: string, value: string) -> string {
    switch type {
    case "date": return parseDate(value) != nil ? value : ""
    case "month": return parseMonth(value) != nil ? value : ""
    case "week": return parseWeek(value) != nil ? value : ""
    case "time": return parseTime(value) != nil ? value : ""
    case "datetime-local":
        let parts = value.split(separator: "T").map { string($0) }
        if parts.count == 2 && parseDate(parts[0]) != nil && parseTime(parts[1]) != nil { return value }
        let spaced = value.split(separator: " ").map { string($0) }
        if spaced.count == 2 && parseDate(spaced[0]) != nil && parseTime(spaced[1]) != nil { return spaced[0] + "T" + spaced[1] }
        return ""
    case "color":
        let b = [uint8](value.lowercased().utf8)
        if b.count == 7 && b[0] == 35 {
            for c in b[1...] where !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) { return "#000000" }
            return value.lowercased()
        }
        return "#000000"
    default:
        return value
    }
}

func digits(s: string) -> int? {
    if s.isEmpty { return nil }
    var n = 0
    for c in s.utf8 {
        if c < 48 || c > 57 { return nil }
        n = n * 10 + int(c - 48)
    }
    return n
}

func daysIn(year: int, month: int) -> int {
    switch month {
    case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
}

func parseDate(s: string) -> (y: int, m: int, d: int)? {
    let p = s.split(separator: "-").map { string($0) }
    guard p.count == 3, p[0].count >= 4, p[1].count == 2, p[2].count == 2,
          let y = digits(p[0]), let m = digits(p[1]), let d = digits(p[2]) else { return nil }
    if m < 1 || m > 12 || d < 1 || d > daysIn(y, m) { return nil }
    return (y: y, m: m, d: d)
}

func parseMonth(s: string) -> (y: int, m: int)? {
    let p = s.split(separator: "-").map { string($0) }
    guard p.count == 2, p[0].count >= 4, p[1].count == 2, let y = digits(p[0]), let m = digits(p[1]), m >= 1 && m <= 12 else { return nil }
    return (y: y, m: m)
}

func parseWeek(s: string) -> (y: int, w: int)? {
    let p = s.split(separator: "-").map { string($0) }
    guard p.count == 2, p[0].count >= 4, p[1].count == 3, p[1].hasPrefix("W"), let y = digits(p[0]),
          let w = digits(string(p[1].dropFirst())), w >= 1 && w <= 53 else { return nil }
    return (y: y, w: w)
}

func parseTime(s: string) -> (h: int, m: int)? {
    let p = s.split(separator: ":").map { string($0) }
    guard p.count >= 2, p[0].count == 2, p[1].count == 2, let h = digits(p[0]), let m = digits(p[1]), h < 24 && m < 60 else { return nil }
    return (h: h, m: m)
}

/// Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm).
func daysFromCivil(y0: int, m: int, d: int) -> int {
    let y = m <= 2 ? y0 - 1 : y0
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = m > 2 ? m - 3 : m + 9
    let doy = (153 * mp + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

func civilFromDays(z0: int) -> (y: int, m: int, d: int) {
    let z = z0 + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    return (y: yoe + era * 400 + (m <= 2 ? 1 : 0), m: m, d: d)
}

func pad(n: int, width: int) -> string {
    var s = "\(n)"
    while s.count < width { s = "0" + s }
    return s
}

/// A date or time value moved by steps (a day, a minute, a month, a
/// week), from today's "zero" where it is empty.
public func StepDateTime(type: string, value: string, by steps: int) -> string {
    switch type {
    case "date":
        let d = parseDate(value) ?? (y: 2026, m: 1, d: 1)
        let c = civilFromDays(daysFromCivil(d.y, d.m, d.d) + steps)
        return pad(c.y, 4) + "-" + pad(c.m, 2) + "-" + pad(c.d, 2)
    case "month":
        let m = parseMonth(value) ?? (y: 2026, m: 1)
        let total = m.y * 12 + (m.m - 1) + steps
        return pad(total / 12, 4) + "-" + pad(total % 12 + 1, 2)
    case "week":
        let w = parseWeek(value) ?? (y: 2026, w: 1)
        var week = w.w + steps
        var year = w.y
        while week > 52 { week -= 52; year += 1 }
        while week < 1 { week += 52; year -= 1 }
        return pad(year, 4) + "-W" + pad(week, 2)
    case "time":
        let t = parseTime(value) ?? (h: 0, m: 0)
        var mins = (t.h * 60 + t.m + steps) % 1440
        if mins < 0 { mins += 1440 }
        return pad(mins / 60, 2) + ":" + pad(mins % 60, 2)
    case "datetime-local":
        let parts = value.split(separator: "T").map { string($0) }
        var date = parts.count == 2 ? (parseDate(parts[0]) ?? (y: 2026, m: 1, d: 1)) : (y: 2026, m: 1, d: 1)
        let t = parts.count == 2 ? (parseTime(parts[1]) ?? (h: 0, m: 0)) : (h: 0, m: 0)
        var mins = t.h * 60 + t.m + steps
        var days = daysFromCivil(date.y, date.m, date.d)
        while mins >= 1440 { mins -= 1440; days += 1 }
        while mins < 0 { mins += 1440; days -= 1 }
        date = civilFromDays(days)
        return pad(date.y, 4) + "-" + pad(date.m, 2) + "-" + pad(date.d, 2) + "T" + pad(mins / 60, 2) + ":" + pad(mins % 60, 2)
    default:
        return value
    }
}

/// A number field's value moved by steps of its step attribute (1 where
/// it gives none), kept within min and max.
public func StepNumber(node: html.Node, value: string, by steps: int) -> string {
    let step = number(node.GetAttribute("step") ?? "") ?? 1
    var v = number(value) ?? (number(node.GetAttribute("min") ?? "") ?? 0) - (steps > 0 ? step : -step)
    v += step * float64(steps)
    if let lo = number(node.GetAttribute("min") ?? ""), v < lo { v = lo }
    if let hi = number(node.GetAttribute("max") ?? ""), v > hi { v = hi }
    let rounded = float64(int64(v))
    if rounded == v { return "\(int64(v))" }
    return "\(v)"
}

func number(s: string) -> float64? {
    if s.isEmpty { return nil }
    var seen = false
    for c in s.utf8 {
        if c >= 48 && c <= 57 { seen = true; continue }
        if c == 45 || c == 43 || c == 46 || c == 101 || c == 69 { continue }
        return nil
    }
    if !seen { return nil }
    let b = [uint8](s.utf8)
    var i = 0
    var neg = false
    if i < b.count && (b[i] == 45 || b[i] == 43) { neg = b[i] == 45; i += 1 }
    var v: float64 = 0
    while i < b.count && b[i] >= 48 && b[i] <= 57 { v = v * 10 + float64(b[i] - 48); i += 1 }
    if i < b.count && b[i] == 46 {
        i += 1
        var scale: float64 = 0.1
        while i < b.count && b[i] >= 48 && b[i] <= 57 { v += float64(b[i] - 48) * scale; scale *= 0.1; i += 1 }
    }
    return neg ? -v : v
}
