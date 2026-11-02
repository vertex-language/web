package web

import (
    "image/draw"
    "web/cascade"
    "web/css"
    "web/html"
    "web/layout"
)

// Scroll-driven animations: how far along scroll() and view() timelines
// an element is, and view transitions' old picture.

extension Page {
    /// How far along a timeline an element's animation is, by animation-
    /// timeline's and animation-range's words; below 0 or above 1 outside.
    func timelineProgress(node: html.Node, timeline: string, range: string) -> float32? {
        guard let name = timeline.split(separator: "(").first.map({ string($0) }) else { return nil }
        // The words in its parentheses.
        var words: [string] = []
        let parts = timeline.split(separator: "(").map { string($0) }
        if parts.count > 1 {
            words = parts[1].split(whereSeparator: { $0 == " " || $0 == ")" }).map { string($0) }
        }
        var subject: html.Node? = nil
        var isView = false
        var scroller: layout.Box? = nil
        var horizontal = words.contains("inline") || words.contains("x")
        if name == "scroll" {
            if words.contains("self") {
                scroller = previousBoxes[node.Id]
            } else if !words.contains("root") {
                scroller = nearestScroller(node)
            }
        } else if name == "view" {
            subject = node
            isView = true
            scroller = nearestScroller(node)
        } else if name.hasPrefix("--") {
            // A name on the element or an ancestor.
            var cur: html.Node? = node
            while let n = cur, subject == nil {
                if let b = previousBoxes[n.Id] {
                    if css.lower(b.Style.ScrollTimelineName) == name {
                        subject = n
                        scroller = b
                        break
                    }
                    if css.lower(b.Style.ViewTimelineName) == name {
                        subject = n
                        isView = true
                        scroller = nearestScroller(n)
                        break
                    }
                }
                cur = n.Parent
            }
            // Or a name an ancestor's timeline-scope reaches for, on any
            // element under it.
            if subject == nil {
                var scope: html.Node? = node
                while let n = scope, subject == nil {
                    if let b = previousBoxes[n.Id], b.Style.TimelineScope.contains(where: { css.lower($0) == name }) {
                        func search(under: html.Node) {
                            if subject != nil { return }
                            if let c = previousBoxes[under.Id] {
                                if css.lower(c.Style.ScrollTimelineName) == name {
                                    subject = under
                                    scroller = c
                                    return
                                }
                                if css.lower(c.Style.ViewTimelineName) == name {
                                    subject = under
                                    isView = true
                                    scroller = nearestScroller(under)
                                    return
                                }
                            }
                            for k in under.Children where k.Kind == html.NodeKind.element { search(k) }
                        }
                        search(n)
                        break
                    }
                    scope = n.Parent
                }
            }
            if subject == nil { return nil }
        } else {
            return nil
        }
        if horizontal && scroller == nil { horizontal = contentWidth > size.Width && contentHeight <= size.Height }
        // Where the scroll is, how far it goes, and how big the view is.
        var at = horizontal ? scroll.X : scroll.Y
        var most = horizontal ? contentWidth - size.Width : contentHeight - size.Height
        var view = horizontal ? size.Width : size.Height
        var origin: float32 = 0
        if let s = scroller {
            at = horizontal ? s.ScrollX : s.ScrollY
            most = horizontal ? s.ContentWidth - s.InnerWidth : s.ContentHeight - s.InnerHeight
            view = horizontal ? s.InnerWidth : s.InnerHeight
            let p = layout.PagePosition(s)
            origin = (horizontal ? p.x : p.y) - at
        }
        var low: float32 = 0
        var high = most
        var ranges: [string: (float32, float32)] = [:]
        if isView {
            guard let n = subject, let b = previousBoxes[n.Id] else { return nil }
            let p = layout.PagePosition(b)
            let start = (horizontal ? p.x : p.y) - origin
            let length = horizontal ? b.Width : b.Height
            // view()'s insets take from the view at each end.
            var insets: [float32] = []
            for w in words where w.hasSuffix("px") {
                if let v = float32(w.dropLast(2)) { insets.append(v) }
            }
            if let first = insets.first {
                view -= first + (insets.count > 1 ? insets[1] : first)
                origin -= insets.count > 1 ? 0 : 0
            }
            low = start - view
            high = start + length
            ranges["cover"] = (start - view, start + length)
            ranges["contain"] = (length < view ? start - view + length : start, length < view ? start : start - view + length)
            ranges["entry"] = (start - view, start - view + length)
            ranges["exit"] = (start, start + length)
            ranges["entry-crossing"] = ranges["entry"]
            ranges["exit-crossing"] = ranges["exit"]
        }
        // animation-range: a name and a percentage at each end.
        var from = low
        var to = high
        if range != "normal" {
            let parts = range.split(separator: " ").map { string($0) }
            var points: [float32] = []
            var current: (float32, float32) = (low, high)
            var i = 0
            while i < parts.count {
                if let r = ranges[parts[i]] {
                    current = r
                    if i + 1 >= parts.count || ranges[parts[i + 1]] != nil {
                        // A name alone: the whole of it, at whichever end.
                        points.append(points.isEmpty ? r.0 : r.1)
                    }
                } else if parts[i].hasSuffix("%"), let v = float32(parts[i].dropLast()) {
                    points.append(current.0 + (current.1 - current.0) * v / 100)
                }
                i += 1
            }
            if points.count >= 1 { from = points[0] }
            if points.count >= 2 { to = points[1] } else if parts.count >= 1 && ranges[parts[0]] != nil { to = ranges[parts[0]]!.1 }
        }
        // Nothing to scroll: where it starts.
        if to <= from { return 0 }
        return (at - from) / (to - from)
    }

