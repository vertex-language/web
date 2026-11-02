package css

import (
    "image/draw"
    "math"
)

// CSS Color 4 and 5 beyond rgb() and hsl(): hwb(), lab(), lch(),
// oklab(), oklch(), color(), color-mix(), contrast-color(),
// light-dark(), and relative colors (`rgb(from <color> r g b / alpha)`).
// Every space converts through CIE XYZ (D65), and what is out of the
// sRGB gamut is clipped, since draw.Color is 8-bit sRGB.

/// A color in some space: three channels as the space keeps them, and
/// the alpha from 0 to 1. A missing (`none`) channel is NaN-free: it is
/// marked in `missing` and holds 0.
struct SpaceColor {
    var c: [float64]
    var alpha: float64
    var missing: [bool]
}

/// The spaces a color can be written or mixed in. `rgb` is sRGB with
/// channels 0-255 (what rgb() and its relative keywords use); `hsl` and
/// `hwb` keep their second and third channels 0-100.
let colorSpaces: [string] = [
    "rgb", "srgb", "srgb-linear", "display-p3", "a98-rgb", "prophoto-rgb", "rec2020",
    "xyz", "xyz-d50", "xyz-d65", "lab", "lch", "oklab", "oklch", "hsl", "hwb",
]

/// Which channel is a hue in a space, or -1.
func hueIndex(space: string) -> int {
    switch space {
    case "hsl", "hwb": return 0
    case "lch", "oklch": return 2
    default: return -1
    }
}

/// What 100% is for channel i of a space.
func percentRef(space: string, i: int) -> float64 {
    switch space {
    case "rgb": return 255
    case "hsl", "hwb": return 100
    case "lab": return i == 0 ? 100 : 125
    case "lch": return i == 0 ? 100 : 150
    case "oklab", "oklch": return i == 0 ? 1 : 0.4
    default: return 1
    }
}

/// The names relative colors give a space's channels.
func channelNames(space: string) -> [string] {
    switch space {
    case "rgb", "srgb", "srgb-linear", "display-p3", "a98-rgb", "prophoto-rgb", "rec2020": return ["r", "g", "b"]
    case "xyz", "xyz-d50", "xyz-d65": return ["x", "y", "z"]
    case "lab", "oklab": return ["l", "a", "b"]
    case "lch", "oklch": return ["l", "c", "h"]
    case "hsl": return ["h", "s", "l"]
    case "hwb": return ["h", "w", "b"]
    default: return []
    }
}

/// The functional colors this file parses, where `name(` starts one.
func parseColorFunction(name: string, b: [uint8], start: int) -> draw.Color? {
    let end = b.count - 1
    switch name {
    case "color-mix": return parseColorMix(b, start, end)
    case "contrast-color":
        guard let c = ParseColor(stringOf(b, start, end)) else { return nil }
        return contrastColor(c)
    case "light-dark":
        let parts = commaArgs(b, start, end)
        if parts.count != 2 { return nil }
        return ParseColor(parts[0])
    default:
        break
    }
    var args = colorArgs(b, start, end)
    var space = name
    switch name {
    case "rgb", "rgba": space = "rgb"
    case "hsl", "hsla": space = "hsl"
    case "hwb", "lab", "lch", "oklab", "oklch", "color": break
    default: return nil
    }
    var env: [string: float64] = [:]
    if args.count >= 2 && args[0] == "from" {
        guard let origin = ParseColor(args[1]) else { return nil }
        args.removeFirst(2)
        if space == "color" {
            if args.isEmpty { return nil }
            space = args[0] == "xyz" ? "xyz-d65" : args[0]
            args.removeFirst()
            if !isRGBFamily(space) && !space.hasPrefix("xyz") { return nil }
        }
        let o = fromSRGB(space, srgbOf(origin))
        let names = channelNames(space)
        var i = 0
        while i < 3 { env[names[i]] = o.c[i]; i += 1 }
        env["alpha"] = o.alpha
    } else if space == "color" {
        if args.isEmpty { return nil }
        space = args[0] == "xyz" ? "xyz-d65" : args[0]
        args.removeFirst()
        if !isRGBFamily(space) && !space.hasPrefix("xyz") { return nil }
    }
    guard let sc = channelsIn(space, args, env) else { return nil }
    return toDrawColor(space, sc)
}

func isRGBFamily(space: string) -> bool {
    switch space {
    case "srgb", "srgb-linear", "display-p3", "a98-rgb", "prophoto-rgb", "rec2020": return true
    default: return false
    }
}

