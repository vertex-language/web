// Package svg draws SVG: an inline <svg> element's shapes, or an SVG
// file's (read with encoding/xml) that an <img> shows, filled into the
// box it lays out as. What it reads: <path> (every command, arcs
// too), <rect>, <circle>, <ellipse>, <polygon> and <polyline>, grouped
// by <g>, repeated by <use> and <symbol>, and moved by `transform`; fills
// by attribute or style (colors, none, currentColor, linear and radial
// gradients), fill-rule, fill-opacity and opacity; strokes (stroke,
// stroke-width, stroke-linecap, stroke-linejoin, stroke-miterlimit,
// stroke-opacity) of those and <line>; clip-path and mask by url(); <text>
// and <tspan>; and the viewBox with preserveAspectRatio. Dashes, filters,
// patterns and text on a path aren't drawn yet.
package svg

import (
    "encoding/xml"
    "image/draw"
    "math"
    "text/font"
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

    public init(a: float32, b: float32, c: float32, d: float32, e: float32, f: float32) {
        A = a; B = b; C = c; D = d; E = e; F = f
    }

    public static let identity = Matrix(1, 0, 0, 1, 0, 0)

    /// This transform after another: other first, then self.
    public func Times(o: Matrix) -> Matrix {
        return Matrix(A * o.A + C * o.B, B * o.A + D * o.B,
                      A * o.C + C * o.D, B * o.C + D * o.D,
                      A * o.E + C * o.F + E, B * o.E + D * o.F + F)
    }

    public func Apply(x: float32, y: float32) -> (x: float32, y: float32) {
        return (x: A * x + C * y + E, y: B * x + D * y + F)
    }
}

/// How a shape is filled.
struct Fill {
    /// 0 none, 1 the current color, 2 Color, 3 Gradient.
    var kind: int
    var color: draw.Color
    var gradient: Gradient? = nil
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
    var stroke: Fill
    var strokeStyle: draw.Stroke
    var strokeOpacity: float32
    /// What it is cut to and masked by; clip-rule, for a shape in a clip.
    var clips: [Drawing] = []
    var masks: [Drawing] = []
    var clipRule: draw.FillRule = .nonZero
    /// paint-order: the stroke goes down before the fill.
    var strokeFirst: bool = false
    /// A <text> run instead of an outline.
    var text: TextRun? = nil
}

