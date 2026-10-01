# web/cascade

The user agent stylesheet, rule sets, the resolver, and `ComputedStyle`: the cascade, inheritance, `em`/`rem`/viewport units, `calc()`, custom properties and `var()`, `@media` (with the range syntax), `@supports`, `@layer`, and state (`:hover`, `:focus`, `:active`, `:visited`) re-matched without a rebuild.

```vertex
import "web/cascade"
```

## Types

- **`StateEntry`** (struct): One selector of one rule, with what the cascade sorts by. One test of a rule that asks about hover, focus or the press.
- **`RuleSet`** (class): The rules of one origin, bucketed by what their rightmost compound asks for, so that an element is tested against the rules that could match it and not against every rule on the page.
- **`StyleResolver`** (class): Computes styles: the user agent's rules, the page's, the element's own attribute, in that order, sorted as the cascade sorts them.
- **`ComputedStyle`** (class): The style an element ends up with: every property, resolved as far as the cascade can without knowing the containing block.
- **`Display`** (enum)
- **`Position`** (enum)
- **`FloatSide`** (enum)
- **`Clear`** (enum)
- **`BoxSizing`** (enum)
- **`BorderStyle`** (enum)
- and 24 more

## Functions

- `func ReadsAttribute(_ name: string) -> bool`: Whether the cascade reads an attribute itself, outside any selector: inline style, and the presentational hints.
- `func SupportsCondition(_ text: string) -> bool`: Whether an @supports condition holds here: `(display: grid)` where the engine parses the declaration, `selector(:has(a))` where it parses and matches the selector, and those combined with `not`, `and` and `or`.
- `func UserAgentCSS() -> string`: The user agent stylesheet: what HTML looks like before a page says otherwise, after the standard's rendering section.
- `func UserAgentRules() -> RuleSet`

Part of the [`web`](https://github.com/vertex-language/web) repository.
