// Layout checked: box geometry for block, inline, flex, grid, tables, floats and positioning.
package main

import (
    "image/draw"
    "web/cascade"
    "web/css"
    "web/css/selector"
    "web/html"
    "web/layout"
)

typealias Display = cascade.Display
typealias Length = css.Length

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func styleOf(_ source: string, _ sel: string) -> cascade.ComputedStyle? {
    let doc = html.Parse(source)
    let resolver = cascade.StyleResolver(ua: cascade.UserAgentRules())
    for style in doc.ElementsByTagName("style") {
        resolver.Author.Add(css.Parse(style.InnerText()))
    }
    guard let node = selector.QuerySelector(sel, in: doc.Root) else { return nil }
    // Resolve the chain from the root down, as the engine does.
    var chain: [html.Node] = []
    var cur: html.Node? = node
    while let n = cur {
        if n.Kind == html.NodeKind.element { chain.insert(n, at: 0) }
        cur = n.Parent
    }
    var parent: cascade.ComputedStyle? = nil
    for n in chain {
        parent = resolver.Resolve(n, parent: parent, context: selector.MatchContext.none)
    }
    return parent
}

final class Laid {
    let doc: html.Document
    let root: layout.Box
    let builder: layout.BoxTreeBuilder
    init(doc: html.Document, root: layout.Box, builder: layout.BoxTreeBuilder) {
        self.doc = doc
        self.root = root
        self.builder = builder
    }
    func box(_ id: string) -> layout.Box? {
        guard let node = doc.ElementById(id) else { return nil }
        return builder.byNode[node.Id]
    }
    /// A box's border-box rect relative to the viewport.
    func rect(_ id: string) -> draw.Rect? {
        guard let b = box(id) else { return nil }
        var x = b.X
        var y = b.Y
        var p = b.Parent
        while let parent = p {
            x += parent.X
            y += parent.Y
            p = parent.Parent
        }
        return draw.Rect(x, y, b.Width, b.Height)
    }
}

func layoutOf(_ source: string, width: float32 = 800, height: float32 = 600) -> Laid? {
    let doc = html.Parse(source)
    let resolver = cascade.StyleResolver(ua: cascade.UserAgentRules())
    resolver.ViewportWidth = width
    resolver.ViewportHeight = height
    for style in doc.ElementsByTagName("style") {
        resolver.Author.Add(css.Parse(style.InnerText()))
    }
    let builder = layout.BoxTreeBuilder(resolver: resolver, context: selector.MatchContext.none)
    guard let root = builder.Build(doc) else { return nil }
    let run = layout.Layout(viewportWidth: width, viewportHeight: height)
    run.Run(root)
    return Laid(doc: doc, root: root, builder: builder)
}

func near(_ a: float32, _ b: float32, _ tolerance: float32 = 0.5) -> bool {
    let d = a - b
    return d < tolerance && d > -tolerance
}

