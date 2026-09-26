// Times the engine on a page: the first render, a relayout, a repaint,
// and the pointer moving across the page.
//
//     vsc run bench -- page.html [width] [height]
package main

import (
    "time"
    "image/draw"
    "web"
)

/// A decimal argument, or the fallback when it is missing or not positive.
func number(_ s: string, _ fallback: float32) -> float32 {
    var value: float32 = 0
    var scale: float32 = 0
    var any = false
    for c in s.utf8 {
        if c >= 48 && c <= 57 {
            any = true
            if scale == 0 {
                value = value * 10 + float32(c - 48)
            } else {
                value += float32(c - 48) * scale
                scale /= 10
            }
        } else if c == 46 && scale == 0 {
            scale = 0.1
        } else {
            break
        }
    }
    return any && value > 0 ? value : fallback
}

func ms(_ d: time.Duration) -> string {
    let us = d.AsMicroseconds()
    return "\(us / 1000).\((us % 1000) / 100) ms"
}

@MainActor
func main() -> int32 {
    let args = CommandLine.arguments
    if args.count < 2 {
        print("usage: bench page.html [width] [height]")
        return 2
    }
    let width = number(args.count > 2 ? args[2] : "", 900)
    let height = number(args.count > 3 ? args[3] : "", 700)
    let scale: float32 = 2
    let pw = int32(width * scale)
    let ph = int32(height * scale)
    var pixels = [uint8](repeating: 0, count: int(pw) * int(ph) * 4)

    let page = web.Page()
    page.SetViewportSize(draw.Size(width, height))
    var t = time.Instant.Now()
    do {
        try page.LoadFile(args[1])
    } catch {
        print("cannot read \(args[1])")
        return 1
    }
    print("load (parse + sheets): \(ms(t.Elapsed()))")

    t = time.Instant.Now()
    page.Draw(into: &pixels, width: pw, height: ph, scale: scale)
    print("first frame (style, layout, paint, raster): \(ms(t.Elapsed()))")

    page.SetViewportSize(draw.Size(width - 1, height))
    t = time.Instant.Now()
    page.Draw(into: &pixels, width: pw, height: ph, scale: scale)
    print("resize (layout, paint, raster): \(ms(t.Elapsed()))")

    page.SetScrollOffset(draw.Point(0, 100))
    t = time.Instant.Now()
    page.Draw(into: &pixels, width: pw, height: ph, scale: scale)
    print("scroll (raster): \(ms(t.Elapsed()))")

    page.Invalidate()
    t = time.Instant.Now()
    page.Draw(into: &pixels, width: pw, height: ph, scale: scale)
    print("invalidate (style, layout, paint, raster): \(ms(t.Elapsed()))")

    // The pointer sweeps the page in a grid; each stop may restyle.
    var restyles = 0
    var frames = 0
    t = time.Instant.Now()
    var y: float32 = 5
    while y < height {
        var x: float32 = 5
        while x < width {
            _ = page.Handle(.pointerMoved(draw.Point(x, y)))
            if page.NeedsRepaint() {
                frames += 1
                page.Draw(into: &pixels, width: pw, height: ph, scale: scale)
            }
            x += 25
        }
        y += 25
    }
    _ = restyles
    let sweep = t.Elapsed()
    let stops = int(width / 25) * int(height / 25)
    print("pointer sweep: \(stops) stops, \(frames) frames, \(ms(sweep)) total, \(sweep.AsMicroseconds() / int64(stops)) us per stop")
    return 0
}