/// The three channels and the alpha written in args, in a space's own
/// units. env names the origin's channels in a relative color.
func channelsIn(space: string, args: [string], env: [string: float64]) -> SpaceColor? {
    var values: [float64] = []
    var missing: [bool] = []
    var alpha: float64 = env["alpha"] ?? 1
    var i = 0
    while i < args.count {
        if args[i] == "/" {
            if i + 2 != args.count { return nil }
            guard let a = channelOf(args[i + 1], env) else { return nil }
            alpha = a.none ? 0 : (a.percent ? a.value / 100 : a.value)
            break
        }
        if values.count == 3 {
            // The legacy comma form puts the alpha fourth.
            if i + 1 != args.count { return nil }
            guard let a = channelOf(args[i], env) else { return nil }
            alpha = a.percent ? a.value / 100 : a.value
            break
        }
        guard let ch = channelOf(args[i], env) else { return nil }
        let k = values.count
        if ch.angle && k != hueIndex(space) { return nil }
        if ch.percent && k == hueIndex(space) { return nil }
        values.append(ch.percent ? ch.value * percentRef(space, k) / 100 : ch.value)
        missing.append(ch.none)
        i += 1
    }
    if values.count != 3 { return nil }
    return SpaceColor(c: values, alpha: clamp01(alpha), missing: missing)
}

/// One channel as written: a number, a percentage, an angle in degrees,
/// `none`, an origin's channel keyword, or a calc() of those.
struct Channel {
    var value: float64
    var percent: bool
    var angle: bool
    var none: bool
}

func channelOf(s: string, env: [string: float64]) -> Channel? {
    if s == "none" { return Channel(value: 0, percent: false, angle: false, none: true) }
    if let v = env[s] { return Channel(value: v, percent: false, angle: false, none: false) }
    let b = [uint8](s.utf8)
    if b.count > 6 && startsWith(b, "calc(") && b[b.count - 1] == 41 {
        let p = CalcReader(b, 5, b.count - 1, env)
        guard let v = p.sum() else { return nil }
        p.skipSpace()
        if p.i != p.end { return nil }
        return Channel(value: v, percent: false, angle: false, none: false)
    }
    guard let n = numberAt(b, 0, b.count) else { return nil }
    let unit = stringOf(b, n.next, b.count)
    switch unit {
    case "": return Channel(value: n.value, percent: false, angle: false, none: false)
    case "%": return Channel(value: n.value, percent: true, angle: false, none: false)
    default:
        guard let deg = degrees(n.value, unit) else { return nil }
        return Channel(value: deg, percent: false, angle: true, none: false)
    }
}

/// An angle in degrees, from a number and its unit; nil for anything
/// that is not an angle unit.
func degrees(v: float64, unit: string) -> float64? {
    switch unit {
    case "deg": return v
    case "grad": return v * 0.9
    case "rad": return v * 180 / math.Pi
    case "turn": return v * 360
    default: return nil
    }
}

/// The number at b[i..<end] and where it ends; nil where none starts there.
func numberAt(b: [uint8], i: int, end: int) -> (value: float64, next: int)? {
    var j = i
    if j < end && (b[j] == 43 || b[j] == 45) { j += 1 }
    let digitsFrom = j
    while j < end && b[j] >= 48 && b[j] <= 57 { j += 1 }
    if j < end && b[j] == 46 {
        j += 1
        while j < end && b[j] >= 48 && b[j] <= 57 { j += 1 }
    }
    if j == digitsFrom || (j == digitsFrom + 1 && b[digitsFrom] == 46) { return nil }
    if j < end && (b[j] == 101 || b[j] == 69) {
        var k = j + 1
        if k < end && (b[k] == 43 || b[k] == 45) { k += 1 }
        if k < end && b[k] >= 48 && b[k] <= 57 {
            while k < end && b[k] >= 48 && b[k] <= 57 { k += 1 }
            j = k
        }
    }
    return (value: float64(parseNumber(b, i, j)), next: j)
}

/// Reads the arithmetic in a relative color's calc(): numbers (with
/// angle units), the origin's channel keywords, + - * / and parentheses.
final class CalcReader {
    let b: [uint8]
    var i: int
    let end: int
    let env: [string: float64]

    init(b: [uint8], i: int, end: int, env: [string: float64]) {
        self.b = b
        self.i = i
        self.end = end
        self.env = env
    }

    func skipSpace() {
        while i < end && isSpace(b[i]) { i += 1 }
    }

    func sum() -> float64? {
        guard var v = product() else { return nil }
        while true {
            skipSpace()
            if i < end && (b[i] == 43 || b[i] == 45) {
                let minus = b[i] == 45
                i += 1
                guard let r = product() else { return nil }
                v = minus ? v - r : v + r
            } else {
                return v
            }
        }
    }