func testBlockLayout() {
    print("Block layout")
    guard let l = layoutOf("<body style='margin:0'><div id=a style='height:50px'></div><div id=b style='height:30px;margin:20px 0'></div><div id=c style='height:10px;margin-top:10px;width:50%'></div></body>") else { check(false, "layout"); return }
    let a = l.rect("a")!
    let b = l.rect("b")!
    let c = l.rect("c")!
    check(a == draw.Rect(0, 0, 800, 50), "the first block fills the width at the top (got \(a.X) \(a.Y) \(a.Width) \(a.Height))")
    check(b.Y == 70 && b.Height == 30, "a margin separates siblings (got y \(b.Y))")
    check(c.Y == 120, "adjacent margins collapse to the larger (got y \(c.Y))")
    check(c.Width == 400, "width: 50% of the containing block")
    let bodyBox = l.doc.ElementsByTagName("body")[0]
    let body = l.builder.byNode[bodyBox.Id]!
    check(near(body.Height, 130), "the body's height is its content's (got \(body.Height))")

    guard let m = layoutOf("<body style='margin:0'><div id=outer style='padding:10px;background:red'><p id=p style='margin:16px 0'>x</p></div><div id=next></div></body>") else { check(false, "layout"); return }
    let outer = m.rect("outer")!
    let p = m.rect("p")!
    check(p.Y == 26, "padding keeps a child's margin inside (got \(p.Y))")
    check(near(outer.Height, 20 + 32 + p.Height), "the parent's height holds the child's margins (got \(outer.Height))")

    guard let n = layoutOf("<body style='margin:0'><div id=outer><p id=p style='margin:16px 0'>x</p></div></body>") else { check(false, "layout"); return }
    let outer2 = n.rect("outer")!
    let p2 = n.rect("p")!
    check(outer2.Y == 16 && p2.Y == 16, "a first child's margin collapses through its parent (got \(outer2.Y) \(p2.Y))")

    guard let w = layoutOf("<body style='margin:0'><div id=a style='width:200px;margin:0 auto'></div><div id=b style='width:100px;padding:10px;border:5px solid;box-sizing:border-box'></div><div id=c style='width:100px;padding:10px;border:5px solid'></div><div id=d style='max-width:300px'></div><div id=e style='width:1000px;min-width:0'></div></body>") else { check(false, "layout"); return }
    check(w.rect("a")!.X == 300, "margin: auto centres (got x \(w.rect("a")!.X))")
    check(w.rect("b")!.Width == 100, "box-sizing: border-box keeps the width")
    check(w.rect("c")!.Width == 130, "content-box adds padding and border")
    check(w.rect("d")!.Width == 300, "max-width caps an auto width")
    check(w.rect("e")!.Width == 1000, "a wider box overflows rather than shrinks")
    guard let cw = layoutOf("<body style='margin:0'><div id=a style='width:calc(100% - 100px);height:10px'></div></body>") else { check(false, "layout"); return }
    check(cw.rect("a")!.Width == 700, "calc() resolves against the containing block in layout (got \(cw.rect("a")!.Width))")

    guard let h = layoutOf("<html style='height:100%'><body style='margin:0;height:100%'><div id=half style='height:50%'></div></body></html>", width: 800, height: 600) else { check(false, "layout"); return }
    check(h.rect("half")!.Height == 300, "percentage heights resolve against a definite chain (got \(h.rect("half")!.Height))")
}

