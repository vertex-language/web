package layout

import (
    "image/draw"
    "web/css"
)

/// What a box is laid out against: the width of the containing block,
/// and its height where that is known.
public struct ContainingBlock {
    public var Width: float32
    public var Height: float32?

    public init(width: float32, height: float32?) {
        Width = width
        Height = height
    }
}

/// Lays out a box tree: block flow, lines, flex, positioned boxes.
/// Positions come out relative to each box's parent; the root's are
/// relative to the viewport.
public final class Layout {
    public var ViewportWidth: float32
    public var ViewportHeight: float32
    /// Boxes with position: sticky, whose offsets follow the scroll.
    public var Sticky: [Box] = []
    /// Whether something here is placed by an anchor: a scroll moves it.
    public var HasAnchored: bool = false
    var anchored: [Box] = []
    /// The root being laid out: what fixed boxes are positioned against.
    var rootBox: Box? = nil

    public init(viewportWidth: float32, viewportHeight: float32) {
        ViewportWidth = viewportWidth
        ViewportHeight = viewportHeight
    }

    /// Lays out the whole tree from the root. The root box fills the
    /// viewport's width; its height is its content's.
    public func Run(root: Box) {
        Sticky = []
        rootBox = root
        let cb = ContainingBlock(width: ViewportWidth, height: ViewportHeight)
        root.X = 0
        root.Y = 0
        root.Positioned = []
        let flow = Flow(positioned: root, floats: FloatContext(), x: 0, y: 0)
        layoutBlock(root, cb: cb, flow: flow)
        root.X = root.Margin.Left
        root.Y = root.Margin.Top
        layoutPositioned(root, cb: cb)
        HasAnchored = !anchored.isEmpty
        if HasAnchored { resolveAnchors(root) }
        anchored = []
    }

    /// A box's content size at auto, without keeping that layout's result
    /// on the box beyond its own size.
    public func MeasureAuto(box: Box, height: bool) -> float32 {
        let style = box.Style
        if !height {
            let widths = intrinsicWidths(box, ignoringWidth: true)
            return style.BoxSizing == .borderBox ? widths.max : widths.max - box.Padding.Horizontal - box.Border.Horizontal
        }
        let saved = style.Height
        let savedHeight = box.Height
        style.Height = .auto
        let cb = ContainingBlock(width: box.Parent?.InnerWidth ?? ViewportWidth, height: nil)
        layoutFixed(box, width: box.Width, height: nil, cb: cb, flow: Flow(positioned: box, floats: FloatContext(), x: 0, y: 0))
        let measured = box.Height
        style.Height = saved
        box.Height = savedHeight
        return style.BoxSizing == .borderBox ? measured : measured - box.Padding.Vertical - box.Border.Vertical
    }

    // MARK: - Anchor positioning

    /// Places what anchor() and position-area name, once everything it may
    /// be anchored to is where it ends up. position-try's fallbacks are
    /// tried in turn, and the first that stays in the viewport used.
    func resolveAnchors(root: Box) {
        var named: [string: Box] = [:]
        func walk(b: Box) {
            // Text shares its element's style; it's the element that's named.
            if b.Kind != .text {
                for n in b.Style.AnchorNames { named[n] = b }
                // A popover's invoker is what it's anchored to by default.
                if let t = b.Node?.GetAttribute("popovertarget") { named["#invoker:" + t] = b }
            }
            for c in b.Children { walk(c) }
            for p in b.Positioned { walk(p) }
        }
        walk(root)
        for child in anchored { place(child, among: named, root: root) }
    }

    func place(child: Box, among named: [string: Box], root: Box) {
        let s = child.Style
        var tries: [(uses: [cascade.AnchorUse], area: [string])] = [(uses: s.AnchorUses, area: s.PositionArea)]
        for t in s.PositionTries {
            if let rule = cascade.PositionTryRules[t] {
                tries.append((uses: rule.Uses, area: rule.Area))
                continue
            }
            var uses = s.AnchorUses
            var area = s.PositionArea
            for word in t.split(separator: " ").map({ string($0) }) {
                if word == "flip-block" {
                    uses = uses.map { flippedUse($0, a: "top", b: "bottom") }
                    area = area.map { flippedWord($0, a: "top", b: "bottom") }
                } else if word == "flip-inline" {
                    uses = uses.map { flippedUse($0, a: "left", b: "right") }
                    area = area.map { flippedWord($0, a: "left", b: "right") }
                }
            }
            tries.append((uses: uses, area: area))
        }
        let viewX = root.ViewportScrollX
        let viewY = root.ViewportScrollY
        var first: (x: float32, y: float32, w: float32, h: float32)? = nil
        var chosen: (x: float32, y: float32, w: float32, h: float32)? = nil
        for t in tries {
            guard let spot = anchoredSpot(child, uses: t.uses, area: t.area, named: named) else { continue }
            if first == nil { first = spot }
            if spot.x >= viewX && spot.y >= viewY && spot.x + spot.w <= viewX + ViewportWidth && spot.y + spot.h <= viewY + ViewportHeight {
                chosen = spot
                break
            }
        }
        guard let at = chosen ?? first else { return }
        // position-visibility: hidden when it overflows, or its anchor is out
        // of view.
        child.AnchorHidden = false
        if s.PositionVisibility.contains("no-overflow") && chosen == nil { child.AnchorHidden = true }
        if s.PositionVisibility.contains("anchors-visible") {
            let key = s.PositionAnchor
            if let a = named[key] {
                let p = PagePosition(a)
                if p.x + a.Width < viewX || p.y + a.Height < viewY || p.x > viewX + ViewportWidth || p.y > viewY + ViewportHeight { child.AnchorHidden = true }
            }
        }
        if at.w != child.Width || at.h != child.Height {
            let cb = ContainingBlock(width: child.Parent?.PaddingBoxWidth ?? ViewportWidth, height: child.Parent?.PaddingBoxHeight)
            layoutFixed(child, width: at.w, height: at.h != child.Height ? at.h : nil, cb: cb, flow: Flow(positioned: child, floats: FloatContext(), x: 0, y: 0))
        }
        // Where it goes on the page, from where it hangs.
        let now = PagePosition(child)
        child.X += at.x - now.x
        child.Y += at.y - now.y
    }

