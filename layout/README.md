# web/layout

The box tree and its layout: block, inline, flex, grid, tables, floats, positioning, scrolling. Hit testing.

```vertex
import "web/layout"
```

## Types

- **`BoxKind`** (enum): What kind of box a layout box is.
- **`ReplacedKind`** (enum): What a replaced box shows.
- **`Box`** (class)
- **`Line`** (struct): One line of a block container's inline content.
- **`FragmentKind`** (enum)
- **`Fragment`** (struct): A piece of a line: a run of text in one style, or an atomic box.
- **`Span`** (struct): The stretch of an inline element's box along one line.
- **`BoxTreeBuilder`** (class): What the box tree builder needs from the view: styles, the page's state, and images.
- **`Hit`** (struct): What lies under a point: the deepest box, the element it belongs to, and for text, where in the text.
- **`ContainingBlock`** (struct): What a box is laid out against: the width of the containing block, and its height where that is known.
- and 1 more

## Functions

- `func IsBlank(_ s: string) -> bool`
- `func HitTest(_ box: Box, _ px: float32, _ py: float32, originX: float32, originY: float32) -> Hit?`: The innermost box under a page point.
- `func PagePosition(_ box: Box) -> (x: float32, y: float32)`: The page position of a box: its corner with every ancestor's added.
- `func ReadsAttribute(_ name: string) -> bool`: Whether building or laying out boxes reads an attribute itself, as an image's source or a cell's span: a change to it rebuilds the element's boxes.

Part of the [`web`](https://github.com/vertex-language/web) repository.
