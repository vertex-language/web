package dom

import "web/html"

/// An element's role: its role attribute, or what its tag implies; "" for
/// one with none of its own, which only holds what is in it.
public func RoleOf(node: html.Node) -> string {
    if let r = node.GetAttribute("role"), !r.isEmpty { return r }
    switch node.TagName {
    case "button", "summary": return "button"
    case "a": return node.HasAttribute("href") ? "link" : ""
    case "input":
        switch InputType(node) {
        case "hidden": return ""
        case "checkbox": return "checkbox"
        case "radio": return "radio"
        case "button", "submit", "reset", "image", "file", "color": return "button"
        case "range": return "slider"
        case "search": return "searchbox"
        case "number": return "spinbutton"
        default: return "textbox"
        }
    case "textarea": return "textbox"
    case "select": return "combobox"
    case "li": return "listitem"
    case "ul", "ol", "menu": return "list"
    case "h1", "h2", "h3", "h4", "h5", "h6": return "heading"
    case "img": return "img"
    case "svg": return node.HasAttribute("aria-label") ? "img" : ""
    case "video", "audio": return "group"
    case "nav": return "navigation"
    case "main": return "main"
    case "header": return "banner"
    case "footer": return "contentinfo"
    case "aside": return "complementary"
    case "section", "article": return node.HasAttribute("aria-label") ? "region" : ""
    case "form": return "form"
    case "dialog": return "dialog"
    case "table": return "table"
    case "tr": return "row"
    case "td": return "cell"
    case "th": return "columnheader"
    case "progress", "meter": return "progressbar"
    case "hr": return "separator"
    case "option": return "option"
    default: return ""
    }
}

/// Text with its runs of white space made one space, and trimmed.
public func CollapseSpace(text: string) -> string {
    var out: [uint8] = []
    var space = false
    for b in text.utf8 {
        if b == 32 || b == 10 || b == 9 || b == 13 {
            space = !out.isEmpty
        } else {
            if space { out.append(32) }
            space = false
            out.append(b)
        }
    }
    return string(decoding: out, as: UTF8.self)
}

/// What an assistive technology calls an element, in the order the
/// accessible name computation asks: aria-labelledby, aria-label, its label
/// or alt, what it holds where its role takes its name from there, its title.
public func AccessibleName(node: html.Node, in doc: html.Document?) -> string {
    if let ids = node.GetAttribute("aria-labelledby"), let d = doc {
        var parts: [string] = []
        for id in ids.split(separator: " ") {
            if let n = d.ElementById(string(id)) { parts.append(CollapseSpace(n.InnerText())) }
        }
        if !parts.isEmpty { return parts.joined(separator: " ") }
    }
    if let l = node.GetAttribute("aria-label"), !l.isEmpty { return CollapseSpace(l) }
    let tag = node.TagName
    if tag == "img", let a = node.GetAttribute("alt") { return CollapseSpace(a) }
    if tag == "input" || tag == "textarea" || tag == "select" || tag == "progress" || tag == "meter" {
        // A <label> that names it, or holds it.
        if let id = node.GetAttribute("id"), let d = doc {
            for l in d.ElementsByTagName("label") where l.GetAttribute("for") == id { return CollapseSpace(l.InnerText()) }
        }
        if let l = Ancestor(node, "label") { return CollapseSpace(l.InnerText()) }
        if tag == "input" {
            let type = InputType(node)
            if type == "submit" || type == "button" || type == "reset" { return node.GetAttribute("value") ?? (type == "submit" ? "Submit" : (type == "reset" ? "Reset" : "")) }
        }
        if let p = node.GetAttribute("placeholder") { return CollapseSpace(p) }
    }
    switch RoleOf(node) {
    case "button", "link", "heading", "listitem", "option", "cell", "columnheader", "checkbox", "radio", "menuitem", "tab", "row":
        let text = CollapseSpace(node.InnerText())
        if !text.isEmpty { return text }
    default:
        break
    }
    return CollapseSpace(node.GetAttribute("title") ?? "")
}