    /// Where a box goes by these uses and this area, on the page; nil where
    /// it names an anchor there isn't.
    func anchoredSpot(child: Box, uses: [cascade.AnchorUse], area: [string], named: [string: Box]) -> (x: float32, y: float32, w: float32, h: float32)? {
        let s = child.Style
        func rect(name: string) -> (x: float32, y: float32, w: float32, h: float32)? {
            var key = name.isEmpty ? s.PositionAnchor : name
            if key.isEmpty, let id = child.Node?.GetAttribute("id") { key = "#invoker:" + id }
            guard let a = named[key] else { return nil }
            let p = PagePosition(a)
            return (x: p.x, y: p.y, w: a.Width, h: a.Height)
        }
        var w = child.Width
        var h = child.Height
        for u in uses where u.Property == "width" || u.Property == "height" {
            guard let a = rect(u.Name) else { return nil }
            let size = u.Edge == "height" || u.Edge == "block" ? a.h : (u.Edge == "width" || u.Edge == "inline" ? a.w : (u.Property == "width" ? a.w : a.h))
            if u.Property == "width" { w = size + u.Offset } else { h = size + u.Offset }
        }
        let start = PagePosition(child)
        var x = start.x
        var y = start.y
        func along(a: (x: float32, y: float32, w: float32, h: float32), u: cascade.AnchorUse, horizontal: bool) -> float32 {
            let low = horizontal ? a.x : a.y
            let size = horizontal ? a.w : a.h
            if u.Percent >= 0 { return low + size * u.Percent / 100 }
            switch u.Edge {
            case "right", "bottom", "end", "self-end": return low + size
            case "center": return low + size / 2
            default: return low
            }
        }
        for u in uses {
            switch u.Property {
            case "top":
                guard let a = rect(u.Name) else { return nil }
                y = along(a, u, horizontal: false) + u.Offset + child.Margin.Top
            case "bottom":
                guard let a = rect(u.Name) else { return nil }
                y = along(a, u, horizontal: false) - u.Offset - h - child.Margin.Bottom
            case "left":
                guard let a = rect(u.Name) else { return nil }
                x = along(a, u, horizontal: true) + u.Offset + child.Margin.Left
            case "right":
                guard let a = rect(u.Name) else { return nil }
                x = along(a, u, horizontal: true) - u.Offset - w - child.Margin.Right
            default:
                break
            }
        }
        if !area.isEmpty {
            guard let a = rect("") else { return nil }
            var acrossSet = false
            var downSet = false
            for word in area {
                switch word {
                case "top", "block-start", "y-start":
                    y = a.y - h - child.Margin.Bottom
                    downSet = true
                case "bottom", "block-end", "y-end":
                    y = a.y + a.h + child.Margin.Top
                    downSet = true
                case "span-bottom", "span-block-end":
                    y = a.y + child.Margin.Top
                    downSet = true
                case "span-top", "span-block-start":
                    y = a.y + a.h - h - child.Margin.Bottom
                    downSet = true
                case "left", "inline-start", "x-start":
                    x = a.x - w - child.Margin.Right
                    acrossSet = true
                case "right", "inline-end", "x-end":
                    x = a.x + a.w + child.Margin.Left
                    acrossSet = true
                case "span-right", "span-inline-end":
                    x = a.x + child.Margin.Left
                    acrossSet = true
                case "span-left", "span-inline-start":
                    x = a.x + a.w - w - child.Margin.Right
                    acrossSet = true
                default:
                    break
                }
            }
            // Over the anchor's middle on whichever axis wasn't said.
            if !acrossSet { x = a.x + (a.w - w) / 2 }
            if !downSet { y = a.y + (a.h - h) / 2 }
        }
        // anchor-center: over the anchor's middle on that axis.
        if s.JustifySelf == "anchor-center", let a = rect("") { x = a.x + (a.w - w) / 2 }
        if s.AlignSelfWord == "anchor-center", let a = rect("") { y = a.y + (a.h - h) / 2 }
        return (x: x, y: y, w: w, h: h)
    }

    // MARK: - Edges and sizes

    /// Resolves a box's margins, borders and padding against its
    /// containing block's width; auto margins are 0 until the width is
    /// known.
    func resolveEdges(box: Box, cbWidth: float32) {
        let s = box.Style
        box.Margin = draw.Edges(s.MarginTop.Or(0, base: cbWidth), s.MarginRight.Or(0, base: cbWidth),
                                s.MarginBottom.Or(0, base: cbWidth), s.MarginLeft.Or(0, base: cbWidth))
        box.Padding = draw.Edges(s.PaddingTop.Or(0, base: cbWidth), s.PaddingRight.Or(0, base: cbWidth),
                                 s.PaddingBottom.Or(0, base: cbWidth), s.PaddingLeft.Or(0, base: cbWidth))
        box.Border = s.BorderWidths
    }

    /// The border-box width a length gives, for box-sizing.
    func borderBoxWidth(box: Box, contentWidth: float32) -> float32 {
        return contentWidth + box.Padding.Horizontal + box.Border.Horizontal
    }

    func widthFromStyle(box: Box, length: css.Length, cbWidth: float32) -> float32? {
        guard let v = length.Resolve(cbWidth) else { return nil }
        if box.Style.BoxSizing == .borderBox { return v }
        return borderBoxWidth(box, contentWidth: v)
    }

    func heightFromStyle(box: Box, length: css.Length, cbHeight: float32?) -> float32? {
        var base: float32 = 0
        if case .percent = length {
            guard let h = cbHeight else { return nil }
            base = h
        }
        // A calc() with a percentage in it needs the height as much.
        if case .calc(_, let p) = length, p != 0 {
            guard let h = cbHeight else { return nil }
            base = h
        }
        guard let v = length.Resolve(base) else { return nil }
        if box.Style.BoxSizing == .borderBox { return v }
        return v + box.Padding.Vertical + box.Border.Vertical
    }

