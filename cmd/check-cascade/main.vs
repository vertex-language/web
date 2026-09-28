// The cascade checked: computed styles from HTML and CSS.
package main

import (
    "image/draw"
    "web/cascade"
    "web/css"
    "web/css/selector"
    "web/dom"
    "web/html"
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

func testStyles() {
    print("Styles")
    let page = """
    <style>
      body { font-size: 20px; color: rgb(10, 20, 30); }
      .box { width: 50%; padding: 1em 2em; margin: 4px auto; border: 2px solid #ff0000; border-radius: 6px 3px; }
      #big { font-size: 2em; line-height: 1.5; }
      p { color: blue !important; }
      p.red { color: red; }
      .hidden { display: none }
      span { font-weight: bold; text-decoration: underline; }
      .flex { display: flex; flex-direction: column; gap: 10px 20px; justify-content: space-between; }
      .item { flex: 2 1 100px; }
      @media (max-width: 500px) { .box { width: 100px; } }
      @media screen and (min-width: 500px) { .box { max-width: 300px; } }
      .rem { margin-left: 2rem; font: italic 700 12px/2 Georgia, serif; }
    </style>
    <div class="box" id="big">
      <p class="red">text <span style="color: green; font-weight: normal">inner</span></p>
      <div class="flex"><div class="item"></div></div>
      <p class="rem">r</p>
    </div>
    """
    guard let body = styleOf(page, "body") else { check(false, "body resolves"); return }
    check(body.Display == .block, "body is a block")
    check(body.FontSize == 20, "body font-size 20px (got \(body.FontSize))")
    check(body.MarginTop == .px(8), "body has the UA's 8px margin")
    check(body.Color == draw.Color(10, 20, 30), "rgb() color")

    guard let box = styleOf(page, ".box") else { check(false, "box resolves"); return }
    check(box.FontSize == 40, "2em of 20px is 40px (got \(box.FontSize))")
    check(box.Width == .percent(50), "width: 50% stays a percentage")
    check(box.PaddingTop == .px(40) && box.PaddingLeft == .px(80), "padding in em uses the element's own font size (got \(box.PaddingTop) \(box.PaddingLeft))")
    check(box.MarginTop == .px(4) && box.MarginLeft == .auto, "margin: 4px auto")
    check(box.BorderTopWidth == 2 && box.BorderLeftStyle == .solid && box.BorderTopColor == draw.Color(255, 0, 0), "border shorthand sets width, style and color")
    check(box.BorderRadius.TopLeft == 6 && box.BorderRadius.TopRight == 3 && box.BorderRadius.BottomRight == 6, "border-radius with two values")
    check(box.LineHeight == .number(1.5) && box.LineHeightPx == 60, "unitless line-height multiplies the font size (got \(box.LineHeightPx))")
    check(box.MaxWidth == .px(300), "a matching @media rule applies")
    check(box.Width != .px(100), "a non-matching @media rule does not")

    guard let p = styleOf(page, "p.red") else { check(false, "p resolves"); return }
    check(p.Color == draw.Color(0, 0, 255), "!important beats a more specific rule")
    check(p.FontSize == 40, "font-size inherits")
    check(p.Display == .block && p.MarginTop == .px(40), "p margin 1em of the inherited 40px")

    guard let span = styleOf(page, "span") else { check(false, "span resolves"); return }
    check(span.Color == draw.Color(0, 128, 0), "inline style beats the sheet (got \(span.Color.R) \(span.Color.G) \(span.Color.B))")
    check(span.FontWeight == 400, "inline style sets weight normal")
    check(span.TextDecoration.Underline, "text-decoration: underline")
    check(span.Display == .inline, "span is inline")

    guard let hidden = styleOf("<style>.hidden{display:none}</style><p class=hidden>x</p>", ".hidden") else { check(false, "hidden resolves"); return }
    check(hidden.Display == .none, "display: none")

    guard let flex = styleOf(page, ".flex") else { check(false, "flex resolves"); return }
    check(flex.Display == .flex && flex.FlexDirection == .column, "display: flex, column")
    check(flex.RowGap == .px(10) && flex.ColumnGap == .px(20), "gap: 10px 20px")
    check(flex.JustifyContent == .spaceBetween, "justify-content")
    guard let item = styleOf(page, ".item") else { check(false, "item resolves"); return }
    check(item.FlexGrow == 2 && item.FlexShrink == 1 && item.FlexBasis == .px(100), "flex: 2 1 100px")

    guard let rem = styleOf(page, ".rem") else { check(false, "rem resolves"); return }
    check(rem.MarginLeft == .px(32), "2rem against the root's 16px (got \(rem.MarginLeft))")
    check(rem.FontStyle == .italic && rem.FontWeight == 700 && rem.FontSize == 12, "font shorthand: style weight size")
    check(rem.LineHeight == .number(2), "font shorthand: line-height")
    check(rem.FontFamilies.count == 2 && rem.FontFamilies[0] == "Georgia" && rem.FontFamilies[1] == "serif", "font shorthand: families")

    let h1 = styleOf("<h1>x</h1>", "h1")
    check(h1?.FontSize == 32 && h1?.FontWeight == 700, "h1 is 2em bold by default")
    let a = styleOf("<a href=x>x</a>", "a")
    check(a?.Cursor == .pointer && a?.TextDecoration.Underline == true, "a link is underlined with a pointer cursor")
    let li = styleOf("<ul><li>x</li></ul>", "li")
    check(li?.Display == .listItem && li?.ListStyleType == .disc, "li is a list item with a disc")
    let nested = styleOf("<ul><li><ul><li>x</li></ul></li></ul>", "ul ul li")
    check(nested?.ListStyleType == .circle, "nested lists use circles")
    let input = styleOf("<input>", "input")
    check(input?.Display == .inlineBlock && input?.BorderTopWidth == 1 && input?.BoxSizing == .borderBox, "inputs are bordered inline blocks")
    let hiddenAttr = styleOf("<div hidden>x</div>", "div")
    check(hiddenAttr?.Display == Display.none, "the hidden attribute hides")
    let img = styleOf("<img width=40 height=30>", "img")
    check(img?.Width == .px(40) && img?.Height == .px(30), "img width and height attributes")
    let floated = styleOf("<span style='float: left'>x</span>", "span")
    check(floated?.Display == .block && floated?.Float == .left, "a floated inline becomes a block")
    let noStyleBorder = styleOf("<div style='border-width: 4px'>x</div>", "div")
    check(noStyleBorder?.BorderTopWidth == 0, "a border with no style has no width")
    let inheritColor = styleOf("<div style='color: red'><p style='border-color: currentcolor; color: inherit'>x</p></div>", "p")
    check(inheritColor?.Color == draw.Color(255, 0, 0) && inheritColor?.BorderTopColor == nil, "inherit and currentcolor")
    let percentFont = styleOf("<div style='font-size: 10px'><p style='font-size: 150%'>x</p></div>", "p")
    check(percentFont?.FontSize == 15, "percentage font-size is of the parent")
    let bg = styleOf("<div style='background: url(x.png) #123456 no-repeat'>x</div>", "div")
    check(bg?.BackgroundColor == draw.Color(0x12, 0x34, 0x56) && bg?.BackgroundImage?.URL == "x.png", "background shorthand with a url and a color")
    let shadow = styleOf("<div style='box-shadow: 0 2px 4px rgba(0,0,0,.5), inset 1px 1px red'>x</div>", "div")
    check(shadow?.Shadows.count == 2 && shadow?.Shadows[0].Blur == 4 && shadow?.Shadows[1].Inset == true, "box-shadow list")
    let vw = styleOf("<div style='width: 50vw'>x</div>", "div")
    check(vw?.Width == .px(400), "vw against the resolver's 800px viewport")
    let calc = styleOf("<div style='width: calc(100% - 20px); margin-left: calc(1em + 2px); font-size: 10px; height: calc(2 * 7px); padding: calc(3px + 1px) calc(50% / 2)'>x</div>", "div")!
    check(calc.Width == .calc(-20, 100), "calc() of a percentage and pixels stays a calc (got \(calc.Width))")
    check(calc.MarginLeft == .px(12), "calc() of em and px resolves (got \(calc.MarginLeft))")
    check(calc.Height == .px(14) && calc.PaddingTop == .px(4) && calc.PaddingLeft == .percent(25), "calc() multiplies and divides (got \(calc.Height) \(calc.PaddingTop) \(calc.PaddingLeft))")
    let carousel = styleOf("<div style='--n: 3; --g: 16px; --cols: 12; width: calc(var(--n)*(100% - (var(--cols) - 1)*var(--g))/var(--cols) + (var(--n) - 1)*var(--g)); height: calc(-1 * (2px + 3px))'>x</div>", "div")!
    check(carousel.Width == .calc(-12, 25) && carousel.Height == .px(-5), "calc() multiplies and divides sums in parentheses (got \(carousel.Width) \(carousel.Height))")
    let mm = styleOf("<div style='width: min(30px, 20px); height: max(1px, 5px); margin-top: clamp(4px, 9px, 6px)'>x</div>", "div")!
    check(mm.Width == .px(20) && mm.Height == .px(5) && mm.MarginTop == .px(6), "min(), max() and clamp() fold (got \(mm.Width) \(mm.Height) \(mm.MarginTop))")
}

/// The roots a change restyles, as tag#id, for a page with sheet.
func invalidated(_ sheet: string, _ body: string, _ change: (dom.Document) -> Void) -> [string] {
    let doc = dom.Document(html.Parse("<body>" + body + "</body>"))
    let resolver = cascade.StyleResolver(ua: cascade.UserAgentRules())
    resolver.Author.Add(css.Parse(sheet))
    change(doc)
    let roots = resolver.Invalidate(doc.TakeRecords(), reads: { name in name == "src" })
    var out: [string] = []
    for r in roots { out.append(r.TagName + "#" + (r.GetAttribute("id") ?? "")) }
    return out
}

func testInvalidation() {
    print("Invalidation")
    let sheet = ".on { color: red } #hot { color: blue } [data-state=open] { width: 5px } a.big b { color: green } p::after { content: attr(title) }"
    let body = "<div id=a class=x><p id=p>text</p></div><img id=i><a id=l></a>"

    check(invalidated(sheet, body, { d in d.ElementById("a")!.SetAttribute("data-other", "1") }).isEmpty,
          "an attribute no rule names restyles nothing")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.ClassList.Add("unused") }).isEmpty,
          "a class no rule names restyles nothing")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.ClassList.Add("on") }) == ["div#a"],
          "a class a rule names restyles the element")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.ClassList.Remove("x") }).isEmpty,
          "removing a class no rule names restyles nothing")
    check(invalidated(sheet, body, { d in d.ElementById("l")!.ClassList.Add("big") }) == ["a#l"],
          "a class named in an ancestor compound restyles the element (its subtree follows)")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.SetAttribute("data-state", "open") }) == ["div#a"],
          "an attribute a selector names restyles the element")
    check(invalidated(sheet, body, { d in d.ElementById("p")!.SetAttribute("title", "t") }) == ["p#p"],
          "an attribute content: attr() reads restyles the element")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.SetAttribute("style", "color: red") }) == ["div#a"],
          "inline style restyles the element")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.SetAttribute("hidden", "") }) == ["div#a"],
          "a presentational attribute restyles the element")
    check(invalidated(sheet, body, { d in d.ElementById("i")!.SetAttribute("src", "x.png") }) == ["img#i"],
          "an attribute a later stage reads restyles the element")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.SetAttribute("id", "hot") }) == ["div#hot"],
          "an id a rule names restyles the element")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.SetAttribute("id", "cold") }).isEmpty,
          "an id change no rule names on either side restyles nothing")
    check(invalidated(sheet, body, { d in
        let a = d.ElementById("a")!
        a.ClassList.Add("on")
        a.ClassList.Remove("on")
    }) == ["div#a"], "a class that came and went is still looked at")
    check(invalidated(sheet, body, { d in d.ElementById("p")!.TextContent = "other" }) == ["p#p"],
          "new text restyles the text's element")
    check(invalidated(sheet, body, { d in d.ElementById("a")!.AppendChild(d.CreateElement("span")) }) == ["div#a"],
          "a new child restyles its parent")
    check(invalidated(sheet, body, { d in
        d.ElementById("a")!.ClassList.Add("on")
        d.ElementById("a")!.SetAttribute("data-state", "open")
    }).count == 1, "each element is a root once")

    let siblingSheet = ".on + p { color: red }"
    check(invalidated(siblingSheet, body, { d in d.ElementById("a")!.ClassList.Add("on") }) == ["body#"],
          "with sibling selectors, a change restyles from the parent")
    let hasSheet = "div:has(.on) { color: red }"
    check(invalidated(hasSheet, body, { d in d.ElementById("p")!.ClassList.Add("on") }) == ["html#"],
          "with :has(), a change restyles from the top")
    check(invalidated(":checked { color: red }", "<input id=c type=checkbox>", { d in _ = d.ElementById("c")!.ToggleAttribute("checked") }) == ["input#c"],
          ":checked makes checked matter")
}

