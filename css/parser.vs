package css

/// Parser that converts CSS tokens into a StyleSheet or Declaration list.
public class Parser {
    var scanner: Scanner
    var current: Token
    /// Rules nested in the rule being parsed (CSS Nesting), flattened: each
    /// with its selectors composed with its parents'. The caller puts them
    /// after the rule they were in.
    var nested: [Rule] = []
    /// The next rule's or at-rule's source position.
    var position = 0

    public init(scanner: Scanner) {
        self.scanner = scanner
        self.current = scanner.Next()
    }

    func advance() {
        self.current = scanner.Next()
    }

    /// Parses the entire CSS stream into a StyleSheet.
    public func Parse() -> StyleSheet {
        var rules: [Rule] = []
        var atRules: [AtRule] = []

        while current.Kind != TokenKind.eof {
            if current.Kind == TokenKind.atKeyword {
                if let at = parseAtRule() { atRules.append(at) }
            } else if current.Kind == TokenKind.closeBrace {
                // A stray '}' closes nothing: skip it.
                advance()
            } else {
                if let rule = parseRule() {
                    rules.append(rule)
                    rules.append(contentsOf: takeNested())
                }
            }
        }

        return StyleSheet(rules: rules, atRules: atRules)
    }

    /// Parses an at-rule, current at its keyword: a statement ending in
    /// ';', a block of declarations (@font-face), or a block of rules
    /// and at-rules (@media, @supports, @layer, @container), nested as
    /// deep as the sheet nests them.
    func parseAtRule() -> AtRule? {
        let pos = nextPosition()
        guard var at = parseAtRuleInner() else { return nil }
        at.Position = pos
        return at
    }

    func nextPosition() -> int {
        position += 1
        return position
    }

