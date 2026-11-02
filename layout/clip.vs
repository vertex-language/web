package layout

import (
    "image/draw"
    "math"
    "web/cascade"
    "web/svg"
)

// clip-path's region on the page: what paint keeps of a box and what
// hit testing lets the pointer reach.

/// A clip-path's shape on the page, in CSS pixels: Kind is inset (Rect
/// and its corners), ellipse (a centre and two radii), polygon (Points,
/// one contour) or path (Path's contours, for path() and shape()).
public struct ClipRegion {
    public var Kind: string
    public var Rect: draw.Rect = draw.Rect.zero
    public var Radii: draw.Radii = draw.Radii.zero
    public var CX: float32 = 0
    public var CY: float32 = 0
    public var RX: float32 = 0
    public var RY: float32 = 0
    public var Points: [draw.Point] = []
    public var Path: draw.Path = draw.Path()
    /// nonzero or evenodd, for polygons and paths.
    public var EvenOdd: bool = false

    init(kind: string) {
        Kind = kind
    }

    /// Whether a point on the page is inside.
    public func Contains(px: float32, py: float32) -> bool {
        switch Kind {
        case "inset":
            if px < Rect.X || py < Rect.Y || px >= Rect.X + Rect.Width || py >= Rect.Y + Rect.Height { return false }
            let r = Radii.Fitted(Rect.Width, Rect.Height)
            func corner(cx: float32, cy: float32, rad: float32) -> bool {
                if rad <= 0 { return true }
                let dx = (px - cx) / rad
                let dy = (py - cy) / rad
                return dx * dx + dy * dy <= 1
            }
            let right = Rect.X + Rect.Width
            let bottom = Rect.Y + Rect.Height
            if px < Rect.X + r.TopLeft && py < Rect.Y + r.TopLeft { return corner(Rect.X + r.TopLeft, Rect.Y + r.TopLeft, r.TopLeft) }
            if px > right - r.TopRight && py < Rect.Y + r.TopRight { return corner(right - r.TopRight, Rect.Y + r.TopRight, r.TopRight) }
            if px > right - r.BottomRight && py > bottom - r.BottomRight { return corner(right - r.BottomRight, bottom - r.BottomRight, r.BottomRight) }
            if px < Rect.X + r.BottomLeft && py > bottom - r.BottomLeft { return corner(Rect.X + r.BottomLeft, bottom - r.BottomLeft, r.BottomLeft) }
            return true
        case "ellipse":
            if RX <= 0 || RY <= 0 { return false }
            let dx = (px - CX) / RX
            let dy = (py - CY) / RY
            return dx * dx + dy * dy <= 1
        case "polygon":
            return windingAt(Points, [0], px, py, EvenOdd)
        default:
            return windingAt(Path.Points, Path.Starts, px, py, EvenOdd)
        }
    }
}

/// Whether contours (each starting at an index in starts) cover a point,
/// by nonzero winding or even-odd.
func windingAt(points: [draw.Point], starts: [int], px: float32, py: float32, evenOdd: bool) -> bool {
    var winding = 0
    var c = 0
    while c < starts.count {
        let from = starts[c]
        let to = c + 1 < starts.count ? starts[c + 1] : points.count
        var i = from
        while i < to {
            let a = points[i]
            let b = points[i + 1 < to ? i + 1 : from]
            if a.Y <= py {
                if b.Y > py && (b.X - a.X) * (py - a.Y) - (px - a.X) * (b.Y - a.Y) > 0 { winding += 1 }
            } else if b.Y <= py && (b.X - a.X) * (py - a.Y) - (px - a.X) * (b.Y - a.Y) < 0 {
                winding -= 1
            }
            i += 1
        }
        c += 1
    }
    return evenOdd ? winding % 2 != 0 : winding != 0
}

