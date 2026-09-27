// Inline SVG checked: sizes, and shapes drawn pixel by pixel.
package main

import (
    "image/draw"
    "web/html"
    "web/svg"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func svgNode(_ source: string) -> html.Node {
    let doc = html.Parse("<body>" + source + "</body>")
    return doc.ElementsByTagName("svg")[0]
}

/// The drawing rendered into a size-by-size canvas at its origin, in the
/// current color given, with an optional CSS fill.
func render(_ source: string, size: int32 = 20, fill: draw.Color? = nil, fillNone: bool = false) -> [uint8] {
    let d = svg.Parse(svgNode(source))
    var pixels = [uint8](repeating: 0, count: int(size * size * 4))
    draw.WithCanvas(&pixels, width: size, height: size) { c in
        d.Render(on: c, into: draw.Rect(0, 0, float32(size), float32(size)), scale: 1,
                 currentColor: draw.Color(0, 128, 0), fill: fill, fillNone: fillNone)
    }
    return pixels
}

func at(_ p: [uint8], _ x: int32, _ y: int32, size: int32 = 20) -> (r: uint8, g: uint8, b: uint8, a: uint8) {
    let i = int((y * size + x) * 4)
    return (r: p[i], g: p[i + 1], b: p[i + 2], a: p[i + 3])
}

func main() -> int32 {
    print("Sizes")
    var s = svg.IntrinsicSize(svgNode("<svg width=32 height=16></svg>"))
    check(s.width == 32 && s.height == 16, "width and height attributes")
    s = svg.IntrinsicSize(svgNode("<svg viewBox='0 0 24 12' width=48></svg>"))
    check(s.width == 48 && s.height == 24, "one attribute and the viewBox's proportions")
    s = svg.IntrinsicSize(svgNode("<svg viewBox='0 0 2 1'></svg>"))
    check(s.width == 300 && s.height == 150, "no size: 300 wide, shaped by the viewBox")
    s = svg.IntrinsicSize(svgNode("<svg width='100%'></svg>"))
    check(s.width == 300 && s.height == 150, "a percentage is no intrinsic size")

    print("Shapes")
    var p = render("<svg><rect x=2 y=2 width=10 height=10 fill=red /></svg>")
    check(at(p, 5, 5).r == 255 && at(p, 5, 5).a == 255 && at(p, 15, 15).a == 0, "a rect in its color")
    p = render("<svg viewBox='0 0 1 1'><path d='M0 0h1v1H0z' fill='#00f'/></svg>")
    check(at(p, 1, 1).b == 255 && at(p, 18, 18).b == 255, "the viewBox scales user units to the box")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 10a10 10 0 1 0 20 0a10 10 0 1 0 -20 0z'/></svg>")
    check(at(p, 10, 10).a == 255 && at(p, 1, 1).a == 0 && at(p, 10, 1).a > 0, "arcs make a circle")
    p = render("<svg viewBox='0 0 20 20'><circle cx=10 cy=10 r=9 /></svg>")
    check(at(p, 10, 10).a == 255 && at(p, 0, 0).a == 0, "a circle, black by default")
    p = render("<svg viewBox='0 0 20 20'><path fill-rule=evenodd d='M0 0H20V20H0ZM5 5H15V15H5Z'/></svg>")
    check(at(p, 10, 10).a == 0 && at(p, 2, 2).a == 255, "fill-rule evenodd cuts a hole")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 0H20V20H0ZM5 5H15V15H5Z'/></svg>")
    check(at(p, 10, 10).a == 255, "nonzero fills over it")
    p = render("<svg viewBox='0 0 20 20'><g transform='translate(10 0) scale(0.5)'><rect width=20 height=20 fill=red /></g></svg>")
    check(at(p, 12, 2).r == 255 && at(p, 2, 2).a == 0 && at(p, 12, 12).a == 0, "a group's transforms, in order")
    p = render("<svg viewBox='0 0 20 20'><path d='M2 2L18 2L18 18L2 18Z' fill=none /></svg>")
    check(at(p, 10, 10).a == 0, "fill=none draws nothing")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 0H20V20H0Z' fill=currentColor /></svg>")
    check(at(p, 10, 10).g == 128 && at(p, 10, 10).r == 0, "currentColor is the element's color")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 0H20V20H0Z' /></svg>", fill: draw.Color(255, 0, 0))
    check(at(p, 10, 10).r == 255, "the svg's CSS fill reaches shapes that set none")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 0H20V20H0Z' fill=blue /></svg>", fill: draw.Color(255, 0, 0))
    check(at(p, 10, 10).b == 255, "but not shapes that set their own")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 0H20V20H0Z' /></svg>", fillNone: true)
    check(at(p, 10, 10).a == 0, "CSS fill: none hides them")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 0H20V20H0Z' style='fill: #f00; opacity: .5' /></svg>")
    check(at(p, 10, 10).a > 120 && at(p, 10, 10).a < 135, "style attribute: fill and opacity (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><path d='M0.5.5H10V10H.5z' /></svg>")
    check(at(p, 5, 5).a == 255, "numbers that run together: 0.5.5")
    p = render("<svg viewBox='0 0 20 20'><path d='M0 0C0 0 20 0 20 20S0 20 0 20z' /></svg>")
    check(at(p, 10, 10).a == 255 && at(p, 19, 1).a == 0, "cubic and smooth cubic")
    p = render("<svg viewBox='0 0 20 20'><polygon points='0,0 20,0 20,20' /></svg>")
    check(at(p, 18, 2).a == 255 && at(p, 2, 18).a == 0, "a polygon")
    p = render("<svg viewBox='0 0 20 20'><defs><linearGradient id=g><stop stop-color='#f00'/></linearGradient></defs><rect width=20 height=20 fill='url(#g)'/></svg>")
    check(at(p, 10, 10).r == 255, "a gradient fill is its first stop, for now")
    p = render("<svg viewBox='0 0 40 20'><rect width=40 height=20 /></svg>")
    check(at(p, 10, 3).a == 0 && at(p, 10, 10).a == 255, "a wide viewBox is centered in a square box")

    if failures == 0 {
        print("ALL SVG CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
