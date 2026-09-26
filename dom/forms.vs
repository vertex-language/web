package dom

import "web/html"

/// A field of a submitted form.
public struct FormField {
    public var Name: string
    public var Value: string

    public init(Name: string, Value: string) {
        self.Name = Name
        self.Value = Value
    }
}

/// A form submission: where it goes and what it carries.
public struct Submission {
    public var Action: string
    public var Method: string
    public var Fields: [FormField]

    public init(Action: string, Method: string, Fields: [FormField]) {
        self.Action = Action
        self.Method = Method
        self.Fields = Fields
    }
}

/// Whether an element edits text: a textarea, or an input of a text type.
public func IsTextControl(_ node: html.Node) -> bool {
    if node.TagName == "textarea" { return true }
    if node.TagName != "input" { return false }
    let type = lower(node.GetAttribute("type") ?? "text")
    switch type {
    case "text", "password", "search", "email", "url", "tel", "number", "": return true
    default: return false
    }
}

/// Whether an input is a button: submit, button, reset or image.
public func IsButtonInput(_ node: html.Node) -> bool {
    let type = lower(node.GetAttribute("type") ?? "text")
    return type == "submit" || type == "button" || type == "reset" || type == "image"
}

/// The input's type, lowercased; "text" when it names none.
public func InputType(_ node: html.Node) -> string {
    return lower(node.GetAttribute("type") ?? "text")
}

/// The form controls under a node, in document order.
public func Controls(_ node: html.Node) -> [html.Node] {
    var out: [html.Node] = []
    collectControls(node, &out)
    return out
}

func collectControls(_ node: html.Node, _ out: inout [html.Node]) {
    for c in node.Children where c.Kind == html.NodeKind.element {
        let tag = c.TagName
        if tag == "input" || tag == "textarea" || tag == "select" || tag == "button" {
            out.append(c)
        }
        collectControls(c, &out)
    }
}

/// The elements Tab moves through, in document order: enabled controls,
/// links with an href, and anything with a tabindex.
public func FocusOrder(_ root: html.Node) -> [html.Node] {
    var out: [html.Node] = []
    collectFocusable(root, &out)
    return out
}

func collectFocusable(_ node: html.Node, _ out: inout [html.Node]) {
    for c in node.Children where c.Kind == html.NodeKind.element {
        if c.HasAttribute("disabled") { continue }
        let tag = c.TagName
        if tag == "input" {
            if InputType(c) != "hidden" { out.append(c) }
        } else if tag == "textarea" || tag == "select" || tag == "button" {
            out.append(c)
        } else if tag == "a" && c.HasAttribute("href") {
            out.append(c)
        } else if c.HasAttribute("tabindex") {
            out.append(c)
        }
        collectFocusable(c, &out)
    }
}

/// The value a select submits: its selected option's, or its first's.
public func SelectedValue(_ select: html.Node) -> string {
    let options = Descendants(select, tag: "option")
    var first: html.Node? = nil
    for o in options {
        if first == nil { first = o }
        if o.HasAttribute("selected") { return o.GetAttribute("value") ?? trimSpaces(o.InnerText()) }
    }
    if let f = first { return f.GetAttribute("value") ?? trimSpaces(f.InnerText()) }
    return ""
}

/// The text a button stands for: its value attribute, or its text.
public func ButtonValue(_ button: html.Node) -> string {
    return button.GetAttribute("value") ?? trimSpaces(button.InnerText())
}

/// The control a label is for: the element its `for` names, or the
/// first control inside it.
public func LabelTarget(_ label: html.Node, in doc: html.Document?) -> html.Node? {
    if let id = label.GetAttribute("for"), let d = doc {
        return d.ElementById(id)
    }
    return Controls(label).first
}

/// The fields a form submits, as the HTML standard's form data set
/// builds them: named, enabled controls; checked boxes and radios;
/// only the button that submitted it. `value` answers a text control's
/// current text.
public func FormData(_ form: html.Node, submitter: html.Node?, value: (html.Node) -> string) -> [FormField] {
    var fields: [FormField] = []
    for c in Controls(form) {
        guard let name = c.GetAttribute("name"), !name.isEmpty else { continue }
        if c.HasAttribute("disabled") { continue }
        let tag = c.TagName
        if tag == "input" {
            let type = InputType(c)
            if type == "checkbox" || type == "radio" {
                if c.HasAttribute("checked") { fields.append(FormField(Name: name, Value: c.GetAttribute("value") ?? "on")) }
                continue
            }
            if type == "submit" || type == "button" || type == "reset" || type == "image" {
                if let s = submitter, s.Id == c.Id { fields.append(FormField(Name: name, Value: c.GetAttribute("value") ?? "")) }
                continue
            }
            fields.append(FormField(Name: name, Value: value(c)))
        } else if tag == "textarea" {
            fields.append(FormField(Name: name, Value: value(c)))
        } else if tag == "select" {
            fields.append(FormField(Name: name, Value: SelectedValue(c)))
        } else if tag == "button" {
            if let s = submitter, s.Id == c.Id { fields.append(FormField(Name: name, Value: c.GetAttribute("value") ?? "")) }
        }
    }
    return fields
}
