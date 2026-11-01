// The page checked headless: loading, painting, input, selection.
package main

import (
    "image"
    "image/draw"
    "image/png"
    "web"
    "web/dom"
    "web/html"
    "web/layout"
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

    // Stacking: an absolute background under a z-index: 1 relative
    // box after it in the flow; without z-index, tree order.
    let view5 = web.Page()
    view5.SetViewportSize(draw.Size(100, 100))
    view5.LoadHTML("<body style='margin:0'><div style='position:relative;height:40px'><div style='position:absolute;inset:0;background:red'></div><div style='position:relative;z-index:1;height:40px;background:lime'></div></div><div style='position:relative;height:40px'><div style='position:relative;height:40px;background:lime'></div><div style='position:absolute;inset:0;background:blue'></div></div></body>")
    var px5 = [uint8](repeating: 0, count: 100 * 100 * 4)
    view5.Draw(into: &px5, width: 100, height: 100, scale: 1)
    check(pixelAt(px5, 100, 10, 10) == draw.Color(0, 255, 0), "a z-index: 1 relative box paints over an earlier absolute one")
    check(pixelAt(px5, 100, 10, 50) == draw.Color(0, 0, 255), "and without z-index a later absolute box paints over a relative one")

    // ::placeholder: the UA's grey, an author's color, or hidden.
    let view4 = web.Page()
    view4.SetViewportSize(draw.Size(200, 100))
    view4.LoadHTML("<body style='margin:0'><style>.r::placeholder{color:red}.h::placeholder{opacity:0}</style><input placeholder='MMMMMM' style='display:block;border:0;padding:0;height:20px;font-size:16px'><input class=r placeholder='MMMMMM' style='display:block;border:0;padding:0;height:20px;font-size:16px'><input class=h placeholder='MMMMMM' style='display:block;border:0;padding:0;height:20px;font-size:16px'></body>")
    var px4 = [uint8](repeating: 0, count: 200 * 100 * 4)
    view4.Draw(into: &px4, width: 200, height: 100, scale: 1)
    func inks(_ y: int32, _ want: (draw.Color) -> bool) -> int {
        var n = 0
        var yy = y
        while yy < y + 20 {
            var x: int32 = 0
            while x < 80 {
                if want(pixelAt(px4, 200, x, yy)) { n += 1 }
                x += 1
            }
            yy += 1
        }
        return n
    }
    check(inks(0, { c in c.R < 200 && c.R == c.G && c.G == c.B }) > 10, "a placeholder is grey by default")
    check(inks(20, { c in c.R > 200 && c.G < 150 }) > 10, "::placeholder sets its color")
    check(inks(40, { c in c.R < 250 }) == 0, "and opacity: 0 hides it")
}

func near(_ a: float32, _ b: float32, _ tolerance: float32 = 0.5) -> bool {
    let d = a - b
    return d < tolerance && d > -tolerance
}

@MainActor
func testEvents() {
    print("Events reach listeners")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.LoadHTML("""
    <style>body { margin: 0 } button, input { position: absolute; left: 10px; width: 80px; height: 20px }</style>
    <form id=f><button id=b style='top: 10px'>Go</button><input id=t style='top: 50px'></form>
    """)
    var pixels = [uint8](repeating: 0, count: 300 * 200 * 4)
    view.Draw(into: &pixels, width: 300, height: 200, scale: 1)
    let doc = view.Document!
    let b = view.QuerySelector("#b")!
    let t = view.QuerySelector("#t")!
    var clicks = 0
    var submits = 0
    var submitted = 0
    var typed = ""
    var keys: [string] = []
    _ = doc.AddEventListener(b, "click", { e in clicks += 1 })
    _ = doc.AddEventListener(view.QuerySelector("#f")!, "submit", { e in
        submits += 1
        e.PreventDefault()
    })
    _ = doc.AddEventListener(t, "input", { e in
        if let i = e as? dom.InputEvent { typed = i.Value }
    })
    _ = doc.AddEventListener(t, "keydown", { e in
        if let k = e as? dom.KeyboardEvent { keys.append(k.Key) }
    })
    view.OnSubmit({ s in submitted += 1 })

    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(30, 20))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(30, 20))))
    check(clicks == 1, "a click on a button reaches its listener")
    check(submits == 1 && submitted == 0, "the submit it makes reaches the form's listener, which prevents it")

    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(30, 60))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(30, 60))))
    _ = view.Handle(.text("hi"))
    check(typed == "hi", "typing in a field fires input with its value (got '\(typed)')")
    _ = view.Handle(.keyDown(web.Key(Key: "Backspace", Code: "Backspace")))
    check(typed == "h" && keys == ["Backspace"], "a key fires keydown, and deleting fires input")

    // Focus, hover, double and secondary clicks.
    var seen: [string] = []
    let form = view.QuerySelector("#f")!
    for type in ["focus", "blur", "mouseenter", "mouseleave"] {
        _ = doc.AddEventListener(t, type, { e in seen.append("t." + e.Type) })
        _ = doc.AddEventListener(form, type, { e in seen.append("form." + e.Type) })
    }
    _ = doc.AddEventListener(b, "dblclick", { e in seen.append("b.dblclick") })
    _ = doc.AddEventListener(b, "contextmenu", { e in seen.append("b.contextmenu") })
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(30, 20))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(30, 20))))
    check(seen == ["t.blur"], "focus moving off a field sends it blur, which does not bubble (got \(seen))")
    _ = view.Handle(.pointerMoved(draw.Point(30, 20)))
    seen = []
    _ = view.Handle(.pointerMoved(draw.Point(30, 60)))
    check(seen.contains("t.mouseenter") && !seen.contains("form.mouseenter"), "the pointer entering a field sends it mouseenter; its form was entered already (got \(seen))")
    seen = []
    _ = view.Handle(.pointerMoved(draw.Point(250, 180)))
    check(seen.contains("t.mouseleave") && seen.contains("form.mouseleave"), "leaving sends mouseleave to each element left (got \(seen))")
    seen = []
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(30, 20), clicks: 2)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(30, 20), clicks: 2)))
    check(seen.contains("b.dblclick"), "a second click is a dblclick (got \(seen))")
    seen = []
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(30, 20), button: .secondary)))
    check(seen == ["b.contextmenu"], "a secondary press asks for the context menu (got \(seen))")
}

@MainActor
func testEventModel() {
    print("The DOM's event model: phases, keys, compatibility events, composition")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.LoadHTML("""
    <body style="margin:0"><div id="outer" style="padding:20px"><button id="b" style="width:100px;height:40px">b</button></div>
    <div id="far" style="height:60px"></div><input id="t" style="width:200px"></body>
    """)
    let doc = view.Document!
    let outer = view.QuerySelector("#outer")!
    let b = view.QuerySelector("#b")!
    var seen: [string] = []

    // Capturing listeners, outermost first; the target's; then bubbling.
    _ = doc.AddEventListener(outer, "click", capture: true, { _ in seen.append("outer.capture") })
    _ = doc.AddEventListener(outer, "click", { _ in seen.append("outer.bubble") })
    _ = doc.AddEventListener(b, "click", { _ in seen.append("b") })
    _ = doc.AddEventListener(b, "click", capture: true, { _ in seen.append("b.capture") })
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(40, 40))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(40, 40))))
    check(seen == ["outer.capture", "b.capture", "b", "outer.bubble"],
          "capture down to the target, the target's own, then bubbling (got \(seen))")

    // A listener that stops the event immediately stops its element's others.
    seen = []
    let stopper = doc.AddEventListener(b, "click", capture: true, { e in
        seen.append("stop")
        e.StopImmediatePropagation()
    })
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(40, 40))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(40, 40))))
    check(seen == ["outer.capture", "b.capture", "stop"] || seen == ["outer.capture", "stop"],
          "StopImmediatePropagation stops the element's other listeners too (got \(seen))")
    doc.RemoveEventListener(b, stopper)

    // The mouse events a pointer event is compatible with follow it.
    seen = []
    for type in ["pointerdown", "mousedown", "pointerup", "mouseup", "pointermove", "mousemove"] {
        _ = doc.AddEventListener(b, type, { e in seen.append(e.Type) })
    }
    _ = view.Handle(.pointerMoved(draw.Point(41, 41)))
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(41, 41))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(41, 41))))
    // (The click listeners above still log the click that follows.)
    check(Array(seen.prefix(6)) == ["pointermove", "mousemove", "pointerdown", "mousedown", "pointerup", "mouseup"],
          "mousemove, mousedown and mouseup follow their pointer events (got \(seen))")
    // A pointerdown listener that takes the press keeps the mouse events back.
    seen = []
    let taker = doc.AddEventListener(b, "pointerdown", { e in e.PreventDefault() })
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(41, 41))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(41, 41))))
    check(!seen.contains("mousedown") && !seen.contains("mouseup"), "and none follow a pointerdown a listener prevented (got \(seen))")
    doc.RemoveEventListener(b, taker)

    // Over and out bubble; enter and leave are each element's own.
    seen = []
    for type in ["pointerover", "pointerout", "pointerenter", "pointerleave", "mouseover", "mouseout"] {
        _ = doc.AddEventListener(outer, type, { e in seen.append("outer." + e.Type) })
        _ = doc.AddEventListener(b, type, { e in seen.append("b." + e.Type) })
    }
    _ = view.Handle(.pointerMoved(draw.Point(200, 100)))
    seen = []
    _ = view.Handle(.pointerMoved(draw.Point(40, 40)))
    check(seen.contains("b.pointerover") && seen.contains("outer.pointerover") && seen.contains("b.mouseover"),
          "pointerover and mouseover bubble from the element entered (got \(seen))")
    check(seen.contains("b.pointerenter") && seen.contains("outer.pointerenter"), "pointerenter comes to each element entered (got \(seen))")
    seen = []
    _ = view.Handle(.pointerMoved(draw.Point(200, 100)))
    check(seen.contains("b.pointerout") && seen.contains("b.pointerleave") && seen.contains("outer.pointerleave") && seen.contains("b.mouseout"),
          "and out and leave as it goes (got \(seen))")

    // A press the pointer leaves the window in the middle of is cancelled.
    seen = []
    _ = doc.AddEventListener(b, "pointercancel", { e in seen.append(e.Type) })
    _ = view.Handle(.pointerMoved(draw.Point(40, 40)))
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(40, 40))))
    _ = view.Handle(.pointerLeft)
    check(seen.contains("pointercancel"), "a press the pointer leaves the page during is cancelled (got \(seen))")

    // keyup, after keydown.
    let t = view.QuerySelector("#t")!
    view.Focus(t)
    var keys: [string] = []
    _ = doc.AddEventListener(t, "keydown", { e in keys.append("down") })
    _ = doc.AddEventListener(t, "keyup", { e in
        if let k = e as? dom.KeyboardEvent { keys.append("up " + k.Key) }
    })
    _ = view.Handle(.keyDown(web.Key(Key: "a", Code: "KeyA")))
    _ = view.Handle(.keyUp(web.Key(Key: "a", Code: "KeyA")))
    check(keys == ["down", "up a"], "a key's release fires keyup (got \(keys))")

    // An input method: start, updates, the composed text shown at the
    // caret, then end with what it committed.
    var comp: [string] = []
    for type in ["compositionstart", "compositionupdate", "compositionend"] {
        _ = doc.AddEventListener(t, type, { e in
            if let c = e as? dom.CompositionEvent { comp.append(c.Type + ":" + c.Data) }
        })
    }
    _ = view.Handle(.composition("ni"))
    _ = view.Handle(.composition("nih"))
    check(view.Composing == "nih", "what an input method composes is held while it does (\(view.Composing))")
    _ = view.Handle(.text("你好"))
    check(comp == ["compositionstart:", "compositionupdate:ni", "compositionupdate:nih", "compositionend:你好"],
          "compositionstart, an update each change, and compositionend with what was committed (got \(comp))")
    check(view.Composing.isEmpty && view.ValueOf(t) == "你好", "the committed text is the field's (\(view.ValueOf(t)))")

    // scroll, toggle and reset.
    let page2 = web.Page()
    page2.SetViewportSize(draw.Size(300, 200))
    page2.LoadHTML("""
    <body style="margin:0">
    <div id="box" style="height:80px;overflow:auto"><div style="height:400px">tall</div></div>
    <details id="d"><summary id="s" style="display:block;height:20px">more</summary>inside</details>
    <form id="f"><input id="name" value="a"><button id="r" type="reset" style="width:60px;height:20px">reset</button></form>
    <div style="height:1000px"></div>
    </body>
    """)
    let doc2 = page2.Document!
    var events: [string] = []
    _ = doc2.AddEventListener(page2.QuerySelector("html")!, "scroll", { _ in events.append("page") })
    _ = doc2.AddEventListener(page2.QuerySelector("#box")!, "scroll", { _ in events.append("box") })
    _ = doc2.AddEventListener(page2.QuerySelector("#d")!, "toggle", { _ in events.append("toggle") })
    _ = doc2.AddEventListener(page2.QuerySelector("#f")!, "reset", { _ in events.append("reset") })
    _ = page2.Handle(.pointerMoved(draw.Point(20, 20)))
    _ = page2.Handle(.wheel(web.Wheel(draw.Point(0, -1))))
    check(events == ["box"], "the wheel over a scroll container scrolls it: scroll at it (got \(events))")
    events = []
    page2.SetScrollOffset(draw.Point(0, 50))
    check(events == ["page"], "the page scrolling is scroll at its root (got \(events))")
    page2.SetScrollOffset(draw.Point(0, 0))
    events = []
    let sb = page2.BoundsOf(page2.QuerySelector("#s")!)!
    _ = page2.Handle(.pointerDown(web.Pointer(draw.Point(sb.X + 5, sb.Y + 5))))
    _ = page2.Handle(.pointerUp(web.Pointer(draw.Point(sb.X + 5, sb.Y + 5))))
    check(events == ["toggle"] && page2.QuerySelector("#d")!.HasAttribute("open"), "a summary's click opens its details: toggle (got \(events))")
    events = []
    let name = page2.QuerySelector("#name")!
    page2.Focus(name)
    _ = page2.Handle(.text("bc"))
    let rb = page2.BoundsOf(page2.QuerySelector("#r")!)!
    _ = page2.Handle(.pointerDown(web.Pointer(draw.Point(rb.X + 5, rb.Y + 5))))
    _ = page2.Handle(.pointerUp(web.Pointer(draw.Point(rb.X + 5, rb.Y + 5))))
    check(events == ["reset"] && page2.ValueOf(name) == "a", "a reset button: reset, and the fields their defaults (got \(events), '\(page2.ValueOf(name))')")
    let keep = doc2.AddEventListener(page2.QuerySelector("#f")!, "reset", { e in e.PreventDefault() })
    page2.Focus(name)
    _ = page2.Handle(.text("z"))
    _ = page2.Handle(.pointerDown(web.Pointer(draw.Point(rb.X + 5, rb.Y + 5))))
    _ = page2.Handle(.pointerUp(web.Pointer(draw.Point(rb.X + 5, rb.Y + 5))))
    check(page2.ValueOf(name) != "a", "a reset a listener prevented keeps the values ('\(page2.ValueOf(name))')")
    doc2.RemoveEventListener(page2.QuerySelector("#f")!, keep)
}