func testInlineLayout() {
    print("Inline layout")
    guard let l = layoutOf("<body style='margin:0;font-size:16px;line-height:20px'><p id=p style='margin:0;width:200px'>one two three four five six seven eight nine ten eleven twelve</p></body>") else { check(false, "layout"); return }
    let p = l.box("p")!
    check(p.Lines.count > 2, "text wraps into several lines in 200px (got \(p.Lines.count))")
    check(p.Lines.count > 0 && near(p.Lines[0].Height, 20), "each line is the line-height tall (got \(p.Lines.count > 0 ? p.Lines[0].Height : -1))")
    check(near(p.Height, float32(p.Lines.count) * 20), "the paragraph is as tall as its lines")
    var allFit = true
    for line in p.Lines {
        for f in line.Fragments {
            if f.X + f.Width > 200.5 { allFit = false }
        }
    }
    check(allFit, "no line is wider than the paragraph")
    check(p.Lines.count > 1 && p.Lines[1].Fragments.count > 0 && p.Lines[1].Fragments[0].X == 0, "a later line starts at the left edge")

    guard let c = layoutOf("<body style='margin:0'><p id=p style='margin:0;width:400px;text-align:center'>hi</p><p id=r style='margin:0;width:400px;text-align:right'>hi</p></body>") else { check(false, "layout"); return }
    let cf = c.box("p")!.Lines[0].Fragments[0]
    check(near(cf.X + cf.Width / 2, 200, 1), "text-align: center centres the line (got \(cf.X + cf.Width / 2))")
    let rf = c.box("r")!.Lines[0].Fragments[0]
    check(near(rf.X + rf.Width, 400, 1), "text-align: right ends the line at the right edge")

    guard let s = layoutOf("<body style='margin:0;font-size:16px'><p id=p style='margin:0'>a <b>bold</b> <i>word</i> <span style='font-size:32px'>big</span> end</p></body>") else { check(false, "layout"); return }
    let sp = s.box("p")!
    check(sp.Lines.count == 1, "short mixed text is one line")
    let line = sp.Lines[0]
    var owners = 0
    for f in line.Fragments { if f.Owner.Node?.TagName == "b" || f.Owner.Node?.TagName == "i" { owners += 1 } }
    check(owners == 2, "inline elements own their text fragments (got \(owners))")
    check(line.Height > 30, "a bigger font makes the line taller (got \(line.Height))")
    var sameBaseline = true
    var baselineY: float32 = -1
    for f in line.Fragments {
        let b = f.Y + f.Ascent
        if baselineY < 0 { baselineY = b } else if !near(b, baselineY) { sameBaseline = false }
    }
    check(sameBaseline, "all fragments share the baseline")
    check(line.Spans.count == 3, "each inline element gets a span on the line (got \(line.Spans.count))")

    guard let w = layoutOf("<body style='margin:0'><p id=p style='margin:0;width:100px;white-space:nowrap'>one two three four five</p><pre id=pre style='margin:0'>a  b\nc</pre></body>") else { check(false, "layout"); return }
    check(w.box("p")!.Lines.count == 1, "nowrap keeps one line")
    check(w.box("pre")!.Lines.count == 2, "pre breaks at newlines (got \(w.box("pre")!.Lines.count))")
    let preLine = w.box("pre")!.Lines[0]
    check(preLine.Fragments.count == 1 && preLine.Fragments[0].Text == "a  b", "pre keeps its spaces (got \(preLine.Fragments.count) fragments)")

    guard let br = layoutOf("<body style='margin:0'><p id=p style='margin:0'>a<br>b<br><br>c</p></body>") else { check(false, "layout"); return }
    check(br.box("p")!.Lines.count == 4, "br breaks lines, an empty one too (got \(br.box("p")!.Lines.count))")

    guard let ib = layoutOf("<body style='margin:0'><p id=p style='margin:0'>x <span id=ib style='display:inline-block;width:50px;height:40px'></span> y <img id=img width=20 height=10></p></body>") else { check(false, "layout"); return }
    let ibr = ib.rect("ib")!
    check(ibr.Width == 50 && ibr.Height == 40, "an inline-block takes its width and height")
    let pl = ib.box("p")!.Lines[0]
    check(pl.Height >= 40, "the line grows to hold the inline-block (got \(pl.Height))")
    check(near(ibr.Y + 40, pl.Y + pl.Baseline), "an empty inline-block sits on the baseline (bottom \(ibr.Y + 40) baseline \(pl.Y + pl.Baseline))")
    check(ib.rect("img")!.Width == 20 && ib.rect("img")!.Height == 10, "an image takes its attributes' size")

    guard let li = layoutOf("<body style='margin:0'><ul id=ul><li id=a>one</li><li id=b>two</li></ul><ol><li id=c>x</li><li id=d>y</li></ol></body>") else { check(false, "layout"); return }
    check(li.box("a")!.Marker == "•" && li.box("c")!.Marker == "1." && li.box("d")!.Marker == "2.", "list markers count (got \(li.box("d")!.Marker))")
    check(li.rect("a")!.X == 40, "the ul's padding indents the items (got \(li.rect("a")!.X))")
    let firstLine = li.box("a")!.Lines[0]
    check(firstLine.Fragments.count == 2 && firstLine.Fragments[0].Kind == .marker && firstLine.Fragments[0].X < 0, "the marker sits outside the item's first line")

    guard let e = layoutOf("<body style='margin:0'><div id=e></div><p id=blank>   </p></body>") else { check(false, "layout"); return }
    check(e.rect("e")!.Height == 0 && e.rect("blank")!.Height == 0, "empty and blank blocks have no height")
}

