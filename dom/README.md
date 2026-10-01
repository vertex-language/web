# web/dom

The live document: typed mutation (`SetAttribute`, `AppendChild`, `TextContent`, `ClassList`) and the journal of every change, which is how the engine learns of one. Document positions (`TextPosition`) and the HTML standard's form semantics: text controls, focus order, labels, form data.

```vertex
import "web/dom"
```

## Types

- **`MutationKind`** (enum): What a mutation changed, in MutationObserver's terms.
- **`MutationRecord`** (struct): One change to the tree. The cascade turns these into the elements to restyle, and layout into the boxes to rebuild.
- **`Document`** (class): The live document: the tree, and the journal of every change made to it since the engine last looked.
- **`Element`** (class): An element of a live document: reads go to the node, changes go through the document's journal. A handle: two for one node are the same element.
- **`ClassList`** (struct): An element's classes, as the `class` attribute lists them.
- **`TextPosition`** (struct): A point in the document's text: a text node and a byte offset into its text. One end of a selection.
- **`Event`** (class): An event dispatched to an element: what happened, where, and whether a listener asked for the default action not to be taken.
- **`MouseEvent`** (class): A pointer press and release on the same element, and its kin.
- **`InputEvent`** (class): A text control's value changed by the user.
- **`KeyboardEvent`** (class): A key, as the W3C names keys and codes.
- and 10 more

## Functions

- `func Ancestor(_ node: html.Node?, _ tag: string) -> html.Node?`: The nearest element at or above a node with a tag name, or nil.
- `func LinkAncestor(_ node: html.Node?) -> html.Node?`: The link a node is inside: the nearest `<a>` or `<area>` with an href.
- `func ControlAncestor(_ node: html.Node?) -> html.Node?`: The form control a node is inside: the nearest input, textarea, button or select.
- `func Contains(_ a: html.Node, _ b: html.Node) -> bool`: Whether a is b or one of b's ancestors.
- `func Descendants(_ node: html.Node, tag: string) -> [html.Node]`: The elements under a node with a tag name, in document order.
- `func IsTextControl(_ node: html.Node) -> bool`: Whether an element edits text: a textarea, or an input of a text type.
- `func IsButtonInput(_ node: html.Node) -> bool`: Whether an input is a button: submit, button, reset or image.
- `func InputType(_ node: html.Node) -> string`: The input's type, lowercased; "text" when it names none.
- `func Controls(_ node: html.Node) -> [html.Node]`: The form controls under a node, in document order.
- `func FocusOrder(_ root: html.Node) -> [html.Node]`: The elements Tab moves through, in document order: enabled controls, links with an href, and anything with a tabindex.
- and 4 more

Part of the [`web`](https://github.com/vertex-language/web) repository.
