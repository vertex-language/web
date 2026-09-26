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

func main() -> int32 {
    testTreeBuilding()
    testHTML()

    if failures == 0 {
        print("ALL HTML CHECKS PASSED")
        return 0
    }
    print("FAILED: \(failures) check(s) did not pass.")
    return 1
}