func testFlexLayout() {
    print("Flex layout")
    guard let l = layoutOf("<body style='margin:0'><div id=f style='display:flex;width:600px;height:100px'><div id=a style='flex:1'></div><div id=b style='flex:2'></div><div id=c style='width:100px'></div></div></body>") else { check(false, "layout"); return }
    let a = l.rect("a")!
    let b = l.rect("b")!
    let c = l.rect("c")!
    check(near(a.Width, 166.67, 0.1) && near(b.Width, 333.33, 0.1) && c.Width == 100, "flex grows into the free space by factor (got \(a.Width) \(b.Width) \(c.Width))")
    check(a.X == 0 && near(b.X, 166.67, 0.1) && near(c.X, 500, 0.1), "items sit side by side")
    check(a.Height == 100, "align-items: stretch fills the height")

    guard let j = layoutOf("<body style='margin:0'><div style='display:flex;width:600px;justify-content:space-between;align-items:center;height:100px'><div id=a style='width:100px;height:20px'></div><div id=b style='width:100px;height:40px'></div></div></body>") else { check(false, "layout"); return }
    check(j.rect("a")!.X == 0 && j.rect("b")!.X == 500, "justify-content: space-between")
    check(j.rect("a")!.Y == 40 && j.rect("b")!.Y == 30, "align-items: center (got \(j.rect("a")!.Y) \(j.rect("b")!.Y))")

    guard let col = layoutOf("<body style='margin:0'><div id=col style='display:flex;flex-direction:column;gap:10px;width:200px'><div id=a style='height:20px'></div><div id=b style='height:30px'></div></div></body>") else { check(false, "layout"); return }
    check(col.rect("b")!.Y == 30 && col.rect("col")!.Height == 60, "a column stacks with gaps and takes their height (got \(col.rect("b")!.Y) \(col.rect("col")!.Height))")
    check(col.rect("a")!.Width == 200, "column items stretch across")

    guard let wr = layoutOf("<body style='margin:0'><div id=w style='display:flex;flex-wrap:wrap;width:250px'><div id=a style='width:100px;height:10px'></div><div id=b style='width:100px;height:10px'></div><div id=c style='width:100px;height:10px'></div></div></body>") else { check(false, "layout"); return }
    check(wr.rect("c")!.Y == 10 && wr.rect("c")!.X == 0 && wr.rect("w")!.Height == 20, "flex-wrap wraps onto a second line")

    guard let sh = layoutOf("<body style='margin:0'><div style='display:flex;width:300px'><div id=a style='width:200px'></div><div id=b style='width:200px'></div></div></body>") else { check(false, "layout"); return }
    check(sh.rect("a")!.Width == 150 && sh.rect("b")!.Width == 150, "items shrink to fit (got \(sh.rect("a")!.Width))")

    guard let tx = layoutOf("<body style='margin:0'><div style='display:flex;width:400px'><div id=a>short</div><div id=b style='flex:1'>grows</div></div></body>") else { check(false, "layout"); return }
    let ta = tx.rect("a")!
    check(ta.Width > 20 && ta.Width < 60 && near(tx.rect("b")!.Width, 400 - ta.Width), "an item without flex takes its content width (got \(ta.Width))")

    guard let fl = layoutOf("<body style='margin:0'><div style='width:600px'><div id=f style='float:right;display:flex'><div id=a style='width:100px;height:10px'></div><div id=b style='float:right;width:50px;height:10px'></div></div></div></body>") else { check(false, "layout"); return }
    check(fl.rect("f")!.Width == 150 && fl.rect("b")!.X == 550, "a float inside a flex container is an item like the others (got \(fl.rect("f")!.Width) \(fl.rect("b")!.X))")

    guard let sv = layoutOf("<body style='margin:0'><div style='width:40px;padding:8px;box-sizing:border-box'><svg id=s viewBox='0 0 24 12'></svg></div><div style='width:500px'><svg id=t viewBox='0 0 10 10' width=20></svg></div></body>") else { check(false, "layout"); return }
    check(sv.rect("s")!.Width == 24 && sv.rect("s")!.Height == 12, "an svg with only a viewBox takes the room it has, at its ratio (got \(sv.rect("s")!.Width)x\(sv.rect("s")!.Height))")
    check(sv.rect("t")!.Width == 20 && sv.rect("t")!.Height == 20, "and one with a width keeps it")
}

