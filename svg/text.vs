package svg

import (
    "image/draw"
    "math"
    "text/font"
    "web/css"
)

/// A run of <text>: its characters, where it starts in user units, and
/// how it is set.
struct TextRun {
    var text: string
    var x: float32
    var y: float32
    var spec: font.Spec
    var anchor: string
    /// <textPath>: the points of the path it runs along, and how far along it
    /// starts, in user units.
    var along: [(x: float32, y: float32)] = []
    var startOffset: float32 = 0
}

/// The families a font-family names, unquoted.
func familiesOf(v: string) -> [string] {
    var out: [string] = []
    for part in v.split(separator: ",") {
        var name = trim(string(part))
        if name.hasPrefix("\"") || name.hasPrefix("'") { name = string(name.dropFirst().dropLast()) }
        if !name.isEmpty { out.append(name) }
    }
    return out.isEmpty ? ["sans-serif"] : out
}

func weightOf(v: string, current: int32) -> int32 {
    switch v {
    case "normal": return 400
    case "bold": return 700
    case "bolder": return current + 300 > 900 ? 900 : current + 300
    case "lighter": return current - 300 < 100 ? 100 : current - 300
    default:
        let b = [uint8](v.utf8)
        let n = css.parseNumber(b, 0, b.count)
        return n >= 1 && n <= 1000 ? int32(n) : current
    }
}

/// A <text>'s characters and <tspan>s as runs, each going on from where
/// the last ended unless it says where to start. Spaces collapse, as
/// SVG's default white-space does.
func walkText(n: element, ctx: Context, d: Drawing, ids: [string: element]) {
    var x = lengthAttribute(n.GetAttribute("x")) ?? 0
    var y = lengthAttribute(n.GetAttribute("y")) ?? 0
    x += lengthAttribute(n.GetAttribute("dx")) ?? 0
    y += lengthAttribute(n.GetAttribute("dy")) ?? 0
    var runs: [Shape] = []
    collectText(n, ctx, &runs, &x, &y, ids, atStart: true)
    // text-anchor moves the whole line.
    if ctx.anchor == "middle" || ctx.anchor == "end" {
        var width: float32 = 0
        for r in runs { width += font.Load(r.text!.spec).Shape(r.text!.text).Width }
        let shift = ctx.anchor == "middle" ? width / 2 : width
        var i = 0
        while i < runs.count {
            runs[i].text!.x -= shift
            i += 1
        }
    }
    for r in runs { d.shapes.append(r) }
}

func collectText(n: element, ctx: Context, runs: inout [Shape], x: inout float32, y: inout float32, ids: [string: element], atStart: bool,
                 along: [(x: float32, y: float32)] = [], startOffset: float32 = 0) {
    var first = atStart
    for c in n.Children {
        if c.TagName == "#text" {
            let words = collapsed(c.Text, keepLeading: !first)
            if words.isEmpty { continue }
            first = false
            var run = TextRun(text: words, x: x, y: y, spec: ctx.spec, anchor: ctx.anchor)
            run.along = along
            run.startOffset = startOffset
            runs.append(Shape(ops: [], coords: [], matrix: ctx.matrix, fill: ctx.fill, rule: ctx.rule, opacity: ctx.opacity,
                              fillInherited: ctx.fillInherited, stroke: ctx.stroke, strokeStyle: ctx.strokeStyle, strokeOpacity: ctx.strokeOpacity,
                              clips: ctx.clips, masks: ctx.masks, clipRule: ctx.clipRule, dashes: ctx.dashes, dashOffset: ctx.dashOffset, text: run))
            x += font.Load(ctx.spec).Shape(words).Width
        } else if c.TagName == "textpath" {
            // The path it names, in its own units, as points.
            guard let href = c.GetAttribute("href") ?? c.GetAttribute("xlink:href"), let target = referenced(href, ids) else { continue }
            var ops: [uint8] = []
            var coords: [float32] = []
            outline(target, &ops, &coords)
            let points = flattened(ops, coords)
            var offset = coordinate(c.GetAttribute("startoffset")) ?? 0
            if (c.GetAttribute("startoffset") ?? "").hasSuffix("%") { offset *= pathLength(points) }
            collectText(c, ctx.with(c, ids: ids), &runs, &x, &y, ids, atStart: first, along: points, startOffset: offset)
            first = false
        } else if c.TagName == "tspan" || c.TagName == "a" {
            if isHidden(c) { continue }
            if let v = lengthAttribute(c.GetAttribute("x")) { x = v }
            if let v = lengthAttribute(c.GetAttribute("y")) { y = v }
            x += lengthAttribute(c.GetAttribute("dx")) ?? 0
            y += lengthAttribute(c.GetAttribute("dy")) ?? 0
            collectText(c, ctx.with(c, ids: ids), &runs, &x, &y, ids, atStart: first, along: along, startOffset: startOffset)
            first = false
        }
    }
}