@MainActor
func testCursors() {
    print("Cursors: CSS's keywords")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 100))
    view.LoadHTML("""
    <body style="margin:0;display:flex">
    <div id="a" style="width:50px;height:50px;cursor:grab"></div>
    <div id="b" style="width:50px;height:50px;cursor:nwse-resize"></div>
    <div id="c" style="width:50px;height:50px;cursor:not-allowed"></div>
    <div id="d" style="width:50px;height:50px;cursor:url(hand.png) 4 4, zoom-in"></div>
    <div id="e" style="width:50px;height:50px;cursor:wait"></div>
    <div id="f" style="width:50px;height:50px">text</div>
    </body>
    """)
    var got: [string] = []
    for x in [25, 75, 125, 175, 225, 260] {
        _ = view.Handle(.pointerMoved(draw.Point(float32(x), 10)))
        got.append(view.DesiredCursor().CSSName)
    }
    check(got == ["grab", "nwse-resize", "not-allowed", "zoom-in", "wait", "text"],
          "each keyword is its own cursor, a url() list its fallback, auto over text an I-beam (got \(got))")
}


@MainActor
func testTransforms() {
    print("Transforms")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.LoadHTML("""
    <body style="margin:0;background:white">
    <div id="t" style="position:absolute;left:0;top:0;width:20px;height:20px;background:rgb(255,0,0);transform:translate(100px, 50%)"></div>
    <div id="r" style="position:absolute;left:0;top:100px;width:40px;height:10px;background:rgb(0,0,255);transform:rotate(90deg)"></div>
    <div id="s" style="position:absolute;left:200px;top:0;width:20px;height:20px;background:rgb(0,128,0);scale:2;transform-origin:top left"></div>
    <div id="p" style="width:20px;height:20px;margin-top:170px;background:rgb(0,0,0);translate:calc(10px + 50%) 0">x</div>
    </body>
    """)
    var px = [uint8](repeating: 0, count: 300 * 200 * 4)
    view.Draw(into: &px, width: 300, height: 200, scale: 1)
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 300, x, y) }
    check(at(110, 15) == draw.Color(255, 0, 0) && at(5, 5) == draw.Color(255, 255, 255),
          "translate() moves a box, by lengths and percentages of itself (got \(at(110, 15)))")
    check(at(20, 88) == draw.Color(0, 0, 255) && at(20, 112) == draw.Color(0, 0, 255) && at(2, 105) == draw.Color(255, 255, 255),
          "rotate() turns it about its center (got \(at(20, 88)) \(at(2, 105)))")
    check(at(235, 35) == draw.Color(0, 128, 0) && at(242, 42) == draw.Color(255, 255, 255),
          "the scale property grows it from transform-origin (got \(at(235, 35)))")
    check(at(35, 180) == draw.Color(0, 0, 0) && at(5, 180) == draw.Color(255, 255, 255),
          "the translate property moves an in-flow box, calc() and all (got \(at(35, 180)))")
    func idAt(_ x: float32, _ y: float32) -> string { return view.ElementAt(draw.Point(x, y))?.GetAttribute("id") ?? "" }
    check(idAt(110, 15) == "t" && idAt(5, 5) != "t", "a click lands on a translated box where it is drawn")
    check(idAt(20, 90) == "r" && idAt(35, 105) != "r", "and on a rotated one")
    check(idAt(235, 35) == "s", "and on a scaled one")
}

@MainActor
func testAnimations() {
    print("Transitions and animations")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.LoadHTML("""
    <style>
    #a { width: 10px; height: 10px; opacity: 1; transition: opacity 1s linear, width 2s linear 1s }
    #a.on { opacity: 0; width: 110px }
    @keyframes grow { from { width: 0px } 50% { width: 100px; background-color: rgb(0, 0, 255) } to { width: 40px } }
    #b { height: 10px; width: 40px; background-color: rgb(255, 0, 0); animation: grow 2s linear 2 alternate forwards }
    @keyframes fade { to { opacity: 0 } }
    #c { animation: fade 1s steps(2) paused }
    #d { color: rgb(0, 0, 0); transition: color 1s linear } #d.on { color: rgb(200, 100, 0) }
    </style>
    <div id=a></div><div id=b></div><div id=c>c</div><div id=d><span id=e>e</span></div>
    """)
    let doc = view.Document!
    let a = view.QuerySelector("#a")!
    let b = view.QuerySelector("#b")!
    let c = view.QuerySelector("#c")!
    var events: [string] = []
    _ = doc.AddEventListener(a, "transitionend", { e in events.append("end") })
    _ = doc.AddEventListener(b, "animationend", { e in events.append("animationend") })
    _ = doc.AddEventListener(b, "animationiteration", { e in events.append("iteration") })
    func width(_ n: html.Node) -> float32 { return view.BoxFor(n)!.Width }
    func opacity(_ n: html.Node) -> float32 { return view.BoxFor(n)!.Style.Opacity }

    _ = view.Advance(time: 0)
    check(opacity(a) == 1 && width(a) == 10, "nothing moves before a change")
    check(width(b) == 0, "an animation shows its 0% at once (got \(width(b)))")
    doc.ElementFor(a).ClassList.Add("on")
    doc.ElementFor(view.QuerySelector("#d")!).ClassList.Add("on")
    check(opacity(a) == 1 && view.NeedsAnimation(), "a change starts a transition from the old value")
    _ = view.Advance(time: 0)
    _ = view.Advance(time: 0.5)
    check(abs(opacity(a) - 0.5) < 0.01, "halfway through, the value is halfway (got \(opacity(a)))")
    check(width(a) == 10, "a delayed transition waits")
    check(abs(width(b) - 50) < 0.5, "keyframes interpolate between their offsets (got \(width(b)))")
    let bg = view.BoxFor(b)!.Style.BackgroundColor
    check(abs(int(bg.R) - 128) <= 1 && abs(int(bg.B) - 128) <= 1, "and a keyframe that names a property late starts from the element's own value (got \(bg.R) \(bg.B))")
    let span = view.BoxFor(view.QuerySelector("#e")!)!.Style.Color
    check(abs(int(span.R) - 100) <= 1 && abs(int(span.G) - 50) <= 1, "a transitioning inherited property reaches the children (got \(span.R) \(span.G))")
    _ = view.Advance(time: 1.5)
    check(opacity(a) == 0, "a finished transition leaves the new value")
    check(abs(width(a) - 35) < 0.5, "a delayed one runs after its delay (got \(width(a)))")
    check(abs(width(b) - 70) < 0.5, "past 50% toward 100% (got \(width(b)))")
    _ = view.Advance(time: 2.5)
    check(abs(width(b) - 70) < 0.5, "alternate runs the second iteration backwards (got \(width(b)))")
    check(abs(width(a) - 85) < 0.5, "the delayed transition keeps going (got \(width(a)))")
    _ = view.Advance(time: 4.5)
    check(width(b) == 0, "fill forwards keeps where the last iteration ended (got \(width(b)))")
    check(width(a) == 110, "and the transition is done")
    _ = view.Advance(time: 4.6)
    check(events.filter { $0 == "end" }.count == 2, "transitionend fires for each property (got \(events))")
    check(events.contains("iteration") && events.contains("animationend"), "animationiteration and animationend fire")
    check(opacity(c) == 1, "a paused animation holds its start")
    doc.ElementFor(c).SetAttribute("style", "animation-play-state: running")
    check(opacity(c) == 1, "resumed, it goes on from there")
    _ = view.Advance(time: 5.2)
    check(abs(opacity(c) - 0.5) < 0.01, "steps() moves in steps (got \(opacity(c)))")
    _ = view.Advance(time: 6)
    check(opacity(c) == 1 && !view.NeedsAnimation(), "without a fill an ended animation lets go, and the page asks for no more frames")

    // A transition only the new state declares, and discrete ones.
    let v2 = web.Page()
    v2.SetViewportSize(draw.Size(300, 200))
    v2.LoadHTML("""
    <style>
    #h { opacity: 1 } #h.on { opacity: 0; transition: opacity 1s linear }
    #x { opacity: 1; display: block; transition: opacity 1s linear, display 1s allow-discrete }
    #x.gone { opacity: 0; display: none }
    #v { visibility: visible; transition: visibility 1s } #v.off { visibility: hidden }
    #n { transition: display 1s } #n.gone { display: none }
    </style>
    <div id=h>h</div><div id=x>x</div><div id=v>v</div><div id=n>n</div>
    """)
    let d2 = v2.Document!
    _ = v2.Advance(time: 0)
    // Styled once, as a page that has been drawn is.
    _ = v2.BoxFor(v2.QuerySelector("#h")!)
    for id in ["#h", "#x", "#v", "#n"] {
        let n = v2.QuerySelector(id)!
        d2.ElementFor(n).ClassList.Add(id == "#h" ? "on" : (id == "#v" ? "off" : "gone"))
    }
    // Drawn after the change, which restyles; the next frame starts them.
    _ = v2.BoxFor(v2.QuerySelector("#h")!)
    _ = v2.Advance(time: 0)
    _ = v2.Advance(time: 0.5)
    let h = v2.BoxFor(v2.QuerySelector("#h")!)!.Style.Opacity
    check(abs(h - 0.5) < 0.01, "a transition the new state alone declares runs from the old value (got \(h))")
    check(v2.BoxFor(v2.QuerySelector("#x")!) != nil, "display: none with allow-discrete waits for the transition's end, showing it fade")
    check(v2.BoxFor(v2.QuerySelector("#v")!)!.Style.Visibility == .visible, "visibility stays visible while it transitions to hidden")
    check(v2.BoxFor(v2.QuerySelector("#n")!) == nil, "display without allow-discrete changes at once")
    _ = v2.Advance(time: 1.5)
    check(v2.BoxFor(v2.QuerySelector("#x")!) == nil && v2.BoxFor(v2.QuerySelector("#v")!)!.Style.Visibility == .hidden,
          "and at the end it is gone, and hidden")
}

