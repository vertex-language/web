package css

/// A CSS length as the cascade leaves it: resolved to pixels where the
/// unit allowed, a percentage where only layout can resolve it, or a
/// keyword.
public enum Length: Equatable {
    case auto
    case none
    case px(float32)
    case percent(float32)
    /// calc(): so many pixels plus so much of the base.
    case calc(float32, float32)
    case minContent
    case maxContent
    case fitContent

    public var IsAuto: bool { return self == .auto }
    public var IsNone: bool { return self == .none }

    /// The length in pixels against a base for percentages; nil where it
    /// is a keyword.
    public func Resolve(_ base: float32) -> float32? {
        switch self {
        case .px(let v): return v
        case .percent(let p): return base * p / 100
        case .calc(let v, let p): return v + base * p / 100
        default: return nil
        }
    }

    /// The length in pixels, or a fallback where it is a keyword.
    public func Or(_ fallback: float32, base: float32) -> float32 {
        return Resolve(base) ?? fallback
    }

    /// The length in pixels where it needs no base, or nil.
    public var Pixels: float32? {
        if case .px(let v) = self { return v }
        return nil
    }
}

/// One track of a grid: a fixed length, a share of the free space, or
/// what its items need.
public enum GridTrack: Equatable {
    case length(Length)
    case fr(float32)
    case auto
    /// minmax(min, max): the minimum in pixels, the maximum in pixels
    /// (0 for none), and the maximum's fr where a share (0 for none).
    case minmax(float32, float32, float32)
}

/// Where a grid item is put: a line, a span, or automatic.
public struct GridPlacement: Equatable {
    /// 1-based start line, 0 for auto.
    public var Start: int32
    /// Lines spanned.
    public var Span: int32

    public init(start: int32 = 0, span: int32 = 1) {
        Start = start
        Span = span
    }

    public static let auto = GridPlacement(start: 0, span: 1)
}
