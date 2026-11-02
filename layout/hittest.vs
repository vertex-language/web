package layout

import (
    "image/draw"
    "web/html"
)

/// What lies under a point: the deepest box, the element it belongs
/// to, and for text, where in the text.
public struct Hit {
    public var Box: Box
    public var Node: html.Node?
    /// The text box hit, if the point was on text.
    public var TextBox: Box?
    /// Where in the text box's text the point falls, in bytes.
    public var TextOffset: int
    /// The box's border-box corner in page coordinates.
    public var PageX: float32
    public var PageY: float32
}

/// The 3D context being tested in: the point on the screen, and the
/// matrix of the plane whose children are being asked.
var hitContext: (screen: (x: float32, y: float32), matrix: draw.Matrix4)? = nil

/// How near the viewer the plane of the last hit in a 3D context is.
var hitDepth: float32? = nil

/// A box's rectangle on the page as it shows: through the turns of any
/// vertical text it's in, whose layout it's in unturned.
public func VisualBounds(box: Box) -> draw.Rect {
    let p = PagePosition(box)
    var x0 = p.x
    var y0 = p.y
    var x1 = p.x + box.Width
    var y1 = p.y + box.Height
    var turned = false
    var cur = box.Parent
    while let a = cur {
        if a.QuarterTurn != 0 {
            turned = true
            let at = PagePosition(a)
            let m = QuarterMatrix(a, x: at.x, y: at.y)
            let c0 = m.Apply(x0, y0)
            let c1 = m.Apply(x1, y1)
            x0 = c0.x < c1.x ? c0.x : c1.x
            x1 = c0.x < c1.x ? c1.x : c0.x
            y0 = c0.y < c1.y ? c0.y : c1.y
            y1 = c0.y < c1.y ? c1.y : c0.y
        }
        cur = a.Parent
    }
    if !turned { return draw.Rect(p.x, p.y, box.Width, box.Height) }
    return draw.Rect(x0, y0, x1 - x0, y1 - y0)
}

/// What transform-box says a box's transforms are about: nil for its border
/// box, the rectangle within it otherwise.
public func TransformBoxOf(box: Box) -> draw.Rect? {
    switch box.Style.TransformBox {
    case "content-box", "fill-box":
        return draw.Rect(box.ContentX, box.ContentY, box.InnerWidth, box.InnerHeight)
    case "view-box":
        // The viewport's, from the box's corner.
        let at = PagePosition(box)
        var top = box
        while let up = top.Parent { top = up }
        return draw.Rect(-at.x, -at.y, top.Width, top.Height)
    default:
        return nil
    }
}

/// How a vertical box's content turns from where layout set it, x and y its
/// corner, to where it shows: its corner stays at the box's top left.
public func QuarterMatrix(box: Box, x: float32, y: float32) -> draw.Affine {
    if box.QuarterTurn < 0 { return draw.Affine(0, -1, 1, 0, x - y, y + box.Width + x) }
    return draw.Affine(0, 1, -1, 0, x + y + box.BlockAxisSize, y - x)
}

/// A box's matrix on the page where it needs one in 3D, its parent's
/// perspective included: nil for a box a 2D transform, or none, will do.
/// x and y are its border box's corner.
public func ThreeDMatrix(box: Box, x: float32, y: float32) -> draw.Matrix4? {
    let s = box.Style
    let parent = box.Parent?.Style
    let perspective = parent?.Perspective ?? 0
    let needed = s.UsedPreserve3D || (s.HasTransform && (s.Is3D || perspective > 0 || (parent?.UsedPreserve3D ?? false)))
    if !needed { return nil }
    var m = draw.Matrix4.translate(x, y).Concat(s.Matrix3D(width: box.Width, height: box.Height, box: TransformBoxOf(box))).Concat(draw.Matrix4.translate(-x, -y))
    if perspective > 0, let pb = box.Parent {
        let at = PagePosition(box)
        let pat = PagePosition(pb)
        let ox = x - at.x + pat.x + (parent!.PerspectiveOriginX.Resolve(pb.Width) ?? pb.Width / 2)
        let oy = y - at.y + pat.y + (parent!.PerspectiveOriginY.Resolve(pb.Height) ?? pb.Height / 2)
        m = draw.Matrix4.translate(ox, oy).Concat(draw.Matrix4.perspective(perspective)).Concat(draw.Matrix4.translate(-ox, -oy)).Concat(m)
    }
    return m
}