@MainActor
func testContainerQueries() {
    print("Container queries and new units")
    let view = web.Page()
    view.SetViewportSize(draw.Size(800, 600))
    view.LoadHTML("""
    <style>
    body { margin: 0 }
    .card { container: card / inline-size }
    .wide { width: 500px } .narrow { width: 200px }
    .t { width: 10px; height: 10px }
    @container card (width > 400px) { .t { width: 30px } }
    @container (min-width: 100px) and (max-width: 300px) { .t { height: 20px } }
    @container style(--theme: dark) { .t { margin-left: 5px } }
    @container other (width > 1px) { .t { width: 99px } }
    .u { width: 50cqw; height: 10px }
    .sz { container-type: size; width: 100px; height: 60px }
    @container (orientation: landscape) and (not (height < 10px)) { .v { width: 7px } }
    @container (height > 10px) { .w { width: 9px } }
    .l { font-size: 10px; line-height: 2; height: 1lh; width: 2dvw }
    </style>
    <div class="card wide"><div class=t id=t1></div><div class=u id=u1></div></div>
    <div class="card narrow" style="--theme: dark"><div class=t id=t2></div><div class=w id=w></div></div>
    <div class=sz><div class=v id=v></div></div>
    <div class=l id=l></div>
    """)
    func box(_ id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
    check(box("t1").Width == 30 && box("t1").Height == 10, "a named query holds in a wide container (got \(box("t1").Width) \(box("t1").Height))")
    check(box("t2").Width == 10 && box("t2").Height == 20, "and an unnamed range query in a narrow one (got \(box("t2").Width) \(box("t2").Height))")
    check(box("t2").Style.MarginLeft == .px(5) && box("t1").Style.MarginLeft == .px(0), "style() asks the container's custom properties")
    check(box("u1").Width == 250, "cqw is of the container's width (got \(box("u1").Width))")
    check(box("v").Width == 7, "a size container answers orientation, not and nesting (got \(box("v").Width))")
    check(box("w").Width != 9, "an inline-size container has no height to ask about")
    check(box("l").Height == 20 && box("l").Width == 16, "lh is the line height, dvw the viewport's (got \(box("l").Height) \(box("l").Width))")
    view.SetViewportSize(draw.Size(300, 600))
    check(box("t1").Width == 30, "a container's own width is what counts, not the viewport's")
}

@MainActor
func testFrames() {
    print("Frames, media and object-fit")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 500))
    view.Configuration.Fetcher = fetch.Fetcher({ url in
        if url.hasSuffix("inner.html") {
            return [uint8]("<body style='margin:0;background:rgb(0,0,255)'><a id=l href='next.html' style='display:block;width:50px;height:20px'>x</a></body>".utf8)
        }
        if url.hasSuffix("next.html") { return [uint8]("<body style='margin:0;background:rgb(0,255,0)'></body>".utf8) }
        return nil
    })
    view.LoadHTML("""
    <body style="margin:0;background:white">
    <iframe id=f src="inner.html" style="border:0;width:100px;height:50px;display:block"></iframe>
    <iframe id=s srcdoc="<body style='margin:0;background:rgb(255,0,0)'>" style="border:0;width:60px;height:30px;display:block"></iframe>
    <canvas id=c><p id=fb>fallback</p></canvas>
    <audio id=a></audio><audio id=ac controls></audio>
    <img id=i src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z/AfiAAN+QP9Wkb9ewAAAABJRU5ErkJggg==" style="display:block;width:100px;height:100px;object-fit:contain">
    <video id=v poster="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z/AfiAAN+QP9Wkb9ewAAAABJRU5ErkJggg==" style="display:block;width:100px;height:100px"></video>
    <object id=o data="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4z/AfiAAN+QP9Wkb9ewAAAABJRU5ErkJggg==" style="display:block"></object>
    <object id=u data="thing.bin" type="application/x-thing"><span id=ufb>no plugin</span></object>
    </body>
    """, baseURL: "/site/")
    var px = [uint8](repeating: 0, count: 400 * 500 * 4)
    func draw() { view.Draw(into: &px, width: 400, height: 500, scale: 1) }
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 400, x, y) }
    func box(_ id: string) -> layout.Box? { return view.BoxFor(view.QuerySelector("#" + id)!) }
    draw()
    check(at(70, 40) == draw.Color(0, 0, 255), "an iframe shows its document (got \(at(70, 40)))")
    check(at(30, 65) == draw.Color(255, 0, 0), "and srcdoc (got \(at(30, 65)))")
    check(box("fb") != nil && box("c")!.Replaced == .none, "a canvas shows its fallback, as without scripting")
    check(box("a") == nil, "an audio without controls shows nothing")
    check(box("ac")!.Width == 300 && box("ac")!.Height == 54, "with them, a bar of controls")
    let img = box("i")!
    let iy = int32(layout.PagePosition(img).y)
    check(at(50, iy + 5) == draw.Color(255, 255, 255) && at(50, iy + 50) == draw.Color(255, 0, 255),
          "object-fit: contain letterboxes an image (got \(at(50, iy + 5)) \(at(50, iy + 50)))")
    let vb = box("v")!
    let vy = int32(layout.PagePosition(vb).y)
    check(vb.Replaced == .image && at(50, vy + 5) == draw.Color(255, 255, 255) && at(50, vy + 50) == draw.Color(255, 0, 255),
          "a video shows its poster, contained (got \(at(50, vy + 5)) \(at(50, vy + 50)))")
    check(box("o")!.Replaced == .image && box("o")!.Width == 2, "an object of an image is that image")
    check(box("ufb") != nil, "an object of something unknown shows its fallback")
    _ = view.Handle(.pointerMoved(draw.Point(10, 10)))
    check(view.DesiredCursor() == web.Cursor.pointer, "the pointer over a link in a frame is a hand")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(10, 10))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(10, 10))))
    check(view.NeedsRepaint(), "a click in a frame asks for a frame")
    draw()
    check(at(70, 40) == draw.Color(0, 255, 0), "and a link in it navigates the frame (got \(at(70, 40)))")
}

@MainActor
func testFocusVisibleAndTarget() {
    print(":focus-visible and :target")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 300))
    view.LoadHTML("""
    <style>
    body { margin: 0 } button, input { display: block; width: 100px; height: 20px; border: 0; padding: 0 }
    :focus-visible { width: 50px } #t { height: 10px } #t:target { height: 30px }
    </style>
    <button id=b>b</button><input id=i><a id=l href="#t">go</a><div id=t></div>
    """)
    func w(_ id: string) -> float32 { return view.BoxFor(view.QuerySelector("#" + id)!)!.Width }
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(10, 10))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(10, 10))))
    check(w("b") == 100, "a button clicked into focus shows no :focus-visible (got \(w("b")))")
    _ = view.Handle(.keyDown(web.Key(Key: "Tab", Code: "Tab")))
    check(w("i") == 50, "tabbing to a control shows it (got \(w("i")))")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(10, 30))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(10, 30))))
    check(w("i") == 50, "a text field shows it however it was focused")
    let link = view.BoundsOf(view.QuerySelector("#l")!)!
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(link.X + 2, link.Y + 5))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(link.X + 2, link.Y + 5))))
    check(view.BoxFor(view.QuerySelector("#t")!)!.Height == 30, "following a fragment link makes its element :target")
}

@MainActor
func testPseudoElements() {
    print("::marker, ::first-letter, ::first-line, ::selection")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 300))
    view.LoadHTML("""
    <style>
    body { margin: 0; font: 20px Helvetica } ul { margin: 0; padding-left: 40px }
    li::marker { color: rgb(255, 0, 0) }
    #fl { margin: 0 } #fl::first-letter { font-size: 40px; color: rgb(0, 0, 255) }
    #ln { margin: 0; width: 120px } #ln::first-line { color: rgb(0, 160, 0) }
    #sel::selection { background-color: rgb(255, 255, 0); color: rgb(255, 0, 0) } #sel { margin: 0 }
    </style>
    <ul><li id=li>item</li></ul>
    <p id=fl>"Drop cap</p>
    <p id=ln>first line here and then the second line</p>
    <p id=sel>select me</p>
    """)
    var px = [uint8](repeating: 0, count: 400 * 300 * 4)
    func count(_ c: draw.Color, _ r: draw.Rect) -> int {
        var n = 0
        var y = int32(r.Y)
        while y < int32(r.Y + r.Height) {
            var x = int32(r.X)
            while x < int32(r.X + r.Width) {
                if pixelAt(px, 400, x, y) == c { n += 1 }
                x += 1
            }
            y += 1
        }
        return n
    }
    func bounds(_ id: string) -> draw.Rect { return view.BoundsOf(view.QuerySelector("#" + id)!)! }
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    let li = bounds("li")
    check(count(draw.Color(255, 0, 0), draw.Rect(0, li.Y, 40, li.Height)) > 4, "::marker colors the bullet")
    let flBox = view.BoxFor(view.QuerySelector("#fl")!)!
    var letter = ""
    for c in flBox.Children where c.Kind == .inline { for t in c.Children { letter += t.Text } ; check(c.Style.FontSize == 40, "::first-letter's font size applies") }
    check(letter == "\"D", "::first-letter takes the punctuation before the letter (got '\(letter)')")
    let fl = bounds("fl")
    check(count(draw.Color(0, 0, 255), fl) > 20 && fl.Height >= 40, "and lays it out larger, in its color (got height \(fl.Height))")
    let ln = bounds("ln")
    check(count(draw.Color(0, 160, 0), draw.Rect(ln.X, ln.Y, ln.Width, 22)) > 10 && count(draw.Color(0, 160, 0), draw.Rect(ln.X, ln.Y + 26, ln.Width, ln.Height - 26)) == 0,
          "::first-line colors the first line only")
    let sel = bounds("sel")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(sel.X + 1, sel.Y + 10))))
    _ = view.Handle(.pointerMoved(draw.Point(sel.X + 80, sel.Y + 10)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(sel.X + 80, sel.Y + 10))))
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    check(count(draw.Color(255, 255, 0), sel) > 50 && count(draw.Color(255, 0, 0), sel) > 5, "::selection sets the highlight and the selected text's color")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(fl.X + 1, fl.Y + 30))))
    _ = view.Handle(.pointerMoved(draw.Point(fl.X + 300, fl.Y + 30)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(fl.X + 300, fl.Y + 30))))
    check(view.SelectedText() == "\"Drop cap", "a selection across a ::first-letter reads the text whole (got '\(view.SelectedText())')")
}

