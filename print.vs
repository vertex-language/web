package web

import (
    "compress/flate"
    "image/draw"
    "text/font"
    "web/cascade"
    "web/layout"
)

// Printing: the page laid out for paper, as @media print and @page say, and
// cut into sheets where CSS says it may break.

/// A sheet of paper, in CSS pixels, and its margins.
public struct PrintPaper {
    public var Width: float32
    public var Height: float32
    public var Top: float32
    public var Right: float32
    public var Bottom: float32
    public var Left: float32

    public init(width: float32 = 816, height: float32 = 1056, margin: float32 = 48) {
        Width = width
        Height = height
        Top = margin
        Right = margin
        Bottom = margin
        Left = margin
    }
}

/// Where a page may be cut.
struct PageBreaks {
    /// Places it may break; places it must; spans it mustn't.
    var may: [float32] = []
    var must: [float32] = []
    var never: [(float32, float32)] = []
}

extension Page {
    /// Draws the page on sheets of paper. @page's size and margins win over
    /// those given. Answers each sheet's picture, scale pixels to the pixel.
    public func Print(paper given: PrintPaper = PrintPaper(), scale: float32 = 2) -> [draw.Image] {
        var paper = given
        update()
        if let p = cascade.PageRule {
            if p.Width > 0 { paper.Width = p.Width }
            if p.Height > 0 { paper.Height = p.Height }
            if p.Margins.count == 4 {
                paper.Top = p.Margins[0]
                paper.Right = p.Margins[1]
                paper.Bottom = p.Margins[2]
                paper.Left = p.Margins[3]
            }
        }
        let savedSize = size
        let savedScroll = scroll
        let contentW = paper.Width - paper.Left - paper.Right
        let contentH = paper.Height - paper.Top - paper.Bottom
        cascade.MediaIsPrint = true
        printing = true
        SetViewportSize(draw.Size(contentW, contentH))
        needsStyle = true
        needsLayout = true
        update()
        var found = PageBreaks()
        if let r = root { collectBreaks(r, into: &found) }
        // Each sheet's paper: its own margins, by :first, :left and :right.
        func paperFor(sheet: int) -> PrintPaper {
            var p = paper
            if let r = cascade.PageRuleFor(sheet), r.Margins.count == 4 {
                p.Top = r.Margins[0]
                p.Right = r.Margins[1]
                p.Bottom = r.Margins[2]
                p.Left = r.Margins[3]
            }
            return p
        }
        let cuts = cutPages(found, total: contentHeight, page: { sheet in
            let p = paperFor(sheet)
            return p.Height - p.Top - p.Bottom
        })
        // The text on each sheet, for a PDF to make selectable.
        var runs: [SheetText] = []
        if let r = root { collectText(r, into: &runs) }
        printedText = []
        var sheets: [draw.Image] = []
        let w = draw.RoundToInt(paper.Width * scale)
        let h = draw.RoundToInt(paper.Height * scale)
        var i = 0
        while i + 1 < cuts.count {
            let top = cuts[i]
            let bottom = cuts[i + 1]
            let sheetPaper = paperFor(i)
            var onSheet: [SheetText] = []
            for t in runs where t.y >= top && t.y < bottom {
                var placed = t
                placed.x += sheetPaper.Left
                placed.y = t.y - top + sheetPaper.Top
                onSheet.append(placed)
            }
            printedText.append(onSheet)
            var pixels = [uint8](repeating: 255, count: int(w) * int(h) * 4)
            scroll = draw.Point(0, top)
            root?.ViewportScrollX = 0
            root?.ViewportScrollY = top
            size = draw.Size(contentW, bottom - top)
            needsRepaint = true
            Draw(into: &pixels, width: w, height: h, scale: scale, at: draw.Point(sheetPaper.Left, sheetPaper.Top))
            drawMarginBoxes(&pixels, width: w, height: h, scale: scale, paper: sheetPaper, page: i + 1, pages: cuts.count - 1)
            sheets.append(draw.Image(width: w, height: h, pixels: pixels))
            i += 1
        }
        printing = false
        cascade.MediaIsPrint = false
        size = draw.Size(contentW, contentH)
        SetViewportSize(savedSize)
        needsStyle = true
        needsLayout = true
        update()
        scroll = savedScroll
        clampScroll()
        return sheets
    }

