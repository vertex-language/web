package layout

import (
    "image/draw"
    "text/bidi"
    "text/font"
    "text/hyphen"
    "web/cascade"
)

enum ItemKind: Equatable {
    case word
    case space
    case open
    case close
    case atomic
    case lineBreak
    case newline
    case float
    /// An absolutely positioned box in the text: it takes no room, and
    /// where the line has got to is its static position.
    case positioned
}

/// One thing inline layout places: a word, a space, the start or end of
/// an inline element, an atomic box, or a break.
struct Item {
    var kind: ItemKind
    var box: Box
    var owner: Box
    var text: string
    var run: font.Run
    var width: float32
    var offset: int
    var length: int
    var breakable: bool
    var decoration: cascade.TextDecoration
    var decorationColor: draw.Color
    /// The bidi embedding level: odd is right to left.
    var level: uint8 = 0
    /// A piece of a word after a soft hyphen: the line may break before
    /// it, and the piece before then shows a hyphen.
    var softBreakBefore: bool = false
    /// hyphens: auto may break after this piece: it then shows a hyphen.
    var autoHyphen: bool = false

    init(kind: ItemKind, box: Box, owner: Box) {
        self.kind = kind
        self.box = box
        self.owner = owner
        text = ""
        run = font.Run()
        width = 0
        offset = 0
        length = 0
        breakable = true
        decoration = cascade.TextDecoration()
        decorationColor = draw.Color.black
    }
}

/// An inline element open while a line is being built: where on the
/// line it began, and whether it began on this line.
struct OpenSpan {
    var box: Box
    var startX: float32
    var isFirst: bool
}

extension Layout {
    /// Lays out a block container's inline content as lines and answers
    /// the content height.
    /// Lays out a block's inline content as lines, then as text-wrap-style
    /// and line-clamp ask: balanced lines, a last line not left with one
    /// word, or only so many lines with an ellipsis.
    func layoutInline(box: Box, contentWidth: float32, flow: Flow) -> float32 {
        // Floats placed by a try are taken back for the next.
        let placedBefore = flow.floats.floats.count
        func untried() {
            let extra = flow.floats.floats.count - placedBefore
            if extra > 0 { flow.floats.floats.removeLast(extra) }
        }
        var height = layoutInlineOnce(box, contentWidth: contentWidth, flow: flow)
        let wrap = box.Style.TextWrapStyle
        let n = box.Lines.count
        if (wrap == "balance" || wrap == "pretty") && n >= 2 && canReflow(box, flow) {
            var narrowest = contentWidth
            if wrap == "balance" && n <= 10 {
                // The narrowest width that keeps the same lines.
                var lo = contentWidth / float32(n)
                var hi = contentWidth
                var k = 0
                while k < 12 {
                    let mid = (lo + hi) / 2
                    untried()
                    _ = layoutInlineOnce(box, contentWidth: mid, flow: flow)
                    if box.Lines.count > n { lo = mid } else { hi = mid }
                    k += 1
                }
                narrowest = hi
            } else if wrap == "pretty" && lonelyLastLine(box) {
                // A little narrower, so that a word comes down to the last.
                var k: float32 = 1
                while k <= 4 {
                    let w = contentWidth * (1 - 0.05 * k)
                    untried()
                    _ = layoutInlineOnce(box, contentWidth: w, flow: flow)
                    if box.Lines.count == n && !lonelyLastLine(box) { narrowest = w; break }
                    k += 1
                }
            }
            untried()
            height = layoutInlineOnce(box, contentWidth: narrowest, flow: flow)
            if narrowest < contentWidth { shiftForAlignment(box, contentWidth - narrowest) }
        }
        let clamp = int(box.Style.LineClamp)
        if clamp > 0 && box.Lines.count > clamp {
            box.Lines.removeLast(box.Lines.count - clamp)
            ellipsize(&box.Lines[clamp - 1], width: contentWidth, box: box)
            let last = box.Lines[clamp - 1]
            height = last.Y + last.Height - box.ContentY
        }
        return height
    }

    /// Whether the lines can be laid out again: no absolutely positioned
    /// boxes among the content, which a layout attaches once each.
    func canReflow(box: Box, flow: Flow) -> bool {
        func clean(b: Box) -> bool {
            for c in b.Children where c.Kind != .text {
                if c.Style.Position == .absolute || c.Style.Position == .fixed { return false }
                if c.Kind == .inline && !clean(c) { return false }
            }
            return true
        }
        return clean(box)
    }

    /// Whether the last line is one word under a quarter of the width.
    func lonelyLastLine(box: Box) -> bool {
        guard let last = box.Lines.last else { return false }
        return wordsOn(last) <= 1
    }

    /// How many words a line holds: runs of text between spaces.
    func wordsOn(line: Line) -> int {
        var words = 0
        var inWord = false
        for f in line.Fragments where f.Kind == .text {
            for c in f.Text.utf8 {
                let space = c == 32 || c == 10 || c == 9
                if !space && !inWord { words += 1 }
                inWord = !space
            }
            inWord = false
        }
        return words
    }

    /// Moves the lines over by the room a narrower layout left, as their
    /// alignment says: half for center, all of it for right and end.
    func shiftForAlignment(box: Box, room: float32) {
        var d: float32 = 0
        let rtl = box.LinesRightToLeft
        switch box.Style.TextAlign {
        case .center: d = room / 2
        case .right: d = room
        case .end: if rtl { return } else { d = room }
        case .start, .justify: if rtl { d = room } else { return }
        default: return
        }
        var i = 0
        while i < box.Lines.count {
            box.Lines[i].X += d
            var k = 0
            while k < box.Lines[i].Fragments.count {
                box.Lines[i].Fragments[k].X += d
                if box.Lines[i].Fragments[k].Kind == .atomic { box.Lines[i].Fragments[k].Box.X += d }
                k += 1
            }
            k = 0
            while k < box.Lines[i].Spans.count {
                box.Lines[i].Spans[k].X += d
                k += 1
            }
            i += 1
        }
    }

    /// Ends a line with an ellipsis that fits in the width: what
    /// line-clamp leaves at the last line it keeps.
    func ellipsize(line: inout Line, width: float32, box: Box) {
        let face = box.Style.Face
        let ellipsis = face.Shape("…")
        let limit = box.ContentX + width - ellipsis.Width
        var fragments = line.Fragments
        while let last = fragments.last, last.Kind != .text || IsBlank(last.Text) { fragments.removeLast() }
        while let last = fragments.last, last.X > limit { fragments.removeLast() }
        guard var last = fragments.last, last.Kind == .text else { return }
        let f = last.Owner.Style.Face
        let bytes = [uint8](last.Text.utf8)
        var cut = bytes.count
        while cut > 0 && last.X + f.Measure(stringOf(bytes, 0, cut)) > limit {
            cut -= 1
            while cut > 0 && (bytes[cut] & 0xC0) == 0x80 { cut -= 1 }
        }
        last.Text = stringOf(bytes, 0, cut) + "…"
        last.Run = f.Shape(last.Text)
        last.Width = last.Run.Width
        fragments[fragments.count - 1] = last
        line.Fragments = fragments
    }