    /// The border-box height aspect-ratio gives a box of its width, or
    /// nil where it has no ratio. The ratio is of the box-sizing box.
    func heightFromRatio(box: Box) -> float32? {
        let r = box.Style.AspectRatio
        if r <= 0 { return nil }
        if box.Style.BoxSizing == .borderBox { return box.Width / r }
        let inner = box.Width - box.Padding.Horizontal - box.Border.Horizontal
        return (inner > 0 ? inner : 0) / r + box.Padding.Vertical + box.Border.Vertical
    }

    /// Clamps a border-box width to min-width and max-width.
    func clampWidth(box: Box, width: float32, cbWidth: float32) -> float32 {
        var w = width
        if let max = widthFromStyle(box, box.Style.MaxWidth, cbWidth: cbWidth), w > max { w = max }
        if let min = widthFromStyle(box, box.Style.MinWidth, cbWidth: cbWidth), w < min { w = min }
        let edges = box.Padding.Horizontal + box.Border.Horizontal
        if w < edges { w = edges }
        return w
    }

    func clampHeight(box: Box, height: float32, cbHeight: float32?) -> float32 {
        var h = height
        if let max = heightFromStyle(box, box.Style.MaxHeight, cbHeight: cbHeight), h > max { h = max }
        if let min = heightFromStyle(box, box.Style.MinHeight, cbHeight: cbHeight), h < min { h = min }
        let edges = box.Padding.Vertical + box.Border.Vertical
        if h < edges { h = edges }
        return h
    }

    // MARK: - Blocks

    /// Lays out a block-level box in normal flow: its width from the
    /// containing block, its content, then its height. Sets Width,
    /// Height and the edges; the caller places X and Y.
    func layoutBlock(box: Box, cb: ContainingBlock, flow: Flow) {
        resolveEdges(box, cbWidth: cb.Width)
        box.Positioned = []
        box.ColumnFragments = []
        let s = box.Style

        if box.Kind == .replaced {
            sizeReplaced(box, cb: cb)
            return
        }

        // Width: given, or the containing block's less the margins.
        let available = cb.Width - box.Margin.Horizontal
        if let w = widthFromStyle(box, s.Width, cbWidth: cb.Width) {
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
            // Auto margins share what is left: centring.
            let free = cb.Width - box.Width
            if s.MarginLeft.IsAuto && s.MarginRight.IsAuto {
                box.Margin.Left = free / 2
                box.Margin.Right = free / 2
            } else if s.MarginLeft.IsAuto {
                box.Margin.Left = free - box.Margin.Right
            } else if s.MarginRight.IsAuto {
                box.Margin.Right = free - box.Margin.Left
            } else if rightToLeftContainer(box) {
                // Over-constrained: the end margin gives way, which right
                // to left is the left one.
                box.Margin.Left = free - box.Margin.Right
            }
        } else if s.Width == .minContent || s.Width == .maxContent || s.Width == .fitContent || box.Style.Float != .none || box.Style.IsOutOfFlow || box.Style.Display == .table || box.Style.Display == .inlineTable {
            let widths = intrinsicWidths(box)
            var w = widths.max
            if s.Width == .minContent { w = widths.min }
            if w > available { w = available > widths.min ? available : widths.min }
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
        } else {
            box.Width = clampWidth(box, available > 0 ? available : 0, cbWidth: cb.Width)
            // A max-width that left room: auto margins take it.
            let free = cb.Width - box.Width
            if free > 0 {
                if s.MarginLeft.IsAuto && s.MarginRight.IsAuto {
                    box.Margin.Left = free / 2
                    box.Margin.Right = free / 2
                } else if s.MarginLeft.IsAuto {
                    box.Margin.Left = free - box.Margin.Right
                } else if s.MarginRight.IsAuto {
                    box.Margin.Right = free - box.Margin.Left
                } else if rightToLeftContainer(box) {
                    box.Margin.Left = free - box.Margin.Right
                }
            }
        }

        // A height given up front is what the children's percentages
        // measure against.
        let givenHeight = heightFromStyle(box, s.Height, cbHeight: cb.Height)
        var ratioHeight: float32? = nil
        if givenHeight == nil { ratioHeight = heightFromRatio(box) }
        box.DefiniteInnerHeight = nil
        var definite = givenHeight
        if definite == nil { definite = ratioHeight }
        if let g = definite {
            box.DefiniteInnerHeight = clampHeight(box, g, cbHeight: cb.Height) - box.Padding.Vertical - box.Border.Vertical
        }
        var inner = box.IsFormattingRoot ? flow.root(box) : (s.IsPositioned ? flow.positionedBy(box) : flow)
        // A transform, a filter or containment makes the box what its
        // fixed descendants are placed against, instead of the viewport.
        if s.HasTransform || s.WillChangeContains || s.Perspective > 0 || s.Preserve3D || !s.Filters.isEmpty || s.ContainPaint || s.LayoutContained { inner.fixed = box }
        let contentHeight = layoutContent(box, flow: inner)

        // Height: given, or the content's, or the ratio's where the
        // content fits in it.
        var h = contentHeight + box.Padding.Vertical + box.Border.Vertical
        if let given = givenHeight {
            h = given
        } else if let r = ratioHeight {
            if r > h { h = r }
        }
        box.Height = clampHeight(box, h, cbHeight: cb.Height)
        box.ContentHeight = contentHeight
        applyRelativeOffsets(box, cbWidth: cb.Width, cbHeight: cb.Height)
        if box.Style.IsPositioned || (!box.Positioned.isEmpty && box.Parent != nil) {
            layoutPositioned(box, cb: ContainingBlock(width: box.PaddingBoxWidth, height: box.PaddingBoxHeight))
        }
    }

    /// Hands a box taken out of the flow to what it is positioned
    /// against: its positioned ancestor, or for position: fixed the
    /// viewport (the root) or the ancestor standing in for it.
    func attachPositioned(child: Box, flow: Flow) {
        if child.Style.Position == .fixed {
            child.FixedToViewport = flow.fixed == nil
            (flow.fixed ?? rootBox ?? flow.positioned).Positioned.append(child)
        } else {
            child.FixedToViewport = false
            flow.positioned.Positioned.append(child)
        }
    }

