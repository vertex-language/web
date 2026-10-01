# web/paint

The display list for a laid-out tree (`Build`), and its rasterization onto `image/draw` (`Rasterize`).

```vertex
import "web/paint"
```

## Types

- **`PaintKind`** (enum)
- **`PaintItem`** (struct): One thing to paint, in CSS pixels on the page: a filled rectangle, a border, a run of text at a baseline, an image, or a change of clip.
- **`State`** (struct): Builds the list of what to paint from a laid-out box tree, in the order CSS paints: block backgrounds and borders, then floats, then inline content, with positioned boxes after their siblings.

## Functions

- `func Build(_ root: layout.Box, state: State, viewportWidth: float32, viewportHeight: float32, background: draw.Color) -> [PaintItem]`: The display list for a laid-out box tree: what to paint, in the order CSS paints it, in page coordinates.
- `func Rasterize(_ items: [PaintItem], on base: draw.Canvas, scale: float32, originX: float32, originY: float32, scrollX: float32, scrollY: float32)`: Paints a display list onto a canvas: page coordinates are scaled by the device scale and shifted by the view's origin and scroll.
- `func SelectedPart(_ f: layout.Fragment, _ node: html.Node, _ range: (start: dom.TextPosition, end: dom.TextPosition), _ order: [int64: int]) -> (from: int, to: int)?`: The part of a text fragment inside a selection, as byte offsets into the fragment's text, or nil for none.
- `func ReadsAttribute(_ name: string) -> bool`: Whether painting reads an attribute itself, as a checkbox's check or a field's placeholder. `web/cmd/check-deps` keeps this in step with the code.

Part of the [`web`](https://github.com/vertex-language/web) repository.
