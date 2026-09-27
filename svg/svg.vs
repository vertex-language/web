// Package svg draws inline SVG: an <svg> element's shapes, filled into
// the box it lays out as. What it reads: <path> (every command, arcs
// too), <rect>, <circle>, <ellipse>, <polygon> and <polyline>, grouped
// by <g> and moved by `transform`; fills by attribute or style
// (colors, none, currentColor, the first stop of a gradient), fill-rule,
// fill-opacity and opacity; and the viewBox with preserveAspectRatio.
// Strokes, <use>, clipping, masks, filters and text aren't drawn yet.
package svg

import (
    "image/draw"
    "web/css"
    "web/html"
)

/// A 2D affine transform: x' = a x + c y + e, y' = b x + d y + f.
public struct Matrix {
    public var A: float32
    public var B: float32
    public var C: float32
    public var D: float32
    public var E: float32
    public var F: float32

    public init(_ a: float32, _ b: float32, _ c: float32, _ d: float32, _ e: float32, _ f: float32) {
        A = a; B = b; C = c; D = d; E = e; F = f
    }

    public static let identity = Matrix(1, 0, 0, 1, 0, 0)

    /// This transform after another: other first, then self.
    public func Times(_ o: Matrix) -> Matrix {
        return Matrix(A * o.A + C * o.B, B * o.A + D * o.B,
                      A * o.C + C * o.D, B * o.C + D * o.D,
                      A * o.E + C * o.F + E, B * o.E + D * o.F + F)
    }

    public func Apply(_ x: float32, _ y: float32) -> (x: float32, y: float32) {
        return (x: A * x + C * y + E, y: B * x + D * y + F)
    }
}

/// How a shape is filled.
struct Fill {
    /// 0 none, 1 the current color, 2 Color.
    var kind: int
    var color: draw.Color
}

let noFill = Fill(kind: 0, color: draw.Color.transparent)
let currentFill = Fill(kind: 1, color: draw.Color.transparent)
let blackFill = Fill(kind: 2, color: draw.Color(0, 0, 0))

/// Path commands, as the shape keeps them.
let opMove: uint8 = 0
let opLine: uint8 = 1
let opCubic: uint8 = 2
let opClose: uint8 = 3

/// One shape: its outline in user units (commands, and their points),
/// the transform to the drawing's user space, and how it's filled.
struct Shape {
    var ops: [uint8]
    var coords: [float32]
    var matrix: Matrix
    var fill: Fill
    var rule: draw.FillRule
    var opacity: float32
    /// Whether no element on the way down set a fill: the <svg>
    /// element's CSS fill decides it.
    var fillInherited: bool
}

/// An <svg> element's shapes, ready to draw into a box.
public final class Drawing {
    /// The viewBox, or nil where it has none.
    public let ViewBox: draw.Rect?
    /// preserveAspectRatio="none": stretch to the box.
    let stretch: bool
    var shapes: [Shape] = []

    init(viewBox: draw.Rect?, stretch: bool) {
        ViewBox = viewBox
        self.stretch = stretch
    }

    public var IsEmpty: bool { return shapes.isEmpty }