    func product() -> float64? {
        guard var v = atom() else { return nil }
        while true {
            skipSpace()
            if i < end && (b[i] == 42 || b[i] == 47) {
                let divide = b[i] == 47
                i += 1
                guard let r = atom() else { return nil }
                if divide && r == 0 { return nil }
                v = divide ? v / r : v * r
            } else {
                return v
            }
        }
    }

    func atom() -> float64? {
        skipSpace()
        if i >= end { return nil }
        if b[i] == 40 {
            i += 1
            guard let v = sum() else { return nil }
            skipSpace()
            if i >= end || b[i] != 41 { return nil }
            i += 1
            return v
        }
        if b[i] == 45 && i + 1 < end && !(b[i + 1] >= 48 && b[i + 1] <= 57) && b[i + 1] != 46 {
            i += 1
            guard let v = atom() else { return nil }
            return -v
        }
        if let n = numberAt(b, i, end) {
            i = n.next
            var j = i
            while j < end && ((b[j] >= 97 && b[j] <= 122) || b[j] == 37) { j += 1 }
            let unit = stringOf(b, i, j)
            i = j
            if unit == "" || unit == "%" { return n.value }
            return degrees(n.value, unit)
        }
        var j = i
        while j < end && ((b[j] >= 97 && b[j] <= 122) || b[j] == 45) { j += 1 }
        let word = stringOf(b, i, j)
        i = j
        return env[word]
    }
}

/// The pieces between a function's parentheses, split at spaces and
/// commas outside nested parentheses; a `/` is a piece of its own.
func colorArgs(b: [uint8], start: int, end: int) -> [string] {
    var out: [string] = []
    var i = start
    while i < end {
        let c = b[i]
        if isSpace(c) || c == 44 { i += 1; continue }
        if c == 47 { out.append("/"); i += 1; continue }
        var j = i
        var depth = 0
        while j < end {
            let d = b[j]
            if d == 40 { depth += 1 }
            else if d == 41 { depth -= 1 }
            else if depth == 0 && (isSpace(d) || d == 44 || d == 47) { break }
            j += 1
        }
        out.append(stringOf(b, i, j))
        i = j
    }
    return out
}

/// The pieces between a function's parentheses split at top-level
/// commas, each trimmed.
func commaArgs(b: [uint8], start: int, end: int) -> [string] {
    var out: [string] = []
    var depth = 0
    var from = start
    var i = start
    while i <= end {
        if i == end || (depth == 0 && b[i] == 44) {
            out.append(stringOf(trimmedBytes(b, from, i), 0, trimmedBytes(b, from, i).count))
            from = i + 1
        } else if b[i] == 40 {
            depth += 1
        } else if b[i] == 41 {
            depth -= 1
        }
        i += 1
    }
    return out
}

func trimmedBytes(b: [uint8], start: int, end: int) -> [uint8] {
    var s = start
    var e = end
    while s < e && isSpace(b[s]) { s += 1 }
    while e > s && isSpace(b[e - 1]) { e -= 1 }
    var out: [uint8] = []
    while s < e { out.append(b[s]); s += 1 }
    return out
}

// MARK: - color-mix() and contrast-color()

/// color-mix([in <space> [<hue> hue]?,] <color> <p>?, <color> <p>?):
/// the two mixed in the space (oklab where none is named), with
/// premultiplied alpha and the hue taken the shorter way by default.
func parseColorMix(b: [uint8], start: int, end: int) -> draw.Color? {
    var parts = commaArgs(b, start, end)
    var space = "oklab"
    var hueMethod = "shorter"
    if !parts.isEmpty && parts[0].hasPrefix("in ") {
        let words = colorArgs([uint8](parts[0].utf8), 0, [uint8](parts[0].utf8).count)
        if words.count < 2 { return nil }
        space = words[1] == "xyz" ? "xyz-d65" : words[1]
        if space == "rgb" || !colorSpaces.contains(space) { return nil }
        if words.count == 4 && words[3] == "hue" && hueIndex(space) >= 0 {
            hueMethod = words[2]
            if hueMethod != "shorter" && hueMethod != "longer" && hueMethod != "increasing" && hueMethod != "decreasing" { return nil }
        } else if words.count != 2 {
            return nil
        }
        parts.removeFirst()
    }
    if parts.count != 2 { return nil }
    guard let one = mixItem(parts[0]), let two = mixItem(parts[1]) else { return nil }
    var p1 = one.percent
    var p2 = two.percent
    if p1 == nil && p2 == nil { p1 = 50; p2 = 50 }
    else if p1 == nil { p1 = 100 - p2! }
    else if p2 == nil { p2 = 100 - p1! }
    var w1 = p1!
    var w2 = p2!
    if w1 < 0 || w2 < 0 || w1 > 100 || w2 > 100 { return nil }
    let total = w1 + w2
    if total == 0 { return nil }
    let alphaScale = total < 100 ? total / 100 : 1
    w1 = w1 / total
    w2 = w2 / total
    var mixed = mixIn(space, hueMethod, one.color, two.color, w2)
    mixed.A = unitByte(float64(mixed.A) / 255 * alphaScale)
    return mixed
}

