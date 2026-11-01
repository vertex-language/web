package css

import "math"

/// One function of a transform list as parsed: its name, lowercased,
/// and its arguments -- lengths as lengths, angles as `.number` in
/// radians, and plain numbers and percentages (for scale) as `.number`.
public struct TransformFunction {
    public var Name: string
    public var Args: [Value]

    public init(_ name: string, _ args: [Value]) {
        Name = name
        Args = args
    }
}

/// `transform`: none, or a list of transform functions. The 3D ones are
/// read in their 2D projection: z is dropped, rotateX/Y and perspective
/// are taken as nothing.
func parseTransformList(_ tokens: [Token]) -> Value? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return Value.none }
    var out: [TransformFunction] = []
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind != .function { return nil }
        let end = closeParen(tokens, from: i + 1)
        if end >= tokens.count { return nil }
        let args = splitArgs(tokens, i + 1, end)
        guard let f = transformFunction(lower(t.Value), args) else { return nil }
        if !f.Name.isEmpty { out.append(f) }
        i = end + 1
    }
    if out.isEmpty { return nil }
    return .transforms(out)
}

/// The tokens between start and end split at top-level commas.
func splitArgs(_ tokens: [Token], _ start: int, _ end: int) -> [[Token]] {
    var out: [[Token]] = []
    var cur: [Token] = []
    var depth = 0
    var i = start
    while i < end {
        let t = tokens[i]
        if t.Kind == .function || t.Kind == .openParen { depth += 1 }
        if t.Kind == .closeParen { depth -= 1 }
        if depth == 0 && t.Kind == .comma {
            out.append(cur)
            cur = []
        } else {
            cur.append(t)
        }
        i += 1
    }
    if !cur.isEmpty || !out.isEmpty { out.append(cur) }
    return out
}

/// A length argument: a length, a percentage, 0, or calc().
func transformLength(_ arg: [Token]) -> Value? {
    if arg.isEmpty { return nil }
    if arg.count == 1 { return parseLengthValue(arg[0], allowAuto: false) }
    return calcValue(arg)
}

/// An angle argument, in radians; a bare 0 is allowed.
func transformAngle(_ arg: [Token]) -> float32? {
    if arg.count != 1 { return nil }
    let t = arg[0]
    if t.Kind == .number && t.NumberVal == 0 { return 0 }
    if t.Kind != .dimension { return nil }
    return angleRadians(t.NumberVal, lower(t.Unit))
}

func angleRadians(_ v: float32, _ unit: string) -> float32? {
    switch unit {
    case "deg": return v * float32(math.Pi) / 180
    case "rad": return v
    case "grad": return v * float32(math.Pi) / 200
    case "turn": return v * 2 * float32(math.Pi)
    default: return nil
    }
}

/// A scale argument: a number, or a percentage of one.
func transformNumber(_ arg: [Token]) -> float32? {
    if arg.count != 1 { return nil }
    if arg[0].Kind == .number { return arg[0].NumberVal }
    if arg[0].Kind == .percentage { return arg[0].NumberVal / 100 }
    return nil
}

/// A transform function in its 2D form: translate(x, y), scale(x, y),
/// rotate(a), skew(x, y) or matrix(a..f). An empty name is one that
/// does nothing in 2D; nil is one that is not valid.
func transformFunction(_ name: string, _ args: [[Token]]) -> TransformFunction? {
    let zero = Value.length(0, .px)
    switch name {
    case "translate", "translatex", "translatey", "translate3d", "translatez":
        var x = zero
        var y = zero
        switch name {
        case "translate":
            if args.count < 1 || args.count > 2 { return nil }
            guard let a = transformLength(args[0]) else { return nil }
            x = a
            if args.count == 2 { guard let b = transformLength(args[1]) else { return nil }; y = b }
        case "translatex":
            if args.count != 1 { return nil }
            guard let a = transformLength(args[0]) else { return nil }
            x = a
        case "translatey":
            if args.count != 1 { return nil }
            guard let a = transformLength(args[0]) else { return nil }
            y = a
        case "translate3d":
            if args.count != 3 { return nil }
            guard let a = transformLength(args[0]), let b = transformLength(args[1]) else { return nil }
            x = a
            y = b
        default:
            return TransformFunction("", [])
        }
        return TransformFunction("translate", [x, y])
    case "scale", "scalex", "scaley", "scale3d", "scalez":
        var nums: [float32] = []
        for a in args {
            guard let n = transformNumber(a) else { return nil }
            nums.append(n)
        }
        switch name {
        case "scale":
            if nums.count < 1 || nums.count > 2 { return nil }
            return TransformFunction("scale", [.number(nums[0]), .number(nums.count == 2 ? nums[1] : nums[0])])
        case "scalex":
            if nums.count != 1 { return nil }
            return TransformFunction("scale", [.number(nums[0]), .number(1)])
        case "scaley":
            if nums.count != 1 { return nil }
            return TransformFunction("scale", [.number(1), .number(nums[0])])
        case "scale3d":
            if nums.count != 3 { return nil }
            return TransformFunction("scale", [.number(nums[0]), .number(nums[1])])
        default:
            return nums.count == 1 ? TransformFunction("", []) : nil
        }
    case "rotate", "rotatez":
        if args.count != 1 { return nil }
        guard let a = transformAngle(args[0]) else { return nil }
        return TransformFunction("rotate", [.number(a)])
    case "rotate3d":
        // Only a turn about z shows in 2D.
        if args.count != 4 { return nil }
        guard let x = transformNumber(args[0]), let y = transformNumber(args[1]), let z = transformNumber(args[2]),
              let a = transformAngle(args[3]) else { return nil }
        if x == 0 && y == 0 && z != 0 { return TransformFunction("rotate", [.number(z > 0 ? a : -a)]) }
        return TransformFunction("", [])
    case "rotatex", "rotatey", "perspective":
        if args.count != 1 { return nil }
        return TransformFunction("", [])
    case "skew", "skewx", "skewy":
        var angles: [float32] = []
        for a in args {
            guard let n = transformAngle(a) else { return nil }
            angles.append(n)
        }
        if name == "skew" {
            if angles.count < 1 || angles.count > 2 { return nil }
            return TransformFunction("skew", [.number(angles[0]), .number(angles.count == 2 ? angles[1] : 0)])
        }
        if angles.count != 1 { return nil }
        return TransformFunction("skew", name == "skewx" ? [.number(angles[0]), .number(0)] : [.number(0), .number(angles[0])])
    case "matrix", "matrix3d":
        var nums: [float32] = []
        for a in args {
            guard a.count == 1, a[0].Kind == .number else { return nil }
            nums.append(a[0].NumberVal)
        }
        if name == "matrix" {
            if nums.count != 6 { return nil }
            return TransformFunction("matrix", nums.map { Value.number($0) })
        }
        if nums.count != 16 { return nil }
        // Column-major: the 2D part is m11 m12 m21 m22 m41 m42.
        return TransformFunction("matrix", [nums[0], nums[1], nums[4], nums[5], nums[12], nums[13]].map { Value.number($0) })
    default:
        return nil
    }
}

