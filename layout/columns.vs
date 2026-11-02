package layout

import "image/draw"

// Multi-column layout: a block's content laid out at the column width,
// then cut between lines and between boxes and moved, piece by piece,
// into columns side by side. Columns balance to the shortest height
// that fits them, unless column-fill is auto under a given height.
// Pieces are whole boxes or a block's lines: a plain block is opened up
// so its lines and children can go to different columns -- one with a
// border, padding or background of its own too, drawn then as a
// fragment in each column (box-decoration-break) -- and anything that
// is a formatting root, or has break-inside: avoid, stays in one piece.
// break-before and break-after force a column; orphans and widows keep
// lines together at a break; column-span: all cuts the content into
// column sets, each balanced on its own, with the spanner across them.

/// A piece of a multi-column container's content, its top and bottom
/// in the container's coordinates.
struct ColumnPiece {
    var box: Box
    /// The line of box, or -1 for the box itself.
    var line: int
    var top: float32
    var bottom: float32
    /// A break before it is forced (break-before, or break-after on what
    /// came before).
    var forced: bool = false
    /// The opened blocks it is inside, outermost first, and where each
    /// one's border box sits in the container.
    var chain: [Box] = []
}

/// Where a split block is, in the container: its border box's corner.
struct OpenedBlock {
    var box: Box
    var left: float32
    var top: float32
}

extension Layout {
    /// The columns' count, width and gap in a content width, as
    /// Multi-column 1 §3.4 works them out.
    func columnGeometry(box: Box, available: float32) -> (count: int, width: float32, gap: float32) {
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
    func layoutColumns(box: Box, contentWidth: float32, flow: Flow) -> float32 {
        let g = columnGeometry(box, contentWidth)
        _ = box.HasInlineChildren
            ? layoutInline(box, contentWidth: g.width, flow: flow)
            : layoutBlockChildren(box, contentWidth: g.width, flow: flow)
        box.ColumnWidthUsed = g.width
        box.ColumnGapUsed = g.gap
        box.ColumnRules = []
        // The content cut into column sets at the spanners.
        var segments: [[ColumnPiece]] = [[]]
        var spanners: [Box] = []
        var opened: [OpenedBlock] = []
        var force = false
        if !box.Lines.isEmpty {
            collectColumnPieces(box, left: 0, top: 0, &segments[0], &opened, &force, chain: [])
        } else {
            for child in box.Children {
                if child.Style.Position == .absolute || child.Style.Position == .fixed { continue }
                if child.Style.ColumnSpanAll && child.Kind == .block && child.Style.Float == .none {
                    spanners.append(child)
                    segments.append([])
                    force = false
                    continue
                }
                collectChild(child, left: 0, top: 0, &segments[segments.count - 1], &opened, &force, chain: [])
            }
        }
        var y = box.ContentY
        var used = 0
        var moves: [int64: (dx: float32, dy: float32)] = [:]
        var s = 0
        while s < segments.count {
            let pieces = sortedByTop(segments[s])
            if !pieces.isEmpty {
                let start = s == 0 ? box.ContentY : pieces[0].top
                let fill = fillColumns(box, pieces, start: start, at: y, g, single: segments.count == 1)
                for (k, v) in fill.moves { moves[k] = v }
                if fill.columns > used { used = fill.columns }
                // A rule down the middle of each gap between columns
                // that hold content, as tall as this set.
                var i = 1
                while i < fill.columns {
                    let mid = box.ContentX + float32(i) * (g.width + g.gap) - g.gap / 2
                    box.ColumnRules.append(draw.Rect(mid, y, 0, fill.height))
                    i += 1
                }
                y += fill.height
                let right = box.ContentX + float32(fill.columns) * (g.width + g.gap) - g.gap
                if right - box.ContentX > box.ContentWidth { box.ContentWidth = right - box.ContentX }
            }
            if s < spanners.count {
                // A spanner across the columns, laid out at the full width.
                let sp = spanners[s]
                layoutBlock(sp, cb: ContainingBlock(width: contentWidth, height: nil), flow: flow.root(sp))
                sp.X = box.ContentX + sp.Margin.Left
                sp.Y = y + sp.Margin.Top
                y += sp.OuterHeight
            }
            s += 1
        }
        box.ColumnsUsed = used
        box.ColumnHeightUsed = y - box.ContentY
        splitFragments(opened, segments, moves)
        return y - box.ContentY
    }

    /// One column set: its pieces placed (balanced, or filling a given
    /// height), moved into their columns with this set's top at `at`.
    /// Answers how many columns it took, how tall it is, and each
    /// piece's move by its box and line.
    func fillColumns(box: Box, pieces: [ColumnPiece], start: float32, at: float32, g: (count: int, width: float32, gap: float32),
                     single: bool) -> (columns: int, height: float32, moves: [int64: (dx: float32, dy: float32)]) {
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
            if placeColumns(pieces, start, low).count <= g.count {
                high = low
            } else {
                var i = 0
                while i < 24 && high - low > 0.25 {
                    let mid = (low + high) / 2
                    if placeColumns(pieces, start, mid).count <= g.count { high = mid } else { low = mid }
                    i += 1
                }
            }
            limit = high
        }
        if single, let definite = box.DefiniteInnerHeight {
            limit = box.Style.ColumnBalance && limit < definite ? limit : definite
        }
        let placed = placeColumns(pieces, start, limit)
        var height: float32 = 0
        var moves: [int64: (dx: float32, dy: float32)] = [:]
        var i = 0
        while i < pieces.count {
            let p = pieces[i]
            let col = placed.columns[i]
            let dx = float32(col) * (g.width + g.gap)
            let dy = at - placed.starts[col]
            moveColumnPiece(p, dx, dy)
            moves[pieceKey(p)] = (dx: dx, dy: dy)
            if p.bottom + dy - at > height { height = p.bottom + dy - at }
            i += 1
        }
        return (columns: placed.count, height: height, moves: moves)
    }

