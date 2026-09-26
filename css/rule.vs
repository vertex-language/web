package css

/// A standard CSS rule with a list of selectors and declarations.
public struct Rule {
    public var Selectors: [string]
    public var Declarations: [Declaration]

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

    public init(name: string, params: string, rules: [Rule], declarations: [Declaration] = []) {
        self.Name = toLower(name)
        self.Params = params
        self.Rules = rules
        self.Declarations = declarations
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