/// A box's clip-path region, its border box's corner at x, y on the
/// page, or nil for none. Percentages are of the reference box (the
/// border box unless the clip-path names another), a circle's of its
/// diagonal over root two.
public func ClipRegionOf(box: Box, x: float32, y: float32, shape: cascade.ClipPath? = nil) -> ClipRegion? {
    guard let cp = shape ?? box.Style.ClipPath else { return nil }
    // The reference box, and its corners.
    var ref = draw.Rect(x, y, box.Width, box.Height)
    var radii = box.Style.HasBorderRadius ? box.Style.Radii(width: box.Width, height: box.Height) : draw.Radii.zero
    switch cp.Box {
    case "padding-box":
        ref = draw.Rect(x + box.Border.Left, y + box.Border.Top, box.PaddingBoxWidth, box.PaddingBoxHeight)
        radii = radii.Inset(box.Border)
    case "content-box":
        let inset = draw.Edges(box.Border.Top + box.Padding.Top, box.Border.Right + box.Padding.Right,
                               box.Border.Bottom + box.Padding.Bottom, box.Border.Left + box.Padding.Left)
        ref = draw.Rect(x + inset.Left, y + inset.Top, box.InnerWidth, box.InnerHeight)
        radii = radii.Inset(inset)
    case "margin-box":
        let m = box.Margin
        ref = draw.Rect(x - m.Left, y - m.Top, box.Width + m.Horizontal, box.Height + m.Vertical)
        if !radii.IsZero { radii = draw.Radii(radii.TopLeft + m.Left, radii.TopRight + m.Right, radii.BottomRight + m.Right, radii.BottomLeft + m.Left) }
    default:
        break
    }
    let w = ref.Width
    let h = ref.Height
    let a = cp.Args
    func at(i: int, base: float32) -> float32 { return i < a.count ? a[i].Or(0, base: base) : 0 }
    switch cp.Kind {
    case "box":
        var r = ClipRegion("inset")
        r.Rect = ref
        r.Radii = radii
        return r
    case "inset":
        if a.count < 5 { return nil }
        var r = ClipRegion("inset")
        let top = at(0, h)
        let right = at(1, w)
        let bottom = at(2, h)
        let left = at(3, w)
        r.Rect = draw.Rect(ref.X + left, ref.Y + top, math.Max(w - left - right, 0), math.Max(h - top - bottom, 0))
        r.Radii = draw.Radii(all: at(4, math.Min(w, h)))
        return r
    case "circle", "ellipse":
        let circle = cp.Kind == "circle"
        let n = circle ? 1 : 2
        if a.count < n + 2 { return nil }
        var r = ClipRegion("ellipse")
        r.CX = ref.X + at(n, w)
        r.CY = ref.Y + at(n + 1, h)
        let left = r.CX - ref.X
        let rightSide = ref.X + w - r.CX
        let top = r.CY - ref.Y
        let bottomSide = ref.Y + h - r.CY
        // A radius: a length, or the distance to the nearest or the
        // farthest side (each axis's own for an ellipse).
        func radius(i: int, base: float32, near: float32, far: float32) -> float32 {
            if a[i] == .auto { return near }
            if a[i] == .none { return far }
            return a[i].Or(0, base: base)
        }
        if circle {
            let diagonal = math.Sqrt(w * w + h * h) / math.Sqrt(2)
            let rr = radius(0, diagonal, math.Min(math.Min(left, rightSide), math.Min(top, bottomSide)),
                            math.Max(math.Max(left, rightSide), math.Max(top, bottomSide)))
            r.RX = rr
            r.RY = rr
        } else {
            r.RX = radius(0, w, math.Min(left, rightSide), math.Max(left, rightSide))
            r.RY = radius(1, h, math.Min(top, bottomSide), math.Max(top, bottomSide))
        }
        return r
    case "polygon":
        var r = ClipRegion("polygon")
        r.EvenOdd = cp.Rule == "evenodd"
        var i = 0
        while i + 1 < a.count {
            r.Points.append(draw.Point(ref.X + at(i, w), ref.Y + at(i + 1, h)))
            i += 2
        }
        return r
    case "path":
        var r = ClipRegion("path")
        r.EvenOdd = cp.Rule == "evenodd"
        r.Path = svg.PathFromData(cp.Words.first ?? "", scale: 1, dx: ref.X, dy: ref.Y)
        return r
    case "shape":
        var r = ClipRegion("path")
        r.EvenOdd = cp.Rule == "evenodd"
        var p = draw.Path()
        var k = 0
        var cx: float32 = 0
        var cy: float32 = 0
        // A point's coordinates: of the box from its corner, or by from
        // the pen.
        func point(rel: bool) -> (float32, float32) {
            let px = at(k, w)
            let py = at(k + 1, h)
            k += 2
            return rel ? (cx + px, cy + py) : (ref.X + px, ref.Y + py)
        }
        // The last curve's second control point, for what smooths after it.
        var lastControl: (float32, float32)? = nil
        for whole in cp.Words {
            let parts = whole.split(separator: ":").map { string($0) }
            let word = parts[0]
            let rel = word.lowercased() == word && word != "Z"
            let was = lastControl
            lastControl = nil
            switch word.uppercased() {
            case "S":
                let c2 = point(rel)
                let q = point(rel)
                let c1 = was.map { (2 * cx - $0.0, 2 * cy - $0.1) } ?? (cx, cy)
                p.CubicTo(c1.0, c1.1, c2.0, c2.1, q.0, q.1)
                lastControl = c2
                cx = q.0
                cy = q.1
            case "T":
                let q = point(rel)
                let c1 = was.map { (2 * cx - $0.0, 2 * cy - $0.1) } ?? (cx, cy)
                p.QuadTo(c1.0, c1.1, q.0, q.1)
                lastControl = c1
                cx = q.0
                cy = q.1
            case "A":
                let rx = at(k, w)
                let ry = at(k + 1, h)
                k += 2
                let q = point(rel)
                svg.AppendArc(&p, fromX: cx, fromY: cy, rx: rx, ry: ry, angle: parts.count > 3 ? float32(parts[3]) ?? 0 : 0,
                              large: parts.count > 1 && parts[1] == "1", sweep: parts.count > 2 && parts[2] == "1", toX: q.0, toY: q.1)
                cx = q.0
                cy = q.1
            case "M":
                let q = point(rel)
                p.MoveTo(q.0, q.1)
                cx = q.0
                cy = q.1
            case "L":
                let q = point(rel)
                p.LineTo(q.0, q.1)
                cx = q.0
                cy = q.1
            case "H":
                cx = rel ? cx + at(k, w) : ref.X + at(k, w)
                k += 1
                p.LineTo(cx, cy)
            case "V":
                cy = rel ? cy + at(k, h) : ref.Y + at(k, h)
                k += 1
                p.LineTo(cx, cy)
            case "C":
                let c1 = point(rel)
                let c2 = point(rel)
                let q = point(rel)
                p.CubicTo(c1.0, c1.1, c2.0, c2.1, q.0, q.1)
                lastControl = c2
                cx = q.0
                cy = q.1
            case "Q":
                let c1 = point(rel)
                let q = point(rel)
                p.QuadTo(c1.0, c1.1, q.0, q.1)
                lastControl = c1
                cx = q.0
                cy = q.1
            default:
                p.Close()
            }
        }
        r.Path = p
        return r
    default:
        return nil
    }
}