/// Two colors mixed in a space, t of the way from the first to the
/// second, hues going round as hueMethod says: color-mix(), and a
/// gradient's `in <space>`.
func mixIn(space: string, hueMethod: string, first: draw.Color, second: draw.Color, t: float64) -> draw.Color {
    let w1 = 1 - t
    let w2 = t
    var a = fromSRGB(space, srgbOf(first))
    var c = fromSRGB(space, srgbOf(second))
    let h = hueIndex(space)
    if h >= 0 {
        // An achromatic color's hue is powerless: it takes the other's.
        if powerlessHue(space, a) { a.c[h] = c.c[h] }
        if powerlessHue(space, c) { c.c[h] = a.c[h] }
        var h1 = normalizeHue(a.c[h])
        var h2 = normalizeHue(c.c[h])
        let d = h2 - h1
        switch hueMethod {
        case "shorter":
            if d > 180 { h1 += 360 } else if d < -180 { h2 += 360 }
        case "longer":
            if d > 0 && d < 180 { h1 += 360 } else if d > -180 && d <= 0 { h2 += 360 }
        case "increasing":
            if d < 0 { h2 += 360 }
        default:
            if d > 0 { h1 += 360 }
        }
        a.c[h] = h1
        c.c[h] = h2
    }
    let alpha = a.alpha * w1 + c.alpha * w2
    var out: [float64] = []
    var i = 0
    while i < 3 {
        if i == h {
            out.append(normalizeHue(a.c[i] * w1 + c.c[i] * w2))
        } else {
            let v = a.c[i] * a.alpha * w1 + c.c[i] * c.alpha * w2
            out.append(alpha == 0 ? v : v / alpha)
        }
        i += 1
    }
    return toDrawColor(space, SpaceColor(c: out, alpha: alpha, missing: [false, false, false]))
}

/// One color of a color-mix(), with its percentage before or after it.
func mixItem(s: string) -> (color: draw.Color, percent: float64?)? {
    let b = [uint8](s.utf8)
    let words = colorArgs(b, 0, b.count)
    if words.isEmpty { return nil }
    let last = words[words.count - 1]
    let first = words[0]
    if words.count >= 2, let p = percentOf(last) {
        guard let c = ParseColor(stringOf(b, 0, b.count - [uint8](last.utf8).count)) else { return nil }
        return (color: c, percent: p)
    }
    if words.count >= 2, let p = percentOf(first) {
        guard let c = ParseColor(stringOf(b, [uint8](first.utf8).count, b.count)) else { return nil }
        return (color: c, percent: p)
    }
    guard let c = ParseColor(s) else { return nil }
    return (color: c, percent: nil)
}

func percentOf(s: string) -> float64? {
    let b = [uint8](s.utf8)
    if b.count < 2 || b[b.count - 1] != 37 { return nil }
    guard let n = numberAt(b, 0, b.count - 1), n.next == b.count - 1 else { return nil }
    return n.value
}

func powerlessHue(space: string, c: SpaceColor) -> bool {
    switch space {
    case "hsl": return c.c[1] < 1e-6 || c.c[2] < 1e-6 || c.c[2] > 100 - 1e-6
    case "hwb": return c.c[1] + c.c[2] >= 100 - 1e-6
    case "lch": return c.c[1] < 1e-4
    case "oklch": return c.c[1] < 1e-6
    default: return false
    }
}

func normalizeHue(h: float64) -> float64 {
    var v = h
    while v < 0 { v += 360 }
    while v >= 360 { v -= 360 }
    return v
}

/// contrast-color(): white or black, whichever contrasts more with c.
func contrastColor(c: draw.Color) -> draw.Color {
    let s = srgbOf(c)
    let l = 0.2126 * toLinear(s.c[0]) + 0.7152 * toLinear(s.c[1]) + 0.0722 * toLinear(s.c[2])
    let withWhite = 1.05 / (l + 0.05)
    let withBlack = (l + 0.05) / 0.05
    return withBlack > withWhite ? draw.Color.black : draw.Color.white
}

// MARK: - Conversions