func testFloats() {
    print("Floats")
    guard let l = layoutOf("<body style='margin:0;font-size:16px;line-height:20px'><div id=f style='float:left;width:100px;height:50px'></div><div id=g style='float:right;width:80px;height:30px'></div><p id=p style='margin:0;width:400px'>one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty</p><div id=c style='clear:both;height:10px'></div></body>", width: 400) else { check(false, "layout"); return }
    let f = l.rect("f")!
    let g = l.rect("g")!
    check(f.X == 0 && f.Y == 0, "a left float sits at the left")
    check(g.X == 320 && g.Y == 0, "a right float sits at the right (got \(g.X) \(g.Y))")
    let p = l.box("p")!
    check(l.rect("p")!.Y == 0, "the paragraph starts where the floats do: floats take no flow height")
    let first = p.Lines[0]
    check(first.X == 100 && near(first.Width, 220), "the first line runs between the floats (x \(first.X) width \(first.Width))")
    var afterRight: Line? = nil
    var afterLeft: Line? = nil
    for line in p.Lines {
        if line.Y >= 30 && line.Y < 50 && afterRight == nil { afterRight = line }
        if line.Y >= 50 && afterLeft == nil { afterLeft = line }
    }
    let afterRightWidth: float32 = afterRight != nil ? afterRight!.Width : -1
    check(afterRight != nil && afterRight!.X == 100 && near(afterRightWidth, 300), "below the right float lines widen (got \(afterRightWidth))")
    check(afterLeft != nil && afterLeft!.X == 0 && near(afterLeft!.Width, 400), "below both floats lines take the full width")
    check(l.rect("c")!.Y >= 50, "clear: both moves below the floats (got \(l.rect("c")!.Y))")

    guard let s = layoutOf("<body style='margin:0'><div id=wrap style='overflow:hidden'><div id=a style='float:left;width:50px;height:40px'></div></div><div id=next style='height:5px'></div></body>") else { check(false, "layout"); return }
    check(s.rect("wrap")!.Height == 40, "a formatting root grows to hold its floats (got \(s.rect("wrap")!.Height))")
    check(s.rect("next")!.Y == 40, "and the next block comes after it")

    guard let i = layoutOf("<body style='margin:0;line-height:20px;width:300px'><p id=p style='margin:0'>text before <img id=img style='float:right;width:60px;height:30px'> and text after the image that keeps going and going and going for a while</p></body>", width: 300) else { check(false, "layout"); return }
    let img = i.rect("img")!
    check(img.X == 240 && img.Y == 0, "a float in text goes to the side at the top of its line (got \(img.X) \(img.Y))")
    let pl = i.box("p")!.Lines
    check(pl.count > 1 && near(pl[0].Width, 240) && pl[pl.count - 1].Width == 300, "lines beside the image are narrower, later ones full (got \(pl[0].Width) then \(pl[pl.count - 1].Width))")

    guard let two = layoutOf("<body style='margin:0'><div id=a style='float:left;width:100px;height:20px'></div><div id=b style='float:left;width:100px;height:20px'></div><div id=c style='float:left;width:100px;height:20px'></div></body>", width: 250) else { check(false, "layout"); return }
    check(two.rect("b")!.X == 100 && two.rect("c")!.X == 0 && two.rect("c")!.Y == 20, "floats line up and wrap when they do not fit (c at \(two.rect("c")!.X) \(two.rect("c")!.Y))")
}