    func layoutInlineOnce(box: Box, contentWidth: float32, flow: Flow) -> float32 {
        box.Lines = []
        var items: [Item] = []
        var pendingSpace = false
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(box))
        let rootX = flow.x + box.ContentX
        let rootY = flow.y + box.ContentY
        collectItems(box, owner: box, cb: cb, flow: flow,
                     decoration: box.Style.TextDecoration, decorationColor: box.Style.TextDecorationColor ?? box.Style.Color,
                     into: &items, pendingSpace: &pendingSpace)
        // A collapsing space at the very end never shows.
        while let last = items.last, last.kind == .space, last.owner.Style.WhiteSpace.Collapses {
            items.removeLast()
        }
        if items.isEmpty && box.Marker.isEmpty {
            return 0
        }
        // Only empty inline elements, with no margins, padding or borders
        // across: a line with no text or other content is no line (CSS 2.1
        // section 9.4.2), and takes no height. A <span></span> or a custom
        // element holding only a script lays out as nothing.
        var phantom = box.Marker.isEmpty
        for it in items where phantom {
            if !(it.kind == .open || it.kind == .close) || it.width != 0 { phantom = false }
        }
        if phantom {
            return 0
        }
        resolveBidi(box, &items)

        let indent = box.Style.TextIndent.Or(0, base: contentWidth)
        var y: float32 = 0
        var lineItems: [Item] = []
        var lineWidth: float32 = 0
        var open: [OpenSpan] = []
        var lineHasContent = false
        var firstLine = true
        var contentRight: float32 = 0
        // A line may break before a word only where a space came before
        // it: not between a word and the punctuation stuck to it.
        var breakOpportunity = true
        // Floats met in the text go to the side at the next line's top.
        var pendingFloats: [Box] = []
        let strutHeight = box.Style.LineHeightPx
        let floats = flow.floats

        // Where the current line starts and how wide it is, between the
        // floats that reach it.
        func band() -> (start: float32, width: float32) {
            let b = floats.intrusions(y: rootY + y, height: strutHeight, left: rootX, right: rootX + contentWidth)
            return (start: b.left - rootX, width: b.right - b.left)
        }

        func available() -> float32 {
            return band().width - (firstLine ? indent : 0)
        }

        func narrowed() -> bool {
            return band().width < contentWidth - 0.01
        }

        func placePendingFloats() {
            for f in pendingFloats {
                let placed = floats.place(f, left: f.Style.Float == .left, y: rootY + y,
                                          containerLeft: rootX, containerRight: rootX + contentWidth)
                f.X = placed.x - rootX + box.ContentX + f.Margin.Left
                f.Y = placed.y - rootY + box.ContentY + f.Margin.Top
            }
            pendingFloats = []
        }

        func finishLine(forced: Bool) {
            // Trailing spaces hang off the line: they take no room.
            while let last = lineItems.last, last.kind == .space, last.owner.Style.WhiteSpace.Collapses {
                lineItems.removeLast()
            }
            if !lineHasContent && !forced && !firstLine {
                lineItems = []
                lineWidth = 0
                placePendingFloats()
                return
            }
            let b = band()
            let line = buildLine(box, items: lineItems, y: y, startX: b.start, contentWidth: b.width,
                                 indent: firstLine ? indent : 0, open: &open, isFirst: firstLine, isLast: forced)
            box.Lines.append(line)
            y += line.Height
            for f in line.Fragments {
                if f.X + f.Width > contentRight { contentRight = f.X + f.Width }
            }
            lineItems = []
            lineWidth = 0
            lineHasContent = false
            firstLine = false
            placePendingFloats()
        }

