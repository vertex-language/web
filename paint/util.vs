package paint

import (
    "math"
    "image/draw"
    "unicode/utf8"
)

func roundf(v: float32) -> float32 {
    return float32(math.RoundToInt(v))
}

// paint.vs calls these by their old names; they are math's now. (Its
// call sites can use math directly once the work in flight there lands.)
func c_ceilf(x: float32) -> float32 { return math.Ceil(x) }

func clampf(v: float32, lo: float32, hi: float32) -> float32 { return math.Clamp(v, lo, hi) }

/// The string bytes[start..<end] spell.
func stringOf(bytes: [uint8], start: int, end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}

func minf(a: float32, b: float32) -> float32 { return math.Min(a, b) }
func maxf(a: float32, b: float32) -> float32 { return math.Max(a, b) }