    /// What an element's size would be at auto, from the boxes it has.
    func measureAutoSize(node: html.Node, height: bool) -> float32? {
        guard let b = previousBoxes[node.Id] else { return nil }
        let run = layout.Layout(viewportWidth: size.Width, viewportHeight: size.Height)
        return run.MeasureAuto(b, height: height)
    }

    func nearestScroller(node: html.Node) -> layout.Box? {
        var cur = node.Parent
        while let n = cur {
            if let b = previousBoxes[n.Id], b.Style.IsScrollContainer, n.TagName != "html" && n.TagName != "body" { return b }
            cur = n.Parent
        }
        return nil
    }

    // MARK: - View transitions

    /// Runs an update of the page, its old picture fading into the new. A
    /// box with a view-transition-name moves from where it was to where it
    /// is, as it fades. A host that hasn't drawn yet just gets the update.
    public func StartViewTransition(update: () -> Void) {
        takeTransitionPicture()
        update()
        beginTransition()
    }

    func takeTransitionPicture() {
        oldPicture = nil
        oldGroups = [:]
        transitionAt = -1
        if drawnScale <= 0 || cascade.PrefersReducedMotion { return }
        let w = draw.RoundToInt(size.Width * drawnScale)
        let h = draw.RoundToInt(size.Height * drawnScale)
        if w <= 0 || h <= 0 { return }
        var pixels = [uint8](repeating: 0, count: int(w) * int(h) * 4)
        Draw(into: &pixels, width: w, height: h, scale: drawnScale)
        oldPicture = draw.Image(width: w, height: h, pixels: pixels)
        for (id, b) in builder.byNode where !b.Style.ViewTransitionName.isEmpty {
            guard let n = b.Node, let r = BoundsOf(n) else { continue }
            oldGroups[b.Style.ViewTransitionName] = (node: id, rect: r)
        }
    }

    func beginTransition() {
        if oldPicture == nil { return }
        update()
        transitionMoves = []
        transitionElapsed = 0
        // The pseudo-elements say how long, after how much and how it eases:
        // the page's fade by root's, each group by its name, then its
        // view-transition-class, then *.
        rootTiming = transitionTiming(["view-transition-group(root)", "view-transition-old(root)", "view-transition-new(root)", "view-transition-group(*)", "view-transition"])
        transitionLength = rootTiming.delay + rootTiming.duration
        for (id, b) in builder.byNode where !b.Style.ViewTransitionName.isEmpty {
            guard let n = b.Node, let now = BoundsOf(n), let was = oldGroups[b.Style.ViewTransitionName] else { continue }
            var keys = ["view-transition-group(\(b.Style.ViewTransitionName))"]
            for c in b.Style.ViewTransitionClasses { keys.append("view-transition-group(.\(c))") }
            keys.append("view-transition-group(*)")
            let timing = transitionTiming(keys)
            if timing.delay + timing.duration > transitionLength { transitionLength = timing.delay + timing.duration }
            transitionMoves.append(TransitionMove(from: was.rect, to: now, node: id, timing: timing))
        }
        transitionFade = 1
        needsRepaint = true
    }