    /// Draws into a rectangle in device pixels: the viewBox fitted to it
    /// (centered, keeping its proportions, unless stretched); without one,
    /// user units at `scale` device pixels each. `fill` is what the
    /// <svg> element's own CSS fill resolved to, nil for the default.
    public func Render(on canvas: draw.Canvas, into r: draw.Rect, scale: float32, currentColor: draw.Color, fill: draw.Color?, fillNone: bool) {
        if shapes.isEmpty || r.Width <= 0 || r.Height <= 0 { return }
        var view = Matrix(scale, 0, 0, scale, r.X, r.Y)
        if let vb = ViewBox, vb.Width > 0, vb.Height > 0 {
            var sx = r.Width / vb.Width
            var sy = r.Height / vb.Height
            var tx = r.X
            var ty = r.Y
            if !stretch {
                let s = sx < sy ? sx : sy
                tx += (r.Width - vb.Width * s) / 2
                ty += (r.Height - vb.Height * s) / 2
                sx = s
                sy = s
            }
            view = Matrix(sx, 0, 0, sy, tx - vb.X * sx, ty - vb.Y * sy)
        }
        var clipped = canvas
        clipped.ClipTo(draw.IRect(int32(r.X), int32(r.Y), int32(r.Width + 1), int32(r.Height + 1)))
        for s in shapes {
            var color: draw.Color
            switch s.fill.kind {
            case 0:
                continue
            case 1:
                color = currentColor
            default:
                color = s.fill.color
            }
            // The <svg> element's CSS fill stands in for a shape that
            // says nothing of its own.
            if s.fillInherited {
                if fillNone { continue }
                if let f = fill { color = f }
            }
            if s.opacity < 1 { color = color.Faded(s.opacity) }
            let m = view.Times(s.matrix)
            var path = draw.Path()
            var i = 0
            var k = 0
            while i < s.ops.count {
                switch s.ops[i] {
                case opMove:
                    let p = m.Apply(s.coords[k], s.coords[k + 1])
                    path.MoveTo(p.x, p.y)
                    k += 2
                case opLine:
                    let p = m.Apply(s.coords[k], s.coords[k + 1])
                    path.LineTo(p.x, p.y)
                    k += 2
                case opCubic:
                    let c1 = m.Apply(s.coords[k], s.coords[k + 1])
                    let c2 = m.Apply(s.coords[k + 2], s.coords[k + 3])
                    let p = m.Apply(s.coords[k + 4], s.coords[k + 5])
                    path.CubicTo(c1.x, c1.y, c2.x, c2.y, p.x, p.y)
                    k += 6
                default:
                    path.Close()
                }
                i += 1
            }
            clipped.FillPath(path, rule: s.rule, color)
        }
    }
}

/// What an <svg> element draws.
public func Parse(_ root: html.Node) -> Drawing {
    let d = Drawing(viewBox: viewBoxOf(root), stretch: (root.GetAttribute("preserveaspectratio") ?? "").hasPrefix("none"))
    var ctx = Context(matrix: Matrix.identity, fill: blackFill, fillInherited: true, rule: .nonZero, opacity: 1)
    ctx = ctx.with(root, ids: [:])
    var ids: [string: html.Node] = [:]
    collectIds(root, &ids)
    walk(root, ctx, d, ids)
    return d
}

/// The size an <svg> lays out at before CSS: its width and height
/// attributes in pixels; one of them and the viewBox's proportions; or
/// 300 by 150, as for any replaced element, shaped by the viewBox.
/// Whether an <svg> has a ratio from its viewBox but neither a width nor
/// a height: CSS then sizes it to the room it has, not to 300 by 150.
public func HasRatioOnly(_ root: html.Node) -> bool {
    if lengthAttribute(root.GetAttribute("width")) != nil || lengthAttribute(root.GetAttribute("height")) != nil { return false }
    if let vb = viewBoxOf(root), vb.Width > 0, vb.Height > 0 { return true }
    return false
}

public func IntrinsicSize(_ root: html.Node) -> (width: float32, height: float32) {
    let w = lengthAttribute(root.GetAttribute("width"))
    let h = lengthAttribute(root.GetAttribute("height"))
    let vb = viewBoxOf(root)
    if let w = w, let h = h { return (width: w, height: h) }
    if let vb = vb, vb.Width > 0, vb.Height > 0 {
        if let w = w { return (width: w, height: w * vb.Height / vb.Width) }
        if let h = h { return (width: h * vb.Width / vb.Height, height: h) }
        return (width: 300, height: 300 * vb.Height / vb.Width)
    }
    return (width: w ?? 300, height: h ?? 150)
}

/// What a group passes down to what's inside it.
struct Context {
    var matrix: Matrix
    var fill: Fill
    var fillInherited: bool
    var rule: draw.FillRule
    var opacity: float32

