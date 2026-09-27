// The live document checked on its own: typed mutation, and the journal
// each change is recorded in.
package main

import (
    "web/dom"
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

func load(_ source: string) -> dom.Document {
    return dom.Document(html.Parse(source))
}

func testAttributes() {
    print("Attributes")
    let doc = load("<div id=a title=old></div>")
    let a = doc.ElementById("a")!
    check(!doc.HasMutations, "a parsed document has an empty journal")

    a.SetAttribute("Title", "new")
    var records = doc.TakeRecords()
    check(records.count == 1 && records[0].Kind == .attributes, "setting an attribute records one change")
    check(records[0].AttributeName == "title" && records[0].OldValue == "old", "the record names the attribute, lowercase, and its old value")
    check(records[0].Target.Id == a.Node.Id, "the record's target is the element")
    check(!doc.HasMutations, "TakeRecords empties the journal")

    a.SetAttribute("title", "new")
    check(!doc.HasMutations, "setting an attribute to the value it has records nothing")

    a.SetAttribute("lang", "en")
    records = doc.TakeRecords()
    check(records.count == 1 && records[0].OldValue == nil, "a new attribute's old value is nil")

    a.RemoveAttribute("missing")
    check(!doc.HasMutations, "removing an attribute the element lacks records nothing")
    a.RemoveAttribute("lang")
    records = doc.TakeRecords()
    check(records.count == 1 && records[0].OldValue == "en" && !a.HasAttribute("lang"), "removing an attribute records its old value")

    check(a.ToggleAttribute("hidden") && a.HasAttribute("hidden"), "ToggleAttribute adds a missing attribute")
    check(!a.ToggleAttribute("hidden") && !a.HasAttribute("hidden"), "and removes a present one")
    check(!a.ToggleAttribute("hidden", force: false), "forced off where it is already off")
    check(doc.TakeRecords().count == 2, "only the toggles that changed something are recorded")
}

func testClassList() {
    print("ClassList")
    let doc = load("<p id=p class='one two'></p>")
    let p = doc.ElementById("p")!
    check(p.ClassList.Values == ["one", "two"], "the classes, in order")
    p.ClassList.Add("three")
    check(p.GetAttribute("class") == "one two three", "Add appends a class")
    p.ClassList.Add("one")
    p.ClassList.Remove("absent")
    check(doc.TakeRecords().count == 1, "adding a present class or removing an absent one records nothing")
    p.ClassList.Remove("two")
    check(p.GetAttribute("class") == "one three", "Remove takes the class out")
    check(p.ClassList.Toggle("two") && p.ClassList.Contains("two"), "Toggle adds a missing class")
    check(!p.ClassList.Toggle("two") && !p.ClassList.Contains("two"), "and removes a present one")
    check(p.ClassList.Toggle("one", force: true), "a forced toggle leaves a present class")
    let records = doc.TakeRecords()
    check(records.count == 3 && records[0].Kind == .attributes && records[0].AttributeName == "class", "class changes are attribute changes to class")
    check(records[0].OldValue == "one two three", "with the list as it was")
}

func testChildren() {
    print("Children")
    let doc = load("<ul id=list><li id=x>x</li><li id=y>y</li></ul><div id=other></div>")
    let list = doc.ElementById("list")!
    let other = doc.ElementById("other")!
    let li = doc.CreateElement("LI")
    check(li.TagName == "li" && li.Parent == nil, "CreateElement makes a detached element, lowercase")

    list.AppendChild(li)
    var records = doc.TakeRecords()
    check(records.count == 1 && records[0].Kind == .childList && records[0].Target.Id == list.Node.Id, "appending records a child-list change on the parent")
    check(records[0].Added.count == 1 && records[0].Added[0].Id == li.Id && records[0].Removed.isEmpty, "with the node added")
    check(list.Node.Children.count == 3 && li.Parent?.Id == list.Node.Id, "the child is last, and knows its parent")

    let y = doc.ElementById("y")!
    list.InsertBefore(li, y.Node)
    records = doc.TakeRecords()
    check(records.count == 2 && records[0].Removed.count == 1 && records[1].Added.count == 1, "moving a child records its removal and its insertion")
    check(list.Node.Children[1].Id == li.Id, "InsertBefore puts it before the reference child")

    other.AppendChild(li)
    records = doc.TakeRecords()
    check(records.count == 2 && records[0].Target.Id == list.Node.Id && records[1].Target.Id == other.Node.Id, "a node moved between parents is recorded on both")
    check(list.Node.Children.count == 2 && other.Node.Children.count == 1, "and is in one place only")

    doc.RemoveChild(list.Node, li)
    check(!doc.HasMutations, "removing a node from a parent it isn't under records nothing")
    doc.ElementFor(li).Remove()
    records = doc.TakeRecords()
    check(records.count == 1 && records[0].Removed.count == 1 && li.Parent == nil, "Remove takes an element out of the tree")
}

func testText() {
    print("Text")
    let doc = load("<p id=p>hello</p><div id=d><b>bold</b> and <i>it</i></div><span id=e></span>")
    let p = doc.ElementById("p")!
    p.TextContent = "goodbye"
    var records = doc.TakeRecords()
    check(p.TextContent == "goodbye", "TextContent sets the text")
    check(records.count == 1 && records[0].Kind == .characterData && records[0].OldValue == "hello", "a lone text child is changed in place, as character data")

    p.TextContent = "goodbye"
    check(!doc.HasMutations, "setting the same text records nothing")

    let d = doc.ElementById("d")!
    d.TextContent = "plain"
    records = doc.TakeRecords()
    check(d.Node.Children.count == 1 && d.TextContent == "plain", "TextContent replaces mixed children with one text node")
    check(records.count == 1 && records[0].Kind == .childList && records[0].Removed.count == 3 && records[0].Added.count == 1, "recorded as one child-list change")

    d.TextContent = ""
    check(d.Node.Children.isEmpty && doc.TakeRecords().count == 1, "empty text leaves no children")

    let e = doc.ElementById("e")!
    e.TextContent = ""
    check(!doc.HasMutations, "emptying an empty element records nothing")
}

func main() -> int32 {
    testAttributes()
    testClassList()
    testChildren()
    testText()
    if failures == 0 {
        print("ALL DOM CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
