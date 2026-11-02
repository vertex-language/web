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
    "inset-block-start", "inset-block-end", "inline-size", "block-size", "min-inline-size", "max-inline-size",
    "min-block-size", "max-block-size", "border-inline", "border-block", "border-inline-start", "border-inline-end",
    "border-block-start", "border-block-end", "border-inline-end-width", "border-block-start-width",
    "border-block-end-width", "grid-template", "grid", "place-self", "place-content", "text-wrap", "overscroll-behavior", "contain-intrinsic-size", "scroll-padding", "scroll-margin", "scroll-padding-block", "scroll-padding-inline", "scroll-margin-block", "scroll-margin-inline", "transition", "-webkit-transition", "animation", "-webkit-animation", "container", "mask", "-webkit-mask", "border-image", "-webkit-border-image", "columns", "column-rule"
]

/// Properties the engine knows and parses past, but does not apply yet:
/// a page that uses them renders without them. The same names as the
/// case in Longhands that sets nothing.
let unappliedNames: [string] = [
    "perspective", "perspective-origin", "backface-visibility",
    "transform-style", "transform-box",
    "font-variant", "font-stretch", "font-feature-settings", "src",
    "unicode-range",
    "text-rendering", "-webkit-font-smoothing", "-moz-osx-font-smoothing",
    "hyphens",
    "writing-mode",
    "caption-side", "empty-cells", "speak", "font-display",
    "text-size-adjust", "-webkit-text-size-adjust",
    "-webkit-tap-highlight-color",
    "list-style-image", "font-kerning", "text-align-last", "text-justify",
    "font-variant-numeric", "font-variant-ligatures", "font-optical-sizing",
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
