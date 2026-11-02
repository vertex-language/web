package svg

import (
    "image/draw"
    "math"
    "web/css"
)

/// A linear or radial gradient: its stops, its geometry, and the units
/// that geometry is in.
final class Gradient {
    var radial = false
    var boundingBoxUnits = true
    var transform = Matrix.identity
    /// pad, reflect or repeat.
    var spread = "pad"
    var x1: float32 = 0
    var y1: float32 = 0
    var x2: float32 = 1
    var y2: float32 = 0
    var cx: float32 = 0.5
    var cy: float32 = 0.5
    var r: float32 = 0.5
    var fx: float32 = 0.5
    var fy: float32 = 0.5
    var stops: [GradientStop] = []
}

struct GradientStop {
    var offset: float32
    /// Nil for currentColor.
    var color: draw.Color?
    var opacity: float32
}

extension Matrix {
    /// The transform that undoes this one, or nil where it flattens.
    func Inverted() -> Matrix? {
        let det = A * D - B * C
        if det == 0 { return nil }
        return Matrix(D / det, -B / det, -C / det, A / det, (C * F - D * E) / det, (B * E - A * F) / det)
    }
}

/// The id a url(#id) names, and the element it is.
func referenced(v: string, ids: [string: element]) -> element? {
    let b = [uint8](v.utf8)
    var i = 0
    while i < b.count && b[i] != 35 { i += 1 }
    if i >= b.count { return nil }
    var j = i + 1
    while j < b.count && b[j] != 41 && b[j] != 34 && b[j] != 39 { j += 1 }
    return ids[css.stringOf(b, i + 1, j)]
}

/// A url(#id) paint: a gradient, or nil for anything else.
func gradientFill(v: string, ids: [string: element]) -> Fill? {
    guard let e = referenced(v, ids), e.TagName == "lineargradient" || e.TagName == "radialgradient" else { return nil }
    let g = Gradient()
    g.radial = e.TagName == "radialgradient"
    readGradient(e, into: g, ids, depth: 0)
    if g.stops.isEmpty { return noFill }
    return Fill(kind: 3, color: draw.Color.transparent, gradient: g)
}

/// A fraction or a percentage of the box, or a length in user units.
func coordinate(v: string?) -> float32? {
    guard let t = v else { return nil }
    let text = trim(t)
    let b = [uint8](text.utf8)
    if b.isEmpty { return nil }
    let n = css.parseNumber(b, 0, b.count)
    return text.hasSuffix("%") ? n / 100 : n
}

/// A gradient's attributes and stops. What it doesn't say comes from the
/// gradient it links to, whose own say first being read last.
func readGradient(e: element, into g: Gradient, ids: [string: element], depth: int) {
    if depth < 8, let href = e.GetAttribute("href") ?? e.GetAttribute("xlink:href"), let base = referenced(href, ids) {
        readGradient(base, into: g, ids, depth: depth + 1)
    }
    if let u = e.GetAttribute("gradientunits") { g.boundingBoxUnits = u != "userSpaceOnUse" && css.lower(u) != "userspaceonuse" }
    if let t = e.GetAttribute("gradienttransform") { g.transform = parseTransform(t) }
    if let s = e.GetAttribute("spreadmethod") { g.spread = css.lower(trim(s)) }
    if let v = coordinate(e.GetAttribute("x1")) { g.x1 = v }
    if let v = coordinate(e.GetAttribute("y1")) { g.y1 = v }
    if let v = coordinate(e.GetAttribute("x2")) { g.x2 = v }
    if let v = coordinate(e.GetAttribute("y2")) { g.y2 = v }
    if let v = coordinate(e.GetAttribute("cx")) { g.cx = v; g.fx = v }
    if let v = coordinate(e.GetAttribute("cy")) { g.cy = v; g.fy = v }
    if let v = coordinate(e.GetAttribute("r")) { g.r = v }
    if let v = coordinate(e.GetAttribute("fx")) { g.fx = v }
    if let v = coordinate(e.GetAttribute("fy")) { g.fy = v }
    var stops: [GradientStop] = []
    for s in e.Children where s.TagName == "stop" {
        var color = s.GetAttribute("stop-color")
        var opacity = s.GetAttribute("stop-opacity")
        if let style = s.GetAttribute("style") {
            for d in css.ParseDeclarations(style) {
                if d.Property == "stop-color" { color = d.Value }
                if d.Property == "stop-opacity" { opacity = d.Value }
            }
        }
        var stop = GradientStop(offset: coordinate(s.GetAttribute("offset")) ?? 0, color: draw.Color(0, 0, 0), opacity: 1)
        if let c = color {
            let t = trim(c)
            stop.color = css.lower(t) == "currentcolor" ? nil : (css.ParseColor(t) ?? draw.Color(0, 0, 0))
        }
        if let o = coordinate(opacity) { stop.opacity = o < 0 ? 0 : (o > 1 ? 1 : o) }
        // Each offset at least the one before.
        if let last = stops.last, stop.offset < last.offset { stop.offset = last.offset }
        stops.append(stop)
    }
    if !stops.isEmpty { g.stops = stops }
}