/// An <svg> element's shapes, ready to draw into a box.
public final class Drawing {
    /// The viewBox, or nil where it has none.
    public let ViewBox: draw.Rect?
    /// preserveAspectRatio="none": stretch to the box.
    let stretch: bool
    var shapes: [Shape] = []
    /// A clipPath's or mask's units: its content is in fractions of what
    /// it applies to.
    var boundingBoxUnits: bool = false

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
        drawShapes(on: clipped, view: view, currentColor: currentColor, fill: fill, fillNone: fillNone, solid: false)
    }

    /// Draws the shapes through a view. Solid draws them opaque in black,
    /// fills only: a clipPath's content.
    func drawShapes(on canvas: draw.Canvas, view: Matrix, currentColor: draw.Color, fill: draw.Color?, fillNone: bool, solid: bool) {
        for s in shapes {
            let m = view.Times(s.matrix)
            if s.clips.isEmpty && s.masks.isEmpty {
                drawShape(s, m, on: canvas, currentColor: currentColor, fill: fill, fillNone: fillNone, solid: solid)
                continue
            }
            // Apart, then cut, then put back.
            let area = reach(s, m).Intersect(canvas.Clip)
            if area.IsEmpty { continue }
            let layer = draw.Layer(area)
            drawShape(s, m, on: layer.Canvas, currentColor: currentColor, fill: fill, fillNone: fillNone, solid: solid)
            let box = boundingBox(s)
            for c in s.clips {
                let alpha = draw.Layer(area)
                c.drawShapes(on: alpha.Canvas, view: c.boundingBoxUnits ? m.Times(box) : m, currentColor: currentColor, fill: nil, fillNone: false, solid: true)
                layer.MaskBy(alpha)
                alpha.Free()
            }
            for k in s.masks {
                let lum = draw.Layer(area)
                k.drawShapes(on: lum.Canvas, view: k.boundingBoxUnits ? m.Times(box) : m, currentColor: currentColor, fill: nil, fillNone: false, solid: false)
                layer.MaskByLuminance(lum)
                lum.Free()
            }
            layer.Composite(onto: canvas)
            layer.Free()
        }
    }

    /// One shape's fill and stroke, m taking it to device pixels.
    func drawShape(s: Shape, m: Matrix, on canvas: draw.Canvas, currentColor: draw.Color, fill: draw.Color?, fillNone: bool, solid: bool) {
        var paint = s.fill
        // The <svg> element's CSS fill stands in for a shape that says
        // nothing of its own.
        if s.fillInherited && !solid {
            if fillNone {
                paint = noFill
            } else if let f = fill {
                paint = Fill(kind: 2, color: f)
            }
        }
        if solid { paint = blackFill }
        if let t = s.text {
            if paint.kind != 0 { drawText(t, m, on: canvas, paint: paint, opacity: solid ? 1 : s.opacity, currentColor: currentColor) }
            return
        }
        if paint.kind == 0 && (s.stroke.kind == 0 || solid) { return }
        let path = devicePath(s, m)
        let box = boundingBox(s)
        func putFill() {
            if paint.kind != 0 {
                fillPath(path, rule: solid ? s.clipRule : s.rule, paint: paint, opacity: solid ? 1 : s.opacity, m: m, box: box, on: canvas, currentColor: currentColor)
            }
        }
        func putStroke() {
            if s.stroke.kind != 0 && !solid {
                // The width scales as the transform does.
                let det = m.A * m.D - m.B * m.C
                var st = s.strokeStyle
                st.Width = st.Width * math.Sqrt(det < 0 ? -det : det)
                fillPath(path.Stroked(st), rule: .nonZero, paint: s.stroke, opacity: s.opacity * s.strokeOpacity, m: m, box: box, on: canvas, currentColor: currentColor)
            }
        }
        if s.strokeFirst {
            putStroke()
            putFill()
        } else {
            putFill()
            putStroke()
        }
    }

    /// Where a shape can paint, in device pixels.
    func reach(s: Shape, m: Matrix) -> draw.IRect {
        if s.text != nil { return draw.IRect(-16384, -16384, 32768, 32768) }
        let b = devicePath(s, m).Bounds
        let det = m.A * m.D - m.B * m.C
        let w = s.stroke.kind == 0 ? 1 : s.strokeStyle.Width * math.Sqrt(det < 0 ? -det : det) * math.Max(s.strokeStyle.MiterLimit, 1) + 2
        return draw.IRect(int32(math.Floor(b.X - w)), int32(math.Floor(b.Y - w)), int32(math.Ceil(b.Width + 2 * w)) + 1, int32(math.Ceil(b.Height + 2 * w)) + 1)
    }

    /// A shape's outline in device pixels.
    func devicePath(s: Shape, m: Matrix) -> draw.Path {
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
        return path
    }
}

/// An SVG file shown as an image, as <img src=logo.svg> shows one: what
/// it draws, and the size it lays out at before CSS. It is a document of
/// its own, so the page's CSS doesn't reach into it: its fill and color
/// are its own.
public final class Document {
    public let Drawing: Drawing
    public let Width: float32
    public let Height: float32

    init(drawing: Drawing, width: float32, height: float32) {
        self.Drawing = drawing
        Width = width
        Height = height
    }
}

/// Reads bytes that are an SVG file, or nil where they aren't one: not
/// well-formed XML (a raster image, say), or a root that isn't <svg>.
public func ParseDocument(bytes: [uint8]) -> Document? {
    guard let doc = try? xml.Parse(bytes: bytes) else { return nil }
    if doc.Root.Name.Local != "svg" { return nil }
    let root = fromXML(doc.Root)
    let size = intrinsicSize(root)
    return Document(drawing: parse(root), width: size.width, height: size.height)
}

/// What an <svg> element draws.
public func Parse(root: html.Node) -> Drawing {
    return parse(fromHTML(root))
}

func parse(root: element) -> Drawing {
    let d = Drawing(viewBox: viewBoxOf(root), stretch: (root.GetAttribute("preserveaspectratio") ?? "").hasPrefix("none"))
    var ctx = Context(matrix: Matrix.identity, fill: blackFill, fillInherited: true, rule: .nonZero, opacity: 1)
    ctx = ctx.with(root, ids: [:])
    var ids: [string: element] = [:]
    collectIds(root, &ids)
    walk(root, ctx, d, ids)
    return d
}

/// The size an <svg> lays out at before CSS: its width and height
/// attributes in pixels; one of them and the viewBox's proportions; or
/// 300 by 150, as for any replaced element, shaped by the viewBox.
/// Whether an <svg> has a ratio from its viewBox but neither a width nor
/// a height: CSS then sizes it to the room it has, not to 300 by 150.
public func HasRatioOnly(root: html.Node) -> bool {
    return hasRatioOnly(fromHTML(root))
}