func testCustomProperties() {
    print("Custom properties and var()")
    let sheet = """
    <style>
      :root { --fg: rgb(1, 2, 3); --gap: 12px; --pad: var(--gap); --Case: 7px; --a: var(--b); --b: var(--a); }
      .card { color: var(--fg); padding: var(--pad) 4px; margin-left: var(--missing, 9px); }
      .inner { --fg: rgb(4, 5, 6); }
      .later { width: var(--gap); width: 30px; }
      .earlier { width: 30px; width: var(--gap); }
      .cycle { width: 10px; width: var(--a); }
      .none { margin-top: 5px; margin-top: var(--nothing); }
      .case { margin-top: var(--Case); margin-bottom: var(--case, 1px); }
      .imp { width: var(--gap) !important; }
      .border { border: 2px solid var(--fg); }
    </style>
    """
    let card = styleOf(sheet + "<div class=card>x</div>", ".card")
    check(card?.Color == draw.Color(1, 2, 3), "var() reads a custom property the root declares")
    check(card?.PaddingTop == Length.px(12) && card?.PaddingRight == Length.px(4), "var() inside a shorthand, through another custom property")
    check(card?.MarginLeft == Length.px(9), "a missing custom property takes the fallback")
    let inner = styleOf(sheet + "<div class=card><p class='inner card'>x</p></div>", "p")
    check(inner?.Color == draw.Color(4, 5, 6), "an element's own custom property hides its parent's")
    let child = styleOf(sheet + "<div class=inner><span class=card>x</span></div>", "span")
    check(child?.Color == draw.Color(4, 5, 6), "custom properties inherit")
    check(styleOf(sheet + "<div class=later>x</div>", ".later")?.Width == Length.px(30), "a later plain declaration wins over an earlier var() one")
    check(styleOf(sheet + "<div class=earlier>x</div>", ".earlier")?.Width == Length.px(12), "a later var() declaration wins over an earlier plain one")
    check(styleOf(sheet + "<div class=cycle>x</div>", ".cycle")?.Width == Length.auto, "a var() cycle makes the declaration unset")
    check(styleOf(sheet + "<div class=none>x</div>", ".none")?.MarginTop == Length.px(0), "a reference to nothing without a fallback is unset")
    let c = styleOf(sheet + "<div class=case>x</div>", ".case")
    check(c?.MarginTop == Length.px(7) && c?.MarginBottom == Length.px(1), "custom property names are case-sensitive")
    check(styleOf(sheet + "<div class=imp style='width: 1px'>x</div>", ".imp")?.Width == Length.px(12), "!important with var() beats the style attribute")
    check(styleOf(sheet + "<div style='--gap: 3px; width: var(--gap)'>x</div>", "div")?.Width == Length.px(3), "the style attribute declares and reads custom properties")
    let b = styleOf(sheet + "<div class=border>x</div>", ".border")
    check(b?.BorderTopColor == draw.Color(1, 2, 3) && b?.BorderTopWidth == 2, "var() inside the border shorthand")
}

