package main

import "web/html"

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

// MARK: - HTML Tests

func testTreeBuilding() {
    print("Testing web/html tree building...")
    let doc = html.Parse("<title>T</title><p>one<p>two<ul><li>a<li>b</ul><input disabled><textarea>x<b>y</textarea>")
    let htmls = doc.ElementsByTagName("html")
    let heads = doc.ElementsByTagName("head")
    let bodies = doc.ElementsByTagName("body")
    check(htmls.count == 1 && heads.count == 1 && bodies.count == 1, "html, head and body are made where the source has none")
    same(doc.Title, "T", "the title ends up in the head")
    if heads.count == 1 {
        check(heads[0].Children.count == 1 && heads[0].Children[0].TagName == "title", "the head holds the title and nothing else")
    }
    let ps = doc.ElementsByTagName("p")
    check(ps.count == 2, "a <p> is closed by the next <p> (\(ps.count) paragraphs)")
    if ps.count == 2 {
        same(ps[0].InnerText(), "one", "first paragraph's text")
        same(ps[1].InnerText(), "two", "second paragraph's text")
        check(ps[1].Parent != nil && ps[1].Parent?.TagName == "body", "the second paragraph is the body's, not the first's")
    }
    let lis = doc.ElementsByTagName("li")
    check(lis.count == 2 && lis[1].Parent?.TagName == "ul", "an <li> is closed by the next <li>")
    if let input = doc.ElementsByTagName("input").first {
        check(input.HasAttribute("disabled") && input.GetAttribute("disabled") == "", "a boolean attribute's value is the empty string")
    }
    if let area = doc.ElementsByTagName("textarea").first {
        same(area.InnerText(), "x<b>y", "a textarea's text is not markup")
        check(doc.ElementsByTagName("b").isEmpty, "no <b> was made inside the textarea")
    }
    let attrs = html.Parse("<div CLASS='x' Data-ID=7></div>")
    if let div = attrs.ElementsByTagName("div").first {
        check(div.GetAttribute("class") == "x" && div.Attributes[0].Name == "class", "attribute names are lowercased")
        check(div.GetAttribute("data-id") == "7", "unquoted attribute values")
    }
    let links = html.Parse("<link href=https://example.com/a.css rel=stylesheet><img src=/x.png/>")
    if let link = links.ElementsByTagName("link").first, let img = links.ElementsByTagName("img").first {
        check(link.GetAttribute("href") == "https://example.com/a.css" && link.GetAttribute("rel") == "stylesheet", "an unquoted URL keeps its slashes (got \(link.GetAttribute("href") ?? ""))")
        check(img.GetAttribute("src") == "/x.png/", "even one before the tag's end")
    }
    let table = html.Parse("<table><tr><td>a<td>b<tr><td>c</table>")
    check(table.ElementsByTagName("tr").count == 2 && table.ElementsByTagName("td").count == 3, "cells and rows close each other")
    let full = html.Parse("<!DOCTYPE html><html><head><meta charset=utf-8></head><body><p>x</p></body></html>")
    check(full.ElementsByTagName("head").count == 1 && full.ElementsByTagName("body").count == 1, "a complete document is left as it is")
}

