package web

import (
    "image/draw"
    "math"
    "web/cascade"
    "web/dom"
    "web/layout"
)

// Scrolling beyond the wheel's own: element scroll offsets kept across
// restyles, smooth scrolling (scroll-behavior: smooth, and every snap),
// and CSS Scroll Snap -- once a wheel scroll has been still for a moment,
// the page or the container settles where scroll-snap-align says.

/// A scroll moving smoothly to where it is going: the page's (node 0)
/// or an element's.
struct ScrollAnimation {
    var node: int64
    var from: draw.Point
    var to: draw.Point
    /// When it began, in the page's seconds; -1 until the next frame.
    var start: float64
    var duration: float64
}

/// How long a smooth scroll takes, and how long a wheel scroll is still
/// before it snaps.
let smoothScrollSeconds: float64 = 0.3
let snapIdleSeconds: float64 = 0.12

extension Page {
    /// Whether scrolls the page makes itself -- to a fragment, by a key --
    /// glide: the root's scroll-behavior, unless the user asked for less
    /// motion.
    var smoothScrolling: bool {
        guard let r = root else { return false }
        return r.Style.ScrollBehavior == "smooth" && !cascade.PrefersReducedMotion
    }

    /// Scrolls the page to an offset, smoothly or at once.
    func scrollPage(to p: draw.Point, smooth: bool) {
        if !smooth {
            scrollAnimation = nil
            SetScrollOffset(p)
            return
        }
        let maxY = contentHeight > size.Height ? contentHeight - size.Height : 0
        let maxX = contentWidth > size.Width ? contentWidth - size.Width : 0
        let to = draw.Point(math.Clamp(p.X, 0, maxX), math.Clamp(p.Y, 0, maxY))
        if to.X == scroll.X && to.Y == scroll.Y { return }
        scrollAnimation = ScrollAnimation(node: 0, from: scroll, to: to, start: -1, duration: smoothScrollSeconds)
    }

    /// Scrolls an element to an offset within its content, smoothly or
    /// at once.
    func scrollElement(b: layout.Box, to p: draw.Point, smooth: bool) {
        guard let node = b.Node else { return }
        let to = clampedScroll(b, p)
        if !smooth {
            setElementScroll(b, to)
            return
        }
        if to.X == b.ScrollX && to.Y == b.ScrollY { return }
        scrollAnimation = ScrollAnimation(node: node.Id, from: draw.Point(b.ScrollX, b.ScrollY), to: to, start: -1, duration: smoothScrollSeconds)
    }

    func clampedScroll(b: layout.Box, p: draw.Point) -> draw.Point {
        let maxY = b.ContentHeight - b.InnerHeight
        let maxX = b.ContentWidth - b.InnerWidth
        return draw.Point(math.Clamp(p.X, 0, maxX > 0 ? maxX : 0), math.Clamp(p.Y, 0, maxY > 0 ? maxY : 0))
    }

    /// Sets an element's scroll offset, and keeps it for the boxes a
    /// restyle builds; scroll fires at it.
    func setElementScroll(b: layout.Box, p: draw.Point) {
        if b.ScrollX == p.X && b.ScrollY == p.Y { return }
        b.ScrollX = p.X
        b.ScrollY = p.Y
        needsPaint = true
        if let n = b.Node {
            elementScroll[n.Id] = p
            _ = dispatch(dom.Event("scroll", bubbles: false), to: n)
        }
    }

    /// Puts the kept scroll offsets back on a newly laid-out tree.
    func restoreElementScrolls() {
        if elementScroll.isEmpty { return }
        var gone: [int64] = []
        for (id, p) in elementScroll {
            guard let b = builder.byNode[id] else { gone.append(id); continue }
            let c = clampedScroll(b, p)
            b.ScrollX = c.X
            b.ScrollY = c.Y
        }
        for id in gone { elementScroll[id] = nil }
    }

    /// A wheel scroll moved the page (nil) or a container: once it has
    /// been still a moment, it snaps.
    func noteWheelScroll(container: layout.Box?) {
        let id = container?.Node?.Id ?? 0
        let style = container?.Style ?? root?.Style
        guard let s = style, s.SnapType != "none" else { return }
        pendingSnap = (node: id, at: animator.now)
    }