@MainActor
func testDecorations() {
    print("Border and outline styles, decorations, text-shadow, background-clip")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 300))
    view.LoadHTML("""
    <style>
    body { margin: 0; background: white; font: 20px Helvetica }
    #d { position: absolute; left: 0; top: 0; width: 100px; height: 20px; border-top: 4px dashed rgb(0, 0, 0) }
    #o { position: absolute; left: 50px; top: 50px; width: 20px; height: 20px; outline: 2px solid rgb(255, 0, 0); outline-offset: 4px }
    #u { position: absolute; left: 0; top: 100px; margin: 0; color: rgb(0, 0, 0); text-decoration: underline 3px rgb(0, 0, 255); text-underline-offset: 8px }
    #s { position: absolute; left: 0; top: 150px; margin: 0; color: rgb(0, 0, 0); text-shadow: 3px 3px 0 rgb(255, 0, 0) }
    #c { position: absolute; left: 200px; top: 0; width: 20px; height: 20px; padding: 10px; background: rgb(0, 200, 0); background-clip: content-box }
    </style>
    <div id=d></div><div id=o></div><p id=u>under</p><p id=s>shadow</p><div id=c></div>
    """)
    var px = [uint8](repeating: 0, count: 400 * 300 * 4)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 400, x, y) }
    func count(_ c: draw.Color, _ x0: int32, _ y0: int32, _ x1: int32, _ y1: int32) -> int {
        var n = 0
        var y = y0
        while y < y1 { var x = x0; while x < x1 { if at(x, y) == c { n += 1 }; x += 1 }; y += 1 }
        return n
    }
    let black = draw.Color(0, 0, 0)
    let dashes = count(black, 0, 1, 100, 2)
    check(dashes > 30 && dashes < 80, "a dashed border has gaps (got \(dashes) of 100)")
    check(at(45, 60) == draw.Color(255, 0, 0) && at(48, 60) == draw.Color(255, 255, 255), "outline-offset moves the outline out from the box")
    let u = view.BoundsOf(view.QuerySelector("#u")!)!
    var rows: [int32] = []
    var ry = int32(u.Y)
    while ry < int32(u.Y) + 40 { if count(draw.Color(0, 0, 255), 0, ry, 40, ry + 1) > 5 { rows.append(ry) }; ry += 1 }
    // The font's ascent is about 15px: an auto underline would sit near
    // 17px down, the offset one 8px below the baseline.
    check(rows.count == 3 && rows[0] - int32(u.Y) >= 21 && rows[0] - int32(u.Y) <= 26,
          "text-underline-offset and thickness place the underline (rows \(rows) from \(u.Y))")
    let sh = view.BoundsOf(view.QuerySelector("#s")!)!
    check(count(draw.Color(255, 0, 0), 0, int32(sh.Y), 80, int32(sh.Y + sh.Height) + 4) > 20, "text-shadow draws behind the text")
    check(at(205, 5) == draw.Color(255, 255, 255) && at(215, 15) == draw.Color(0, 200, 0), "background-clip: content-box keeps out of the padding")

    view.LoadHTML("""
    <style>body { margin: 0 } div { position: absolute; width: 100px; height: 100px }</style>
    <div style="left: 0; top: 0; background: conic-gradient(rgb(255, 0, 0) 0deg 90deg, rgb(0, 0, 255) 90deg 360deg)"></div>
    <div style="left: 150px; top: 0; background: conic-gradient(from 90deg at 0% 0%, rgb(0, 255, 0) 0 25%, rgb(0, 0, 0) 25% 100%)"></div>
    <div style="left: 0; top: 150px; background: repeating-linear-gradient(90deg, rgb(255, 0, 0) 0 10%, rgb(0, 0, 255) 10% 20%)"></div>
    """)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    check(at(75, 25) == draw.Color(255, 0, 0) && at(25, 75) == draw.Color(0, 0, 255), "conic-gradient goes round from the top, clockwise, in hard stops")
    // From the top-left corner, starting rightwards, the box lies in
    // the first quarter turn: green all over.
    check(at(245, 5) == draw.Color(0, 255, 0) && at(155, 95) == draw.Color(0, 255, 0) && at(200, 50) == draw.Color(0, 255, 0),
          "from and at move its start and centre (got \(at(245, 5)) \(at(155, 95)))")
    check(at(5, 200) == draw.Color(255, 0, 0) && at(15, 200) == draw.Color(0, 0, 255) && at(45, 200) == draw.Color(255, 0, 0) && at(95, 200) == draw.Color(0, 0, 255),
          "repeating-linear-gradient repeats its stops (got \(at(45, 200)) \(at(95, 200)))")
}

@MainActor
func testGridAreasAndLogical() {
    print("Grid areas, justify, logical sizes")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 300))
    view.LoadHTML("""
    <style>
    body { margin: 0 }
    #g { display: grid; width: 300px; grid-template: "head head" 20px "side main" 50px / 100px 1fr }
    #h { grid-area: head } #s { grid-area: side } #m { grid-area: main }
    #j { display: grid; width: 300px; grid-template-columns: 100px 50px; justify-content: center; justify-items: center }
    #j div { height: 10px } #e { justify-self: end; width: 10px }
    #l { inline-size: 50px; block-size: 7px; border-inline: 2px solid black }
    #a { display: grid; grid-template-areas: "x y"; grid-template-columns: 100px 100px; width: 200px } #ay { grid-column: y }
    </style>
    <div id=g><div id=m>m</div><div id=h>h</div><div id=s>s</div></div>
    <div id=j><div id=jc><span style="display:inline-block;width:20px">x</span></div><div id=e></div></div>
    <div id=l></div>
    <div id=a><div id=ay>y</div></div>
    """)
    func box(_ id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
    func at(_ id: string) -> draw.Rect { return view.BoundsOf(view.QuerySelector("#" + id)!)! }
    check(at("h").X == 0 && at("h").Y == 0 && at("h").Width == 300 && at("h").Height == 20, "a named area spans its cells (got \(at("h")))")
    check(at("s").X == 0 && at("s").Y == 20 && at("s").Width == 100 && at("s").Height == 50, "grid-template sets rows, areas and columns (got \(at("s")))")
    check(at("m").X == 100 && at("m").Y == 20 && at("m").Width == 200, "and source order doesn't matter (got \(at("m")))")
    let jc = at("jc")
    let jy = at("j").Y
    check(jc.Width == 20 && jc.X == 75 + 40, "justify-content centers the tracks, justify-items an item in its area (got \(jc))")
    check(at("e").X == 75 + 100 + 40 && at("e").Y == jy, "justify-self: end puts one at the area's end (got \(at("e")))")
    check(box("l").Width == 54 && box("l").Height == 7 && box("l").Border.Left == 2 && box("l").Border.Top == 0, "inline-size, block-size and border-inline")
    check(at("ay").X == 100, "a placement may name an area on one axis (got \(at("ay").X))")
}

@MainActor
func testTextWrap() {
    print("text-wrap, white-space-collapse, line-clamp")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 400))
    view.LoadHTML("""
    <style>
    body { margin: 0; font: 16px Helvetica } p { margin: 0; width: 220px }
    #b { text-wrap: balance } #n { text-wrap: nowrap } #c { line-clamp: 2; overflow: hidden }
    #w { white-space-collapse: preserve } #pr { text-wrap: pretty; width: 200px }
    </style>
    <p id=plain style="width: 300px">one two three four five six seven eight nine ten eleven twelve</p>
    <p id=b style="width: 300px">one two three four five six seven eight nine ten eleven twelve</p>
    <p id=n>one two three four five six seven eight nine ten eleven</p>
    <p id=c>one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen</p>
    <p id=w>a    b</p>
    <p id=pr>aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm</p>
    """)
    func box(_ id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
    func widths(_ b: layout.Box) -> [float32] {
        return b.Lines.map { l in
            var right: float32 = 0
            for f in l.Fragments where f.Kind == .text && !layout.IsBlank(f.Text) { right = f.X + f.Width }
            return right
        }
    }
    let plain = widths(box("plain"))
    let bal = widths(box("b"))
    check(plain.count == 2 && bal.count == 2, "balance keeps the lines there are (got \(plain.count) \(bal.count))")
    check(abs(bal[0] - bal[1]) < abs(plain[0] - plain[1]) && abs(bal[0] - bal[1]) < 40, "and evens them out (got \(bal), plain \(plain))")
    check(box("n").Lines.count == 1, "text-wrap: nowrap keeps one line")
    let c = box("c")
    check(c.Lines.count == 2 && (c.Lines[1].Fragments.last?.Text.hasSuffix("…") ?? false), "line-clamp keeps two lines and ends with an ellipsis")
    check(c.Height == 2 * c.Style.LineHeightPx || abs(c.Height - c.Lines[1].Y - c.Lines[1].Height + c.ContentY) < 0.5, "and is as tall as them (got \(c.Height))")
    var text = ""
    for f in box("w").Lines[0].Fragments { text += f.Text }
    check(text == "a    b", "white-space-collapse: preserve keeps the spaces (got '\(text)')")
    let pr = box("pr")
    var lastText = ""
    for f in pr.Lines[pr.Lines.count - 1].Fragments where f.Kind == .text { lastText += f.Text }
    let lastWords = lastText.split(separator: " ").filter { !$0.isEmpty }.count
    check(lastWords >= 2, "text-wrap: pretty brings a word down to a lonely last one (got \(lastWords))")
}

@MainActor
func testScrollbarsZoomAndContainment() {
    print("zoom, color-scheme, scrollbars, caret, appearance, resize, containment")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 300))
    view.LoadHTML("""
    <style>
    body { margin: 0; background: white }
    #z { zoom: 2; width: 50px; height: 10px; font-size: 10px; border-left: 1px solid black }
    #zc { width: 1rem; height: 1em }
    #dk { color-scheme: dark; color: light-dark(rgb(1, 1, 1), rgb(2, 2, 2)) } #lt { color-scheme: light; color: light-dark(rgb(1, 1, 1), rgb(2, 2, 2)) }
    #sc { position: absolute; left: 300px; top: 0; width: 60px; height: 60px; overflow: auto; scrollbar-color: rgb(255, 0, 0) rgb(0, 0, 255) }
    #cb { appearance: none; width: 16px; height: 16px; position: absolute; left: 0; top: 200px; margin: 0 }
    #ta { position: absolute; left: 100px; top: 150px; width: 100px; height: 40px; padding: 0; border: 1px solid black; box-sizing: border-box }
    #cv { content-visibility: hidden; contain-intrinsic-size: 40px 30px; width: 40px } #cs { contain: size } #cp { contain: paint; height: 5px }
    </style>
    <div id=z><div id=zc></div></div>
    <p id=dk>d</p><p id=lt>l</p>
    <div id=sc><div style="height: 300px"></div></div>
    <input id=cb type=checkbox checked>
    <textarea id=ta></textarea>
    <div id=cv><p id=cvp>hidden</p></div><div id=cs><p>sized</p></div><div id=cp><p>clipped</p></div>
    """)
    func box(_ id: string) -> layout.Box? { return view.BoxFor(view.QuerySelector("#" + id)!) }
    check(box("z")!.Width == 102 && box("z")!.Height == 20 && box("z")!.Border.Left == 2, "zoom doubles lengths and borders (got \(box("z")!.Width) \(box("z")!.Height))")
    check(box("zc")!.Width == 32 && box("zc")!.Height == 20, "and rem and em inside it (got \(box("zc")!.Width) \(box("zc")!.Height))")
    check(box("dk")!.Style.Color == draw.Color(2, 2, 2) && box("lt")!.Style.Color == draw.Color(1, 1, 1), "color-scheme picks light-dark()'s color")
    var px = [uint8](repeating: 0, count: 400 * 300 * 4)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 400, x, y) }
    check(at(354, 5) == draw.Color(255, 0, 0) && at(354, 50) == draw.Color(0, 0, 255), "scrollbar-color's thumb and track (got \(at(354, 5)) \(at(354, 50)))")
    check(at(8, 208) != draw.Color(0, 117, 255), "appearance: none draws no checkbox of its own")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(196, 187))))
    _ = view.Handle(.pointerMoved(draw.Point(216, 197)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(216, 197))))
    check(box("ta")!.Width == 120 && box("ta")!.Height == 50, "dragging a textarea's grip resizes it (got \(box("ta")!.Width) \(box("ta")!.Height))")
    check(box("cvp") == nil && box("cv")!.Height == 30, "content-visibility: hidden skips the content and takes contain-intrinsic-size")
    check(box("cs")!.Height == 0 && box("cp")!.Style.ClipsOverflow, "contain: size and paint")
}