/// The `translate` property: none, or x [y [z]].
func parseTranslateProperty(_ tokens: [Token]) -> Value? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return Value.none }
    let parts = spaceArgs(tokens)
    if parts.isEmpty || parts.count > 3 { return nil }
    guard let x = transformLength(parts[0]) else { return nil }
    var y = Value.length(0, .px)
    if parts.count >= 2 { guard let v = transformLength(parts[1]) else { return nil }; y = v }
    return .transforms([TransformFunction("translate", [x, y])])
}

/// The `rotate` property: none, an angle, or an axis and an angle (of
/// which only z shows in 2D).
func parseRotateProperty(_ tokens: [Token]) -> Value? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return Value.none }
    var angle: float32? = nil
    var aboutZ = true
    for t in tokens {
        if let a = transformAngle([t]), t.Kind == .dimension { angle = a; continue }
        if t.Kind == .ident {
            let k = lower(t.Value)
            if k == "x" || k == "y" { aboutZ = false; continue }
            if k == "z" { continue }
        }
        if t.Kind == .number { if t.NumberVal != 0 { aboutZ = false }; continue }
        return nil
    }
    guard let a = angle else { return nil }
    return .transforms(aboutZ ? [TransformFunction("rotate", [.number(a)])] : [])
}

/// The `scale` property: none, or x [y [z]] as numbers or percentages.
func parseScaleProperty(_ tokens: [Token]) -> Value? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return Value.none }
    var nums: [float32] = []
    for t in tokens {
        guard let n = transformNumber([t]) else { return nil }
        nums.append(n)
    }
    if nums.isEmpty || nums.count > 3 { return nil }
    return .transforms([TransformFunction("scale", [.number(nums[0]), .number(nums.count >= 2 ? nums[1] : nums[0])])])
}

/// `transform-origin`: x and y as lengths, percentages or keywords,
/// in either order where keywords say which is which; z is dropped.
/// Kept as an "origin" function of the two.
func parseTransformOrigin(_ tokens: [Token]) -> Value? {
    var x: Value? = nil
    var y: Value? = nil
    var pending: [Value] = []
    let half = Value.length(50, .percent)
    for t in tokens {
        if t.Kind == .ident {
            switch lower(t.Value) {
            case "left": x = .length(0, .percent)
            case "right": x = .length(100, .percent)
            case "top": y = .length(0, .percent)
            case "bottom": y = .length(100, .percent)
            case "center": pending.append(half)
            default: return nil
            }
            continue
        }
        guard let v = parseLengthValue(t, allowAuto: false) else { return nil }
        pending.append(v)
    }
    // Lengths and centers fill x then y, whichever a keyword left open.
    for v in pending {
        if x == nil { x = v } else if y == nil { y = v }
    }
    if tokens.isEmpty || tokens.count > 3 { return nil }
    return .transforms([TransformFunction("origin", [x ?? half, y ?? half])])
}

/// Tokens split into space-separated arguments, calc() kept whole.
func spaceArgs(_ tokens: [Token]) -> [[Token]] {
    var out: [[Token]] = []
    var i = 0
    while i < tokens.count {
        if tokens[i].Kind == .function {
            let end = closeParen(tokens, from: i + 1)
            if end >= tokens.count { return [] }
            out.append(Array(tokens[i...end]))
            i = end + 1
        } else {
            out.append([tokens[i]])
            i += 1
        }
    }
    return out
}
