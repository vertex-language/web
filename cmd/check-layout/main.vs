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

func check(ok: bool, what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func styleOf(source: string, sel: string) -> cascade.ComputedStyle? {
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
    func box(id: string) -> layout.Box? {
        guard let node = doc.ElementById(id) else { return nil }
        return builder.byNode[node.Id]
    }
    /// A box's border-box rect relative to the viewport.
    func rect(id: string) -> draw.Rect? {
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

func layoutOf(source: string, width: float32 = 800, height: float32 = 600, images: [string: draw.Image] = [:]) -> Laid? {
    let doc = html.Parse(source)
    let resolver = cascade.StyleResolver(ua: cascade.UserAgentRules())
    resolver.ViewportWidth = width
    resolver.ViewportHeight = height
    for style in doc.ElementsByTagName("style") {
        resolver.Author.Add(css.Parse(style.InnerText()))
    }
    let builder = layout.BoxTreeBuilder(resolver: resolver, context: selector.MatchContext.none)
    builder.Images = images
    guard let root = builder.Build(doc) else { return nil }
    let run = layout.Layout(viewportWidth: width, viewportHeight: height)
    run.Run(root)
    return Laid(doc: doc, root: root, builder: builder)
}

func near(a: float32, b: float32, tolerance: float32 = 0.5) -> bool {
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

    guard let fc = layoutOf("<body style='margin:0;font-size:16px'><div style='display:flex;flex-direction:column;width:100px'><div id=c style='flex:1'><p style='margin:0;height:40px'>x</p></div><div id=n style='height:10px'></div></div></body>") else { check(false, "layout"); return }
    check(fc.rect("c")!.Height == 40 && fc.rect("n")!.Y == 40, "a column item with flex: 1 keeps its content's height, min-height: auto (got \(fc.rect("c")!.Height))")

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

    guard let fx = layoutOf("<body style='margin:0'><table style='width:400px;border-spacing:0'><tr><td id=a style='width:100px;padding:0'>a</td><td id=b style='padding:0'>b</td></tr></table></body>") else { check(false, "layout"); return }
    check(near(fx.rect("a")!.Width, 100) && near(fx.rect("b")!.Width, 300), "room to spare goes to the column with no width (got \(fx.rect("a")!.Width) \(fx.rect("b")!.Width))")
    guard let fa = layoutOf("<body style='margin:0'><table style='width:400px;border-spacing:0'><tr><td id=a style='width:100px;padding:0'>a</td><td id=b style='width:100px;padding:0'>b</td></tr></table></body>") else { check(false, "layout"); return }
    check(near(fa.rect("a")!.Width, 200) && near(fa.rect("b")!.Width, 200), "and to every column where all have one (got \(fa.rect("a")!.Width) \(fa.rect("b")!.Width))")

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

func testTextAlignLast() {
    print("text-align-last")
    guard let l = layoutOf("<body style='margin:0;font:10px Helvetica'><p id=r style='margin:0;width:200px;text-align-last:right'>one</p><p id=j style='margin:0;width:200px;text-align:justify;text-align-last:justify'>a b</p><p id=c style='margin:0;width:60px;text-align:justify;text-align-last:center'>aaa bbb ccc ddd e</p><p id=d style='margin:0;width:200px;text-align:center'>x<br>y</p></body>") else { check(false, "layout"); return }
    func frags(id: string, line: int) -> [layout.Fragment] {
        let b = l.box(id)!
        return line < b.Lines.count ? b.Lines[line].Fragments : []
    }
    let r = frags("r", 0)
    check(r.count == 1 && near(r[0].X + r[0].Width, 200), "text-align-last: right aligns a one-line paragraph (got \(r[0].X) \(r[0].Width))")
    let j = frags("j", 0)
    let jl = j[j.count - 1]
    check(j[0].X == 0 && near(jl.X + jl.Width, 200), "text-align-last: justify spreads the last line (got \(jl.X + jl.Width))")
    let c = l.box("c")!
    let last = c.Lines[c.Lines.count - 1].Fragments
    let first = c.Lines[0].Fragments
    check(c.Lines.count > 1 && last[0].X > 5 && first[0].X == 0, "a justified paragraph's last line takes text-align-last: center (got \(last[0].X))")
    check(frags("d", 0)[0].X > 90, "auto keeps text-align for the line before a <br> (got \(frags("d", 0)[0].X))")
}

func testHyphens() {
    print("hyphens")
    guard let l = layoutOf("<body style='margin:0;font:20px Helvetica'><p id=s style='margin:0;width:120px'>super&shy;cali&shy;fragi&shy;listic</p><p id=n style='margin:0;width:120px;hyphens:none'>super&shy;cali&shy;fragi&shy;listic</p><p id=w style='margin:0;width:400px'>super&shy;cali</p></body>") else { check(false, "layout"); return }
    let s = l.box("s")!
    var widest: float32 = 0
    for line in s.Lines { for f in line.Fragments where f.X + f.Width > widest { widest = f.X + f.Width } }
    let first = s.Lines[0].Fragments[0]
    check(s.Lines.count >= 2 && widest <= 120.5, "a word breaks at its soft hyphens to fit (got \(s.Lines.count) lines, \(widest) wide)")
    check(first.Width > first.Owner.Style.Face.Measure("supercali") + 1, "the piece before the break shows a hyphen (got \(first.Width))")
    check(l.box("n")!.Lines.count == 1, "hyphens: none keeps the word whole (got \(l.box("n")!.Lines.count) lines)")
    let w = l.box("w")!.Lines[0].Fragments
    check(w.count == 1 && near(w[0].Width, w[0].Owner.Style.Face.Measure("supercali")), "an unbroken soft hyphen doesn't show (got \(w[0].Width))")
}

func testCaptionSide() {
    print("caption-side")
    guard let l = layoutOf("<body style='margin:0'><table id=t style='border-spacing:0'><caption id=top style='height:10px'></caption><caption id=bot style='caption-side:bottom;height:15px'></caption><tr><td id=c style='height:20px;padding:0'></td></tr></table></body>") else { check(false, "layout"); return }
    let top = l.rect("top")!
    let bot = l.rect("bot")!
    let c = l.rect("c")!
    check(top.Y == 0 && near(c.Y, 10) && near(bot.Y, 30), "caption-side: bottom puts a caption under the rows (got \(top.Y) \(c.Y) \(bot.Y))")
    check(near(l.rect("t")!.Height, 45), "and the table holds it (got \(l.rect("t")!.Height))")
}

func testCounters() {
    print("Counters and quotes")
    guard let l = layoutOf("""
    <style>
    body { margin: 0; counter-reset: sec } h2, h3, p, li { margin: 0; font-size: 10px }
    h2 { counter-reset: sub } h2::before { counter-increment: sec; content: counter(sec) ". " }
    h3::before { counter-increment: sub; content: counter(sec) "." counter(sub, lower-alpha) " " }
    ol.n { list-style: none } ol.n li::before { content: counters(list-item, ".") " " }
    .r::before { content: counter(r, upper-roman) } .r { counter-set: r 4 }
    #s { counter-reset: n 5 } .n6::before { counter-increment: n; content: counter(n) }
    .fr q { quotes: "«" "»" "‹" "›" }
    ol.m li::marker { content: counter(list-item) ") " }
    </style>
    <h2 id=h1>A</h2><h3 id=a1>x</h3><h3 id=a2>y</h3><h2 id=h2>B</h2><h3 id=b1>z</h3>
    <ol class=n><li id=i1>A<ol class=n><li id=i2>B</li><li id=i3>C</li></ol></li><li id=i4>D</li></ol>
    <p class=r id=r>!</p>
    <div id=s></div><p class=n6 id=n6>!</p>
    <p id=q>say <q>a <q>b</q> c</q></p><p class=fr id=fq><q>a <q>b</q></q></p>
    <ol class=m><li id=m1>x</li><li id=m2>y</li></ol>
    """) else { check(false, "layout"); return }
    func text(id: string) -> string {
        var out = ""
        // The first line, in the box or its first block.
        guard var b = l.box(id) else { return out }
        while b.Lines.isEmpty && !b.Children.isEmpty { b = b.Children[0] }
        if !b.Lines.isEmpty { for f in b.Lines[0].Fragments { out += f.Text } }
        return out
    }
    check(text("h1") == "1. A" && text("h2") == "2. B", "counter-increment on ::before numbers headings (got '\(text("h1"))' '\(text("h2"))')")
    check(text("a1") == "1.a x" && text("a2") == "1.b y" && text("b1") == "2.a z",
          "a counter reset by each heading numbers what follows it, in its style (got '\(text("a1"))' '\(text("a2"))' '\(text("b1"))')")
    check(text("i1") == "1 A" && text("i2") == "1.1 B" && text("i3") == "1.2 C" && text("i4") == "2 D",
          "counters() joins the nested list-item counters (got '\(text("i1"))' '\(text("i2"))' '\(text("i3"))' '\(text("i4"))')")
    check(text("r") == "IV!", "counter-set sets a counter (got '\(text("r"))')")
    check(text("n6") == "6!", "a counter reset on an element reaches its later siblings (got '\(text("n6"))')")
    check(text("q") == "say \u{201C}a \u{2018}b\u{2019} c\u{201D}", "<q> quotes, nested ones in the inner pair (got '\(text("q"))')")
    check(text("fq") == "«a ‹b›»", "quotes sets the pairs (got '\(text("fq"))')")
    check(l.box("m1")!.Marker == "1) " && l.box("m2")!.Marker == "2) ", "::marker content reads list-item (got '\(l.box("m1")!.Marker)' '\(l.box("m2")!.Marker)')")
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

    guard let cf = layoutOf("<body style='margin:0'><div style='display:grid;grid-auto-flow:column;grid-auto-columns:calc(50% - 5px);gap:10px;width:400px'><div id=c1 style='height:10px'></div><div id=c2 style='height:10px'></div><div id=c3 style='height:10px'></div></div></body>") else { check(false, "layout"); return }
    let c1 = cf.rect("c1")!
    let c2 = cf.rect("c2")!
    let c3 = cf.rect("c3")!
    check(c1.Y == c2.Y && c2.Y == c3.Y && near(c2.X, 205) && near(c3.X, 410) && near(c1.Width, 195), "grid-auto-flow: column puts items side by side in grid-auto-columns tracks (got \(c2.X) \(c3.X) \(c1.Width))")
    guard let cr = layoutOf("<body style='margin:0'><div style='display:grid;grid-auto-flow:column;grid-template-rows:10px 10px;width:400px'><div id=a></div><div id=b></div><div id=c></div></div></body>") else { check(false, "layout"); return }
    check(cr.rect("b")!.Y == 10 && cr.rect("b")!.X == cr.rect("a")!.X && cr.rect("c")!.Y == 0 && cr.rect("c")!.X > 0, "and fills each column's rows before the next column")

    guard let ar = layoutOf("<body style='margin:0;font-size:16px'><div id=r style='width:300px;aspect-ratio:2 / 3'></div><div id=t style='width:100px;aspect-ratio:4'><p style='margin:0;height:60px'>x</p></div><div id=p style='width:200px;aspect-ratio:1;position:relative'><div id=fill style='height:50%'></div></div><img id=i style='width:120px;aspect-ratio:16/9'></body>") else { check(false, "layout"); return }
    check(near(ar.rect("r")!.Height, 450), "aspect-ratio gives an auto height (got \(ar.rect("r")!.Height))")
    check(near(ar.rect("t")!.Height, 60), "content taller than the ratio keeps its height")
    check(near(ar.rect("fill")!.Height, 100), "the ratio's height is definite for percentages (got \(ar.rect("fill")!.Height))")
    check(near(ar.rect("i")!.Height, 67.5), "and it sizes a replaced element (got \(ar.rect("i")!.Height))")

    guard let gl = layoutOf("<body style='margin:0'><div style='display:grid;grid-template-columns:repeat(4,1fr);width:400px'><div id=w style='grid-column-end:span 4;height:5px'></div><div id=f style='grid-column:1 / -1;height:5px'></div><div id=s style='grid-column-start:2;grid-column-end:4;height:5px'></div><div id=e style='grid-column:1 / 3;height:5px'></div></div></body>") else { check(false, "layout"); return }
    check(near(gl.rect("w")!.Width, 400) && near(gl.rect("f")!.Width, 400), "grid-column-end: span and a -1 end line span the grid (got \(gl.rect("w")!.Width) \(gl.rect("f")!.Width))")
    check(near(gl.rect("s")!.X, 100) && near(gl.rect("s")!.Width, 200) && near(gl.rect("e")!.Width, 200), "start and end longhands, and 1 / 3 (got \(gl.rect("s")!.X) \(gl.rect("s")!.Width))")
    guard let ga = layoutOf("<body style='margin:0'><div style='display:grid;width:200px'><div id=bg style='grid-area:1/1;height:80px'></div><div id=fg style='grid-area:1/1;height:20px'></div></div></body>") else { check(false, "layout"); return }
    check(ga.rect("fg")!.Y == 0 && ga.rect("bg")!.Y == 0, "grid-area: 1/1 puts items in the same cell (got \(ga.rect("fg")!.Y))")
    guard let gp = layoutOf("<body style='margin:0'><div style='display:grid;grid-template-columns:1fr 1fr;width:200px'><div id=f style='height:100%;max-height:70px;position:relative'><div id=abs style='position:absolute;inset:0'></div></div><div style='height:100px'></div></div></body>") else { check(false, "layout"); return }
    check(gp.rect("f")!.Height == 70 && gp.rect("abs")!.Height == 70, "a grid item's percentage height is of its grid area, then clamped (got \(gp.rect("f")!.Height) \(gp.rect("abs")!.Height))")
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

    guard let il = layoutOf("<body style='margin:0;font-size:16px'><div id=p style='position:relative;width:200px'>one<i id=after style='position:absolute;left:50px;top:0;width:5px;height:5px'></i></div><div id=q style='position:relative;width:200px'><i id=first style='position:absolute;right:0;top:0;width:5px;height:5px'></i>two</div></body>") else { check(false, "layout"); return }
    check(il.rect("after")!.X == 50 && il.box("p")!.Lines.count == 1, "an absolute box after text takes its insets and no room in the line (got \(il.rect("after")!.X))")
    check(il.box("q")!.Lines.count == 1 && il.rect("first")!.X == 195, "one before the text leaves it inline content (got \(il.box("q")!.Lines.count) lines)")

    guard let r = layoutOf("<body style='margin:0'><div id=a style='height:10px'></div><div id=b style='position:relative;top:5px;left:8px;height:10px'></div><div id=c style='height:10px'></div></body>") else { check(false, "layout"); return }
    let b = r.box("b")!
    check(b.OffsetX == 8 && b.OffsetY == 5, "relative offsets are kept aside (got \(b.OffsetX) \(b.OffsetY))")
    check(r.rect("c")!.Y == 20, "relative positioning leaves the flow alone")

    guard let fr = layoutOf("<body style='margin:0'><div style='display:flex'><div id=fa style='position:relative;left:60px;width:80px;height:10px'></div><div id=fb style='width:80px;height:10px'></div></div></body>") else { check(false, "layout"); return }
    check(fr.box("fa")!.OffsetX == 60 && fr.rect("fb")!.X == 80, "a flex item is shifted by its relative insets, its place kept (got \(fr.box("fa")!.OffsetX))")
}

// MARK: - The view

// Images: a replaced element's width where nothing fixes it, as
// Chrome lays these out.
func testImages() {
    print("Images")
    let logo = draw.Image(width: 75, height: 24, pixels: [uint8](repeating: 0, count: 75 * 24 * 4))
    let images = ["logo.png": logo]
    // about.google's header: an image of height 32px and max-width 100%, in
    // a block, in a flex link whose width is a percentage of a flex item
    // sized by its content. Chrome: 132, 100 and 100x32.
    guard let l = layoutOf("""
        <body style='margin:0'><div style='display:flex'><div id=logo style='display:flex'>
        <a id=link style='display:flex;align-items:center;width:calc(100% - 8px);padding:0 12px 0 20px;height:48px'>
        <div id=custom><img id=im src=logo.png style='display:inline-block;max-width:100%;height:32px'></div></a></div></div></body>
        """, images: images) else { check(false, "layout"); return }
    check(l.rect("logo")!.Width == 132, "a flex item holding it is its width plus padding (got \(l.rect("logo")!.Width))")
    check(l.rect("custom")!.Width == 100, "its block is as wide as it (got \(l.rect("custom")!.Width))")
    let im = l.rect("im")!
    check(im.Width == 100 && im.Height == 32, "its width is its height times its ratio, not its max-width of nothing (got \(im.Width)x\(im.Height))")
    guard let b = layoutOf("<body style='margin:0'><img id=a src=logo.png style='display:block'><img id=b src=logo.png style='display:block'></body>", images: images) else { check(false, "layout"); return }
    check(b.rect("a")! == draw.Rect(0, 0, 75, 24) && b.rect("b")! == draw.Rect(0, 24, 75, 24),
          "display:block images stack, each a line of its own (got \(b.rect("b")!.X),\(b.rect("b")!.Y))")
}

func testControls() {
    print("Controls")
    guard let l = layoutOf("""
        <body style='margin:0'>
        <input id=plain style='display:block'>
        <input id=padded style='display:block;font:14px system-ui;padding:8px 10px;width:300px'>
        <input id=wide style='display:block;width:100%;padding:8px'>
        <img id=pic src=logo.png style='display:block;width:150px'>
        </body>
        """, images: ["logo.png": draw.Image(width: 75, height: 24, pixels: [uint8](repeating: 0, count: 75 * 24 * 4))]) else { check(false, "layout"); return }
    let plain = l.rect("plain")!
    check(near(plain.Height, 24, 1), "an input is a line of its font, with its padding and border: 24px by default (got \(plain.Height))")
    let padded = l.rect("padded")!
    check(padded.Height > 30, "padding makes it taller, not the text shorter (got \(padded.Height))")
    check(near(l.rect("wide")!.Height, plain.Height + 10, 1), "a width does not scale an input's height (got \(l.rect("wide")!.Height))")
    check(l.rect("pic")!.Height == 48, "while an image's width scales its height by its ratio")
}

func testColumns() {
    print("Multi-column")
    guard let l = layoutOf("""
    <body style='margin:0'>
    <div id=mc style='width:620px;column-count:3;column-gap:10px'>
    <div id=d0 style='height:50px'></div><div id=d1 style='height:50px'></div><div id=d2 style='height:50px'></div>
    <div id=d3 style='height:50px'></div><div id=d4 style='height:50px'></div><div id=d5 style='height:50px'></div>
    </div>
    <div id=after style='height:10px'></div>
    </body>
    """) else { check(false, "layout"); return }
    let d2 = l.rect("d2")!
    let d5 = l.rect("d5")!
    check(l.rect("d0")! == draw.Rect(0, 0, 200, 50) && l.rect("d1")!.Y == 50, "the first column takes the first blocks, at the column's width (got \(l.rect("d0")!))")
    check(d2 == draw.Rect(210, 0, 200, 50) && d5 == draw.Rect(420, 50, 200, 50), "the columns balance, the gap between them (got \(d2) \(d5))")
    check(l.rect("mc")!.Height == 100 && l.rect("after")!.Y == 100, "the box is as tall as its columns (got \(l.rect("mc")!.Height))")

    guard let w = layoutOf("<body style='margin:0;font-size:16px'><div id=mc style='width:620px;columns:150px'><div style='height:10px'></div></div></body>") else { check(false, "layout"); return }
    check(near(w.box("mc")!.ColumnWidthUsed, 196) && w.box("mc")!.ColumnGapUsed == 16, "column-width fits as many as it can, the gap normal 1em (got \(w.box("mc")!.ColumnWidthUsed))")

    guard let t = layoutOf("<body style='margin:0'><div style='width:400px;column-count:2;column-gap:20px;font-size:16px;line-height:20px'><p id=p style='margin:0'>one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty</p></div></body>") else { check(false, "layout"); return }
    let lines = t.box("p")!.Lines
    var inSecond = 0
    var maxBottom: float32 = 0
    for line in lines {
        if line.X >= 190 { inSecond += 1 }
        if line.Y + line.Height > maxBottom { maxBottom = line.Y + line.Height }
    }
    check(lines.count >= 2 && inSecond > 0 && inSecond <= (lines.count + 1) / 2, "a paragraph's lines run on into the next column (got \(inSecond) of \(lines.count))")
    check(near(maxBottom, float32((lines.count + 1) / 2) * 20), "and the columns share them evenly (got \(maxBottom))")

    guard let a = layoutOf("""
    <body style='margin:0'><div id=mc style='width:400px;column-count:2;column-gap:0'>
    <div style='height:60px'></div>
    <div id=mid style='break-inside:avoid'><div style='height:30px'></div><div style='height:30px'></div></div>
    <div style='height:60px'></div>
    </div></body>
    """) else { check(false, "layout"); return }
    check(a.rect("mid")!.Y == 60 && a.rect("mid")!.X == 0 && a.rect("mc")!.Height == 120, "break-inside: avoid keeps a block in one column (got \(a.rect("mid")!) \(a.rect("mc")!.Height))")

    guard let o = layoutOf("""
    <body style='margin:0'><div id=mc style='width:400px;height:100px;column-count:2;column-gap:0;column-fill:auto'>
    <div style='height:50px'></div><div style='height:50px'></div><div style='height:50px'></div><div style='height:50px'></div><div id=last style='height:50px'></div>
    </div></body>
    """) else { check(false, "layout"); return }
    check(o.rect("last")!.X == 400 && o.rect("last")!.Y == 0 && o.box("mc")!.ColumnsUsed == 3, "under a set height, content past the last column makes more (got \(o.rect("last")!))")

    guard let br = layoutOf("<body style='margin:0'><div style='width:400px;column-count:2;column-gap:0'><div style='height:50px'></div><div id=br style='break-before:column;height:20px'></div></div></body>") else { check(false, "layout"); return }
    check(br.rect("br")!.X == 200 && br.rect("br")!.Y == 0, "break-before: column starts the next column (got \(br.rect("br")!))")

    // Four lines in columns three lines tall: widows (2 by default)
    // brings a second line over; widows: 1 lets one go alone.
    func secondColumnLines(widows: string) -> int {
        guard let w = layoutOf("<body style='margin:0'><div style='width:200px;height:60px;column-count:2;column-gap:0;column-fill:auto;font-size:16px;line-height:20px'><p id=p style='margin:0;\(widows)'>a<br>b<br>c<br>d</p></div></body>") else { return -1 }
        var n = 0
        for line in w.box("p")!.Lines where line.X >= 100 { n += 1 }
        return n
    }
    check(secondColumnLines("") == 2 && secondColumnLines("widows:1") == 1,
          "widows keeps two lines together at the next column's top (got \(secondColumnLines("")) and \(secondColumnLines("widows:1")))")

    guard let spn = layoutOf("""
    <body style='margin:0'><div id=mc style='width:400px;column-count:2;column-gap:0'>
    <div id=a style='height:40px'></div><div id=b style='height:40px'></div>
    <div id=span style='column-span:all;height:10px'></div>
    <div id=c style='height:40px'></div><div id=d style='height:40px'></div>
    </div></body>
    """) else { check(false, "layout"); return }
    check(spn.rect("b")!.X == 200 && spn.rect("span")! == draw.Rect(0, 40, 400, 10), "column-span: all goes across, after the columns before it (got \(spn.rect("b")!) \(spn.rect("span")!))")
    check(spn.rect("c")! == draw.Rect(0, 50, 200, 40) && spn.rect("d")! == draw.Rect(200, 50, 200, 40) && spn.rect("mc")!.Height == 90,
          "and what follows starts a column set of its own (got \(spn.rect("c")!) \(spn.rect("d")!) \(spn.rect("mc")!.Height))")

    guard let dc = layoutOf("<body style='margin:0'><div style='width:400px;column-count:2;column-gap:0'><div id=dec style='border:2px solid;padding:0 4px'><div style='height:40px'></div><div style='height:40px'></div></div></div></body>") else { check(false, "layout"); return }
    let frags = dc.box("dec")!.ColumnFragments
    check(frags.count == 2 && frags[1].X == 200 && frags[0].Y == 0 && frags[1].Y < 10, "a block with a border splits into a fragment in each column (got \(frags))")

    guard let f = layoutOf("<body style='margin:0'><div id=mc style='float:left;column-count:2;column-gap:10px'><div style='width:100px;height:40px'></div><div style='width:100px;height:40px'></div></div></body>") else { check(false, "layout"); return }
    check(f.rect("mc")!.Width == 210 && f.rect("mc")!.Height == 40, "a shrink-to-fit box makes room for every column (got \(f.rect("mc")!))")
}

/// A box's line's fragments' texts, left to right.
func lineTexts(b: layout.Box, line: int) -> [string] {
    var frags = b.Lines[line].Fragments
    frags.sort { $0.X < $1.X }
    var out: [string] = []
    for f in frags where f.Kind == .text { out.append(f.Text) }
    return out
}

func testContainment() {
    print("Containment")
    guard let l = layoutOf("""
    <body style='margin:0'>
    <div id=size style='container-type:size;width:100px'><div style='height:50px'></div></div>
    <div id=inl style='container-type:inline-size;float:left'><div style='width:80px;height:30px'></div></div>
    <div id=plain style='float:left'><div style='width:80px;height:30px'></div></div>
    </body>
    """) else { check(false, "layout"); return }
    check(l.rect("size")!.Height == 0, "container-type: size doesn't take its content's height (got \(l.rect("size")!.Height))")
    check(l.rect("inl")!.Width == 0 && l.rect("inl")!.Height == 30, "inline-size takes no width from its content, but its height (got \(l.rect("inl")!))")
    check(l.rect("plain")!.Width == 80, "without containment a float fits its content")
}

func testRightToLeft() {
    print("Right to left")
    guard let l = layoutOf("""
    <body style='margin:0;font-size:16px'>
    <div dir=rtl style='width:400px'>
    <p id=en style='margin:0'>abc def</p>
    <p id=num style='margin:0'>אב 12</p>
    <p id=left style='margin:0;text-align:left'>אב</p>
    <div id=fixed style='width:100px;height:10px'></div>
    <div id=logical style='margin-inline-start:20px;height:10px'></div>
    <ul id=list style='margin:0'><li id=item>א</li></ul>
    <div style='display:flex'><div id=f1 style='width:50px;height:10px'></div><div id=f2 style='width:50px;height:10px;margin-left:10px'></div></div>
    <table style='border-spacing:0;width:400px'><tr><td id=c1 style='width:100px;padding:0'>א</td><td id=c2 style='padding:0'>ב</td></tr></table>
    </div>
    <p id=mixed style='margin:0'>ab אב גד cd</p>
    <p id=auto dir=auto style='margin:0;width:400px'>שלום</p>
    </body>
    """) else { check(false, "layout"); return }
    let en = l.box("en")!
    let enLine = en.Lines[0]
    let enEnd = enLine.Fragments[enLine.Fragments.count - 1]
    check(near(enEnd.X + enEnd.Width, 400, 1) && lineTexts(en, 0) == ["abc def"], "English in a right-to-left block is set at the right, in its own order (got \(enEnd.X + enEnd.Width) \(lineTexts(en, 0)))")
    guard let st = layoutOf("<body style='margin:0'><p id=p dir=rtl style='margin:0;width:400px'>אב 2026.</p></body>") else { check(false, "layout"); return }
    check(lineTexts(st.box("p")!, 0) == [".", "2026", " ", "אב"], "a full stop after a number at the end goes to the far left (got \(lineTexts(st.box("p")!, 0)))")
    check(lineTexts(l.box("num")!, 0) == ["12", " ", "אב"], "a number in Hebrew shows to its left, its digits in order (got \(lineTexts(l.box("num")!, 0)))")
    check(l.box("left")!.Lines[0].Fragments[0].X < 5, "text-align: left stays left right to left")
    check(lineTexts(l.box("mixed")!, 0) == ["ab ", "גד", " ", "אב", " cd"], "Hebrew words in English read right to left (got \(lineTexts(l.box("mixed")!, 0)))")
    check(l.rect("fixed")!.X == 300, "a fixed-width block sits at the right (got \(l.rect("fixed")!.X))")
    let logical = l.box("logical")!
    check(logical.Margin.Right == 20 && logical.Margin.Left == 0 && l.rect("logical")!.X == 0, "margin-inline-start is the right margin (got \(logical.Margin.Left) \(logical.Margin.Right))")
    check(l.box("list")!.Padding.Right == 40 && l.box("list")!.Padding.Left == 0, "a list is indented at the right (got \(l.box("list")!.Padding.Left) \(l.box("list")!.Padding.Right))")
    let item = l.box("item")!
    let marker = item.Lines[0].Fragments.first { $0.Kind == .marker }
    check(marker != nil && marker!.X >= item.InnerWidth, "and its marker is past the line's right end (got \(marker?.X ?? -1))")
    check(l.rect("f1")!.X == 350 && l.rect("f2")!.X == 300, "flex items run from the right, margins kept on their sides (got \(l.rect("f1")!.X) \(l.rect("f2")!.X))")
    check(near(l.rect("c1")!.Width, 100, 0.5) && near(l.rect("c1")!.X, 300, 0.5) && near(l.rect("c2")!.X, 0, 0.5), "a table's first column is at the right (got \(l.rect("c1")!) \(l.rect("c2")!) cell \(l.box("c1")!.X) row \(l.box("c1")!.Parent!.X) \(l.box("c1")!.Parent!.Width) up \(l.box("c1")!.Parent!.Parent!.X))")
    let auto = l.box("auto")!
    check(auto.Style.Direction == .rtl && near(auto.Lines[0].Fragments[0].X + auto.Lines[0].Fragments[0].Width, 400, 1), "dir=auto takes Hebrew's direction (got \(auto.Style.Direction))")

    guard let o = layoutOf("<body style='margin:0'><p id=o style='margin:0'><bdo dir=rtl>abc</bdo> <span style='unicode-bidi:bidi-override;direction:rtl'>xy</span></p></body>") else { check(false, "layout"); return }
    let reversed = o.box("o")!.Lines[0].Fragments.filter { $0.Text == "abc" }
    let shapedBack = reversed.count == 1 ? o.box("o")!.Style.Face.Shape("cba").Glyphs : []
    check(reversed.count == 1 && reversed[0].Run.Glyphs == shapedBack && reversed[0].RightToLeft, "bdo dir=rtl shows its letters reversed")

    // A click near a Hebrew word's right edge is at its start.
    let nb = l.box("num")!
    var hebrew: layout.Fragment? = nil
    for f in nb.Lines[0].Fragments where f.Text == "אב" { hebrew = f }
    if let h = hebrew {
        let r = l.rect("num")!
        let atRight = layout.HitTest(l.root, r.X + h.X + h.Width - 1, r.Y + h.Y + 4, originX: 0, originY: 0)
        let atLeft = layout.HitTest(l.root, r.X + h.X + 1, r.Y + h.Y + 4, originX: 0, originY: 0)
        check(h.RightToLeft && atRight?.TextOffset == h.Offset && atLeft?.TextOffset == h.Offset + 4,
              "a Hebrew word's first letter is at its right (got \(atRight?.TextOffset ?? -1) \(atLeft?.TextOffset ?? -1) from \(h.Offset))")
    } else {
        check(false, "the Hebrew word is on the line")
    }
}

func main() -> int32 {
    testBlockLayout()
    testImages()
    testControls()
    testInlineLayout()
    testFlexLayout()
    testFloats()
    testTables()
    testWrapping()
    testPseudoElements()
    testCounters()
    testCaptionSide()
    testTextAlignLast()
    testHyphens()
    testGrid()
    testPositioning()
    testColumns()
    testRightToLeft()
    testContainment()
    if failures == 0 {
        print("ALL LAYOUT CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