func testTables() {
    print("Tables")
    guard let l = layoutOf("<body style='margin:0'><table id=t style='border-spacing:0'><tr><td id=a style='width:100px;height:20px;padding:0'>a</td><td id=b style='padding:0'>bb</td></tr><tr id=r2><td id=c style='padding:0'>c</td><td id=d style='padding:0;height:40px'>d</td></tr></table></body>") else { check(false, "layout"); return }
    let a = l.rect("a")!
    let b = l.rect("b")!
    let c = l.rect("c")!
    let d = l.rect("d")!
    check(a.X == 0 && b.X == 100, "cells sit side by side in their columns (b at \(b.X))")
    check(c.X == 0 && c.Width == 100, "a column is as wide as its widest cell (got \(c.Width))")
    check(c.Y == a.Height && c.Height == 40 && d.Height == 40, "a row is as tall as its tallest cell and cells stretch (c \(c.Y) \(c.Height))")
    check(b.Width > 10 && b.Width < 40, "an auto column fits its content (got \(b.Width))")
    let t = l.rect("t")!
    check(near(t.Width, 100 + b.Width) && near(t.Height, a.Height + 40), "the table shrinks to its columns and rows (got \(t.Width) x \(t.Height))")

    guard let w = layoutOf("<body style='margin:0'><table id=t style='width:400px;border-spacing:0'><tr><td id=a style='padding:0'>x</td><td id=b style='padding:0'>y</td></tr></table></body>") else { check(false, "layout"); return }
    check(w.rect("t")!.Width == 400 && near(w.rect("a")!.Width + w.rect("b")!.Width, 400), "a given width is shared by the columns (got \(w.rect("a")!.Width) + \(w.rect("b")!.Width))")

    guard let sp = layoutOf("<body style='margin:0'><table id=t style='border-spacing:4px'><tr><td id=a style='padding:0;width:50px;height:10px'></td><td id=b style='padding:0;width:50px'></td></tr></table></body>") else { check(false, "layout"); return }
    check(sp.rect("a")!.X == 4 && sp.rect("b")!.X == 58 && sp.rect("t")!.Width == 112, "border-spacing goes between and around cells (got \(sp.rect("a")!.X) \(sp.rect("b")!.X) \(sp.rect("t")!.Width))")

    guard let cs = layoutOf("<body style='margin:0'><table style='border-spacing:0'><tr><td id=wide colspan=2 style='padding:0'>wide</td></tr><tr><td id=a style='padding:0;width:60px'>a</td><td id=b style='padding:0;width:70px'>b</td></tr></table></body>") else { check(false, "layout"); return }
    check(cs.rect("wide")!.Width == 130, "a colspan cell spans its columns (got \(cs.rect("wide")!.Width))")

    guard let va = layoutOf("<body style='margin:0;line-height:20px'><table style='border-spacing:0'><tr><td id=tall style='padding:0;height:60px'></td><td id=mid style='padding:0;vertical-align:middle'>m</td><td id=top style='padding:0;vertical-align:top'>t</td></tr></table></body>") else { check(false, "layout"); return }
    let midLine = va.box("mid")!.Lines[0]
    let topLine = va.box("top")!.Lines[0]
    check(near(midLine.Y, 20) && topLine.Y == 0, "vertical-align middle centres a cell's content (got \(midLine.Y) and \(topLine.Y))")

    guard let tb = layoutOf("<body style='margin:0'><table id=t style='border-spacing:0'><thead id=h><tr><th id=th style='padding:0'>Head</th></tr></thead><tbody id=body><tr><td id=td style='padding:0'>cell</td></tr></tbody></table><p id=after style='margin:0'>x</p></body>") else { check(false, "layout"); return }
    check(tb.rect("td")!.Y == tb.rect("th")!.Height && tb.rect("body")!.Y == tb.rect("th")!.Height, "row groups stack (td at \(tb.rect("td")!.Y), tbody at \(tb.rect("body")!.Y))")
    check(tb.rect("after")!.Y == tb.rect("t")!.Height, "the table takes its rows' height in the flow")
    check(tb.box("th")!.Style.FontWeight == 700 && tb.box("th")!.Style.TextAlign == .center, "th is bold and centred by default")
}

func testWrapping() {
    print("Wrapping")
    let long = "averyveryveryveryveryverylongwordthatdoesnotfitonaline"
    guard let l = layoutOf("<body style='margin:0;font-size:16px'><p id=a style='margin:0;width:100px'>\(long) end</p><p id=b style='margin:0;width:100px;overflow-wrap:break-word'>\(long) end</p><p id=c style='margin:0;width:100px;word-break:break-all'>short words \(long)</p></body>") else { check(false, "layout"); return }
    let a = l.box("a")!
    check(a.Lines.count == 2 && a.Lines[0].Fragments[0].Width > 100, "a long word overflows by default (\(a.Lines.count) lines)")
    let b = l.box("b")!
    var widest: float32 = 0
    var pieces = 0
    for line in b.Lines {
        for f in line.Fragments {
            if f.X + f.Width > widest { widest = f.X + f.Width }
            pieces += 1
        }
    }
    check(b.Lines.count > 2 && widest <= 100.5, "overflow-wrap: break-word breaks the word across lines (\(b.Lines.count) lines, widest \(widest))")
    var joined = ""
    for line in b.Lines {
        for f in line.Fragments { joined += f.Text }
    }
    check(joined == long + " end" || joined == long + "end", "the pieces spell the word (got \(joined))")
    let c = l.box("c")!
    check(c.Lines.count > 2, "word-break: break-all breaks anywhere (\(c.Lines.count) lines)")

    guard let e = layoutOf("<body style='margin:0;font-size:16px'><p id=p style='margin:0;width:120px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis'>This sentence is far too long for the box</p></body>") else { check(false, "layout"); return }
    let line = e.box("p")!.Lines[0]
    let last = line.Fragments[line.Fragments.count - 1]
    check(last.Text.hasSuffix("…") && last.X + last.Width <= 120.5, "text-overflow: ellipsis cuts the line with an ellipsis (got \(last.Text))")
}