        placePendingFloats()
        let firstLineFont = firstLineFontOf(box)
        for plain in items {
            var item = plain
            if firstLine, let fl = firstLineFont { item = inFirstLineFont(item, block: box, style: fl) }
            switch item.kind {
            case .float:
                // Beside the line's content when it fits there, else at
                // the top of the next line.
                if lineHasContent && lineWidth + item.box.OuterWidth > available() + 0.01 {
                    pendingFloats.append(item.box)
                } else {
                    let placed = floats.place(item.box, left: item.box.Style.Float == .left, y: rootY + y,
                                              containerLeft: rootX, containerRight: rootX + contentWidth)
                    item.box.X = placed.x - rootX + box.ContentX + item.box.Margin.Left
                    item.box.Y = placed.y - rootY + box.ContentY + item.box.Margin.Top
                }
            case .space:
                breakOpportunity = true
                // Spaces that collapse never start a line; preserved
                // ones do.
                if !lineHasContent && item.owner.Style.WhiteSpace.Collapses { continue }
                lineItems.append(item)
                lineWidth += item.width
                if !item.owner.Style.WhiteSpace.Collapses { lineHasContent = true }
            case .word, .atomic:
                let canBreak = breakOpportunity || item.kind == .atomic || item.softBreakBefore
                breakOpportunity = item.kind == .atomic
                // An empty line squeezed by floats that cannot hold the
                // word moves down to where the floats end.
                var guardRounds = 0
                while !lineHasContent && item.width > available() + 0.01 && narrowed() && guardRounds < 64 {
                    guardRounds += 1
                    guard let next = floats.nextBand(after: rootY + y) else { break }
                    y = next - rootY
                }
                // A word too long for a line of its own is broken inside
                // where overflow-wrap or word-break allow; break-all
                // breaks any word at the line's end.
                if item.kind == .word && item.breakable {
                    let style = item.owner.Style
                    let breakAll = style.WordBreak == .breakAll
                    let mayBreak = breakAll || style.OverflowWrap != .normal
                    if mayBreak {
                        var rest = item
                        var rounds = 0
                        while rounds < 1000 {
                            rounds += 1
                            let room = available() - (lineHasContent ? lineWidth : 0)
                            let tooWide = rest.width > room + 0.01
                            if !tooWide { break }
                            // Whole-word wrapping first, unless break-all.
                            if lineHasContent && canBreak && !breakAll && rest.width <= available() + 0.01 { break }
                            if lineHasContent && (!breakAll || room < style.FontSize) && (canBreak || rounds > 1) {
                                finishLine(forced: false)
                                continue
                            }
                            let split = splitWord(rest, fitting: available() - (lineHasContent ? lineWidth : 0))
                            if split.head.length == 0 {
                                if lineHasContent { finishLine(forced: false); continue }
                                break
                            }
                            lineItems.append(split.head)
                            lineWidth += split.head.width
                            lineHasContent = true
                            if split.tail.length == 0 {
                                rest.length = 0
                                break
                            }
                            rest = split.tail
                            finishLine(forced: false)
                        }
                        if rest.length == 0 { continue }
                        if rest.length != item.length {
                            lineItems.append(rest)
                            lineWidth += rest.width
                            lineHasContent = true
                            continue
                        }
                    }
                }
                // hanging-punctuation: allow-end and force-end let a stop at a
                // line's end stand out past it, rather than move down.
                let hangingWords = box.Style.HangingPunctuation
                if lineHasContent && (hangingWords.contains("allow-end") || hangingWords.contains("force-end")) && isStop(item.text) {
                    lineItems.append(item)
                    lineHasContent = true
                    continue
                }
                if lineHasContent && item.breakable && canBreak && lineWidth + item.width > available() + 0.01 {
                    // Break before the item, at the last space. The
                    // starts of inline elements just before it belong
                    // with it on the new line.
                    var carried: [Item] = []
                    while let last = lineItems.last, last.kind == .open {
                        carried.insert(last, at: 0)
                        lineWidth -= last.width
                        lineItems.removeLast()
                        if let idx = lastIndex(open, of: last.box) { open.remove(at: idx) }
                    }
                    // Breaking at a soft hyphen, the piece before shows
                    // it; where the hyphen doesn't fit, the break moves
                    // back a piece.
                    var moved: [Item] = []
                    if item.softBreakBefore && carried.isEmpty {
                        while let last = lineItems.last, last.kind == .word, last.softBreakBefore, lineItems.count > 1,
                              lineWidth - last.width + hyphenated(last).width > available() + 0.01 {
                            moved.insert(last, at: 0)
                            lineWidth -= last.width
                            lineItems.removeLast()
                        }
                        if let last = lineItems.last, last.kind == .word {
                            let h = hyphenated(last)
                            lineWidth += h.width - last.width
                            lineItems[lineItems.count - 1] = h
                        }
                    }
                    finishLine(forced: false)
                    for m in moved {
                        lineItems.append(m)
                        lineWidth += m.width
                        lineHasContent = true
                    }
                    for c in carried {
                        lineItems.append(c)
                        lineWidth += c.width
                    }
                }
                // A break just now took it off the first line.
                if !firstLine { item = plain }
                lineItems.append(item)
                lineWidth += item.width
                lineHasContent = true
            case .open, .close:
                lineItems.append(item)
                lineWidth += item.width
            case .positioned:
                item.box.X = box.ContentX + lineWidth
                item.box.Y = box.ContentY + y
            case .lineBreak, .newline:
                lineItems.append(item)
                finishLine(forced: true)
                breakOpportunity = true
            }
        }
        if lineHasContent || box.Lines.isEmpty {
            finishLine(forced: true)
        }
        box.ContentWidth = contentRight - box.ContentX
        return y - trimTextBox(box)
    }

    /// text-box-trim: the first line's top and the last's bottom cut to the
    /// edges text-box-edge names. Answers how much height went.
    func trimTextBox(box: Box) -> float32 {
        let s = box.Style
        let trim = trimOf(box)
        if !trim.start && !trim.end || box.Lines.isEmpty { return 0 }
        let face = s.Face
        let half = (s.LineHeightPx - (face.Ascent + face.Descent)) / 2
        let edges = trim.edge.split(separator: " ").map { string($0) }
        let over = edges.first ?? "text"
        let under = edges.count > 1 ? edges[1] : (over == "cap" || over == "ex" ? "alphabetic" : over)
        var top: float32 = 0
        var bottom: float32 = 0
        if trim.start {
            top = half
            // The font's cap height, or near enough 1.4 of its x height
            // where it doesn't say.
            if over == "cap" { top += face.Ascent - (face.CapHeight > 0 ? face.CapHeight : face.XHeight * 1.4) }
            if over == "ex" { top += face.Ascent - face.XHeight }
        }
        if trim.end {
            bottom = half
            if under == "alphabetic" { bottom += face.Descent }
        }
        if top != 0 {
            var i = 0
            while i < box.Lines.count {
                box.Lines[i].Y -= top
                var k = 0
                while k < box.Lines[i].Fragments.count {
                    box.Lines[i].Fragments[k].Y -= top
                    k += 1
                }
                k = 0
                while k < box.Lines[i].Spans.count {
                    box.Lines[i].Spans[k].Y -= top
                    k += 1
                }
                i += 1
            }
        }
        return top + bottom
    }

    /// Gives each item its bidi level, where the paragraph is right to
    /// left or holds right-to-left text: the text of the items in order,
    /// with inline elements' unicode-bidi as the explicit marks it
    /// stands for, through the bidi algorithm. A word takes the highest
    /// level of its characters.
    func resolveBidi(box: Box, items: inout [Item]) {
        box.BidiLines = false
        box.LinesRightToLeft = box.Style.Direction == .rtl
        var text: [uint32] = []
        var at: [int] = []
        var any = box.Style.Direction == .rtl || box.Style.UnicodeBidi == .plaintext
        for it in items {
            at.append(text.count)
            switch it.kind {
            case .word, .space:
                if it.text.isEmpty { text.append(0x20) }
                for u in it.text.unicodeScalars {
                    text.append(u.value)
                    if !any && u.value >= 0x590 { any = true }
                }
            case .atomic:
                text.append(0xFFFC)
            case .open:
                let st = it.box.Style
                let rtl = st.Direction == .rtl
                switch st.UnicodeBidi {
                case .embed: text.append(rtl ? 0x202B : 0x202A)
                case .isolate: text.append(rtl ? 0x2067 : 0x2066)
                case .bidiOverride: text.append(rtl ? 0x202E : 0x202D)
                case .isolateOverride:
                    text.append(rtl ? 0x2067 : 0x2066)
                    text.append(rtl ? 0x202E : 0x202D)
                case .plaintext: text.append(0x2068)
                case .normal: break
                }
                if st.UnicodeBidi != .normal && rtl { any = true }
            case .close:
                switch it.box.Style.UnicodeBidi {
                case .embed, .bidiOverride: text.append(0x202C)
                case .isolate, .plaintext: text.append(0x2069)
                case .isolateOverride:
                    text.append(0x202C)
                    text.append(0x2069)
                case .normal: break
                }
            case .lineBreak, .newline:
                text.append(0x20)
            case .float, .positioned:
                break
            }
        }
        if !any || !bidi.HasRightToLeft(text) && box.Style.Direction != .rtl { return }
        let base: bidi.Direction? = box.Style.UnicodeBidi == .plaintext ? nil : (box.Style.Direction == .rtl ? .rtl : .ltr)
        let resolved = bidi.Levels(text, base: base)
        box.BidiLines = true
        box.LinesRightToLeft = resolved.base == 1
        var out: [Item] = []
        var i = 0
        while i < items.count {
            let from = at[i]
            let to = i + 1 < items.count ? at[i + 1] : text.count
            var item = items[i]
            var level: uint8 = resolved.base
            var mixed = false
            var k = from
            while k < to {
                if k == from { level = resolved.levels[k] } else if resolved.levels[k] != resolved.levels[from] { mixed = true }
                if resolved.levels[k] > level { level = resolved.levels[k] }
                k += 1
            }
            if item.kind == .word && mixed {
                // A word whose characters sit at different levels -- a
                // number and the full stop after it, right to left -- is
                // cut where the level changes, each piece shaped alone.
                let face = item.owner.Style.Face
                let spacing = item.owner.Style.LetterSpacing
                var piece = ""
                var pieceStart = 0
                var bytesSoFar = 0
                var pieceLevel = resolved.levels[from]
                var j = from
                for u in item.text.unicodeScalars {
                    if resolved.levels[j] != pieceLevel && !piece.isEmpty {
                        var p = item
                        p.text = piece
                        p.run = face.Shape(piece)
                        p.width = p.run.Width + spacing * float32(p.run.Count)
                        p.offset = item.offset + pieceStart
                        p.length = bytesSoFar - pieceStart
                        p.level = pieceLevel
                        out.append(p)
                        piece = ""
                        pieceStart = bytesSoFar
                        pieceLevel = resolved.levels[j]
                    }
                    piece += string(Character(u))
                    bytesSoFar += string(Character(u)).utf8.count
                    j += 1
                }
                var p = item
                p.text = piece
                p.run = face.Shape(piece)
                p.width = p.run.Width + spacing * float32(p.run.Count)
                p.offset = item.offset + pieceStart
                p.length = bytesSoFar - pieceStart
                p.level = pieceLevel
                out.append(p)
            } else {
                item.level = level
                out.append(item)
            }
            i += 1
        }
        items = out
    }

    /// Puts a line's fragments in the order they show (L2), each moved
    /// along with the room before it, and the spans over their
    /// fragments again. Answers how far the line now reaches.
    func reorderLine(box: Box, fragments: inout [Fragment], levels: [uint8], spans: inout [Span],
                     indent: float32, end: float32) -> float32 {
        if fragments.isEmpty { return end }
        let rtl = box.LinesRightToLeft
        var gaps: [float32] = []
        var prev = indent
        for f in fragments {
            gaps.append(f.X - prev)
            prev = f.X + f.Width
        }
        let after = end - prev
        let order = bidi.VisualOrder(levels)
        var reordered: [Fragment] = []
        // Right to left, the indent is at the right: the line starts at
        // the left edge.
        var x: float32 = rtl ? 0 : indent
        for i in order {
            var f = fragments[i]
            x += gaps[i]
            f.X = x
            f.RightToLeft = levels[i] & 1 == 1 && f.Kind == .text
            x += f.Width
            reordered.append(f)
        }
        fragments = reordered
        // Each span now runs over what of its element is on the line, one
        // piece for each run of it that stayed together, its padding and
        // border at the sides its ends are on.
        var split: [Span] = []
        for sp in spans {
            let b = sp.Box
            var pieces: [(lo: float32, hi: float32)] = []
            var open = false
            for f in fragments {
                var owner: Box? = f.Kind == .atomic ? f.Box : f.Owner
                var inside = false
                while let o = owner {
                    if o.Id == b.Id { inside = true; break }
                    owner = o.Parent
                }
                if inside {
                    if open {
                        pieces[pieces.count - 1].hi = f.X + f.Width
                    } else {
                        pieces.append((lo: f.X, hi: f.X + f.Width))
                        open = true
                    }
                } else {
                    open = false
                }
            }
            if pieces.isEmpty {
                split.append(sp)
                continue
            }
            let leftEnd = rtl ? sp.IsLast : sp.IsFirst
            let rightEnd = rtl ? sp.IsFirst : sp.IsLast
            var k = 0
            while k < pieces.count {
                var piece = sp
                let first = k == 0
                let last = k == pieces.count - 1
                let left = first && leftEnd ? b.Padding.Left + b.Border.Left : 0
                let right = last && rightEnd ? b.Padding.Right + b.Border.Right : 0
                piece.X = pieces[k].lo - left
                piece.Width = pieces[k].hi - pieces[k].lo + left + right
                piece.IsFirst = sp.IsFirst && first
                piece.IsLast = sp.IsLast && last
                split.append(piece)
                k += 1
            }
        }
        spans = split
        return x + after + (rtl ? indent : 0)
    }

    /// Gathers the items of a box's inline content, in order.
    func collectItems(box: Box, owner: Box, cb: ContainingBlock, flow: Flow,
                      decoration: cascade.TextDecoration, decorationColor: draw.Color,
                      into items: inout [Item], pendingSpace: inout Bool) {
        for child in box.Children {
            if child.Kind != .text && (child.Style.Position == .absolute || child.Style.Position == .fixed) {
                // Whatever kind of box it was made: laid out against its
                // containing block later, from where the text had got to.
                child.X = 0
                child.Y = 0
                attachPositioned(child, flow)
                items.append(Item(kind: .positioned, box: child, owner: owner))
                continue
            }
            if child.Style.Float != .none && child.Kind != .text {
                // A float in the text, whatever kind of box: laid out
                // now, placed when the line it is in is known.
                layoutBlock(child, cb: cb, flow: flow.root(child))
                items.append(Item(kind: .float, box: child, owner: owner))
                pendingSpace = false
                continue
            }
            switch child.Kind {
            case .text:
                textItems(child, owner: owner, decoration: decoration, decorationColor: decorationColor,
                          into: &items, pendingSpace: &pendingSpace)
            case .inline:
                resolveEdges(child, cbWidth: cb.Width)
                var openItem = Item(kind: .open, box: child, owner: child)
                openItem.width = child.Margin.Left + child.Border.Left + child.Padding.Left
                items.append(openItem)
                let deco = decoration.Union(child.Style.TextDecoration)
                let decoColor = child.Style.TextDecoration.IsNone ? decorationColor : (child.Style.TextDecorationColor ?? child.Style.Color)
                collectItems(child, owner: child, cb: cb, flow: flow,
                             decoration: deco, decorationColor: decoColor, into: &items, pendingSpace: &pendingSpace)
                var closeItem = Item(kind: .close, box: child, owner: child)
                closeItem.width = child.Margin.Right + child.Border.Right + child.Padding.Right
                items.append(closeItem)
            case .inlineBlock, .replaced:
                layoutAtomic(child, cb: cb, flow: flow)
                var item = Item(kind: .atomic, box: child, owner: owner)
                item.width = child.OuterWidth
                item.breakable = owner.Style.WhiteSpace.Wraps
                items.append(item)
                pendingSpace = false
            case .lineBreak:
                items.append(Item(kind: .lineBreak, box: child, owner: owner))
                pendingSpace = false
            case .block:
                if child.Style.Float != .none {
                    // A float in the text: laid out now, placed when the
                    // line it is in is known.
                    layoutBlock(child, cb: cb, flow: flow.root(child))
                    items.append(Item(kind: .float, box: child, owner: owner))
                    continue
                }
                // Anonymous wrapping keeps blocks out of inline content;
                // one that got here is laid out as its own line.
                layoutBlock(child, cb: cb, flow: flow)
                var item = Item(kind: .atomic, box: child, owner: owner)
                item.width = child.OuterWidth
                items.append(item)
            }
        }
    }

    /// A word piece that ends in a soft hyphen, ending a line: the
    /// hyphen shows. Its text stays as the source has it.
    func hyphenated(item: Item) -> Item {
        let b = [uint8](item.text.utf8)
        if item.autoHyphen {
            var out = item
            let style = item.owner.Style
            out.run = style.Face.Shape(item.text + "-")
            out.width = out.run.Width + style.LetterSpacing * float32(out.run.Count)
            return out
        }
        if b.count < 2 || b[b.count - 2] != 0xC2 || b[b.count - 1] != 0xAD { return item }
        var out = item
        let style = item.owner.Style
        out.run = style.Face.Shape(stringOf(b, 0, b.count - 2) + "-")
        out.width = out.run.Width + style.LetterSpacing * float32(out.run.Count)
        return out
    }

    /// The language a box's text is in: the nearest lang attribute.
    func languageOf(box: Box) -> string {
        var cur = box.Node
        while let n = cur {
            if let l = n.GetAttribute("lang"), !l.isEmpty { return l }
            cur = n.Parent
        }
        return ""
    }

    /// Splits a text box into words and spaces as its white-space says.
    func textItems(box: Box, owner: Box, decoration: cascade.TextDecoration, decorationColor: draw.Color,
                   into items: inout [Item], pendingSpace: inout Bool) {
        let style = owner.Style
        let face = style.Face
        var bytes = [uint8](box.Text.utf8)
        switch style.TextTransform {
        case .uppercase: bytes = upperBytes(bytes)
        case .lowercase: bytes = lowerBytes(bytes)
        case .capitalize: bytes = capitalizeBytes(bytes)
        case .none: break
        }
        let ws = style.WhiteSpace
        let collapses = ws.Collapses
        let keepsNewlines = ws.KeepsNewlines
        let wraps = ws.Wraps
        let spaceWidth = face.SpaceWidth + style.WordSpacing + style.LetterSpacing
        var i = 0
        let n = bytes.count
        while i < n {
            let b = bytes[i]
            if b == 10 && keepsNewlines {
                var item = Item(kind: .newline, box: box, owner: owner)
                item.offset = i
                item.length = 1
                items.append(item)
                pendingSpace = false
                i += 1
                continue
            }
            if isSpaceByte(b) {
                if collapses {
                    // One space for the run, and none after another.
                    var j = i
                    while j < n && isSpaceByte(bytes[j]) && !(bytes[j] == 10 && keepsNewlines) { j += 1 }
                    if !pendingSpace {
                        var item = Item(kind: .space, box: box, owner: owner)
                        item.width = spaceWidth
                        item.offset = i
                        item.length = j - i
                        item.text = " "
                        item.breakable = wraps
                        items.append(item)
                        pendingSpace = true
                    }
                    i = j
                } else {
                    // pre and pre-wrap: every space shows.
                    var j = i
                    var count = 0
                    while j < n && isSpaceByte(bytes[j]) && bytes[j] != 10 {
                        if bytes[j] == 9 {
                            count += int(style.TabSize)
                        } else {
                            count += 1
                        }
                        j += 1
                    }
                    var item = Item(kind: .space, box: box, owner: owner)
                    item.width = spaceWidth * float32(count)
                    item.offset = i
                    item.length = j - i
                    item.text = spaces(count)
                    item.breakable = wraps
                    items.append(item)
                    i = j
                }
                continue
            }
            var j = i
            while j < n && !isSpaceByte(bytes[j]) { j += 1 }
            // A word with soft hyphens (U+00AD) is a piece per syllable,
            // each holding the hyphen after it, which doesn't show.
            func piece(start: int, end: int) {
                let text = stringOf(bytes, start, end)
                var item = Item(kind: .word, box: box, owner: owner)
                item.text = text
                item.run = face.Shape(text)
                item.width = item.run.Width + style.LetterSpacing * float32(item.run.Count)
                item.offset = start
                item.length = end - start
                item.breakable = wraps
                item.decoration = decoration
                item.decorationColor = decorationColor
                item.softBreakBefore = start > i
                items.append(item)
            }
            // CJK breaks between its characters: each is a piece, but for
            // what may not start or end a line.
            func cjkPieces(from: int, to: int) {
                var at = from
                var cut = from
                var prev: uint32 = 0
                while at < to {
                    let d = decodeUTF8(bytes, at)
                    if at > from && (isCJK(prev) || isCJK(d.scalar)) && !noLineStart(d.scalar) && !noLineEnd(prev) {
                        piece(cut, at)
                        cut = at
                    }
                    prev = d.scalar
                    at += d.length
                }
                piece(cut, to)
            }
            var start = i
            var k = i
            var wide = false
            var w = i
            while w < j {
                if bytes[w] >= 0xE1 && style.WordBreak != .keepAll { wide = true }
                w += 1
            }
            while k + 2 < j {
                if !style.HyphensNone && bytes[k] == 0xC2 && bytes[k + 1] == 0xAD {
                    if wide && wraps { cjkPieces(start, k + 2) } else { piece(start, k + 2) }
                    start = k + 2
                    k += 2
                    continue
                }
                k += 1
            }
            // hyphens: auto: where the language's dictionary says, in a word
            // that says nothing itself.
            if style.HyphensAuto && wraps && !wide && start == i && j - i >= 5 {
                let lang = languageOf(box)
                var points: [int] = []
                if !lang.isEmpty { points = hyphen.Points(stringOf(bytes, i, j), lang: lang) }
                var cut = i
                for p in points {
                    piece(cut, i + p)
                    items[items.count - 1].autoHyphen = true
                    cut = i + p
                }
                piece(cut, j)
            } else if wide && wraps {
                cjkPieces(start, j)
            } else {
                piece(start, j)
            }
            pendingSpace = false
            i = j
        }
    }

    /// Makes a line from its items: places them left to right, merges
    /// neighbouring text of one box into fragments, aligns everything
    /// vertically, and applies text-align.
    func buildLine(box: Box, items: [Item], y: float32, startX: float32, contentWidth: float32, indent: float32,
                   open: inout [OpenSpan], isFirst: Bool, isLast: Bool) -> Line {
        // ::first-line's font sets the first line's text and its height.
        let firstLineFont = isFirst ? firstLineFontOf(box) : nil
        let strutStyle = firstLineFont ?? box.Style
        let strutFace = strutStyle.Face
        var line = Line(x: box.ContentX + startX, y: box.ContentY + y, width: contentWidth)

        var fragments: [Fragment] = []
        // Each fragment's bidi level, beside it.
        var levels: [uint8] = []
        var x: float32 = indent
        // Spans open from earlier lines continue at the line's start.
        var i = 0
        while i < open.count {
            open[i].startX = x
            open[i].isFirst = false
            i += 1
        }
        var spans: [Span] = []

        func emitSpan(o: OpenSpan, endX: float32, isLast: Bool) {
            let b = o.box
            let face = b.Style.Face
            var sp = Span(Box: b, X: o.startX, Y: 0, Width: endX - o.startX, Height: face.Ascent + face.Descent,
                          IsFirst: o.isFirst, IsLast: isLast)
            if o.isFirst { sp.X += b.Margin.Left; sp.Width -= b.Margin.Left }
            if isLast { sp.Width -= b.Margin.Right }
            spans.append(sp)
        }

        for item in items {
            switch item.kind {
            case .word, .space:
                // Join with the previous fragment when it is the same text
                // in the same style.
                // Right-to-left words stay apart: each shows its own
                // glyphs in order, and the line puts the words in theirs.
                if let last = fragments.last, last.Kind == .text, last.Box.Id == item.box.Id, last.Owner.Id == item.owner.Id,
                   levels[levels.count - 1] == item.level, item.level & 1 == 0 {
                    var f = fragments[fragments.count - 1]
                    f.Text += item.text
                    f.Run.Glyphs.append(contentsOf: item.run.Glyphs)
                    f.Run.Faces.append(contentsOf: item.run.Faces)
                    f.Run.Advances.append(contentsOf: item.run.Advances)
                    if item.kind == .space {
                        // A space has no glyphs of its own: advance the pen by one.
                        f.Run.Glyphs.append(0)
                        f.Run.Faces.append(0)
                        f.Run.Advances.append(item.width)
                    }
                    f.Run.Width += item.width
                    f.Width += item.width
                    fragments[fragments.count - 1] = f
                } else {
                    var f = Fragment(kind: .text, box: item.box, owner: item.owner)
                    f.X = x
                    f.Width = item.width
                    f.Text = item.text
                    f.Run = item.run
                    if item.level & 1 == 1 && item.kind == .word {
                        // Text with no right-to-left letters of its own at a
                        // right-to-left level -- an override, or brackets and
                        // punctuation -- is reversed and mirrored here; the
                        // shaper orders only what is right to left itself.
                        var cps: [uint32] = []
                        for u in item.text.unicodeScalars { cps.append(u.value) }
                        if !bidi.HasRightToLeft(cps) {
                            var shown = ""
                            var k = cps.count - 1
                            while k >= 0 {
                                if let u = Unicode.Scalar(bidi.Mirror(cps[k])) { shown += string(Character(u)) }
                                k -= 1
                            }
                            f.Run = item.owner.Style.Face.Shape(shown)
                        }
                    }
                    if item.kind == .space {
                        f.Run.Glyphs.append(0)
                        f.Run.Faces.append(0)
                        f.Run.Advances.append(item.width)
                        f.Run.Width = item.width
                    }
                    f.Offset = item.offset + item.box.TextStart
                    f.Decoration = item.decoration
                    f.DecorationColor = item.decorationColor
                    fragments.append(f)
                    levels.append(item.level)
                }
                x += item.width
            case .atomic:
                var f = Fragment(kind: .atomic, box: item.box, owner: item.owner)
                f.X = x
                f.Width = item.width
                fragments.append(f)
                levels.append(item.level)
                x += item.width
            case .open:
                open.append(OpenSpan(box: item.box, startX: x, isFirst: true))
                x += item.width
            case .close:
                x += item.width
                if let idx = lastIndex(open, of: item.box) {
                    emitSpan(open[idx], endX: x, isLast: true)
                    open.remove(at: idx)
                }
            case .lineBreak, .newline, .float, .positioned:
                break
            }
        }
        // Spans still open run to the line's end.
        for o in open {
            emitSpan(o, endX: x, isLast: false)
        }
        var used = x

        // text-overflow: ellipsis on a clipped line that overflows: the
        // text is cut where an ellipsis still fits.
        if strutStyle.TextOverflow == .ellipsis && strutStyle.OverflowX.Clips && used > contentWidth + 0.01 && !fragments.isEmpty {
            let ellipsis = strutFace.Shape("…")
            let limit = contentWidth - ellipsis.Width
            var keep = fragments.count
            while keep > 0 && fragments[keep - 1].X > limit { keep -= 1 }
            if keep > 0 {
                var last = fragments[keep - 1]
                if last.Kind == .text && last.X + last.Width > limit {
                    let face = last.Owner.Style.Face
                    let bytes = [uint8](last.Text.utf8)
                    var cut = 0
                    var i = 1
                    while i <= bytes.count {
                        if i == bytes.count || (bytes[i] & 0xC0) != 0x80 {
                            if last.X + face.Measure(stringOf(bytes, 0, i)) > limit { break }
                            cut = i
                        }
                        i += 1
                    }
                    last.Text = stringOf(bytes, 0, cut) + "…"
                    last.Run = face.Shape(last.Text)
                    last.Width = last.Run.Width
                    fragments[keep - 1] = last
                }
                while fragments.count > keep { fragments.removeLast() }
                while levels.count > keep { levels.removeLast() }
                used = fragments[keep - 1].X + fragments[keep - 1].Width
            }
        }
        if box.BidiLines {
            used = reorderLine(box, &fragments, levels, &spans, indent: indent, end: used)
        }

        // Vertical metrics: each fragment's box around the baseline.
        let strutAscent = strutFace.Ascent
        let strutDescent = strutFace.Descent
        let strutLH = strutStyle.LineHeightPx
        let strutHalf = (strutLH - (strutAscent + strutDescent)) / 2
        var top: float32 = -(strutAscent + strutHalf)
        var bottom: float32 = strutDescent + strutHalf
        var shifts: [float32] = []
        var aligned: [cascade.VerticalAlign] = []
        i = 0
        while i < fragments.count {
            var f = fragments[i]
            let ownerStyle = f.Owner.Style
            var shift: float32 = 0
            // vertical-align is an inline box's: text straight in the
            // block sits on the baseline whatever the block says.
            var va = f.Owner.Kind == .inline ? ownerStyle.VerticalAlign : cascade.VerticalAlign.baseline
            if f.Kind == .atomic {
                let b = f.Box
                va = b.Style.VerticalAlign
                f.Height = b.OuterHeight
                let baseline = b.Baseline ?? (b.Height + b.Margin.Bottom)
                f.Ascent = baseline + b.Margin.Top
                if b.Baseline == nil { f.Ascent = f.Height }
            } else {
                // Text that takes its font from the block takes ::first-line's.
                let setIn = firstLineFont != nil && ownerStyle.Face === box.Style.Face ? firstLineFont! : ownerStyle
                let face = setIn.Face
                let lh = setIn.LineHeightPx
                let half = (lh - (face.Ascent + face.Descent)) / 2
                f.Ascent = face.Ascent + half
                f.Height = lh
            }
            switch va {
            case .baseline: shift = 0
            case .sub: shift = ownerStyle.FontSize * 0.2
            case .super: shift = -ownerStyle.FontSize * 0.35
            case .middle:
                let parentFace = strutFace
                let mid = f.Ascent - f.Height / 2
                shift = mid - parentFace.XHeight / 2
            case .textTop:
                shift = f.Ascent - strutAscent
            case .textBottom:
                shift = strutDescent - (f.Height - f.Ascent)
            case .length(let l):
                shift = -(l.Or(0, base: ownerStyle.LineHeightPx))
            case .top, .bottom:
                shift = 0
            }
            shifts.append(shift)
            aligned.append(va)
            if va != .top && va != .bottom {
                let t = -f.Ascent + shift
                let b = (f.Height - f.Ascent) + shift
                if t < top { top = t }
                if b > bottom { bottom = b }
            }
            fragments[i] = f
            i += 1
        }
        var lineHeight = bottom - top
        // Boxes aligned to the line's top or bottom may make it taller.
        i = 0
        while i < fragments.count {
            if aligned[i] == .top || aligned[i] == .bottom {
                if fragments[i].Height > lineHeight { lineHeight = fragments[i].Height }
            }
            i += 1
        }
        if aligned.count > 0 {
            // Room added above extends the line downward from the top.
            let extra = lineHeight - (bottom - top)
            if extra > 0 { bottom += extra }
        }
        let baseline = -top
        line.Height = bottom - top
        line.Baseline = baseline

        // Horizontal alignment: start and end are the right and left
        // where the lines run right to left.
        var dx: float32 = 0
        var free = contentWidth - used
        let rtl = box.LinesRightToLeft
        // The last line, and a line a forced break ends, aligns by
        // text-align-last; where that is auto, a justified paragraph's
        // starts at the start.
        // hanging-punctuation: a first line's opening mark, or a last line's
        // closing one, sits outside the line.
        if !strutStyle.HangingPunctuation.hasPrefix("none") && !fragments.isEmpty {
            let words = strutStyle.HangingPunctuation.split(separator: " ").map { string($0) }
            if isFirst && words.contains("first"), let f = fragments.first, f.Kind == .text, let c = f.Text.unicodeScalars.first, hangsFirst(c.value) {
                let width = f.Run.Advances.first ?? 0
                var k = 0
                while k < fragments.count {
                    fragments[k].X -= width
                    k += 1
                }
                k = 0
                while k < spans.count {
                    spans[k].X -= width
                    k += 1
                }
            }
            if isLast && words.contains("last"), let f = fragments.last, f.Kind == .text {
                var lastChar: uint32 = 0
                for u in f.Text.unicodeScalars { lastChar = u.value }
                if hangsLast(lastChar) { free += f.Run.Advances.last ?? 0 }
            }
        }
        var align = strutStyle.TextAlign
        if isLast {
            if let last = strutStyle.TextAlignLast { align = last } else if align == .justify { align = .start }
        }
        if free > 0 {
            switch align {
            case .center: dx = free / 2
            case .right: dx = free
            case .end: dx = rtl ? 0 : free
            case .start: dx = rtl ? free : 0
            case .justify:
                // The line spreads its free room over its spaces; the
                // fragments and spans after each one move on.
                justify(&fragments, &spans, free: free)
            default: dx = 0
            }
        }

        i = 0
        while i < fragments.count {
            var f = fragments[i]
            f.X += line.X + dx
            switch aligned[i] {
            case .top:
                f.Y = line.Y
            case .bottom:
                f.Y = line.Y + line.Height - f.Height
            default:
                f.Y = line.Y + baseline - f.Ascent + shifts[i]
            }
            if f.Kind == .atomic {
                let b = f.Box
                b.X = f.X + b.Margin.Left
                b.Y = f.Y + b.Margin.Top
            }
            fragments[i] = f
            i += 1
        }
        i = 0
        while i < spans.count {
            var sp = spans[i]
            let b = sp.Box
            let face = b.Style.Face
            sp.X += line.X + dx
            sp.Y = line.Y + baseline - face.Ascent - b.Padding.Top - b.Border.Top
            sp.Height = face.Ascent + face.Descent + b.Padding.Vertical + b.Border.Vertical
            spans[i] = sp
            i += 1
        }
        line.Fragments = fragments
        line.Spans = spans

        // A list marker sits outside the first line, or starts it.
        if isFirst && !box.Marker.isEmpty {
            var m = Fragment(kind: .marker, box: box, owner: box)
            m.Text = box.Marker
            if box.MarkerImage != nil || box.MarkerVector != nil {
                // An image marker sits on the baseline, a space from the
                // text.
                m.Width = box.MarkerImageSize.Width + strutFace.SpaceWidth
                m.Ascent = box.MarkerImageSize.Height
                m.Height = box.MarkerImageSize.Height
            } else {
                m.Run = (box.MarkerStyle?.Face ?? strutFace).Shape(box.Marker)
                m.Width = m.Run.Width
                m.Ascent = strutAscent + strutHalf
                m.Height = strutLH
            }
            m.Y = line.Y + baseline - m.Ascent
            if rtl {
                // Right to left, the marker is at the right: outside,
                // past the line's end; inside, the line's last thing.
                m.X = box.Style.ListStylePosition == .inside ? line.X + dx + used : line.X + contentWidth + strutFace.SpaceWidth * 1.5
                if box.Style.ListStylePosition == .inside {
                    var k = 0
                    while k < line.Fragments.count {
                        line.Fragments[k].X -= m.Width + strutFace.SpaceWidth
                        k += 1
                    }
                    k = 0
                    while k < line.Spans.count {
                        line.Spans[k].X -= m.Width + strutFace.SpaceWidth
                        k += 1
                    }
                    m.X -= m.Width
                }
            } else if box.Style.ListStylePosition == .inside {
                m.X = line.X + dx
                var k = 0
                while k < line.Fragments.count {
                    line.Fragments[k].X += m.Width + strutFace.SpaceWidth
                    k += 1
                }
                k = 0
                while k < line.Spans.count {
                    line.Spans[k].X += m.Width + strutFace.SpaceWidth
                    k += 1
                }
            } else {
                m.X = line.X - m.Width - strutFace.SpaceWidth * 1.5
            }
            line.Fragments.insert(m, at: 0)
        }
        return line
    }

    /// Widens the spaces of a line's text fragments so it fills its free
    /// room. Spaces are the zero glyphs the fragments carry.
    func justify(fragments: inout [Fragment], spans: inout [Span], free: float32) {
        // text-justify: none leaves it; inter-character spreads the room
        // between all the glyphs, not only the spaces.
        var byCharacter = false
        if let first = fragments.first {
            if first.Owner.Style.TextJustify == "none" { return }
            byCharacter = first.Owner.Style.TextJustify == "inter-character"
        }
        var spaces = 0
        for f in fragments where f.Kind == .text {
            for g in f.Run.Glyphs where g == 0 || byCharacter { spaces += 1 }
        }
        if byCharacter && spaces > 1 { spaces -= 1 }
        if spaces == 0 { return }
        let each = free / float32(spaces)
        var given = 0
        // Where each fragment began and how much it grew, for the spans.
        var oldX: [float32] = []
        var grown: [float32] = []
        var shift: float32 = 0
        var i = 0
        while i < fragments.count {
            var f = fragments[i]
            oldX.append(f.X)
            f.X += shift
            var g: float32 = 0
            if f.Kind == .text {
                var k = 0
                while k < f.Run.Glyphs.count {
                    if (f.Run.Glyphs[k] == 0 || byCharacter) && given < spaces {
                        f.Run.Advances[k] += each
                        g += each
                        given += 1
                    }
                    k += 1
                }
                f.Run.Width += g
                f.Width += g
            }
            grown.append(g)
            shift += g
            fragments[i] = f
            i += 1
        }
        // A span's edges move by the growth of the fragments before them.
        func moved(x: float32) -> float32 {
            var d: float32 = 0
            var k = 0
            while k < oldX.count {
                if oldX[k] < x - 0.01 { d += grown[k] }
                k += 1
            }
            return x + d
        }
        i = 0
        while i < spans.count {
            let x0 = moved(spans[i].X)
            let x1 = moved(spans[i].X + spans[i].Width)
            spans[i].X = x0
            spans[i].Width = x1 - x0
            i += 1
        }
    }

    /// The widest and narrowest the inline content of a box can be.
    func inlineIntrinsicWidths(box: Box) -> (min: float32, max: float32) {
        var items: [Item] = []
        var pendingSpace = false
        let cb = ContainingBlock(width: 0, height: nil)
        collectItems(box, owner: box, cb: cb, flow: Flow(positioned: box, floats: FloatContext(), x: 0, y: 0),
                     decoration: cascade.TextDecoration(), decorationColor: box.Style.Color,
                     into: &items, pendingSpace: &pendingSpace)
        var lineMax: float32 = 0
        var maxW: float32 = 0
        var minW: float32 = 0
        var current: float32 = 0
        for item in items {
            switch item.kind {
            case .lineBreak, .newline:
                if lineMax > maxW { maxW = lineMax }
                lineMax = 0
                if current > minW { minW = current }
                current = 0
            case .space:
                lineMax += item.width
                if item.breakable {
                    if current > minW { minW = current }
                    current = 0
                } else {
                    current += item.width
                }
            case .atomic, .float:
                // An atomic inline gives its own contributions, not the
                // width it took when laid out here, against no width at
                // all, where a percentage would have come to nothing.
                var most = item.width
                var least = item.width
                if item.kind == .atomic {
                    let w = intrinsicWidths(item.box)
                    let m = item.box.Margin.Horizontal
                    most = w.max + m
                    least = w.min + m
                }
                lineMax += most
                if current > minW { minW = current }
                if least > minW { minW = least }
                current = 0
            default:
                lineMax += item.width
                current += item.width
            }
        }
        if lineMax > maxW { maxW = lineMax }
        if current > minW { minW = current }
        return (min: minW, max: maxW)
    }
}