/// The innermost box under a page point. A transformed box is tested
/// where it paints: the point is taken back through its transform.
public func HitTest(box: Box, px: float32, py: float32, originX: float32, originY: float32) -> Hit? {
    if box.QuarterTurn != 0 {
        let t = QuarterMatrix(box, x: originX + box.X + box.OffsetX, y: originY + box.Y + box.OffsetY)
        guard let inv = t.Inverted() else { return nil }
        let p = inv.Apply(px, py)
        return hitTestBox(box, p.x, p.y, originX: originX, originY: originY)
    }
    if let local = ThreeDMatrix(box, x: originX + box.X + box.OffsetX, y: originY + box.Y + box.OffsetY) {
        // A plane in a 3D context answers to the point on the screen.
        var screen = (x: px, y: py)
        var full = local
        if box.Parent?.Style.UsedPreserve3D ?? false, let c = hitContext {
            screen = c.screen
            full = c.matrix.Concat(local)
        }
        if box.Style.BackfaceHidden && !full.FacesViewer { return nil }
        guard let p = full.Unproject(screen.x, screen.y) else { return nil }
        let saved = hitContext
        if box.Style.UsedPreserve3D { hitContext = (screen: screen, matrix: full) }
        hitDepth = nil
        let hit = hitTestBox(box, p.x, p.y, originX: originX, originY: originY)
        hitContext = saved
        // Its own plane's depth, unless a plane in its context was what's hit.
        if hit != nil && (hitDepth == nil || !box.Style.UsedPreserve3D) {
            let q = full.Apply(p.x, p.y)
            hitDepth = q.w != 0 ? q.z / q.w : 0
        }
        return hit
    }
    if box.AnchorHidden { return nil }
    if box.Style.HasTransform {
        let x = originX + box.X + box.OffsetX
        let y = originY + box.Y + box.OffsetY
        let t = draw.Affine.translate(x, y).Concat(box.Style.TransformMatrix(width: box.Width, height: box.Height, box: TransformBoxOf(box))).Concat(draw.Affine.translate(-x, -y))
        guard let inv = t.Inverted() else { return nil }
        let p = inv.Apply(px, py)
        return hitTestBox(box, p.x, p.y, originX: originX, originY: originY)
    }
    return hitTestBox(box, px, py, originX: originX, originY: originY)
}