@MainActor
func testSmoothScrollAndSnap() {
    print("Scroll offsets kept, smooth scrolling, scroll snap")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.LoadHTML("""
    <style>
    html { scroll-behavior: smooth } body { margin: 0 }
    #box { width: 100px; height: 100px; overflow: auto; scroll-snap-type: y mandatory }
    #box div { height: 100px; scroll-snap-align: start }
    #h { width: 100px; height: 50px; overflow: auto; white-space: nowrap; scroll-snap-type: x mandatory }
    #h span { display: inline-block; width: 100px; height: 40px; scroll-snap-align: start }
    a:hover { color: red } #tall { height: 2000px }
    </style>
    <div id=box><div>1</div><div>2</div><div>3</div></div>
    <div id=h><span>a</span><span>b</span><span>c</span></div>
    <a id=l href="#">link</a><div id=tall></div>
    """)
    func box(_ id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
    _ = view.Advance(time: 0)
    _ = view.Handle(.pointerMoved(draw.Point(50, 50)))
    _ = view.Handle(.wheel(web.Wheel(draw.Point(0, -30), precise: true)))
    check(box("box").ScrollY == 30, "the wheel scrolls the container (got \(box("box").ScrollY))")
    let link = view.BoundsOf(view.QuerySelector("#l")!)!
    _ = view.Handle(.pointerMoved(draw.Point(link.X + 2, link.Y + 5)))
    check(box("box").ScrollY == 30, "and a restyle keeps where it is scrolled to (got \(box("box").ScrollY))")
    check(view.NeedsAnimation(), "a wheel scroll in a snap container waits to snap")
    _ = view.Advance(time: 0.2)
    _ = view.Advance(time: 0.7)
    check(box("box").ScrollY == 0, "mandatory snapping settles on the nearest start (got \(box("box").ScrollY))")
    _ = view.Handle(.pointerMoved(draw.Point(50, 50)))
    _ = view.Handle(.wheel(web.Wheel(draw.Point(0, -70), precise: true)))
    _ = view.Advance(time: 1.0)
    _ = view.Advance(time: 1.5)
    check(box("box").ScrollY == 100, "and on the next one past halfway (got \(box("box").ScrollY))")
    _ = view.Handle(.pointerMoved(draw.Point(50, 120)))
    _ = view.Handle(.wheel(web.Wheel(draw.Point(0, -60), precise: true)))
    check(box("h").ScrollX == 60, "a container that only scrolls sideways takes the wheel sideways (got \(box("h").ScrollX))")
    _ = view.Advance(time: 2.0)
    _ = view.Advance(time: 2.5)
    check(box("h").ScrollX == 100, "and snaps along x (got \(box("h").ScrollX))")
    _ = view.Handle(.pointerMoved(draw.Point(250, 190)))
    _ = view.Handle(.keyDown(web.Key(Key: "End", Code: "End")))
    check(view.ScrollOffset().Y == 0 && view.NeedsAnimation(), "scroll-behavior: smooth makes a key's scroll glide (got \(view.ScrollOffset().Y))")
    _ = view.Advance(time: 3.0)
    _ = view.Advance(time: 3.15)
    let mid = view.ScrollOffset().Y
    _ = view.Advance(time: 3.5)
    let end = view.ScrollOffset().Y
    check(mid > 0 && mid < end && end > 1000, "through the middle to the end (got \(mid) then \(end))")
}

@MainActor
func testDialogsAndPopovers() {
    print("<dialog>, popovers, constraint validation")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 300))
    view.LoadHTML("""
    <style>body { margin: 0; background: white } button { display: block; width: 80px; height: 20px } #d { width: 100px; height: 60px; padding: 0 }</style>
    <button id=open commandfor=d command=show-modal>open</button><button id=other>other</button>
    <dialog id=d><form method=dialog><input id=di><button id=ok value=yes>OK</button></form></dialog>
    <button id=pb popovertarget=p>pop</button><div id=p popover>hi</div>
    <form id=f><input id=req required><button id=go>go</button></form>
    """)
    let doc = view.Document!
    func node(_ id: string) -> html.Node { return view.QuerySelector("#" + id)! }
    func click(_ id: string) {
        let r = view.BoundsOf(node(id))!
        _ = view.Handle(.pointerDown(web.Pointer(draw.Point(r.X + 2, r.Y + 2))))
        _ = view.Handle(.pointerUp(web.Pointer(draw.Point(r.X + 2, r.Y + 2))))
    }
    var events: [string] = []
    var otherClicks = 0
    _ = doc.AddEventListener(node("d"), "close", { e in events.append("close") })
    _ = doc.AddEventListener(node("d"), "cancel", { e in events.append("cancel") })
    _ = doc.AddEventListener(node("other"), "click", { e in otherClicks += 1 })
    _ = doc.AddEventListener(node("p"), "toggle", { e in events.append("toggle") })
    _ = doc.AddEventListener(node("req"), "invalid", { e in events.append("invalid") })
    var submitted = 0
    view.OnSubmit { s in submitted += 1 }
    check(view.BoxFor(node("d")) == nil, "a closed dialog shows nothing")
    let otherBounds = view.BoundsOf(node("other"))!
    click("open")
    let d = view.BoundsOf(node("d"))!
    check(abs(d.X - 148) < 2 && abs(d.Y - 118) < 2, "commandfor show-modal opens it, centered in the viewport (got \(d))")
    check(view.FocusedElement === node("di"), "and focuses the first control in it")
    var px = [uint8](repeating: 0, count: 400 * 300 * 4)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    check(pixelAt(px, 400, 390, 290).R < 250, "its ::backdrop dims the page")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(otherBounds.X + 2, otherBounds.Y + 2))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(otherBounds.X + 2, otherBounds.Y + 2))))
    check(otherClicks == 0 && view.BoxFor(node("d")) != nil, "the page behind a modal dialog is inert")
    _ = view.Handle(.keyDown(web.Key(Key: "Tab", Code: "Tab")))
    _ = view.Handle(.keyDown(web.Key(Key: "Tab", Code: "Tab")))
    check(view.FocusedElement === node("di") || view.FocusedElement === node("ok"), "Tab stays inside it")
    _ = view.Handle(.keyDown(web.Key(Key: "Escape", Code: "Escape")))
    check(view.BoxFor(node("d")) == nil && events == ["cancel", "close"], "Escape cancels and closes it (got \(events))")
    click("open")
    click("ok")
    check(view.BoxFor(node("d")) == nil && view.ReturnValue(of: node("d")) == "yes", "a form method=dialog closes it with the button's value")
    events = []
    click("pb")
    check(view.BoxFor(node("p")) != nil && view.IsPopoverOpen(node("p")), "popovertarget shows a popover")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(390, 290))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(390, 290))))
    check(view.BoxFor(node("p")) == nil && events == ["toggle", "toggle"], "a click outside closes an auto popover (got \(events))")
    events = []
    click("go")
    check(submitted == 0 && events == ["invalid"] && view.FocusedElement === node("req"), "a required field left empty stops the submit, fires invalid and takes focus")
    _ = view.Handle(.text("x"))
    click("go")
    check(submitted == 1, "filled in, the form is sent")
}

@MainActor
func testDragAndDrop() {
    print("Drag and drop, pointer types")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 300))
    view.LoadHTML("""
    <style>body { margin: 0 } div { height: 40px }</style>
    <div id=src draggable=true style="width: 60px">drag me</div>
    <div id=dst style="width: 100px"></div><div id=no style="width: 100px"></div>
    """)
    let doc = view.Document!
    func node(_ id: string) -> html.Node { return view.QuerySelector("#" + id)! }
    var log: [string] = []
    var dropped = ""
    var clicks = 0
    var kind = ""
    _ = doc.AddEventListener(node("src"), "dragstart", { e in
        log.append("dragstart")
        if let d = e as? dom.DragEvent { d.Data.SetData("text/plain", "hello") }
    })
    _ = doc.AddEventListener(node("src"), "dragend", { e in log.append("dragend") })
    _ = doc.AddEventListener(node("src"), "click", { e in clicks += 1 })
    _ = doc.AddEventListener(node("src"), "pointerdown", { e in if let p = e as? dom.PointerEvent { kind = p.PointerType + " \(p.Pressure)" } })
    _ = doc.AddEventListener(node("dst"), "dragenter", { e in log.append("enter") })
    _ = doc.AddEventListener(node("dst"), "dragover", { e in e.PreventDefault() })
    _ = doc.AddEventListener(node("dst"), "dragleave", { e in log.append("leave") })
    _ = doc.AddEventListener(node("dst"), "drop", { e in
        log.append("drop")
        if let d = e as? dom.DragEvent { dropped = d.Data.GetData("text") }
    })
    var pen = web.Pointer(draw.Point(10, 10))
    pen.Kind = "pen"
    pen.Pressure = 0.8
    _ = view.Handle(.pointerDown(pen))
    check(kind == "pen 0.8", "a pointer event says what pointed, and how hard (got \(kind))")
    _ = view.Handle(.pointerMoved(draw.Point(12, 11)))
    check(log.isEmpty, "a small move is no drag")
    _ = view.Handle(.pointerMoved(draw.Point(20, 60)))
    _ = view.Handle(.pointerMoved(draw.Point(30, 62)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(30, 62))))
    check(log == ["dragstart", "enter", "drop", "dragend"] && dropped == "hello", "a drag carries its data to a target that takes it (got \(log) '\(dropped)')")
    check(clicks == 0, "and the press is no click")
    log = []
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(10, 10))))
    _ = view.Handle(.pointerMoved(draw.Point(20, 100)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(20, 100))))
    check(log == ["dragstart", "dragend"], "a target that doesn't take it gets no drop (got \(log))")
    log = []
    let taken = view.DropFiles(["/tmp/a.txt"], at: draw.Point(10, 60))
    check(taken && log == ["enter", "drop"], "files from outside drop the same way (got \(log))")
}

