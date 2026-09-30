package css

// The property names the engine reads, for a compiler to check styles
// against before they reach a page (vsc checks .vss files with these;
// see proposed_vsx.md §7.4 and §13, question 10). web/cmd/css-names
// prints them, and vsc embeds what it prints.

/// Shorthands and logical properties the engine expands into longhands.
let shorthandNames: [string] = [
    "margin", "padding", "inset", "grid-area", "margin-inline", "margin-block", "padding-inline",
    "padding-block", "inset-inline", "inset-block", "border-width", "border-style", "border-color",
    "border", "border-top", "border-right", "border-bottom", "border-left", "border-radius",
    "background", "overflow", "font", "flex", "flex-flow", "gap", "grid-gap", "list-style",
    "text-decoration", "outline", "place-items", "margin-inline-start", "margin-inline-end",
    "margin-block-start", "margin-block-end", "padding-inline-start", "padding-inline-end",
    "padding-block-start", "padding-block-end", "border-inline-start-width",
    "border-inline-end-width", "border-start-start-radius", "border-start-end-radius",
    "border-end-start-radius", "border-end-end-radius", "inset-inline-start", "inset-inline-end",
    "inset-block-start", "inset-block-end"
]

/// Properties the engine knows and parses past, but does not apply yet:
/// a page that uses them renders without them. The same names as the
/// case in Longhands that sets nothing.
let unappliedNames: [string] = [
    "text-decoration-style", "text-decoration-thickness", "text-underline-offset", "transition",
    "animation", "transform", "quotes", "counter-reset", "counter-increment",
    "background-attachment", "font-variant", "font-stretch", "font-feature-settings", "src",
    "unicode-range", "user-select", "pointer-events", "appearance", "-webkit-appearance", "resize",
    "scroll-behavior", "text-rendering", "-webkit-font-smoothing", "-moz-osx-font-smoothing",
    "backdrop-filter", "clip-path", "object-fit", "will-change", "contain", "isolation", "hyphens",
    "direction", "unicode-bidi", "writing-mode", "columns", "column-count", "column-width",
    "caption-side", "empty-cells", "speak", "orphans", "widows", "page-break-before",
    "page-break-after", "break-inside", "font-display", "text-shadow", "mix-blend-mode",
    "background-clip", "background-origin", "outline-offset", "outline-style", "border-image",
    "box-decoration-break", "text-size-adjust", "-webkit-text-size-adjust",
    "-webkit-tap-highlight-color", "touch-action", "overscroll-behavior", "scrollbar-width",
    "scrollbar-color", "list-style-image", "font-kerning", "text-align-last", "text-justify",
    "font-variant-numeric", "font-variant-ligatures", "font-optical-sizing", "color-scheme",
    "accent-color", "caret-color", "border-inline", "border-block", "min-inline-size",
    "max-inline-size", "inline-size", "block-size", "place-content", "place-self", "justify-items",
    "justify-self", "grid", "grid-template", "grid-template-areas"
]

/// Every property name the engine applies: its longhands, and the
/// shorthands and logical names it expands. Sorted.
public func AppliedPropertyNames() -> [string] {
    var out: [string] = []
    for (name, _) in propNames { out.append(name) }
    out += shorthandNames
    return out.sorted()
}

/// Every property name the engine knows but does not apply yet. Sorted.
public func UnappliedPropertyNames() -> [string] {
    return unappliedNames.sorted()
}