    /// The context inside an element: its transform, and the fill
    /// properties it sets by attribute or style.
    func with(_ n: html.Node, ids: [string: html.Node]) -> Context {
        var c = self
        if let t = n.GetAttribute("transform") { c.matrix = matrix.Times(parseTransform(t)) }
        var props: [(string, string)] = []
        for name in ["fill", "fill-rule", "fill-opacity", "opacity"] {
            if let v = n.GetAttribute(name) { props.append((name, v)) }
        }
        if let style = n.GetAttribute("style") {
            for decl in css.ParseDeclarations(style) { props.append((decl.Property, decl.Value)) }
        }
        for (name, raw) in props {
            let v = css.lower(trim(raw))
            switch name {
            case "fill":
                c.fillInherited = false
                if v == "none" || v == "transparent" {
                    c.fill = noFill
                } else if v == "currentcolor" {
                    c.fill = currentFill
                } else if v.hasPrefix("url(") {
                    c.fill = gradientFill(v, ids) ?? currentFill
                } else if let color = css.ParseColor(v) {
                    c.fill = Fill(kind: 2, color: color)
                } else if v == "inherit" {
                    c.fillInherited = fillInherited
                }
            case "fill-rule":
                c.rule = v == "evenodd" ? .evenOdd : .nonZero
            case "fill-opacity", "opacity":
                let b = [uint8](v.utf8)
                var o = css.parseNumber(b, 0, b.count)
                if v.hasSuffix("%") { o /= 100 }
                if o < 0 { o = 0 }
                if o > 1 { o = 1 }
                c.opacity *= o
            default:
                break
            }
        }
        return c
    }
}

/// A url(#id) fill: a gradient's first stop color, until gradients are
/// drawn as gradients.
func gradientFill(_ v: string, _ ids: [string: html.Node]) -> Fill? {
    let b = [uint8](v.utf8)
    var i = 0
    while i < b.count && b[i] != 35 { i += 1 }
    var j = i + 1
    while j < b.count && b[j] != 41 && b[j] != 34 && b[j] != 39 { j += 1 }
    if i >= b.count { return nil }
    guard let g = ids[css.stringOf(b, i + 1, j)] else { return nil }
    for stop in g.Children where stop.Kind == html.NodeKind.element && stop.TagName == "stop" {
        var color = stop.GetAttribute("stop-color")
        if let style = stop.GetAttribute("style") {
            for d in css.ParseDeclarations(style) where d.Property == "stop-color" { color = d.Value }
        }
        if let c = color, let parsed = css.ParseColor(trim(c)) { return Fill(kind: 2, color: parsed) }
    }
    return nil
}

func collectIds(_ n: html.Node, _ ids: inout [string: html.Node]) {
    for c in n.Children where c.Kind == html.NodeKind.element {
        if let id = c.GetAttribute("id") { ids[id] = c }
        collectIds(c, &ids)
    }
}

/// The shapes under an element, into the drawing.
func walk(_ n: html.Node, _ ctx: Context, _ d: Drawing, _ ids: [string: html.Node]) {
    for c in n.Children where c.Kind == html.NodeKind.element {
        switch c.TagName {
        case "defs", "clippath", "mask", "lineargradient", "radialgradient", "pattern", "symbol", "marker",
             "title", "desc", "metadata", "style", "script", "filter", "text", "foreignobject":
            continue
        case "g", "a", "switch":
            if isHidden(c) { continue }
            walk(c, ctx.with(c, ids: ids), d, ids)
        case "svg":
            walk(c, ctx.with(c, ids: ids), d, ids)
        default:
            if isHidden(c) { continue }
            let inner = ctx.with(c, ids: ids)
            var ops: [uint8] = []
            var coords: [float32] = []
            outline(c, &ops, &coords)
            if ops.isEmpty || inner.fill.kind == 0 { continue }
            d.shapes.append(Shape(ops: ops, coords: coords, matrix: inner.matrix, fill: inner.fill, rule: inner.rule,
                                  opacity: inner.opacity, fillInherited: inner.fillInherited))
        }
    }
}

func isHidden(_ n: html.Node) -> bool {
    if n.GetAttribute("display") == "none" || n.GetAttribute("visibility") == "hidden" { return true }
    if let style = n.GetAttribute("style") {
        let s = css.lower(style)
        if s.contains("display:none") || s.contains("display: none") { return true }
    }
    return false
}