@MainActor
func testInputTypes() {
    print("number, date and time, color and file inputs")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 400))
    view.LoadHTML("""
    <style>body { margin: 0 } input { display: block; width: 150px; height: 20px; border: 0; padding: 0; margin: 0 }</style>
    <input id=n type=number value=5 step=2 max=8>
    <input id=d type=date value=2026-02-28><input id=t type=time value=23:59><input id=m type=month value=2026-12>
    <input id=dt type=datetime-local value=2026-12-31T23:59><input id=bad type=date value=2026-13-01>
    <input id=c type=color value=#ff0000><input id=f type=file>
    """)
    func node(_ id: string) -> html.Node { return view.QuerySelector("#" + id)! }
    func key(_ id: string, _ code: string) {
        view.Focus(node(id))
        _ = view.Handle(.keyDown(web.Key(Key: code, Code: code)))
    }
    key("n", "ArrowUp")
    check(view.ValueOf(node("n")) == "7", "ArrowUp steps a number by its step (got \(view.ValueOf(node("n"))))")
    key("n", "ArrowUp")
    check(view.ValueOf(node("n")) == "8", "and stops at max (got \(view.ValueOf(node("n"))))")
    let nb = view.BoundsOf(node("n"))!
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(nb.X + nb.Width - 4, nb.Y + nb.Height - 3))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(nb.X + nb.Width - 4, nb.Y + nb.Height - 3))))
    check(view.ValueOf(node("n")) == "6", "the spinner's lower half steps down (got \(view.ValueOf(node("n"))))")
    key("d", "ArrowUp")
    key("t", "ArrowUp")
    key("m", "ArrowUp")
    key("dt", "ArrowUp")
    check(view.ValueOf(node("d")) == "2026-03-01" && view.ValueOf(node("t")) == "00:00" && view.ValueOf(node("m")) == "2027-01" && view.ValueOf(node("dt")) == "2027-01-01T00:00",
          "the arrow keys step a date, a time, a month and a date-time across their ends (got \(view.ValueOf(node("d"))) \(view.ValueOf(node("t"))) \(view.ValueOf(node("m"))) \(view.ValueOf(node("dt"))))")
    check(view.ValueOf(node("bad")) == "", "a date that isn't one is no value")
    var picked = ""
    var changes = 0
    view.OnPickColor { n, current in picked = current }
    _ = view.Document!.AddEventListener(node("c"), "change", { e in changes += 1 })
    let cb = view.BoundsOf(node("c"))!
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(cb.X + 5, cb.Y + 5))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(cb.X + 5, cb.Y + 5))))
    check(picked == "#ff0000", "a color well asks the host for a color")
    view.SetControlValue(node("c"), "#00FF00")
    check(view.ValueOf(node("c")) == "#00ff00" && changes == 1 && view.BoxFor(node("c"))!.Text == "#00ff00", "and shows what it answers, with change")
    var asked = false
    view.OnPickFiles { n, multiple, accept in asked = true }
    let fb = view.BoundsOf(node("f"))!
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(fb.X + 5, fb.Y + 5))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(fb.X + 5, fb.Y + 5))))
    view.SetFiles(node("f"), ["/tmp/notes/a.txt"])
    check(asked && view.BoxFor(node("f"))!.Text == "a.txt" && view.FilesOf(node("f")) == ["/tmp/notes/a.txt"], "a file input asks for files and shows the one chosen")
}

@MainActor
func testPointerEventsAndUserSelect() {
    print("pointer-events and user-select")
    let view = web.Page()
    view.SetViewportSize(draw.Size(400, 200))
    view.LoadHTML("""
    <body style="margin:0">
    <div id="under" style="position:absolute;left:0;top:0;width:200px;height:100px"></div>
    <div id="over" style="position:absolute;left:0;top:0;width:200px;height:100px;pointer-events:none">
      <button id="live" style="pointer-events:auto;width:50px;height:20px">x</button>
    </div>
    <p id="plain" style="position:absolute;top:120px;margin:0">select me</p>
    <p id="chrome" style="position:absolute;top:150px;margin:0;user-select:none">not me</p>
    <p id="whole" style="position:absolute;top:175px;margin:0;user-select:all">all of it</p>
    </body>
    """)
    let doc = view.Document!
    var clicked: [string] = []
    for id in ["under", "over", "live"] {
        _ = doc.AddEventListener(view.QuerySelector("#" + id)!, "click", { e in
            if let t = e.CurrentTarget?.GetAttribute("id"), t == id { clicked.append(id) }
        })
    }
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(150, 60))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(150, 60))))
    check(clicked == ["under"], "a click passes through pointer-events: none to what is under it (got \(clicked))")
    clicked = []
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(10, 5))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(10, 5))))
    check(clicked.first == "live", "and reaches what inside it sets auto again (got \(clicked))")

    // A drag over text selects it; not where user-select is none.
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(2, 128))))
    _ = view.Handle(.pointerMoved(draw.Point(40, 128)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(40, 128))))
    check(view.HasSelection, "a drag over text selects it (\(view.SelectedText()))")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(2, 158))))
    _ = view.Handle(.pointerMoved(draw.Point(40, 158)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(40, 158))))
    check(!view.HasSelection, "but not text where user-select is none ('\(view.SelectedText())')")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(20, 182))))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(20, 182))))
    check(view.SelectedText() == "all of it", "and a press in user-select: all selects the whole element ('\(view.SelectedText())')")
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

// Images a page defers are decoded off the main thread by LoadImages,
// and given to the page, which is the main actor's.
@MainActor
func testDeferredImages() async {
    print("Deferred images")
    var red = image.RGBA(width: 2, height: 2)
    var i = 0
    while i < red.Pixels.count {
        red.Pixels[i] = i % 4 == 0 || i % 4 == 3 ? 255 : 0
        i += 1
    }
    let bytes = png.Encode(red)
    let junk: [uint8] = [1, 2, 3]
    let page = web.Page(configuration: web.Config(baseURL: "/site/", fetcher: fetch.Fetcher({ url in
        url.hasSuffix("red.png") ? bytes : (url.hasSuffix("junk.png") ? junk : nil)
    }), defersImages: true))
    page.SetViewportSize(draw.Size(20, 20))
    page.LoadHTML("<body style='margin:0'><img src=red.png style='width:10px;height:10px;display:block'><img src=junk.png></body>")
    check(page.PendingImages.count == 2, "loading leaves the images for LoadImages (\(page.PendingImages.count))")
    var px = [uint8](repeating: 0, count: 20 * 20 * 4)
    page.Draw(into: &px, width: 20, height: 20, scale: 1)
    check(pixelAt(px, 20, 5, 5) != draw.Color(255, 0, 0), "and draws none of them before")
    let failed = await page.LoadImages()
    check(failed.count == 1 && failed[0].hasSuffix("junk.png"), "LoadImages answers the one that didn't decode (\(failed))")
    check(page.PendingImages.isEmpty, "and leaves nothing pending")
    page.Draw(into: &px, width: 20, height: 20, scale: 1)
    check(pixelAt(px, 20, 5, 5) == draw.Color(255, 0, 0), "the decoded image draws")
}

// An <img> naming an SVG file draws it as a vector, at its own size or
// the size CSS gives, with its own colors whatever the page's fill is;
// loaded at once or deferred.
@MainActor
func testSVGImages() async {
    print("SVG images")
    let file = "<?xml version='1.0'?>\n<!-- a logo -->\n<svg xmlns='http://www.w3.org/2000/svg' width='8' height='4' viewBox='0 0 8 4'><rect width='8' height='4' fill='#00f'/></svg>"
    let bytes = Array(file.utf8)
    for defers in [false, true] {
        let page = web.Page(configuration: web.Config(baseURL: "/site/", fetcher: fetch.Fetcher({ url in
            url.hasSuffix("logo.svg") ? bytes : nil
        }), defersImages: defers))
        page.SetViewportSize(draw.Size(40, 20))
        page.LoadHTML("<body style='margin:0;fill:red'><img src=logo.svg style='display:block'><img src=logo.svg style='width:32px;height:16px;display:block'></body>")
        let failed = await page.LoadImages()
        let how = defers ? "deferred" : "at once"
        check(failed.isEmpty, "\(how): the SVG file decodes (\(failed))")
        var px = [uint8](repeating: 0, count: 40 * 20 * 4)
        page.Draw(into: &px, width: 40, height: 20, scale: 1)
        check(pixelAt(px, 40, 4, 2) == draw.Color(0, 0, 255), "\(how): it draws in its own fill, not the page's")
        check(pixelAt(px, 40, 12, 2) != draw.Color(0, 0, 255), "\(how): at its own width, 8px")
        check(pixelAt(px, 40, 30, 12) == draw.Color(0, 0, 255), "\(how): and scaled where CSS sizes it")
    }
}

@MainActor
func testRange() {
    print("Range inputs and pointer events")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 120))
    view.LoadHTML("""
    <style>body { margin: 0 } input { position: absolute; left: 10px; top: 10px; width: 116px; height: 20px; accent-color: rgb(200, 20, 20) }
    #pad { position: absolute; left: 10px; top: 60px; width: 100px; height: 40px }</style>
    <input type=range id=r min=0 max=10 value=3><div id=pad></div>
    """)
    var pixels = [uint8](repeating: 0, count: 300 * 120 * 4)
    view.Draw(into: &pixels, width: 300, height: 120, scale: 1)
    let doc = view.Document!
    let r = view.QuerySelector("#r")!
    var inputs: [string] = []
    var changes = 0
    _ = doc.AddEventListener(r, "input", { e in if let i = e as? dom.InputEvent { inputs.append(i.Value) } })
    _ = doc.AddEventListener(r, "change", { _ in changes += 1 })
    check(view.ValueOf(r) == "3", "a range starts at its value")
    // The track runs from 8px in (half the 16px thumb) to 8px from the end:
    // 100px for 0…10.
    let filled = pixelAt(pixels, 300, 30, 20)
    check(filled.R > 150 && filled.G < 80, "the track's filled part is in the accent color (got \(filled))")
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(18 + 70, 20))))
    check(view.ValueOf(r) == "7" && inputs.last == "7", "pressing on the track jumps there (got \(view.ValueOf(r)))")
    _ = view.Handle(.pointerMoved(draw.Point(18 + 100, 20)))
    check(view.ValueOf(r) == "10", "dragging moves it, past the end it stops at max (got \(view.ValueOf(r)))")
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(18 + 100, 20))))
    check(changes == 1, "letting go is one change event")
    _ = view.Handle(.keyDown(web.Key(Key: "ArrowLeft", Code: "ArrowLeft")))
    check(view.ValueOf(r) == "9" && changes == 2, "the arrow keys step it")
    // Pointer events with coordinates, captured for the press.
    let pad = view.QuerySelector("#pad")!
    var trail: [string] = []
    _ = doc.AddEventListener(pad, "pointerdown", { e in
        if let m = e as? dom.MouseEvent { trail.append("down \(Int(m.X))") }
        e.PreventDefault()
    })
    _ = doc.AddEventListener(pad, "pointermove", { e in if let m = e as? dom.MouseEvent, m.Pressed { trail.append("move \(Int(m.X))") } })
    _ = doc.AddEventListener(pad, "pointerup", { e in if let m = e as? dom.MouseEvent { trail.append("up \(Int(m.X))") } })
    _ = view.Handle(.pointerDown(web.Pointer(draw.Point(20, 80))))
    _ = view.Handle(.pointerMoved(draw.Point(250, 10)))
    _ = view.Handle(.pointerUp(web.Pointer(draw.Point(250, 10))))
    check(trail == ["down 20", "move 250", "up 250"], "a press's moves and release reach the element it began on, outside it too (got \(trail))")
    var wheel: float32 = 0
    _ = doc.AddEventListener(pad, "wheel", { e in if let w = e as? dom.WheelEvent { wheel = w.DeltaY } })
    _ = view.Handle(.pointerMoved(draw.Point(30, 80)))
    _ = view.Handle(.wheel(web.Wheel(draw.Point(0, -1))))
    check(wheel == 40, "the wheel reaches the element under the pointer (got \(wheel))")
}

@MainActor
func testStacking() {
    print("Hit testing follows paint order")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 200))
    view.LoadHTML("""
    <style>body { margin: 0 } .fill { position: absolute; left: 0; top: 0; right: 0; bottom: 0 }
    #raised { z-index: 5 }</style>
    <div class=fill id=under><div class=fill id=inner></div></div>
    <div class=fill id=over><button id=b style="position: absolute; left: 10px; top: 10px; width: 50px; height: 20px">ok</button></div>
    """)
    var pixels = [uint8](repeating: 0, count: 300 * 200 * 4)
    view.Draw(into: &pixels, width: 300, height: 200, scale: 1)
    check(view.ElementAt(draw.Point(100, 100))?.Id == view.QuerySelector("#over")!.Id, "of two positioned siblings, the later one is on top")
    check(view.ElementAt(draw.Point(20, 15))?.Id == view.QuerySelector("#b")!.Id, "and what is in it takes the click")
}