/// An 8-bit color as sRGB channels from 0 to 1.
func srgbOf(c: draw.Color) -> SpaceColor {
    return SpaceColor(c: [float64(c.R) / 255, float64(c.G) / 255, float64(c.B) / 255], alpha: float64(c.A) / 255, missing: [false, false, false])
}

/// A color in a space as an 8-bit sRGB color, clipped to the gamut.
func toDrawColor(space: string, sc: SpaceColor) -> draw.Color {
    // Spaces built on sRGB skip XYZ, whose round trip would round 0.5
    // down.
    var rgb: [float64] = []
    switch space {
    case "srgb": rgb = sc.c
    case "rgb": rgb = [sc.c[0] / 255, sc.c[1] / 255, sc.c[2] / 255]
    case "hsl": rgb = hslToSRGB(sc.c)
    case "hwb": rgb = hwbToSRGB(sc.c)
    default: rgb = gamutMapped(toXYZ(space, sc.c))
    }
    return draw.Color(unitByte(rgb[0]), unitByte(rgb[1]), unitByte(rgb[2]), unitByte(sc.alpha))
}

/// A color (XYZ, D65) in sRGB, brought into its gamut as CSS Color 4
/// maps colors: chroma lowered in OKLCH, keeping lightness and hue,
/// until clipping what is left changes it less than the eye can see.
func gamutMapped(xyz: [float64]) -> [float64] {
    let rgb = fromXYZ("srgb", xyz)
    if inUnitCube(rgb) { return rgb }
    let origin = fromXYZ("oklch", xyz)
    if origin[0] >= 1 { return [1, 1, 1] }
    if origin[0] <= 0 { return [0, 0, 0] }
    let jnd = 0.02
    let epsilon = 0.0001
    func srgbAt(chroma: float64) -> [float64] {
        return fromXYZ("srgb", toXYZ("oklch", [origin[0], chroma, origin[2]]))
    }
    func clipped(c: [float64]) -> [float64] { return mapEach(c, clamp01) }
    func deltaEOK(a: [float64], b: [float64]) -> float64 {
        let la = fromXYZ("oklab", toXYZ("srgb", a))
        let lb = fromXYZ("oklab", toXYZ("srgb", b))
        let d0 = la[0] - lb[0]
        let d1 = la[1] - lb[1]
        let d2 = la[2] - lb[2]
        return math.Sqrt(d0 * d0 + d1 * d1 + d2 * d2)
    }
    var clip = clipped(rgb)
    if deltaEOK(clip, rgb) < jnd { return clip }
    var low = 0.0
    var high = origin[1]
    var lowInGamut = true
    while high - low > epsilon {
        let chroma = (low + high) / 2
        let current = srgbAt(chroma)
        if lowInGamut && inUnitCube(current) {
            low = chroma
            continue
        }
        clip = clipped(current)
        let e = deltaEOK(clip, current)
        if e < jnd {
            if jnd - e < epsilon { return clip }
            lowInGamut = false
            low = chroma
        } else {
            high = chroma
        }
    }
    return clip
}

func inUnitCube(c: [float64]) -> bool {
    let e = 0.000075
    return c[0] >= -e && c[0] <= 1 + e && c[1] >= -e && c[1] <= 1 + e && c[2] >= -e && c[2] <= 1 + e
}

/// An sRGB color (channels 0-1) in another space.
func fromSRGB(space: string, sc: SpaceColor) -> SpaceColor {
    var c: [float64] = []
    switch space {
    case "srgb": c = sc.c
    case "rgb": c = mapEach(sc.c, { v in v * 255 })
    case "hsl": c = srgbToHSL(sc.c)
    case "hwb": c = srgbToHWB(sc.c)
    default: c = fromXYZ(space, toXYZ("srgb", sc.c))
    }
    return SpaceColor(c: c, alpha: sc.alpha, missing: [false, false, false])
}

func unitByte(v: float64) -> uint8 {
    return uint8(clamp01(v) * 255 + 0.5)
}

func clamp01(v: float64) -> float64 {
    if v < 0 { return 0 }
    if v > 1 { return 1 }
    return v
}

func fabs(v: float64) -> float64 { return v < 0 ? -v : v }

func signed(v: float64, magnitude: float64) -> float64 { return v < 0 ? -magnitude : magnitude }

func toLinear(c: float64) -> float64 {
    let a = fabs(c)
    if a <= 0.04045 { return c / 12.92 }
    return signed(c, math.Pow((a + 0.055) / 1.055, 2.4))
}

func fromLinear(c: float64) -> float64 {
    let a = fabs(c)
    if a <= 0.0031308 { return 12.92 * c }
    return signed(c, 1.055 * math.Pow(a, 1 / 2.4) - 0.055)
}