extension Gradient {
    /// The color at t along the gradient, spread past its ends.
    func colorAt(t0: float32, currentColor: draw.Color) -> draw.Color {
        var t = t0
        switch spread {
        case "repeat": t = t - math.Floor(t)
        case "reflect":
            let m = t - 2 * math.Floor(t / 2)
            t = m > 1 ? 2 - m : m
        default: t = t < 0 ? 0 : (t > 1 ? 1 : t)
        }
        func colored(s: GradientStop) -> draw.Color { return (s.color ?? currentColor).Faded(s.opacity) }
        if t <= stops[0].offset { return colored(stops[0]) }
        var i = 1
        while i < stops.count {
            if t <= stops[i].offset {
                let a = stops[i - 1]
                let b = stops[i]
                let span = b.offset - a.offset
                let k = span > 0 ? (t - a.offset) / span : 1
                let ca = colored(a)
                let cb = colored(b)
                func mix(x: uint8, y: uint8) -> uint8 { return uint8(float32(x) + (float32(y) - float32(x)) * k + 0.5) }
                return draw.Color(mix(ca.R, cb.R), mix(ca.G, cb.G), mix(ca.B, cb.B), mix(ca.A, cb.A))
            }
            i += 1
        }
        return colored(stops[stops.count - 1])
    }

    /// How far along the gradient a point in its own space is.
    func position(x: float32, y: float32) -> float32 {
        if radial {
            // From the focus through the point to the circle's edge.
            let dx = x - fx
            let dy = y - fy
            if r <= 0 { return 1 }
            let ox = fx - cx
            let oy = fy - cy
            let a = dx * dx + dy * dy
            if a == 0 { return 0 }
            let b = 2 * (dx * ox + dy * oy)
            let c = ox * ox + oy * oy - r * r
            let disc = b * b - 4 * a * c
            if disc < 0 { return 1 }
            let edge = (-b + math.Sqrt(disc)) / (2 * a)
            return edge > 0 ? 1 / edge : 1
        }
        let dx = x2 - x1
        let dy = y2 - y1
        let len = dx * dx + dy * dy
        if len == 0 { return 1 }
        return ((x - x1) * dx + (y - y1) * dy) / len
    }
}

/// A shape's bounding box, as a matrix from the unit square onto it.
func boundingBox(s: Shape) -> Matrix {
    if s.coords.count < 2 { return Matrix.identity }
    var x0 = s.coords[0]
    var x1 = s.coords[0]
    var y0 = s.coords[1]
    var y1 = s.coords[1]
    var i = 2
    while i + 1 < s.coords.count {
        x0 = math.Min(x0, s.coords[i])
        x1 = math.Max(x1, s.coords[i])
        y0 = math.Min(y0, s.coords[i + 1])
        y1 = math.Max(y1, s.coords[i + 1])
        i += 2
    }
    return Matrix(x1 - x0, 0, 0, y1 - y0, x0, y0)
}

