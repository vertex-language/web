package selector

import (
    "web/css"
    "web/html"
)

/// Checks if an element node matches a given selector string (can be comma-separated).
public func Matches(_ selectorString: string, _ node: html.Node) -> bool {
    let complexes = ParseSelectors(selectorString)
    var i = 0
    while i < complexes.count {
        if MatchComplex(complexes[i], node) {
            return true
        }
        i += 1
    }
    return false
}

/// Finds the first descendant element matching the selector string.
public func QuerySelector(_ selectorString: string, in root: html.Node) -> html.Node? {
    let complexes = ParseSelectors(selectorString)
    if complexes.isEmpty { return nil }
    return queryFirst(root, complexes)
}

/// Finds all descendant elements matching the selector string.
public func QuerySelectorAll(_ selectorString: string, in root: html.Node) -> [html.Node] {
    let complexes = ParseSelectors(selectorString)
    if complexes.isEmpty { return [] }
    var results: [html.Node] = []
    queryAll(root, complexes, &results)
    return results
}

func queryFirst(_ node: html.Node, _ selectors: [ComplexSelector]) -> html.Node? {
    if node.Kind == html.NodeKind.element {
        var i = 0
        while i < selectors.count {
            if MatchComplex(selectors[i], node) {
                return node
            }
            i += 1
        }
    }
    var j = 0
    while j < node.Children.count {
        if let match = queryFirst(node.Children[j], selectors) {
            return match
        }
        j += 1
    }
    return nil
}

func queryAll(_ node: html.Node, _ selectors: [ComplexSelector], _ out: inout [html.Node]) {
    if node.Kind == html.NodeKind.element {
        var i = 0
        while i < selectors.count {
            if MatchComplex(selectors[i], node) {
                out.append(node)
                break
            }
            i += 1
        }
    }
    var j = 0
    while j < node.Children.count {
        queryAll(node.Children[j], selectors, &out)
        j += 1
    }
}