func mul3(m: [float64], v: [float64]) -> [float64] {
    return [
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    ]
}

func mapEach(v: [float64], f: (float64) -> float64) -> [float64] {
    return [f(v[0]), f(v[1]), f(v[2])]
}

// The matrices of CSS Color 4's sample code.
let linSRGBToXYZ: [float64] = [
    0.41239079926595934, 0.357584339383878, 0.1804807884018343,
    0.21263900587151027, 0.715168678767756, 0.07219231536073371,
    0.01933081871559182, 0.11919477979462598, 0.9505321522496607,
]
let xyzToLinSRGB: [float64] = [
    3.2409699419045226, -1.537383177570094, -0.4986107602930034,
    -0.9692436362808796, 1.8759675015077202, 0.04155505740717559,
    0.05563007969699366, -0.20397695888897652, 1.0569715142428786,
]
let linP3ToXYZ: [float64] = [
    0.4865709486482162, 0.26566769316909306, 0.1982172852343625,
    0.2289745640697488, 0.6917385218365064, 0.079286914093745,
    0.0, 0.04511338185890264, 1.043944368900976,
]
let xyzToLinP3: [float64] = [
    2.493496911941425, -0.9313836179191239, -0.40271078445071684,
    -0.8294889695615747, 1.7626640603183463, 0.023624685841943577,
    0.03584583024378447, -0.07617238926804182, 0.9568845240076872,
]
let linA98ToXYZ: [float64] = [
    0.5766690429101305, 0.1855582379065463, 0.1882286462349947,
    0.29734497525053605, 0.6273635662554661, 0.07529145849399788,
    0.02703136138641234, 0.07068885253582723, 0.9913375368376388,
]
let xyzToLinA98: [float64] = [
    2.0415879038107465, -0.5650069742788596, -0.34473135077832956,
    -0.9692436362808795, 1.8759675015077202, 0.04155505740717557,
    0.013444280632031142, -0.11836239223101838, 1.0151749943912054,
]
let linProPhotoToXYZD50: [float64] = [
    0.7977604896723027, 0.13518583717574031, 0.0313493495815248,
    0.2880711282292934, 0.7118432178101014, 0.00008565396060525902,
    0.0, 0.0, 0.8251046025104601,
]
let xyzD50ToLinProPhoto: [float64] = [
    1.3457989731028281, -0.25558010007997534, -0.05110628506753401,
    -0.5446224939028347, 1.5082327413132781, 0.02053603239147973,
    0.0, 0.0, 1.2119675456389454,
]
let lin2020ToXYZ: [float64] = [
    0.6369580483012914, 0.14461690358620832, 0.1688809751641721,
    0.2627002120112671, 0.6779980715188708, 0.05930171646986196,
    0.0, 0.028072693049087428, 1.060985057710791,
]
let xyzToLin2020: [float64] = [
    1.7166511879712674, -0.35567078377639233, -0.25336628137365974,
    -0.6666843518324892, 1.6164812366349395, 0.01576854581391113,
    0.017639857445310783, -0.042770613257808524, 0.9421031212354738,
]
let d50ToD65: [float64] = [
    0.955473421488075, -0.02309845494876471, 0.06325924320057072,
    -0.0283697093338637, 1.0099953980813041, 0.021041441191917323,
    0.012314014864481998, -0.020507649298898964, 1.330365926242124,
]
let d65ToD50: [float64] = [
    1.0479297925449969, 0.022946870601609652, -0.05019226628920524,
    0.02962780877005599, 0.9904344267538799, -0.017073799063418826,
    -0.009243040646204504, 0.015055191490298152, 0.7518742814281371,
]
let xyzToLMS: [float64] = [
    0.8190224379967030, 0.3619062600528904, -0.1288737815209879,
    0.0329836539323885, 0.9292868615863434, 0.0361446663506424,
    0.0481771893596242, 0.2642395317527308, 0.6335478284694309,
]
let lmsToOKLab: [float64] = [
    0.2104542683093140, 0.7936177747023054, -0.0040720430116193,
    1.9779985324311684, -2.4285922420485799, 0.4505937096174110,
    0.0259040424655478, 0.7827717124575296, -0.8086757549230774,
]
let okLabToLMS: [float64] = [
    1.0, 0.3963377773761749, 0.2158037573099136,
    1.0, -0.1055613458156586, -0.0638541728258133,
    1.0, -0.0894841775298119, -1.2914855480194092,
]
let lmsToXYZ: [float64] = [
    1.2268798758459243, -0.5578149944602171, 0.2813910456659647,
    -0.0405757452148008, 1.1122868032803170, -0.0717110580655164,
    -0.0763729366746601, -0.4214933324022432, 1.5869240198367816,
]
let d50White: [float64] = [0.3457 / 0.3585, 1.0, (1.0 - 0.3457 - 0.3585) / 0.3585]

