# web/css

CSS syntax: tokens, rules, at-rules nested as deep as sheets nest them, declarations. `Coverage` says what a sheet declares and what the engine applies, by name.

```vertex
import "web/css"
```

## Types

- **`Coverage`** (struct): What the engine makes of a stylesheet: how many declarations it applies, and, by name, what it drops.
- **`Declaration`** (struct): A single CSS property declaration, such as `color: red !important;`.
- **`Parser`** (class): Parser that converts CSS tokens into a StyleSheet or Declaration list.
- **`Prop`** (enum): The properties the engine knows, each a longhand. Shorthands are expanded into these when a declaration is parsed.
- **`Unit`** (enum): A unit a length was written in.
- **`Value`** (enum): A declaration's value as parsed: typed, but with lengths still in their units, since em and rem depend on the element it lands on.
- **`CalcTerm`** (struct): One term of a calc(): a number in a unit, or unitless.
- **`ShadowValue`** (struct): A box-shadow before its lengths are resolved.
- **`Longhand`** (struct): One longhand and its value, as the cascade applies it.
- **`Rule`** (struct): A standard CSS rule with a list of selectors and declarations.
- and 8 more

## Functions

- `func LonghandsOf(_ name: string) -> [Prop]`: The longhands a property sets: itself, or a shorthand's parts. Empty for a property the engine doesn't know.
- `func IsKnownProperty(_ name: string) -> bool`: Whether the engine knows a property: a longhand it computes, or a shorthand it expands.
- `func ParseColor(_ text: string) -> draw.Color?`: Parses a CSS color: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`, `hsla()`, `transparent` and the named colors.
- `func Parse(_ source: string) -> StyleSheet`: Parses a CSS stylesheet string into a StyleSheet struct.
- `func Parse(_ sourceBytes: borrowing [uint8]) -> StyleSheet`: Parses CSS bytes into a StyleSheet struct.
- `func ParseDeclarations(_ inlineStyle: string) -> [Declaration]`: Parses an inline CSS style attribute (e.g. `color: red; font-size: 14px;`).
- `func AppliedPropertyNames() -> [string]`: Every property name the engine applies: its longhands, and the shorthands and logical names it expands.
- `func UnappliedPropertyNames() -> [string]`: Every property name the engine knows but does not apply yet. Sorted.
- `func Longhands(_ d: Declaration) -> [Longhand]`: Parses a declaration from a stylesheet into the longhands it sets.
- `func Serialize(_ tokens: [Token]) -> string`: The text a run of tokens spells, with a space wherever the source had one and strings quoted again.

Part of the [`web`](https://github.com/vertex-language/web) repository.
