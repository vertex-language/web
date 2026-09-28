package svg

import (
    "web/css"
    "math"
)

// Path data (SVG 2 section 9.3) and the transform attribute, parsed.

/// Reads path data into commands: every command absolute or relative,
/// implicit repeats, smooth curves reflected, quadratics raised to
/// cubics, arcs turned into cubics. Where the data goes wrong, what came
/// before it stands, as the spec has it.
func parsePath(_ d: string, _ ops: inout [uint8], _ coords: inout [float32]) {
    let b = [uint8](d.utf8)
    var r = NumberReader(bytes: b)
    var cmd: uint8 = 0
    var x: float32 = 0
    var y: float32 = 0
    var startX: float32 = 0
    var startY: float32 = 0
    // The last control point, for S and T.
    var lastCX: float32 = 0
    var lastCY: float32 = 0
    var lastCmd: uint8 = 0
    while true {
        r.skipSeparators()
        if r.atEnd { break }
        let c = b[r.i]
        if isCommand(c) {
            cmd = c
            r.i += 1
        } else if cmd == 0 {
            return
        }
        let rel = cmd >= 97
        let upper = rel ? cmd - 32 : cmd
        switch upper {
        case 77: // M
            guard let nx = r.number(), let ny = r.number() else { return }
            x = rel ? x + nx : nx
            y = rel ? y + ny : ny
            ops.append(opMove)
            coords += [x, y]
            startX = x
            startY = y
            // Pairs after a moveto are linetos.
            cmd = rel ? 108 : 76
        case 76: // L
            guard let nx = r.number(), let ny = r.number() else { return }
            x = rel ? x + nx : nx
            y = rel ? y + ny : ny
            ops.append(opLine)
            coords += [x, y]
        case 72: // H
            guard let nx = r.number() else { return }
            x = rel ? x + nx : nx
            ops.append(opLine)
            coords += [x, y]
        case 86: // V
            guard let ny = r.number() else { return }
            y = rel ? y + ny : ny
            ops.append(opLine)
            coords += [x, y]
        case 67: // C
            guard let a = r.number(), let bb = r.number(), let c2 = r.number(), let dd = r.number(), let e = r.number(), let f = r.number() else { return }
            let c1x = rel ? x + a : a
            let c1y = rel ? y + bb : bb
            let c2x = rel ? x + c2 : c2
            let c2y = rel ? y + dd : dd
            x = rel ? x + e : e
            y = rel ? y + f : f
            ops.append(opCubic)
            coords += [c1x, c1y, c2x, c2y, x, y]
            lastCX = c2x
            lastCY = c2y
        case 83: // S
            guard let c2 = r.number(), let dd = r.number(), let e = r.number(), let f = r.number() else { return }
            let smooth = lastCmd == 67 || lastCmd == 83
            let c1x = smooth ? 2 * x - lastCX : x
            let c1y = smooth ? 2 * y - lastCY : y
            let c2x = rel ? x + c2 : c2
            let c2y = rel ? y + dd : dd
            x = rel ? x + e : e
            y = rel ? y + f : f
            ops.append(opCubic)
            coords += [c1x, c1y, c2x, c2y, x, y]
            lastCX = c2x
            lastCY = c2y
        case 81, 84: // Q, T
            var qx: float32
            var qy: float32
            if upper == 81 {
                guard let a = r.number(), let bb = r.number() else { return }
                qx = rel ? x + a : a
                qy = rel ? y + bb : bb
            } else {
                let smooth = lastCmd == 81 || lastCmd == 84
                qx = smooth ? 2 * x - lastCX : x
                qy = smooth ? 2 * y - lastCY : y
            }
            guard let e = r.number(), let f = r.number() else { return }
            let nx = rel ? x + e : e
            let ny = rel ? y + f : f
            ops.append(opCubic)
            coords += [x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), nx + 2 / 3 * (qx - nx), ny + 2 / 3 * (qy - ny), nx, ny]
            lastCX = qx
            lastCY = qy
            x = nx
            y = ny
        case 65: // A
            guard let rx = r.number(), let ry = r.number(), let rot = r.number(), let large = r.flag(), let sweep = r.flag(),
                  let e = r.number(), let f = r.number() else { return }
            let nx = rel ? x + e : e
            let ny = rel ? y + f : f
            arcTo(x, y, rx, ry, rot, large, sweep, nx, ny, &ops, &coords)
            x = nx
            y = ny
        case 90: // Z
            ops.append(opClose)
            x = startX
            y = startY
        default:
            return
        }
        lastCmd = upper
    }
}