    /// @page's margin boxes on a sheet: their text at the sheet's corners and
    /// edges, counter(page) and counter(pages) filled in.
    func drawMarginBoxes(pixels: inout [uint8], width: int32, height: int32, scale: float32, paper: PrintPaper, page: int, pages: int) {
        guard let rule = cascade.PageRuleFor(page - 1), !rule.MarginBoxes.isEmpty else { return }
        let face = font.Load(font.Spec(families: ["system-ui"], size: 10))
        draw.WithCanvas(&pixels, width: width, height: height) { canvas in
            for (slot, words) in rule.MarginBoxes {
                var text = ""
                for w in words {
                    if w == "\u{1}page" { text += "\(page)" } else if w == "\u{1}pages" { text += "\(pages)" } else { text += w }
                }
                let run = face.Shape(text)
                let top = slot.hasPrefix("top")
                let y = top ? paper.Top / 2 : paper.Height - paper.Bottom / 2
                var x = paper.Width / 2 - run.Width / 2
                if slot.hasSuffix("left") { x = paper.Left }
                if slot.hasSuffix("right") { x = paper.Width - paper.Right - run.Width }
                font.DrawRun(canvas, run, x: x * scale, baseline: (y + face.Ascent / 2) * scale, scale: scale, color: draw.Color(60, 60, 60))
            }
        }
    }

    /// The page as a PDF, each sheet a picture on a page of its paper's size.
    public func PrintPDF(paper: PrintPaper = PrintPaper(), scale: float32 = 2) -> [uint8] {
        let sheets = Print(paper: paper, scale: scale)
        return pdfOf(sheets, text: printedText, widthPoints: float32(sheets.first?.Width ?? 0) / scale * 0.75, heightPoints: float32(sheets.first?.Height ?? 0) / scale * 0.75)
    }

    /// Each run of horizontal text the boxes hold, where its baseline is on
    /// the page.
    func collectText(box: layout.Box, into out: inout [SheetText]) {
        if !box.Lines.isEmpty && box.Style.Visibility == .visible && !box.Style.IsVertical {
            let p = layout.PagePosition(box)
            for line in box.Lines {
                for f in line.Fragments where f.Kind == .text && f.Owner.Style.Visibility == .visible {
                    var shows = false
                    for u in f.Text.unicodeScalars where u.value > 32 { shows = true }
                    if !shows || f.Width <= 0 { continue }
                    out.append(SheetText(x: p.x + f.X, y: p.y + f.Y + f.Ascent, width: f.Width, size: f.Owner.Style.FontSize, text: f.Text))
                }
            }
        }
        for c in box.Children { collectText(c, into: &out) }
        for c in box.Positioned where c.Parent?.Id != box.Id { collectText(c, into: &out) }
    }

    func collectBreaks(box: layout.Box, into out: inout PageBreaks) {
        let p = layout.PagePosition(box)
        let top = p.y + scroll.Y
        let s = box.Style
        if s.BreakInsideAvoid && box.Parent != nil { out.never.append((top, top + box.Height)) }
        if box.Kind == .replaced || box.Kind == .lineBreak { return }
        // Lines keep orphans at a sheet's foot and widows at its head.
        var at = 0
        for l in box.Lines {
            if at >= Int(s.Orphans) && box.Lines.count - at >= Int(s.Widows) || at == 0 { out.may.append(top + l.Y) }
            at += 1
        }
        for c in box.Children where c.Kind != .text {
            let at = layout.PagePosition(c)
            let cTop = at.y + scroll.Y
            if forcesPageBreak(c.Style.BreakBefore) { out.must.append(cTop) }
            if forcesPageBreak(c.Style.BreakAfter) { out.must.append(cTop + c.Height) }
            if c.Style.BreakBefore != "avoid" && c.Style.BreakBefore != "avoid-page" { out.may.append(cTop) }
            collectBreaks(c, into: &out)
        }
    }