    /// Which column each piece goes in at a column height, where each
    /// column starts, and how many there are: a new column where a piece
    /// would reach past the height or a break is forced, moved earlier
    /// to keep a block's orphans and widows.
    func placeColumns(pieces: [ColumnPiece], start: float32, limit: float32) -> (columns: [int], starts: [float32], count: int) {
        var cols = [int](repeating: 0, count: pieces.count)
        var starts: [float32] = [start]
        var col = 0
        var colStart = start
        var first = 0
        var i = 0
        while i < pieces.count {
            let p = pieces[i]
            let over = p.bottom - colStart > limit + 0.01 && p.top > colStart + 0.01
            if i > first && (p.forced || over) {
                var b = i
                if !p.forced && p.line >= 0 {
                    // A break inside a block's lines: no fewer than
                    // widows after it and orphans before it, else the
                    // break comes earlier.
                    let c = p.box
                    var j = i
                    while j - 1 >= first && pieces[j - 1].line >= 0 && pieces[j - 1].box === c { j -= 1 }
                    let firstLine = pieces[j].line
                    var at = p.line
                    let n = c.Lines.count
                    if n - at < int(c.Style.Widows) { at = n - int(c.Style.Widows) }
                    if at - firstLine < int(c.Style.Orphans) { at = firstLine }
                    if at < firstLine { at = firstLine }
                    b = i - (p.line - at)
                    if b <= first { b = i }
                }
                col += 1
                colStart = pieces[b].top
                starts.append(colStart)
                var k = b
                while k < i {
                    cols[k] = col
                    k += 1
                }
                first = b
            }
            cols[i] = col
            i += 1
        }
        return (columns: cols, starts: starts, count: col + 1)
    }

    /// Whether a break-before or break-after value forces a break.
    func forcesBreak(v: string) -> bool {
        switch v {
        case "column", "page", "left", "right", "recto", "verso", "all", "region": return true
        default: return false
        }
    }