/// Fills a path in device pixels with a paint: m takes the shape's user
/// space to device pixels, box the unit square onto the shape.
func fillPath(path: draw.Path, rule: draw.FillRule, paint: Fill, opacity: float32, m: Matrix, box: Matrix, on canvas: draw.Canvas, currentColor: draw.Color) {
    switch paint.kind {
    case 0: return
    case 1: canvas.FillPath(path, rule: rule, currentColor.Faded(opacity))
    case 2: canvas.FillPath(path, rule: rule, paint.color.Faded(opacity))
    case 4:
        guard let p = paint.pattern else { return }
        let b = path.Bounds
        let area = draw.IRect(int32(math.Floor(b.X)), int32(math.Floor(b.Y)), int32(math.Ceil(b.Width)) + 2, int32(math.Ceil(b.Height)) + 2).Intersect(canvas.Clip)
        if area.IsEmpty { return }
        // The tile in user units; drawn once, then repeated over the shape.
        let bw = math.Sqrt(box.A * box.A + box.B * box.B)
        let bh = math.Sqrt(box.C * box.C + box.D * box.D)
        let tileX = p.boundingBoxUnits ? box.E + p.x * bw : p.x
        let tileY = p.boundingBoxUnits ? box.F + p.y * bh : p.y
        let tileW = p.boundingBoxUnits ? p.width * bw : p.width
        let tileH = p.boundingBoxUnits ? p.height * bh : p.height
        if tileW <= 0 || tileH <= 0 { return }
        let toDevice = m.Times(p.transform)
        let scale = math.Sqrt(math.Abs(toDevice.A * toDevice.D - toDevice.B * toDevice.C))
        let pw = int32(math.Ceil(tileW * scale))
        let ph = int32(math.Ceil(tileH * scale))
        if pw <= 0 || ph <= 0 || pw > 4096 || ph > 4096 { return }
        guard let inv = toDevice.Inverted() else { return }
        let tile = draw.Layer(draw.IRect(0, 0, pw, ph))
        var view = Matrix(float32(pw) / tileW, 0, 0, float32(ph) / tileH, 0, 0)
        if let vb = p.viewBox, vb.Width > 0, vb.Height > 0 {
            view = Matrix(float32(pw) / vb.Width, 0, 0, float32(ph) / vb.Height, -vb.X * float32(pw) / vb.Width, -vb.Y * float32(ph) / vb.Height)
        } else if p.contentInBoxUnits {
            view = view.Times(Matrix(bw, 0, 0, bh, 0, 0))
        }
        p.content.drawShapes(on: tile.Canvas, view: view, currentColor: currentColor, fill: nil, fillNone: false, solid: false)
        let layer = draw.Layer(area)
        layer.Canvas.FillPath(path, rule: rule, draw.Color(255, 255, 255))
        layer.Shade { x, y in
            let u = inv.Apply(float32(x) + 0.5, float32(y) + 0.5)
            var tx = (u.x - tileX) - tileW * math.Floor((u.x - tileX) / tileW)
            var ty = (u.y - tileY) - tileH * math.Floor((u.y - tileY) / tileH)
            tx *= float32(pw) / tileW
            ty *= float32(ph) / tileH
            return tile.ColorAt(int32(tx), int32(ty)).Faded(opacity)
        }
        layer.Composite(onto: canvas)
        layer.Free()
        tile.Free()
    default:
        guard let g = paint.gradient else { return }
        let b = path.Bounds
        let area = draw.IRect(int32(math.Floor(b.X)), int32(math.Floor(b.Y)), int32(math.Ceil(b.Width)) + 2, int32(math.Ceil(b.Height)) + 2).Intersect(canvas.Clip)
        if area.IsEmpty { return }
        var toDevice = g.boundingBoxUnits ? m.Times(box) : m
        toDevice = toDevice.Times(g.transform)
        guard let inv = toDevice.Inverted() else { return }
        let layer = draw.Layer(area)
        layer.Canvas.FillPath(path, rule: rule, draw.Color(255, 255, 255))
        layer.Shade { x, y in
            let p = inv.Apply(float32(x) + 0.5, float32(y) + 0.5)
            return g.colorAt(g.position(p.x, p.y), currentColor: currentColor).Faded(opacity)
        }
        layer.Composite(onto: canvas)
        layer.Free()
    }
}

/// A <pattern>: its tile's place and size, and what is drawn on it.
final class Pattern {
    var boundingBoxUnits = true
    var contentInBoxUnits = false
    var x: float32 = 0
    var y: float32 = 0
    var width: float32 = 0
    var height: float32 = 0
    var transform = Matrix.identity
    var viewBox: draw.Rect? = nil
    let content: Drawing

    init(content: Drawing) { self.content = content }
}

/// A url(#id) paint that is a pattern; nil for anything else.
func patternFill(v: string, ids: [string: element]) -> Fill? {
    guard let e = referenced(v, ids), e.TagName == "pattern", nesting < deepestNesting else { return nil }
    nesting += 1
    let d = Drawing(viewBox: nil, stretch: false)
    walk(e, contentContext(), d, ids)
    nesting -= 1
    let p = Pattern(content: d)
    p.boundingBoxUnits = css.lower(e.GetAttribute("patternunits") ?? "") != "userspaceonuse"
    p.contentInBoxUnits = css.lower(e.GetAttribute("patterncontentunits") ?? "") == "objectboundingbox"
    p.x = coordinate(e.GetAttribute("x")) ?? 0
    p.y = coordinate(e.GetAttribute("y")) ?? 0
    p.width = coordinate(e.GetAttribute("width")) ?? 0
    p.height = coordinate(e.GetAttribute("height")) ?? 0
    if let t = e.GetAttribute("patterntransform") { p.transform = parseTransform(t) }
    p.viewBox = viewBoxOf(e)
    return Fill(kind: 4, color: draw.Color.transparent, pattern: p)
}