func testMediaQueries() {
    print("Media queries")
    func width(_ query: string) -> Length? {
        return styleOf("<style>div { width: 1px } @media \(query) { div { width: 2px } }</style><div>x</div>", "div")?.Width
    }
    // styleOf's viewport is 800 by 600.
    let yes = ["(width >= 768px)", "(width>=48rem)", "(min-width: 40em)", "screen and (width <= calc(64rem - .02px))",
               "(400px <= width < 900px)", "(height > 500px)", "(hover: hover)", "(prefers-reduced-motion: no-preference)",
               "(forced-colors: none)", "not print", "(max-width: 400px), (min-width: 700px)", "(aspect-ratio > 1)"]
    let no = ["(width >= 1012px)", "(width<768px)", "(forced-colors: active)", "(prefers-color-scheme: dark)",
              "(prefers-reduced-motion: reduce)", "print", "(900px <= width)", "(prefers-contrast: more)", "(scripting: enabled)"]
    for q in yes { check(width(q) == Length.px(2), "@media \(q) holds") }
    for q in no { check(width(q) == Length.px(1), "@media \(q) doesn't") }
}

func testAtRules() {
    print("@supports, @layer and nesting")
    func width(_ css: string) -> Length? {
        return styleOf("<style>" + css + "</style><div class=d>x</div>", "div")?.Width
    }
    check(width("div { width: 1px } @supports (display: flex) { div { width: 2px } }") == Length.px(2), "@supports holds for a declaration the engine parses")
    check(width("div { width: 1px } @supports (display: nonsense-value) { div { width: 2px } }") == Length.px(1), "and not for one it doesn't")
    check(width("div { width: 1px } @supports not (frobnicate: 1) { div { width: 2px } }") == Length.px(2), "not")
    check(width("div { width: 1px } @supports (display: flex) and (color: red) { div { width: 2px } }") == Length.px(2), "and")
    check(width("div { width: 1px } @supports (frob: 1) or (color: red) { div { width: 2px } }") == Length.px(2), "or")
    check(width("div { width: 1px } @supports ((display: flex) and (not (frob: 1))) { div { width: 2px } }") == Length.px(2), "nested parentheses")
    check(width("div { width: 1px } @supports selector(:has(a)) { div { width: 2px } }") == Length.px(2), "selector() of a pseudo-class the matcher knows")
    check(width("div { width: 1px } @supports selector(:popover-open) { div { width: 2px } }") == Length.px(1), "selector() of one it doesn't")
    check(width("div { width: 1px } @supports (--x: y) { div { width: 2px } }") == Length.px(2), "a custom property is always supported")

    check(width("@layer base { .d { width: 5px } } div { width: 1px }") == Length.px(1), "an unlayered rule beats a layered one, however specific")
    check(width("@layer a, b; @layer b { div { width: 2px } } @layer a { div { width: 1px } }") == Length.px(2), "@layer a, b; sets the order: b beats a")
    check(width("@layer a { div { width: 1px } } @layer b { div { width: 2px } }") == Length.px(2), "a later layer beats an earlier one")
    check(width("@layer a { .d { width: 3px } div { width: 1px } }") == Length.px(3), "within a layer, specificity decides")
    check(width("@layer base { @media (min-width: 100px) { div { width: 4px } } }") == Length.px(4), "@media inside @layer")
    check(width("@media (min-width: 100px) { @media (max-width: 200px) { div { width: 4px } } div { width: 6px } }") == Length.px(6), "nested @media needs both queries")
    check(width("@supports (display: grid) { @media (min-width: 100px) { div { width: 7px } } }") == Length.px(7), "@media inside @supports")
    check(width("@layer outer { @layer inner { div { width: 8px } } }") == Length.px(8), "a layer inside a layer")
}