func a98ToLinear(c: float64) -> float64 { return signed(c, math.Pow(fabs(c), 563.0 / 256.0)) }
func a98FromLinear(c: float64) -> float64 { return signed(c, math.Pow(fabs(c), 256.0 / 563.0)) }

func proPhotoToLinear(c: float64) -> float64 {
    let a = fabs(c)
    if a <= 16.0 / 512.0 { return c / 16 }
    return signed(c, math.Pow(a, 1.8))
}

func proPhotoFromLinear(c: float64) -> float64 {
    let a = fabs(c)
    if a >= 1.0 / 512.0 { return signed(c, math.Pow(a, 1 / 1.8)) }
    return 16 * c
}

let rec2020Alpha: float64 = 1.09929682680944
let rec2020Beta: float64 = 0.018053968510807

func rec2020ToLinear(c: float64) -> float64 {
    let a = fabs(c)
    if a < rec2020Beta * 4.5 { return c / 4.5 }
    return signed(c, math.Pow((a + rec2020Alpha - 1) / rec2020Alpha, 1 / 0.45))
}

func rec2020FromLinear(c: float64) -> float64 {
    let a = fabs(c)
    if a > rec2020Beta { return signed(c, rec2020Alpha * math.Pow(a, 0.45) - (rec2020Alpha - 1)) }
    return 4.5 * c
}

let labKappa: float64 = 24389.0 / 27.0
let labEpsilon: float64 = 216.0 / 24389.0

func labToXYZD50(lab: [float64]) -> [float64] {
    let f1 = (lab[0] + 16) / 116
    let f0 = lab[1] / 500 + f1
    let f2 = f1 - lab[2] / 200
    let x = f0 * f0 * f0 > labEpsilon ? f0 * f0 * f0 : (116 * f0 - 16) / labKappa
    let y = lab[0] > labKappa * labEpsilon ? f1 * f1 * f1 : lab[0] / labKappa
    let z = f2 * f2 * f2 > labEpsilon ? f2 * f2 * f2 : (116 * f2 - 16) / labKappa
    return [x * d50White[0], y * d50White[1], z * d50White[2]]
}

func xyzD50ToLab(xyz: [float64]) -> [float64] {
    var f: [float64] = []
    var i = 0
    while i < 3 {
        let t = xyz[i] / d50White[i]
        f.append(t > labEpsilon ? math.Cbrt(t) : (labKappa * t + 16) / 116)
        i += 1
    }
    return [116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])]
}

func polarToLab(lch: [float64]) -> [float64] {
    let h = lch[2] * math.Pi / 180
    return [lch[0], lch[1] * math.Cos(h), lch[1] * math.Sin(h)]
}

func labToPolar(lab: [float64]) -> [float64] {
    let c = math.Sqrt(lab[1] * lab[1] + lab[2] * lab[2])
    let h = c < 1e-9 ? 0 : normalizeHue(math.Atan2(lab[2], lab[1]) * 180 / math.Pi)
    return [lab[0], c, h]
}

/// HSL (s and l 0-100) to sRGB 0-1.
func hslToSRGB(hsl: [float64]) -> [float64] {
    let h = normalizeHue(hsl[0])
    let s = clamp01(hsl[1] / 100)
    let l = clamp01(hsl[2] / 100)
    func f(n: float64) -> float64 {
        var k = n + h / 30
        while k >= 12 { k -= 12 }
        let a = s * (l < 1 - l ? l : 1 - l)
        var m = k - 3
        if 9 - k < m { m = 9 - k }
        if m > 1 { m = 1 }
        if m < -1 { m = -1 }
        return l - a * m
    }
    return [f(0), f(8), f(4)]
}

func srgbToHSL(rgb: [float64]) -> [float64] {
    let mx = rgb[0] > rgb[1] ? (rgb[0] > rgb[2] ? rgb[0] : rgb[2]) : (rgb[1] > rgb[2] ? rgb[1] : rgb[2])
    let mn = rgb[0] < rgb[1] ? (rgb[0] < rgb[2] ? rgb[0] : rgb[2]) : (rgb[1] < rgb[2] ? rgb[1] : rgb[2])
    let l = (mx + mn) / 2
    let d = mx - mn
    var h: float64 = 0
    var s: float64 = 0
    if d > 1e-9 {
        s = (l == 0 || l == 1) ? 0 : (mx - l) / (l < 1 - l ? l : 1 - l)
        if mx == rgb[0] { h = (rgb[1] - rgb[2]) / d + (rgb[1] < rgb[2] ? 6 : 0) }
        else if mx == rgb[1] { h = (rgb[2] - rgb[0]) / d + 2 }
        else { h = (rgb[0] - rgb[1]) / d + 4 }
        h = h * 60
    }
    return [h, s * 100, l * 100]
}