/// A path cut into dashes, along its contours.
func dashed(path: draw.Path, dashes: [float32], offset: float32) -> draw.Path {
    var out = draw.Path()
    var total: float32 = 0
    for d in dashes { total += d }
    if total <= 0 { return path }
    var c = 0
    while c < path.Starts.count {
        let from = path.Starts[c]
        let to = c + 1 < path.Starts.count ? path.Starts[c + 1] : path.Points.count
        var pts: [draw.Point] = []
        var i = from
        while i < to {
            pts.append(path.Points[i])
            i += 1
        }
        if c < path.Closed.count && path.Closed[c], let first = pts.first { pts.append(first) }
        // Where in the pattern the contour starts.
        var at = offset - total * math.Floor(offset / total)
        var which = 0
        while at >= dashes[which] {
            at -= dashes[which]
            which = (which + 1) % dashes.count
        }
        var left = dashes[which] - at
        var on = which % 2 == 0
        i = 0
        if on, let first = pts.first { out.MoveTo(first.X, first.Y) }
        while i + 1 < pts.count {
            let a = pts[i]
            let b = pts[i + 1]
            let dx = b.X - a.X
            let dy = b.Y - a.Y
            let len = math.Sqrt(dx * dx + dy * dy)
            var done: float32 = 0
            while len - done > left {
                done += left
                let x = a.X + dx * done / len
                let y = a.Y + dy * done / len
                if on { out.LineTo(x, y) } else { out.MoveTo(x, y) }
                on = !on
                which = (which + 1) % dashes.count
                left = dashes[which]
                if left <= 0 { left = 0.001 }
            }
            left -= len - done
            if on { out.LineTo(b.X, b.Y) }
            i += 1
        }
        c += 1
    }
    return out
}

/// How deep clipPaths, masks and <use>s have nested: what stops one that
/// reaches itself.
var nesting = 0
let deepestNesting = 16

/// A clipPath's or mask's content, in the space of what refers to it.
func contentOf(n: element, ids: [string: element]) -> Drawing? {
    if nesting >= deepestNesting { return nil }
    nesting += 1
    let d = Drawing(viewBox: nil, stretch: false)
    let units = n.TagName == "mask" ? n.GetAttribute("maskcontentunits") : n.GetAttribute("clippathunits")
    d.boundingBoxUnits = css.lower(units ?? "") == "objectboundingbox"
    walk(n, contentContext(), d, ids)
    nesting -= 1
    return d
}

/// A nested viewport: the viewBox of an <svg> or <symbol> fitted to a
/// size, as a transform. The whole is x and y's move.
func viewportOf(n: element, width: float32?, height: float32?) -> Matrix {
    var out = Matrix(1, 0, 0, 1, lengthAttribute(n.GetAttribute("x")) ?? 0, lengthAttribute(n.GetAttribute("y")) ?? 0)
    if n.TagName == "symbol" { out = Matrix.identity }
    guard let vb = viewBoxOf(n), vb.Width > 0, vb.Height > 0 else { return out }
    let w = width ?? vb.Width
    let h = height ?? vb.Height
    var sx = w / vb.Width
    var sy = h / vb.Height
    var tx: float32 = 0
    var ty: float32 = 0
    if !(n.GetAttribute("preserveaspectratio") ?? "").hasPrefix("none") {
        let s = sx < sy ? sx : sy
        tx = (w - vb.Width * s) / 2
        ty = (h - vb.Height * s) / 2
        sx = s
        sy = s
    }
    return out.Times(Matrix(sx, 0, 0, sy, tx - vb.X * sx, ty - vb.Y * sy))
}

/// A <use>: what it names, drawn where it is, under its own properties.
func walkUse(n: element, ctx: Context, d: Drawing, ids: [string: element]) {
    if nesting >= deepestNesting { return }
    guard let href = n.GetAttribute("href") ?? n.GetAttribute("xlink:href"), let target = referenced(href, ids) else { return }
    nesting += 1
    var inner = ctx.with(n, ids: ids)
    inner.matrix = inner.matrix.Times(Matrix(1, 0, 0, 1, lengthAttribute(n.GetAttribute("x")) ?? 0, lengthAttribute(n.GetAttribute("y")) ?? 0))
    if target.TagName == "symbol" || target.TagName == "svg" {
        let box = inner.with(target, ids: ids)
        var fitted = box
        fitted.matrix = box.matrix.Times(viewportOf(target, width: lengthAttribute(n.GetAttribute("width")), height: lengthAttribute(n.GetAttribute("height"))))
        walk(target, fitted, d, ids)
    } else {
        // One element: walked as the only child of a holder.
        let holder = element("g")
        holder.Children = [target]
        walk(holder, inner, d, ids)
    }
    nesting -= 1
}
