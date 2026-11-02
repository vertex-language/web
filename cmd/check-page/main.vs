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

func check(ok: bool, what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func pixelAt(pixels: [uint8], w: int32, x: int32, y: int32) -> draw.Color {
    let i = int((y * w + x) * 4)
    return draw.Color(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
}


func countDark(pixels: [uint8], w: int32, r: draw.IRect) -> int {
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
    func inks(y: int32, want: (draw.Color) -> bool) -> int {
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

func near(a: float32, b: float32, tolerance: float32 = 0.5) -> bool {
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
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 300, x, y) }
    check(at(110, 15) == draw.Color(255, 0, 0) && at(5, 5) == draw.Color(255, 255, 255),
          "translate() moves a box, by lengths and percentages of itself (got \(at(110, 15)))")
    check(at(20, 88) == draw.Color(0, 0, 255) && at(20, 112) == draw.Color(0, 0, 255) && at(2, 105) == draw.Color(255, 255, 255),
          "rotate() turns it about its center (got \(at(20, 88)) \(at(2, 105)))")
    check(at(235, 35) == draw.Color(0, 128, 0) && at(242, 42) == draw.Color(255, 255, 255),
          "the scale property grows it from transform-origin (got \(at(235, 35)))")
    check(at(35, 180) == draw.Color(0, 0, 0) && at(5, 180) == draw.Color(255, 255, 255),
          "the translate property moves an in-flow box, calc() and all (got \(at(35, 180)))")
    func idAt(x: float32, y: float32) -> string { return view.ElementAt(draw.Point(x, y))?.GetAttribute("id") ?? "" }
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
    func width(n: html.Node) -> float32 { return view.BoxFor(n)!.Width }
    func opacity(n: html.Node) -> float32 { return view.BoxFor(n)!.Style.Opacity }

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
    func box(id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
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
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 400, x, y) }
    func box(id: string) -> layout.Box? { return view.BoxFor(view.QuerySelector("#" + id)!) }
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
    check(vb.Replaced == .video && at(50, vy + 5) == draw.Color(255, 255, 255) && at(50, vy + 50) == draw.Color(255, 0, 255),
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
    func w(id: string) -> float32 { return view.BoxFor(view.QuerySelector("#" + id)!)!.Width }
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
    func count(c: draw.Color, r: draw.Rect) -> int {
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
    func bounds(id: string) -> draw.Rect { return view.BoundsOf(view.QuerySelector("#" + id)!)! }
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
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 400, x, y) }
    func count(c: draw.Color, x0: int32, y0: int32, x1: int32, y1: int32) -> int {
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

    // Rounded dashed, dotted and double borders follow the corner.
    view.LoadHTML("""
    <style>body { margin: 0; background: white } div { position: absolute; top: 0; width: 88px; height: 88px; border-radius: 30px }</style>
    <div style="left: 0; border: 6px dashed rgb(0, 0, 0)"></div>
    <div style="left: 120px; border: 6px dotted rgb(0, 0, 0)"></div>
    <div style="left: 240px; border: 9px double rgb(0, 0, 0)"></div>
    """)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    // Points on the top-left corner's arc, `inset` in from the edge.
    func arc(left: float32, inset: float32, degrees: float32) -> draw.Color {
        let a = degrees * float32(math.Pi) / 180
        return at(int32(left + 30 + (30 - inset) * math.Cos(a)), int32(30 + (30 - inset) * math.Sin(a)))
    }
    // Black, or nearly: the curve's edges are smoothed.
    func dark(c: draw.Color) -> bool { return c.R < 60 && c.G < 60 && c.B < 60 }
    func marked(left: float32, inset: float32) -> (ink: int, paper: int) {
        var ink = 0
        var paper = 0
        var d: float32 = 182
        while d < 268 {
            let c = arc(left, inset, d)
            if dark(c) { ink += 1 } else if c == draw.Color(255, 255, 255) { paper += 1 }
            d += 2
        }
        return (ink, paper)
    }
    let dashed = marked(0, 3)
    check(dark(arc(0, 3, 225)) && dashed.ink > 5 && dashed.paper > 5, "a rounded dashed border has a dash on the corner and gaps round it (\(dashed))")
    let dots = marked(120, 3)
    check(dark(arc(120, 3, 225)) && dots.ink > 3 && dots.paper > 5, "a rounded dotted border has dots round the corner (\(dots))")
    check(count(black, 150, 1, 210, 2) < 50, "and along its sides")
    check(dark(arc(240, 1.5, 225)) && dark(arc(240, 7.5, 225)) && arc(240, 4.5, 225) == draw.Color(255, 255, 255),
          "a rounded double border is two lines round the corner (got \(arc(240, 1.5, 225)) \(arc(240, 4.5, 225)) \(arc(240, 7.5, 225)))")

    // list-style-image: a blue 4px PNG, and an SVG red square.
    view.LoadHTML("""
    <style>body { margin: 0; background: white; font: 16px Helvetica; color: white } ul { margin: 0; padding-left: 40px }</style>
    <ul style="list-style-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGNgYPiPhIjiAACOsw/xs6MvMwAAAABJRU5ErkJggg==)"><li>a</li></ul>
    <ul style="list: none; list-style: square outside url('data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%226%22 height=%226%22><rect width=%226%22 height=%226%22 fill=%22rgb(255,0,0)%22/></svg>')"><li>b</li></ul>
    """)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    check(count(draw.Color(0, 0, 255), 20, 0, 40, 20) == 16, "list-style-image draws the image as the marker (got \(count(draw.Color(0, 0, 255), 20, 0, 40, 20)) pixels)")
    check(count(draw.Color(255, 0, 0), 20, 18, 40, 40) >= 20, "an SVG list image, from the list-style shorthand (got \(count(draw.Color(255, 0, 0), 20, 18, 40, 40)))")

    // empty-cells: hide leaves an empty cell undrawn.
    view.LoadHTML("""
    <style>body { margin: 0; background: white } table { empty-cells: hide; border-spacing: 0 } td { width: 20px; height: 20px; padding: 0; background: rgb(0, 0, 255) }</style>
    <table><tr><td>x</td><td> </td><td style="empty-cells: show"></td></tr></table>
    """)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    check(at(2, 2) == draw.Color(0, 0, 255) && at(30, 10) == draw.Color(255, 255, 255) && at(50, 10) == draw.Color(0, 0, 255),
          "empty-cells: hide leaves an empty cell's background undrawn (got \(at(2, 2)) \(at(30, 10)) \(at(50, 10)))")

    // Outlines on boxes in the flow, not only on boxes painted whole.
    view.LoadHTML("""
    <style>body { margin: 20px; background: white } div { width: 60px; height: 20px; outline: 3px solid rgb(255, 0, 0) }
    section { display: flex; margin-top: 20px }</style>
    <div></div><section><div></div></section>
    """)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    check(at(18, 30) == draw.Color(255, 0, 0) && at(18, 70) == draw.Color(255, 0, 0), "an in-flow block and a flex item draw their outlines (got \(at(18, 30)) \(at(18, 70)))")
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
    func box(id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
    func at(id: string) -> draw.Rect { return view.BoundsOf(view.QuerySelector("#" + id)!)! }
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
    func box(id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
    func widths(b: layout.Box) -> [float32] {
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
    func box(id: string) -> layout.Box? { return view.BoxFor(view.QuerySelector("#" + id)!) }
    check(box("z")!.Width == 102 && box("z")!.Height == 20 && box("z")!.Border.Left == 2, "zoom doubles lengths and borders (got \(box("z")!.Width) \(box("z")!.Height))")
    check(box("zc")!.Width == 32 && box("zc")!.Height == 20, "and rem and em inside it (got \(box("zc")!.Width) \(box("zc")!.Height))")
    check(box("dk")!.Style.Color == draw.Color(2, 2, 2) && box("lt")!.Style.Color == draw.Color(1, 1, 1), "color-scheme picks light-dark()'s color")
    var px = [uint8](repeating: 0, count: 400 * 300 * 4)
    view.Draw(into: &px, width: 400, height: 300, scale: 1)
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 400, x, y) }
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
    func box(id: string) -> layout.Box { return view.BoxFor(view.QuerySelector("#" + id)!)! }
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
    func node(id: string) -> html.Node { return view.QuerySelector("#" + id)! }
    func click(id: string) {
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
    check(view.ValidationMessage(node("req")) == "Please fill out this field.", "and says why (got \(view.ValidationMessage(node("req"))))")
    func orangeUnder(id: string) -> bool {
        var bp = [uint8](repeating: 0, count: 400 * 300 * 4)
        view.Draw(into: &bp, width: 400, height: 300, scale: 1)
        let r = view.BoundsOf(node(id))!
        var y = int32(r.Y + r.Height)
        while y < int32(r.Y + r.Height) + 40 && y < 300 {
            var x = int32(r.X)
            while x < int32(r.X) + 40 {
                let c = pixelAt(bp, 400, x, y)
                if c.R > 220 && c.G > 120 && c.G < 160 && c.B < 40 { return true }
                x += 1
            }
            y += 1
        }
        return false
    }
    check(orangeUnder("req"), "a validation bubble shows under the field")
    _ = view.Handle(.text("x"))
    check(!orangeUnder("req"), "and goes when the user types")
    click("go")
    check(submitted == 1, "filled in, the form is sent")

    // pattern, checked by text/regexp.
    let pv = web.Page()
    pv.SetViewportSize(draw.Size(300, 100))
    pv.LoadHTML("<form><input id=zip pattern='\\d{5}(-\\d{4})?' value='12a45' title='Five digits'><input id=ok pattern='[a-z]+' value='abc'></form>")
    let zip = pv.QuerySelector("#zip")!
    check(pv.QuerySelector("input:invalid")?.GetAttribute("id") == "zip" && pv.QuerySelector("#ok:valid") != nil, "pattern makes a value that doesn't match it :invalid")
    check(pv.ValidationMessage(zip) == "Please match the requested format.\nFive digits", "and says so, with the title (got \(pv.ValidationMessage(zip)))")
    pv.Document!.ElementFor(zip).SetAttribute("value", "12345-6789")
    check(pv.ValidationMessage(zip).isEmpty && pv.QuerySelector("input:invalid") == nil, "a value that matches is valid")
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
    func node(id: string) -> html.Node { return view.QuerySelector("#" + id)! }
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
    func node(id: string) -> html.Node { return view.QuerySelector("#" + id)! }
    func key(id: string, code: string) {
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
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 300, x, y) }
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

    // ::first-line's font is laid out, and only on the first line.
    let fl = web.Page()
    fl.SetViewportSize(draw.Size(200, 300))
    fl.LoadHTML("""
    <style>body { margin: 0; font-size: 10px; line-height: 1 } p { margin: 0; width: 200px } .big::first-line { font-size: 40px }</style>
    <p id=plain>word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word</p>
    <p id=big class=big>word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word</p>
    """)
    let plainBox = fl.BoxFor(fl.QuerySelector("#plain")!)!
    let bigBox = fl.BoxFor(fl.QuerySelector("#big")!)!
    let plainLines = plainBox.Lines
    let bigLines = bigBox.Lines
    check(plainLines.count >= 2 && bigLines.count > plainLines.count, "a larger first line holds fewer words (\(plainLines.count) lines, then \(bigLines.count))")
    check(bigLines[0].Height == 40 && bigLines[1].Height == 10, "the first line is as tall as its font, the next as the block's (\(bigLines[0].Height) \(bigLines[1].Height))")
    check(bigLines[0].Fragments[0].Width <= 200 && bigLines[1].Fragments[0].Width > bigLines[0].Fragments[0].Width / 2,
          "and each line's words are set in its own font (\(bigLines[0].Fragments[0].Width) \(bigLines[1].Fragments[0].Width))")

    // display: flow-root holds its floats and its children's margins.
    let fr = web.Page()
    fr.SetViewportSize(draw.Size(200, 200))
    fr.LoadHTML("<style>body { margin: 0 } .f { float: left; width: 10px; height: 50px } #kid { margin-top: 20px; height: 5px }</style><div id=root style='display: flow-root'><div class=f></div></div><div id=m style='display: flow-root'><div id=kid></div></div>")
    check(fr.BoundsOf(fr.QuerySelector("#root")!)!.Height == 50, "display: flow-root holds its floats (got \(fr.BoundsOf(fr.QuerySelector("#root")!)!.Height))")
    check(fr.BoundsOf(fr.QuerySelector("#m")!)!.Height == 25, "and its child's margin stays inside (got \(fr.BoundsOf(fr.QuerySelector("#m")!)!.Height))")

    // Font features, and the text details.
    let ff = web.Page()
    ff.SetViewportSize(draw.Size(600, 900))
    ff.LoadHTML("""
    <style>body { margin: 0; font: 40px Times, serif } p { margin: 0; width: fit-content } .sys { font-family: system-ui } </style>
    <p id=kern>AVAVAV</p><p id=nokern style="font-kerning: none">AVAVAV</p>
    <p id=light class=sys style='font-variation-settings: "wght" 100'>Wide text</p><p id=heavy class=sys style='font-variation-settings: "wght" 900'>Wide text</p>
    <p id=narrow class=sys style="font-stretch: 75%">Wide text</p><p id=normal class=sys>Wide text</p>
    <p id=prop class=sys>1111</p><p id=tab class=sys style="font-variant-numeric: tabular-nums">1111</p><p id=feat class=sys style='font-feature-settings: "tnum"'>1111</p>
    <div style="width: 200px; font-size: 20px"><p id=j style="width: auto; display: block; text-align: justify; text-align-last: justify; text-justify: inter-character">abcd</p></div>
    <div style="width: 200px; font-size: 20px"><p id=nj style="width: auto; display: block; text-align: justify; text-align-last: justify; text-justify: none">ab cd</p></div>
    <p id=hang style="display: block; hanging-punctuation: first; font-size: 20px">\u{201C}quoted</p>
    <p id=em style="display: block; font-size: 20px; text-emphasis: filled dot rgb(255,0,0); margin-top: 30px; width: 100px">abc</p>
    <p id=hy lang=en style="display: block; font: 16px Times; width: 60px; hyphens: auto">internationalization</p>
    <p id=nohy lang=en style="display: block; font: 16px Times; width: 60px; hyphens: manual">internationalization</p>
    """)
    func ffw(id: string) -> float32 { return ff.BoxFor(ff.QuerySelector("#" + id)!)!.Width }
    check(ffw("nokern") > ffw("kern"), "font-kerning: none undoes kerning (\(ffw("kern")) \(ffw("nokern")))")
    check(ffw("heavy") > ffw("light"), "font-variation-settings reaches a variable font (\(ffw("light")) \(ffw("heavy")))")
    check(ffw("narrow") < ffw("normal"), "font-stretch narrows one with a width axis (\(ffw("narrow")) \(ffw("normal")))")
    check(ffw("tab") != ffw("prop"), "font-variant-numeric: tabular-nums changes a 1's width (\(ffw("prop")) \(ffw("tab")))")
    check(ffw("feat") == ffw("tab"), "font-feature-settings does the same (\(ffw("feat")))")
    let jLine = ff.BoxFor(ff.QuerySelector("#j")!)!.Lines[0]
    check(jLine.Fragments[0].Width > 190, "text-justify: inter-character spreads a line with no spaces (\(jLine.Fragments[0].Width))")
    let njLine = ff.BoxFor(ff.QuerySelector("#nj")!)!.Lines[0]
    check(njLine.Fragments[0].Width < 100, "text-justify: none leaves it (\(njLine.Fragments[0].Width))")
    let hangFrag = ff.BoxFor(ff.QuerySelector("#hang")!)!.Lines[0].Fragments[0]
    check(hangFrag.X < 0, "hanging-punctuation: first puts the quote outside (\(hangFrag.X))")
    var ffp = [uint8](repeating: 0, count: 600 * 900 * 4)
    ff.Draw(into: &ffp, width: 600, height: 900, scale: 1)
    let emAt = ff.BoundsOf(ff.QuerySelector("#em")!)!
    var marks = 0
    var ex = int32(emAt.X)
    while ex < int32(emAt.X) + 60 {
        var ey = int32(emAt.Y) - 14
        while ey < int32(emAt.Y) + 6 {
            let c = pixelAt(ffp, 600, ex, ey)
            if c.R > 200 && c.G < 120 { marks += 1 }
            ey += 1
        }
        ex += 1
    }
    check(marks > 3, "text-emphasis draws marks over the line (\(marks) pixels)")
    let hyLines = ff.BoxFor(ff.QuerySelector("#hy")!)!.Lines
    check(hyLines.count > 1 && hyLines[0].Fragments[0].Width <= 60, "hyphens: auto breaks a long word by the dictionary (\(hyLines.count) lines)")
    check(ff.BoxFor(ff.QuerySelector("#nohy")!)!.Lines.count == 1, "hyphens: manual doesn't")

    // Loose text beside blocks, where its parent is out of the flow.
    for parentStyle in ["position: absolute", "position: fixed", "float: left"] {
        let lt = web.Page()
        lt.SetViewportSize(draw.Size(400, 300))
        lt.LoadHTML("<div id=c style='\(parentStyle); width: 200px'><h4>head</h4><div style='float: left; width: 10px; height: 10px'></div>Some loose text</div>")
        func lines(b: layout.Box) -> [string] {
            var out: [string] = []
            for l in b.Lines {
                for f in l.Fragments { out.append(f.Text) }
            }
            for k in b.Children { out += lines(k) }
            return out
        }
        let got = lines(lt.BoxFor(lt.QuerySelector("#c")!)!).joined(separator: "")
        check(got.contains("Some loose text"), "\(parentStyle): text beside a block keeps its place (got \(got))")
    }

    // Layout's other shapes: shape-outside, subgrid, masonry, table text.
    let lo = web.Page()
    lo.SetViewportSize(draw.Size(400, 900))
    lo.LoadHTML("""
    <style>body { margin: 0; font-size: 10px; line-height: 10px; background: white }
    #fl { float: left; width: 100px; height: 100px; shape-outside: circle(50%) }
    #tx { width: 200px; height: 100px }
    #g { display: grid; grid-template-columns: 50px 70px 90px; width: 210px }
    #sub { grid-column: 1 / 4; display: grid; grid-template-columns: subgrid } #sub div { height: 5px }
    #m { display: masonry; grid-template-columns: 50px 50px; width: 100px; column-gap: 0; row-gap: 0 } #m div { width: auto }
    #t { display: table }
    #cs { width: 100px; height: 100px; background: rgb(255,0,0); border-radius: 50px; corner-shape: bevel }
    #sq { width: 100px; height: 100px; background: rgb(255,0,0); border-radius: 50px; corner-shape: squircle }
    #sqi { width: 100px; height: 100px; background: linear-gradient(rgb(0,0,255), rgb(0,0,255)); border-radius: 50px; corner-shape: squircle }
    #bev { width: 100px; height: 100px; border: 10px solid; border-color: rgb(255,0,0) rgb(0,255,0) rgb(0,0,255) rgb(255,128,0); border-radius: 30px; corner-shape: bevel }
    #mk { width: 100px; height: 40px; padding: 10px; box-sizing: border-box; background: rgb(0,0,255); mask-image: linear-gradient(black, black); mask-clip: content-box }
    #over { position: relative; height: 10px } #cover { margin-top: -10px; height: 10px }
    #grow { interpolate-size: allow-keywords; transition: height 1s linear; overflow: hidden; height: 0 } #grow.open { height: auto } #grow div { height: 40px }
    #cgrow { transition: height 1s linear; overflow: hidden; height: 0 } #cgrow.open { height: calc-size(auto, size) } #cgrow div { height: 40px }
    </style>
    <div id=tx><div id=fl></div>word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word</div>
    <div id=g><div id=sub><div id=s1></div><div id=s2></div><div id=s3></div></div></div>
    <div id=m><div id=m1 style="height: 30px"></div><div id=m2 style="height: 10px"></div><div id=m3 style="height: 10px"></div></div>
    <div id=t>loose text</div>
    <div id=cs></div><div id=sq></div><div id=sqi></div><div id=bev></div><div id=mk></div>
    <div id=over></div><div id=cover></div>
    <div id=grow><div></div></div>
    <div id=cgrow><div></div></div>
    """)
    func lob(id: string) -> draw.Rect { return lo.BoundsOf(lo.QuerySelector("#" + id)!)! }
    let txLines = lo.BoxFor(lo.QuerySelector("#tx")!)!.Lines
    var shortest: float32 = 1000
    var longestStart: float32 = 0
    for line in txLines {
        if let f = line.Fragments.first {
            if f.X < shortest { shortest = f.X }
            if f.X > longestStart { longestStart = f.X }
        }
    }
    check(shortest < 40 && longestStart > 80, "lines wrap round shape-outside's circle (x from \(shortest) to \(longestStart))")
    check(lob("s1").Width == 50 && lob("s2").Width == 70 && lob("s3").Width == 90, "a subgrid's columns are its parent's (got \(lob("s1").Width) \(lob("s2").Width) \(lob("s3").Width))")
    check(lob("m1").X == 0 && lob("m2").X == 50 && lob("m3").X == 50 && lob("m3").Y == lob("m2").Y + 10, "masonry puts each item in the shortest column (got \(lob("m3").X) \(lob("m3").Y - lob("m2").Y))")
    check(lob("t").Width > 10 && lob("t").Height > 5, "text in a display: table gets a cell (got \(lob("t").Width) x \(lob("t").Height))")
    var lop = [uint8](repeating: 0, count: 400 * 900 * 4)
    lo.Draw(into: &lop, width: 400, height: 900, scale: 1)
    func loc(x: float32, y: float32) -> draw.Color { return pixelAt(lop, 400, int32(x), int32(y)) }
    let csAt = lob("cs")
    // A bevel's corner is cut straight: (15, 15) is outside it, (30, 30) in.
    check(loc(csAt.X + 15, csAt.Y + 15) == draw.Color.white && loc(csAt.X + 30, csAt.Y + 30) == draw.Color(255, 0, 0), "corner-shape: bevel cuts straight (got \(loc(csAt.X + 15, csAt.Y + 15)) \(loc(csAt.X + 30, csAt.Y + 30)))")
    let sqAt = lob("sq")
    // A round corner would leave (10, 10) outside; a squircle covers (14, 14)
    // where a circle doesn't.
    check(loc(sqAt.X + 14, sqAt.Y + 14) == draw.Color(255, 0, 0), "corner-shape: squircle bulges past round (got \(loc(sqAt.X + 14, sqAt.Y + 14)))")
    let sqiAt = lob("sqi")
    check(loc(sqiAt.X + 50, sqiAt.Y + 50) == draw.Color(0, 0, 255) && loc(sqiAt.X + 3, sqiAt.Y + 3) == draw.Color.white,
          "corner-shape with a background image keeps it to the shape (got \(loc(sqiAt.X + 3, sqiAt.Y + 3)))")
    let bevAt = lob("bev")
    check(loc(bevAt.X + 60, bevAt.Y + 4) == draw.Color(255, 0, 0) && loc(bevAt.X + 115, bevAt.Y + 60) == draw.Color(0, 255, 0)
          && loc(bevAt.X + 60, bevAt.Y + 115) == draw.Color(0, 0, 255) && loc(bevAt.X + 4, bevAt.Y + 60) == draw.Color(255, 128, 0),
          "corner-shape's border takes each side's color (got \(loc(bevAt.X + 4, bevAt.Y + 60)) \(loc(bevAt.X + 115, bevAt.Y + 60)))")
    let mkAt = lob("mk")
    check(loc(mkAt.X + 50, mkAt.Y + 20) == draw.Color(0, 0, 255) && loc(mkAt.X + 5, mkAt.Y + 20) == draw.Color.white, "mask-clip: content-box cuts the padding (got \(loc(mkAt.X + 5, mkAt.Y + 20)))")
    let overAt = lob("over")
    check(lo.ElementAt(draw.Point(overAt.X + 5, overAt.Y + 5))?.GetAttribute("id") == "over", "a relative box is hit before a later block under it (got \(lo.ElementAt(draw.Point(overAt.X + 5, overAt.Y + 5))?.GetAttribute("id") ?? "none"))")
    let grower = lo.QuerySelector("#grow")!
    _ = lo.BoundsOf(grower)
    _ = lo.Advance(time: 20)
    lo.Document?.SetAttribute(grower, "class", "open")
    let cgrower = lo.QuerySelector("#cgrow")!
    lo.Document?.SetAttribute(cgrower, "class", "open")
    _ = lo.BoundsOf(grower)
    _ = lo.Advance(time: 20)
    _ = lo.Advance(time: 20.5)
    let midHeight = lo.BoundsOf(grower)!.Height
    check(midHeight > 10 && midHeight < 30, "interpolate-size: allow-keywords transitions to auto (got \(midHeight))")
    let cMid = lo.BoundsOf(cgrower)!.Height
    check(cMid > 10 && cMid < 30, "and so does calc-size(auto, size), on its own (got \(cMid))")
    _ = lo.Advance(time: 22)
    check(lo.BoundsOf(cgrower)!.Height == 40, "ending at the size it comes to (got \(lo.BoundsOf(cgrower)!.Height))")

    // An animated image moves on with time.
    let ga = web.Page()
    ga.SetViewportSize(draw.Size(40, 40))
    ga.LoadHTML("<style>body { margin: 0 } img { display: block; width: 40px; height: 40px }</style><img src='data:image/gif;base64,R0lGODdhBAAEAKIAAAAAAAAA//8AAP///wAAAAAAAAAAAAAAACH5BAUUAAQALAAAAAAEAAQAAAMEKLrckgAh+QQFFAAEACwAAAAABAAEAAADBBi63JEAOw=='>")
    var gap = [uint8](repeating: 0, count: 40 * 40 * 4)
    ga.Draw(into: &gap, width: 40, height: 40, scale: 1)
    check(pixelAt(gap, 40, 20, 20).R > 200 && pixelAt(gap, 40, 20, 20).B < 60, "an animated image starts on its first frame (got \(pixelAt(gap, 40, 20, 20)))")
    check(ga.NeedsAnimation(), "and asks for frames")
    _ = ga.Advance(time: 5)
    _ = ga.Advance(time: 5.3)
    ga.Draw(into: &gap, width: 40, height: 40, scale: 1)
    check(pixelAt(gap, 40, 20, 20).B > 200 && pixelAt(gap, 40, 20, 20).R < 60, "its next frame shows when it's due (got \(pixelAt(gap, 40, 20, 20)))")
    _ = ga.Advance(time: 5.5)
    ga.Draw(into: &gap, width: 40, height: 40, scale: 1)
    check(pixelAt(gap, 40, 20, 20).R > 200, "and it goes round (got \(pixelAt(gap, 40, 20, 20)))")

    // Text strokes, will-change, transform-box, element states.
    let st2 = web.Page()
    st2.SetViewportSize(draw.Size(300, 300))
    st2.LoadHTML("""
    <style>body { margin: 0; background: white } #ts { font: 60px Times; -webkit-text-stroke: 3px rgb(255,0,0); color: transparent; width: 100px; height: 60px; line-height: 60px; position: absolute; left: 0; top: 0 }
    #wc { will-change: transform; position: absolute; left: 100px; top: 0; width: 50px; height: 50px } #fx2 { position: fixed; left: 5px; top: 5px; width: 5px; height: 5px }
    #tb { position: absolute; left: 150px; top: 0; width: 40px; height: 40px; padding: 20px; transform-box: content-box; transform-origin: 0 0; transform: scale(2); background: rgb(0,255,0) }
    #stt:state(open) { color: rgb(1,2,3) } #stt:fullscreen { background-color: rgb(4,5,6) } #af:autofill { background-color: rgb(7,8,9) }
    @counter-style pd { system: numeric; symbols: "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"; pad: 3 "0"; suffix: ""; range: 1 5; fallback: decimal }
    </style>
    <div id=ts>H</div><div id=wc><div id=fx2></div></div><div id=tb></div><p id=stt>state</p><input id=af>
    <ol style="list-style-type: pd"><li id=c1>a</li><li>b</li><li>c</li><li>d</li><li>e</li><li id=c6>f</li></ol>
    """)
    var st2p = [uint8](repeating: 0, count: 300 * 300 * 4)
    st2.Draw(into: &st2p, width: 300, height: 300, scale: 1)
    var strokeRed = 0
    var sy2: int32 = 0
    while sy2 < 60 {
        var sx2: int32 = 0
        while sx2 < 100 {
            let c = pixelAt(st2p, 300, sx2, sy2)
            if c.R > 200 && c.G < 80 { strokeRed += 1 }
            sx2 += 1
        }
        sy2 += 1
    }
    check(strokeRed > 40, "-webkit-text-stroke draws the outline (\(strokeRed) pixels)")
    let fx2b = st2.BoundsOf(st2.QuerySelector("#fx2")!)!
    check(fx2b.X == 105 && fx2b.Y == 5, "will-change: transform holds its fixed descendants (got \(fx2b.X) \(fx2b.Y))")
    // Scaled about the content box's corner: its border box's corner moves out.
    check(pixelAt(st2p, 300, 145, 5) != draw.Color.white || pixelAt(st2p, 300, 131, 2) != draw.Color.white, "transform-box: content-box moves the origin (got \(pixelAt(st2p, 300, 145, 5)))")
    let sttN = st2.QuerySelector("#stt")!
    st2.SetCustomState(sttN, name: "open", on: true)
    check(st2.BoxFor(sttN)!.Style.Color == draw.Color(1, 2, 3), ":state() answers what's set (got \(st2.BoxFor(sttN)!.Style.Color))")
    st2.SetFullscreenElement(sttN)
    check(st2.BoxFor(sttN)!.Style.BackgroundColor == draw.Color(4, 5, 6), ":fullscreen answers it")
    let afN = st2.QuerySelector("#af")!
    st2.SetAutofilled(afN, on: true)
    check(st2.BoxFor(afN)!.Style.BackgroundColor == draw.Color(7, 8, 9), ":autofill answers it")
    check(st2.BoxFor(st2.QuerySelector("#c1")!)!.Marker == "001", "@counter-style's pad (got \(st2.BoxFor(st2.QuerySelector("#c1")!)!.Marker))")
    check(st2.BoxFor(st2.QuerySelector("#c6")!)!.Marker.hasPrefix("6"), "and range's fallback (got \(st2.BoxFor(st2.QuerySelector("#c6")!)!.Marker))")
    // Field-sizing, horizontal text inside vertical, balance beside a float.
    let fs2 = web.Page()
    fs2.SetViewportSize(draw.Size(400, 300))
    fs2.LoadHTML("""
    <style>body { margin: 0; font-size: 20px; line-height: 20px } input, textarea { font-size: 20px; padding: 0; border: 0 } #sized { field-sizing: content } #ta { field-sizing: content }
    #vb { writing-mode: vertical-rl; height: 100px; position: absolute; left: 300px; top: 0 } #hb { writing-mode: horizontal-tb; width: 30px; height: 10px; background: rgb(255,0,0); display: block }
    #fb { float: left; width: 50px; height: 80px } #bal { text-wrap: balance; width: 250px }</style>
    <input id=sized value="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"><textarea id=ta>one
    two
    three</textarea><div id=vb><div id=hb></div></div>
    <div><div id=fb></div><p id=bal style="margin: 0">word word word word word word word word word word word</p></div>
    """)
    check(fs2.BoundsOf(fs2.QuerySelector("#sized")!)!.Width > 300, "field-sizing: content on an <input> (got \(fs2.BoundsOf(fs2.QuerySelector("#sized")!)!.Width))")
    check(fs2.BoundsOf(fs2.QuerySelector("#ta")!)!.Height < 80, "and a <textarea>'s height is its lines' (got \(fs2.BoundsOf(fs2.QuerySelector("#ta")!)!.Height))")
    let hbb = fs2.BoundsOf(fs2.QuerySelector("#hb")!)!
    check(hbb.Width == 30 && hbb.Height == 10, "horizontal-tb inside vertical keeps its physical size (got \(hbb.Width) x \(hbb.Height))")
    let balLines = fs2.BoxFor(fs2.QuerySelector("#bal")!)!.Lines
    var widest: float32 = 0
    var narrowest: float32 = 10000
    var bi = 0
    while bi < balLines.count {
        var w: float32 = 0
        for f in balLines[bi].Fragments { w += f.Width }
        if w > widest { widest = w }
        if w < narrowest { narrowest = w }
        bi += 1
    }
    check(balLines.count >= 2 && widest - narrowest < 60, "text-wrap: balance works beside a float (\(balLines.count) lines, \(narrowest) to \(widest))")
    // Print's margin boxes.
    let pm = web.Page()
    pm.SetViewportSize(draw.Size(300, 200))
    pm.LoadHTML("<style>@page { size: 200px 100px; margin: 20px; @bottom-center { content: counter(page) \" of \" counter(pages) } } body { margin: 0 } div { height: 50px }</style><div></div><div></div>")
    let pmSheets = pm.Print(scale: 1)
    var pmDark = 0
    if let first = pmSheets.first {
        var y = 80
        while y < 100 {
            var x = 0
            while x < 200 {
                if first.Pixels[(y * 200 + x) * 4] < 120 { pmDark += 1 }
                x += 1
            }
            y += 1
        }
    }
    check(pmDark > 5, "@page's margin boxes print (\(pmDark) pixels)")

    // A relative inline-block in an anonymous line box, under a later block.
    let ho = web.Page()
    ho.SetViewportSize(draw.Size(200, 200))
    ho.LoadHTML("<style>body { margin: 0 } #pin { position: relative; display: inline-block; width: 40px; height: 40px } #after { margin-top: -20px; height: 40px }</style><div>loose <span id=pin></span><div id=after></div></div>")
    let pinAt = ho.BoundsOf(ho.QuerySelector("#pin")!)!
    let underHit = ho.ElementAt(draw.Point(pinAt.X + 20, pinAt.Y + pinAt.Height - 5))?.GetAttribute("id") ?? "none"
    check(underHit == "pin", "a positioned inline-block in a line is hit over a later block (got \(underHit))")

    // In vertical text a box's border sides and background image keep to
    // the sides they're on the page.
    let vb = web.Page()
    vb.SetViewportSize(draw.Size(200, 200))
    vb.LoadHTML("""
    <style>body { margin: 0; background: white } #v { writing-mode: vertical-rl; height: 150px }
    #vb { width: 40px; height: 40px; border: 5px solid; border-color: rgb(255,0,0) rgb(0,255,0) rgb(0,0,255) rgb(255,128,0); border-top-left-radius: 20px }
    #vi { width: 40px; height: 40px; background: linear-gradient(rgb(255,0,0), rgb(0,0,255)) }</style>
    <div id=v><div id=vb></div><div id=vi></div></div>
    """)
    var vbp = [uint8](repeating: 0, count: 200 * 200 * 4)
    vb.Draw(into: &vbp, width: 200, height: 200, scale: 1)
    let vbAt = vb.BoundsOf(vb.QuerySelector("#vb")!)!
    let vdx = int32(vbAt.X)
    let vdy = int32(vbAt.Y)
    check(pixelAt(vbp, 200, vdx + 25, vdy + 2) == draw.Color(255, 0, 0) && pixelAt(vbp, 200, vdx + 2, vdy + 25) == draw.Color(255, 128, 0)
          && pixelAt(vbp, 200, vdx + 47, vdy + 25) == draw.Color(0, 255, 0) && pixelAt(vbp, 200, vdx + 25, vdy + 47) == draw.Color(0, 0, 255),
          "in vertical text a border's colors stay on their sides (got top \(pixelAt(vbp, 200, vdx + 25, vdy + 2)) left \(pixelAt(vbp, 200, vdx + 2, vdy + 25)))")
    check(pixelAt(vbp, 200, vdx + 1, vdy + 1) == draw.Color.white && pixelAt(vbp, 200, vdx + 48, vdy + 1) != draw.Color.white,
          "and its round corner stays at the top left")
    let viAt = vb.BoundsOf(vb.QuerySelector("#vi")!)!
    let viTop = pixelAt(vbp, 200, int32(viAt.X) + 20, int32(viAt.Y) + 2)
    let viBottom = pixelAt(vbp, 200, int32(viAt.X) + 20, int32(viAt.Y) + 38)
    check(viTop.R > 200 && viTop.B < 50 && viBottom.B > 200 && viBottom.R < 50, "and its background image stands upright (got \(viTop) \(viBottom))")

    // text-combine-upright: one em of a vertical line, upright.
    let tc = web.Page()
    tc.SetViewportSize(draw.Size(200, 300))
    tc.LoadHTML("<style>body { margin: 0; font-size: 20px } p { writing-mode: vertical-rl; height: 280px; margin: 0 } .t { text-combine-upright: all } #d { text-combine-upright: digits 2 }</style><p id=a>x<span class=t>2024</span>y</p><p id=d>a 31 b 123</p>")
    var tcp = [uint8](repeating: 0, count: 200 * 300 * 4)
    tc.Draw(into: &tcp, width: 200, height: 300, scale: 1)
    func combinedWidths(id: string) -> [float32] {
        var out: [float32] = []
        var b = tc.BoxFor(tc.QuerySelector("#" + id)!)!
        if let inner = b.VerticalContent { b = inner }
        for line in b.Lines {
            for f in line.Fragments where f.Combined { out.append(f.Width) }
        }
        return out
    }
    check(combinedWidths("a") == [20], "text-combine-upright: all takes one em of the line (got \(combinedWidths("a")))")
    check(combinedWidths("d") == [20], "digits 2 combines two digits but not three (got \(combinedWidths("d")))")

    // Vertical text takes its CJK punctuation's vertical forms; Latin
    // keeps its own, to turn with the line.
    let vfm = web.Page()
    vfm.SetViewportSize(draw.Size(200, 300))
    vfm.LoadHTML("<style>body { margin: 0; font: 20px serif } p { writing-mode: vertical-rl; height: 280px; margin: 0 }</style><p id=p>「本」Ab</p>")
    var vfmp = [uint8](repeating: 0, count: 200 * 300 * 4)
    vfm.Draw(into: &vfmp, width: 200, height: 300, scale: 1)
    var vfmBox = vfm.BoxFor(vfm.QuerySelector("#p")!)!
    if let inner = vfmBox.VerticalContent { vfmBox = inner }
    var vfmGlyphs: [uint32] = []
    for line in vfmBox.Lines {
        for f in line.Fragments where f.Kind == .text { vfmGlyphs += f.Run.Glyphs }
    }
    let vfmFace = vfmBox.Style.Face
    check(vfmGlyphs.count == 5 && vfmGlyphs[0] != vfmFace.Shape("「").Glyphs[0] && vfmGlyphs[3] == vfmFace.Shape("A").Glyphs[0],
          "vertical text takes a bracket's vertical form, and Latin its own (got \(vfmGlyphs), horizontal 「 \(vfmFace.Shape("「").Glyphs))")

    // shape-outside: url(): text wraps round the image's opaque part.
    let so = web.Page()
    so.SetViewportSize(draw.Size(300, 200))
    so.LoadHTML("<style>body { margin: 0; font-size: 10px; line-height: 10px } #fl { float: left; width: 100px; height: 40px; shape-outside: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAABCAYAAAD5PA/NAAAAEElEQVR4nGNgYGD4D8VgAAAV+wH/4ACp4gAAAABJRU5ErkJggg==) }</style><div id=fl></div><p id=wrap style='margin: 0'>word word word word word word word word word word word word word word word word word word word word</p>")
    _ = so.BoundsOf(so.QuerySelector("#wrap")!)
    var sop = [uint8](repeating: 0, count: 300 * 200 * 4)
    so.Draw(into: &sop, width: 300, height: 200, scale: 1)
    let soLines = so.BoxFor(so.QuerySelector("#wrap")!)!.Lines
    let soX = soLines.isEmpty ? -1 : soLines[0].X
    check(soX >= 50 && soX < 60, "shape-outside with an image wraps text round its opaque half (first line at \(soX))")
    let sg = web.Page()
    sg.SetViewportSize(draw.Size(300, 200))
    sg.LoadHTML("<style>body { margin: 0; font-size: 10px; line-height: 10px } #fl { float: left; width: 100px; height: 40px; shape-outside: linear-gradient(to right, black 50%, transparent 50%) }</style><div id=fl></div><p id=wrap style='margin: 0'>word word word word word word word word word word word word word word word word word word word word</p>")
    var sgp = [uint8](repeating: 0, count: 300 * 200 * 4)
    sg.Draw(into: &sgp, width: 300, height: 200, scale: 1)
    let sgLines = sg.BoxFor(sg.QuerySelector("#wrap")!)!.Lines
    let sgX = sgLines.isEmpty ? -1 : sgLines[0].X
    check(sgX >= 50 && sgX < 60, "and with a gradient, round where it's opaque (first line at \(sgX))")

    // @page :first, :left and :right.
    let pf = web.Page()
    pf.SetViewportSize(draw.Size(300, 200))
    pf.LoadHTML("""
    <style>@page { size: 200px 100px; margin: 10px } @page :first { margin: 40px 10px 10px 10px; @top-center { content: "Title" } } @page :left { margin: 10px 10px 10px 50px }
    body { margin: 0 } div { height: 50px } .r { background: rgb(255,0,0) } .g { background: rgb(0,255,0) } .b { background: rgb(0,0,255) }</style>
    <div class=r></div><div class=g></div><div class=b></div>
    """)
    let pfSheets = pf.Print(scale: 1)
    func pfAt(n: int, x: int, y: int) -> draw.Color {
        let i = (y * int(pfSheets[n].Width) + x) * 4
        return draw.Color(pfSheets[n].Pixels[i], pfSheets[n].Pixels[i + 1], pfSheets[n].Pixels[i + 2])
    }
    func pfDark(n: int) -> int {
        var dark = 0
        var y = 0
        while y < 10 {
            var x = 0
            while x < 200 {
                let c = pfAt(n, x, y + 15)
                if c.R < 120 && c.G < 120 && c.B < 120 { dark += 1 }
                x += 1
            }
            y += 1
        }
        return dark
    }
    check(pfSheets.count == 3, "@page :first's margin leaves room for one box on the first sheet (got \(pfSheets.count) sheets)")
    if pfSheets.count == 3 {
        check(pfAt(0, 50, 45) == draw.Color(255, 0, 0) && pfAt(0, 50, 30) == draw.Color.white, "the first sheet starts below its own top margin (got \(pfAt(0, 50, 30)))")
        check(pfDark(0) > 5 && pfDark(1) == 0, "its margin box is the first sheet's alone (got \(pfDark(0)) \(pfDark(1)))")
        check(pfAt(1, 30, 30) == draw.Color.white && pfAt(1, 60, 30) == draw.Color(0, 255, 0), "a left sheet takes @page :left's margin (got \(pfAt(1, 30, 30)))")
        check(pfAt(2, 15, 30) == draw.Color(0, 0, 255), "and a right one the page's own (got \(pfAt(2, 15, 30)))")
    }

    // Printing.
    let pr = web.Page()
    pr.SetViewportSize(draw.Size(300, 200))
    pr.LoadHTML("""
    <style>@page { size: 200px 100px; margin: 10px } body { margin: 0 } div { height: 60px } .r { background: rgb(255,0,0) } .g { background: rgb(0,255,0) } .b { background: rgb(0,0,255); break-before: page }
    .only { height: 20px } @media print { .only { background: rgb(255,255,0) } .scr { display: none } } @media screen { .only { background: black } }</style>
    <div class=r></div><div class=g></div><div class=b></div><div class="only"></div><div class=scr></div>
    """)
    let sheets = pr.Print(scale: 1)
    check(sheets.count == 3, "a page cuts into sheets where it may (got \(sheets.count))")
    if sheets.count == 3 {
        func sheetAt(n: int, x: int, y: int) -> draw.Color {
            let i = (y * int(sheets[n].Width) + x) * 4
            return draw.Color(sheets[n].Pixels[i], sheets[n].Pixels[i + 1], sheets[n].Pixels[i + 2])
        }
        check(sheets[0].Width == 200 && sheets[0].Height == 100, "@page sets its size (got \(sheets[0].Width) x \(sheets[0].Height))")
        check(sheetAt(0, 50, 30) == draw.Color(255, 0, 0) && sheetAt(0, 5, 5) == draw.Color.white, "@page's margin is left clear (got \(sheetAt(0, 5, 5)))")
        check(sheetAt(1, 50, 30) == draw.Color(0, 255, 0), "a box that won't fit goes to the next sheet, whole (got \(sheetAt(1, 50, 30)))")
        check(sheetAt(2, 50, 30) == draw.Color(0, 0, 255), "break-before: page starts one (got \(sheetAt(2, 50, 30)))")
        check(sheetAt(2, 50, 75) == draw.Color(255, 255, 0), "@media print's rules hold (got \(sheetAt(2, 50, 75)))")
    }
    let afterPrint = pr.BoundsOf(pr.QuerySelector(".scr")!)
    check(afterPrint != nil && pr.BoundsOf(pr.QuerySelector(".only")!)!.Width == 300, "and afterwards the page is as it was on screen")
    let pdf = pr.PrintPDF(scale: 1)
    check(pdf.count > 1000 && string(decoding: pdf[0..<5], as: UTF8.self) == "%PDF-", "PrintPDF writes a PDF (\(pdf.count) bytes)")
    // Its text, hidden over the picture, for a reader to select.
    let tp = web.Page()
    tp.SetViewportSize(draw.Size(300, 200))
    tp.LoadHTML("<style>@page { size: 300px 150px; margin: 10px } body { margin: 0; font-size: 16px } p { margin: 0 0 100px }</style><p>Hello printed world</p><p>Second sheet ünïcode</p>")
    let tpdf = tp.PrintPDF(scale: 1)
    let tpText = string(decoding: tpdf, as: UTF8.self)
    check(tpText.contains("3 Tr") && tpText.contains("<00480065006C006C006F0020007000720069006E00740065006400200077006F0072006C0064> Tj") && tpText.contains("/ToUnicode"),
          "PrintPDF puts each sheet's text over it, hidden, in Unicode")

    // List boxes and suggestions.
    let lb = web.Page()
    lb.SetViewportSize(draw.Size(300, 300))
    lb.LoadHTML("""
    <style>body { margin: 0; font-size: 14px; background: white } select { display: block; width: 120px; padding: 0; border: 0 } input { display: block; width: 120px; height: 24px; margin-top: 10px; padding: 0; border: 0 }</style>
    <form id=fm><select id=l name=l multiple size=3><option>a</option><option selected>b</option><option>c</option><option>d</option></select></form>
    <input id=q list=dl><datalist id=dl><option value="Apple"><option value="Banana"><option value="Apricot"></datalist>
    """)
    guard let lbx = lb.QuerySelector("#l"), let qf = lb.QuerySelector("#q") else { return }
    let lbb = lb.BoundsOf(lbx)!
    let rowH = lbb.Height / 3
    check(rowH > 10 && rowH < 30, "size sets a list box's rows (got \(lbb.Height))")
    func pickRow(n: float32, mods: web.Modifiers? = nil) {
        var e = web.Pointer(draw.Point(lbb.X + 5, lbb.Y + rowH * n + rowH / 2))
        if let m = mods { e.Modifiers = m }
        _ = lb.Handle(.pointerDown(e))
        _ = lb.Handle(.pointerUp(e))
    }
    func chosen() -> [string] {
        var out: [string] = []
        for o in dom.Descendants(lb.QuerySelector("#l")!, tag: "option") where o.HasAttribute("selected") { out.append(o.InnerText()) }
        return out
    }
    pickRow(0)
    check(chosen() == ["a"], "a click chooses one (got \(chosen()))")
    var cmd = web.Modifiers()
    cmd.Meta = true
    pickRow(2, mods: cmd)
    check(chosen() == ["a", "c"], "Command adds one, and the form submits each (got \(chosen()))")
    var sh = web.Modifiers()
    sh.Shift = true
    pickRow(1, mods: sh)
    _ = lb.Handle(.keyDown(web.Key(Key: "ArrowDown", Code: "ArrowDown")))
    check(chosen().count == 1, "keys move a single choice (got \(chosen()))")
    lb.Focus(qf)
    _ = lb.Handle(.text("ap"))
    var lbp = [uint8](repeating: 0, count: 300 * 300 * 4)
    lb.Draw(into: &lbp, width: 300, height: 300, scale: 1)
    check(lb.PressPanelCell(text: "Banana") == false, "a <datalist> suggests what matches, not the rest")
    check(lb.PressPanelCell(text: "Apricot"), "and a suggestion can be taken")
    check(lb.ValueOf(qf) == "Apricot", "which fills the field (got \(lb.ValueOf(qf)))")

    // url() clip paths and filters on HTML, shape() curves, animated images.
    let ue = web.Page()
    ue.SetViewportSize(draw.Size(300, 100))
    ue.LoadHTML("""
    <style>body { margin: 0; background: white } div { position: absolute; top: 0; width: 40px; height: 40px; background: rgb(255,0,0) }</style>
    <svg width=0 height=0 style="position:absolute"><clipPath id=c><rect width=20 height=40 /></clipPath><clipPath id=cb clipPathUnits=objectBoundingBox><rect width=.5 height=1 /></clipPath><mask id=m><rect width=20 height=40 fill=white /></mask><filter id=f><feColorMatrix type=matrix values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  1 0 0 0 0"/></filter></svg>
    <div style="left: 0; clip-path: url(#c)"></div>
    <div style="left: 50px; clip-path: url(#cb)"></div>
    <div style="left: 100px; mask: url(#m)"></div>
    <div style="left: 150px; filter: url(#f); background: rgb(255,0,255)"></div>
    <div style="left: 200px; clip-path: shape(from 0 20px, arc to 40px 20px of 20px cw, close)"></div>
    <div style="left: 250px; clip-path: url(#missing)"></div>
    """)
    var uep = [uint8](repeating: 0, count: 300 * 100 * 4)
    ue.Draw(into: &uep, width: 300, height: 100, scale: 1)
    func uec(x: int32, y: int32) -> draw.Color { return pixelAt(uep, 300, x, y) }
    let ueRed = draw.Color(255, 0, 0)
    check(uec(10, 20) == ueRed && uec(30, 20) == draw.Color.white, "clip-path: url() on an element (got \(uec(10, 20)) \(uec(30, 20)))")
    check(uec(60, 20) == ueRed && uec(80, 20) == draw.Color.white, "in objectBoundingBox units (got \(uec(60, 20)) \(uec(80, 20)))")
    check(uec(110, 20) == ueRed && uec(130, 20) == draw.Color.white, "mask: url() on an element (got \(uec(110, 20)) \(uec(130, 20)))")
    check(uec(170, 20).B > 200 && uec(170, 20).R < 60, "filter: url() on an element (got \(uec(170, 20)))")
    check(uec(220, 5) == ueRed && uec(220, 35) == draw.Color.white && uec(202, 2) == draw.Color.white, "shape()'s arc is an arc (got \(uec(220, 5)) \(uec(220, 35)) \(uec(202, 2)))")
    check(uec(270, 20) == ueRed, "a url() that names nothing doesn't clip (got \(uec(270, 20)))")

    // Anchor positioning.
    let an = web.Page()
    an.SetViewportSize(draw.Size(400, 300))
    an.LoadHTML("""
    <style>body { margin: 0 } #a { anchor-name: --btn; position: absolute; left: 100px; top: 100px; width: 50px; height: 20px }
    .tip { position: absolute; position-anchor: --btn; width: 30px; height: 10px }
    #t1 { top: anchor(bottom); left: anchor(left) }
    #t2 { bottom: anchor(top); right: anchor(right) }
    #t3 { left: calc(anchor(right) + 5px); top: anchor(center) }
    #t4 { width: anchor-size(width); top: anchor(--btn bottom) }
    #t5 { position-area: bottom }
    #t6 { position-area: right span-bottom }
    #flip { anchor-name: --low; position: absolute; left: 10px; top: 280px; width: 40px; height: 10px }
    #t7 { position-anchor: --low; top: anchor(bottom); left: anchor(left); position-try-fallbacks: flip-block; height: 30px }
    #t8 { position-anchor: --none; top: anchor(bottom, 7px); left: 3px }
    @position-try --above { bottom: anchor(top); left: anchor(left) }
    #t9 { position-anchor: --low; top: anchor(bottom); left: anchor(left); position-try-fallbacks: --above; height: 30px }
    </style>
    <div id=a></div><div id=flip></div>
    <div class=tip id=t1></div><div class=tip id=t2></div><div class=tip id=t3></div><div class=tip id=t4></div><div class=tip id=t5></div><div class=tip id=t6></div><div class=tip id=t7></div><div class=tip id=t8></div><div class=tip id=t9></div>
    """)
    func anb(id: string) -> draw.Rect { return an.BoundsOf(an.QuerySelector("#" + id)!)! }
    check(anb("t1").X == 100 && anb("t1").Y == 120, "top: anchor(bottom), left: anchor(left) (got \(anb("t1")))")
    check(anb("t2").X == 120 && anb("t2").Y == 90, "bottom: anchor(top), right: anchor(right) (got \(anb("t2")))")
    check(anb("t3").X == 155 && anb("t3").Y == 110, "calc() on anchor(), and its center (got \(anb("t3")))")
    check(anb("t4").Width == 50 && anb("t4").Y == 120, "anchor-size(), and an anchor named outright (got \(anb("t4")))")
    check(anb("t5").Y == 120 && anb("t5").X == 110, "position-area: bottom centers under it (got \(anb("t5")))")
    check(anb("t6").X == 150 && anb("t6").Y == 100, "position-area with a span (got \(anb("t6")))")
    check(anb("t7").Y == 250, "flip-block where it would leave the viewport (got \(anb("t7")))")
    check(anb("t8").Y == 7, "an anchor there isn't takes the fallback (got \(anb("t8")))")
    check(anb("t9").Y == 250, "an @position-try fallback (got \(anb("t9")))")
    // An anchor with text in it, inside a positioned box.
    let an2 = web.Page()
    an2.SetViewportSize(draw.Size(400, 300))
    an2.LoadHTML("""
    <style>body { margin: 0 } .col { position: absolute; left: 12px; top: 12px; width: 190px } #b { anchor-name: --b; width: 80px; padding: 6px } .tip { position: absolute; position-anchor: --b; width: 20px; height: 10px }
    #u { position-area: bottom } #r { left: anchor(right); top: anchor(top) }</style>
    <div class=col><div id=b>Button</div><div class=tip id=u></div><div class=tip id=r></div></div>
    """)
    let an2b = an2.BoundsOf(an2.QuerySelector("#b")!)!
    let an2u = an2.BoundsOf(an2.QuerySelector("#u")!)!
    let an2r = an2.BoundsOf(an2.QuerySelector("#r")!)!
    check(an2u.Y == an2b.Y + an2b.Height && an2u.X == an2b.X + (an2b.Width - 20) / 2, "an anchor with text: position-area goes under it (got \(an2u), anchor \(an2b))")
    check(an2r.X == an2b.X + an2b.Width && an2r.Y == an2b.Y, "and anchor() beside it (got \(an2r))")
    an.Document?.SetAttribute(an.QuerySelector("#a")!, "style", "left: 200px")
    check(anb("t1").X == 200, "it follows its anchor (got \(anb("t1")))")

    // Scroll-driven animations.
    let sd = web.Page()
    sd.SetViewportSize(draw.Size(100, 100))
    sd.LoadHTML("""
    <style>body { margin: 0; height: 1100px; padding-top: 1px; box-sizing: border-box } @keyframes grow { from { width: 0px } to { width: 100px } }
    #bar { position: fixed; top: 0; left: 0; height: 5px; background: red; animation: grow linear both; animation-timeline: scroll(root) }
    #in { margin-top: 499px; height: 100px; animation: grow linear both; animation-timeline: view() }
    #ranged { margin-top: 200px; height: 100px; animation: grow linear both; animation-timeline: view(); animation-range: entry 0% entry 100% }</style>
    <div id=bar></div><div id=in></div><div id=ranged></div>
    """)
    func sdw(id: string) -> float32 { return sd.BoundsOf(sd.QuerySelector("#" + id)!)!.Width }
    check(sdw("bar") == 0, "scroll(): nothing scrolled is the start (got \(sdw("bar")))")
    check(!sd.NeedsAnimation(), "and it asks for no frames at rest")
    sd.SetScrollOffset(draw.Point(0, 500))
    check(sdw("bar") == 50, "half the scroll is half the animation (got \(sdw("bar")))")
    // #in is 500 to 600 down: cover runs 400 to 600.
    check(sdw("in") == 50, "view(): halfway through the view (got \(sdw("in")))")
    sd.SetScrollOffset(draw.Point(0, 750))
    // #ranged is 800 to 900 down: entry runs 700 to 800.
    check(sdw("ranged") == 50, "animation-range narrows it to the entry (got \(sdw("ranged")))")

    // View transitions.
    let vw = web.Page()
    vw.SetViewportSize(draw.Size(100, 100))
    vw.LoadHTML("<style>body { margin: 0; background: rgb(255,0,0) }</style><div id=d></div>")
    var vwp = [uint8](repeating: 0, count: 100 * 100 * 4)
    vw.Draw(into: &vwp, width: 100, height: 100, scale: 1)
    vw.StartViewTransition {
        vw.Document?.SetAttribute(vw.Document!.Tree.ElementsByTagName("body").first!, "style", "background: rgb(0,0,255)")
    }
    check(vw.NeedsAnimation(), "a view transition asks for frames")
    _ = vw.Advance(time: 10)
    vw.Draw(into: &vwp, width: 100, height: 100, scale: 1)
    check(pixelAt(vwp, 100, 50, 50).R == 255 && pixelAt(vwp, 100, 50, 50).B == 0, "it starts on the old picture (got \(pixelAt(vwp, 100, 50, 50)))")
    _ = vw.Advance(time: 10.125)
    vw.Draw(into: &vwp, width: 100, height: 100, scale: 1)
    let halfway = pixelAt(vwp, 100, 50, 50)
    // Eased, as the user agent's animation is: ease at half the time is
    // about 0.8 of the way.
    check(halfway.R > 30 && halfway.R < 80 && halfway.B > 170, "and fades, eased (got \(halfway))")
    _ = vw.Advance(time: 10.3)
    vw.Draw(into: &vwp, width: 100, height: 100, scale: 1)
    check(pixelAt(vwp, 100, 50, 50) == draw.Color(0, 0, 255) && !vw.NeedsAnimation(), "to the new (got \(pixelAt(vwp, 100, 50, 50)))")
    // A group's own timing, by its view-transition-class.
    let vc = web.Page()
    vc.SetViewportSize(draw.Size(100, 100))
    vc.LoadHTML("""
    <style>body { margin: 0; background: white } #a { position: absolute; left: 0; top: 0; width: 20px; height: 20px; background: rgb(0,255,0); view-transition-name: a; view-transition-class: slow }
    ::view-transition-group(.slow) { animation-duration: 1s; animation-timing-function: linear } ::view-transition-group(root) { animation-duration: 0.2s }</style><div id=a></div>
    """)
    var vcp = [uint8](repeating: 0, count: 100 * 100 * 4)
    vc.Draw(into: &vcp, width: 100, height: 100, scale: 1)
    vc.StartViewTransition {
        vc.Document?.SetAttribute(vc.QuerySelector("#a")!, "style", "left: 60px")
    }
    _ = vc.Advance(time: 10)
    _ = vc.Advance(time: 10.5)
    vc.Draw(into: &vcp, width: 100, height: 100, scale: 1)
    let vcMid = pixelAt(vcp, 100, 40, 10)
    check(vc.NeedsAnimation() && vcMid.R > 90 && vcMid.R < 170 && vcMid.G > 200,
          "a group with view-transition-class runs on its own timing, past the page's fade (got \(vcMid))")
    _ = vc.Advance(time: 11.1)
    check(!vc.NeedsAnimation(), "and the transition ends with its last group")

    let nav = web.Page()
    nav.SetViewportSize(draw.Size(100, 100))
    nav.LoadHTML("<style>body { background: rgb(255,0,0) }</style>")
    var navp = [uint8](repeating: 0, count: 100 * 100 * 4)
    nav.Draw(into: &navp, width: 100, height: 100, scale: 1)
    nav.LoadHTML("<style>@view-transition { navigation: auto } body { background: rgb(0,0,255) }</style>")
    check(nav.NeedsAnimation(), "@view-transition: a new page that asks fades in")
    let plain = web.Page()
    plain.SetViewportSize(draw.Size(100, 100))
    plain.LoadHTML("<p>a</p>")
    plain.Draw(into: &navp, width: 100, height: 100, scale: 1)
    plain.LoadHTML("<p>b</p>")
    check(!plain.NeedsAnimation(), "and one that doesn't just shows")

    // Vertical text.
    let vt = web.Page()
    vt.SetViewportSize(draw.Size(400, 300))
    vt.LoadHTML("""
    <style>body { margin: 0; background: white; font-size: 20px; line-height: 20px } .v { writing-mode: vertical-rl; height: 100px; position: absolute; top: 0 } span { background: rgb(255,0,0) }
    .pic { width: 30px; height: 10px; display: block; background: rgb(0,0,255) }</style>
    <div class=v id=rl style="left: 0"><span>aaa</span><br>bbb</div>
    <div class=v id=lr style="left: 100px; writing-mode: vertical-lr"><span>aaa</span><br>bbb</div>
    <div class=v id=sz style="left: 200px; width: 50px; height: 60px; background: rgb(0,255,0)"></div>
    <div class=v id=kid style="left: 300px"><div class=pic id=pic></div></div>
    <p id=flow style="position: absolute; top: 200px; left: 0; margin: 0; writing-mode: vertical-rl; height: 80px">ab</p>
    """)
    var vtp = [uint8](repeating: 0, count: 400 * 300 * 4)
    vt.Draw(into: &vtp, width: 400, height: 300, scale: 1)
    func vtc(x: int32, y: int32) -> draw.Color { return pixelAt(vtp, 400, x, y) }
    let vrl = vt.BoundsOf(vt.QuerySelector("#rl")!)!
    check(vrl.Width == 40 && vrl.Height == 100, "a vertical box is as wide as its lines stack, and its height is what they run along (got \(vrl.Width) x \(vrl.Height))")
    // The span with the first line is red: which side it lands on says
    // which way the lines go.
    func redIn(x0: int32, x1: int32) -> int {
        var n = 0
        var cx = x0
        while cx < x1 {
            var cy: int32 = 0
            while cy < 60 {
                if vtc(cx, cy) == draw.Color(255, 0, 0) { n += 1 }
                cy += 1
            }
            cx += 1
        }
        return n
    }
    check(redIn(20, 40) > 3 * redIn(0, 20), "vertical-rl: the first line is at the right (\(redIn(20, 40)) \(redIn(0, 20)))")
    check(redIn(100, 120) > 3 * redIn(120, 140), "vertical-lr: the first line is at the left (\(redIn(100, 120)) \(redIn(120, 140)))")
    let vsz = vt.BoundsOf(vt.QuerySelector("#sz")!)!
    check(vsz.Width == 50 && vsz.Height == 60, "its own width and height are physical (got \(vsz.Width) x \(vsz.Height))")
    check(vtc(245, 55) == draw.Color(0, 255, 0), "and its background fills them")
    // A child with a physical width and height shows those, however it is laid out.
    check(vtc(301, 5) != draw.Color.white || vtc(325, 5) != draw.Color.white, "a child's physical size shows (got \(vtc(301, 5)) \(vtc(325, 5)))")
    var bluePixels = 0
    var vbx: int32 = 296
    while vbx < 400 {
        var vby: int32 = 0
        while vby < 120 {
            if vtc(vbx, vby) == draw.Color(0, 0, 255) { bluePixels += 1 }
            vby += 1
        }
        vbx += 1
    }
    check(bluePixels == 300, "a block inside keeps its physical 30 by 10 (\(bluePixels) pixels)")
    let hitV = vt.ElementAt(draw.Point(30, 2))
    check(hitV?.TagName == "span", "a click finds what's drawn there (got \(hitV?.TagName ?? "nothing"))")

    // CJK wraps between its characters, not before a closing mark.
    let cj = web.Page()
    cj.SetViewportSize(draw.Size(400, 300))
    cj.LoadHTML("<style>body { margin: 0; font-size: 20px; line-height: 1 } p { margin: 0; width: 100px }</style><p id=a>\u{65E5}\u{672C}\u{8A9E}\u{65E5}\u{672C}\u{8A9E}\u{65E5}\u{672C}\u{8A9E}\u{65E5}\u{672C}\u{8A9E}</p><p id=b style='width: 40px'>\u{65E5}\u{672C}\u{3002}\u{65E5}</p><p id=c style='white-space: nowrap'>\u{65E5}\u{672C}\u{8A9E}\u{65E5}\u{672C}\u{8A9E}\u{65E5}\u{672C}\u{8A9E}</p>")
    let cjA = cj.BoxFor(cj.QuerySelector("#a")!)!
    check(cjA.Lines.count == 3, "ideographs wrap anywhere (got \(cjA.Lines.count) lines)")
    let cjB = cj.BoxFor(cj.QuerySelector("#b")!)!
    if cjB.Lines.count > 1, let opener = cjB.Lines[1].Fragments.first {
        check(!opener.Text.hasPrefix("\u{3002}"), "a full stop doesn't start a line (\(opener.Text))")
    } else {
        check(false, "those lines wrap (\(cjB.Lines.count))")
    }
    check(cj.BoxFor(cj.QuerySelector("#c")!)!.Lines.count == 1, "nowrap keeps them on one line")
    let keep = web.Page()
    keep.SetViewportSize(draw.Size(400, 300))
    keep.LoadHTML("<style>body { margin: 0; font-size: 20px; line-height: 1 } p { margin: 0; width: 100px; word-break: keep-all }</style><p id=k>\u{65E5}\u{672C}\u{8A9E}\u{65E5}\u{672C}\u{8A9E}\u{65E5}\u{672C}\u{8A9E}</p>")
    check(keep.BoxFor(keep.QuerySelector("#k")!)!.Lines.count == 1, "word-break: keep-all doesn't break them")

    // fit-content across a vertical box holds its lines at its own height.
    let vf = web.Page()
    vf.SetViewportSize(draw.Size(400, 400))
    vf.LoadHTML("<style>body { margin: 0; font-size: 20px; line-height: 20px } #f { writing-mode: vertical-rl; height: 60px; width: fit-content }</style><div id=f>aaaaaa bbbbbb cccccc dddddd</div>")
    check(vf.BoundsOf(vf.QuerySelector("#f")!)!.Width >= 60, "fit-content across a vertical box counts its lines at its own height (got \(vf.BoundsOf(vf.QuerySelector("#f")!)!.Width))")

    // The accessibility tree.
    let ax = web.Page()
    ax.SetViewportSize(draw.Size(400, 400))
    ax.LoadHTML("""
    <title>Shop</title><style>body { margin: 0 } .gone { display: none }</style>
    <nav aria-label="Main"><a href="/x">Home</a></nav>
    <div><div><h2>Basket</h2></div></div>
    <p>Some words</p>
    <img src=a.png alt="A cat" width=10 height=10>
    <label for=q>Search for</label><input id=q value="socks">
    <label><input id=c type=checkbox checked> Gift wrap</label>
    <button id=b onclick="">Buy now</button><button disabled>Off</button>
    <select id=s aria-label="Size"><option>S</option><option selected>M</option></select>
    <div class=gone><button>Hidden</button></div><div aria-hidden=true><button>Also hidden</button></div>
    <input type=password id=pw value="secret">
    """)
    guard let tree = ax.AccessibilityTree() else { check(false, "a page has an accessibility tree"); return }
    func axFind(role: string, name: string) -> web.AccessibleNode? {
        func walk(n: web.AccessibleNode) -> web.AccessibleNode? {
            if n.Role == role && n.Name == name { return n }
            for c in n.Children {
                if let f = walk(c) { return f }
            }
            return nil
        }
        return walk(tree)
    }
    check(tree.Role == "document" && tree.Name == "Shop", "the root is the document, named by its title (got \(tree.Role) \(tree.Name))")
    check(axFind("navigation", "Main") != nil && axFind("link", "Home") != nil, "a landmark and a link inside it")
    let heading = axFind("heading", "Basket")
    check(heading != nil && heading?.Level == 2, "a heading has its level, and the divs round it aren't in the tree")
    check(axFind("text", "Some words") != nil, "text is there")
    check(axFind("img", "A cat") != nil, "an image is named by its alt")
    let field = axFind("textbox", "Search for")
    check(field?.Value == "socks", "a field is named by its label, and has its value (got \(field?.Value ?? "none"))")
    let box = axFind("checkbox", "Gift wrap")
    check(box?.Checked == true, "a checkbox named by the label that holds it, and checked")
    check(axFind("button", "Buy now") != nil && axFind("button", "Off")?.Disabled == true, "buttons, and one disabled")
    check(axFind("combobox", "Size")?.Value == "M", "a select says what's chosen")
    check(axFind("button", "Hidden") == nil && axFind("button", "Also hidden") == nil, "display: none and aria-hidden aren't there")
    var pwValue = "unset"
    func walkPw(n: web.AccessibleNode) {
        if n.Id == ax.QuerySelector("#pw")!.Id { pwValue = n.Value }
        for c in n.Children { walkPw(c) }
    }
    walkPw(tree)
    check(pwValue == "", "a password's value isn't told (got \(pwValue))")
    var pressed = 0
    if let buy = ax.QuerySelector("#b") { _ = ax.Document?.AddEventListener(buy, "click", handler: { e in pressed += 1 }) }
    if let buy = axFind("button", "Buy now") { ax.AccessibilityPress(buy.Id) }
    check(pressed == 1, "pressing it clicks the button (got \(pressed))")
    if let f = field {
        ax.AccessibilityFocus(f.Id)
        ax.AccessibilitySetValue(f.Id, value: "hats")
    }
    check(ax.FocusedElement?.GetAttribute("id") == "q" && ax.ValueOf(ax.QuerySelector("#q")!) == "hats", "focus and a value can be set")
    check(ax.AccessibilityTree()?.Role == "document", "and the tree can be asked again")

    // Right-to-left fields, and a bar on the left.
    let rt = web.Page()
    rt.SetViewportSize(draw.Size(300, 200))
    rt.LoadHTML("""
    <style>body { margin: 0; background: white } input { display: block; width: 200px; height: 30px; font-size: 20px; padding: 0; border: 0; caret-color: rgb(255,0,0) } textarea { display: block; width: 200px; height: 30px; padding: 0; border: 0 }
    #sc { direction: rtl; overflow: auto; width: 100px; height: 50px } #sc div { height: 200px }</style>
    <input id=ar dir=rtl value="\u{5D0}\u{5D1}\u{5D2}"><input id=en dir=rtl value="abc"><div id=sc><div></div></div>
    """)
    guard let ar = rt.QuerySelector("#ar"), let en = rt.QuerySelector("#en") else { return }
    func caretColumn() -> int32 {
        var buf = [uint8](repeating: 0, count: 300 * 200 * 4)
        rt.Draw(into: &buf, width: 300, height: 200, scale: 1)
        var x: int32 = 0
        let fy: int32 = int32(rt.BoundsOf(rt.FocusedElement ?? ar)!.Y + 15)
        while x < 300 {
            if pixelAt(buf, 300, x, fy) == draw.Color(255, 0, 0) { return x }
            x += 1
        }
        return -1
    }
    rt.Focus(ar)
    _ = rt.Handle(.keyDown(web.Key(Key: "Home", Code: "Home")))
    _ = rt.Advance(time: 0)
    let atStart = caretColumn()
    check(atStart > 190, "right-to-left text's start is at the field's right (got \(atStart))")
    _ = rt.Handle(.keyDown(web.Key(Key: "ArrowLeft", Code: "ArrowLeft")))
    _ = rt.Advance(time: 0)
    let moved = caretColumn()
    check(moved >= 0 && moved < atStart, "the left arrow moves the caret left, on through the text (got \(moved) from \(atStart))")
    let b0 = rt.BoundsOf(ar)!
    _ = rt.Handle(.pointerMoved(draw.Point(b0.X + 198, b0.Y + 15)))
    _ = rt.Handle(.pointerDown(web.Pointer(draw.Point(b0.X + 198, b0.Y + 15))))
    _ = rt.Handle(.pointerUp(web.Pointer(draw.Point(b0.X + 198, b0.Y + 15))))
    _ = rt.Advance(time: 0)
    check(caretColumn() == atStart, "a click at the field's right is its text's start (got \(caretColumn()))")
    rt.Focus(en)
    _ = rt.Handle(.keyDown(web.Key(Key: "End", Code: "End")))
    _ = rt.Advance(time: 0)
    check(caretColumn() > 190, "left-to-right text in such a field ends at its right (got \(caretColumn()))")
    var rtb = [uint8](repeating: 0, count: 300 * 200 * 4)
    rt.Draw(into: &rtb, width: 300, height: 200, scale: 1)
    let sb = rt.BoundsOf(rt.QuerySelector("#sc")!)!
    check(pixelAt(rtb, 300, int32(sb.X) + 5, int32(sb.Y) + 5) != draw.Color.white && pixelAt(rtb, 300, int32(sb.X) + 95, int32(sb.Y) + 5) == draw.Color.white,
          "a right-to-left scroller's bar is on its left")
    let rl = web.Page()
    rl.SetViewportSize(draw.Size(300, 300))
    rl.LoadHTML("""
    <style>body { margin: 0; font-size: 20px; line-height: 1 } #hold { position: relative; direction: rtl; width: 200px; height: 40px } #abs { position: absolute; width: 30px; height: 10px }
    table { border-collapse: collapse; direction: rtl } td { border: 2px solid black; width: 20px; height: 20px; padding: 0 }</style>
    <div id=hold><div id=abs></div></div>
    <table><tr><td id=first></td><td id=second></td></tr></table>
    """)
    func rlBox(id: string) -> layout.Box { return rl.BoxFor(rl.QuerySelector("#" + id)!)! }
    check(rlBox("abs").X == rlBox("hold").Width - 30, "an absolute box with no insets starts at the right (got \(rlBox("abs").X))")
    check(rlBox("first").Border.Right == 2 && rlBox("first").Border.Left == 2, "the first cell at the right draws both sides (got \(rlBox("first").Border.Right) \(rlBox("first").Border.Left))")
    check(rlBox("second").Border.Right == 0 && rlBox("second").Border.Left == 2, "the next shares its edge there (got \(rlBox("second").Border.Right) \(rlBox("second").Border.Left))")
    // An element split by reordering draws a span per piece.
    let sp = web.Page()
    sp.SetViewportSize(draw.Size(400, 40))
    sp.LoadHTML("<style>body { margin: 0; font-size: 20px; line-height: 1 } b { font-weight: normal }</style><p style='margin: 0'>start \u{5D0}<b id=m>\u{5D1} word more \u{5D2}</b>\u{5D3} end</p>")
    if let pb = sp.BoxFor(sp.QuerySelector("p")!) , let line = pb.Lines.first {
        var count = 0
        for span in line.Spans { if span.Box.Node?.GetAttribute("id") == "m" { count += 1 } }
        check(count >= 2, "an inline element split by reordering has a span for each piece (got \(count))")
    }

    // A select's list, a calendar, and a palette, in the page.
    let pk = web.Page()
    pk.SetViewportSize(draw.Size(300, 400))
    pk.LoadHTML("""
    <style>body { margin: 0; background: white } select { display: block; width: 100px; height: 24px } input { display: block; width: 120px; height: 24px; margin-top: 4px }</style>
    <select id=s><option>One</option><option disabled>Two</option><option>Three</option></select>
    <input id=d type=date value="2026-02-10"><input id=c type=color value="#000000"><input id=t type=time><input id=m type=month value="2026-03"><input id=w type=week>
    """)
    guard let pSel = pk.QuerySelector("#s"), let pDate = pk.QuerySelector("#d"), let pColor = pk.QuerySelector("#c"), let pTime = pk.QuerySelector("#t"), let pMonth = pk.QuerySelector("#m"), let pWeek = pk.QuerySelector("#w"), let pkDoc = pk.Document else { return }
    var changes = 0
    _ = pkDoc.AddEventListener(pSel, "change", handler: { e in changes += 1 })
    func clickAt(x: float32, y: float32) {
        _ = pk.Handle(.pointerMoved(draw.Point(x, y)))
        _ = pk.Handle(.pointerDown(web.Pointer(draw.Point(x, y))))
        _ = pk.Handle(.pointerUp(web.Pointer(draw.Point(x, y))))
    }
    func clickOn(n: html.Node) {
        let b = pk.BoundsOf(n)!
        clickAt(b.X + 5, b.Y + 5)
    }
    var pkp = [uint8](repeating: 0, count: 300 * 400 * 4)
    clickOn(pSel)
    pk.Draw(into: &pkp, width: 300, height: 400, scale: 1)
    let selBox = pk.BoundsOf(pSel)!
    let rowY = selBox.Y + selBox.Height + 2
    check(pixelAt(pkp, 300, 90, int32(rowY) + 12) != draw.Color.white, "clicking a select opens its list, the chosen row lit (got \(pixelAt(pkp, 300, 90, int32(rowY) + 12)))")
    clickAt(20, rowY + 24 + 12)
    check(dom.SelectedValue(pSel) == "One" && changes == 0, "a disabled option can't be chosen (got \(dom.SelectedValue(pSel)))")
    clickAt(20, rowY + 48 + 12)
    check(dom.SelectedValue(pSel) == "Three" && changes == 1, "a row chooses its option, and change fires (got \(dom.SelectedValue(pSel)), \(changes))")
    clickOn(pSel)
    clickAt(250, 390)
    clickOn(pSel)
    _ = pk.Handle(.keyDown(web.Key(Key: "Escape", Code: "Escape")))
    check(dom.SelectedValue(pSel) == "Three", "a press outside and Escape close it, choosing nothing")
    _ = pk.Handle(.keyDown(web.Key(Key: "Enter", Code: "Enter")))
    _ = pk.Handle(.keyDown(web.Key(Key: "ArrowUp", Code: "ArrowUp")))
    _ = pk.Handle(.keyDown(web.Key(Key: "ArrowUp", Code: "ArrowUp")))
    _ = pk.Handle(.keyDown(web.Key(Key: "Enter", Code: "Enter")))
    check(dom.SelectedValue(pSel) == "One", "keys open it, move and choose (got \(dom.SelectedValue(pSel)))")
    // February 2026: the first is a Sunday; the 18th is a Wednesday, row 2.
    clickOn(pDate)
    let dBox = pk.BoundsOf(pDate)!
    let calY = dBox.Y + dBox.Height + 2
    clickAt(dBox.X + 3 * 30 + 15, calY + 48 + 2 * 30 + 15)
    check(pk.ValueOf(pDate) == "2026-02-18", "a calendar's day sets a date (got \(pk.ValueOf(pDate)))")
    clickOn(pDate)
    clickAt(dBox.X + 210 - 12, calY + 12)
    clickAt(dBox.X + 15, calY + 48 + 15)
    check(pk.ValueOf(pDate) == "2026-03-01", "its arrow goes to the next month, whose first is a Sunday (got \(pk.ValueOf(pDate)))")
    clickOn(pColor)
    let cBox = pk.BoundsOf(pColor)!
    clickAt(cBox.X + 8 * 24 - 12, cBox.Y + cBox.Height + 2 + 5 * 24 + 12)
    check(pk.ValueOf(pColor) == "#000000", "a palette's darkest gray is black (got \(pk.ValueOf(pColor)))")
    clickOn(pColor)
    clickAt(cBox.X + 12, cBox.Y + cBox.Height + 2 + 2 * 24 + 12)
    check(pk.ValueOf(pColor) != "#000000" && pk.ValueOf(pColor).hasPrefix("#"), "and a swatch sets a color (got \(pk.ValueOf(pColor)))")
    clickOn(pTime)
    _ = pk.Handle(.keyDown(web.Key(Key: "ArrowDown", Code: "ArrowDown")))
    _ = pk.Handle(.keyDown(web.Key(Key: "Enter", Code: "Enter")))
    check(pk.ValueOf(pTime) == "09:30", "a list of times (got \(pk.ValueOf(pTime)))")
    clickOn(pMonth)
    pk.PressPanelCell(text: "Apr")
    check(pk.ValueOf(pMonth) == "2026-04", "a month's grid (got \(pk.ValueOf(pMonth)))")
    clickOn(pWeek)
    pk.PressPanelCell(text: "15")
    check(pk.ValueOf(pWeek).hasPrefix("20") && pk.ValueOf(pWeek).contains("-W"), "a day in a week field is its week (got \(pk.ValueOf(pWeek)))")

    // appearance: base-select.
    let bs = web.Page()
    bs.SetViewportSize(draw.Size(300, 200))
    bs.LoadHTML("""
    <style>body { margin: 0; background: white } select, ::picker(select) { appearance: base-select } select { width: 150px } option { height: 30px } option b { color: rgb(255,0,0) } ::picker(select) { background-color: rgb(0,0,255) } select:open { outline: 2px solid rgb(0,255,0) }</style>
    <select id=s><button id=btn><selectedcontent></selectedcontent></button><option id=a><b>Rich</b> one</option><option id=c>Plain two</option></select>
    <p id=after>after</p>
    """)
    guard let bsel = bs.QuerySelector("#s"), let bbtn = bs.QuerySelector("#btn"), let boptC = bs.QuerySelector("#c") else { return }
    _ = bs.BoundsOf(bsel)
    let bsBox = bs.BoxFor(bsel)!
    check(bsBox.Replaced == .none, "a base-select lays out its own content (got \(bsBox.Replaced))")
    check(bs.BoxFor(boptC) == nil, "closed, its options have no boxes")
    let afterY = bs.BoundsOf(bs.QuerySelector("#after")!)!.Y
    let bbtnAt = bs.BoundsOf(bbtn)!
    _ = bs.Handle(.pointerDown(web.Pointer(draw.Point(bbtnAt.X + 4, bbtnAt.Y + 4))))
    _ = bs.Handle(.pointerUp(web.Pointer(draw.Point(bbtnAt.X + 4, bbtnAt.Y + 4))))
    guard let open = bs.BoundsOf(boptC) else { check(false, "clicking its button opens the picker"); return }
    check(open.Height == 30, "open, its options are laid out as their rules say (got \(open.Height))")
    let closedAt = bs.BoundsOf(bsel)!
    check(open.Y >= closedAt.Y + closedAt.Height && open.X >= closedAt.X && open.X < closedAt.X + 10 && open.Width <= closedAt.Width,
          "the picker hangs under the select, as wide as it (option at \(open.X),\(open.Y) width \(open.Width); select \(closedAt.X),\(closedAt.Y) \(closedAt.Width)x\(closedAt.Height))")
    check(bs.BoundsOf(bs.QuerySelector("#after")!)!.Y == afterY, "and the picker pushes nothing down")
    var bsp = [uint8](repeating: 0, count: 300 * 200 * 4)
    bs.Draw(into: &bsp, width: 300, height: 200, scale: 1)
    var picked = false
    var redText = false
    var py: int32 = 0
    while py < 200 {
        var px: int32 = 0
        while px < 300 {
            let c = pixelAt(bsp, 300, px, py)
            if c == draw.Color(0, 0, 255) { picked = true }
            if c.R > 200 && c.G < 60 && c.B < 60 { redText = true }
            px += 1
        }
        py += 1
    }
    check(picked, "::picker(select) styles the picker")
    check(redText, "and an option's rich content shows")
    _ = bs.Handle(.pointerDown(web.Pointer(draw.Point(open.X + 4, open.Y + 4))))
    _ = bs.Handle(.pointerUp(web.Pointer(draw.Point(open.X + 4, open.Y + 4))))
    check(dom.SelectedValue(bsel) == "Plain two", "clicking an option chooses it (got \(dom.SelectedValue(bsel)))")
    check(bs.BoxFor(boptC) == nil, "and closes")
    check(bbtn.InnerText().isEmpty && bs.BoundsOf(bbtn)!.Width > 20, "<selectedcontent> shows the choice")

    // Scroll anchoring, and a page that stretches at its end.
    let ah = web.Page()
    ah.SetViewportSize(draw.Size(100, 100))
    ah.LoadHTML("<style>body { margin: 0; background: rgb(0,255,0) } div { height: 100px } #top { background: rgb(255,0,0) }</style><div id=top></div><div id=a></div><div id=b></div><div id=c></div><div id=d></div><div id=e></div>")
    _ = ah.BoundsOf(ah.QuerySelector("#a")!)
    ah.SetScrollOffset(draw.Point(0, 250))
    let topBox = ah.QuerySelector("#top")!
    ah.Document?.SetAttribute(topBox, "style", "height: 150px")
    _ = ah.BoundsOf(topBox)
    check(ah.ScrollOffset().Y == 300, "content growing above the view keeps the place being read (got \(ah.ScrollOffset().Y))")
    ah.Document?.SetAttribute(ah.QuerySelector("#top")!, "style", "height: 100px")
    _ = ah.BoundsOf(topBox)
    check(ah.ScrollOffset().Y == 250, "and shrinking does too (got \(ah.ScrollOffset().Y))")
    ah.SetScrollOffset(draw.Point(0, 0))
    ah.Bounces = true
    _ = ah.Handle(.pointerMoved(draw.Point(50, 50)))
    _ = ah.Handle(.wheel(web.Wheel(draw.Point(0, 100), precise: true)))
    check(ah.NeedsAnimation(), "a scroll past the top stretches the page, and asks for frames")
    var ahp = [uint8](repeating: 0, count: 100 * 100 * 4)
    ah.Draw(into: &ahp, width: 100, height: 100, scale: 1)
    check(pixelAt(ahp, 100, 50, 10) != draw.Color(255, 0, 0) && pixelAt(ahp, 100, 50, 60) == draw.Color(255, 0, 0), "drawn moved down (got \(pixelAt(ahp, 100, 50, 10)) \(pixelAt(ahp, 100, 50, 60)))")
    var when: float64 = 0
    while when < 2 {
        _ = ah.Advance(time: when)
        when += 0.05
    }
    check(!ah.NeedsAnimation(), "and it eases back")
    ah.Draw(into: &ahp, width: 100, height: 100, scale: 1)
    check(pixelAt(ahp, 100, 50, 10) == draw.Color(255, 0, 0), "to where it was (got \(pixelAt(ahp, 100, 50, 10)))")

    // The smaller properties and at-rules.
    let sm = web.Page()
    sm.SetViewportSize(draw.Size(300, 300))
    sm.LoadHTML("""
    <style>
    body { margin: 0; background: white; font-size: 10px; line-height: 20px }
    @function --double(--x, --y: 1px) { result: calc(var(--x) * 2 + var(--y)); }
    @counter-style thumbs { system: cyclic; symbols: "A" "B"; suffix: ") "; }
    :root { --mode: dark }
    #fn { width: --double(10px); height: 5px }
    #cond { width: if(style(--mode: light): 1px; style(--mode: dark): 22px; else: 3px); height: 5px }
    #mq { width: if(media(max-width: 10px): 1px; else: 33px); height: 5px }
    #clip { overflow: clip; overflow-clip-margin: 10px; width: 10px; height: 10px; margin: 20px } #clip div { width: 15px; height: 10px; background: rgb(255,0,0) }
    #trim { text-box: trim-both text; height: auto } #plainline { }
    #field { field-sizing: content }
    #drop::first-letter { initial-letter: 3 }
    </style>
    <div id=fn></div><div id=cond></div><div id=mq></div>
    <div id=clip><div></div></div>
    <p id=plainline style="margin: 0">x</p><p id=trim style="margin: 0">x</p>
    <div id=trimouter style="text-box: trim-both text"><p style="margin: 0">x</p><div><p style="margin: 0">y</p></div></div>
    <p id=trimcap style="margin: 0; text-box: trim-start cap">X</p><p id=trimex style="margin: 0; text-box: trim-start ex">x</p>
    <textarea id=field>one
    two lines long enough</textarea>
    <ol style="list-style-type: thumbs"><li id=one>x</li><li id=two>y</li><li id=three>z</li></ol>
    <p id=drop style="margin: 0; width: 100px">Drop cap text that goes on for some lines at least</p>
    """)
    func smBox(id: string) -> layout.Box { return sm.BoxFor(sm.QuerySelector("#" + id)!)! }
    check(smBox("fn").Width == 21, "@function: a call with a default (got \(smBox("fn").Width))")
    check(smBox("cond").Width == 22, "if(style()) takes the first branch that holds (got \(smBox("cond").Width))")
    check(smBox("mq").Width == 33, "if(media()) and else (got \(smBox("mq").Width))")
    check(smBox("plainline").Height == 20 && smBox("trim").Height < 20, "text-box-trim cuts the half-leading (got \(smBox("plainline").Height) \(smBox("trim").Height))")
    let cut = smBox("plainline").Height - smBox("trim").Height
    check(smBox("trimouter").Height == 40 - cut, "text-box-trim on a block reaches its first and last children's lines, nested too (got \(smBox("trimouter").Height), cut \(cut))")
    let capFace = smBox("trimcap").Style.Face
    let capTop = smBox("trimcap").Lines[0].Y + (20 - capFace.Ascent - capFace.Descent) / 2 + capFace.Ascent - capFace.CapHeight
    check(smBox("trimcap").Height < smBox("trim").Height + cut / 2 && smBox("trimex").Height < smBox("trimcap").Height && capFace.CapHeight > 0,
          "text-box-edge: cap trims to the font's cap height, above ex (got \(smBox("trimcap").Height) \(smBox("trimex").Height) \(capTop))")
    check(smBox("field").Width > 60 && smBox("field").Height >= 30 && smBox("field").Height < 60, "field-sizing: content fits what it holds (got \(smBox("field").Width) \(smBox("field").Height))")
    check(smBox("one").Marker == "A) " && smBox("two").Marker == "B) " && smBox("three").Marker == "A) ", "@counter-style markers (got \(smBox("one").Marker) \(smBox("two").Marker) \(smBox("three").Marker))")
    var smp = [uint8](repeating: 0, count: 300 * 300 * 4)
    sm.Draw(into: &smp, width: 300, height: 300, scale: 1)
    let clipAt = sm.BoundsOf(sm.QuerySelector("#clip")!)!
    check(pixelAt(smp, 300, int32(clipAt.X) + 13, int32(clipAt.Y) + 5) == draw.Color(255, 0, 0), "overflow-clip-margin shows what overflows by it")
    if let dropLetter = smBox("drop").Children.first {
        let left = dropLetter.Kind == .block
        check(left && dropLetter.Style.FontSize > 50, "initial-letter makes a letter lines tall, beside them (got \(dropLetter.Style.FontSize))")
    } else {
        check(false, "initial-letter makes a box for its letter")
    }

    // image-rendering.
    let ir = web.Page()
    ir.SetViewportSize(draw.Size(100, 40))
    ir.LoadHTML("<style>body { margin: 0 } img { display: block; width: 100px; height: 40px; image-rendering: pixelated }</style><img src=two.png>")
    ir.SetImage(url: "two.png", image: draw.Image(width: 2, height: 1, pixels: [255, 0, 0, 255, 0, 0, 255, 255]))
    var irp = [uint8](repeating: 0, count: 100 * 40 * 4)
    ir.Draw(into: &irp, width: 100, height: 40, scale: 1)
    check(pixelAt(irp, 100, 49, 20) == draw.Color(255, 0, 0) && pixelAt(irp, 100, 50, 20) == draw.Color(0, 0, 255), "image-rendering: pixelated keeps pixels hard (got \(pixelAt(irp, 100, 49, 20)) \(pixelAt(irp, 100, 50, 20)))")

    // @starting-style.
    let st = web.Page()
    st.SetViewportSize(draw.Size(100, 100))
    st.LoadHTML("""
    <style>body { margin: 0; background: white } #s { width: 50px; height: 50px; background: rgb(0,0,0); opacity: 1; transition: opacity 1s linear } @starting-style { #s { opacity: 0 } }</style><div id=s></div>
    """)
    _ = st.BoundsOf(st.QuerySelector("#s")!)
    _ = st.Advance(time: 10)
    _ = st.Advance(time: 10.5)
    var stp = [uint8](repeating: 0, count: 100 * 100 * 4)
    st.Draw(into: &stp, width: 100, height: 100, scale: 1)
    let mid = pixelAt(stp, 100, 20, 20)
    check(mid.R > 60 && mid.R < 200, "@starting-style: a first style transitions from it (got \(mid))")

    // scroll-snap-stop.
    let ss = web.Page()
    ss.SetViewportSize(draw.Size(100, 100))
    ss.LoadHTML("""
    <style>html { scroll-snap-type: y mandatory } body { margin: 0 } div { height: 100px; scroll-snap-align: start } #stop { scroll-snap-stop: always }</style>
    <div></div><div id=stop></div><div></div><div></div><div></div>
    """)
    _ = ss.BoundsOf(ss.QuerySelector("#stop")!)
    _ = ss.Handle(.pointerMoved(draw.Point(50, 50)))
    _ = ss.Handle(.wheel(web.Wheel(draw.Point(0, -300), precise: true)))
    var clock: float64 = 0
    while clock < 3 {
        _ = ss.Advance(time: clock)
        clock += 0.05
    }
    check(ss.ScrollOffset().Y == 100, "scroll-snap-stop: always stops a scroll that would pass it (got \(ss.ScrollOffset().Y))")

    // Links and images drag by default, with a drag image.
    let dg = web.Page()
    dg.SetViewportSize(draw.Size(200, 100))
    dg.LoadHTML("<style>body { margin: 0; background: white } a { display: block; width: 40px; height: 20px; background: rgb(255,0,0) }</style><a id=l href='http://x.test/p'></a><a id=off href='#' draggable=false style='margin-top: 20px'></a>")
    guard let dl = dg.QuerySelector("#l"), let off = dg.QuerySelector("#off"), let dgDoc = dg.Document else { return }
    var dragged = ""
    var starts = 0
    _ = dgDoc.AddEventListener(dgDoc.Tree.Root, "dragstart", handler: { e in
        starts += 1
        if let d = e as? dom.DragEvent { dragged = d.Data.GetData("text/uri-list") }
    })
    _ = dg.BoundsOf(dl)
    _ = dg.Handle(.pointerDown(web.Pointer(draw.Point(10, 10))))
    _ = dg.Handle(.pointerMoved(draw.Point(100, 60)))
    check(starts == 1 && dragged == "http://x.test/p", "a link drags by default, carrying its URL (got \(starts), \(dragged))")
    var gp = [uint8](repeating: 0, count: 200 * 100 * 4)
    dg.Draw(into: &gp, width: 200, height: 100, scale: 1)
    let ghost = pixelAt(gp, 200, 110, 60)
    check(ghost.R == 255 && ghost.G > 60 && ghost.G < 150, "and shows a faint image under the pointer (got \(ghost))")
    _ = dg.Handle(.pointerUp(web.Pointer(draw.Point(100, 60))))
    _ = dg.Handle(.pointerDown(web.Pointer(draw.Point(10, 50))))
    _ = dg.Handle(.pointerMoved(draw.Point(100, 80)))
    check(starts == 1, "draggable=false turns it off (got \(starts), \(off.TagName))")
    _ = dg.Handle(.pointerUp(web.Pointer(draw.Point(100, 80))))

    // ::highlight(), ::target-text and ::file-selector-button.
    let hl = web.Page()
    hl.SetViewportSize(draw.Size(300, 120))
    hl.LoadHTML("""
    <style>body { margin: 0; background: white; font-size: 20px } p { margin: 0 } ::highlight(found) { background-color: rgb(0,255,0) } ::target-text { background-color: rgb(255,0,255) }
    input::file-selector-button { background-color: rgb(0,0,255) } input { display: block; width: 200px; height: 30px }</style>
    <p id=a>aaaaaaaaaa</p><p id=b>find this word</p><input type=file id=f>
    """)
    guard let hp = hl.QuerySelector("#a")?.Children.first, let hpb = hl.QuerySelector("#a") else { return }
    hl.SetHighlight(name: "found", ranges: [(start: dom.TextPosition(Node: hp, Offset: 0), end: dom.TextPosition(Node: hp, Offset: 3))])
    var hx = [uint8](repeating: 0, count: 300 * 120 * 4)
    hl.Draw(into: &hx, width: 300, height: 120, scale: 1)
    func hc(x: int32, y: int32) -> draw.Color { return pixelAt(hx, 300, x, y) }
    let hb = hl.BoundsOf(hpb)!
    check(hc(1, int32(hb.Y) + 1) == draw.Color(0, 255, 0), "::highlight(name) styles its ranges (got \(hc(1, int32(hb.Y) + 1)))")
    check(hc(100, int32(hb.Y) + 1) == draw.Color.white, "and only them (got \(hc(100, int32(hb.Y) + 1)))")
    let fb = hl.BoundsOf(hl.QuerySelector("#f")!)!
    var blue = 0
    var by = int32(fb.Y)
    while by < int32(fb.Y + fb.Height) {
        var bx = int32(fb.X)
        while bx < int32(fb.X + fb.Width) {
            if hc(bx, by) == draw.Color(0, 0, 255) { blue += 1 }
            bx += 1
        }
        by += 1
    }
    check(blue > 100, "::file-selector-button restyles the button (\(blue) pixels)")
    hl.GoToFragment("#:~:text=this%20word")
    hl.Draw(into: &hx, width: 300, height: 120, scale: 1)
    let bb = hl.BoundsOf(hl.QuerySelector("#b")!)!
    var magenta = 0
    var mx: int32 = 0
    while mx < 300 {
        if hc(mx, int32(bb.Y) + 1) == draw.Color(255, 0, 255) { magenta += 1 }
        mx += 1
    }
    check(magenta > 40, "a text fragment is found and shown by ::target-text (\(magenta) pixels)")

    // 3D.
    let d3 = web.Page()
    d3.SetViewportSize(draw.Size(400, 120))
    d3.LoadHTML("""
    <style>body { margin: 0; background: white } .s { position: absolute; top: 0; width: 100px; height: 100px } .f { width: 100px; height: 100px; background: rgb(255,0,0) }</style>
    <div class=s style="left: 0; perspective: 200px"><div class=f id=near style="transform: translateZ(100px)"></div></div>
    <div class=s style="left: 200px"><div class=f id=turned style="transform: rotateY(180deg); backface-visibility: hidden"></div></div>
    <div class=s id=cube style="left: 300px; transform-style: preserve-3d"><div class=f style="position: absolute; background: rgb(0,255,0); transform: translateZ(-10px)"></div><div class=f style="position: absolute; background: rgb(0,0,255); transform: translateZ(10px)"></div><div class=f style="position: absolute; background: rgb(255,255,0); transform: translateZ(-20px)"></div></div>
    """)
    var dp = [uint8](repeating: 0, count: 400 * 120 * 4)
    d3.Draw(into: &dp, width: 400, height: 120, scale: 1)
    func dat(x: int32, y: int32) -> draw.Color { return pixelAt(dp, 400, x, y) }
    // At perspective 200 a plane 100 nearer is scaled 2: 100px becomes 200.
    check(dat(120, 50) == draw.Color(255, 0, 0) && dat(160, 50) == draw.Color.white, "translateZ under perspective draws larger (got \(dat(120, 50)) \(dat(160, 50)))")
    check(dat(250, 50) == draw.Color.white, "backface-visibility: hidden hides a turned box (got \(dat(250, 50)))")
    check(dat(350, 50) == draw.Color(0, 0, 255), "preserve-3d draws the nearest plane last, whatever the order (got \(dat(350, 50)))")
    if let n = d3.QuerySelector("#near") { check(d3.ElementAt(draw.Point(120, 50)) === n, "a 3D plane is hit where it's drawn") }
    check(d3.ElementAt(draw.Point(250, 50))?.TagName != "div" || d3.ElementAt(draw.Point(250, 50))?.GetAttribute("id") != "turned", "and a hidden back isn't hit")
    // Hit by depth, and planes that cross.
    let d3b = web.Page()
    d3b.SetViewportSize(draw.Size(300, 200))
    d3b.LoadHTML("""
    <!doctype html><style>body { margin: 0 } #ctx { position: absolute; left: 50px; top: 50px; width: 200px; height: 100px; transform-style: preserve-3d; transform: translateZ(0) }
    #ctx div { position: absolute; left: 0; top: 0; width: 200px; height: 100px }</style>
    <div id=ctx><div id=front style="background: rgb(255,0,0); transform: translateZ(10px)"></div><div id=back style="background: rgb(0,0,255); transform: translateZ(-10px)"></div></div>
    """)
    if let n = d3b.QuerySelector("#front") { check(d3b.ElementAt(draw.Point(150, 100)) === n, "the nearest plane is hit, not the one painted in order") }
    let d3c = web.Page()
    d3c.SetViewportSize(draw.Size(300, 200))
    d3c.LoadHTML("""
    <!doctype html><style>body { margin: 0 } #ctx { position: absolute; left: 50px; top: 50px; width: 200px; height: 100px; transform-style: preserve-3d; transform: translateZ(0) }
    #ctx div { position: absolute; left: 0; top: 0; width: 200px; height: 100px }</style>
    <div id=ctx><div id=a style="background: rgb(255,0,0); transform: rotateY(40deg)"></div><div id=b style="background: rgb(0,0,255); transform: rotateY(-40deg)"></div></div>
    """)
    if let a = d3c.QuerySelector("#a"), let b = d3c.QuerySelector("#b") {
        check(d3c.ElementAt(draw.Point(100, 100)) === (d3c.ElementAt(draw.Point(200, 100)) === a ? b : a), "planes that cross are hit on the nearer side of the line")
    }
    var d3cp = [uint8](repeating: 0, count: 300 * 200 * 4)
    d3c.Draw(into: &d3cp, width: 300, height: 200, scale: 1)
    let crossL = pixelAt(d3cp, 300, 110, 100)
    let crossR = pixelAt(d3cp, 300, 190, 100)
    check(crossL != crossR && crossL.A == 255 && crossR.A == 255, "planes that cross each show on their nearer side (got \(crossL) \(crossR))")

    // A base-select's picker: out of a clipping box, and flipped at the edge.
    let bf = web.Page()
    bf.SetViewportSize(draw.Size(300, 200))
    bf.LoadHTML("""
    <style>body { margin: 0 } select, ::picker(select) { appearance: base-select } select { width: 100px; height: 20px } option { height: 30px } #clip { overflow: hidden; width: 110px; height: 30px; position: absolute; top: 0; left: 0 } #low { position: absolute; top: 170px; left: 150px }</style>
    <div id=clip><select id=a><option id=a1>One</option><option id=a2>Two</option></select></div>
    <select id=low><option id=b1>One</option><option id=b2>Two</option></select>
    """)
    func openSelect(at: draw.Rect) {
        _ = bf.Handle(.pointerDown(web.Pointer(draw.Point(at.X + 4, at.Y + 4))))
        _ = bf.Handle(.pointerUp(web.Pointer(draw.Point(at.X + 4, at.Y + 4))))
    }
    openSelect(bf.BoundsOf(bf.QuerySelector("#a")!)!)
    if let o = bf.BoundsOf(bf.QuerySelector("#a2")!), let el = bf.QuerySelector("#a2") {
        check(o.Y >= 30, "a picker hangs past its clipping box (got \(o.Y))")
        check(bf.ElementAt(draw.Point(o.X + 4, o.Y + 4)) === el, "and is hit there")
        var cp = [uint8](repeating: 0, count: 300 * 200 * 4)
        bf.Draw(into: &cp, width: 300, height: 200, scale: 1)
        check(pixelAt(cp, 300, int32(o.X) + 50, int32(o.Y) + 15) == draw.Color.white, "and shows there (got \(pixelAt(cp, 300, int32(o.X) + 50, int32(o.Y) + 15)))")
    } else { check(false, "a picker opens in a clipping box") }
    _ = bf.Handle(.pointerDown(web.Pointer(draw.Point(290, 5))))
    _ = bf.Handle(.pointerUp(web.Pointer(draw.Point(290, 5))))
    let lowAt = bf.BoundsOf(bf.QuerySelector("#low")!)!
    openSelect(lowAt)
    if let o = bf.BoundsOf(bf.QuerySelector("#b2")!) {
        check(o.Y + o.Height <= lowAt.Y, "a picker with no room below flips above (option at \(o.Y), select at \(lowAt.Y))")
    } else { check(false, "the low picker opens") }

    // A split block's background image: sliced, one image across its
    // fragments; cloned, one in each.
    func splitTop(clone: bool) -> draw.Color {
        let sp = web.Page()
        sp.SetViewportSize(draw.Size(200, 100))
        sp.LoadHTML("<style>body { margin: 0 } #g { background: linear-gradient(#ff0000, #0000ff); \(clone ? "box-decoration-break: clone" : "") }</style><div style='width:200px;column-count:2;column-gap:0'><div id=g><div style='height:40px'></div><div style='height:40px'></div></div></div>")
        var px = [uint8](repeating: 0, count: 200 * 100 * 4)
        sp.Draw(into: &px, width: 200, height: 100, scale: 1)
        return pixelAt(px, 200, 150, 1)
    }
    let sliced = splitTop(false)
    let cloned = splitTop(true)
    check(sliced.R > 90 && sliced.R < 170 && sliced.B > 90, "a sliced split block's image runs on into its next column (got \(sliced))")
    check(cloned.R > 230 && cloned.B < 30, "a cloned one starts again there (got \(cloned))")

    // anchor-scope, position-try-order, logical position-area.
    let anq = web.Page()
    anq.SetViewportSize(draw.Size(400, 300))
    anq.LoadHTML("""
    <style>body { margin: 0 } .a { anchor-name: --x; position: absolute; width: 10px; height: 10px } .t { position: absolute; position-anchor: --x; top: anchor(bottom); left: anchor(left); width: 10px; height: 10px }
    #s1, #s2 { anchor-scope: --x } #s1 .a { left: 10px; top: 10px } #s2 .a { left: 100px; top: 10px }
    #o { position: absolute; left: 100px; top: 200px; width: 20px; height: 20px; anchor-name: --o }
    #ot { position: absolute; position-anchor: --o; width: 10px; height: 10px; position-area: bottom; position-try-fallbacks: flip-block; position-try-order: most-height }
    #r { position: absolute; left: 200px; top: 100px; width: 20px; height: 20px; anchor-name: --r }
    #rt { position: absolute; position-anchor: --r; width: 10px; height: 10px; position-area: block-end inline-start; }
    #v { direction: rtl; position: relative } #rv { position: absolute; left: 300px; top: 100px; width: 20px; height: 20px; anchor-name: --v }
    #vt { position: absolute; position-anchor: --v; width: 10px; height: 10px; position-area: block-end inline-start; }</style>
    <div id=s1><div class=a></div><div class=t id=t1></div></div><div id=s2><div class=a></div><div class=t id=t2></div></div>
    <div id=o></div><div id=ot></div><div id=r></div><div id=rt></div>
    <div id=v><div id=rv></div><div id=vt></div></div>
    """)
    func anAt(q: string) -> draw.Rect { return anq.BoundsOf(anq.QuerySelector(q)!)! }
    check(anAt("#t1").X == 10 && anAt("#t2").X == 100, "anchor-scope keeps a name to its subtree (got \(anAt("#t1").X) \(anAt("#t2").X))")
    check(anAt("#ot").Y < 200, "position-try-order goes where there's most room, above here (got \(anAt("#ot").Y))")
    check(anAt("#rt").X == 190 && anAt("#rt").Y == 120, "a logical position-area in left to right (got \(anAt("#rt")))")
    check(anAt("#vt").X == 320 && anAt("#vt").Y == 120, "a logical position-area in right to left (got \(anAt("#vt")))")

    // A plane's context ends with it: a sibling after a preserve-3d box
    // isn't drawn inside it.
    let after = web.Page()
    after.SetViewportSize(draw.Size(200, 60))
    after.LoadHTML("""
    <style>body { margin: 0; background: white } div { width: 20px; height: 20px }</style>
    <div style="transform-style: preserve-3d; transform: translateX(100px)"><div style="background: rgb(255,0,0); transform: translateZ(1px)"></div></div>
    <div style="background: rgb(0,0,255); transform: translateZ(1px)"></div>
    """)
    var ap = [uint8](repeating: 0, count: 200 * 60 * 4)
    after.Draw(into: &ap, width: 200, height: 60, scale: 1)
    check(pixelAt(ap, 200, 110, 10) == draw.Color(255, 0, 0) && pixelAt(ap, 200, 10, 30) == draw.Color(0, 0, 255),
          "a sibling after a 3D context stands alone (got \(pixelAt(ap, 200, 110, 10)) \(pixelAt(ap, 200, 10, 30)))")
    let fixedIn = web.Page()
    fixedIn.SetViewportSize(draw.Size(200, 200))
    fixedIn.LoadHTML("<style>body { margin: 0; background: white }</style><div style='margin: 50px; width: 50px; height: 50px; transform: translateX(0)'><div id=fx style='position: fixed; left: 10px; top: 10px; width: 5px; height: 5px'></div></div>")
    if let fx = fixedIn.QuerySelector("#fx"), let b = fixedIn.BoundsOf(fx) {
        check(b.X == 60 && b.Y == 60, "a transformed box holds its fixed descendants (got \(b.X) \(b.Y))")
    }

    // Media, through a player of the test's own.
    final class FakePlayer: web.MediaPlayer {
        var Ready = true
        var Failed = false
        var Paused = true
        var Ended = false
        var Duration: float64 = 10
        var CurrentTime: float64 = 0
        var VideoWidth: int32 = 40
        var VideoHeight: int32 = 20
        var loop = false
        var muted = false
        var fresh: draw.Image? = nil
        func Play() { Paused = false }
        func Pause() { Paused = true }
        func Seek(to seconds: float64) { CurrentTime = seconds }
        func SetVolume(volume: float32) {}
        func SetMuted(muted: bool) { self.muted = muted }
        func SetLoop(loop: bool) { self.loop = loop }
        func Frame() -> draw.Image? { let f = fresh; fresh = nil; return f }
        func Close() {}
    }
    let mediaPage = web.Page()
    mediaPage.SetViewportSize(draw.Size(200, 100))
    var player: FakePlayer? = nil
    var opened = ""
    mediaPage.SetMediaOpener { url in
        opened = url
        let p = FakePlayer()
        player = p
        return p
    }
    mediaPage.LoadHTML("""
    <style>body { margin: 0; background: white } video { display: block } video:playing { outline: 2px solid red } </style>
    <video id=v autoplay muted loop controls><source src="clip.mp4"></video>
    """, baseURL: "file:///m/")
    guard let vid = mediaPage.QuerySelector("#v"), let fake = player else { check(false, "a video opens a player"); return }
    var heard: [string] = []
    for type in ["loadedmetadata", "play", "pause", "ended", "timeupdate", "error"] {
        _ = mediaPage.Document?.AddEventListener(vid, type, handler: { e in heard.append(e.Type) })
    }
    check(opened.hasSuffix("/m/clip.mp4"), "the first <source> is opened, resolved (got \(opened))")
    check(fake.muted && fake.loop, "muted and loop reach the player")
    _ = mediaPage.Advance(time: 0)
    check(!fake.Paused, "autoplay plays once it is ready")
    _ = mediaPage.Advance(time: 0.1)
    check(heard.contains("loadedmetadata") && heard.contains("play"), "metadata and play are told (got \(heard))")
    check(mediaPage.BoundsOf(vid)?.Width == 40 && mediaPage.BoundsOf(vid)?.Height == 20, "the picture's size lays it out (got \(String(describing: mediaPage.BoundsOf(vid))))")
    fake.fresh = draw.Image(width: 1, height: 1, pixels: [0, 0, 255, 255])
    _ = mediaPage.Advance(time: 0.2)
    var mpx = [uint8](repeating: 0, count: 200 * 100 * 4)
    mediaPage.Draw(into: &mpx, width: 200, height: 100, scale: 1)
    let frameAt = pixelAt(mpx, 200, 20, 1)
    check(frameAt == draw.Color(0, 0, 255), "a frame is painted in the box (got \(frameAt))")
    check(mediaPage.NeedsAnimation(), "a playing video keeps frames coming")
    fake.CurrentTime = 1
    _ = mediaPage.Advance(time: 0.3)
    check(heard.contains("timeupdate"), "time passing is told")
    fake.Ended = true
    fake.Paused = true
    _ = mediaPage.Advance(time: 0.4)
    let n = heard.count
    check(n >= 2 && heard[n - 2] == "pause" && heard[n - 1] == "ended", "pause then ended (got \(heard))")
    mediaPage.PlayMedia(vid)
    check(fake.CurrentTime == 0 && !fake.Paused, "playing again from the end starts over")
    let failing = web.Page()
    failing.SetViewportSize(draw.Size(100, 100))
    failing.SetMediaOpener { _ in return nil }
    failing.LoadHTML("<audio id=a src=a.mp3></audio>")
    var failed = 0
    if let a = failing.QuerySelector("#a") { _ = failing.Document?.AddEventListener(a, "error", handler: { e in failed += 1 }) }
    _ = failing.Advance(time: 0)
    _ = failing.BoundsOf(failing.QuerySelector("#a")!)
    _ = failing.Advance(time: 0.1)
    check(failed == 1, "a source no player opens gets error, once (got \(failed))")

    // Markup that comes after the page has loaded, as .vsx mounts it.
    let later = web.Page()
    later.SetViewportSize(draw.Size(100, 100))
    var opens: [string] = []
    later.SetMediaOpener { url in
        opens.append(url)
        return FakePlayer()
    }
    later.LoadHTML("<div id=root></div>", baseURL: "file:///m/")
    guard let laterDoc = later.Document, let root = later.QuerySelector("#root") else { return }
    let added = laterDoc.CreateElement("video")
    laterDoc.SetAttribute(added, "src", "a.mp4")
    laterDoc.AppendChild(root, added)
    _ = later.BoundsOf(added)
    check(opens.count == 1 && opens[0].hasSuffix("a.mp4"), "a video added later opens (got \(opens))")
    laterDoc.SetAttribute(added, "src", "b.mp4")
    _ = later.BoundsOf(added)
    check(opens.count == 2 && opens[1].hasSuffix("b.mp4"), "a new src opens anew (got \(opens))")

    // keypress, and layout as a ResizeObserver would tell it.
    let told = web.Page()
    told.SetViewportSize(draw.Size(200, 100))
    told.LoadHTML("<style>body { margin: 0 } #b { width: 50%; height: 10px }</style><div id=b></div>")
    guard let bx = told.QuerySelector("#b") else { return }
    var sizes: [float32] = []
    var presses: [string] = []
    _ = told.Document?.AddEventListener(bx, "layout", handler: { e in
        if let l = e as? dom.LayoutEvent { sizes.append(l.Width) }
    })
    _ = told.BoundsOf(bx)
    _ = told.Advance(time: 0)
    check(sizes == [100], "layout tells an element its size (got \(sizes))")
    _ = told.BoundsOf(bx)
    _ = told.Advance(time: 0.1)
    check(sizes == [100], "and not again while it stays (got \(sizes))")
    told.SetViewportSize(draw.Size(300, 100))
    check(told.NeedsAnimation() || told.BoundsOf(bx) != nil, "a new size lays out")
    _ = told.BoundsOf(bx)
    _ = told.Advance(time: 0.2)
    check(sizes == [100, 150], "and again when it changes (got \(sizes))")
    guard let tree = told.Document?.Tree, let body = tree.ElementsByTagName("body").first else { return }
    _ = told.Document?.AddEventListener(body, "keypress", handler: { e in
        if let k = e as? dom.KeyboardEvent { presses.append(k.Key) }
    })
    _ = told.Handle(.keyDown(web.Key(Key: "a", Code: "KeyA")))
    _ = told.Handle(.keyDown(web.Key(Key: "ArrowLeft", Code: "ArrowLeft")))
    _ = told.Handle(.keyDown(web.Key(Key: "c", Code: "KeyC", Meta: true)))
    check(presses == ["a"], "keypress is for keys that make a character (got \(presses))")

    // An <img>'s load and error.
    let imgs = web.Page()
    imgs.SetViewportSize(draw.Size(100, 100))
    let dot = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1'/>"
    imgs.LoadHTML("<img id=a src=\"\(dot)\"><img id=b src=missing.png>")
    var heardImage: [string] = []
    for id in ["a", "b"] {
        if let n = imgs.QuerySelector("#\(id)") {
            for type in ["load", "error"] { _ = imgs.Document?.AddEventListener(n, type, handler: { e in heardImage.append("\(id) \(e.Type)") }) }
        }
    }
    _ = imgs.Advance(time: 0)
    check(heardImage.contains("b error"), "an image that can't be had gets error (got \(heardImage))")

    // The rest of filter and mix-blend-mode.
    let fx = web.Page()
    fx.SetViewportSize(draw.Size(300, 60))
    fx.LoadHTML("""
    <style>body { margin: 0; background: white } div { position: absolute; top: 10px; width: 20px; height: 20px }</style>
    <div style="left: 0; background: rgb(200,100,50); filter: grayscale(1)"></div>
    <div style="left: 30px; background: rgb(255,0,0); filter: invert(100%)"></div>
    <div style="left: 60px; background: rgb(100,50,25); filter: brightness(2)"></div>
    <div style="left: 90px; background: rgb(255,0,0); filter: hue-rotate(120deg)"></div>
    <div style="left: 120px; background: black; filter: opacity(50%)"></div>
    <div style="left: 150px; width: 10px; height: 10px; background: black; filter: drop-shadow(10px 10px 0 rgb(0,0,255))"></div>
    <div style="left: 180px; background: rgb(255,0,0)"></div>
    <div style="left: 180px; backdrop-filter: invert(1)"></div>
    <div style="left: 210px; background: rgb(0,0,255)"><div style="left: 0; top: 0; background: rgb(255,0,0); mix-blend-mode: luminosity"></div></div>
    <div style="left: 240px; background: rgb(100,100,0)"><div style="left: 0; top: 0; background: rgb(100,0,100); mix-blend-mode: plus-lighter"></div></div>
    <div style="left: 270px; background: rgb(128,128,128)"><div style="left: 0; top: 0; background: rgb(255,0,0); mix-blend-mode: color"></div></div>
    """)
    var fp = [uint8](repeating: 0, count: 300 * 60 * 4)
    fx.Draw(into: &fp, width: 300, height: 60, scale: 1)
    func fa(x: int32, y: int32) -> draw.Color { return pixelAt(fp, 300, x, y) }
    func near(c: draw.Color, r: int32, g: int32, b: int32) -> bool {
        return abs(int32(c.R) - r) <= 3 && abs(int32(c.G) - g) <= 3 && abs(int32(c.B) - b) <= 3
    }
    check(fa(10, 20).R == fa(10, 20).G && fa(10, 20).G == fa(10, 20).B, "filter: grayscale() (got \(fa(10, 20)))")
    check(near(fa(40, 20), 0, 255, 255), "filter: invert() (got \(fa(40, 20)))")
    check(near(fa(70, 20), 200, 100, 50), "filter: brightness() (got \(fa(70, 20)))")
    check(near(fa(100, 20), 0, 113, 0), "filter: hue-rotate() by its matrix (got \(fa(100, 20)))")
    check(near(fa(130, 20), 127, 127, 127), "filter: opacity() (got \(fa(130, 20)))")
    check(near(fa(155, 15), 0, 0, 0) && near(fa(165, 25), 0, 0, 255) && near(fa(175, 35), 255, 255, 255),
          "filter: drop-shadow() draws under the box, past it (got \(fa(155, 15)) \(fa(165, 25)))")
    check(near(fa(190, 20), 0, 255, 255), "backdrop-filter: invert() (got \(fa(190, 20)))")
    check(near(fa(220, 20), 54, 54, 255), "mix-blend-mode: luminosity keeps the backdrop's hue (got \(fa(220, 20)))")
    check(near(fa(250, 20), 200, 100, 100), "mix-blend-mode: plus-lighter adds (got \(fa(250, 20)))")
    check(near(fa(280, 20), 255, 73, 73), "mix-blend-mode: color takes the source's hue (got \(fa(280, 20)))")

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
    func m(x: int32, y: int32) -> draw.Color { return pixelAt(mp, 200, x, y) }
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
    func k(x: int32, y: int32) -> draw.Color { return pixelAt(kp, 100, x, y) }
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
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 260, x, y) }
    let white = draw.Color(255, 255, 255)
    check(at(5, 15) == draw.Color(0, 0, 255) && at(20, 30) == white,
          "a gradient border image takes the border's place, the middle left empty (got \(at(5, 15)) \(at(20, 30)))")
    check(at(70, 30) == draw.Color(0, 128, 0), "fill draws the middle (got \(at(70, 30)))")
    check(at(105, 15) == draw.Color(255, 0, 0), "an image that isn't loaded leaves the border's own style (got \(at(105, 15)))")
    check(at(147, 30) == draw.Color(0, 0, 255) && at(143, 30) == white, "border-image-outset draws outside the box (got \(at(147, 30)) \(at(143, 30)))")
    // The 40px gradient cut at 10px: the left edge is the darkest part.
    check(at(205, 30).R < 64 && at(254, 30).R > 190, "the longhands cut a gradient into slices (got \(at(205, 30)) \(at(254, 30)))")

    // A raster border image fades with the box, as a gradient does.
    view.LoadHTML("""
    <style>body { margin: 0; background: white } div { position: absolute; top: 10px; width: 20px; height: 20px; border: 10px solid; opacity: 0.5 }</style>
    <div style="left: 0; border-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGNgYPiPhIjiAACOsw/xs6MvMwAAAABJRU5ErkJggg==) 1"></div>
    <div style="left: 50px; border-image: linear-gradient(rgb(0,0,255), rgb(0,0,255)) 10"></div>
    """)
    view.Draw(into: &px, width: 260, height: 70, scale: 1)
    let faded = at(5, 15)
    check(faded.R > 100 && faded.R < 160 && faded.B == 255 && faded == at(55, 15),
          "a raster border image under opacity fades as a gradient one does (got \(faded) and \(at(55, 15)))")

    // An SVG image as the source: a 30px green square with a red middle.
    view.LoadHTML("""
    <style>body { margin: 0; background: white } div { position: absolute; top: 10px; width: 20px; height: 20px; border: 10px solid }</style>
    <div style="left: 0; border-image: url('data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%2230%22 height=%2230%22><rect width=%2230%22 height=%2230%22 fill=%22rgb(0,128,0)%22/><rect x=%2210%22 y=%2210%22 width=%2210%22 height=%2210%22 fill=%22rgb(255,0,0)%22/></svg>') 10"></div>
    """)
    view.Draw(into: &px, width: 260, height: 70, scale: 1)
    check(at(5, 15) == draw.Color(0, 128, 0) && at(20, 30) == white && at(35, 45) == draw.Color(0, 128, 0),
          "an SVG border image is cut and drawn round the box (got \(at(5, 15)) \(at(20, 30)) \(at(35, 45)))")
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
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 300, x, y) }
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
    func at(x: int32, y: int32) -> draw.Color { return pixelAt(px, 100, x, y) }
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
