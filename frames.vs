package web

import (
    "image/draw"
    "web/fetch"
    "web/html"
    "web/layout"
    "web/paint"
)

// Nested documents: <iframe> (srcdoc, or src fetched through the page's
// fetcher), and an <object> or <embed> that points at HTML. Each is a Page
// of its own, laid out in its element's content box and painted there,
// clipped; the pointer, the wheel and, once it is clicked into, the
// keyboard go to it. Links in it navigate the frame.

final class Frame {
    let page: Page
    /// What its element says to show, to notice when that changes.
    let origin: string
    /// What it shows now: the origin, or where a link took it.
    var source: string
    var seen: int = 0

    init(page: Page, source: string) {
        self.page = page
        self.origin = source
        self.source = source
    }
}

extension Page {
    /// What an element's frame shows: "srcdoc:" and its text, or a URL
    /// resolved against the page, or "" for an empty document.
    func frameSource(node: html.Node) -> string {
        switch node.TagName {
        case "iframe":
            if let doc = node.GetAttribute("srcdoc") { return "srcdoc:" + doc }
            if let src = node.GetAttribute("src"), !src.isEmpty, src != "about:blank" { return Resolve(src) }
            return ""
        case "object":
            if let data = node.GetAttribute("data"), !data.isEmpty { return Resolve(data) }
            return ""
        default:
            if let src = node.GetAttribute("src"), !src.isEmpty { return Resolve(src) }
            return ""
        }
    }

    /// Loads a frame's document from its source.
    func loadFrame(f: Frame) {
        let src = f.source
        if src.hasPrefix("srcdoc:") {
            f.page.LoadHTML(string(src.dropFirst(7)), baseURL: baseURL)
        } else if src.isEmpty {
            f.page.LoadHTML("", baseURL: baseURL)
        } else if let bytes = Configuration.Fetcher.Fetch(src) {
            f.page.LoadBytes(bytes, baseURL: fetch.Directory(of: src))
        } else {
            f.page.LoadHTML("", baseURL: baseURL)
        }
    }

    /// Makes, loads and sizes the frames of the laid-out page; answers
    /// their display lists for paint.
    func syncFrames() -> [int64: paint.Subpage] {
        framePass += 1
        var out: [int64: paint.Subpage] = [:]
        for (id, box) in builder.byNode where box.Replaced == .frame {
            guard let node = box.Node else { continue }
            let source = frameSource(node)
            var f = frames[id]
            if f == nil || f!.origin != source {
                var config = Config(baseURL: baseURL, backgroundColor: draw.Color.transparent,
                                    fetcher: Configuration.Fetcher, defersImages: Configuration.DefersImages)
                config.BaseURL = baseURL
                let made = Frame(page: Page(configuration: config), source: source)
                let me = made
                made.page.OnNavigate { url in
                    me.source = url
                    self.loadFrame(me)
                    self.needsPaint = true
                }
                loadFrame(made)
                frames[id] = made
                f = made
            }
            let frame = f!
            frame.seen = framePass
            frame.page.SetColorScheme(dark: IsDark)
            let w = box.InnerWidth > 0 ? box.InnerWidth : 0
            let h = box.InnerHeight > 0 ? box.InnerHeight : 0
            frame.page.SetViewportSize(draw.Size(w, h))
            frame.page.update()
            out[id] = paint.Subpage(items: frame.page.displayList, scrollX: frame.page.scroll.X, scrollY: frame.page.scroll.Y)
            frame.page.needsRepaint = false
        }
        var gone: [int64] = []
        for (id, f) in frames where f.seen != framePass { gone.append(id) }
        for id in gone { frames[id] = nil }
        return out
    }

    /// Whether a frame has changed since it was last painted in.
    var framesNeedPaint: bool {
        for (_, f) in frames where f.page.NeedsRepaint() { return true }
        return false
    }

    /// The frame under a point of the view, and the point in its own
    /// view; nil where there is none.
    func frameAt(p: draw.Point) -> (frame: Frame, point: draw.Point)? {
        if frames.isEmpty { return nil }
        guard let hit = hitAt(p), let node = hit.Node, let f = frames[node.Id], let box = builder.byNode[node.Id] else { return nil }
        return framePoint(f, box, p)
    }

    func framePoint(f: Frame, box: layout.Box, p: draw.Point) -> (frame: Frame, point: draw.Point)? {
        let pos = layout.PagePosition(box)
        let local = draw.Point(p.X + scroll.X - pos.x - box.ContentX, p.Y + scroll.Y - pos.y - box.ContentY)
        if local.X < 0 || local.Y < 0 || local.X >= box.InnerWidth || local.Y >= box.InnerHeight { return nil }
        return (frame: f, point: local)
    }

    /// Sends an input to the frame it belongs to: the one under the
    /// pointer, the one a press started in until it is released, the one
    /// clicked into for keys. Nil where it is the page's own.
    func forwardToFrame(input: Input) -> EventResult? {
        if frames.isEmpty { return nil }
        switch input {
        case .pointerMoved(let p):
            lastPointer = p
            if let id = pressedFrame, let f = frames[id], let box = builder.byNode[id] {
                let pos = layout.PagePosition(box)
                let local = draw.Point(p.X + scroll.X - pos.x - box.ContentX, p.Y + scroll.Y - pos.y - box.ContentY)
                return frameResult(f, f.page.Handle(.pointerMoved(local)))
            }
            update()
            if let hit = frameAt(p) {
                if let old = hoveredFrame, old !== hit.frame { _ = old.page.Handle(.pointerLeft) }
                hoveredFrame = hit.frame
                let r = frameResult(hit.frame, hit.frame.page.Handle(.pointerMoved(hit.point)))
                cursor = hit.frame.page.DesiredCursor()
                return r
            }
            if let old = hoveredFrame {
                _ = old.page.Handle(.pointerLeft)
                hoveredFrame = nil
                needsPaint = true
            }
            return nil
        case .pointerDown(let e):
            update()
            if let hit = frameAt(e.Position) {
                var inner = e
                inner.Position = hit.point
                for (id, f) in frames where f === hit.frame { pressedFrame = id }
                focusedFrame = hit.frame
                return frameResult(hit.frame, hit.frame.page.Handle(.pointerDown(inner)))
            }
            focusedFrame = nil
            return nil
        case .pointerUp(let e):
            guard let id = pressedFrame else { return nil }
            pressedFrame = nil
            guard let f = frames[id], let box = builder.byNode[id] else { return nil }
            let pos = layout.PagePosition(box)
            var inner = e
            inner.Position = draw.Point(e.Position.X + scroll.X - pos.x - box.ContentX, e.Position.Y + scroll.Y - pos.y - box.ContentY)
            return frameResult(f, f.page.Handle(.pointerUp(inner)))
        case .pointerLeft:
            if let old = hoveredFrame {
                _ = old.page.Handle(.pointerLeft)
                hoveredFrame = nil
            }
            return nil
        case .wheel(let w):
            // A frame scrolls first; what it can't take scrolls the page.
            guard let hit = frameAt(lastPointer) else { return nil }
            let before = hit.frame.page.scroll
            _ = hit.frame.page.Handle(.wheel(w))
            let after = hit.frame.page.scroll
            if before.X == after.X && before.Y == after.Y { return nil }
            needsPaint = true
            return .handled
        case .keyDown(_), .keyUp(_), .text(_), .composition(_):
            guard let f = focusedFrame else { return nil }
            return frameResult(f, f.page.Handle(input))
        }
    }

    func frameResult(f: Frame, r: EventResult) -> EventResult {
        if f.page.NeedsRepaint() { needsPaint = true }
        return r
    }
}