@MainActor
func testCompositing() {
    print("clip-path, mask-image, mix-blend-mode, isolation, backdrop-filter")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 120))
    view.LoadHTML("""
    <style>
    body { margin: 0; background: white }
    div { position: absolute; width: 40px; height: 40px }
    .in { position: static }
    </style>
    <div style="left: 0; top: 0; background: rgb(255,0,0); clip-path: circle(50%)"></div>
    <div style="left: 50px; top: 0; background: rgb(0,0,255); -webkit-clip-path: inset(10px round 5px)"></div>
    <div style="left: 100px; top: 0; background: rgb(0,128,0); clip-path: polygon(0 0, 100% 0, 0 100%)"></div>
    <div style="left: 150px; top: 0; background: black; mask-image: linear-gradient(to right, black, transparent)"></div>
    <div style="left: 200px; top: 0; background: rgb(0,0,255); clip-path: ellipse(closest-side 10px at 20px 20px)"></div>
    <div style="left: 0; top: 60px; background: rgb(255,255,0)"><div class=in style="background: rgb(0,255,255); mix-blend-mode: multiply"></div></div>
    <div style="left: 50px; top: 60px; background: rgb(255,0,0)"><div class=in style="background: white; mix-blend-mode: difference"></div></div>
    <div style="left: 100px; top: 60px; background: linear-gradient(to right, black 50%, white 50%)"></div>
    <div style="left: 100px; top: 60px; backdrop-filter: blur(4px)"></div>
    <div style="left: 150px; top: 60px; background: rgb(255,255,0)"><div class=in style="isolation: isolate"><div class=in style="background: rgb(0,255,255); mix-blend-mode: multiply"></div></div></div>
    """)
    var px = [uint8](repeating: 0, count: 300 * 120 * 4)
    view.Draw(into: &px, width: 300, height: 120, scale: 1)
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 300, x, y) }
    let white = draw.Color(255, 255, 255)
    check(at(20, 20) == draw.Color(255, 0, 0) && at(2, 2) == white && at(37, 37) == white,
          "clip-path: circle() keeps the circle (got \(at(20, 20)) \(at(2, 2)))")
    check(at(70, 20) == draw.Color(0, 0, 255) && at(52, 20) == white && at(70, 5) == white && at(60, 10) == white,
          "inset() with round cuts the sides and the corners (got \(at(70, 20)) \(at(52, 20)) \(at(60, 10)))")
    check(at(105, 5) == draw.Color(0, 128, 0) && at(135, 35) == white,
          "polygon() keeps the triangle (got \(at(105, 5)) \(at(135, 35)))")
    check(at(152, 20).R < 30 && at(188, 20).R > 225 && at(170, 20).R > 90 && at(170, 20).R < 170,
          "mask-image: a gradient fades the box out (got \(at(152, 20)) \(at(170, 20)) \(at(188, 20)))")
    check(at(220, 20) == draw.Color(0, 0, 255) && at(220, 5) == white && at(201, 20) == draw.Color(0, 0, 255),
          "ellipse() with closest-side and a length (got \(at(220, 5)) \(at(201, 20)))")
    check(at(20, 80) == draw.Color(0, 255, 0), "mix-blend-mode: multiply (got \(at(20, 80)))")
    check(at(70, 80) == draw.Color(0, 255, 255), "mix-blend-mode: difference (got \(at(70, 80)))")
    let left = at(118, 80)
    let right = at(121, 80)
    check(left.R > 40 && left.R < 200 && right.R > 60 && right.R < 215 && at(110, 80).R < 40 && at(130, 80).R > 215,
          "backdrop-filter: blur() blurs what is behind, inside the box (got \(left) \(right) \(at(110, 80)) \(at(130, 80)))")
    check(at(170, 80) == draw.Color(0, 255, 255), "isolation: isolate keeps a blend inside its group (got \(at(170, 80)))")

    // path(), shape(), a geometry box, and clicks.
    let more = web.Page()
    more.SetViewportSize(draw.Size(200, 60))
    more.LoadHTML("""
    <style>body { margin: 0; background: white } div { position: absolute; top: 0; width: 40px; height: 40px }</style>
    <div id=p style="left: 0; background: rgb(255,0,0); clip-path: path('M 0 0 L 40 0 L 0 40 Z')"></div>
    <div id=s style="left: 50px; background: rgb(0,0,255); clip-path: shape(from 0 0, line to 100% 0, line to 0 100%, close)"></div>
    <div id=c style="left: 100px; background: rgb(0,128,0); padding: 10px; border-radius: 30px; clip-path: content-box"></div>
    """)
    var mp = [uint8](repeating: 0, count: 200 * 60 * 4)
    more.Draw(into: &mp, width: 200, height: 60, scale: 1)
    func m(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(mp, 200, x, y) }
    check(m(5, 5) == draw.Color(255, 0, 0) && m(35, 35) == draw.Color(255, 255, 255), "path() keeps its triangle (got \(m(5, 5)) \(m(35, 35)))")
    check(m(55, 5) == draw.Color(0, 0, 255) && m(85, 35) == draw.Color(255, 255, 255), "shape() with percentages (got \(m(55, 5)) \(m(85, 35)))")
    check(m(130, 30) == draw.Color(0, 128, 0) && m(105, 30) == draw.Color(255, 255, 255), "a geometry box alone clips to that box (got \(m(130, 30)) \(m(105, 30)))")
    check(more.ElementAt(draw.Point(5, 5))?.GetAttribute("id") == "p" && more.ElementAt(draw.Point(35, 35))?.GetAttribute("id") != "p",
          "a click outside the clip-path passes through")

    // mask-size, -position, -repeat, -mode.
    let mk = web.Page()
    mk.SetViewportSize(draw.Size(100, 40))
    mk.LoadHTML("""
    <style>body { margin: 0; background: white } div { position: absolute; top: 0; width: 40px; height: 40px; background: rgb(255,0,0) }</style>
    <div style="left: 0; mask: linear-gradient(black, black) center / 20px 20px no-repeat"></div>
    <div style="left: 50px; mask-image: linear-gradient(to right, white, black); mask-mode: luminance"></div>
    """)
    var kp = [uint8](repeating: 0, count: 100 * 40 * 4)
    mk.Draw(into: &kp, width: 100, height: 40, scale: 1)
    func k(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(kp, 100, x, y) }
    check(k(20, 20) == draw.Color(255, 0, 0) && k(5, 5) == draw.Color(255, 255, 255) && k(35, 20) == draw.Color(255, 255, 255),
          "mask-size and mask-position place one tile, no-repeat (got \(k(20, 20)) \(k(5, 5)) \(k(35, 20)))")
    check(k(52, 20).G < 40 && k(88, 20).G > 215, "mask-mode: luminance keeps what is bright (got \(k(52, 20)) \(k(88, 20)))")
    // An SVG mask from a percent-encoded data: URL: a circle.
    let sv = web.Page()
    sv.SetViewportSize(draw.Size(40, 40))
    sv.LoadHTML("<body style='margin:0;background:white'><div style='width:40px;height:40px;background:rgb(255,0,0);mask-image:url(\"data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 width=%2740%27 height=%2740%27%3E%3Ccircle cx=%2720%27 cy=%2720%27 r=%2715%27/%3E%3C/svg%3E\")'></div></body>")
    var sp2 = [uint8](repeating: 0, count: 40 * 40 * 4)
    sv.Draw(into: &sp2, width: 40, height: 40, scale: 1)
    check(pixelAt(sp2, 40, 20, 20) == draw.Color(255, 0, 0) && pixelAt(sp2, 40, 2, 2) == draw.Color(255, 255, 255),
          "an SVG mask image, from a data: URL (got \(pixelAt(sp2, 40, 20, 20)) \(pixelAt(sp2, 40, 2, 2)))")
}

@MainActor
func testBorderImage() {
    print("border-image")
    let view = web.Page()
    view.SetViewportSize(draw.Size(260, 70))
    view.LoadHTML("""
    <style>
    body { margin: 0; background: white }
    div { position: absolute; top: 10px; width: 20px; height: 20px; border: 10px solid rgb(255,0,0) }
    </style>
    <div style="left: 0; border-image: linear-gradient(rgb(0,0,255), rgb(0,0,255)) 10"></div>
    <div style="left: 50px; border-image: linear-gradient(rgb(0,128,0), rgb(0,128,0)) 10 fill"></div>
    <div style="left: 100px; border-image: url(missing.png) 10"></div>
    <div style="left: 150px; border-image: linear-gradient(rgb(0,0,255), rgb(0,0,255)) 10 / 10px / 5px round"></div>
    <div style="left: 200px; border-image-source: linear-gradient(to right, rgb(0,0,0), rgb(255,255,255)); border-image-slice: 25%"></div>
    """)
    var px = [uint8](repeating: 0, count: 260 * 70 * 4)
    view.Draw(into: &px, width: 260, height: 70, scale: 1)
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 260, x, y) }
    let white = draw.Color(255, 255, 255)
    check(at(5, 15) == draw.Color(0, 0, 255) && at(20, 30) == white,
          "a gradient border image takes the border's place, the middle left empty (got \(at(5, 15)) \(at(20, 30)))")
    check(at(70, 30) == draw.Color(0, 128, 0), "fill draws the middle (got \(at(70, 30)))")
    check(at(105, 15) == draw.Color(255, 0, 0), "an image that isn't loaded leaves the border's own style (got \(at(105, 15)))")
    check(at(147, 30) == draw.Color(0, 0, 255) && at(143, 30) == white, "border-image-outset draws outside the box (got \(at(147, 30)) \(at(143, 30)))")
    // The 40px gradient cut at 10px: the left edge is the darkest part.
    check(at(205, 30).R < 64 && at(254, 30).R > 190, "the longhands cut a gradient into slices (got \(at(205, 30)) \(at(254, 30)))")
}

@MainActor
func testColumnsPaint() {
    print("Multi-column painting")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 100))
    view.LoadHTML("""
    <body style="margin: 0; background: white">
    <div style="width: 300px; column-count: 2; column-gap: 20px; column-rule: 4px solid rgb(255,0,0); font-size: 16px; line-height: 20px">
    <p id=p style="margin: 0">alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu</p>
    </div>
    </body>
    """)
    var px = [uint8](repeating: 0, count: 300 * 100 * 4)
    view.Draw(into: &px, width: 300, height: 100, scale: 1)
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 300, x, y) }
    check(at(150, 5) == draw.Color(255, 0, 0) && at(140, 5) != draw.Color(255, 0, 0), "column-rule runs down the middle of the gap (got \(at(150, 5)) \(at(140, 5)))")
    check(countDark(px, 300, draw.IRect(160, 0, 140, 40)) > 20, "the text goes on in the second column")
    check(view.ElementAt(draw.Point(170, 10))?.GetAttribute("id") == "p", "a click on text in the second column lands on its paragraph")
}

@MainActor
func testRightToLeftPaint() {
    print("Right-to-left painting")
    let view = web.Page()
    view.SetViewportSize(draw.Size(300, 40))
    view.LoadHTML("""
    <body style="margin: 0; background: white; font-size: 16px">
    <p dir=rtl style="margin: 0">שלום עולם</p>
    </body>
    """)
    var px = [uint8](repeating: 0, count: 300 * 40 * 4)
    view.Draw(into: &px, width: 300, height: 40, scale: 1)
    check(countDark(px, 300, draw.IRect(200, 0, 100, 25)) > 20 && countDark(px, 300, draw.IRect(0, 0, 150, 25)) == 0,
          "Hebrew in a dir=rtl paragraph is drawn at the right")
}