    func parseAtRuleInner() -> AtRule? {
        let name = current.Value
        advance()
        var paramTokens: [Token] = []
        while current.Kind != TokenKind.openBrace && current.Kind != TokenKind.semicolon && current.Kind != TokenKind.eof && current.Kind != TokenKind.closeBrace {
            paramTokens.append(current)
            advance()
        }
        let params = trimString(Serialize(paramTokens))
        if current.Kind == TokenKind.semicolon {
            advance()
            return AtRule(name: name, params: params, rules: [])
        }
        if current.Kind != TokenKind.openBrace {
            return AtRule(name: name, params: params, rules: [])
        }
        advance() // skip '{'
        let lowerName = toLower(name)
        if lowerName == "font-face" || lowerName == "page" || lowerName == "counter-style" || lowerName == "font-feature-values" || lowerName == "property" || lowerName == "position-try" {
            // A block of declarations, not of rules.
            let decls = parseDeclarationBlock()
            return AtRule(name: name, params: params, rules: [], declarations: decls)
        }
        var innerRules: [Rule] = []
        var innerAtRules: [AtRule] = []
        while current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
            if current.Kind == TokenKind.atKeyword {
                if let at = parseAtRule() { innerAtRules.append(at) }
            } else if let rule = parseRule() {
                innerRules.append(rule)
                innerRules.append(contentsOf: takeNested())
            }
        }
        if current.Kind == TokenKind.closeBrace {
            advance()
        }
        return AtRule(name: name, params: params, rules: innerRules, atRules: innerAtRules)
    }

    func takeNested() -> [Rule] {
        let out = nested
        nested = []
        return out
    }

    /// Parses a single CSS rule (selectors + declaration block). Inside
    /// another rule, parents are its selectors, which this one's are
    /// composed with.
    func parseRule(parents: [string] = [], prefix: [Token] = []) -> Rule? {
        let pos = nextPosition()
        var selectors: [string] = []

        // Collect selectors until '{'. Parens nest: a `:not(a, b)` keeps
        // its comma.
        var tokens: [Token] = prefix
        var depth = 0
        while current.Kind != TokenKind.openBrace && current.Kind != TokenKind.eof {
            // A nested rule's selector ends at its '{': a ';' or '}' first
            // means it was not one, and nothing past it is taken.
            if !parents.isEmpty && depth == 0 && (current.Kind == TokenKind.semicolon || current.Kind == TokenKind.closeBrace) {
                if current.Kind == TokenKind.semicolon { advance() }
                return nil
            }
            if current.Kind == TokenKind.comma && depth == 0 {
                let s = trimString(Serialize(tokens))
                if !s.isEmpty {
                    selectors.append(s)
                }
                tokens = []
                advance()
                continue
            }
            if current.Kind == TokenKind.function || current.Kind == TokenKind.openParen { depth += 1 }
            if current.Kind == TokenKind.closeParen && depth > 0 { depth -= 1 }
            tokens.append(current)
            advance()
        }

        let lastSel = trimString(Serialize(tokens))
        if !lastSel.isEmpty {
            selectors.append(lastSel)
        }

        if current.Kind != TokenKind.openBrace {
            return nil
        }
        advance() // skip '{'

        if !parents.isEmpty {
            selectors = selectors.map { composeSelector($0, parents) }
        }
        let decls = parseDeclarationBlock(parents: selectors)
        var rule = Rule(selectors: selectors, declarations: decls)
        rule.Position = pos
        return rule
    }

    /// Parses a rule nested in a declaration block, in its place among the
    /// nested rules: before any nested in it.
    func parseNestedRule(parents: [string], prefix: [Token] = []) {
        let at = nested.count
        if let r = parseRule(parents: parents, prefix: prefix) {
            nested.insert(r, at: at)
        }
    }

    /// Parses declarations until matching '}'. Inside a rule, parents are
    /// its selectors, and a rule written among the declarations is nested
    /// in it.
    func parseDeclarationBlock(parents: [string] = []) -> [Declaration] {
        var decls: [Declaration] = []

        while current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
            if !parents.isEmpty && startsNestedRule(current) {
                // `&:hover {`, `.x {`, `> a {`, `:focus {`: a nested rule.
                if current.Kind == TokenKind.atKeyword {
                    // A nested at-rule is not read yet: skip its block.
                    skipBlock()
                    continue
                }
                parseNestedRule(parents: parents)
                continue
            }
            // Expect property name
            if current.Kind == TokenKind.ident {
                let prop = current.Value
                let propToken = current
                advance()

                if !parents.isEmpty && current.Kind != TokenKind.colon {
                    // `h1 {`, `li a {`: a nested rule that begins with a name.
                    parseNestedRule(parents: parents, prefix: [propToken])
                    continue
                }

                if current.Kind == TokenKind.colon {
                    let colonToken = current
                    advance() // skip ':'

                    var tokens: [Token] = []
                    var important = false
                    var depth = 0

                    var isRule = false
                    while current.Kind != TokenKind.eof {
                        if depth == 0 && (current.Kind == TokenKind.semicolon || current.Kind == TokenKind.closeBrace) {
                            break
                        }
                        if depth == 0 && current.Kind == TokenKind.openBrace && !parents.isEmpty {
                            // `a:hover {`: what looked like a declaration
                            // is a nested rule's selector.
                            isRule = true
                            break
                        }
                        if current.Kind == TokenKind.delim && current.Value == "!" {
                            advance()
                            if current.Kind == TokenKind.ident && toLower(current.Value) == "important" {
                                important = true
                                advance()
                                continue
                            }
                        }
                        if current.Kind == TokenKind.function || current.Kind == TokenKind.openParen { depth += 1 }
                        if current.Kind == TokenKind.closeParen && depth > 0 { depth -= 1 }
                        tokens.append(current)
                        advance()
                    }
                    if isRule {
                        parseNestedRule(parents: parents, prefix: [propToken, colonToken] + tokens)
                        continue
                    }
                    if !tokens.isEmpty {
                        tokens[0].SpaceBefore = false
                    }

                    decls.append(Declaration(property: prop, value: Serialize(tokens), important: important, tokens: tokens))

                    if current.Kind == TokenKind.semicolon {
                        advance()
                    }
                } else {
                    // Syntax error: skip to next semicolon or brace
                    skipToNextDeclaration()
                }
            } else {
                advance()
            }
        }

        if current.Kind == TokenKind.closeBrace {
            advance()
        }

        return decls
    }

    /// Skips an at-rule inside a block, up to and past its own block or ';'.
    func skipBlock() {
        var depth = 0
        while current.Kind != TokenKind.eof {
            if current.Kind == TokenKind.semicolon && depth == 0 {
                advance()
                return
            }
            if current.Kind == TokenKind.openBrace { depth += 1 }
            if current.Kind == TokenKind.closeBrace {
                if depth == 0 { return }
                depth -= 1
                if depth == 0 {
                    advance()
                    return
                }
            }
            advance()
        }
    }

    func skipToNextDeclaration() {
        while current.Kind != TokenKind.semicolon && current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
            advance()
        }
        if current.Kind == TokenKind.semicolon {
            advance()
        }
    }
}

/// A nested rule's selector with its parents': `&` stands for them, and a
/// selector without one is a descendant of them. More than one parent is
/// `:is(a, b)`.
func composeSelector(_ sel: string, _ parents: [string]) -> string {
    let parent = parents.count == 1 ? parents[0] : ":is(" + parents.joined(separator: ", ") + ")"
    if sel.contains("&") {
        var out = ""
        for ch in sel {
            if ch == "&" { out += parent } else { out.append(ch) }
        }
        return out
    }
    return parent + " " + sel
}

/// Whether a token in a declaration block begins a nested rule rather than
/// a declaration: `&`, `.`, `#id`, `:`, `[`, and the combinators.
func startsNestedRule(_ t: Token) -> bool {
    switch t.Kind {
    case .hash, .colon, .openBracket, .atKeyword:
        return true
    case .delim:
        return t.Value == "&" || t.Value == "." || t.Value == ">" || t.Value == "+" || t.Value == "~"
    default:
        return false
    }
}
