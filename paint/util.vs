package paint

import "image/draw"

func roundf(_ v: float32) -> float32 {
    return float32(draw.RoundToInt(v))
}

@_silgen_name("ceilf")
func c_ceilf(_ x: float32) -> float32

func clampf(_ v: float32, _ lo: float32, _ hi: float32) -> float32 {
    if v < lo { return lo }
    if v > hi { return hi }
    return v
}

@_silgen_name("vertex_string_from_utf8")
func stringFromUtf8(_ ptr: UnsafeRawPointer, _ count: int64) -> string

/// The string bytes[start..<end] spell.
func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return bytes.withUnsafeBytes { bp in
        stringFromUtf8(bp.baseAddress! + start, int64(end - start))
    }
}

func minf(_ a: float32, _ b: float32) -> float32 { return a < b ? a : b }
func maxf(_ a: float32, _ b: float32) -> float32 { return a > b ? a : b }
