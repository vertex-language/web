package css

/// A standard CSS rule with a list of selectors and declarations.
public struct Rule {
    public var Selectors: [string]
    public var Declarations: [Declaration]
    /// Where the rule stands among the rules and at-rules of its sheet,
    /// in source order: a sheet keeps the two apart, and the cascade
    /// needs them in the order they were written.
    public var Position: int = 0

    public init(selectors: [string], declarations: [Declaration]) {
        self.Selectors = selectors
        self.Declarations = declarations
    }

    /// Looks up a declaration for a specific property name.
    public func GetDeclaration(_ property: string) -> Declaration? {
        let lower = toLower(property)
        var i = 0
        while i < Declarations.count {
            if Declarations[i].Property == lower {
                return Declarations[i]
            }
            i += 1
        }
        return nil
    }
}

/// An at-rule, such as `@media (min-width: 600px) { ... }`, which holds
/// rules, or `@font-face { ... }`, which holds declarations.
public struct AtRule {
    public var Name: string
    public var Params: string
    public var Rules: [Rule]
    public var Declarations: [Declaration]
    /// At-rules inside this one's block, in order: `@media` inside
    /// `@layer`, `@supports` inside `@media`.
    public var AtRules: [AtRule]
    /// Where the at-rule stands in source order; see Rule.Position.
    public var Position: int = 0

    public init(name: string, params: string, rules: [Rule], declarations: [Declaration] = [], atRules: [AtRule] = []) {
        self.Name = toLower(name)
        self.Params = params
        self.Rules = rules
        self.Declarations = declarations
        self.AtRules = atRules
    }
}

/// A parsed CSS stylesheet containing rules and at-rules.
public class StyleSheet {
    public var Rules: [Rule]
    public var AtRules: [AtRule]

    public init(rules: [Rule] = [], atRules: [AtRule] = []) {
        self.Rules = rules
        self.AtRules = atRules
    }
}