    /// Where each sheet starts, and the end of the last.
    func cutPages(found: PageBreaks, total: float32, page pageHeight: (int) -> float32) -> [float32] {
        var cuts: [float32] = [0]
        var at: float32 = 0
        let may = found.may.sorted()
        let must = found.must.sorted()
        var rounds = 0
        while at < total - 0.5 && rounds < 2000 {
            rounds += 1
            let page = pageHeight(cuts.count - 1)
            let limit = at + page
            var next = limit
            var forced = false
            for m in must where m > at + 0.5 && m <= limit {
                next = m
                forced = true
                break
            }
            if !forced && limit < total {
                var best: float32 = -1
                for c in may where c > at + 0.5 && c <= limit {
                    var inside = false
                    for n in found.never where c > n.0 + 0.5 && c < n.1 - 0.5 { inside = true }
                    if !inside { best = c }
                }
                if best > 0 { next = best }
            }
            if next > total { next = total }
            cuts.append(next)
            at = next
        }
        if cuts.count == 1 { cuts.append(pageHeight(0)) }
        return cuts
    }
}

func forcesPageBreak(word: string) -> bool {
    return word == "page" || word == "always" || word == "left" || word == "right" || word == "recto" || word == "verso"
}

/// Bytes as zlib wraps them: what PDF's FlateDecode reads.
func zlibOf(data: [uint8]) -> [uint8] {
    var a: uint32 = 1
    var b: uint32 = 0
    for v in data {
        a = (a + uint32(v)) % 65521
        b = (b + a) % 65521
    }
    var out: [uint8] = [0x78, 0x9C]
    out += flate.Compress(data)
    out += [uint8(b >> 8), uint8(b & 255), uint8(a >> 8), uint8(a & 255)]
    return out
}

/// A PDF of pictures, a page each, enough for any reader.
/// A run of text on a printed sheet: its baseline's start and width, its
/// font size, in CSS pixels on the sheet.
struct SheetText {
    var x: float32
    var y: float32
    var width: float32
    var size: float32
    var text: string
}

/// The PDF objects for a page's hidden text: a Type 0 font whose codes are
/// UTF-16 units, each a 1000-unit wide glyph, and back to Unicode by its
/// ToUnicode map, so that a reader can select, search and copy the text
/// over the picture.
func pdfTextFont(first: int) -> [(n: int, body: string)] {
    var cmap = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
    let hex = Array("0123456789ABCDEF".utf8)
    func byte(b: int) -> string { return string(decoding: [hex[b / 16], hex[b % 16]], as: UTF8.self) }
    var hi = 0
    while hi < 256 {
        let n = 256 - hi < 100 ? 256 - hi : 100
        cmap += "\(n) beginbfrange\n"
        var k = 0
        while k < n {
            let b = byte(hi + k)
            cmap += "<\(b)00> <\(b)FF> <\(b)00>\n"
            k += 1
        }
        cmap += "endbfrange\n"
        hi += n
    }
    cmap += "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend"
    return [
        (n: first, body: "<< /Type /Font /Subtype /Type0 /BaseFont /Helvetica /Encoding /Identity-H /DescendantFonts [\(first + 1) 0 R] /ToUnicode \(first + 2) 0 R >>"),
        (n: first + 1, body: "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Helvetica /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor \(first + 3) 0 R /DW 1000 /CIDToGIDMap /Identity >>"),
        (n: first + 2, body: "<< /Length \(cmap.utf8.count) >>\nstream\n\(cmap)\nendstream"),
        (n: first + 3, body: "<< /Type /FontDescriptor /FontName /Helvetica /Flags 32 /FontBBox [0 -200 1000 900] /ItalicAngle 0 /Ascent 900 /Descent -200 /CapHeight 700 /StemV 80 >>"),
    ]
}