@MainActor
func testFixed() {
    print("position: fixed and background-attachment: fixed")
    let view = web.Page()
    view.SetViewportSize(draw.Size(200, 100))
    view.LoadHTML("""
    <body style="margin: 0; background: white">
    <div id=bar style="position: fixed; top: 0; left: 0; width: 200px; height: 10px; background: rgb(255,0,0)"></div>
    <div style="height: 1000px"></div>
    </body>
    """)
    view.SetScrollOffset(draw.Point(0, 300))
    var px = [uint8](repeating: 0, count: 200 * 100 * 4)
    view.Draw(into: &px, width: 200, height: 100, scale: 1)
    check(pixelAt(px, 200, 50, 5) == draw.Color(255, 0, 0), "a fixed box stays at the top of the viewport when the page scrolls (got \(pixelAt(px, 200, 50, 5)))")
    check(view.ElementAt(draw.Point(50, 5))?.GetAttribute("id") == "bar", "and takes clicks there")
    // Inside a transformed box, a fixed box is placed against that box
    // and scrolls with it.
    let inT = web.Page()
    inT.SetViewportSize(draw.Size(200, 100))
    inT.LoadHTML("<body style='margin:0;background:white'><div style='transform:translate(0,0)'><div style='position:fixed;top:0;left:0;width:200px;height:10px;background:rgb(0,0,255)'></div></div><div style='height:1000px'></div></body>")
    inT.SetScrollOffset(draw.Point(0, 300))
    var tp = [uint8](repeating: 0, count: 200 * 100 * 4)
    inT.Draw(into: &tp, width: 200, height: 100, scale: 1)
    check(pixelAt(tp, 200, 50, 5) == draw.Color(255, 255, 255), "a transformed ancestor holds a fixed box, which scrolls with it (got \(pixelAt(tp, 200, 50, 5)))")

    // background-attachment: fixed stays with the viewport; local moves
    // with a scroll container's content.
    let att = web.Page()
    att.SetViewportSize(draw.Size(200, 100))
    att.LoadHTML("""
    <body style="margin: 0; background: white">
    <div style="height: 1000px; background: linear-gradient(rgb(255,0,0) 50%, rgb(0,0,255) 50%) fixed"></div>
    </body>
    """)
    att.SetScrollOffset(draw.Point(0, 400))
    var ap = [uint8](repeating: 0, count: 200 * 100 * 4)
    att.Draw(into: &ap, width: 200, height: 100, scale: 1)
    check(pixelAt(ap, 200, 50, 10) == draw.Color(255, 0, 0) && pixelAt(ap, 200, 50, 90) == draw.Color(0, 0, 255),
          "a fixed background is laid over the viewport, wherever the page is scrolled (got \(pixelAt(ap, 200, 50, 10)) \(pixelAt(ap, 200, 50, 90)))")

    let still = web.Page()
    still.SetViewportSize(draw.Size(200, 100))
    still.LoadHTML("<body style='margin:0;background:white'><div style='height:10px;background:rgb(255,0,0)'></div><div style='height:1000px'></div></body>")
    still.SetScrollOffset(draw.Point(0, 300))
    var sp = [uint8](repeating: 0, count: 200 * 100 * 4)
    still.Draw(into: &sp, width: 200, height: 100, scale: 1)
    check(pixelAt(sp, 200, 50, 5) == draw.Color(255, 255, 255), "a box in the flow scrolls away (got \(pixelAt(sp, 200, 50, 5)))")
}

@MainActor
func testTextClip() {
    print("background-clip: text and text-fill-color")
    let view = web.Page()
    view.SetViewportSize(draw.Size(200, 60))
    view.LoadHTML("""
    <body style="margin: 0; background: white">
    <div id=t style="font: bold 40px sans-serif; background: rgb(0,0,255); background-clip: text; -webkit-text-fill-color: transparent; width: 200px">MMMM</div>
    </body>
    """)
    var px = [uint8](repeating: 0, count: 200 * 60 * 4)
    view.Draw(into: &px, width: 200, height: 60, scale: 1)
    var blue = 0
    var other = 0
    var y: int32 = 0
    while y < 60 {
        var x: int32 = 0
        while x < 200 {
            let c = pixelAt(px, 200, x, y)
            if c.B > 200 && c.R < 60 { blue += 1 } else if !(c.R > 200 && c.G > 200 && c.B > 200) && !(c.B > c.R) { other += 1 }
            x += 1
        }
        y += 1
    }
    check(blue > 400 && pixelAt(px, 200, 199, 59) == draw.Color(255, 255, 255), "the background shows through the letters alone (\(blue) blue pixels)")
    check(other == 0, "and the transparent fill leaves no text color over it (\(other) other pixels)")
}

@MainActor
func testGradientLengths() {
    print("Gradient stops at lengths")
    let view = web.Page()
    view.SetViewportSize(draw.Size(100, 60))
    view.LoadHTML("""
    <body style="margin: 0; background: white">
    <div style="height: 20px; background: linear-gradient(to right, rgb(255,0,0) 20px, rgb(0,0,255) 20px)"></div>
    <div style="height: 20px; background: linear-gradient(to right, rgb(255,0,0) calc(100% - 10px), rgb(0,0,255) calc(100% - 10px))"></div>
    <div style="height: 20px; background: radial-gradient(circle 50px at 0 0, rgb(255,0,0) 10px, rgb(0,0,255) 10px)"></div>
    </body>
    """)
    var px = [uint8](repeating: 0, count: 100 * 60 * 4)
    view.Draw(into: &px, width: 100, height: 60, scale: 1)
    func at(_ x: int32, _ y: int32) -> draw.Color { return pixelAt(px, 100, x, y) }
    let red = draw.Color(255, 0, 0)
    let blue = draw.Color(0, 0, 255)
    check(at(10, 10) == red && at(30, 10) == blue, "a stop at 20px is 20 pixels along (got \(at(10, 10)) \(at(30, 10)))")
    check(at(85, 30) == red && at(95, 30) == blue, "calc(100% - 10px) is 10 pixels from the end (got \(at(85, 30)) \(at(95, 30)))")
    check(at(3, 43) == red && at(20, 55) == blue, "a radial stop at 10px is 10 pixels out (got \(at(3, 43)) \(at(20, 55)))")
    // At two device pixels to a CSS pixel, the lengths scale too.
    var px2 = [uint8](repeating: 0, count: 200 * 120 * 4)
    view.Draw(into: &px2, width: 200, height: 120, scale: 2)
    // Interpolation in a color space.
    let iv = web.Page()
    iv.SetViewportSize(draw.Size(101, 30))
    iv.LoadHTML("""
    <body style="margin: 0; background: white">
    <div style="height: 10px; background: linear-gradient(to right in oklab, rgb(255,0,0), rgb(0,0,255))"></div>
    <div style="height: 10px; background: color-mix(in oklab, rgb(255,0,0), rgb(0,0,255))"></div>
    <div style="height: 10px; background: linear-gradient(to right in hsl longer hue, rgb(255,0,0), rgb(0,0,255))"></div>
    </body>
    """)
    var ip = [uint8](repeating: 0, count: 101 * 30 * 4)
    iv.Draw(into: &ip, width: 101, height: 30, scale: 1)
    let mid = pixelAt(ip, 101, 50, 5)
    let mix = pixelAt(ip, 101, 50, 15)
    check(abs(int(mid.R) - int(mix.R)) <= 3 && abs(int(mid.G) - int(mix.G)) <= 3 && abs(int(mid.B) - int(mix.B)) <= 3 && (mid.G > 20 || mid.R != 127),
          "a gradient in oklab is color-mix(in oklab) halfway (got \(mid), mix \(mix))")
    let hue = pixelAt(ip, 101, 50, 25)
    check(hue.G > 200 && hue.R < 60 && hue.B < 60, "in hsl longer hue goes round through green (got \(hue))")
    check(pixelAt(px2, 200, 36, 20) == red && pixelAt(px2, 200, 44, 20) == blue, "and at scale 2, 40 device pixels along (got \(pixelAt(px2, 200, 36, 20)) \(pixelAt(px2, 200, 44, 20)))")
}

@MainActor
func testImageSet() {
    print("image-set()")
    let view = web.Page()
    view.SetViewportSize(draw.Size(40, 20))
    view.LoadHTML("""
    <body style="margin: 0; background: white">
    <div style="width: 20px; height: 20px; background: image-set(url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGP4z8AARwzEcQCukw/x0F8jngAAAABJRU5ErkJggg==) 1x, url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEElEQVR4nGNgYPiPAw0pCQCpcD/BFMrqcwAAAABJRU5ErkJggg==) 2x) no-repeat"></div>
    </body>
    """)
    var px = [uint8](repeating: 0, count: 40 * 20 * 4)
    view.Draw(into: &px, width: 40, height: 20, scale: 1)
    check(pixelAt(px, 40, 2, 2) == draw.Color(0, 0, 255) && pixelAt(px, 40, 6, 6) == draw.Color(255, 255, 255),
          "the 2x candidate is chosen and drawn at half its pixel size (got \(pixelAt(px, 40, 2, 2)) \(pixelAt(px, 40, 6, 6)))")
}

@MainActor
func testTypedAttr() {
    print("Typed attr()")
    let view = web.Page()
    view.SetViewportSize(draw.Size(200, 100))
    view.LoadHTML("""
    <style>
    .bar { height: 10px; width: attr(data-w px, 5px); background: attr(data-color type(<color>), black) }
    .label::after { content: attr(data-n) }
    </style>
    <div id=a class=bar data-w=120 data-color="rgb(0, 128, 0)"></div>
    <div id=b class=bar></div>
    <div id=c style="width: attr(data-pct %); height: 10px" data-pct=50></div>
    """)
    check(view.BoxFor(view.QuerySelector("#a")!)!.Width == 120, "attr(data-w px) is a length (got \(view.BoxFor(view.QuerySelector("#a")!)!.Width))")
    check(view.BoxFor(view.QuerySelector("#a")!)!.Style.BackgroundColor == draw.Color(0, 128, 0), "attr(… type(<color>)) parses the value as a color")
    check(view.BoxFor(view.QuerySelector("#b")!)!.Width == 5 && view.BoxFor(view.QuerySelector("#b")!)!.Style.BackgroundColor == draw.Color(0, 0, 0),
          "a missing attribute takes the fallback")
    check(view.BoxFor(view.QuerySelector("#c")!)!.Width == 92, "attr(… %) in an inline style is a percentage of the 184px body (got \(view.BoxFor(view.QuerySelector("#c")!)!.Width))")
    view.Document!.ElementFor(view.QuerySelector("#a")!).SetAttribute("data-w", "30")
    check(view.BoxFor(view.QuerySelector("#a")!)!.Width == 30, "changing the attribute restyles (got \(view.BoxFor(view.QuerySelector("#a")!)!.Width))")
}

func main() async -> int32 {
    testStacking()
    testTextFeatures()
    testPageInput()
    testJournal()
    testEvents()
    testEventModel()
    testCursors()
    testTransforms()
    testAnimations()
    testContainerQueries()
    testFrames()
    testFocusVisibleAndTarget()
    testPseudoElements()
    testDecorations()
    testGridAreasAndLogical()
    testTextWrap()
    testScrollbarsZoomAndContainment()
    testSmoothScrollAndSnap()
    testDialogsAndPopovers()
    testDragAndDrop()
    testInputTypes()
    testPointerEventsAndUserSelect()
    testCompositing()
    testBorderImage()
    testColumnsPaint()
    testRightToLeftPaint()
    testFixed()
    testTextClip()
    testGradientLengths()
    testImageSet()
    testTypedAttr()
    testRange()
    await testDeferredImages()
    await testSVGImages()
    if failures == 0 {
        print("ALL PAGE CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