    /// Lays out what a block holds and answers the content height.
    /// A box whose text runs down the page: its content set as if horizontal
    /// across the box's height, then told how wide that made the box.
    /// Answers the box's content height.
    func layoutVertical(box: Box, inner: Box, flow: Flow) -> float32 {
        let s = box.Style
        var across = box.DefiniteInnerHeight
        if across == nil {
            // As long as its text wants, up to the viewport.
            let room = ViewportHeight - box.Padding.Vertical - box.Border.Vertical
            let wanted = intrinsicWidths(inner).max
            across = wanted < room ? wanted : (room > 0 ? room : wanted)
        }
        let definite: float32? = s.Width.IsAuto ? nil : box.InnerWidth
        inner.X = box.ContentX
        inner.Y = box.ContentY
        var fixedInner = inner.Style.Width
        fixedInner = .px(across!)
        inner.Style.Width = fixedInner
        layoutBlock(inner, cb: ContainingBlock(width: across!, height: definite), flow: flow.root(inner))
        inner.X = box.ContentX
        inner.Y = box.ContentY
        var along = inner.Height
        if let d = definite { along = d } else if s.Width.IsAuto {
            box.Width = along + box.Padding.Horizontal + box.Border.Horizontal
        }
        inner.BlockAxisSize = along
        // vertical-lr: the lines go the other way across.
        if s.WritingMode == "vertical-lr" { mirrorBlockAxis(inner, size: inner.ContentHeight) }
        return across!
    }

    /// Stacks what a box holds the other way down it.
    func mirrorBlockAxis(box: Box, size: float32) {
        var i = 0
        while i < box.Lines.count {
            let oldY = box.Lines[i].Y
            let moved = box.ContentY + size - (oldY - box.ContentY) - box.Lines[i].Height - oldY
            box.Lines[i].Y += moved
            var k = 0
            while k < box.Lines[i].Fragments.count {
                box.Lines[i].Fragments[k].Y += moved
                k += 1
            }
            k = 0
            while k < box.Lines[i].Spans.count {
                box.Lines[i].Spans[k].Y += moved
                k += 1
            }
            i += 1
        }
        for c in box.Children where c.Kind == .block || c.Kind == .inlineBlock {
            if c.Style.IsOutOfFlow { continue }
            c.Y = box.ContentY + size - (c.Y - box.ContentY) - c.Height
            mirrorBlockAxis(c, size: c.ContentHeight)
        }
    }

    func layoutContent(box: Box, flow: Flow) -> float32 {
        if let inner = box.VerticalContent { return layoutVertical(box, inner: inner, flow: flow) }
        let contentWidth = box.InnerWidth
        var height: float32 = 0
        if box.Style.Display == .table || box.Style.Display == .inlineTable {
            height = layoutTable(box, contentWidth: contentWidth, flow: flow)
        } else if box.Style.IsFlexContainer {
            height = layoutFlex(box, contentWidth: contentWidth, flow: flow)
            if box.Style.Direction == .rtl { mirrorChildren(box) }
        } else if box.Style.IsGridContainer {
            height = layoutGrid(box, contentWidth: contentWidth, flow: flow)
            if box.Style.Direction == .rtl { mirrorChildren(box) }
        } else if box.Style.IsMultiColumn && box.Kind == .block {
            height = layoutColumns(box, contentWidth: contentWidth, flow: flow)
        } else if box.HasInlineChildren {
            height = layoutInline(box, contentWidth: contentWidth, flow: flow)
        } else {
            height = layoutBlockChildren(box, contentWidth: contentWidth, flow: flow)
        }
        // A formatting root holds its floats: it grows to their bottom.
        if flow.x == 0 && flow.y == 0 && (box.IsFormattingRoot || box.Parent == nil) {
            let floatsBottom = flow.floats.bottom - box.ContentY
            if floatsBottom > height { height = floatsBottom }
        }
        // Size containment, and content-visibility: hidden: the content
        // doesn't size the box; contain-intrinsic-height stands in.
        if box.Style.SizeContained || box.Style.ContentVisibility == "hidden" {
            height = box.Style.ContainIntrinsicHeight?.Resolve(0) ?? 0
        }
        return height
    }

    /// Whether a box's containing block runs right to left: an in-flow
    /// block there sits against the right.
    func rightToLeftContainer(box: Box) -> bool {
        guard let p = box.Parent else { return false }
        return p.Style.Direction == .rtl && !box.Style.IsOutOfFlow && box.Style.Float == .none
    }

    /// Flex and grid laid out left to right, turned round for right to
    /// left: each in-flow child's margin box mirrored in the content
    /// box, its margins staying on their sides.
    func mirrorChildren(box: Box) {
        let left = box.ContentX
        let right = box.ContentX + box.InnerWidth
        for c in box.Children where !c.Style.IsOutOfFlow {
            c.X = left + right - c.X - c.Width + c.Margin.Left - c.Margin.Right
        }
    }

