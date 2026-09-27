// The page checked headless: loading, painting, input, selection.
package main

import (
    "image/draw"
    "web"
    "web/fetch"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func pixelAt(_ pixels: [uint8], _ w: int32, _ x: int32, _ y: int32) -> draw.Color {
    let i = int((y * w + x) * 4)
    return draw.Color(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
}

func countDark(_ pixels: [uint8], _ w: int32, _ r: draw.IRect) -> int {
    var n = 0
    var y = r.Y
    while y < r.Bottom {
        var x = r.X
        while x < r.Right {
            let c = pixelAt(pixels, w, x, y)
            if int(c.R) + int(c.G) + int(c.B) < 300 { n += 1 }
            x += 1
        }
        y += 1
    }
    return n
}

@MainActor
func testTextFeatures() {
    print("Justify, visited links, @import")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.Configuration.Fetcher = fetch.Fetcher({ url in
        if url == "/site/extra.css" { return [uint8]("a:visited { color: rgb(1, 2, 3) } .imp { margin-left: 33px }".utf8) }
        return nil
    })
    view.IsVisited { url in url == "/site/seen.html" }
    view.LoadHTML("""
    <style>@import url("extra.css"); p { font: 16px Helvetica; text-align: justify; width: 200px; margin: 0 }</style>
    <base href="/site/">
    <p id=p>alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu</p>
    <div class=imp id=imp></div>
    <a id=seen href="seen.html">seen</a> <a id=new href="new.html">new</a>
    """, baseURL: "/elsewhere/")
    let p = view.BoxFor(view.QuerySelector("#p")!)!
    check(p.Lines.count >= 2, "the paragraph wraps (\(p.Lines.count) lines)")
    let first = p.Lines[0]
    var right: float32 = 0
    for f in first.Fragments { if f.X + f.Width > right { right = f.X + f.Width } }
    check(right > 199 && right < 201, "a justified line reaches the right edge (got \(right))")
    let last = p.Lines[p.Lines.count - 1]
    var lastRight: float32 = 0
    for f in last.Fragments { if f.X + f.Width > lastRight { lastRight = f.X + f.Width } }
    check(lastRight < 190, "the last line is not stretched (got \(lastRight))")
    let imp = view.BoxFor(view.QuerySelector("#imp")!)!
    check(imp.Margin.Left == 33, "an @import sheet resolved against <base href> applies (margin \(imp.Margin.Left))")
    let seen = view.BoxFor(view.QuerySelector("#seen")!)!
    let fresh = view.BoxFor(view.QuerySelector("#new")!)!
    check(seen.Style.Color == draw.Color(1, 2, 3), "a visited link takes :visited")
    check(fresh.Style.Color != draw.Color(1, 2, 3), "an unvisited link does not")
    check(view.NeedsAnimation() == false, "nothing animates without a focused field")
}

@MainActor
func testPageInput() {
    print("Page input")
    // A select takes the keyboard.
    let sv = web.Page()
    sv.SetViewportSize(draw.Size(300, 100))
    sv.LoadHTML("<select id=s name=s><option>Alpha</option><option>Beta</option><option value=g>Gamma</option></select>")
    let selectNode = sv.QuerySelector("#s")!
    sv.Focus(selectNode)
    _ = sv.Handle(.keyDown(web.Key(Key: "ArrowDown", Code: "ArrowDown")))
    check(sv.BoxFor(selectNode)!.Text == "Beta", "arrow down picks the next option (got \(sv.BoxFor(selectNode)!.Text))")
    _ = sv.Handle(.keyDown(web.Key(Key: "g", Code: "KeyG")))
    check(sv.BoxFor(selectNode)!.Text == "Gamma", "a letter jumps to the option starting with it")
    _ = sv.Handle(.keyDown(web.Key(Key: "Home", Code: "Home")))
    check(sv.BoxFor(selectNode)!.Text == "Alpha", "Home goes to the first option")

    // A sticky header follows the scroll within its container.
    let st = web.Page()
    st.SetViewportSize(draw.Size(300, 200))
    st.LoadHTML("<body style='margin:0'><div id=wrap style='height:600px'><div style='height:100px'></div><div id=h style='position:sticky;top:10px;height:20px'></div><div style='height:480px'></div></div><div style='height:1000px'></div></body>")
    var stPixels = [uint8](repeating: 0, count: 300 * 200 * 4)
    st.Draw(into: &stPixels, width: 300, height: 200, scale: 1)
    let hBox = st.BoxFor(st.QuerySelector("#h")!)!
    check(hBox.OffsetY == 0, "unscrolled, a sticky box sits where it was laid out")
    st.SetScrollOffset(draw.Point(0, 300))
    st.Draw(into: &stPixels, width: 300, height: 200, scale: 1)
    check(near(hBox.OffsetY, 210), "scrolled past it, it sticks 10px below the top (offset \(hBox.OffsetY))")
    st.SetScrollOffset(draw.Point(0, 590))
    st.Draw(into: &stPixels, width: 300, height: 200, scale: 1)
    check(near(hBox.OffsetY, 480), "it stops at its container's end (offset \(hBox.OffsetY))")
    st.SetScrollOffset(draw.Point(0, 0))
    st.Draw(into: &stPixels, width: 300, height: 200, scale: 1)
    check(hBox.OffsetY == 0, "and comes back when scrolled up")

    // Selecting text by dragging.
    let sel = web.Page()
    sel.SetViewportSize(draw.Size(400, 200))
    sel.LoadHTML("<body style='margin:0;font-size:16px;line-height:20px'><p id=p style='margin:0'>alpha beta gamma</p><p id=q style='margin:0'>delta</p></body>")
    let pBox = sel.BoxFor(sel.QuerySelector("#p")!)!
    let frag = pBox.Lines[0].Fragments[0]
    let face = pBox.Style.Face
    let startX = frag.X + face.Measure("alpha ") + 1
    let endX = frag.X + face.Measure("alpha beta") - 1
    _ = sel.Handle(.pointerDown(web.Pointer(draw.Point(startX, 10))))
    _ = sel.Handle(.pointerMoved(draw.Point(endX, 10)))
    _ = sel.Handle(.pointerUp(web.Pointer(draw.Point(endX, 10))))
    check(sel.SelectedText() == "beta", "dragging across a word selects it (got '\(sel.SelectedText())')")
    _ = sel.Handle(.pointerDown(web.Pointer(draw.Point(startX, 10))))
    _ = sel.Handle(.pointerMoved(draw.Point(20, 30)))
    _ = sel.Handle(.pointerUp(web.Pointer(draw.Point(20, 30))))
    check(sel.SelectedText().hasPrefix("beta gamma\nde"), "a selection across lines breaks the line (got '\(sel.SelectedText())')")
    var px3 = [uint8](repeating: 0, count: 400 * 200 * 4)
    sel.Draw(into: &px3, width: 400, height: 200, scale: 1)
    let hl = pixelAt(px3, 400, int32(frag.X + face.Measure("alpha beta")), 2)
    check(hl == draw.Color(179, 212, 252), "selected text is highlighted (got \(hl.R) \(hl.G) \(hl.B))")
    _ = sel.Handle(.pointerDown(web.Pointer(draw.Point(300, 150))))
    _ = sel.Handle(.pointerUp(web.Pointer(draw.Point(300, 150))))
    check(!sel.HasSelection, "clicking elsewhere clears the selection")
    sel.SelectAll()
    check(sel.SelectedText() == "alpha beta gamma\ndelta", "SelectAll takes the page's text (got '\(sel.SelectedText())')")

    // High-DPI: everything scales.
    let view2 = web.Page()
    view2.SetViewportSize(draw.Size(100, 100))
    view2.LoadHTML("<body style='margin:0'><div style='background:red;width:10px;height:10px'></div></body>")
    var px2 = [uint8](repeating: 0, count: 200 * 200 * 4)
    view2.Draw(into: &px2, width: 200, height: 200, scale: 2)
    check(pixelAt(px2, 200, 19, 19) == draw.Color(255, 0, 0) && pixelAt(px2, 200, 21, 21) == draw.Color.white, "at 2x a 10px box is 20 pixels")

    // Positioned boxes paint, whatever holds them, and opacity reaches
    // gradients.
    let view3 = web.Page()
    view3.SetViewportSize(draw.Size(200, 100))
    view3.LoadHTML("<body style='margin:0;font-size:16px'><style>.p:before{content:'';position:absolute;inset:0;background:linear-gradient(red,red)}.h:before{opacity:0}</style><div style='position:relative;height:20px'><div>x</div><i style='position:absolute;left:50px;top:0;width:10px;height:10px;background:red'></i></div><div style='position:relative;height:20px'>y<i style='position:absolute;left:50px;top:0;width:10px;height:10px;background:red'></i></div><div class=p style='position:relative;width:20px;height:20px'></div><div class='p h' style='position:relative;width:20px;height:20px'></div><div style='height:20px'><i style='position:absolute;left:150px;width:1px;height:1px'></i>zzzz</div></body>")
    var px3b = [uint8](repeating: 0, count: 200 * 100 * 4)
    view3.Draw(into: &px3b, width: 200, height: 100, scale: 1)
    let red = draw.Color(255, 0, 0)
    check(pixelAt(px3b, 200, 55, 5) == red, "a relative block paints the absolute box beside its blocks")
    check(pixelAt(px3b, 200, 55, 25) == red, "and the one after its text, at its left")
    check(pixelAt(px3b, 200, 10, 50) == red && pixelAt(px3b, 200, 10, 70) == draw.Color.white, "a ::before's gradient paints, and not at opacity 0")
    check(countDark(px3b, 200, draw.IRect(0, 80, 60, 20)) > 5, "text after a leading absolute box paints")
}

func near(_ a: float32, _ b: float32, _ tolerance: float32 = 0.5) -> bool {
    let d = a - b
    return d < tolerance && d > -tolerance
}

@MainActor
func testJournal() {
    print("The journal drives restyle")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.LoadHTML("""
    <style>body { margin: 0 } .base { width: 10px; height: 10px } .wide { width: 50px }
    #box { position: absolute; left: 100px; top: 100px; margin: 0; width: 20px; height: 20px }</style>
    <div id=a class=base></div><ul id=list></ul>
    <input type=checkbox id=box>
    """)
    var pixels = [uint8](repeating: 0, count: 300 * 200 * 4)
    let a = view.QuerySelector("#a")!
    check(view.BoxFor(a)!.Width == 10, "the element starts 10px wide")
    view.Draw(into: &pixels, width: 300, height: 200, scale: 1)
    check(!view.NeedsRepaint(), "a drawn page asks for nothing")

    let doc = view.Document!
    doc.ElementFor(a).ClassList.Add("wide")
    check(view.NeedsRepaint(), "a change through the document asks for a frame")
    check(view.BoxFor(a)!.Width == 50, "and restyles: a class added makes the element 50px wide")
    view.Draw(into: &pixels, width: 300, height: 200, scale: 1)

    doc.ElementFor(a).SetAttribute("class", "base wide")
    check(!view.NeedsRepaint(), "a change that changes nothing asks for no frame")
    doc.ElementFor(a).SetAttribute("data-note", "1")
    check(!view.NeedsRepaint(), "an attribute nothing reads asks for no frame")
    doc.ElementFor(a).ClassList.Add("unstyled")
    check(!view.NeedsRepaint(), "a class no rule names asks for no frame")
    doc.ElementFor(a).ClassList.Remove("wide")
    check(view.NeedsRepaint() && view.BoxFor(a)!.Width == 10, "a class a rule names still restyles")
    view.Draw(into: &pixels, width: 300, height: 200, scale: 1)

    let list = doc.ElementFor(view.QuerySelector("#list")!)
    let li = doc.CreateElement("li")
    list.AppendChild(li)
    doc.ElementFor(li).TextContent = "item"
    check(view.BoxFor(li) != nil, "an appended element gets a box")

    doc.ElementFor(li).Remove()
    check(view.BoxFor(li) == nil, "a removed element loses it")

    // The page's own changes go through the journal too.
    let box = view.QuerySelector("#box")!
    view.Draw(into: &pixels, width: 300, height: 200, scale: 1)
    _ = doc.TakeRecords()
    let p = draw.Point(110, 110)
    check(view.ElementAt(p)?.Id == box.Id, "the checkbox is where it was put")
    _ = view.Handle(.pointerDown(web.Pointer(p)))
    _ = view.Handle(.pointerUp(web.Pointer(p)))
    check(box.HasAttribute("checked"), "clicking a checkbox checks it")
    check(doc.HasMutations, "and records the change in the journal")
}

func main() -> int32 {
    testTextFeatures()
    testPageInput()
    testJournal()
    if failures == 0 {
        print("ALL PAGE CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