func isCommand(_ c: uint8) -> bool {
    switch c {
    case 77, 109, 76, 108, 72, 104, 86, 118, 67, 99, 83, 115, 81, 113, 84, 116, 65, 97, 90, 122: return true
    default: return false
    }
}

/// Numbers in path data, points lists and transforms: separated by
/// spaces or commas or by nothing where they can't run together
/// (`1.5.5` is two numbers, `1-2` too).
struct NumberReader {
    let bytes: [uint8]
    var i = 0

    init(bytes: [uint8]) {
        self.bytes = bytes
    }

    var atEnd: bool { return i >= bytes.count }

    mutating func skipSeparators() {
        while i < bytes.count && (bytes[i] == 32 || bytes[i] == 9 || bytes[i] == 10 || bytes[i] == 13 || bytes[i] == 44 || bytes[i] == 12) { i += 1 }
    }

    mutating func number() -> float32? {
        skipSeparators()
        let start = i
        if i < bytes.count && (bytes[i] == 43 || bytes[i] == 45) { i += 1 }
        var digits = false
        while i < bytes.count && bytes[i] >= 48 && bytes[i] <= 57 { i += 1; digits = true }
        if i < bytes.count && bytes[i] == 46 {
            i += 1
            while i < bytes.count && bytes[i] >= 48 && bytes[i] <= 57 { i += 1; digits = true }
        }
        if !digits {
            i = start
            return nil
        }
        if i < bytes.count && (bytes[i] == 101 || bytes[i] == 69) {
            var j = i + 1
            if j < bytes.count && (bytes[j] == 43 || bytes[j] == 45) { j += 1 }
            if j < bytes.count && bytes[j] >= 48 && bytes[j] <= 57 {
                while j < bytes.count && bytes[j] >= 48 && bytes[j] <= 57 { j += 1 }
                i = j
            }
        }
        return css.parseNumber(bytes, start, i)
    }

    /// An arc flag: one digit, 0 or 1, with nothing needed after it.
    mutating func flag() -> bool? {
        skipSeparators()
        if i < bytes.count && (bytes[i] == 48 || bytes[i] == 49) {
            let v = bytes[i] == 49
            i += 1
            return v
        }
        return nil
    }
}

/// Every number in a list: points, a viewBox, a transform's arguments.
func numbers(_ s: string) -> [float32] {
    var r = NumberReader(bytes: [uint8](s.utf8))
    var out: [float32] = []
    while let n = r.number() { out.append(n) }
    return out
}

let pi = float32(math.Pi)

