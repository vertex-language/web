package html

/// Serializes an HTML Node or Document tree into an HTML string.
public func Render(_ node: Node) -> string {
    switch node.Kind {
    case .text:
        return Escape(node.Text)

    case .comment:
        return "<!--" + node.Text + "-->"

    case .document:
        var out = ""
        var i = 0
        while i < node.Children.count {
            out += Render(node.Children[i])
            i += 1
        }
        return out

    case .element:
        var out = "<" + node.TagName
        var i = 0
        while i < node.Attributes.count {
            let attr = node.Attributes[i]
            out += " " + attr.Name + "=\"" + Escape(attr.Value) + "\""
            i += 1
        }

        if isVoidElement(node.TagName) {
            out += " />"
            return out
        }

        out += ">"
        var j = 0
        while j < node.Children.count {
            out += Render(node.Children[j])
            j += 1
        }
        out += "</" + node.TagName + ">"
        return out
    }
}