func testHTML() {
    print("Testing web/html...")

    let htmlSource = """
    <!DOCTYPE html>
    <!-- Page comment -->
    <html lang="en">
      <head>
        <title>Vertex Test Page</title>
        <meta charset="utf-8" />
        <link rel="stylesheet" href="style.css" />
        <style>
          body { background: #fafafa; }
          h1 { color: #333; }
        </style>
      </head>
      <body>
        <div id="container" class="layout main-content">
          <h1 class="heading primary">Welcome to <em>Vertex</em>!</h1>
          <p id="intro">Here is an &lt;example&gt; of <strong>HTML &amp; CSS</strong> parsing.</p>
          <ul class="nav-list">
            <li class="item active"><a href="https://example.com/home">Home</a></li>
            <li class="item"><a href="https://example.com/docs">Documentation</a></li>
            <li class="item disabled"><span class="label">Inactive</span></li>
          </ul>
          <form action="/submit" method="post">
            <input type="text" name="username" value="galaxy" required />
            <input type="checkbox" checked />
          </form>
        </div>
      </body>
    </html>
    """

    let doc = html.Parse(htmlSource)

    // Document & Title
    same(doc.Title, "Vertex Test Page", "HTML document title parsed correctly")

    // Element by ID
    guard let container = doc.ElementById("container") else {
        check(false, "ElementById('container') found")
        return
    }
    check(true, "ElementById('container') found")
    same(container.TagName, "div", "container has tag 'div'")
    check(container.HasClass("layout"), "container has class 'layout'")
    check(container.HasClass("main-content"), "container has class 'main-content'")
    check(!container.HasClass("non-existent"), "container does not have class 'non-existent'")

    // Classes array
    let classes = container.Classes()
    check(classes.count == 2, "container has 2 classes")

    // Elements by Tag Name
    let listItems = doc.ElementsByTagName("li")
    check(listItems.count == 3, "found 3 <li> elements")

    let inputs = doc.ElementsByTagName("input")
    check(inputs.count == 2, "found 2 <input> elements (void elements)")
    if inputs.count >= 2 {
        same(inputs[0].GetAttribute("type") ?? "", "text", "first input type is 'text'")
        same(inputs[0].GetAttribute("value") ?? "", "galaxy", "first input value is 'galaxy'")
        check(inputs[0].HasAttribute("required"), "first input has 'required' attribute")
        check(inputs[1].HasAttribute("checked"), "second input has 'checked' attribute")
    }

    // Elements by Class Name
    let activeItems = doc.ElementsByClassName("active")
    check(activeItems.count == 1, "found 1 element with class 'active'")
    if !activeItems.isEmpty {
        same(activeItems[0].TagName, "li", "active element is <li>")
    }

    // Entities decoding
    guard let intro = doc.ElementById("intro") else {
        check(false, "ElementById('intro') found")
        return
    }
    same(intro.InnerText(), "Here is an <example> of HTML & CSS parsing.", "entities &lt;, &gt;, &amp; decoded correctly in text")

    // Raw text elements (<style>)
    let styles = doc.ElementsByTagName("style")
    check(styles.count == 1, "found 1 <style> element")
    if !styles.isEmpty {
        let cssText = styles[0].InnerText()
        check(cssText.utf8.count > 0, "<style> raw text preserved without tag parsing")
    }

    // Tree navigation (Element siblings)
    if listItems.count >= 2 {
        let first = listItems[0]
        let second = listItems[1]
        if let next = first.NextElementSibling() {
            check(next.Id == second.Id, "first <li>.NextElementSibling() points to second <li>")
        } else {
            check(false, "first <li> has next element sibling")
        }
        if let prev = second.PreviousElementSibling() {
            check(prev.Id == first.Id, "second <li>.PreviousElementSibling() points to first <li>")
        } else {
            check(false, "second <li> has previous element sibling")
        }
        check(first.PreviousElementSibling() == nil, "first <li> has no previous element sibling")
        if let parent = first.Parent {
            same(parent.TagName, "ul", "first <li> parent is <ul>")
        } else {
            check(false, "first <li> has parent")
        }
    }

    // Mutation
    let newLi = html.Node(kind: html.NodeKind.element, tagName: "li")
    newLi.SetAttribute("class", "item extra")
    container.AppendChild(newLi)
    let countAfterAdd = container.Children.count
    check(countAfterAdd > 0 && container.Children[countAfterAdd - 1].TagName == "li", "AppendChild successfully added new child")
    container.RemoveChild(newLi)
    let countAfterRemove = container.Children.count
    check(countAfterRemove > 0 && container.Children[countAfterRemove - 1].TagName != "li", "RemoveChild successfully removed child")

    // Serialization
    let rendered = html.Render(container)
    check(rendered.utf8.count > 0, "Render produced non-empty HTML string")
}

func testEncodings() {
    print("Encodings")
    let latin: [uint8] = [70, 114, 97, 110, 0xE7, 97, 105, 115, 32, 0x80]
    check(html.DetectEncoding(latin, contentType: "text/html; charset=ISO-8859-1") == "windows-1252", "iso-8859-1 in the Content-Type is windows-1252")
    check(html.Decode(latin, contentType: "text/html; charset=ISO-8859-1") == "Fran\u{E7}ais \u{20AC}", "windows-1252 decodes, 0x80 as the euro sign")
    let meta = [uint8]("<!doctype html><meta charset=\"windows-1252\"><p>caf".utf8) + [0xE9]
    check(html.DetectEncoding(meta) == "windows-1252", "a <meta charset> in the first bytes")
    check(html.Decode(meta).hasSuffix("caf\u{E9}"), "and decoded by it")
    let equiv = [uint8]("<meta http-equiv=Content-Type content='text/html; charset=latin1'>".utf8)
    check(html.DetectEncoding(equiv) == "windows-1252", "a <meta http-equiv=content-type>")
    check(html.DetectEncoding(meta, contentType: "text/html; charset=utf-8") == "utf-8", "the HTTP charset wins over the <meta>")
    let bom: [uint8] = [0xEF, 0xBB, 0xBF, 104, 105]
    check(html.DetectEncoding(bom, contentType: "text/html; charset=latin1") == "utf-8" && html.Decode(bom) == "hi", "a UTF-8 byte order mark wins, and is dropped")
    let utf16: [uint8] = [0xFF, 0xFE, 104, 0, 0x3D, 0xD8, 0x00, 0xDE]
    check(html.Decode(utf16) == "h\u{1F600}", "UTF-16LE with a surrogate pair")
    check(html.DetectEncoding([uint8]("<p>plain".utf8)) == "utf-8", "UTF-8 when nothing says otherwise")
    check(html.EncodingForLabel(" Latin1 ") == "windows-1252" && html.EncodingForLabel("shift_jis") == nil, "labels, and one not supported")
}

// A '<' that starts no tag is text, and <?...> a bogus comment: the
// scanner used to stop at either with nothing read, and loop forever.
func testStrayLessThan() {
    print("Stray '<'")
    let d = html.Parse("<p>a < b <</p>")
    let p = d.ElementsByTagName("p")
    check(p.count == 1 && p[0].InnerText() == "a < b <", "a '<' that starts nothing is text (\(p.first?.InnerText() ?? "none"))")
    check(html.Parse("x <").ElementsByTagName("body").count == 1, "a '<' at the end is text")
    let svg = html.Parse("<?xml version='1.0'?>\n<svg width='8'></svg>")
    check(svg.ElementsByTagName("svg").count == 1, "an XML declaration is a bogus comment, and what follows parses")
}

func main() -> int32 {
    testEncodings()
    testTreeBuilding()
    testHTML()
    testStrayLessThan()

    if failures == 0 {
        print("ALL HTML CHECKS PASSED")
        return 0
    }
    print("FAILED: \(failures) check(s) did not pass.")
    return 1
}
