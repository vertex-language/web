package main

import (
    "image/draw"
    "web/css"
    "web/css/selector"
    "web/html"
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

func same(_ got: string, _ want: string, _ what: string) {
    check(got == want, got == want ? what : "\(what): got \"\(got)\", want \"\(want)\"")
}

// MARK: - CSS Tests

func testCSS() {
    print("Testing web/css...")

    let cssSource = """
    /* Reset styles */
    *, *::before, *::after {
        box-sizing: border-box;
        margin: 0;
    }

    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        font-size: 16px;
        color: #24292f;
        background-color: #ffffff;
        line-height: 1.5;
    }

    .container, #main {
        max-width: 1200px;
        margin: 0 auto;
        padding: 20px 15px;
    }

    a.btn-primary {
        background-color: #0969da !important;
        color: #ffffff;
        border-radius: 6px;
        padding: 8px 16px;
    }

    @media (max-width: 768px) {
        .container {
            padding: 10px;
        }
        h1 {
            font-size: 24px;
        }
    }
    """

    let sheet = css.Parse(cssSource)

    check(sheet.Rules.count == 4, "parsed 4 top-level CSS rules, got \(sheet.Rules.count)")
    check(sheet.AtRules.count == 1, "parsed 1 @media at-rule")

    // Rule 1: Body
    if sheet.Rules.count >= 2 {
        let bodyRule = sheet.Rules[1]
        same(bodyRule.Selectors[0], "body", "Rule 2 selector is 'body'")
        if let colorDecl = bodyRule.GetDeclaration("color") {
            same(colorDecl.Value, "#24292f", "body color is '#24292f'")
            check(!colorDecl.Important, "body color is not !important")
        } else {
            check(false, "body color declaration found")
        }

        if let fontSizeDecl = bodyRule.GetDeclaration("font-size") {
            same(fontSizeDecl.Value, "16px", "body font-size is '16px'")
        } else {
            check(false, "body font-size declaration found")
        }
    }

    // Rule 2: Multiple selectors
    if sheet.Rules.count >= 3 {
        let containerRule = sheet.Rules[2]
        check(containerRule.Selectors.count == 2, "container rule has 2 selectors (.container, #main)")
        same(containerRule.Selectors[0], ".container", "first selector is '.container'")
        same(containerRule.Selectors[1], "#main", "second selector is '#main'")
    }

    // Rule 3: !important declaration
    if sheet.Rules.count >= 4 {
        let btnRule = sheet.Rules[3]
        if let bgDecl = btnRule.GetDeclaration("background-color") {
            same(bgDecl.Value, "#0969da", "btn background-color is '#0969da'")
            check(bgDecl.Important, "btn background-color is marked !important")
        } else {
            check(false, "btn background-color found")
        }
    }

    // At-rule @media
    if !sheet.AtRules.isEmpty {
        let media = sheet.AtRules[0]
        same(media.Name, "media", "at-rule name is 'media'")
        same(media.Params, "(max-width: 768px)", "media query params parsed correctly")
        check(media.Rules.count == 2, "media block contains 2 inner rules")
    }

    // Inline style declarations parsing
    let inline = "color: red; font-size: 14pt; font-weight: bold !important;"
    let decls = css.ParseDeclarations(inline)
    check(decls.count == 3, "parsed 3 inline declarations")
    if decls.count >= 3 {
        same(decls[0].Property, "color", "first property is 'color'")
        same(decls[0].Value, "red", "first value is 'red'")
        same(decls[1].Property, "font-size", "second property is 'font-size'")
        same(decls[1].Value, "14pt", "second value is '14pt'")
        same(decls[2].Property, "font-weight", "third property is 'font-weight'")
        check(decls[2].Important, "third declaration is !important")
    }
}

// MARK: - Selector Tests

func testSelector() {
    print("Testing web/css/selector...")

    let htmlSnippet = """
    <div id="app" class="wrapper">
      <header class="site-header">
        <h1 id="logo" class="brand title">Vertex</h1>
        <nav class="main-nav">
          <ul>
            <li class="nav-item first"><a href="https://vertex.dev" target="_blank" class="nav-link">Home</a></li>
            <li class="nav-item"><a href="https://docs.vertex.dev" class="nav-link active">Docs</a></li>
            <li class="nav-item"><a href="/download" class="nav-link">Download</a></li>
          </ul>
        </nav>
      </header>
      <main id="content" class="container">
        <article class="post featured">
          <h2 class="post-title">Release Notes</h2>
          <p class="summary">Vertex text package is ready.</p>
        </article>
      </main>
    </div>
    """

    let doc = html.Parse(htmlSnippet)

    // Tag selector
    let headers = selector.QuerySelectorAll("header", in: doc.Root)
    check(headers.count == 1, "QuerySelectorAll('header') found 1 header")

    // ID selector
    if let logo = selector.QuerySelector("#logo", in: doc.Root) {
        same(logo.TagName, "h1", "#logo points to <h1>")
        check(logo.HasClass("brand"), "#logo has class 'brand'")
    } else {
        check(false, "QuerySelector('#logo') found")
    }

    // Class selector
    let navLinks = selector.QuerySelectorAll(".nav-link", in: doc.Root)
    check(navLinks.count == 3, "QuerySelectorAll('.nav-link') found 3 links")

    // Compound selector (tag + class + pseudo)
    let activeLink = selector.QuerySelector("a.nav-link.active", in: doc.Root)
    check(activeLink != nil, "QuerySelector('a.nav-link.active') matched")
    if let al = activeLink {
        same(al.InnerText(), "Docs", "active link text is 'Docs'")
    }

    // Child combinator (>)
    let navLis = selector.QuerySelectorAll("nav > ul > li", in: doc.Root)
    check(navLis.count == 3, "QuerySelectorAll('nav > ul > li') matched 3 direct child items")

    // Descendant combinator (space)
    let linksInApp = selector.QuerySelectorAll("#app a", in: doc.Root)
    check(linksInApp.count == 3, "QuerySelectorAll('#app a') matched 3 links under #app")

    // Attribute selector [target] and [href^="https"]
    let externalLinks = selector.QuerySelectorAll("a[target='_blank']", in: doc.Root)
    check(externalLinks.count == 1, "QuerySelectorAll(\"a[target='_blank']\") matched 1 link")

    let httpsLinks = selector.QuerySelectorAll("a[href^='https']", in: doc.Root)
    check(httpsLinks.count == 2, "QuerySelectorAll(\"a[href^='https']\") matched 2 HTTPS links")

    // Pseudo-class :first-child
    let firstLi = selector.QuerySelector("li:first-child", in: doc.Root)
    check(firstLi != nil, "QuerySelector('li:first-child') matched")
    if let fl = firstLi {
        check(fl.HasClass("first"), "first-child has class 'first'")
    }

    // Matches() API
    if let h1 = doc.ElementById("logo") {
        check(selector.Matches("h1.brand", h1), "Matches('h1.brand', h1) returns true")
        check(selector.Matches("#logo", h1), "Matches('#logo', h1) returns true")
        check(selector.Matches("header > h1", h1), "Matches('header > h1', h1) returns true")
        check(!selector.Matches("div > h1", h1), "Matches('div > h1', h1) returns false (direct child mismatch)")
        check(selector.Matches("#app h1", h1), "Matches('#app h1', h1) returns true (descendant match)")
    }
}

// MARK: - Main Runner

func testPseudoClasses() {
    print("Testing web/css/selector pseudo-classes...")
    let doc = html.Parse("<ul><li id=a class=x>1<li id=b>2<li id=c class=x>3<li id=d>4<li id=e>5</ul><p id=empty></p><input id=in disabled><a id=link href=/>l</a><a id=anchor>n</a>")
    func ids(_ sel: string) -> string {
        let nodes = selector.QuerySelectorAll(sel, in: doc.Root)
        var out = ""
        var i = 0
        while i < nodes.count {
            out += nodes[i].IdAttr() ?? "?"
            i += 1
        }
        return out
    }
    same(ids("li:first-child"), "a", ":first-child")
    same(ids("li:last-child"), "e", ":last-child")
    same(ids("li:nth-child(2)"), "b", ":nth-child(2)")
    same(ids("li:nth-child(odd)"), "ace", ":nth-child(odd)")
    same(ids("li:nth-child(even)"), "bd", ":nth-child(even)")
    same(ids("li:nth-child(2n+1)"), "ace", ":nth-child(2n+1)")
    same(ids("li:nth-child(-n+2)"), "ab", ":nth-child(-n+2)")
    same(ids("li:nth-child(n+4)"), "de", ":nth-child(n+4)")
    same(ids("li:nth-last-child(1)"), "e", ":nth-last-child(1)")
    same(ids("li:not(.x)"), "bde", ":not(.x)")
    same(ids("li:not(.x, #b)"), "de", ":not() with a list")
    same(ids("li:is(#a, #e)"), "ae", ":is()")
    same(ids("ul:has(> li.x)"), "?", ":has() with a child combinator is not matched yet")
    same(ids("p:empty"), "empty", ":empty")
    same(ids("input:disabled"), "in", ":disabled")
    same(ids("a:link"), "link", ":link wants an href")
    same(ids("li::before"), "", "a pseudo-element matches no element")
    same(ids("LI.x"), "ac", "tag names are matched case-insensitively")
    // Junk -- a page's HTML read as CSS -- ends; it doesn't loop.
    _ = selector.ParseSelectors("<link href=\"a,b\"> p 'x,y' ,z")
    check(selector.ParseSelectors("a\"q,r\" b").count == 1, "a comma in quotes outside brackets ends the parse, not loops it")

    let ctx = selector.MatchContext()
    let sels = selector.ParseSelectors("li:hover")
    let b = doc.ElementById("b")!
    let ul = doc.ElementsByTagName("ul")[0]
    check(!selector.MatchComplexIn(sels[0], b, ctx), "nothing is hovered by default")
    ctx.Hovered = b
    check(selector.MatchComplexIn(sels[0], b, ctx), ":hover matches the hovered element")
    let ulSel = selector.ParseSelectors("ul:hover")[0]
    check(selector.MatchComplexIn(ulSel, ul, ctx), ":hover matches an ancestor of the hovered element")
    let focusSel = selector.ParseSelectors("li:focus")[0]
    check(!selector.MatchComplexIn(focusSel, b, ctx), ":focus is not :hover")
    ctx.Focused = b
    check(selector.MatchComplexIn(focusSel, b, ctx), ":focus matches the focused element")
    let spec = selector.ParseSelectors("li.x:not(#a):hover")[0].Specificity()
    check(spec.0 == 1 && spec.1 == 2 && spec.2 == 1, "specificity counts :not()'s argument (got \(spec.0),\(spec.1),\(spec.2))")
}


func testFormAndLanguagePseudoClasses() {
    print("Form state, language and direction pseudo-classes")
    let doc = html.Parse("""
    <div lang=en-US><p id=en>e</p><div lang=fr dir=rtl><p id=fr>f</p></div></div>
    <form id=f>
    <input id=req required><input id=filled required value=x><input id=mail type=email value=nope>
    <input id=num type=number min=1 max=5 value=9><input id=num2 type=number min=1 max=5 value=3>
    <input id=ro readonly value=r><textarea id=ta></textarea><input id=cb type=checkbox checked>
    <input type=radio name=g id=r1><input type=radio name=g id=r2>
    <input id=short minlength=3 value=ab><button id=go>go</button><button id=go2>go</button>
    </form>
    <details id=d open><summary>s</summary></details><ul><li class=i id=i1><li id=n><li class=i id=i2><li class=i id=i3></ul>
    <div contenteditable><p id=ce>c</p></div>
    """)
    func ids(_ sel: string) -> string {
        return selector.QuerySelectorAll(sel, in: doc.Root).map { $0.GetAttribute("id") ?? "?" }.filter { $0 != "?" }.joined(separator: " ")
    }
    check(ids(":lang(en)") == "en", ":lang matches a prefix before a hyphen (got \(ids(":lang(en)")))")
    check(ids("p:lang(fr)") == "fr" && ids("p:lang(\"*-US\")") == "en", ":lang takes the nearest lang, and wildcards")
    check(ids("p:dir(rtl)") == "fr" && ids("p:dir(ltr)").hasPrefix("en"), ":dir follows dir attributes (got \(ids("p:dir(ltr)")))")
    check(ids("input:invalid") == "req mail num short", ":invalid: required and empty, a bad email, out of range, too short (got \(ids("input:invalid")))")
    check(ids("form:invalid") == "f" && ids(":valid").contains("filled"), "a form with an invalid control is :invalid")
    check(ids(":out-of-range") == "num" && ids(":in-range") == "num2", ":in-range and :out-of-range")
    check(ids("input:read-only").contains("ro") && ids(":read-write").contains("ta") && ids("p:read-write") == "ce", ":read-only, :read-write and contenteditable")
    check(ids(":default") == "cb go", ":default: what is checked, and the form's first submit button (got \(ids(":default")))")
    check(ids(":indeterminate") == "r1 r2", "radios with none checked are :indeterminate")
    check(ids(":open") == "d", ":open is an open details")
    check(ids("li:nth-child(2 of .i)") == "i2" && ids("li:nth-last-child(1 of .i)") == "i3", ":nth-child(An+B of S) counts the matching siblings")
}

func testColors() {
    print("Testing css.ParseColor...")
    check(css.ParseColor("#fff") == draw.Color(255, 255, 255), "#fff")
    check(css.ParseColor("#0969da") == draw.Color(9, 105, 218), "#rrggbb")
    check(css.ParseColor("#00FF0080") == draw.Color(0, 255, 0, 128), "#rrggbbaa")
    check(css.ParseColor("rgb(1, 2, 3)") == draw.Color(1, 2, 3), "rgb()")
    check(css.ParseColor("rgba(255, 0, 0, 0.5)") == draw.Color(255, 0, 0, 128), "rgba()")
    check(css.ParseColor("rgb(100% 0% 50% / 25%)") == draw.Color(255, 0, 128, 64), "rgb() with slash alpha")
    check(css.ParseColor("hsl(120, 100%, 50%)") == draw.Color(0, 255, 0), "hsl()")
    check(css.ParseColor("hsl(0 0% 100%)") == draw.Color(255, 255, 255), "hsl() white")
    check(css.ParseColor("RebeccaPurple") == draw.Color(102, 51, 153), "named color, any case")
    check(css.ParseColor(" transparent ") == draw.Color.transparent, "transparent, trimmed")
    check(css.ParseColor("nonsense") == nil, "unknown name is nil")
    check(css.ParseColor("#12345") == nil, "bad hex length is nil")
    near("hsl(0.5turn 100% 50%)", draw.Color(0, 255, 255))
    near("rgb(none 0 0)", draw.Color(0, 0, 0))
    near("hwb(0 0% 0%)", draw.Color(255, 0, 0))
    near("hwb(120 0% 50%)", draw.Color(0, 128, 0))
    near("hwb(0 60% 60%)", draw.Color(128, 128, 128))
    near("lab(50 0 0)", draw.Color(119, 119, 119))
    near("lab(54.29% 80.8 69.89)", draw.Color(255, 0, 0))
    near("lch(54.29 106.84 40.85)", draw.Color(255, 0, 0))
    near("oklab(1 0 0)", draw.Color(255, 255, 255))
    near("oklab(0% 0 0 / 0.5)", draw.Color(0, 0, 0, 128))
    near("oklch(62.8% 0.2577 29.23)", draw.Color(255, 0, 0))
    near("oklch(0.452 0.313 264.05)", draw.Color(0, 0, 255))
    near("color(srgb 0 0.5 1)", draw.Color(0, 128, 255))
    near("color(srgb-linear 0.5 0.5 0.5)", draw.Color(188, 188, 188))
    // Out of sRGB's gamut, colors are mapped into it (CSS Color 4):
    // chroma lowered in OKLCH, so P3's red keeps its hue rather than
    // clipping to sRGB's, and a far-out oklch() keeps its lightness.
    near("color(display-p3 1 0 0)", draw.Color(255, 11, 12))
    near("oklch(1.2 0.1 30)", draw.Color(255, 255, 255))
    near("color(display-p3 0.5 0.5 0.5)", draw.Color(128, 128, 128))
    near("color(a98-rgb 0.5 0.5 0.5)", draw.Color(128, 128, 128))
    near("color(prophoto-rgb 0.5 0.5 0.5)", draw.Color(146, 146, 146))
    near("color(rec2020 0.5 0.5 0.5)", draw.Color(139, 139, 139))
    near("color(xyz 0.9505 1 1.089)", draw.Color(255, 255, 255))
    near("color(xyz-d50 0.9642 1 0.8251)", draw.Color(255, 255, 255))
    near("color-mix(in srgb, red, blue)", draw.Color(128, 0, 128))
    near("color-mix(in srgb, red 25%, blue)", draw.Color(64, 0, 191))
    near("color-mix(in srgb, 25% red, blue)", draw.Color(64, 0, 191))
    near("color-mix(in srgb, red 20%, blue 20%)", draw.Color(128, 0, 128, 102))
    near("color-mix(in srgb, red, transparent)", draw.Color(255, 0, 0, 128))
    near("color-mix(in oklab, white, black)", draw.Color(99, 99, 99))
    near("color-mix(white, black)", draw.Color(99, 99, 99))
    near("color-mix(in hsl, red, blue)", draw.Color(255, 0, 255))
    near("color-mix(in hsl longer hue, red, blue)", draw.Color(0, 255, 0))
    near("color-mix(in oklch, white, red)", draw.Color(255, 161, 145))
    near("rgb(from red r g b / 50%)", draw.Color(255, 0, 0, 128))
    near("rgb(from #336699 b g r)", draw.Color(153, 102, 51))
    near("hsl(from red calc(h + 120) s l)", draw.Color(0, 255, 0))
    near("oklch(from red l c h)", draw.Color(255, 0, 0))
    near("lab(from #777777 calc(l * 2) a b)", draw.Color(255, 255, 255))
    near("color(from red srgb r g calc(b + 1))", draw.Color(255, 0, 255))
    near("rgb(from rgb(0 0 0 / 40%) 255 255 255 / alpha)", draw.Color(255, 255, 255, 102))
    near("contrast-color(white)", draw.Color(0, 0, 0))
    near("contrast-color(navy)", draw.Color(255, 255, 255))
    near("light-dark(red, blue)", draw.Color(255, 0, 0))
    check(css.ParseColor("lab(50)") == nil, "lab() with one channel is nil")
    check(css.ParseColor("hsl(10% 50% 50%)") == nil, "a percentage hue is nil")
    check(css.ParseColor("color(foo 1 1 1)") == nil, "color() in an unknown space is nil")
    check(css.ParseColor("color-mix(in srgb, red 120%, blue)") == nil, "color-mix() over 100% is nil")
}

/// Checks a color parses to within one step of each channel.
func near(_ text: string, _ want: draw.Color) {
    guard let c = css.ParseColor(text) else {
        check(false, "\(text) parses")
        return
    }
    func d(_ a: uint8, _ b: uint8) -> int { return a > b ? int(a - b) : int(b - a) }
    let ok = d(c.R, want.R) <= 1 && d(c.G, want.G) <= 1 && d(c.B, want.B) <= 1 && d(c.A, want.A) <= 1
    check(ok, "\(text) (got \(c.R) \(c.G) \(c.B) \(c.A))")
}

func testNesting() {
    print("Nesting")
    let sheet = css.Parse("""
    .card {
        padding: 4px;
        &:hover { color: red; }
        & .title, .sub { font-weight: 700; }
        h2 { margin: 0; }
        a:hover { color: blue; }
        > p { margin: 1px; }
        .inner { &.on { color: green; } }
        *zoom: 1;
        color: black;
    }
    a, b { &:focus { outline: none } }
    """)
    var got: [string] = []
    for r in sheet.Rules { got.append(r.Selectors.joined(separator: ", ")) }
    same(got.joined(separator: " | "),
         ".card | .card:hover | .card .title, .card .sub | .card h2 | .card a:hover | .card > p | .card .inner | .card .inner.on | a, b | :is(a, b):focus",
         "nested rules are flattened after their parent, their selectors composed with its")
    let card = sheet.Rules[0]
    check(card.GetDeclaration("padding") != nil && card.GetDeclaration("color")?.Value == "black",
          "the parent keeps its declarations, before and after the nested rules")
    check(sheet.Rules[5].GetDeclaration("margin")?.Value == "1px", "a nested rule keeps its own declarations")
    check(css.Parse("p { color: red; } .x { a { b: c } }").Rules.count == 3, "a rule nested without & is a descendant")
}

func testNames() {
    print("Property names")
    let applied = css.AppliedPropertyNames()
    let unapplied = css.UnappliedPropertyNames()
    var both: [string] = []
    for n in unapplied where applied.contains(n) { both.append(n) }
    check(both.isEmpty, "no property is both applied and not (got \(both))")
    var unknown: [string] = []
    for n in applied where !css.IsKnownProperty(n) && css.Longhands(css.Declaration(property: n, value: "initial", important: false, tokens: [])).isEmpty && !["outline", "place-items", "flex-flow", "inset", "grid-gap", "border-top", "border-right", "border-bottom", "border-left"].contains(n) { unknown.append(n) }
    check(unknown.isEmpty, "every applied name is one the engine expands (got \(unknown))")
    check(applied.contains("margin") && applied.contains("color") && applied.contains("transition") && applied.contains("clip-path") && applied.contains("border-image") && unapplied.contains("writing-mode"), "the lists hold what they should")
}

func main() -> int32 {
    testNames()
    testNesting()
    testCSS()
    testSelector()
    testPseudoClasses()
    testColors()
    testFormAndLanguagePseudoClasses()

    if failures == 0 {
        print("ALL CSS CHECKS PASSED")
        return 0
    }
    print("FAILED: \(failures) check(s) did not pass.")
    return 1
}
