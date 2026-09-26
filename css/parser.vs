package css

/// Parser that converts CSS tokens into a StyleSheet or Declaration list.
public class Parser {
    var scanner: Scanner
    var current: Token

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
                let name = current.Value
                advance()
                // Collect params until '{' or ';'
                var paramTokens: [Token] = []
                while current.Kind != TokenKind.openBrace && current.Kind != TokenKind.semicolon && current.Kind != TokenKind.eof {
                    paramTokens.append(current)
                    advance()
                }
                let params = Serialize(paramTokens)
                if current.Kind == TokenKind.openBrace {
                    advance() // skip '{'
                    let lowerName = toLower(name)
                    if lowerName == "font-face" || lowerName == "page" || lowerName == "counter-style" || lowerName == "font-feature-values" || lowerName == "property" {
                        // A block of declarations, not of rules.
                        let decls = parseDeclarationBlock()
                        atRules.append(AtRule(name: name, params: trimString(params), rules: [], declarations: decls))
                        continue
                    }
                    var innerRules: [Rule] = []
                    while current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
                        if let rule = parseRule() {
                            innerRules.append(rule)
                        }
                    }
                    if current.Kind == TokenKind.closeBrace {
                        advance()
                    }
                    atRules.append(AtRule(name: name, params: trimString(params), rules: innerRules))
                } else if current.Kind == TokenKind.semicolon {
                    advance()
                    atRules.append(AtRule(name: name, params: trimString(params), rules: []))
                }
            } else {
                if let rule = parseRule() {
                    rules.append(rule)
                }
            }
        }

        return StyleSheet(rules: rules, atRules: atRules)
    }

    /// Parses a single CSS rule (selectors + declaration block).
    func parseRule() -> Rule? {
        var selectors: [string] = []

        // Collect selectors until '{'. Parens nest: a `:not(a, b)` keeps
        // its comma.
        var tokens: [Token] = []
        var depth = 0
        while current.Kind != TokenKind.openBrace && current.Kind != TokenKind.eof {
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

        let decls = parseDeclarationBlock()
        return Rule(selectors: selectors, declarations: decls)
    }

    /// Parses declarations until matching '}'.
    func parseDeclarationBlock() -> [Declaration] {
        var decls: [Declaration] = []

        while current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
            // Expect property name
            if current.Kind == TokenKind.ident {
                let prop = current.Value
                advance()

                if current.Kind == TokenKind.colon {
                    advance() // skip ':'

                    var tokens: [Token] = []
                    var important = false
                    var depth = 0

                    while current.Kind != TokenKind.eof {
                        if depth == 0 && (current.Kind == TokenKind.semicolon || current.Kind == TokenKind.closeBrace) {
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

    func skipToNextDeclaration() {
        while current.Kind != TokenKind.semicolon && current.Kind != TokenKind.closeBrace && current.Kind != TokenKind.eof {
            advance()
        }
        if current.Kind == TokenKind.semicolon {
            advance()
        }
    }
}