    /// The first of these pseudo-elements on the root that says how long,
    /// with its delay and easing; a quarter second, eased, where none does.
    func transitionTiming(which: [string]) -> TransitionTiming {
        guard let html = Document?.Tree.ElementsByTagName("html").first, let box = builder.byNode[html.Id] else { return TransitionTiming() }
        for w in which {
            guard let style = resolver.ResolvePseudo(html, w, parent: box.Style, context: context) else { continue }
            let a = style.Animation
            guard let d = a.Durations.first, d > 0 else { continue }
            return TransitionTiming(duration: float64(d), delay: float64(a.Delays.first ?? 0), easing: a.Timings.first ?? cascade.Easing.ease)
        }
        return TransitionTiming()
    }

    /// Eases the fade. Answers whether it moved.
    func advanceTransition(time: float64) -> bool {
        guard oldPicture != nil else { return false }
        if transitionAt < 0 { transitionAt = time }
        transitionElapsed = time - transitionAt
        if transitionElapsed >= transitionLength {
            oldPicture = nil
            transitionMoves = []
            transitionFade = 0
        } else {
            transitionFade = 1 - rootTiming.progress(transitionElapsed)
        }
        needsRepaint = true
        return true
    }

    /// The old picture over the new: all of it fading, and what has a name
    /// moving to where it now is.
    func drawTransition(on canvas: draw.Canvas, view: draw.IRect, scale: float32) {
        guard let old = oldPicture else { return }
        canvas.DrawImage(old, into: view, opacity: transitionFade)
        for m in transitionMoves {
            let k = m.timing.progress(transitionElapsed)
            let x = m.from.X + (m.to.X - m.from.X) * k
            let y = m.from.Y + (m.to.Y - m.from.Y) * k
            let w = m.from.Width + (m.to.Width - m.from.Width) * k
            let h = m.from.Height + (m.to.Height - m.from.Height) * k
            let crop = cropped(old, m.from, scale: scale)
            canvas.DrawImage(crop, into: draw.Rect(x + float32(view.X) / scale, y + float32(view.Y) / scale, w, h).Snapped(scale: scale), opacity: 1 - k)
        }
    }

    func cropped(img: draw.Image, r: draw.Rect, scale: float32) -> draw.Image {
        let x0 = draw.RoundToInt(r.X * scale)
        let y0 = draw.RoundToInt(r.Y * scale)
        let w = draw.RoundToInt(r.Width * scale)
        let h = draw.RoundToInt(r.Height * scale)
        if w <= 0 || h <= 0 { return draw.Image(width: 1, height: 1, pixels: [0, 0, 0, 0]) }
        var out = [uint8](repeating: 0, count: int(w) * int(h) * 4)
        var y: int32 = 0
        while y < h {
            var x: int32 = 0
            while x < w {
                let sx = x0 + x
                let sy = y0 + y
                if sx >= 0 && sy >= 0 && sx < img.Width && sy < img.Height {
                    let from = int(sy * img.Width + sx) * 4
                    let to = int(y * w + x) * 4
                    out[to] = img.Pixels[from]
                    out[to + 1] = img.Pixels[from + 1]
                    out[to + 2] = img.Pixels[from + 2]
                    out[to + 3] = img.Pixels[from + 3]
                }
                x += 1
            }
            y += 1
        }
        return draw.Image(width: w, height: h, pixels: out)
    }
}

/// A named box in a view transition.
struct TransitionMove {
    var from: draw.Rect
    var to: draw.Rect
    var node: int64
    var timing: TransitionTiming
}

/// How a part of a view transition runs: for how long, after how much, and
/// how it eases.
struct TransitionTiming {
    var duration: float64
    var delay: float64
    var easing: cascade.Easing

    /// A quarter second, eased, as the user agent's sheet has it. (Written
    /// out: a memberwise init with these defaults, called from page.vs, is
    /// what vsc_TODO.md's memberwise entry is about.)
    init() {
        duration = 0.25
        delay = 0
        easing = cascade.Easing.ease
    }

    init(duration: float64, delay: float64, easing: cascade.Easing) {
        self.duration = duration
        self.delay = delay
        self.easing = easing
    }

    /// How far along it is, eased, so long into the transition.
    func progress(elapsed: float64) -> float32 {
        var t = float32((elapsed - delay) / duration)
        if t < 0 { t = 0 }
        if t > 1 { t = 1 }
        return easing.Progress(t)
    }
}