    /// Stacks block children top to bottom, collapsing the margins that
    /// meet: adjacent siblings', and a first or last child's with the
    /// parent's where nothing separates them.
    func layoutBlockChildren(box: Box, contentWidth: float32, flow: Flow) -> float32 {
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(box))
        // The content box's corner in the formatting context, for floats.
        let rootX = flow.x + box.ContentX
        let rootY = flow.y + box.ContentY
        var y: float32 = 0
        // The margin waiting to be placed: the largest positive and the
        // most negative seen since the last content.
        var positive: float32 = 0
        var negative: float32 = 0
        var first = true
        // The root's margins never collapse with its children's (CSS 2
        // 8.3.1): what is positioned against it stays at the page's top.
        let canCollapseTop = box.Border.Top == 0 && box.Padding.Top == 0 && !box.IsFormattingRoot && box.Parent != nil
        var firstCollapsed = false
        var lastChild: Box? = nil
        var contentRight: float32 = 0

        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed {
                // Out of flow: its static position is where it would
                // have been.
                child.X = box.ContentX
                child.Y = box.ContentY + y + positive + negative
                attachPositioned(child, flow)
                child.Parent = box
                continue
            }
            if child.Style.Float != .none {
                // A float takes its own width and goes to the side, as
                // high as the floats before it allow; the flow's y is
                // untouched.
                layoutBlock(child, cb: cb, flow: flow.root(child))
                let top = rootY + y + positive + negative
                let placed = flow.floats.place(child, left: child.Style.Float == .left, y: top,
                                               containerLeft: rootX, containerRight: rootX + contentWidth)
                child.X = placed.x - rootX + box.ContentX + child.Margin.Left
                child.Y = placed.y - rootY + box.ContentY + child.Margin.Top
                if child.X + child.Width > contentRight { contentRight = child.X + child.Width }
                continue
            }
            // A list item whose content starts with a block hands its
            // marker to that block's first line.
            if first && !box.Marker.isEmpty && child.Marker.isEmpty {
                child.Marker = box.Marker
                child.MarkerImage = box.MarkerImage
                child.MarkerVector = box.MarkerVector
                child.MarkerImageSize = box.MarkerImageSize
            }
            if child.Style.Clear != .none {
                // Move down past the floats cleared, margins and all.
                let cleared = flow.floats.clearance(child.Style.Clear, at: rootY + y + positive + negative)
                let need = cleared - rootY
                if need > y + positive + negative {
                    y = need
                    positive = 0
                    negative = 0
                }
            }
            resolveEdges(child, cbWidth: contentWidth)
            let childTop = child.Margin.Top
            var pendingTop = positive
            var pendingBottom = negative
            if childTop >= 0 { if childTop > pendingTop { pendingTop = childTop } } else { if childTop < pendingBottom { pendingBottom = childTop } }
            layoutBlock(child, cb: cb, flow: flow.at(box.ContentX + child.Margin.Left, box.ContentY + y + pendingTop + pendingBottom))

            // The child's top margin joins the pending one.
            let top = child.Margin.Top
            if top >= 0 { if top > positive { positive = top } } else { if top < negative { negative = top } }