    /// The pieces of a box's content in order, its border box's corner at
    /// left, top in the container's coordinates.
    func collectColumnPieces(box: Box, left: float32, top: float32, out: inout [ColumnPiece], opened: inout [OpenedBlock],
                             force: inout bool, chain: [Box]) {
        if !box.Lines.isEmpty {
            var i = 0
            while i < box.Lines.count {
                let line = box.Lines[i]
                var p = ColumnPiece(box: box, line: i, top: top + line.Y, bottom: top + line.Y + line.Height)
                p.forced = force
                p.chain = chain
                force = false
                out.append(p)
                i += 1
            }
            // Floats in the lines go with them.
            for child in box.Children where child.Style.Float != .none {
                var p = ColumnPiece(box: child, line: -1, top: top + child.Y, bottom: top + child.Y + child.Height)
                p.chain = chain
                out.append(p)
            }
            return
        }
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed { continue }
            collectChild(child, left: left, top: top, &out, &opened, &force, chain: chain)
        }
    }

    func collectChild(child: Box, left: float32, top: float32, out: inout [ColumnPiece], opened: inout [OpenedBlock],
                      force: inout bool, chain: [Box]) {
        if forcesBreak(child.Style.BreakBefore) { force = true }
        let childLeft = left + child.X
        let childTop = top + child.Y
        let before = out.count
        if opensForColumns(child) {
            child.ColumnFragments = []
            if child.HasDecoration { opened.append(OpenedBlock(box: child, left: childLeft, top: childTop)) }
            collectColumnPieces(child, left: childLeft, top: childTop, &out, &opened, &force, chain: chain + [child])
        }
        if out.count == before && (child.Height > 0 || child.Kind != .text) {
            var p = ColumnPiece(box: child, line: -1, top: childTop, bottom: childTop + child.Height)
            p.forced = force
            p.chain = chain
            force = false
            out.append(p)
        }
        if forcesBreak(child.Style.BreakAfter) { force = true }
    }

    /// Whether a box's lines and children may go to different columns:
    /// a block that lays out in the container's flow.
    func opensForColumns(box: Box) -> bool {
        let s = box.Style
        if box.Kind != .block || box.IsFormattingRoot || s.BreakInsideAvoid || s.Float != .none { return false }
        if s.HasTransform || s.IsPositioned || s.HasCompositing || s.Opacity < 1 { return false }
        return true
    }

    /// Pieces by their tops, in order where they tie: floats among the
    /// lines they sit beside.
    func sortedByTop(pieces: [ColumnPiece]) -> [ColumnPiece] {
        var out = pieces
        var i = 1
        while i < out.count {
            let p = out[i]
            var j = i - 1
            while j >= 0 && out[j].top > p.top + 0.01 {
                out[j + 1] = out[j]
                j -= 1
            }
            out[j + 1] = p
            i += 1
        }
        return out
    }

    func pieceKey(p: ColumnPiece) -> int64 {
        return int64(p.box.Id) * 100000 + int64(p.line + 1)
    }

    /// The fragments of each split decorated block: in every column its
    /// pieces went to, from its first piece's top (its own top in the
    /// first) to its last's bottom (its own bottom in the last).
    func splitFragments(opened: [OpenedBlock], segments: [[ColumnPiece]], moves: [int64: (dx: float32, dy: float32)]) {
        for d in opened {
            var frags: [(dx: float32, dy: float32, top: float32, bottom: float32)] = []
            for seg in segments {
                for p in seg where p.chain.contains(where: { $0 === d.box }) {
                    guard let m = moves[pieceKey(p)] else { continue }
                    if let last = frags.last, last.dx == m.dx && last.dy == m.dy {
                        frags[frags.count - 1].bottom = p.bottom
                    } else {
                        frags.append((dx: m.dx, dy: m.dy, top: p.top, bottom: p.bottom))
                    }
                }
            }
            if frags.count < 2 { continue }
            // The block's own top and bottom edges, with their padding
            // and border, go with its first and last fragments.
            frags[0].top = d.top
            frags[frags.count - 1].bottom = d.top + d.box.Height
            var rects: [draw.Rect] = []
            for f in frags {
                rects.append(draw.Rect(f.dx, f.top + f.dy - d.top, d.box.Width, f.bottom - f.top))
            }
            d.box.ColumnFragments = rects
        }
    }

    func moveColumnPiece(p: ColumnPiece, dx: float32, dy: float32) {
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
