package paint

import (
    "math"
    "image/draw"
    "unicode/utf8"
)

func roundf(_ v: float32) -> float32 {
    return float32(math.RoundToInt(v))
}

// paint.vs calls these by their old names; they are math's now. (Its
// call sites can use math directly once the work in flight there lands.)
func c_ceilf(_ x: float32) -> float32 { return math.Ceil(x) }

func clampf(_ v: float32, _ lo: float32, _ hi: float32) -> float32 { return math.Clamp(v, lo, hi) }

/// The string bytes[start..<end] spell.
func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}

func minf(_ a: float32, _ b: float32) -> float32 { return math.Min(a, b) }
func maxf(_ a: float32, _ b: float32) -> float32 { return math.Max(a, b) }