/// A word cut in two at the last character boundary where the first
/// part fits a width; the head is empty where not even one character
/// fits.
/// A block's ::first-line where it changes the font or the line's height:
/// nil where only its color does, which painting alone sees to.
func firstLineFontOf(box: Box) -> cascade.ComputedStyle? {
    guard let fl = box.FirstLineStyle else { return nil }
    if fl.Face !== box.Style.Face || fl.LineHeightPx != box.Style.LineHeightPx { return fl }
    return nil
}

/// A word or space reset in ::first-line's font, where it takes its font
/// from the block.
func inFirstLineFont(item: Item, block: Box, style: cascade.ComputedStyle) -> Item {
    if item.owner.Style.Face !== block.Style.Face { return item }
    var out = item
    if item.kind == .word {
        out.run = style.Face.Shape(item.text)
        out.width = out.run.Width + style.LetterSpacing * float32(out.run.Count)
    } else if item.kind == .space {
        out.width = style.Face.SpaceWidth + style.WordSpacing + style.LetterSpacing
    }
    return out
}

/// A full stop or comma, for hanging-punctuation's allow-end and force-end.
func isStop(text: string) -> bool {
    switch text {
    case ",", ".", "\u{060C}", "\u{06D4}", "\u{3001}", "\u{3002}", "\u{FF0C}", "\u{FF0E}", "\u{FE50}", "\u{FE51}", "\u{FE52}", "\u{FF61}", "\u{FF64}": return true
    default: return false
    }
}

