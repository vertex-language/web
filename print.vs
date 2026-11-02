package web

import (
    "image/draw"
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
        let cuts = cutPages(found, total: contentHeight, page: contentH)
        var sheets: [draw.Image] = []
        let w = draw.RoundToInt(paper.Width * scale)
        let h = draw.RoundToInt(paper.Height * scale)
        var i = 0
        while i + 1 < cuts.count {
            let top = cuts[i]
            let bottom = cuts[i + 1]
            var pixels = [uint8](repeating: 255, count: int(w) * int(h) * 4)
            scroll = draw.Point(0, top)
            root?.ViewportScrollX = 0
            root?.ViewportScrollY = top
            size = draw.Size(contentW, bottom - top)
            needsRepaint = true
            Draw(into: &pixels, width: w, height: h, scale: scale, at: draw.Point(paper.Left, paper.Top))
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

    /// The page as a PDF, each sheet a picture on a page of its paper's size.
    public func PrintPDF(paper: PrintPaper = PrintPaper(), scale: float32 = 2) -> [uint8] {
        let sheets = Print(paper: paper, scale: scale)
        return pdfOf(sheets, widthPoints: float32(sheets.first?.Width ?? 0) / scale * 0.75, heightPoints: float32(sheets.first?.Height ?? 0) / scale * 0.75)
    }

    func collectBreaks(box: layout.Box, into out: inout PageBreaks) {
        let p = layout.PagePosition(box)
        let top = p.y + scroll.Y
        let s = box.Style
        if s.BreakInsideAvoid && box.Parent != nil { out.never.append((top, top + box.Height)) }
        if box.Kind == .replaced || box.Kind == .lineBreak { return }
        for l in box.Lines { out.may.append(top + l.Y) }
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
    func cutPages(found: PageBreaks, total: float32, page: float32) -> [float32] {
        var cuts: [float32] = [0]
        var at: float32 = 0
        let may = found.may.sorted()
        let must = found.must.sorted()
        var rounds = 0
        while at < total - 0.5 && rounds < 2000 {
            rounds += 1
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
        if cuts.count == 1 { cuts.append(page) }
        return cuts
    }
}

func forcesPageBreak(word: string) -> bool {
    return word == "page" || word == "always" || word == "left" || word == "right" || word == "recto" || word == "verso"
}

/// A PDF of pictures, a page each: uncompressed, and enough for any reader.
func pdfOf(sheets: [draw.Image], widthPoints: float32, heightPoints: float32) -> [uint8] {
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
    k = 0
    while k < sheets.count {
        let img = sheets[k]
        let page = 3 + k * 3
        object(page, body: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(widthPoints) \(heightPoints)] /Contents \(page + 1) 0 R /Resources << /XObject << /I \(page + 2) 0 R >> >> >>")
        let draws = "q \(widthPoints) 0 0 \(heightPoints) 0 0 cm /I Do Q"
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
        add("\(page + 2) 0 obj\n<< /Type /XObject /Subtype /Image /Width \(img.Width) /Height \(img.Height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length \(rgb.count) >>\nstream\n")
        out += rgb
        add("\nendstream\nendobj\n")
        k += 1
    }
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