func hitTestBox(box: Box, px: float32, py: float32, originX: float32, originY: float32) -> Hit? {
    let x = originX + box.X + box.OffsetX
    let y = originY + box.Y + box.OffsetY
    // clip-path cuts what takes the pointer as it cuts what shows.
    if box.Style.ClipPath != nil, let region = ClipRegionOf(box, x: x, y: y), !region.Contains(px, py) { return nil }
    let inside = px >= x && py >= y && px < x + box.Width && py < y + box.Height
    let sx = x - box.ScrollX
    let sy = y - box.ScrollY

    // In a 3D context, what's nearest the viewer at the point.
    if box.Style.UsedPreserve3D, let c = hitContext {
        var best: Hit? = nil
        var bestDepth: float32 = -1e9
        func ask(p: Box, fx: float32, fy: float32) {
            hitDepth = nil
            guard let h = HitTest(p, px, py, originX: fx, originY: fy) else { return }
            // A plane with no 3D of its own is in this one.
            var depth = hitDepth
            if depth == nil {
                let q = c.matrix.Apply(px, py)
                depth = q.w != 0 ? q.z / q.w : 0
            }
            // On top where they tie: asked first, painted last.
            if best == nil || depth! > bestDepth + 0.001 {
                best = h
                bestDepth = depth!
            }
        }
        for p in box.Positioned.reversed() {
            ask(p, fx: p.FixedToViewport ? sx + box.ViewportScrollX : sx, fy: p.FixedToViewport ? sy + box.ViewportScrollY : sy)
        }
        if box.Lines.isEmpty {
            for child in box.Children.reversed() where child.Kind != .text && child.Kind != .inline && child.Kind != .lineBreak && child.Style.Position != .absolute && child.Style.Position != .fixed {
                ask(child, fx: sx, fy: sy)
            }
        }
        if let h = best {
            // Its own plane can be in front of them.
            let own = c.matrix.Apply(px, py)
            let ownDepth = own.w != 0 ? own.z / own.w : 0
            if inside && box.Style.PointerEvents != .none && ownDepth > bestDepth + 0.001 {
                hitDepth = ownDepth
                return Hit(Box: box, Node: box.Element, TextBox: nil, TextOffset: 0, PageX: x, PageY: y)
            }
            hitDepth = bestDepth
            return h
        }
        hitDepth = nil
    }

    // Positioned boxes are on top, the highest z-index first.
    if !box.Positioned.isEmpty {
        var i = box.Positioned.count - 1
        var best: Hit? = nil
        var bestZ: int32 = -2147483647
        while i >= 0 {
            let p = box.Positioned[i]
            // A box fixed to the viewport is where the scroll leaves it.
            let fx = p.FixedToViewport ? sx + box.ViewportScrollX : sx
            let fy = p.FixedToViewport ? sy + box.ViewportScrollY : sy
            if let h = HitTest(p, px, py, originX: fx, originY: fy) {
                // Later boxes paint over earlier ones: an earlier box
                // wins only with a higher z-index.
                if best == nil || p.Style.ZIndex > bestZ {
                    best = h
                    bestZ = p.Style.ZIndex
                }
            }
            i -= 1
        }
        if let h = best { return h }
    }
    if box.Style.ClipsOverflow && !inside { return nil }

    // pointer-events: none -- the box isn't a target; what is in it may be.
    let takes = box.Style.PointerEvents != .none
    if box.Kind == .replaced {
        return inside && takes ? Hit(Box: box, Node: box.Element, TextBox: nil, TextOffset: 0, PageX: x, PageY: y) : nil
    }
    if !box.Lines.isEmpty {
        var li = box.Lines.count - 1
        while li >= 0 {
            let line = box.Lines[li]
            let lineTop = sy + line.Y
            if py >= lineTop && py < lineTop + line.Height {
                var fi = line.Fragments.count - 1
                while fi >= 0 {
                    let f = line.Fragments[fi]
                    let fx = sx + f.X
                    let fy = sy + f.Y
                    if px >= fx && px < fx + f.Width {
                        if f.Kind == .atomic {
                            if let h = HitTest(f.Box, px, py, originX: sx, originY: sy) { return h }
                        } else if f.Kind == .text && py >= fy - 2 && py < fy + f.Height + 2 && f.Owner.Style.PointerEvents != .none {
                            // Right-to-left text starts at its right.
                            let along = f.RightToLeft ? f.Width - (px - fx) : px - fx
                            let offset = f.Offset + offsetInRun(f, at: along, letterSpacing: f.Owner.Style.LetterSpacing)
                            return Hit(Box: f.Owner, Node: f.Owner.Element, TextBox: f.Box, TextOffset: offset, PageX: fx, PageY: fy)
                        }
                    }
                    fi -= 1
                }
                // On the line but beside its text: the inline element
                // whose span covers the point, else the container.
                var si = line.Spans.count - 1
                while si >= 0 {
                    let sp = line.Spans[si]
                    if px >= sx + sp.X && px < sx + sp.X + sp.Width && sp.Box.Style.PointerEvents != .none {
                        return Hit(Box: sp.Box, Node: sp.Box.Element, TextBox: nil, TextOffset: 0, PageX: sx + sp.X, PageY: sy + sp.Y)
                    }
                    si -= 1
                }
                if inside && takes {
                    return Hit(Box: box, Node: box.Element, TextBox: nil, TextOffset: 0, PageX: x, PageY: y)
                }
            }
            li -= 1
        }
    } else {
        // What is positioned paints over what isn't, so it is asked first.
        var i = box.Children.count - 1
        while i >= 0 {
            let c = box.Children[i]
            i -= 1
            // A positioned box among a plain static child's lines, an
            // anonymous one's too, paints over later blocks as well.
            if c.Style.Position == .static && !c.Lines.isEmpty && !c.Style.ClipsOverflow && !c.Style.HasTransform && c.QuarterTurn == 0 {
                let cx = sx + c.X + c.OffsetX - c.ScrollX
                let cy = sy + c.Y + c.OffsetY - c.ScrollY
                var li = c.Lines.count - 1
                while li >= 0 {
                    var fi = c.Lines[li].Fragments.count - 1
                    while fi >= 0 {
                        let f = c.Lines[li].Fragments[fi]
                        fi -= 1
                        if f.Kind != .atomic || (f.Box.Style.Position != .relative && f.Box.Style.Position != .sticky) { continue }
                        if let h = HitTest(f.Box, px, py, originX: cx, originY: cy) { return h }
                    }
                    li -= 1
                }
            }
            if c.Style.Position != .relative && c.Style.Position != .sticky { continue }
            if c.Kind == .text || c.Kind == .inline || c.Kind == .lineBreak { continue }
            if let h = HitTest(c, px, py, originX: sx, originY: sy) { return h }
        }
        i = box.Children.count - 1
        while i >= 0 {
            let c = box.Children[i]
            i -= 1
            if c.Style.Position != .static { continue }
            if c.Kind == .text || c.Kind == .inline || c.Kind == .lineBreak { continue }
            if let h = HitTest(c, px, py, originX: sx, originY: sy) { return h }
        }
    }
    if inside && takes {
        return Hit(Box: box, Node: box.Element, TextBox: nil, TextOffset: 0, PageX: x, PageY: y)
    }
    return nil
}