func hwbToSRGB(hwb: [float64]) -> [float64] {
    let w = hwb[1] / 100
    let bl = hwb[2] / 100
    if w + bl >= 1 {
        let g = w / (w + bl)
        return [g, g, g]
    }
    let rgb = hslToSRGB([hwb[0], 100, 50])
    return mapEach(rgb, { v in v * (1 - w - bl) + w })
}

func srgbToHWB(rgb: [float64]) -> [float64] {
    let hsl = srgbToHSL(rgb)
    let mx = rgb[0] > rgb[1] ? (rgb[0] > rgb[2] ? rgb[0] : rgb[2]) : (rgb[1] > rgb[2] ? rgb[1] : rgb[2])
    let mn = rgb[0] < rgb[1] ? (rgb[0] < rgb[2] ? rgb[0] : rgb[2]) : (rgb[1] < rgb[2] ? rgb[1] : rgb[2])
    return [hsl[0], mn * 100, (1 - mx) * 100]
}

/// Channels in a space to CIE XYZ (D65).
func toXYZ(space: string, c: [float64]) -> [float64] {
    switch space {
    case "rgb": return mul3(linSRGBToXYZ, mapEach([c[0] / 255, c[1] / 255, c[2] / 255], toLinear))
    case "srgb": return mul3(linSRGBToXYZ, mapEach(c, toLinear))
    case "srgb-linear": return mul3(linSRGBToXYZ, c)
    case "display-p3": return mul3(linP3ToXYZ, mapEach(c, toLinear))
    case "a98-rgb": return mul3(linA98ToXYZ, mapEach(c, a98ToLinear))
    case "prophoto-rgb": return mul3(d50ToD65, mul3(linProPhotoToXYZD50, mapEach(c, proPhotoToLinear)))
    case "rec2020": return mul3(lin2020ToXYZ, mapEach(c, rec2020ToLinear))
    case "xyz-d50": return mul3(d50ToD65, c)
    case "lab": return mul3(d50ToD65, labToXYZD50(c))
    case "lch": return mul3(d50ToD65, labToXYZD50(polarToLab(c)))
    case "oklab": return mul3(lmsToXYZ, mapEach(mul3(okLabToLMS, c), { v in v * v * v }))
    case "oklch": return mul3(lmsToXYZ, mapEach(mul3(okLabToLMS, polarToLab(c)), { v in v * v * v }))
    case "hsl": return mul3(linSRGBToXYZ, mapEach(hslToSRGB(c), toLinear))
    case "hwb": return mul3(linSRGBToXYZ, mapEach(hwbToSRGB(c), toLinear))
    default: return c // xyz, xyz-d65
    }
}

/// CIE XYZ (D65) to channels in a space.
func fromXYZ(space: string, xyz: [float64]) -> [float64] {
    switch space {
    case "rgb": return mapEach(mapEach(mul3(xyzToLinSRGB, xyz), fromLinear), { v in v * 255 })
    case "srgb": return mapEach(mul3(xyzToLinSRGB, xyz), fromLinear)
    case "srgb-linear": return mul3(xyzToLinSRGB, xyz)
    case "display-p3": return mapEach(mul3(xyzToLinP3, xyz), fromLinear)
    case "a98-rgb": return mapEach(mul3(xyzToLinA98, xyz), a98FromLinear)
    case "prophoto-rgb": return mapEach(mul3(xyzD50ToLinProPhoto, mul3(d65ToD50, xyz)), proPhotoFromLinear)
    case "rec2020": return mapEach(mul3(xyzToLin2020, xyz), rec2020FromLinear)
    case "xyz-d50": return mul3(d65ToD50, xyz)
    case "lab": return xyzD50ToLab(mul3(d65ToD50, xyz))
    case "lch": return labToPolar(xyzD50ToLab(mul3(d65ToD50, xyz)))
    case "oklab": return mul3(lmsToOKLab, mapEach(mul3(xyzToLMS, xyz), math.Cbrt))
    case "oklch": return labToPolar(mul3(lmsToOKLab, mapEach(mul3(xyzToLMS, xyz), math.Cbrt)))
    case "hsl": return srgbToHSL(mapEach(mul3(xyzToLinSRGB, xyz), fromLinear))
    case "hwb": return srgbToHWB(mapEach(mul3(xyzToLinSRGB, xyz), fromLinear))
    default: return xyz
    }
}
