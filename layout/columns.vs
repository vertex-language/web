package layout

// Multi-column layout: a block's content laid out at the column width,
// then cut between lines and between boxes and moved, piece by piece,
// into columns side by side. Columns balance to the shortest height
// that fits them, unless column-fill is auto under a given height.
// Pieces are whole boxes or a block's lines: a block with no border,
// padding or background of its own is opened up so its lines and
// children can go to different columns, and anything else, or
// anything with break-inside: avoid, stays in one piece.

/// A piece of a multi-column container's content, its top and bottom
/// in the container's coordinates.
struct ColumnPiece {
    var box: Box
    /// The line of box, or -1 for the box itself.
    var line: int
    var top: float32
    var bottom: float32
}

extension Layout {
    /// The columns' count, width and gap in a content width, as
    /// Multi-column 1 §3.4 works them out.
    func columnGeometry(_ box: Box, _ available: float32) -> (count: int, width: float32, gap: float32) {
        let s = box.Style
        let gap = s.ColumnGapNormal ? s.FontSize : s.ColumnGap.Or(0, base: available)
        var n = 1
        if let w = s.ColumnWidth {
            n = int((available + gap) / (w + gap))
            if n < 1 { n = 1 }
            if s.ColumnCount > 0 && int(s.ColumnCount) < n { n = int(s.ColumnCount) }
        } else {
            n = int(s.ColumnCount)
        }
        var width = (available + gap) / float32(n) - gap
        if width < 0 { width = 0 }
        return (count: n, width: width, gap: gap)
    }

    /// Lays out a multi-column block's content and answers its height.
    func layoutColumns(_ box: Box, contentWidth: float32, flow: Flow) -> float32 {
        let g = columnGeometry(box, contentWidth)
        _ = box.HasInlineChildren
            ? layoutInline(box, contentWidth: g.width, flow: flow)
            : layoutBlockChildren(box, contentWidth: g.width, flow: flow)
        box.ColumnWidthUsed = g.width
        box.ColumnGapUsed = g.gap
        var pieces: [ColumnPiece] = []
        collectColumnPieces(box, top: 0, &pieces, isRoot: true)
        let start = box.ContentY
        if pieces.isEmpty {
            box.ColumnsUsed = 0
            box.ColumnHeightUsed = 0
            return 0
        }
        var total: float32 = 0
        var tallest: float32 = 0
        for p in pieces {
            if p.bottom - start > total { total = p.bottom - start }
            if p.bottom - p.top > tallest { tallest = p.bottom - p.top }
        }
        // The height the columns may take: the shortest that fits the
        // content in the columns there are, or the box's own.
        var limit = total
        if g.count > 1 {
            let even = total / float32(g.count)
            var low = even > tallest ? even : tallest
            var high = total
            if columnsNeeded(pieces, start, low) <= g.count {
                high = low
            } else {
                var i = 0
                while i < 24 && high - low > 0.25 {
                    let mid = (low + high) / 2
                    if columnsNeeded(pieces, start, mid) <= g.count { high = mid } else { low = mid }
                    i += 1
                }
            }
            limit = high
        }
        if let definite = box.DefiniteInnerHeight {
            limit = box.Style.ColumnBalance && limit < definite ? limit : definite
        }
        // Each piece to its column: across by whole columns, up by
        // where its column starts.
        var col = 0
        var colStart = start
        var used: float32 = 0
        var started = false
        for p in pieces {
            if started && p.bottom - colStart > limit + 0.01 && p.top > colStart + 0.01 {
                col += 1
                colStart = p.top
            }
            started = true
            let dx = float32(col) * (g.width + g.gap)
            let dy = start - colStart
            moveColumnPiece(p, dx, dy)
            if p.bottom + dy - start > used { used = p.bottom + dy - start }
        }
        box.ColumnsUsed = col + 1
        box.ColumnHeightUsed = used
        let right = box.ContentX + float32(col + 1) * (g.width + g.gap) - g.gap
        if right - box.ContentX > box.ContentWidth { box.ContentWidth = right - box.ContentX }
        return used
    }

    /// How many columns the pieces take at a column height.
    func columnsNeeded(_ pieces: [ColumnPiece], _ start: float32, _ limit: float32) -> int {
        var n = 1
        var colStart = start
        var started = false
        for p in pieces {
            if started && p.bottom - colStart > limit + 0.01 && p.top > colStart + 0.01 {
                n += 1
                colStart = p.top
            }
            started = true
        }
        return n
    }

    /// The pieces of a box's content in order, top being the box's top
    /// in the container's coordinates.
    func collectColumnPieces(_ box: Box, top: float32, _ out: inout [ColumnPiece], isRoot: bool) {
        if !box.Lines.isEmpty {
            var i = 0
            while i < box.Lines.count {
                let line = box.Lines[i]
                out.append(ColumnPiece(box: box, line: i, top: top + line.Y, bottom: top + line.Y + line.Height))
                i += 1
            }
            return
        }
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed { continue }
            let childTop = top + child.Y
            if opensForColumns(child) {
                let before = out.count
                collectColumnPieces(child, top: childTop, &out, isRoot: false)
                if out.count > before { continue }
            }
            if child.Height > 0 || child.Kind != .text {
                out.append(ColumnPiece(box: child, line: -1, top: childTop, bottom: childTop + child.Height))
            }
        }
    }

    /// Whether a box's lines and children may go to different columns:
    /// a plain block, with nothing of its own a cut would show.
    func opensForColumns(_ box: Box) -> bool {
        let s = box.Style
        if box.Kind != .block || box.IsFormattingRoot || s.BreakInsideAvoid || s.Float != .none { return false }
        if s.HasTransform || s.IsPositioned || s.HasCompositing || s.Opacity < 1 { return false }
        if box.Border.Vertical > 0 || box.Border.Horizontal > 0 || box.Padding.Vertical > 0 { return false }
        if s.BackgroundColor.A > 0 || s.BackgroundImage != nil || !s.Shadows.isEmpty { return false }
        return true
    }

    func moveColumnPiece(_ p: ColumnPiece, _ dx: float32, _ dy: float32) {
        if dx == 0 && dy == 0 { return }
        if p.line < 0 {
            p.box.X += dx
            p.box.Y += dy
            return
        }
        let b = p.box
        b.Lines[p.line].X += dx
        b.Lines[p.line].Y += dy
        var k = 0
        while k < b.Lines[p.line].Fragments.count {
            b.Lines[p.line].Fragments[k].X += dx
            b.Lines[p.line].Fragments[k].Y += dy
            if b.Lines[p.line].Fragments[k].Kind == .atomic {
                b.Lines[p.line].Fragments[k].Box.X += dx
                b.Lines[p.line].Fragments[k].Box.Y += dy
            }
            k += 1
        }
        k = 0
        while k < b.Lines[p.line].Spans.count {
            b.Lines[p.line].Spans[k].X += dx
            b.Lines[p.line].Spans[k].Y += dy
            k += 1
        }
    }
}
