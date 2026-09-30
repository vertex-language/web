// Prints the property names the engine applies and those it knows but
// does not apply yet, as JSON, for vsc to embed (vsc/vss/properties.go).
//
//     vsc run css-names > ../vsc/vss/properties.json
package main

import "web/css"

func list(_ names: [string]) -> string {
    return "[" + names.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
}

func main() -> int32 {
    print("{\"applied\": \(list(css.AppliedPropertyNames())), \"unapplied\": \(list(css.UnappliedPropertyNames()))}")
    return 0
}