/// A sheet's text as invisible PDF text, each run scaled to its width.
func pdfTextOps(runs: [SheetText], heightPoints: float32) -> string {
    if runs.isEmpty { return "" }
    let hex = Array("0123456789ABCDEF".utf8)
    var ops = "\nBT 3 Tr"
    for r in runs {
        var units: [uint8] = []
        var count = 0
        for u in r.text.unicodeScalars {
            let v = u.value > 0xFFFF ? 0xFFFD : int(u.value)
            for b in [v / 256, v % 256] {
                units.append(hex[b / 16])
                units.append(hex[b % 16])
            }
            count += 1
        }
        if count == 0 || r.size <= 0 { continue }
        let size = r.size * 0.75
        let stretch = 100 * r.width / (float32(count) * r.size)
        ops += "\n/F \(size) Tf \(stretch) Tz 1 0 0 1 \(r.x * 0.75) \(heightPoints - r.y * 0.75) Tm <\(string(decoding: units, as: UTF8.self))> Tj"
    }
    return ops + " ET"
}

func pdfOf(sheets: [draw.Image], text: [[SheetText]] = [], widthPoints: float32, heightPoints: float32) -> [uint8] {
    var out: [uint8] = []
    var offsets: [int] = []
    func add(s: string) { out += [uint8](s.utf8) }
    func object(n: int, body: string) {
        while offsets.count < n { offsets.append(0) }
        offsets[n - 1] = out.count
        add("\(n) 0 obj\n\(body)\nendobj\n")
    }
    add("%PDF-1.4\n")
    var kids: [string] = []
    var k = 0
    while k < sheets.count {
        kids.append("\(3 + k * 3) 0 R")
        k += 1
    }
    object(1, body: "<< /Type /Catalog /Pages 2 0 R >>")
    object(2, body: "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(sheets.count) >>")
    let font = 3 + sheets.count * 3
    k = 0
    while k < sheets.count {
        let img = sheets[k]
        let page = 3 + k * 3
        object(page, body: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(widthPoints) \(heightPoints)] /Contents \(page + 1) 0 R /Resources << /XObject << /I \(page + 2) 0 R >> /Font << /F \(font) 0 R >> >> >>")
        let draws = "q \(widthPoints) 0 0 \(heightPoints) 0 0 cm /I Do Q" + (k < text.count ? pdfTextOps(text[k], heightPoints: heightPoints) : "")
        object(page + 1, body: "<< /Length \(draws.utf8.count) >>\nstream\n\(draws)\nendstream")
        // The picture, its pixels without alpha.
        while offsets.count < page + 2 { offsets.append(0) }
        offsets[page + 1] = out.count
        var rgb = [uint8](repeating: 255, count: int(img.Width) * int(img.Height) * 3)
        var i = 0
        var o = 0
        while o < rgb.count {
            rgb[o] = img.Pixels[i]
            rgb[o + 1] = img.Pixels[i + 1]
            rgb[o + 2] = img.Pixels[i + 2]
            o += 3
            i += 4
        }
        let packed = zlibOf(rgb)
        add("\(page + 2) 0 obj\n<< /Type /XObject /Subtype /Image /Width \(img.Width) /Height \(img.Height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length \(packed.count) >>\nstream\n")
        out += packed
        add("\nendstream\nendobj\n")
        k += 1
    }
    for o in pdfTextFont(font) { object(o.n, body: o.body) }
    let xref = out.count
    add("xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n")
    for off in offsets {
        var text = "\(off)"
        while text.utf8.count < 10 { text = "0" + text }
        add("\(text) 00000 n \n")
    }
    add("trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n")
    return out
}