func hasRatioOnly(root: element) -> bool {
    if lengthAttribute(root.GetAttribute("width")) != nil || lengthAttribute(root.GetAttribute("height")) != nil { return false }
    if let vb = viewBoxOf(root), vb.Width > 0, vb.Height > 0 { return true }
    return false
}

public func IntrinsicSize(root: html.Node) -> (width: float32, height: float32) {
    return intrinsicSize(fromHTML(root))
}

func intrinsicSize(root: element) -> (width: float32, height: float32) {
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

/// The context a clipPath's or mask's content starts from.
func contentContext() -> Context {
    return Context(matrix: Matrix.identity, fill: blackFill, fillInherited: false, rule: .nonZero, opacity: 1)
}

/// What a group passes down to what's inside it.
struct Context {
    var matrix: Matrix
    var fill: Fill
    var fillInherited: bool
    var rule: draw.FillRule
    var opacity: float32
    var stroke: Fill = noFill
    var strokeStyle = draw.Stroke(width: 1)
    var strokeOpacity: float32 = 1
    var clips: [Drawing] = []
    var masks: [Drawing] = []
    var clipRule: draw.FillRule = .nonZero
    var strokeFirst: bool = false
    var spec = font.Spec(families: ["sans-serif"], size: 16)
    var anchor: string = "start"

    /// The context inside an element: its transform, and the fill
    /// properties it sets by attribute or style.
    func with(n: element, ids: [string: element]) -> Context {
        var c = self
        if let t = n.GetAttribute("transform") { c.matrix = matrix.Times(parseTransform(t)) }
        var props: [(string, string)] = []
        for name in ["fill", "fill-rule", "fill-opacity", "opacity", "stroke", "stroke-width", "stroke-linecap",
                     "stroke-linejoin", "stroke-miterlimit", "stroke-opacity", "clip-path", "mask", "clip-rule", "paint-order",
                     "font-family", "font-size", "font-weight", "font-style", "text-anchor"] {
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
            case "paint-order":
                // Only the first word that puts the stroke before the fill.
                let words = v.split(separator: " ").map { string($0) }
                let at = words.firstIndex(of: "stroke")
                let fillAt = words.firstIndex(of: "fill")
                c.strokeFirst = at != nil && (fillAt == nil || at! < fillAt!)
            case "clip-rule":
                c.clipRule = v == "evenodd" ? .evenOdd : .nonZero
            case "clip-path":
                if let t = referenced(v, ids), t.TagName == "clippath", let d = contentOf(t, ids) { c.clips.append(d) }
            case "mask":
                if let t = referenced(v, ids), t.TagName == "mask", let d = contentOf(t, ids) { c.masks.append(d) }
            case "font-family":
                c.spec.Families = familiesOf(raw)
            case "font-size":
                if let w = lengthAttribute(v), w > 0 { c.spec.Size = w }
            case "font-weight":
                c.spec.Weight = weightOf(v, c.spec.Weight)
            case "font-style":
                c.spec.Italic = v == "italic" || v == "oblique"
            case "text-anchor":
                c.anchor = v
            case "stroke":
                if v == "none" || v == "transparent" {
                    c.stroke = noFill
                } else if v == "currentcolor" {
                    c.stroke = currentFill
                } else if v.hasPrefix("url(") {
                    c.stroke = gradientFill(v, ids) ?? currentFill
                } else if let color = css.ParseColor(v) {
                    c.stroke = Fill(kind: 2, color: color)
                }
            case "stroke-width":
                if let w = lengthAttribute(v), w >= 0 { c.strokeStyle.Width = w }
            case "stroke-linecap":
                c.strokeStyle.Cap = v == "round" ? .round : (v == "square" ? .square : .butt)
            case "stroke-linejoin":
                c.strokeStyle.Join = v == "round" ? .round : (v == "bevel" ? .bevel : .miter)
            case "stroke-miterlimit":
                let b = [uint8](v.utf8)
                let m = css.parseNumber(b, 0, b.count)
                if m >= 1 { c.strokeStyle.MiterLimit = m }
            case "stroke-opacity":
                let b = [uint8](v.utf8)
                var o = css.parseNumber(b, 0, b.count)
                if v.hasSuffix("%") { o /= 100 }
                c.strokeOpacity = o < 0 ? 0 : (o > 1 ? 1 : o)
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

func collectIds(n: element, ids: inout [string: element]) {
    for c in n.Children {
        if let id = c.GetAttribute("id") { ids[id] = c }
        collectIds(c, &ids)
    }
}

/// The shapes under an element, into the drawing.
func walk(n: element, ctx: Context, d: Drawing, ids: [string: element]) {
    for c in n.Children {
        switch c.TagName {
        case "defs", "clippath", "mask", "lineargradient", "radialgradient", "pattern", "symbol", "marker",
             "title", "desc", "metadata", "style", "script", "filter", "foreignobject", "#text":
            continue
        case "text":
            if isHidden(c) { continue }
            walkText(c, ctx.with(c, ids: ids), d, ids)
        case "use":
            if isHidden(c) { continue }
            walkUse(c, ctx, d, ids)
        case "g", "a", "switch":
            if isHidden(c) { continue }
            walk(c, ctx.with(c, ids: ids), d, ids)
        case "svg":
            var inner = ctx.with(c, ids: ids)
            inner.matrix = inner.matrix.Times(viewportOf(c, width: lengthAttribute(c.GetAttribute("width")), height: lengthAttribute(c.GetAttribute("height"))))
            walk(c, inner, d, ids)
        default:
            if isHidden(c) { continue }
            let inner = ctx.with(c, ids: ids)
            var ops: [uint8] = []
            var coords: [float32] = []
            outline(c, &ops, &coords)
            if ops.isEmpty || (inner.fill.kind == 0 && inner.stroke.kind == 0) { continue }
            // A line has no inside to fill.
            let fill = c.TagName == "line" ? noFill : inner.fill
            d.shapes.append(Shape(ops: ops, coords: coords, matrix: inner.matrix, fill: fill, rule: inner.rule,
                                  opacity: inner.opacity, fillInherited: inner.fillInherited && c.TagName != "line",
                                  stroke: inner.stroke, strokeStyle: inner.strokeStyle, strokeOpacity: inner.strokeOpacity,
                                  clips: inner.clips, masks: inner.masks, clipRule: inner.clipRule, strokeFirst: inner.strokeFirst))
        }
    }
}

func isHidden(n: element) -> bool {
    if n.GetAttribute("display") == "none" || n.GetAttribute("visibility") == "hidden" { return true }
    if let style = n.GetAttribute("style") {
        let s = css.lower(style)
        if s.contains("display:none") || s.contains("display: none") { return true }
    }
    return false
}

/// A shape element's outline, as path commands.
func outline(n: element, ops: inout [uint8], coords: inout [float32]) {
    func num(name: string) -> float32 { return lengthAttribute(n.GetAttribute(name)) ?? 0 }
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
        // A polyline is open: its stroke ends at its ends.
        if n.TagName == "polygon" { ops.append(opClose) }
    case "line":
        ops += [opMove, opLine]
        coords += [num("x1"), num("y1"), num("x2"), num("y2")]
    default:
        return
    }
}

func smaller(a: float32, b: float32) -> float32 { return a < b ? a : b }

/// The viewBox: min-x, min-y, width, height.
func viewBoxOf(n: element) -> draw.Rect? {
    guard let v = n.GetAttribute("viewbox") else { return nil }
    let parts = numbers(v)
    if parts.count != 4 || parts[2] <= 0 || parts[3] <= 0 { return nil }
    return draw.Rect(parts[0], parts[1], parts[2], parts[3])
}

/// A width, height or coordinate attribute in user units: a number,
/// with px or nothing after it. Percentages and other units are nil.
func lengthAttribute(v: string?) -> float32? {
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

func trim(s: string) -> string {
    let b = [uint8](s.utf8)
    var i = 0
    var j = b.count
    while i < j && (b[i] == 32 || b[i] == 9 || b[i] == 10 || b[i] == 13) { i += 1 }
    while j > i && (b[j - 1] == 32 || b[j - 1] == 9 || b[j - 1] == 10 || b[j - 1] == 13) { j -= 1 }
    return css.stringOf(b, i, j)
}

/// SVG path data as a path, each point x, y taken to x * scale + dx,
/// y * scale + dy: clip-path: path(), on a page.
public func PathFromData(d: string, scale: float32, dx: float32, dy: float32) -> draw.Path {
    var ops: [uint8] = []
    var coords: [float32] = []
    parsePath(d, &ops, &coords)
    var path = draw.Path()
    var i = 0
    var k = 0
    while i < ops.count {
        switch ops[i] {
        case opMove:
            path.MoveTo(coords[k] * scale + dx, coords[k + 1] * scale + dy)
            k += 2
        case opLine:
            path.LineTo(coords[k] * scale + dx, coords[k + 1] * scale + dy)
            k += 2
        case opCubic:
            path.CubicTo(coords[k] * scale + dx, coords[k + 1] * scale + dy, coords[k + 2] * scale + dx, coords[k + 3] * scale + dy,
                         coords[k + 4] * scale + dx, coords[k + 5] * scale + dy)
            k += 6
        default:
            path.Close()
        }
        i += 1
    }
    return path
}
