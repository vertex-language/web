package layout

import "web/css"

/// A grid item once placed: its cell range.
struct GridItem {
    var box: Box
    var column: int
    var columnSpan: int
    var row: int
    var rowSpan: int
}

extension Layout {
    /// Lays out a grid container: explicit column tracks, rows given or
    /// made as items need them, items placed where they ask or in the
    /// next free cell row by row, then sized to their cells. Answers the
    /// content height.
    /// Masonry: the column tracks as a grid sizes them; each item in turn in
    /// the shortest, straight under what's there. One that spans tracks goes
    /// where the tallest of them is shortest, or at the line it names.
    func layoutMasonry(box: Box, contentWidth: float32, flow: Flow) -> float32 {
        let s = box.Style
        let gap = s.ColumnGap.Or(0, base: contentWidth)
        let rowGap = s.RowGap.Or(0, base: contentWidth)
        let tracks = expandAutoFill(s.GridColumns, available: contentWidth, gap: gap)
        var sizes: [float32] = []
        var shares: [float32] = []
        var left = contentWidth - gap * float32(tracks.count > 0 ? tracks.count - 1 : 0)
        for t in tracks {
            switch t {
            case .length(let l):
                let w = l.Or(0, base: contentWidth)
                sizes.append(w)
                shares.append(0)
                left -= w
            case .fr(let f):
                sizes.append(0)
                shares.append(f)
            case .minmax(let low, _, let f):
                sizes.append(low)
                shares.append(f > 0 ? f : 1)
                left -= low
            default:
                sizes.append(0)
                shares.append(1)
            }
        }
        var total: float32 = 0
        for f in shares { total += f }
        if total > 0 && left > 0 {
            var i = 0
            while i < sizes.count {
                sizes[i] += left * shares[i] / total
                i += 1
            }
        }
        if sizes.isEmpty { sizes = [contentWidth] }
        var heights = [float32](repeating: 0, count: sizes.count)
        var xs: [float32] = []
        var x = box.ContentX
        for w in sizes {
            xs.append(x)
            x += w + gap
        }
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed {
                child.X = box.ContentX
                child.Y = box.ContentY
                attachPositioned(child, flow)
                continue
            }
            resolveEdges(child, cbWidth: contentWidth)
            let count = heights.count
            let place = child.Style.GridColumn
            var start = place.Start > 0 ? int(place.Start) - 1 : -1
            var span = int(place.Span > 0 ? place.Span : 1)
            if place.Start > 0 && place.End != 0 {
                let end = place.End > 0 ? int(place.End) - 1 : count + 1 + int(place.End)
                if end > start { span = end - start }
            }
            if span > count { span = count }
            if start + span > count { start = count - span }
            // How tall the run of tracks from c is: its tallest.
            func top(c: int) -> float32 {
                var most: float32 = 0
                var k = c
                while k < c + span {
                    if heights[k] > most { most = heights[k] }
                    k += 1
                }
                return most
            }
            var at = start
            if at < 0 {
                at = 0
                var c = 1
                while c + span <= count {
                    if top(c) < top(at) - 0.01 { at = c }
                    c += 1
                }
            }
            let y = top(at)
            var cell = sizes[at]
            var k = at + 1
            while k < at + span {
                cell += gap + sizes[k]
                k += 1
            }
            layoutFixed(child, width: cell - child.Margin.Horizontal, height: nil, cb: ContainingBlock(width: cell, height: nil), flow: flow.root(child))
            child.X = xs[at] + child.Margin.Left
            child.Y = box.ContentY + y + child.Margin.Top
            k = at
            while k < at + span {
                heights[k] = y + child.OuterHeight + rowGap
                k += 1
            }
        }
        var most: float32 = 0
        for h in heights where h - rowGap > most { most = h - rowGap }
        return most
    }

    func layoutGrid(box: Box, contentWidth: float32, flow: Flow) -> float32 {
        let s = box.Style
        if s.Masonry { return layoutMasonry(box, contentWidth: contentWidth, flow: flow) }
        var columnGap = s.ColumnGap.Or(0, base: contentWidth)
        var rowGap = s.RowGap.Or(0, base: contentWidth)
        // A subgrid's lines are its parent's, and so its gaps.
        if s.SubgridColumns, box.ParentColumnTracks != nil { columnGap = box.ParentColumnGap }
        if s.SubgridRows, box.ParentRowTracks != nil { rowGap = box.ParentRowGap }
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(box))

        // The items, in order.
        var boxes: [Box] = []
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed {
                child.X = box.ContentX
                child.Y = box.ContentY
                attachPositioned(child, flow)
                continue
            }
            resolveEdges(child, cbWidth: contentWidth)
            boxes.append(child)
        }

        // Column tracks: the template's, with auto-fill repeats counted
        // to fit, or one auto column for a grid without a template.
        var columns = expandAutoFill(s.GridColumns, available: contentWidth, gap: columnGap)
        if s.SubgridColumns, let t = box.ParentColumnTracks { columns = t.map { css.GridTrack.length(.px($0)) } }
        // Each item's lines, end lines made spans against the explicit
        // tracks (-1 being the last line).
        var columnOf: [int: css.GridPlacement] = [:]
        var rowOf: [int: css.GridPlacement] = [:]
        // A template of areas with fewer column tracks than columns
        // has auto tracks for the rest.
        while int32(columns.count) < s.GridAreaColumns { columns.append(s.GridAutoColumns) }
        let explicitRows = int32(s.GridRows.count) > s.GridAreaRows ? int32(s.GridRows.count) : s.GridAreaRows
        for b in boxes {
            var col = b.Style.GridColumn
            var row = b.Style.GridRow
            // A name places the item in that template area.
            if !col.Area.isEmpty, let a = s.GridAreas[col.Area] {
                col = css.GridPlacement(start: a.ColumnStart, span: a.ColumnEnd - a.ColumnStart)
            } else if !col.Area.isEmpty {
                col = css.GridPlacement.auto
            }
            if !row.Area.isEmpty, let a = s.GridAreas[row.Area] {
                row = css.GridPlacement(start: a.RowStart, span: a.RowEnd - a.RowStart)
            } else if !row.Area.isEmpty {
                row = css.GridPlacement.auto
            }
            columnOf[b.Id] = col.Resolved(explicitTracks: int32(columns.count))
            rowOf[b.Id] = row.Resolved(explicitTracks: explicitRows)
        }
        if columns.isEmpty { columns = [s.GridAutoColumns] }
        var maxColumnNeeded = 1
        for b in boxes {
            let p = columnOf[b.Id] ?? b.Style.GridColumn
            let end = (p.Start > 0 ? int(p.Start) : 1) + int(p.Span) - 1
            if end > maxColumnNeeded { maxColumnNeeded = end }
        }
        // Flowing by column, the items fill the rows there are, one
        // column after another, as many columns as that takes.
        let columnFlow = s.GridAutoFlowColumn
        let flowRows = s.GridRows.count > 0 ? s.GridRows.count : 1
        if columnFlow {
            var row = 0
            var column = 0
            for b in boxes where !((columnOf[b.Id] ?? b.Style.GridColumn).Start > 0 && (rowOf[b.Id] ?? b.Style.GridRow).Start > 0) {
                let bc = columnOf[b.Id] ?? b.Style.GridColumn
                let cs = bc.Span > 0 ? int(bc.Span) : 1
                if row >= flowRows {
                    row = 0
                    column += 1
                }
                if column + cs > maxColumnNeeded { maxColumnNeeded = column + cs }
                row += 1
                if cs > 1 {
                    // A wide item leaves the rest of its columns' rows.
                    column += cs - 1
                }
            }
        }
        // Implicit columns past the template take grid-auto-columns.
        while columns.count < maxColumnNeeded { columns.append(s.GridAutoColumns) }
        let columnCount = columns.count

        // Placement: explicit positions first, then the rest row by row.
        var items: [GridItem] = []
        var occupied: [[Bool]] = []
        func occupy(r: int, c: int) {
            while occupied.count <= r { occupied.append([Bool](repeating: false, count: columnCount)) }
            if c < columnCount { occupied[r][c] = true }
        }
        func isFree(r: int, c: int, rs: int, cs: int) -> Bool {
            var rr = r
            while rr < r + rs {
                var cc = c
                while cc < c + cs {
                    if cc >= columnCount { return false }
                    if rr < occupied.count && occupied[rr][cc] { return false }
                    cc += 1
                }
                rr += 1
            }
            return true
        }
        var pending: [Box] = []
        for b in boxes {
            let pc = columnOf[b.Id] ?? b.Style.GridColumn
            let pr = rowOf[b.Id] ?? b.Style.GridRow
            let cs = pc.Span > 0 ? int(pc.Span) : 1
            let rs = pr.Span > 0 ? int(pr.Span) : 1
            if pc.Start > 0 && pr.Start > 0 {
                let item = GridItem(box: b, column: int(pc.Start) - 1, columnSpan: cs, row: int(pr.Start) - 1, rowSpan: rs)
                items.append(item)
                var rr = item.row
                while rr < item.row + rs { var cc = item.column; while cc < item.column + cs { occupy(rr, cc); cc += 1 }; rr += 1 }
            } else {
                pending.append(b)
            }
        }
        var cursorRow = 0
        var cursorColumn = 0
        for b in pending {
            let pc = columnOf[b.Id] ?? b.Style.GridColumn
            let pr = rowOf[b.Id] ?? b.Style.GridRow
            var cs = pc.Span > 0 ? int(pc.Span) : 1
            let rs = pr.Span > 0 ? int(pr.Span) : 1
            if cs > columnCount { cs = columnCount }
            var placed = false
            if pc.Start > 0 {
                // A fixed column: the first row where it is free.
                let c = int(pc.Start) - 1
                var r = 0
                while r < 10000 {
                    if isFree(r, c, rs, cs) {
                        items.append(GridItem(box: b, column: c, columnSpan: cs, row: r, rowSpan: rs))
                        var rr = r
                        while rr < r + rs { var cc = c; while cc < c + cs { occupy(rr, cc); cc += 1 }; rr += 1 }
                        placed = true
                        break
                    }
                    r += 1
                }
            }
            if placed { continue }
            if columnFlow {
                // Down the rows, then on to the next column.
                var rounds = 0
                while rounds < 100000 && cursorColumn < columnCount {
                    rounds += 1
                    if cursorRow + rs > flowRows && cursorRow > 0 {
                        cursorColumn += 1
                        cursorRow = 0
                        continue
                    }
                    if isFree(cursorRow, cursorColumn, rs, cs) {
                        items.append(GridItem(box: b, column: cursorColumn, columnSpan: cs, row: cursorRow, rowSpan: rs))
                        var rr = cursorRow
                        while rr < cursorRow + rs { var cc = cursorColumn; while cc < cursorColumn + cs { occupy(rr, cc); cc += 1 }; rr += 1 }
                        cursorRow += rs
                        break
                    }
                    cursorRow += 1
                }
                continue
            }
            var guardRounds = 0
            while guardRounds < 100000 {
                guardRounds += 1
                if cursorColumn + cs > columnCount {
                    cursorRow += 1
                    cursorColumn = 0
                }
                if isFree(cursorRow, cursorColumn, rs, cs) {
                    items.append(GridItem(box: b, column: cursorColumn, columnSpan: cs, row: cursorRow, rowSpan: rs))
                    var rr = cursorRow
                    while rr < cursorRow + rs { var cc = cursorColumn; while cc < cursorColumn + cs { occupy(rr, cc); cc += 1 }; rr += 1 }
                    cursorColumn += cs
                    break
                }
                cursorColumn += 1
            }
        }
        var rowCount = occupied.count
        for it in items where it.row + it.rowSpan > rowCount { rowCount = it.row + it.rowSpan }
        if rowCount == 0 { return 0 }

        // Column widths: fixed tracks first, auto tracks from what their
        // items need, then fr tracks share the rest.
        let gaps = columnGap * float32(columnCount > 1 ? columnCount - 1 : 0)
        var widths = [float32](repeating: 0, count: columnCount)
        var frs = [float32](repeating: 0, count: columnCount)
        // How far each auto track may grow: its max-content width.
        var limits = [float32](repeating: 0, count: columnCount)
        var totalFr: float32 = 0
        var fixed: float32 = 0
        let lent = subgridContributions(items)
        var c = 0
        while c < columnCount {
            switch columns[c] {
            case .length(let l):
                widths[c] = l.Or(0, base: contentWidth)
                fixed += widths[c]
            case .fr(let f):
                frs[c] = f > 0 ? f : 1
                totalFr += frs[c]
            case .auto:
                // From its items' min-content widths, and as far as their
                // max-content widths where there is room (below).
                var least: float32 = 0
                var most: float32 = 0
                for it in items where it.column == c && it.columnSpan == 1 {
                    let w = intrinsicWidths(it.box)
                    if w.min + it.box.Margin.Horizontal > least { least = w.min + it.box.Margin.Horizontal }
                    if w.max + it.box.Margin.Horizontal > most { most = w.max + it.box.Margin.Horizontal }
                }
                for l in lent where l.column == c {
                    if l.min > least { least = l.min }
                    if l.max > most { most = l.max }
                }
                widths[c] = least
                limits[c] = most > least ? most : least
                fixed += least
            case .minmax(let minPx, let maxPx, let maxFr):
                if maxFr > 0 {
                    frs[c] = maxFr
                    totalFr += maxFr
                    widths[c] = minPx
                } else {
                    var need = minPx
                    for it in items where it.column == c && it.columnSpan == 1 {
                        let w = intrinsicWidths(it.box)
                        if w.max + it.box.Margin.Horizontal > need { need = w.max + it.box.Margin.Horizontal }
                    }
                    for l in lent where l.column == c && l.max > need { need = l.max }
                    if maxPx > 0 && need > maxPx { need = maxPx }
                    widths[c] = need
                    fixed += need
                }
            }
            c += 1
        }
        var free = contentWidth - gaps - fixed
        // Auto tracks grow toward their max-content widths into the room
        // there is, equally, each stopping at its limit (grid's "maximize
        // tracks"); what's left is the fr tracks'.
        var rounds = 0
        while free > 0.01 && rounds < 16 {
            rounds += 1
            var growing = 0
            c = 0
            while c < columnCount {
                if case .auto = columns[c], widths[c] < limits[c] - 0.01 { growing += 1 }
                c += 1
            }
            if growing == 0 { break }
            let each = free / float32(growing)
            c = 0
            while c < columnCount {
                if case .auto = columns[c], widths[c] < limits[c] - 0.01 {
                    let add = each < limits[c] - widths[c] ? each : limits[c] - widths[c]
                    widths[c] += add
                    free -= add
                }
                c += 1
            }
        }
        if totalFr > 0 {
            // Each fr track gets its share, no less than its minimum.
            var share = free > 0 ? free / totalFr : 0
            var rounds = 0
            while rounds < 8 {
                rounds += 1
                var overMin: float32 = 0
                var frLeft: float32 = 0
                c = 0
                while c < columnCount {
                    if frs[c] > 0 {
                        let got = share * frs[c]
                        if got < widths[c] { overMin += widths[c] } else { frLeft += frs[c] }
                    }
                    c += 1
                }
                let newShare = frLeft > 0 ? (free - overMin) / frLeft : share
                if newShare == share || frLeft == 0 { break }
                share = newShare
            }
            c = 0
            while c < columnCount {
                if frs[c] > 0 {
                    let got = share * frs[c]
                    if got > widths[c] { widths[c] = got }
                }
                c += 1
            }
        } else if free > 0 && s.JustifyContent == .flexStart {
            // Auto tracks with room still left stretch into it, equally.
            var autoCount = 0
            c = 0
            while c < columnCount {
                if case .auto = columns[c] { autoCount += 1 }
                c += 1
            }
            if autoCount > 0 {
                c = 0
                while c < columnCount {
                    if case .auto = columns[c] { widths[c] += free / float32(autoCount) }
                    c += 1
                }
            }
        }
        _ = free
        var columnX = [float32](repeating: 0, count: columnCount + 1)
        var columnEnd = [float32](repeating: 0, count: columnCount)
        c = 0
        var x: float32 = 0
        while c < columnCount {
            columnX[c] = x
            columnEnd[c] = x + widths[c]
            x += widths[c] + columnGap
            c += 1
        }
        columnX[columnCount] = x - columnGap
        // justify-content: tracks narrower than the grid move over, or
        // spread out, as a group.
        let freeX = contentWidth - columnX[columnCount]
        if freeX > 0.5 && columnCount > 0 {
            var shift: float32 = 0
            var between: float32 = 0
            switch s.JustifyContent {
            case .center: shift = freeX / 2
            case .flexEnd: shift = freeX
            case .spaceBetween: between = columnCount > 1 ? freeX / float32(columnCount - 1) : 0
            case .spaceAround:
                between = freeX / float32(columnCount)
                shift = between / 2
            case .spaceEvenly:
                between = freeX / float32(columnCount + 1)
                shift = between
            default: break
            }
            if shift != 0 || between != 0 {
                c = 0
                while c <= columnCount {
                    let move = shift + between * float32(c)
                    columnX[c] += move
                    if c < columnCount { columnEnd[c] += move }
                    c += 1
                }
            }
        }

        // Row heights: given tracks, else the tallest item in the row
        // once laid out at its column width.
        var heights = [float32](repeating: 0, count: rowCount)
        var needs: [(row: int, height: float32)] = []
        var r = 0
        while r < rowCount {
            let track: css.GridTrack = r < s.GridRows.count ? s.GridRows[r] : s.GridAutoRows
            if case .length(let l) = track, let h = l.Resolve(cb.Height ?? 0) { heights[r] = h }
            if case .minmax(let minPx, _, _) = track { heights[r] = minPx }
            r += 1
        }
        for it in items {
            let w = columnEnd[it.column + it.columnSpan - 1] - columnX[it.column] - it.box.Margin.Horizontal
            let child = it.box
            var itemWidth = w
            if let given = widthFromStyle(child, child.Style.Width, cbWidth: w) {
                itemWidth = clampWidth(child, given, cbWidth: w)
            } else if justifyFor(child, container: s) != "stretch" {
                // Not stretched across its area: as wide as its content,
                // within the area.
                let widths = intrinsicWidths(child)
                itemWidth = clampWidth(child, widths.max < w ? widths.max : w, cbWidth: w)
            }
            if child.Style.SubgridColumns {
                var tracks: [float32] = []
                var c = it.column
                while c < it.column + it.columnSpan {
                    tracks.append(columnEnd[c] - columnX[c])
                    c += 1
                }
                child.ParentColumnTracks = tracks
                child.ParentColumnGap = columnGap
            }
            layoutFixed(child, width: itemWidth, height: nil, cb: ContainingBlock(width: w, height: nil), flow: flow.root(child))
            if it.rowSpan == 1 {
                let track: css.GridTrack = it.row < s.GridRows.count ? s.GridRows[it.row] : s.GridAutoRows
                var fixedRow = false
                if case .length = track { fixedRow = true }
                // A 0fr row takes only its items' minimums: nothing of an
                // item that clips its overflow (an accordion, closed).
                if case .fr(let f) = track, f == 0 {
                    fixedRow = true
                    if !child.Style.ClipsOverflow && child.OuterHeight > heights[it.row] { heights[it.row] = child.OuterHeight }
                }
                if !fixedRow && child.OuterHeight > heights[it.row] { heights[it.row] = child.OuterHeight }
                needs.append((row: it.row, height: child.OuterHeight))
            }
            // A subgrid on rows: its items ask of the rows they're in, its own
            // edges on its first and last.
            if child.Style.SubgridRows {
                for n in child.GridRowNeeds where n.row < it.rowSpan {
                    let row = it.row + n.row
                    let track: css.GridTrack = row < s.GridRows.count ? s.GridRows[row] : s.GridAutoRows
                    if case .length = track { continue }
                    var h = n.height
                    if n.row == 0 { h += child.Margin.Top + child.Border.Top + child.Padding.Top }
                    if n.row == it.rowSpan - 1 { h += child.Margin.Bottom + child.Border.Bottom + child.Padding.Bottom }
                    if h > heights[row] { heights[row] = h }
                }
            }
        }
        box.GridRowNeeds = needs
        var rowY = [float32](repeating: 0, count: rowCount + 1)
        var rowEnd = [float32](repeating: 0, count: rowCount)
        var y: float32 = 0
        r = 0
        while r < rowCount {
            rowY[r] = y
            rowEnd[r] = y + heights[r]
            y += heights[r] + rowGap
            r += 1
        }
        rowY[rowCount] = y - rowGap

        // Place and stretch.
        for it in items {
            let child = it.box
            let cellX = columnX[it.column]
            let cellY = rowY[it.row]
            let cellW = columnEnd[it.column + it.columnSpan - 1] - cellX
            let cellH = rowEnd[it.row + it.rowSpan - 1] - cellY
            let align = alignFor(child, container: s)
            // A subgrid's rows are known only now: it is set again on them.
            if child.Style.SubgridRows {
                var tracks: [float32] = []
                var r = it.row
                while r < it.row + it.rowSpan {
                    tracks.append(rowEnd[r] - rowY[r])
                    r += 1
                }
                child.ParentRowTracks = tracks
                child.ParentRowGap = rowGap
                layoutFixed(child, width: child.Width, height: cellH - child.Margin.Vertical, cb: ContainingBlock(width: cellW, height: cellH), flow: flow.root(child))
            }
            // Stretching fills the cell; an item that clips its overflow may
            // also shrink to it, its automatic minimum being zero.
            if align == .stretch && child.Style.Height.IsAuto && (child.OuterHeight < cellH || (child.Style.ClipsOverflow && child.OuterHeight > cellH)) {
                layoutFixed(child, width: child.Width, height: cellH - child.Margin.Vertical, cb: ContainingBlock(width: cellW, height: cellH), flow: flow.root(child))
            }
            // A percentage height is of the grid area, known only now.
            if case .percent = child.Style.Height, let given = heightFromStyle(child, child.Style.Height, cbHeight: cellH) {
                let h = clampHeight(child, given, cbHeight: cellH)
                if h != child.Height {
                    layoutFixed(child, width: child.Width, height: h, cb: ContainingBlock(width: cellW, height: cellH), flow: flow.root(child))
                }
            }
            var dy: float32 = 0
            if align == .center { dy = (cellH - child.OuterHeight) / 2 } else if align == .flexEnd { dy = cellH - child.OuterHeight }
            var dx: float32 = 0
            if child.Width + child.Margin.Horizontal < cellW {
                switch justifyFor(child, container: s) {
                case "center": dx = (cellW - child.OuterWidth) / 2
                case "end", "right", "flex-end", "self-end": dx = cellW - child.OuterWidth
                default: dx = 0
                }
            }
            child.X = box.ContentX + cellX + child.Margin.Left + dx
            child.Y = box.ContentY + cellY + child.Margin.Top + dy
        }
        box.ContentWidth = columnX[columnCount]
        return rowY[rowCount]
    }

    /// What a subgrid's items ask of the parent's columns they're in: each
    /// one-column item's min- and max-content widths, in the parent's
    /// column, with the subgrid's own padding and border on its edge columns.
    /// Its items are placed as it would: at their lines, or in turn.
    func subgridContributions(items: [GridItem]) -> [(column: int, min: float32, max: float32)] {
        var out: [(column: int, min: float32, max: float32)] = []
        for it in items where it.box.Style.SubgridColumns {
            let sub = it.box
            let n = it.columnSpan
            resolveEdges(sub, cbWidth: 0)
            var next = 0
            for k in sub.Children {
                if k.Kind == .text || k.Style.Position == .absolute || k.Style.Position == .fixed { continue }
                let p = k.Style.GridColumn
                let span = p.Span > 0 ? int(p.Span) : 1
                var col = p.Start > 0 ? int(p.Start) - 1 : next
                if p.Start <= 0 && col + span > n { col = 0 }
                next = col + span
                if span != 1 || col >= n { continue }
                resolveEdges(k, cbWidth: 0)
                let w = intrinsicWidths(k)
                var extra = k.Margin.Horizontal
                if col == 0 { extra += sub.Margin.Left + sub.Border.Left + sub.Padding.Left }
                if col == n - 1 { extra += sub.Margin.Right + sub.Border.Right + sub.Padding.Right }
                out.append((column: it.column + col, min: w.min + extra, max: w.max + extra))
            }
        }
        return out
    }

    /// Tracks with a repeat(auto-fill) expanded to as many as fit.
    func expandAutoFill(tracks: [css.GridTrack], available: float32, gap: float32) -> [css.GridTrack] {
        var marker = -1
        var i = 0
        while i < tracks.count {
            if case .fr(let f) = tracks[i], f < 0 { marker = i }
            i += 1
        }
        if marker < 0 { return tracks }
        // The tracks before the marker repeat; their widths are their
        // minimums.
        var unit: float32 = 0
        var pattern: [css.GridTrack] = []
        i = 0
        while i < marker {
            pattern.append(tracks[i])
            switch tracks[i] {
            case .length(let l): unit += l.Or(0, base: available)
            case .minmax(let minPx, _, _): unit += minPx
            default: unit += 0
            }
            i += 1
        }
        if unit <= 0 || pattern.isEmpty { return pattern }
        var count = int((available + gap) / (unit + gap * float32(pattern.count)))
        if count < 1 { count = 1 }
        var out: [css.GridTrack] = []
        var k = 0
        while k < count {
            for t in pattern { out.append(t) }
            k += 1
        }
        i = marker + 1
        while i < tracks.count { out.append(tracks[i]); i += 1 }
        return out
    }
}

extension Layout {
    /// How a grid item sits across its area: its justify-self, else the
    /// container's justify-items; normal is stretch, except for a
    /// replaced element with a size of its own, which starts.
    func justifyFor(child: Box, container: cascade.ComputedStyle) -> string {
        var j = child.Style.JustifySelf
        if j == "auto" { j = container.JustifyItems }
        if j == "normal" || j == "legacy" { return child.Kind == .replaced ? "start" : "stretch" }
        if j == "left" || j == "flex-start" || j == "self-start" || j == "baseline" { return "start" }
        return j
    }
}