func testPseudoElements() {
    print("Pseudo-elements")
    guard let l = layoutOf("<style>p::before { content: '> '; color: red } a::after { content: ' (' attr(href) ')' } .clear::after { content: ''; display: block; clear: both; height: 5px }</style><body style='margin:0'><p id=p style='margin:0'>text</p><p id=q style='margin:0'><a href='x.html'>link</a></p><div class=clear id=c><div style='float:left;width:20px;height:30px'></div></div><div id=after></div></body>") else { check(false, "layout"); return }
    let p = l.box("p")!
    var joined = ""
    for f in p.Lines[0].Fragments { joined += f.Text }
    check(joined == "> text", "::before puts its content first (got '\(joined)')")
    check(p.Lines[0].Fragments[0].Owner.Style.Color == draw.Color(255, 0, 0), "the pseudo-element has its own style")
    let q = l.box("q")!
    joined = ""
    for f in q.Lines[0].Fragments { joined += f.Text }
    check(joined == "> link (x.html)", "::after with attr() reads the element's attribute (got '\(joined)')")
    check(l.rect("c")!.Height == 35 && l.rect("after")!.Y == l.rect("c")!.Y + 35, "a clearing ::after block contains the float (got \(l.rect("c")!.Height))")
}

func testGrid() {
    print("Grid")
    guard let l = layoutOf("<body style='margin:0'><div id=g style='display:grid;grid-template-columns:100px 1fr 2fr;gap:10px;width:600px'><div id=a style='height:20px'></div><div id=b style='height:30px'></div><div id=c></div><div id=d style='height:15px'></div></div></body>") else { check(false, "layout"); return }
    let a = l.rect("a")!
    let b = l.rect("b")!
    let c = l.rect("c")!
    let d = l.rect("d")!
    check(a.Width == 100 && near(b.Width, 160) && near(c.Width, 320), "columns take their lengths and fr shares (got \(a.Width) \(b.Width) \(c.Width))")
    check(a.X == 0 && near(b.X, 110) && near(c.X, 280), "columns are placed with the gap")
    check(near(a.Height, 20) && near(c.Height, 30), "auto-height items stretch to the row's height (got \(a.Height) \(c.Height))")
    check(d.X == 0 && near(d.Y, 40), "the fourth item wraps to the next row after the gap (got \(d.X) \(d.Y))")
    check(near(l.rect("g")!.Height, 55), "the grid is as tall as its rows and gaps (got \(l.rect("g")!.Height))")

    guard let sp = layoutOf("<body style='margin:0'><div style='display:grid;grid-template-columns:repeat(3, 1fr);width:300px'><div id=wide style='grid-column:span 2;height:10px'></div><div id=one style='height:10px'></div><div id=two style='grid-column:2 / 4;height:10px'></div></div></body>") else { check(false, "layout"); return }
    check(sp.rect("wide")!.Width == 200 && sp.rect("one")!.X == 200, "span 2 covers two columns and the next item follows")
    check(sp.rect("two")!.X == 100 && sp.rect("two")!.Width == 200 && sp.rect("two")!.Y == 10, "grid-column with lines places on the next row")

    guard let af = layoutOf("<body style='margin:0'><div style='display:grid;grid-template-columns:repeat(auto-fill, minmax(120px, 1fr));gap:20px;width:440px'><div id=a1 style='height:10px'></div><div id=a2 style='height:10px'></div><div id=a3 style='height:10px'></div><div id=a4 style='height:10px'></div></div></body>") else { check(false, "layout"); return }
    check(near(af.rect("a1")!.Width, 133.33, 0.1) && af.rect("a4")!.Y == 30, "auto-fill makes as many columns as fit (got width \(af.rect("a1")!.Width), a4 at y \(af.rect("a4")!.Y))")

    guard let au = layoutOf("<body style='margin:0;font-size:16px'><div style='display:grid;grid-template-columns:auto 1fr;width:400px'><div id=k style='white-space:nowrap'>label</div><div id=v style='height:10px'></div></div></body>") else { check(false, "layout"); return }
    let k = au.rect("k")!
    check(k.Width > 20 && k.Width < 60 && near(au.rect("v")!.X, k.Width) && near(au.rect("v")!.Width, 400 - k.Width), "an auto column fits its content and fr takes the rest (got \(k.Width))")

    let longText = "words that would run far wider than the grid if nothing wrapped them at all, on and on"
    guard let one = layoutOf("<body style='margin:0;font-size:16px'><div style='display:grid;width:200px'><p id=t style='margin:0'>\(longText)</p></div></body>") else { check(false, "layout"); return }
    check(near(one.rect("t")!.Width, 200) && one.rect("t")!.Height > 30, "one implicit auto column is the grid's width, and its text wraps (got \(one.rect("t")!.Width))")
    guard let two = layoutOf("<body style='margin:0;font-size:16px'><div style='display:grid;grid-template-columns:auto auto;width:300px'><div id=s>short</div><div id=l>\(longText)</div></div></body>") else { check(false, "layout"); return }
    let sw = two.rect("s")!.Width
    let lw = two.rect("l")!.Width
    check(near(sw + lw, 300, 1) && sw < 150, "two auto columns share the width, the short one keeping to its content (got \(sw) \(lw))")
    guard let ac = layoutOf("<body style='margin:0'><div id=acc style='display:grid;grid-template-rows:0fr'><div id=panel style='overflow:hidden'><p style='margin:0;height:50px'>hidden</p></div></div><div id=after style='height:5px'></div></body>") else { check(false, "layout"); return }
    check(ac.rect("panel")!.Height == 0 && ac.rect("after")!.Y == 0, "a 0fr row holding an item that clips collapses to nothing (got \(ac.rect("panel")!.Height))")
    guard let open = layoutOf("<body style='margin:0'><div style='display:grid;grid-template-rows:1fr'><div id=panel style='overflow:hidden'><p style='margin:0;height:50px'>shown</p></div></div></body>") else { check(false, "layout"); return }
    check(open.rect("panel")!.Height == 50, "and a 1fr row holds it whole")
}