/// A path's commands as points along it.
func flattened(ops: [uint8], coords: [float32]) -> [(x: float32, y: float32)] {
    var out: [(x: float32, y: float32)] = []
    var k = 0
    for op in ops {
        switch op {
        case opMove, opLine:
            out.append((x: coords[k], y: coords[k + 1]))
            k += 2
        case opCubic:
            guard let p0 = out.last else { break }
            var i: float32 = 1
            while i <= 16 {
                let t = i / 16
                let u = 1 - t
                out.append((x: u * u * u * p0.x + 3 * u * u * t * coords[k] + 3 * u * t * t * coords[k + 2] + t * t * t * coords[k + 4],
                            y: u * u * u * p0.y + 3 * u * u * t * coords[k + 1] + 3 * u * t * t * coords[k + 3] + t * t * t * coords[k + 5]))
                i += 1
            }
            k += 6
        default:
            break
        }
    }
    return out
}

func pathLength(points: [(x: float32, y: float32)]) -> float32 {
    var total: float32 = 0
    var i = 1
    while i < points.count {
        let dx = points[i].x - points[i - 1].x
        let dy = points[i].y - points[i - 1].y
        total += math.Sqrt(dx * dx + dy * dy)
        i += 1
    }
    return total
}

/// Where a distance along points falls, and which way the path goes there;
/// nil past its end.
func pointAlong(points: [(x: float32, y: float32)], at distance: float32) -> (x: float32, y: float32, angle: float32)? {
    if distance < 0 { return nil }
    var left = distance
    var i = 1
    while i < points.count {
        let dx = points[i].x - points[i - 1].x
        let dy = points[i].y - points[i - 1].y
        let len = math.Sqrt(dx * dx + dy * dy)
        if left <= len && len > 0 {
            return (x: points[i - 1].x + dx * left / len, y: points[i - 1].y + dy * left / len, angle: math.Atan2(dy, dx))
        }
        left -= len
        i += 1
    }
    return nil
}

/// A text run's glyphs as an outline in device pixels.
func textOutline(t: TextRun, m: Matrix) -> draw.Path {
    let det = m.A * m.D - m.B * m.C
    let unit = math.Sqrt(det < 0 ? -det : det)
    let run = font.Load(t.spec).Shape(t.text)
    let frame = math.Atan2(m.B, m.A)
    var path = draw.Path()
    var pen: float32 = 0
    var i = 0
    while i < run.Glyphs.count {
        let adv = run.Advances[i]
        if t.along.isEmpty {
            let p = m.Apply(t.x + pen, t.y)
            font.AppendOutline(&path, face: run.Faces[i], glyph: run.Glyphs[i], x: p.x, baseline: p.y, scale: unit, turn: frame)
        } else if let at = pointAlong(t.along, at: t.startOffset + t.x + pen + adv / 2) {
            // Its middle on the path, turned with it.
            let turn = at.angle + frame
            let p = m.Apply(at.x, at.y)
            font.AppendOutline(&path, face: run.Faces[i], glyph: run.Glyphs[i], x: p.x - math.Cos(turn) * adv / 2 * unit, baseline: p.y - math.Sin(turn) * adv / 2 * unit, scale: unit, turn: turn)
        }
        pen += adv
        i += 1
    }
    return path
}

/// Runs of white space made one; a leading one dropped at a line's start.
func collapsed(s: string, keepLeading: bool) -> string {
    var out: [uint8] = []
    var space = !keepLeading
    for b in s.utf8 {
        if b == 32 || b == 9 || b == 10 || b == 13 {
            if !space { out.append(32) }
            space = true
        } else {
            out.append(b)
            space = false
        }
    }
    return css.stringOf(out, 0, out.count)
}

/// Draws a run. With only a scale and a move it is drawn straight, sharp;
/// turned or skewed, it is drawn flat apart and put back through m.
func drawText(t: TextRun, m: Matrix, on canvas: draw.Canvas, paint: Fill, opacity: float32, currentColor: draw.Color) {
    let det = m.A * m.D - m.B * m.C
    let scale = math.Sqrt(det < 0 ? -det : det)
    if scale <= 0 { return }
    let face = font.Load(t.spec)
    let run = face.Shape(t.text)
    var color = paint.kind == 1 ? currentColor : paint.color
    if paint.kind == 3, let g = paint.gradient, let s = g.stops.first { color = s.color ?? currentColor }
    color = color.Faded(opacity)
    let straight = m.B == 0 && m.C == 0 && m.A > 0 && m.D == m.A
    if straight {
        let p = m.Apply(t.x, t.y)
        font.DrawRun(canvas: canvas, run: run, x: p.x, baseline: p.y, scale: scale, color: color)
        return
    }
    let w = int32(math.Ceil(run.Width * scale)) + 4
    let h = int32(math.Ceil(face.LineHeight * scale)) + 4
    if w <= 0 || h <= 0 { return }
    let base = int32(math.Ceil(face.Ascent * scale)) + 2
    let layer = draw.Layer(draw.IRect(0, 0, w, h))
    font.DrawRun(canvas: layer.Canvas, run: run, x: 2, baseline: float32(base), scale: scale, color: color)
    // From the flat layer back to the page: its pen at the run's start.
    let toUser = Matrix(1 / scale, 0, 0, 1 / scale, t.x - 2 / scale, t.y - float32(base) / scale)
    let full = m.Times(toUser)
    layer.Composite(onto: canvas, transform: draw.Affine(full.A, full.B, full.C, full.D, full.E, full.F), blend: .normal)
    layer.Free()
}