/// Opening marks hanging-punctuation: first hangs.
func hangsFirst(c: uint32) -> bool {
    switch c {
    case 0x22, 0x27, 0x28, 0x5B, 0x7B, 0xAB, 0x2018, 0x201C, 0x201E, 0x2039, 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0xFF08: return true
    default: return false
    }
}

/// Closing marks hanging-punctuation: last hangs.
func hangsLast(c: uint32) -> bool {
    switch c {
    case 0x22, 0x27, 0x29, 0x5D, 0x7D, 0xBB, 0x2019, 0x201D, 0x203A, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0xFF09: return true
    default: return false
    }
}

/// The character at a place in UTF-8, and how many bytes it takes.
func decodeUTF8(b: [uint8], at: int) -> (scalar: uint32, length: int) {
    let c = uint32(b[at])
    func cont(i: int) -> uint32 { return at + i < b.count ? uint32(b[at + i]) & 0x3F : 0 }
    if c < 0x80 { return (scalar: c, length: 1) }
    if c < 0xE0 { return (scalar: (c & 0x1F) << 6 | cont(1), length: 2) }
    if c < 0xF0 { return (scalar: (c & 0x0F) << 12 | cont(1) << 6 | cont(2), length: 3) }
    return (scalar: (c & 0x07) << 18 | cont(1) << 12 | cont(2) << 6 | cont(3), length: 4)
}