/// A shape element's outline, as path commands.
func outline(_ n: html.Node, _ ops: inout [uint8], _ coords: inout [float32]) {
    func num(_ name: string) -> float32 { return lengthAttribute(n.GetAttribute(name)) ?? 0 }
    switch n.TagName {
    case "path":
        parsePath(n.GetAttribute("d") ?? "", &ops, &coords)
    case "rect":
        let x = num("x")
        let y = num("y")
        let w = num("width")
        let h = num("height")
        if w <= 0 || h <= 0 { return }
        var rx = lengthAttribute(n.GetAttribute("rx"))
        var ry = lengthAttribute(n.GetAttribute("ry"))
        if rx == nil { rx = ry }
        if ry == nil { ry = rx }
        let ex = smaller(rx ?? 0, w / 2)
        let ey = smaller(ry ?? 0, h / 2)
        if ex <= 0 || ey <= 0 {
            ops += [opMove, opLine, opLine, opLine, opClose]
            coords += [x, y, x + w, y, x + w, y + h, x, y + h]
            return
        }
        let k: float32 = 0.5523
        ops.append(opMove); coords += [x + ex, y]
        ops.append(opLine); coords += [x + w - ex, y]
        ops.append(opCubic); coords += [x + w - ex + ex * k, y, x + w, y + ey - ey * k, x + w, y + ey]
        ops.append(opLine); coords += [x + w, y + h - ey]
        ops.append(opCubic); coords += [x + w, y + h - ey + ey * k, x + w - ex + ex * k, y + h, x + w - ex, y + h]
        ops.append(opLine); coords += [x + ex, y + h]
        ops.append(opCubic); coords += [x + ex - ex * k, y + h, x, y + h - ey + ey * k, x, y + h - ey]
        ops.append(opLine); coords += [x, y + ey]
        ops.append(opCubic); coords += [x, y + ey - ey * k, x + ex - ex * k, y, x + ex, y]
        ops.append(opClose)
    case "circle", "ellipse":
        let cx = num("cx")
        let cy = num("cy")
        var rx = n.TagName == "circle" ? num("r") : num("rx")
        var ry = n.TagName == "circle" ? rx : num("ry")
        if n.TagName == "ellipse" {
            if rx <= 0 { rx = ry }
            if ry <= 0 { ry = rx }
        }
        if rx <= 0 || ry <= 0 { return }
        let k: float32 = 0.5523
        ops.append(opMove); coords += [cx + rx, cy]
        ops.append(opCubic); coords += [cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry]
        ops.append(opCubic); coords += [cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy]
        ops.append(opCubic); coords += [cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry]
        ops.append(opCubic); coords += [cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy]
        ops.append(opClose)
    case "polygon", "polyline":
        let pts = numbers(n.GetAttribute("points") ?? "")
        if pts.count < 4 { return }
        var i = 0
        while i + 1 < pts.count {
            ops.append(i == 0 ? opMove : opLine)
            coords += [pts[i], pts[i + 1]]
            i += 2
        }
        ops.append(opClose)
    default:
        return
    }
}

func smaller(_ a: float32, _ b: float32) -> float32 { return a < b ? a : b }

/// The viewBox: min-x, min-y, width, height.
func viewBoxOf(_ n: html.Node) -> draw.Rect? {
    guard let v = n.GetAttribute("viewbox") else { return nil }
    let parts = numbers(v)
    if parts.count != 4 || parts[2] <= 0 || parts[3] <= 0 { return nil }
    return draw.Rect(parts[0], parts[1], parts[2], parts[3])
}

/// A width, height or coordinate attribute in user units: a number,
/// with px or nothing after it. Percentages and other units are nil.
func lengthAttribute(_ v: string?) -> float32? {
    guard let s = v else { return nil }
    let t = trim(s)
    let b = [uint8](t.utf8)
    if b.isEmpty { return nil }
    var end = 0
    while end < b.count && ((b[end] >= 48 && b[end] <= 57) || b[end] == 46 || b[end] == 45 || b[end] == 43 || b[end] == 101 || b[end] == 69) { end += 1 }
    if end == 0 { return nil }
    let rest = css.lower(css.stringOf(b, end, b.count))
    if !rest.isEmpty && rest != "px" { return nil }
    return css.parseNumber(b, 0, end)
}

func trim(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var i = 0
    var j = b.count
    while i < j && (b[i] == 32 || b[i] == 9 || b[i] == 10 || b[i] == 13) { i += 1 }
    while j > i && (b[j - 1] == 32 || b[j - 1] == 9 || b[j - 1] == 10 || b[j - 1] == 13) { j -= 1 }
    return css.stringOf(b, i, j)
}