            if first && canCollapseTop && collapsesThrough(child, top: true) {
                // The first child's margin escapes to the parent: the
                // parent's top margin becomes the collapsed pair.
                let joined = positive + negative
                box.Margin.Top = collapse(box.Margin.Top, joined)
                positive = 0
                negative = 0
                firstCollapsed = true
            }
            let margin = positive + negative
            child.X = box.ContentX + child.Margin.Left
            child.Y = box.ContentY + y + margin
            y += margin + child.Height
            positive = 0
            negative = 0
            let bottom = child.Margin.Bottom
            if bottom >= 0 { positive = bottom } else { negative = bottom }
            first = false
            lastChild = child
            if child.X + child.Width > contentRight { contentRight = child.X + child.Width }
        }
        _ = firstCollapsed
        // The last child's bottom margin: kept inside the box when the
        // box has a bottom edge or a set height, and otherwise passed to
        // the parent.
        let canCollapseBottom = box.Border.Bottom == 0 && box.Padding.Bottom == 0 && !box.IsFormattingRoot && box.Style.Height.IsAuto && box.Parent != nil
        if lastChild != nil && canCollapseBottom {
            box.Margin.Bottom = collapse(box.Margin.Bottom, positive + negative)
        } else {
            y += positive + negative
        }
        box.ContentWidth = contentRight - box.ContentX
        return y > 0 ? y : 0
    }

    /// Two collapsing margins: the larger of positives, the more negative
    /// of negatives, or their sum when mixed.
    func collapse(a: float32, b: float32) -> float32 {
        if a >= 0 && b >= 0 { return a > b ? a : b }
        if a < 0 && b < 0 { return a < b ? a : b }
        return a + b
    }

    /// Whether a box's own top (or bottom) margin can collapse with its
    /// parent's: nothing of the box lies between them.
    func collapsesThrough(box: Box, top: Bool) -> bool {
        if box.IsFormattingRoot || box.Kind != .block { return false }
        if top { return box.Border.Top == 0 && box.Padding.Top == 0 }
        return box.Border.Bottom == 0 && box.Padding.Bottom == 0
    }

    /// The content height a box's children can take percentages of, if
    /// the box's height is known before its content is.
    func definiteInnerHeight(box: Box) -> float32? {
        if let h = box.DefiniteInnerHeight { return h }
        if let h = box.Style.Height.Pixels {
            if box.Style.BoxSizing == .borderBox { return h - box.Padding.Vertical - box.Border.Vertical }
            return h
        }
        return nil
    }

    // MARK: - Replaced and atomic boxes

    /// Whether a replaced box keeps its intrinsic proportions when only one
    /// of its sizes is given: an image or an SVG does, a control does not.
    func keepsRatio(box: Box) -> bool {
        return box.Replaced == .image || box.Replaced == .svg || box.Replaced == .video
    }

    /// Sizes an image or control from its style, or its own size.
    func sizeReplaced(box: Box, cb: ContainingBlock) {
        let s = box.Style
        var w: float32? = widthFromStyle(box, s.Width, cbWidth: cb.Width)
        var h: float32? = heightFromStyle(box, s.Height, cbHeight: cb.Height)
        let iw = box.IntrinsicWidth
        let ih = box.IntrinsicHeight
        let edgesW = box.Padding.Horizontal + box.Border.Horizontal
        let edgesH = box.Padding.Vertical + box.Border.Vertical
        if w == nil && h == nil && box.RatioOnly && iw > 0 && cb.Width - box.Margin.Horizontal > edgesW {
            let inner = cb.Width - box.Margin.Horizontal - edgesW
            w = inner + edgesW
            h = inner * ih / iw + edgesH
        } else if w == nil && h == nil {
            w = iw + edgesW
            h = ih + edgesH
        } else if w == nil {
            // Keep the image's proportions. A control has none: its
            // width is its own whatever its height.
            let inner = h! - edgesH
            w = (keepsRatio(box) && ih > 0 ? inner * iw / ih : iw) + edgesW
        } else if h == nil {
            let inner = w! - edgesW
            if s.AspectRatio > 0 {
                h = inner / s.AspectRatio + edgesH
            } else {
                // A 300px-wide input is its own height, not one scaled
                // to its width.
                h = (keepsRatio(box) && iw > 0 ? inner * ih / iw : ih) + edgesH
            }
        }
        box.Width = clampWidth(box, w!, cbWidth: cb.Width)
        if (box.Replaced == .image || box.Replaced == .video) && iw > 0 && ih > 0 && box.Width != w! && s.Height.IsAuto {
            h = (box.Width - edgesW) * ih / iw + edgesH
        }
        box.Height = clampHeight(box, h!, cbHeight: cb.Height)
        box.Baseline = box.Height
        if box.Replaced == .textInput || box.Replaced == .button || box.Replaced == .select {
            let face = s.Face
            let lh = face.LineHeight
            box.Baseline = box.Border.Top + box.Padding.Top + (box.InnerHeight - lh) / 2 + face.Ascent
        }
    }

    /// Lays out an atomic inline box -- inline-block, inline-flex or a
    /// control -- for a line: it takes its own width, up to what the
    /// line offers.
    func layoutAtomic(box: Box, cb: ContainingBlock, flow: Flow) {
        if box.Kind == .replaced {
            resolveEdges(box, cbWidth: cb.Width)
            sizeReplaced(box, cb: cb)
            return
        }
        resolveEdges(box, cbWidth: cb.Width)
        box.Positioned = []
        let s = box.Style
        if let w = widthFromStyle(box, s.Width, cbWidth: cb.Width) {
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
        } else {
            let widths = intrinsicWidths(box)
            let available = cb.Width - box.Margin.Horizontal
            var w = widths.max
            if w > available { w = available > widths.min ? available : widths.min }
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
        }
        let givenHeight = heightFromStyle(box, s.Height, cbHeight: cb.Height)
        var ratioHeight: float32? = nil
        if givenHeight == nil { ratioHeight = heightFromRatio(box) }
        box.DefiniteInnerHeight = nil
        var definite = givenHeight
        if definite == nil { definite = ratioHeight }
        if let g = definite { box.DefiniteInnerHeight = g - box.Padding.Vertical - box.Border.Vertical }
        let contentHeight = layoutContent(box, flow: flow.root(box))
        var h = contentHeight + box.Padding.Vertical + box.Border.Vertical
        if let given = givenHeight {
            h = given
        } else if let r = ratioHeight {
            if r > h { h = r }
        }
        box.Height = clampHeight(box, h, cbHeight: cb.Height)
        box.ContentHeight = contentHeight
        // The baseline is the last line's, unless overflow hides it.
        box.Baseline = nil
        if !s.ClipsOverflow {
            box.Baseline = lastBaseline(box)
        }
        if box.Style.IsPositioned {
            layoutPositioned(box, cb: ContainingBlock(width: box.PaddingBoxWidth, height: box.PaddingBoxHeight))
        }
    }

    /// The baseline of the last line in a box, from the box's top.
    func lastBaseline(box: Box) -> float32? {
        if !box.Lines.isEmpty {
            let line = box.Lines[box.Lines.count - 1]
            return line.Y + line.Baseline
        }
        var i = box.Children.count - 1
        while i >= 0 {
            let c = box.Children[i]
            if c.Kind == .block && !c.Style.IsOutOfFlow {
                if let b = lastBaseline(c) { return c.Y + b }
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Intrinsic widths

    /// The narrowest and widest a box would be if its width were its
    /// content's: the longest word, and the whole content on one line.
    /// Border-box widths.
    func intrinsicWidths(box: Box) -> (min: float32, max: float32) {
        return intrinsicWidths(box, ignoringWidth: false)
    }

    func intrinsicWidths(box: Box, ignoringWidth: Bool) -> (min: float32, max: float32) {
        let s = box.Style
        let edges = box.Padding.Horizontal + box.Border.Horizontal
        // Across a vertical box's lines is as wide as they stack.
        if let inner = box.VerticalContent {
            let across = intrinsicWidths(inner).max
            // Its lines are as long as its own height, where it has one.
            var room = ViewportHeight > 0 ? ViewportHeight : across
            if let given = heightFromStyle(box, s.Height, cbHeight: nil) { room = given - box.Padding.Vertical - box.Border.Vertical }
            let measure = Flow(positioned: inner, floats: FloatContext(), x: 0, y: 0)
            let saved = inner.Style.Width
            inner.Style.Width = .px(across < room ? across : room)
            layoutBlock(inner, cb: ContainingBlock(width: across < room ? across : room, height: nil), flow: measure)
            inner.Style.Width = saved
            return (min: inner.Height + edges, max: inner.Height + edges)
        }
        if box.Kind == .replaced {
            return replacedIntrinsicWidths(box, ignoringWidth: ignoringWidth)
        }
        if (s.InlineSizeContained || s.ContentVisibility == "hidden") && (ignoringWidth || s.Width.IsAuto) {
            let w = (s.ContainIntrinsicWidth?.Resolve(0) ?? 0) + edges
            return (min: w, max: w)
        }
        if let w = s.Width.Pixels, !ignoringWidth {
            let bw = s.BoxSizing == .borderBox ? w : w + edges
            return (min: bw, max: bw)
        }
        var minW: float32 = 0
        var maxW: float32 = 0
        if s.Display == .table || s.Display == .inlineTable {
            let w = tableIntrinsicWidths(box)
            minW = w.min
            maxW = w.max
        } else if s.IsFlexContainer {
            var sumMax: float32 = 0
            var maxMin: float32 = 0
            var sumMin: float32 = 0
            var maxMax: float32 = 0
            var n = 0
            for c in box.Children where !c.Style.IsOutOfFlow {
                resolveEdges(c, cbWidth: 0)
                let w = intrinsicWidths(c)
                sumMax += w.max + c.Margin.Horizontal
                sumMin += w.min + c.Margin.Horizontal
                if w.min + c.Margin.Horizontal > maxMin { maxMin = w.min + c.Margin.Horizontal }
                if w.max + c.Margin.Horizontal > maxMax { maxMax = w.max + c.Margin.Horizontal }
                n += 1
            }
            let gap = s.ColumnGap.Or(0, base: 0) * float32(n > 1 ? n - 1 : 0)
            if s.FlexDirection.IsRow {
                minW = (s.FlexWrap == .nowrap ? sumMin : maxMin) + gap
                maxW = sumMax + gap
            } else {
                minW = maxMin
                maxW = maxMax
            }
        } else if box.HasInlineChildren {
            let w = inlineIntrinsicWidths(box)
            minW = w.min
            maxW = w.max
        } else {
            for c in box.Children where !c.Style.IsOutOfFlow {
                resolveEdges(c, cbWidth: 0)
                let w = intrinsicWidths(c)
                let m = c.Margin.Horizontal
                if w.min + m > minW { minW = w.min + m }
                if w.max + m > maxW { maxW = w.max + m }
            }
        }
        if s.IsMultiColumn && box.Kind == .block {
            // Columns side by side: each as wide as the content needs,
            // or column-width where that is given (Multi-column 1 §3.4).
            let gap = s.ColumnGapNormal ? s.FontSize : s.ColumnGap.Or(0, base: 0)
            let n = float32(s.ColumnCount > 0 ? s.ColumnCount : 1)
            if let cw = s.ColumnWidth {
                minW = minW > cw ? minW : cw
                maxW = n * (maxW > cw ? maxW : cw) + (n - 1) * gap
            } else {
                maxW = n * maxW + (n - 1) * gap
            }
        }
        if let max = s.MaxWidth.Pixels {
            let bw = s.BoxSizing == .borderBox ? max : max + edges
            if maxW + edges > bw { maxW = bw - edges }
            if minW + edges > bw { minW = bw - edges }
        }
        if let min = s.MinWidth.Pixels {
            let bw = s.BoxSizing == .borderBox ? min : min + edges
            if maxW + edges < bw { maxW = bw - edges }
            if minW + edges < bw { minW = bw - edges }
        }
        return (min: minW + edges, max: maxW + edges)
    }

    /// A replaced element's contributions (CSS Sizing 3 §5): its natural
    /// width -- the width CSS fixes, or the height CSS fixes times its
    /// ratio, or its own -- within fixed min- and max-widths. Percentages
    /// have nothing to resolve against here, so a percentage max-width
    /// limits nothing; and an element whose width or max-width is a
    /// percentage is compressible, contributing nothing to min-content.
    func replacedIntrinsicWidths(box: Box, ignoringWidth: Bool) -> (min: float32, max: float32) {
        let s = box.Style
        let edges = box.Padding.Horizontal + box.Border.Horizontal
        var w: float32
        if let fixed = s.Width.Pixels, !ignoringWidth {
            w = s.BoxSizing == .borderBox ? fixed : fixed + edges
        } else if let h = s.Height.Pixels, box.IntrinsicHeight > 0 {
            let inner = s.BoxSizing == .borderBox ? h - box.Padding.Vertical - box.Border.Vertical : h
            w = inner * box.IntrinsicWidth / box.IntrinsicHeight + edges
        } else {
            w = box.IntrinsicWidth + edges
        }
        if let max = s.MaxWidth.Pixels {
            let bw = s.BoxSizing == .borderBox ? max : max + edges
            if w > bw { w = bw }
        }
        if let min = s.MinWidth.Pixels {
            let bw = s.BoxSizing == .borderBox ? min : min + edges
            if w < bw { w = bw }
        }
        var compressible = false
        if case .percent(_) = s.MaxWidth { compressible = true }
        if case .calc(_, _) = s.MaxWidth { compressible = true }
        if !ignoringWidth {
            if case .percent(_) = s.Width { compressible = true }
            if case .calc(_, _) = s.Width { compressible = true }
        }
        return (min: compressible ? edges : w, max: w)
    }

    // MARK: - Positioned boxes

    /// Lays out the boxes positioned against a box, after its flow: each
    /// against the box's padding box, at its insets, or where it would
    /// have been where it has none.
    func layoutPositioned(box: Box, cb: ContainingBlock) {
        if box.Positioned.isEmpty { return }
        let list = box.Positioned
        let padX = box.Kind == .block && box.Parent != nil ? box.PaddingBoxX : 0
        let padY = box.Kind == .block && box.Parent != nil ? box.PaddingBoxY : 0
        let cbWidth = cb.Width
        let cbHeight = cb.Height ?? 0
        for child in list {
            let s = child.Style
            if s.IsAnchored { anchored.append(child) }
            // The static position was written into X and Y by the flow
            // layout, relative to the flow parent; move it to be relative
            // to this containing block.
            var staticX = child.X
            var staticY = child.Y
            var p = child.Parent
            while let parent = p, parent.Id != box.Id {
                staticX += parent.X
                staticY += parent.Y
                p = parent.Parent
            }
            staticX -= padX
            staticY -= padY

            resolveEdges(child, cbWidth: cbWidth)
            let left = s.Left.Resolve(cbWidth)
            let right = s.Right.Resolve(cbWidth)
            let top = s.Top.Resolve(cbHeight)
            let bottom = s.Bottom.Resolve(cbHeight)

            if child.Kind == .replaced {
                sizeReplaced(child, cb: ContainingBlock(width: cbWidth, height: cbHeight))
            } else {
                if let w = widthFromStyle(child, s.Width, cbWidth: cbWidth) {
                    child.Width = clampWidth(child, w, cbWidth: cbWidth)
                } else if let l = left, let r = right, !isSizingKeyword(s.Width) {
                    child.Width = clampWidth(child, cbWidth - l - r - child.Margin.Horizontal, cbWidth: cbWidth)
                } else {
                    let widths = intrinsicWidths(child)
                    var available = cbWidth - child.Margin.Horizontal
                    if let l = left { available -= l } else if let r = right { available -= r } else { available -= staticX }
                    var w = widths.max
                    if w > available { w = available > widths.min ? available : widths.min }
                    child.Width = clampWidth(child, w, cbWidth: cbWidth)
                }
                child.Positioned = []
                child.DefiniteInnerHeight = nil
                if let given = heightFromStyle(child, s.Height, cbHeight: cbHeight) {
                    child.DefiniteInnerHeight = given - child.Padding.Vertical - child.Border.Vertical
                } else if let t = top, let b = bottom, !isSizingKeyword(s.Height) {
                    child.DefiniteInnerHeight = cbHeight - t - b - child.Margin.Vertical - child.Padding.Vertical - child.Border.Vertical
                }
                // A transform, a filter or containment here holds fixed descendants too.
                var childFlow = Flow(positioned: child, floats: FloatContext(), x: 0, y: 0)
                if s.HasTransform || s.WillChangeContains || s.Perspective > 0 || s.Preserve3D || !s.Filters.isEmpty || s.ContainPaint || s.LayoutContained { childFlow.fixed = child }
                let contentHeight = layoutContent(child, flow: childFlow)
                var h = contentHeight + child.Padding.Vertical + child.Border.Vertical
                if let given = heightFromStyle(child, s.Height, cbHeight: cbHeight) {
                    h = given
                } else if let t = top, let b = bottom, !isSizingKeyword(s.Height) {
                    h = cbHeight - t - b - child.Margin.Vertical
                }
                child.Height = clampHeight(child, h, cbHeight: cbHeight)
                child.ContentHeight = contentHeight
            }
            // Both insets and auto margins: the margins share what is
            // left, which centers the box (CSS 2 10.3.7 and 10.6.4).
            if let l = left, let r = right, s.MarginLeft.IsAuto && s.MarginRight.IsAuto {
                let free = cbWidth - l - r - child.Width
                child.Margin.Left = free > 0 ? free / 2 : 0
                child.Margin.Right = free > 0 ? free / 2 : 0
            }
            if let t = top, let b = bottom, s.MarginTop.IsAuto && s.MarginBottom.IsAuto {
                let free = cbHeight - t - b - child.Height
                child.Margin.Top = free > 0 ? free / 2 : 0
                child.Margin.Bottom = free > 0 ? free / 2 : 0
            }
            if let l = left {
                child.X = padX + l + child.Margin.Left
            } else if let r = right {
                child.X = padX + cbWidth - r - child.Width - child.Margin.Right
            } else if s.Direction == .rtl, let flowParent = child.Parent {
                // Its static place, seen from the right.
                var from = flowParent.ContentX
                var cur: Box? = flowParent
                while let up = cur, up.Id != box.Id {
                    from += up.X
                    cur = up.Parent
                }
                from -= padX
                let to = from + flowParent.InnerWidth
                child.X = padX + from + to - staticX - child.Width - child.Margin.Right
            } else {
                child.X = padX + staticX + child.Margin.Left
            }
            if let t = top {
                child.Y = padY + t + child.Margin.Top
            } else if let b = bottom {
                child.Y = padY + cbHeight - b - child.Height - child.Margin.Bottom
            } else {
                child.Y = padY + staticY + child.Margin.Top
            }
            child.Parent = box
            layoutPositioned(child, cb: ContainingBlock(width: child.PaddingBoxWidth, height: child.PaddingBoxHeight))
        }
    }

    /// Applies relative positioning after layout: the box is drawn
    /// shifted by its insets, its place in the flow kept.
    func applyRelativeOffsets(box: Box, cbWidth: float32, cbHeight: float32?) {
        let s = box.Style
        box.OffsetX = 0
        box.OffsetY = 0
        if s.Position == .relative {
            if let l = s.Left.Resolve(cbWidth) { box.OffsetX = l }
            else if let r = s.Right.Resolve(cbWidth) { box.OffsetX = -r }
            if let t = s.Top.Resolve(cbHeight ?? 0) { box.OffsetY = t }
            else if let b = s.Bottom.Resolve(cbHeight ?? 0) { box.OffsetY = -b }
        } else if s.Position == .sticky {
            Sticky.append(box)
        }
    }

    /// Moves sticky boxes to follow a scroll: a box with `top` stays
    /// that far below the viewport's top while its container is in
    /// view, and likewise for `bottom`. Answers whether any moved.
    public func UpdateSticky(scrollY: float32, viewportHeight: float32) -> bool {
        var moved = false
        for box in Sticky {
            guard let parent = box.Parent else { continue }
            let pos = PagePosition(box)
            let base = pos.y - box.OffsetY
            let parentPos = PagePosition(parent)
            let parentTop = parentPos.y + parent.ContentY
            let parentBottom = parentPos.y + parent.Height - parent.Padding.Bottom - parent.Border.Bottom
            var offset: float32 = 0
            if let top = box.Style.Top.Resolve(viewportHeight) {
                let wanted = scrollY + top
                if wanted > base {
                    offset = wanted - base
                    let limit = parentBottom - (base + box.Height + box.Margin.Bottom)
                    if offset > limit { offset = limit > 0 ? limit : 0 }
                }
            } else if let bottom = box.Style.Bottom.Resolve(viewportHeight) {
                let wanted = scrollY + viewportHeight - bottom - box.Height
                if wanted < base {
                    offset = wanted - base
                    let limit = parentTop - base
                    if offset < limit { offset = limit < 0 ? limit : 0 }
                }
            }
            if offset != box.OffsetY {
                box.OffsetY = offset
                moved = true
            }
        }
        return moved
    }
}

/// Whether building or laying out boxes reads an attribute itself, as
/// an image's source or a cell's span: a change to it rebuilds the
/// element's boxes. `web/cmd/check-deps` keeps this in step with the
/// code.
public func ReadsAttribute(name: string) -> bool {
    switch name {
    case "src", "colspan", "rowspan", "start", "type", "value", "selected", "placeholder", "multiple", "poster", "data", "lang", "size", "popovertarget", "id":
        return true
    default:
        return false
    }
}

/// Whether a width or height is min-content, max-content or fit-content:
/// sized by the content even where both insets are given.
func isSizingKeyword(l: css.Length) -> bool {
    switch l {
    case .minContent, .maxContent, .fitContent: return true
    default: return false
    }
}

func flippedName(n: string, a: string, b: string) -> string {
    return n == a ? b : (n == b ? a : n)
}

/// An anchor use the other way along an axis.
func flippedUse(u: cascade.AnchorUse, a: string, b: string) -> cascade.AnchorUse {
    var out = u
    out.Property = flippedName(u.Property, a, b)
    out.Edge = flippedName(u.Edge, a, b)
    return out
}

func flippedWord(w: string, a: string, b: string) -> string {
    if w == "span-" + a { return "span-" + b }
    if w == "span-" + b { return "span-" + a }
    return flippedName(w, a, b)
}
