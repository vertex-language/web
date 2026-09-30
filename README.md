# web

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![engine: html | css | cascade | layout | paint](https://img.shields.io/badge/engine-html%20%7C%20css%20%7C%20cascade%20%7C%20layout%20%7C%20paint-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/web)

The web engine: HTML and CSS parsed, styled, laid out and painted into
pixels, in pure Vertex. It needs no window. `ui/webview` puts a page in
one, and a headless program renders a page to an image itself.

The engine is split into packages, one per stage of the pipeline. Each
stage takes plain data in and gives plain data out, and each has its own
check program, so a stage can be tested and read on its own.

---

## Quick Start

```bash
# Render a page to a PNG, no window.
vsc run snapshot -- testdata/pages/home.html out.png 900 700 2

# Render a site the ui browser recorded (browser --record site/ https://...),
# offline, and ask what is at a point or matches a selector, and why.
vsc run snapshot -- --archive site/ out.png 1000 716
vsc run inspect -- --archive site/ 400,300 'tree:header' 4

# Time the stages on a page.
vsc run bench -- testdata/pages/docs.html

# The checks, one per stage.
vsc run check-html
vsc run check-css
vsc run check-dom
vsc run check-cascade
vsc run check-layout
vsc run check-page
vsc run check-fetch
vsc run check-svg
vsc run check-deps
```

---

## Packages

| Package | Stage | What it is |
| :--- | :--- | :--- |
| **`web/html`** | parse | The HTML tokenizer and tree builder, entities, the node tree, and a serializer. Character encodings as the HTML standard detects them (a byte order mark, the HTTP charset, `<meta charset>`), decoded from UTF-8, UTF-16 and windows-1252 (`Decode`). |
| **`web/css`** | parse | CSS syntax: tokens, rules, at-rules nested as deep as sheets nest them, declarations. `Coverage` says what a sheet declares and what the engine applies, by name. Typed values and the property table: every longhand the engine knows (`Prop`), values in their units (`Value`, `Length`), shorthands expanded into `Longhand`s, and CSS color syntax (`ParseColor`). |
| **`web/css/selector`** | parse | Selectors: the parser, the matcher (combinators, attributes, pseudo-classes, `:not()`, `:is()`, `:has()`), specificity, `QuerySelector`. |
| **`web/dom`** | document | The live document: typed mutation (`SetAttribute`, `AppendChild`, `TextContent`, `ClassList`) and the journal of every change, which is how the engine learns of one. Document positions (`TextPosition`) and the HTML standard's form semantics: text controls, focus order, labels, form data. |
| **`web/cascade`** | style | The user agent stylesheet, rule sets, the resolver, and `ComputedStyle`: the cascade, inheritance, `em`/`rem`/viewport units, `calc()`, custom properties and `var()`, `@media` (with the range syntax), `@supports`, `@layer`, and state (`:hover`, `:focus`, `:active`, `:visited`) re-matched without a rebuild. `Invalidate` turns the DOM journal into the subtrees to restyle, by what the selectors mention: a change nothing depends on costs no frame. |
| **`web/svg`** | paint | Inline SVG: `<path>` (every command, arcs too), basic shapes, `<g>` and transforms, fills (`currentColor`, fill-rule, opacity) and the viewBox, drawn with `image/draw`'s paths. No strokes, `<use>`, clipping or text yet. |
| **`web/layout`** | layout | The box tree and its layout: block, inline, flex, grid, tables, floats, positioning, scrolling. Hit testing. |
| **`web/paint`** | paint | The display list for a laid-out tree (`Build`), and its rasterization onto `image/draw` (`Rasterize`). |
| **`web/edit`** | input | Caret movement and text editing over UTF-8: characters, words, lines. |
| **`web/fetch`** | resources | URLs resolved against a base (through `net/url`), and a `Fetcher` that answers their bytes: files by default, or a host's handler. An `Archive` is a page and its resources recorded to a folder, shown again offline. |
| **`web`** | the page | `Page`: loads a document and its resources, runs the stages whose inputs changed, takes input (`Input`) in its own coordinates, and draws into pixels. |

Dependencies point down the pipeline, and nothing here imports `ui/`.
`cmd/check-deps` holds the repository to that:

```
web            Page, Input: the pipeline driver
 ├─ paint      display list, raster
 │   └─ layout       box tree, formatting contexts, hit testing
 │       └─ cascade      rules, computed style
 │           └─ css/selector ─ css ─ html
 ├─ dom, edit, fetch       the document, editing, resources
 └─ image/draw, text/font  below everything: pixels and glyphs
```

---

## A page without a window

```vertex
package main

import (
    "fs"
    "image"
    "image/draw"
    "image/png"
    "web"
)

@MainActor
func main() -> int32 {
    let page = web.Page()
    page.SetViewportSize(draw.Size(900, 700))
    try! page.LoadFile("docs/index.html")

    var pixels = [uint8](repeating: 0, count: 1800 * 1400 * 4)
    page.Draw(into: &pixels, width: 1800, height: 1400, scale: 2)
    try! fs.WriteFile(fs.Path("page.png"), png.Encode(image.RGBA(width: 1800, height: 1400, pixels: pixels)))
    return 0
}
```

Input is the page's own: points in CSS pixels from the viewport's corner,
and keys as the W3C names them.

```vertex
_ = page.Handle(.pointerDown(web.Pointer(draw.Point(40, 12))))
_ = page.Handle(.pointerUp(web.Pointer(draw.Point(40, 12))))
_ = page.Handle(.text("hello"))
_ = page.Handle(.keyDown(web.Key(Key: "Enter", Code: "Enter")))
```

### `Page`

| | |
| :--- | :--- |
| `LoadHTML(_:baseURL:)`, `LoadFile(_:)` | Show a page; relative references resolve against the base. |
| `Configuration` | `BaseURL`, `BackgroundColor`, and the `Fetcher` resources come from. |
| `SetViewportSize(_:)`, `ContentSize()` | The viewport, and the page's whole size. |
| `Draw(into:width:height:scale:at:)` | Paint into premultiplied RGBA pixels. |
| `Handle(_:)` | Take an `Input`: `.handled` or `.ignored`. |
| `NeedsRepaint()`, `DesiredCursor()` | What the host should do next. |
| `NeedsAnimation()`, `Advance(time:)` | The caret blinks: keep frames coming while true. |
| `ScrollOffset()`, `SetScrollOffset(_:)`, `ScrollTo(_:)`, `ScrollIntoViewIfNeeded(_:)` | Scrolling. |
| `OnNavigate`, `OnSubmit`, `OnAction`, `OnTitleChanged`, `OnHoverLink` | What the user did. |
| `IsVisited`, `VisitedChanged()` | Which links the host has been to, for `:visited`. |
| `Clipboard` | Where copy and paste go; the host provides it. |
| `Document`, `Title`, `QuerySelector(_:)`, `ElementAt(_:)`, `BoxFor(_:)`, `RootBox` | The page and its layout. `Document` is a `dom.Document`: change the page through it, and the next frame restyles. |
| `Focus(_:)`, `FocusedElement`, `ValueOf(_:)` | Forms. |
| `SelectedText()`, `SelectAll()`, `ClearSelection()`, `HasSelection` | Selection. |
| `SetImage(_:_:)` | Resources the host fetches. |

---

## What it renders

- **Style**: CSS nesting, `@layer`, `@scope`, the cascade with specificity, `!important`, inheritance, `em`,
  `rem` and viewport units, `calc()`, `@media` (including
  `prefers-color-scheme` and `prefers-reduced-motion`), `@import`,
  `@font-face`, `<link rel=stylesheet>`, `<base href>`, inline styles and
  presentational attributes, and a user agent stylesheet after the HTML
  standard's rendering section.
- **Layout**: block flow with collapsing margins; inline formatting with
  white-space handling, breaking, baselines, `justify` and `text-overflow`;
  inline-blocks; images and form controls; floats; flexbox; grid with
  `fr`, `repeat()`, `auto-fill` and spans; tables; absolute, fixed,
  relative and sticky positioning; overflow and scrolling.
- **Paint**: backgrounds with colors, gradients and images, rounded
  corners, borders in every style, box shadows, text decorations,
  opacity, `z-index`, and a display list that scrolls without layout.
- **Input**: hover and cursors, links, text editing in inputs and
  textareas, check boxes, radios, selects, buttons, labels, `<details>`,
  form submission, Tab focus, keyboard scrolling, text selection, copy
  and paste.

No JavaScript today. Scripting comes as an optional module, `web/script`
over the `js` repository, that a program opts into; a page without it
follows the HTML standard's rules for scripting disabled.
`proposed_webview.md` has the plan.

---

## License

[MIT](LICENSE)