func testPositioning() {
    print("Positioning")
    guard let l = layoutOf("<body style='margin:0'><div id=rel style='position:relative;width:300px;height:200px;margin-left:50px'><div id=abs style='position:absolute;top:10px;right:20px;width:100px;height:30px'></div><div id=full style='position:absolute;left:0;right:0;bottom:0;height:10px'></div></div><div id=fixed style='position:fixed;left:5px;top:6px;width:7px;height:8px'></div></body>") else { check(false, "layout"); return }
    let abs = l.rect("abs")!
    check(abs.X == 230 && abs.Y == 10, "absolute against the positioned ancestor's insets (got \(abs.X) \(abs.Y))")
    let full = l.rect("full")!
    check(full.Width == 300 && full.Y == 190, "left and right both set stretch the box (got \(full.Width) \(full.Y))")
    let fixed = l.rect("fixed")!
    check(fixed.X == 5 && fixed.Y == 6, "fixed against the viewport")
    let rel = l.box("rel")!
    check(rel.Positioned.count == 2, "the positioned ancestor keeps its positioned boxes")

    guard let r = layoutOf("<body style='margin:0'><div id=a style='height:10px'></div><div id=b style='position:relative;top:5px;left:8px;height:10px'></div><div id=c style='height:10px'></div></body>") else { check(false, "layout"); return }
    let b = r.box("b")!
    check(b.OffsetX == 8 && b.OffsetY == 5, "relative offsets are kept aside (got \(b.OffsetX) \(b.OffsetY))")
    check(r.rect("c")!.Y == 20, "relative positioning leaves the flow alone")
}

// MARK: - The view

func main() -> int32 {
    testBlockLayout()
    testInlineLayout()
    testFlexLayout()
    testFloats()
    testTables()
    testWrapping()
    testPseudoElements()
    testGrid()
    testPositioning()
    if failures == 0 {
        print("ALL LAYOUT CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
