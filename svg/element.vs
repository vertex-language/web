package svg

import (
    "encoding/xml"
    "web/html"
)

let svgNamespace = "http://www.w3.org/2000/svg"
let xlinkNamespace = "http://www.w3.org/1999/xlink"

/// An element as this package reads one, whichever markup it came from:
/// an inline <svg>'s HTML tree, or an SVG file's XML tree. Names are
/// lowercased, as HTML has them, so one set of comparisons serves both.
final class element {
    let TagName: string
    var attributes: [string: string] = [:]
    var Children: [element] = []

    init(_ name: string) {
        TagName = name
    }

    func GetAttribute(_ name: string) -> string? {
        return attributes[name]
    }
}

/// The element for an HTML one, with its element children.
func fromHTML(_ n: html.Node) -> element {
    let e = element(n.TagName)
    for a in n.Attributes { e.attributes[a.Name] = a.Value }
    for c in n.Children where c.Kind == html.NodeKind.element {
        e.Children.append(fromHTML(c))
    }
    return e
}

/// The element for an XML one. Elements of other namespaces (an editor's
/// own, say) keep a name no SVG element has, so nothing draws them; an
/// XLink attribute is named xlink:..., as HTML names it.
func fromXML(_ x: xml.Element) -> element {
    let space = x.Name.Space
    var name = x.Name.Local.lowercased()
    if space != svgNamespace && space != "" { name = "\(space):\(name)" }
    let e = element(name)
    for a in x.Attributes {
        if a.Name.Space == "" {
            e.attributes[a.Name.Local.lowercased()] = a.Value
        } else if a.Name.Space == xlinkNamespace {
            e.attributes["xlink:\(a.Name.Local.lowercased())"] = a.Value
        }
    }
    for c in x.Elements { e.Children.append(fromXML(c)) }
    return e
}