/// Ideographs, kana and full-width forms: a line may break either side.
func isCJK(c: uint32) -> bool {
    return (c >= 0x2E80 && c <= 0x9FFF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFE30 && c <= 0xFE4F)
        || (c >= 0xFF00 && c <= 0xFFEF) || (c >= 0x20000 && c <= 0x3FFFF)
}

/// What may not start a line: closing marks, small kana, and the rest of
/// what CSS's line-break calls strict.
func noLineStart(c: uint32) -> bool {
    switch c {
    case 0x3001, 0x3002, 0xFF0C, 0xFF0E, 0x30FB, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F, 0x30FC, 0x3005,
         0xFF09, 0xFF3D, 0xFF5D, 0x3015, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3017, 0x3019, 0x301B,
         0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E,
         0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE:
        return true
    default:
        return false
    }
}

/// What may not end a line: opening marks.
func noLineEnd(c: uint32) -> bool {
    switch c {
    case 0xFF08, 0xFF3B, 0xFF5B, 0x3014, 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3016, 0x3018, 0x301A:
        return true
    default:
        return false
    }
}

func splitWord(item: Item, fitting width: float32) -> (head: Item, tail: Item) {
    let bytes = [uint8](item.text.utf8)
    let face = item.owner.Style.Face
    let spacing = item.owner.Style.LetterSpacing
    var best = 0
    var bestWidth: float32 = 0
    var i = 1
    while i <= bytes.count {
        if i == bytes.count || (bytes[i] & 0xC0) != 0x80 {
            let prefix = stringOf(bytes, 0, i)
            let run = face.Shape(prefix)
            let w = run.Width + spacing * float32(run.Count)
            if w > width + 0.01 { break }
            best = i
            bestWidth = w
        }
        i += 1
    }
    var head = item
    var tail = item
    head.text = stringOf(bytes, 0, best)
    head.run = face.Shape(head.text)
    head.width = bestWidth
    head.length = best
    tail.text = stringOf(bytes, best, bytes.count)
    tail.run = face.Shape(tail.text)
    tail.width = tail.run.Width + spacing * float32(tail.run.Count)
    tail.offset = item.offset + best
    tail.length = bytes.count - best
    return (head: head, tail: tail)
}

func lastIndex(list: [OpenSpan], of box: Box) -> int? {
    var i = list.count - 1
    while i >= 0 {
        if list[i].box.Id == box.Id { return i }
        i -= 1
    }
    return nil
}

func spaces(n: int) -> string {
    var out = ""
    var i = 0
    while i < n {
        out += " "
        i += 1
    }
    return out
}
