// What is at a point of a page, and why it looks as it does: the
// element there and its ancestors, each with its box and the computed
// styles that place it. For finding what a render gets wrong.
//
//     vsc run inspect -- page.html x,y [x,y ...]
//     vsc run inspect -- --archive site/ x,y [x,y ...]
//     vsc run inspect -- --archive site/ 'div.sr-only'      (a selector: every match)
//     vsc run inspect -- --archive site/ 'tree:header' 4    (a subtree, 4 levels deep)
package main

import (
    "image/draw"
    "web"
    "web/fetch"
    "web/html"
    "web/layout"
)

func describe(_ n: html.Node) -> string {
    var s = n.TagName
    if let id = n.GetAttribute("id") { s += "#" + id }
    for c in n.Classes() { s += "." + c }
    return s
}

@MainActor
func report(_ page: web.Page, _ node: html.Node) {
    var chain: [html.Node] = []
    var cur: html.Node? = node
    while let n = cur, n.Kind == html.NodeKind.element {
        chain.append(n)
        cur = n.Parent
    }
    for n in chain.reversed() {
        var line = "  " + describe(n)
        if let b = page.BoxFor(n) {
            let p = layout.PagePosition(b)
            let s = b.Style
            line += "  box \(int(p.x)),\(int(p.y)) \(int(b.Width))x\(int(b.Height))"
            line += "  display \(s.Display) position \(s.Position)"
            if s.OverflowX != .visible || s.OverflowY != .visible { line += " overflow \(s.OverflowX)/\(s.OverflowY)" }
            if s.Visibility != .visible { line += " visibility \(s.Visibility)" }
            if s.Opacity < 1 { line += " opacity \(s.Opacity)" }
        } else {
            line += "  (no box)"
        }
        print(line)
    }
}

/// An element and what is under it, a line each, to a depth.
@MainActor
func tree(_ page: web.Page, _ n: html.Node, _ depth: int, _ indent: string) {
    var line = indent + describe(n)
    if let b = page.BoxFor(n) {
        let p = layout.PagePosition(b)
        line += "  \(int(p.x)),\(int(p.y)) \(int(b.Width))x\(int(b.Height)) \(b.Style.Display) \(b.Style.Position)"
        if b.Style.Visibility != .visible { line += " visibility \(b.Style.Visibility)" }
        if b.Style.Opacity < 1 { line += " opacity \(b.Style.Opacity)" }
        if b.Style.ClipsOverflow { line += " clips" }
    } else {
        line += "  (no box)"
    }
    var text = ""
    for c in n.Children where c.Kind == html.NodeKind.text { text += c.Text }
    var t = ""
    var space = false
    for ch in text {
        if ch == " " || ch == "\n" || ch == "\t" { space = !t.isEmpty; continue }
        if space { t += " " }
        space = false
        t.append(ch)
    }
    if !t.isEmpty { line += "  \"" + string(t.prefix(40)) + "\"" }
    print(line)
    if depth <= 0 { return }
    for c in n.Children where c.Kind == html.NodeKind.element { tree(page, c, depth - 1, indent + "  ") }
}

@MainActor
func main() -> int32 {
    var args = CommandLine.arguments
    let page = web.Page()
    page.SetViewportSize(draw.Size(1000, 716))
    if args.count > 2 && args[1] == "--archive" {
        guard let archive = try? fetch.Archive.Read(from: args[2]), let entry = archive.Entries[archive.Page] else {
            print("cannot read the archive in \(args[2])")
            return 1
        }
        page.Configuration.Fetcher = archive.Fetcher()
        page.LoadBytes(entry.Body, contentType: entry.ContentType, baseURL: archive.Page)
        args.remove(at: 1)
        args.remove(at: 1)
    } else if args.count > 1 {
        do {
            try page.LoadFile(args[1])
        } catch {
            print("cannot read \(args[1])")
            return 1
        }
        args.remove(at: 1)
    } else {
        print("usage: inspect page.html x,y ... | inspect --archive dir x,y ...")
        return 2
    }
    _ = page.ContentSize()
    var k = 1
    while k < args.count {
        let a = args[k]
        k += 1
        if a.hasPrefix("tree:") {
            var depth = 3
            if k < args.count, let d = int(args[k]) {
                depth = d
                k += 1
            }
            for n in page.QuerySelectorAll(string(a.dropFirst(5))).prefix(3) { tree(page, n, depth, "") }
            continue
        }
        let parts = a.split(separator: ",")
        if parts.count == 2, let x = float32(string(parts[0])), let y = float32(string(parts[1])) {
            print("at \(a):")
            if let n = page.ElementAt(draw.Point(x, y)) { report(page, n) } else { print("  nothing") }
        } else {
            let found = page.QuerySelectorAll(a)
            print("\(a): \(found.count) elements")
            for n in found.prefix(5) {
                report(page, n)
                print("")
            }
        }
    }
    return 0
}