    /// Moves a smooth scroll, and snaps a wheel scroll that has come to
    /// rest. Answers whether a repaint is needed.
    func advanceScroll(time: float64) -> bool {
        var moved = false
        if let p = pendingSnap, time - p.at >= snapIdleSeconds {
            pendingSnap = nil
            if p.node == 0 {
                if let to = snapTarget(nil) { scrollPage(to: to, smooth: true) }
            } else if let b = builder.byNode[p.node], let to = snapTarget(b) {
                scrollElement(b, to: to, smooth: true)
            }
        }
        guard var a = scrollAnimation else { return moved }
        if a.start < 0 {
            a.start = time
            scrollAnimation = a
        }
        let t = math.Saturate(float32((time - a.start) / a.duration))
        // Ease in and out.
        let e = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2
        let p = draw.Point(a.from.X + (a.to.X - a.from.X) * e, a.from.Y + (a.to.Y - a.from.Y) * e)
        if a.node == 0 {
            let before = scroll
            scroll = p
            clampScroll()
            if scroll.X != before.X || scroll.Y != before.Y {
                needsRepaint = true
                pageScrolled()
            }
        } else if let b = builder.byNode[a.node] {
            setElementScroll(b, clampedScroll(b, p))
        }
        moved = true
        if t >= 1 { scrollAnimation = nil }
        return moved
    }

    /// Where a snap container settles from where it is: the nearest snap
    /// position of the boxes in it, along the axes it snaps; with
    /// proximity, only one near enough. Nil where there is none.
    func snapTarget(container: layout.Box?) -> draw.Point? {
        guard let r = root else { return nil }
        let cs = container?.Style ?? r.Style
        let words = cs.SnapType.split(separator: " ").map { string($0) }
        if words.isEmpty || words[0] == "none" { return nil }
        let snapY = words.contains("y") || words.contains("block") || words.contains("both")
        let snapX = words.contains("x") || words.contains("inline") || words.contains("both")
        let mandatory = words.contains("mandatory")
        let viewW = container?.InnerWidth ?? size.Width
        let viewH = container?.InnerHeight ?? size.Height
        let current = container.map { draw.Point($0.ScrollX, $0.ScrollY) } ?? scroll
        let pad = cs.ScrollPadding
        let padTop = pad[0].Resolve(viewH) ?? 0
        let padRight = pad[1].Resolve(viewW) ?? 0
        let padBottom = pad[2].Resolve(viewH) ?? 0
        let padLeft = pad[3].Resolve(viewW) ?? 0
        // The scroll content's origin, on the page.
        var originX: float32 = 0
        var originY: float32 = 0
        if let c = container {
            let pos = layout.PagePosition(c)
            originX = pos.x + c.Border.Left - c.ScrollX
            originY = pos.y + c.Border.Top - c.ScrollY
        }
        var bestX: float32? = nil
        var bestY: float32? = nil
        func consider(b: layout.Box) {
            let align = b.Style.SnapAlign.split(separator: " ").map { string($0) }
            if align.isEmpty || align[0] == "none" { return }
            let blockAlign = align[0]
            let inlineAlign = align.count > 1 ? align[1] : align[0]
            let pos = layout.PagePosition(b)
            let x = pos.x - originX
            let y = pos.y - originY
            let m = b.Style.ScrollMargin
            if snapY && blockAlign != "none" {
                var target = y - (m[0].Resolve(viewH) ?? 0) - padTop
                if blockAlign == "end" { target = y + b.Height + (m[2].Resolve(viewH) ?? 0) - (viewH - padBottom) }
                if blockAlign == "center" { target = y + b.Height / 2 - (padTop + (viewH - padTop - padBottom) / 2) }
                if bestY == nil || math.Abs(target - current.Y) < math.Abs(bestY! - current.Y) { bestY = target }
            }
            if snapX && inlineAlign != "none" {
                var target = x - (m[3].Resolve(viewW) ?? 0) - padLeft
                if inlineAlign == "end" { target = x + b.Width + (m[1].Resolve(viewW) ?? 0) - (viewW - padRight) }
                if inlineAlign == "center" { target = x + b.Width / 2 - (padLeft + (viewW - padLeft - padRight) / 2) }
                if bestX == nil || math.Abs(target - current.X) < math.Abs(bestX! - current.X) { bestX = target }
            }
        }
        // The boxes the container scrolls, not into scroll containers of
        // their own.
        func walk(b: layout.Box) {
            for c in b.Children {
                consider(c)
                if !c.Style.IsScrollContainer { walk(c) }
            }
        }
        walk(container ?? r)
        var to = current
        if let y = bestY, mandatory || math.Abs(y - current.Y) <= viewH * 0.3 { to.Y = y }
        if let x = bestX, mandatory || math.Abs(x - current.X) <= viewW * 0.3 { to.X = x }
        if to.X == current.X && to.Y == current.Y { return nil }
        return to
    }
}