func testBackgroundPosition() {
    print("background-position")
    func pos(_ value: string) -> (float32, float32, float32, float32)? {
        guard let b = styleOf("<style>div { background: url(x.png) " + value + " }</style><div>x</div>", "div")?.BackgroundImage else { return nil }
        return (b.PositionX, b.OffsetX, b.PositionY, b.OffsetY)
    }
    func same(_ v: (float32, float32, float32, float32)?, _ want: (float32, float32, float32, float32)) -> bool {
        guard let v = v else { return false }
        return v.0 == want.0 && v.1 == want.1 && v.2 == want.2 && v.3 == want.3
    }
    check(same(pos("0 -261px repeat-x"), (0, 0, 0, -261)), "lengths: a sprite's slice (0 -261px)")
    check(same(pos("center"), (0.5, 0, 0.5, 0)), "center alone is both")
    check(same(pos("top"), (0.5, 0, 0, 0)), "top alone centers x")
    check(same(pos("right 10px bottom 5px"), (1, -10, 1, -5)), "edge offsets")
    check(same(pos("25% 2em"), (0.25, 0, 0, 32)), "a percentage and an em length")
    check(same(pos("bottom left"), (0, 0, 1, 0)), "keywords in either order")
}

func testEffects() {
    print("Effects")
    guard let e = styleOf("<style>div { filter: brightness(2) blur(1em); border-radius: 50% 4px; background: radial-gradient(circle at 0 100%, red 10%, blue 60%) }</style><div>x</div>", "div") else { check(false, "effects resolve"); return }
    check(e.FilterBlur == 16, "filter: blur() in em, among other functions (got \(e.FilterBlur))")
    let r = e.Radii(width: 200, height: 100)
    check(r.TopLeft == 50 && r.TopRight == 4 && r.BottomRight == 50, "border-radius percentages resolve against the box (got \(r.TopLeft) \(r.TopRight))")
    guard let shape = e.BackgroundImage?.Gradient?.Radial else { check(false, "radial-gradient has a shape"); return }
    check(shape.Circle && shape.CenterX == 0 && shape.CenterY == 1, "radial-gradient's shape and position")
    check(e.BackgroundImage!.Gradient!.Stops.count == 2 && e.BackgroundImage!.Gradient!.Stops[0].Position == 0.1, "and its stops after them")
    guard let n = styleOf("<style>div { filter: blur(4px); } div.n { filter: none }</style><div class=n>x</div>", "div") else { return }
    check(n.FilterBlur == 0, "filter: none clears it")

    guard let lg = styleOf("<style>div { --s: 24px; padding-inline: var(--s); margin-block: 3px 5px; padding-block: 7px }</style><div>x</div>", "div") else { check(false, "logical resolves"); return }
    check(lg.PaddingLeft == .px(24) && lg.PaddingRight == .px(24), "padding-inline sets both sides, through var() (got \(lg.PaddingLeft))")
    check(lg.MarginTop == .px(3) && lg.MarginBottom == .px(5) && lg.PaddingTop == .px(7), "margin-block's start and end, and padding-block")
}

func main() -> int32 {
    testStyles()
    testInvalidation()
    testCustomProperties()
    testMediaQueries()
    testAtRules()
    testBackgroundPosition()
    testEffects()
    if failures == 0 {
        print("ALL CASCADE CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