/// An elliptical arc from (x1, y1) to (x2, y2) as cubics, a quarter turn
/// at most each (SVG 2 appendix B.2.4, endpoint to center).
func arcTo(_ x1: float32, _ y1: float32, _ rxIn: float32, _ ryIn: float32, _ angle: float32, _ large: bool, _ sweep: bool,
           _ x2: float32, _ y2: float32, _ ops: inout [uint8], _ coords: inout [float32]) {
    var rx = rxIn < 0 ? -rxIn : rxIn
    var ry = ryIn < 0 ? -ryIn : ryIn
    if (x1 == x2 && y1 == y2) { return }
    if rx == 0 || ry == 0 {
        ops.append(opLine)
        coords += [x2, y2]
        return
    }
    let phi = angle * pi / 180
    let cosPhi = math.Cos(phi)
    let sinPhi = math.Sin(phi)
    let dx = (x1 - x2) / 2
    let dy = (y1 - y2) / 2
    let x1p = cosPhi * dx + sinPhi * dy
    let y1p = -sinPhi * dx + cosPhi * dy
    // Radii too small to reach are scaled up until they do.
    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1 {
        let s = math.Sqrt(lambda)
        rx *= s
        ry *= s
    }
    let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    var coef = den > 0 && num > 0 ? math.Sqrt(num / den) : 0
    if large == sweep { coef = -coef }
    let cxp = coef * rx * y1p / ry
    let cyp = -coef * ry * x1p / rx
    let cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2
    let cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2
    let theta1 = math.Atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
    var delta = math.Atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx) - theta1
    if sweep && delta < 0 { delta += 2 * pi }
    if !sweep && delta > 0 { delta -= 2 * pi }
    var pieces = int((delta < 0 ? -delta : delta) / (pi / 2)) + 1
    if pieces > 8 { pieces = 8 }
    let step = delta / float32(pieces)
    let t = 4 / 3 * math.Tan(step / 4)
    var a = theta1
    var k = 0
    while k < pieces {
        let b = a + step
        let cosA = math.Cos(a)
        let sinA = math.Sin(a)
        let cosB = math.Cos(b)
        let sinB = math.Sin(b)
        // The piece on the unit circle, then onto the ellipse.
        let p1x = cosA - t * sinA
        let p1y = sinA + t * cosA
        let p2x = cosB + t * sinB
        let p2y = sinB - t * cosB
        func map(_ ux: float32, _ uy: float32) -> (float32, float32) {
            let ex = ux * rx
            let ey = uy * ry
            return (cosPhi * ex - sinPhi * ey + cx, sinPhi * ex + cosPhi * ey + cy)
        }
        let c1 = map(p1x, p1y)
        let c2 = map(p2x, p2y)
        let end = k == pieces - 1 ? (x2, y2) : map(cosB, sinB)
        ops.append(opCubic)
        coords += [c1.0, c1.1, c2.0, c2.1, end.0, end.1]
        a = b
        k += 1
    }
}

/// A transform attribute: matrix, translate, scale, rotate, skewX and
/// skewY, applied left to right as written.
func parseTransform(_ text: string) -> Matrix {
    var m = Matrix.identity
    let b = [uint8](text.utf8)
    var i = 0
    while i < b.count {
        while i < b.count && !((b[i] >= 97 && b[i] <= 122) || (b[i] >= 65 && b[i] <= 90)) { i += 1 }
        let nameStart = i
        while i < b.count && ((b[i] >= 97 && b[i] <= 122) || (b[i] >= 65 && b[i] <= 90)) { i += 1 }
        let name = css.lower(css.stringOf(b, nameStart, i))
        while i < b.count && b[i] != 40 { i += 1 }
        let argStart = i + 1
        while i < b.count && b[i] != 41 { i += 1 }
        if i >= b.count { break }
        let args = numbers(css.stringOf(b, argStart, i))
        i += 1
        var t = Matrix.identity
        switch name {
        case "matrix":
            if args.count == 6 { t = Matrix(args[0], args[1], args[2], args[3], args[4], args[5]) }
        case "translate":
            if args.count >= 1 { t = Matrix(1, 0, 0, 1, args[0], args.count > 1 ? args[1] : 0) }
        case "scale":
            if args.count >= 1 { t = Matrix(args[0], 0, 0, args.count > 1 ? args[1] : args[0], 0, 0) }
        case "rotate":
            if args.count >= 1 {
                let r = args[0] * pi / 180
                let c = math.Cos(r)
                let s = math.Sin(r)
                t = Matrix(c, s, -s, c, 0, 0)
                if args.count == 3 {
                    t = Matrix(1, 0, 0, 1, args[1], args[2]).Times(t).Times(Matrix(1, 0, 0, 1, -args[1], -args[2]))
                }
            }
        case "skewx":
            if args.count == 1 { t = Matrix(1, 0, math.Tan(args[0] * pi / 180), 1, 0, 0) }
        case "skewy":
            if args.count == 1 { t = Matrix(1, math.Tan(args[0] * pi / 180), 0, 1, 0, 0) }
        default:
            break
        }
        m = m.Times(t)
    }
    return m
}
