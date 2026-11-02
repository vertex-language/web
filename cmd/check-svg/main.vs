// Inline SVG checked: sizes, and shapes drawn pixel by pixel.
package main

import (
    "image/draw"
    "web/html"
    "web/svg"
)

var failures = 0

func check(ok: bool, what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func svgNode(source: string) -> html.Node {
    let doc = html.Parse("<body>" + source + "</body>")
    return doc.ElementsByTagName("svg")[0]
}

/// The drawing rendered into a size-by-size canvas at its origin, in the
/// current color given, with an optional CSS fill.
func render(source: string, size: int32 = 20, fill: draw.Color? = nil, fillNone: bool = false) -> [uint8] {
    let d = svg.Parse(svgNode(source))
    var pixels = [uint8](repeating: 0, count: int(size * size * 4))
    draw.WithCanvas(&pixels, width: size, height: size) { c in
        d.Render(on: c, into: draw.Rect(0, 0, float32(size), float32(size)), scale: 1,
                 currentColor: draw.Color(0, 128, 0), fill: fill, fillNone: fillNone)
    }
    return pixels
}

func at(p: [uint8], x: int32, y: int32, size: int32 = 20) -> (r: uint8, g: uint8, b: uint8, a: uint8) {
    let i = int((y * size + x) * 4)
    return (r: p[i], g: p[i + 1], b: p[i + 2], a: p[i + 3])
}

func main() -> int32 {
    print("Strokes")
    // Lucide's form: the stroke on the <svg>, fill none, round ends.
    let lucide = "<svg viewBox='0 0 20 20' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M4 10h12'/><line x1='10' y1='4' x2='10' y2='16'/><circle cx='10' cy='10' r='8'/></svg>"
    var sp = render(lucide)
    check(at(sp, 6, 10).g > 100 && at(sp, 6, 10).r == 0, "a stroked path draws in the current color")
    check(at(sp, 10, 6).a > 200, "so does a <line>")
    check(at(sp, 18, 10).a > 200 && at(sp, 13, 13).a == 0, "a circle's stroke is a ring, not a disc")
    check(at(sp, 3, 10).a > 120, "round caps reach past the path's end")
    sp = render("<svg viewBox='0 0 20 20'><polyline points='2,2 18,2 18,18' fill='none' stroke='#f00' stroke-width='2'/></svg>")
    check(at(sp, 10, 2).r > 200 && at(sp, 10, 10).a == 0, "a polyline's stroke stays open")
    sp = render("<svg viewBox='0 0 20 20'><rect x='4' y='4' width='12' height='12' fill='#00f' stroke='#f00' stroke-width='2' stroke-opacity='0.5'/></svg>")
    check(at(sp, 10, 10).b > 200 && at(sp, 4, 10).r > 100 && at(sp, 4, 10).r < 200, "fill and a half-opaque stroke over it")

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
    check(at(p, 10, 10).r == 255, "a gradient of one stop is that stop's color")
    p = render("<svg viewBox='0 0 20 20'><defs><linearGradient id=g><stop offset=0 stop-color='#f00'/><stop offset=1 stop-color='#00f'/></linearGradient></defs><rect width=20 height=20 fill='url(#g)'/></svg>")
    check(at(p, 1, 10).r > 220 && at(p, 18, 10).b > 220 && at(p, 10, 10).r > 90 && at(p, 10, 10).r < 160, "a linear gradient runs across the shape (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><defs><linearGradient id=g gradientUnits=userSpaceOnUse x1=0 y1=0 x2=0 y2=20><stop offset=0 stop-color='#000'/><stop offset=1 stop-color='#fff' stop-opacity=0 /></linearGradient></defs><rect width=20 height=20 fill='url(#g)'/></svg>")
    check(at(p, 10, 1).a > 220 && at(p, 10, 18).a < 40, "user space units, down the box, and stop-opacity (\(at(p, 10, 1)) \(at(p, 10, 18)))")
    p = render("<svg viewBox='0 0 20 20'><defs><radialGradient id=g><stop offset=0 stop-color='#f00'/><stop offset=1 stop-color='#00f'/></radialGradient></defs><rect width=20 height=20 fill='url(#g)'/></svg>")
    check(at(p, 10, 10).r > 220 && at(p, 1, 10).b > 200, "a radial gradient from its centre (\(at(p, 10, 10)) \(at(p, 1, 10)))")
    p = render("<svg viewBox='0 0 20 20'><defs><linearGradient id=a><stop offset=0 stop-color='#0f0'/></linearGradient><linearGradient id=b xlink:href='#a'/></defs><rect width=20 height=20 fill='url(#b)'/></svg>")
    check(at(p, 10, 10).g == 255, "a gradient takes its stops from what it links to")
    print("Use, clips and masks")
    p = render("<svg viewBox='0 0 20 20'><defs><rect id=r width=5 height=5 /></defs><use href='#r' x=10 y=10 fill='#f00'/></svg>")
    check(at(p, 12, 12).r == 255 && at(p, 2, 2).a == 0, "<use> draws what it names, moved, with its own fill")
    p = render("<svg viewBox='0 0 20 20'><symbol id=s viewBox='0 0 1 1'><rect width=1 height=1 fill='#00f'/></symbol><use href='#s' width=10 height=10 /></svg>")
    check(at(p, 8, 8).b == 255 && at(p, 12, 12).a == 0, "<use> of a <symbol> fits its viewBox to the size")
    p = render("<svg viewBox='0 0 20 20'><g id=a><use href='#a'/><rect width=4 height=4 /></g></svg>")
    check(at(p, 2, 2).a == 255, "a <use> of its own ancestor stops")
    p = render("<svg viewBox='0 0 20 20'><clipPath id=c><circle cx=10 cy=10 r=5 /></clipPath><rect width=20 height=20 fill='#f00' clip-path='url(#c)'/></svg>")
    check(at(p, 10, 10).r == 255 && at(p, 1, 1).a == 0, "clip-path by url() keeps the circle")
    p = render("<svg viewBox='0 0 20 20'><clipPath id=c clipPathUnits=objectBoundingBox><rect width=.5 height=1 /></clipPath><rect x=10 width=10 height=20 fill='#f00' clip-path='url(#c)'/></svg>")
    check(at(p, 12, 10).r == 255 && at(p, 17, 10).a == 0, "objectBoundingBox clip units")
    p = render("<svg viewBox='0 0 20 20'><mask id=m><rect width=10 height=20 fill=white /></mask><g mask='url(#m)'><rect width=20 height=20 fill='#00f'/></g></svg>")
    check(at(p, 5, 10).b == 255 && at(p, 15, 10).a == 0, "a mask keeps what is bright in it")
    p = render("<svg viewBox='0 0 20 20'><rect x=5 y=5 width=10 height=10 fill='#00f' stroke='#f00' stroke-width=4 paint-order=stroke /></svg>")
    check(at(p, 6, 10).b == 255 && at(p, 6, 10).r == 0, "paint-order: stroke puts the fill over the stroke (\(at(p, 6, 10)))")
    p = render("<svg viewBox='0 0 20 20'><line x1=0 y1=10 x2=20 y2=10 stroke='#f00' stroke-width=4 stroke-dasharray='5 5'/></svg>")
    check(at(p, 2, 10).r == 255 && at(p, 7, 10).a == 0 && at(p, 12, 10).r == 255, "stroke-dasharray leaves gaps (\(at(p, 2, 10)) \(at(p, 7, 10)))")
    p = render("<svg viewBox='0 0 20 20'><line x1=0 y1=10 x2=20 y2=10 stroke='#f00' stroke-width=4 stroke-dasharray='5 5' stroke-dashoffset=5 /></svg>")
    check(at(p, 2, 10).a == 0 && at(p, 7, 10).r == 255, "stroke-dashoffset moves them")
    p = render("<svg viewBox='0 0 20 20'><pattern id=pt width=10 height=10 patternUnits=userSpaceOnUse><rect width=5 height=10 fill='#00f'/></pattern><rect width=20 height=20 fill='url(#pt)'/></svg>")
    check(at(p, 2, 5).b == 255 && at(p, 7, 5).a == 0 && at(p, 12, 5).b == 255, "a <pattern> tiles across the shape (\(at(p, 2, 5)) \(at(p, 7, 5)) \(at(p, 12, 5)))")
    p = render("<svg viewBox='0 0 20 20'><marker id=mk markerWidth=4 markerHeight=4 refX=2 refY=2 markerUnits=userSpaceOnUse><rect width=4 height=4 fill='#f00'/></marker><line x1=2 y1=10 x2=18 y2=10 stroke='#00f' stroke-width=2 marker-start='url(#mk)' marker-end='url(#mk)'/></svg>")
    check(at(p, 2, 9).r == 255 && at(p, 18, 9).r == 255 && at(p, 10, 10).b == 255, "markers at a line's ends (\(at(p, 2, 9)) \(at(p, 18, 9)) \(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><marker id=ar markerWidth=4 markerHeight=2 refX=0 refY=1 orient=auto markerUnits=userSpaceOnUse><rect width=4 height=2 fill='#f00'/></marker><line x1=10 y1=2 x2=10 y2=10 stroke='#00f' marker-end='url(#ar)'/></svg>")
    check(at(p, 10, 12).r == 255 && at(p, 13, 10).r != 255, "orient=auto turns a marker along the path (\(at(p, 10, 12)) \(at(p, 13, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=off filterUnits=userSpaceOnUse x=0 y=0 width=20 height=20><feOffset dx=10 dy=0 /></filter><rect width=5 height=20 fill='#f00' filter='url(#off)'/></svg>")
    check(at(p, 12, 10).r == 255 && at(p, 2, 10).a == 0, "feOffset moves a shape (\(at(p, 12, 10)) \(at(p, 2, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=gr><feColorMatrix type=saturate values=0 /></filter><rect width=20 height=20 fill='#f00' filter='url(#gr)'/></svg>")
    check(at(p, 10, 10).r == at(p, 10, 10).g, "feColorMatrix saturate (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=bl x='-50%' y='-50%' width='200%' height='200%'><feGaussianBlur stdDeviation=2 /></filter><rect x=5 y=5 width=10 height=10 fill='#000' filter='url(#bl)'/></svg>")
    check(at(p, 3, 10).a > 0 && at(p, 10, 10).a > 200, "feGaussianBlur (\(at(p, 3, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=rg><feOffset dx=10 /></filter><rect width=5 height=20 fill='#f00' filter='url(#rg)'/></svg>")
    check(at(p, 12, 10).a == 0, "a filter's region cuts what it moves (\(at(p, 12, 10)))")
    let whole = "filterUnits=userSpaceOnUse x=0 y=0 width=20 height=20 color-interpolation-filters=sRGB"
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feFlood flood-color='#00f' result=back /><feComposite in=SourceGraphic in2=back operator=over /></filter><rect x=5 y=5 width=10 height=10 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 10, 10).r == 255 && at(p, 1, 1).b == 255 && at(p, 1, 1).r == 0, "feFlood and feComposite by name (\(at(p, 10, 10)) \(at(p, 1, 1)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feFlood flood-color='#00f' /><feComposite in2=SourceAlpha operator=in /></filter><rect x=5 y=5 width=10 height=10 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 10, 10).b == 255 && at(p, 1, 1).a == 0, "operator=in cuts the flood to the shape (\(at(p, 10, 10)) \(at(p, 1, 1)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feOffset in=SourceGraphic dx=5 result=a /><feOffset in=SourceGraphic dx=-5 result=b /><feMerge><feMergeNode in=a /><feMergeNode in=b /></feMerge></filter><rect x=8 y=0 width=4 height=20 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 14, 10).r == 255 && at(p, 5, 10).r == 255 && at(p, 10, 10).a == 0, "feMerge of two results (\(at(p, 14, 10)) \(at(p, 5, 10)) \(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feFlood flood-color='#ff0000' result=top /><feFlood flood-color='#00ff00' result=bottom /><feBlend in=top in2=bottom mode=screen /></filter><rect width=20 height=20 filter='url(#f)'/></svg>")
    check(at(p, 10, 10).r == 255 && at(p, 10, 10).g == 255, "feBlend of two results (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feComponentTransfer><feFuncR type=linear slope=0 intercept=1 /><feFuncB type=discrete tableValues='0 1' /></feComponentTransfer></filter><rect width=20 height=20 fill='#00f' filter='url(#f)'/></svg>")
    check(at(p, 10, 10).r == 255 && at(p, 10, 10).b == 255, "feComponentTransfer (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feMorphology operator=dilate radius=3 /></filter><rect x=8 y=8 width=4 height=4 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 6, 10).r == 255 && at(p, 3, 10).a == 0, "feMorphology dilates (\(at(p, 6, 10)) \(at(p, 3, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feOffset in=SourceGraphic x=0 y=0 width=10 height=20 /><feTile /></filter><rect width=5 height=20 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 12, 10).r == 255 && at(p, 7, 10).a == 0, "feTile repeats a subregion (\(at(p, 12, 10)) \(at(p, 7, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feTurbulence type=fractalNoise baseFrequency=0.3 numOctaves=2 seed=4 /></filter><rect width=20 height=20 filter='url(#f)'/></svg>")
    check(at(p, 3, 3) != at(p, 15, 12) && at(p, 3, 3).a > 0, "feTurbulence makes noise (\(at(p, 3, 3)) \(at(p, 15, 12)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feFlood flood-color='#ffffff' x=0 y=0 width=20 height=20 result=m /><feDisplacementMap in=SourceGraphic in2=m scale=10 xChannelSelector=R yChannelSelector=G /></filter><rect x=5 y=5 width=4 height=4 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 2, 2).r == 255 && at(p, 7, 7).a == 0, "feDisplacementMap moves by its map (\(at(p, 2, 2)) \(at(p, 7, 7)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feConvolveMatrix order=3 kernelMatrix='0 0 0 0 0 1 0 0 0' /></filter><rect x=8 y=0 width=4 height=20 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 12, 10).r == 255 && at(p, 8, 10).a == 0, "feConvolveMatrix moves by its kernel (\(at(p, 12, 10)) \(at(p, 8, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feDiffuseLighting lighting-color='#fff' surfaceScale=1><feDistantLight azimuth=0 elevation=90 /></feDiffuseLighting></filter><rect width=20 height=20 filter='url(#f)'/></svg>")
    check(at(p, 10, 10).r == 255, "feDiffuseLighting from straight above lights a flat surface (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f \(whole)><feSpecularLighting lighting-color='#fff' specularConstant=1 specularExponent=20><feDistantLight azimuth=0 elevation=0 /></feSpecularLighting></filter><rect width=20 height=20 filter='url(#f)'/></svg>")
    check(at(p, 10, 10).r < 8, "feSpecularLighting from the side leaves a flat surface dark (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f filterUnits=userSpaceOnUse x=0 y=0 width=20 height=20><feComposite in=SourceGraphic in2=SourceGraphic operator=arithmetic k2=0.5 /></filter><rect width=20 height=20 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 10, 10).a > 120 && at(p, 10, 10).a < 135, "operator=arithmetic (\(at(p, 10, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f filterUnits=userSpaceOnUse x=0 y=0 width=20 height=20><feGaussianBlur stdDeviation='3 0' /></filter><rect x=8 y=8 width=4 height=4 fill='#f00' filter='url(#f)'/></svg>")
    check(at(p, 5, 10).a > 0 && at(p, 10, 5).a == 0, "a blur that goes one way only (\(at(p, 5, 10)) \(at(p, 10, 5)))")
    print("Groups")
    p = render("<svg viewBox='0 0 20 20'><g opacity=.5><rect width=12 height=20 fill='#f00'/><rect x=8 width=12 height=20 fill='#f00'/></g></svg>")
    check(at(p, 10, 10).a == at(p, 2, 10).a && at(p, 10, 10).a < 140, "a group's opacity is the group's, not each shape's (\(at(p, 10, 10)) \(at(p, 2, 10)))")
    p = render("<svg viewBox='0 0 20 20'><filter id=f filterUnits=userSpaceOnUse x=0 y=0 width=20 height=20><feOffset dx=5 /></filter><g filter='url(#f)' transform='translate(2 0)'><rect width=2 height=20 fill='#f00'/><rect x=4 width=2 height=20 fill='#00f'/></g></svg>")
    check(at(p, 7, 10).r == 255 && at(p, 11, 10).b == 255 && at(p, 2, 10).a == 0, "a group's filter (\(at(p, 7, 10)) \(at(p, 11, 10)) \(at(p, 2, 10)))")
    p = render("<svg viewBox='0 0 20 20'><mask id=m><rect width=10 height=20 fill='#fff'/></mask><g mask='url(#m)'><rect width=20 height=20 fill='#f00'/></g></svg>")
    check(at(p, 5, 10).r == 255 && at(p, 15, 10).a == 0, "a group's mask (\(at(p, 5, 10)) \(at(p, 15, 10)))")
    p = render("<svg viewBox='0 0 20 20'><defs><rect id=u width=12 height=20 fill='#f00'/></defs><g opacity=.5><use href='#u'/><use href='#u' x=8 /></g><use href='#u' opacity=.5 y=30 /></svg>")
    check(at(p, 10, 10).a == at(p, 2, 10).a && at(p, 10, 10).a < 140, "<use> in a group with opacity (\(at(p, 10, 10)))")
    print("Text")
    p = render("<svg viewBox='0 0 40 40'><text x=2 y=30 font-size=30 fill=none stroke='#f00' stroke-width=2>H</text></svg>", size: 40)
    var strokeLit = 0
    var sy: int32 = 0
    while sy < 40 {
        var sx: int32 = 0
        while sx < 40 {
            if at(p, sx, sy, size: 40).r > 100 { strokeLit += 1 }
            sx += 1
        }
        sy += 1
    }
    check(strokeLit > 30, "<text> takes a stroke along its outline (\(strokeLit) pixels)")
    p = render("<svg viewBox='0 0 40 40'><defs><linearGradient id=gt><stop offset=0 stop-color='#f00'/><stop offset=1 stop-color='#00f'/></linearGradient></defs><text x=0 y=32 font-size=40 fill='url(#gt)'>HH</text></svg>", size: 40)
    var reds = 0
    var blues = 0
    sy = 0
    while sy < 40 {
        var sx: int32 = 0
        while sx < 40 {
            let c = at(p, sx, sy, size: 40)
            if c.r > 180 && c.b < 110 { reds += 1 }
            if c.b > 120 && c.r < 140 && c.a > 200 { blues += 1 }
            sx += 1
        }
        sy += 1
    }
    check(reds > 5 && blues > 5, "<text> with a gradient runs across it (\(reds) \(blues))")
    p = render("<svg viewBox='0 0 100 100'><path id=arc d='M10 90 L90 10' fill=none /><text font-size=20 fill='#00f'><textPath href='#arc'>IIII</textPath></text></svg>", size: 100)
    var nearPath = 0
    var far = 0
    sy = 0
    while sy < 100 {
        var sx: int32 = 0
        while sx < 100 {
            if at(p, sx, sy, size: 100).a > 100 {
                if sx + sy > 70 && sx + sy < 130 && sx < 90 { nearPath += 1 }
                if sx + sy < 50 || sx + sy > 150 { far += 1 }
            }
            sx += 1
        }
        sy += 1
    }
    check(nearPath > 10 && far == 0, "<textPath> sets its glyphs along the path (\(nearPath) near, \(far) far)")
    p = render("<svg viewBox='0 0 40 40' ><text x=2 y=30 font-size=30 fill='#f00'>HH</text></svg>", size: 40)
    var lit = 0
    var y: int32 = 0
    while y < 40 {
        var x: int32 = 0
        while x < 40 {
            if at(p, x, y, size: 40).r > 100 { lit += 1 }
            x += 1
        }
        y += 1
    }
    check(lit > 40, "<text> draws glyphs in its fill (\(lit) pixels)")
    p = render("<svg viewBox='0 0 40 40'><text x=20 y=30 font-size=30 text-anchor=end fill='#f00'>H</text></svg>", size: 40)
    var rightOf = 0
    y = 0
    while y < 40 {
        var x: int32 = 22
        while x < 40 {
            if at(p, x, y, size: 40).a > 0 { rightOf += 1 }
            x += 1
        }
        y += 1
    }
    check(rightOf == 0, "text-anchor: end ends at x (\(rightOf))")
    p = render("<svg viewBox='0 0 40 20'><rect width=40 height=20 /></svg>")
    check(at(p, 10, 3).a == 0 && at(p, 10, 10).a == 255, "a wide viewBox is centered in a square box")

    if failures == 0 {
        print("ALL SVG CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