/// The byte offset in a text fragment nearest a horizontal position:
/// glyph by glyph, rounding to the nearer edge.
func offsetInRun(f: Fragment, at x: float32, letterSpacing: float32) -> int {
    let bytes = [uint8](f.Text.utf8)
    // Glyphs and bytes line up only for ASCII; for anything else the
    // run is measured by prefix.
    var ascii = true
    for b in bytes where b >= 128 { ascii = false }
    if ascii && f.Run.Count == bytes.count {
        var pen: float32 = 0
        var i = 0
        while i < f.Run.Count {
            let adv = f.Run.Advances[i] + letterSpacing
            if x < pen + adv / 2 { return i }
            pen += adv
            i += 1
        }
        return bytes.count
    }
    let face = f.Owner.Style.Face
    var best = 0
    var bestDist: float32 = 1e9
    var i = 0
    while i <= bytes.count {
        if i == bytes.count || (bytes[i] & 0xC0) != 0x80 {
            let w = face.Measure(stringOf(bytes, 0, i))
            let d = w > x ? w - x : x - w
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        i += 1
    }
    return best
}

/// The page position of a box: its corner with every ancestor's added.
public func PagePosition(box: Box) -> (x: float32, y: float32) {
    var x: float32 = 0
    var y: float32 = 0
    var cur: Box? = box
    var fixed = false
    var top: Box = box
    while let b = cur {
        if b.FixedToViewport { fixed = true }
        top = b
        x += b.X + b.OffsetX
        y += b.Y + b.OffsetY
        if let p = b.Parent {
            x -= p.ScrollX
            y -= p.ScrollY
        }
        cur = b.Parent
    }
    // Inside a box fixed to the viewport: as far down the page as it is
    // scrolled.
    if fixed {
        x += top.ViewportScrollX
        y += top.ViewportScrollY
    }
    return (x: x, y: y)
}
