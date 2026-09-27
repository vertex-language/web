// Renders an HTML file to a PNG without a window: for looking at what
// the engine draws, and for comparing renders. An archive (a site the
// browser recorded with --record) renders as the site did, offline.
//
//     vsc run snapshot -- page.html out.png [width] [height] [scale]
//     vsc run snapshot -- --archive site/ out.png [width] [height] [scale]
package main

import (
    "fs"
    "image"
    "image/png"
    "image/draw"
    "time"
    "web"
    "web/fetch"
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

func main() -> int32 {
    var args = CommandLine.arguments
    var archiveDir: string? = nil
    if args.count > 2 && args[1] == "--archive" {
        archiveDir = args[2]
        args.remove(at: 1)
    }
    if args.count < 3 {
        print("usage: snapshot page.html out.png [width] [height] [scale]")
        print("       snapshot --archive dir out.png [width] [height] [scale]")
        return 2
    }
    let width = number(args.count > 3 ? args[3] : "", 800)
    let height = number(args.count > 4 ? args[4] : "", 600)
    let scale = number(args.count > 5 ? args[5] : "", 1)

    let page = web.Page()
    page.SetViewportSize(draw.Size(width, height))
    let start = time.Instant.Now()
    if let dir = archiveDir {
        guard let archive = try? fetch.Archive.Read(from: dir), let entry = archive.Entries[archive.Page] else {
            print("cannot read the archive in \(dir)")
            return 1
        }
        page.Configuration.Fetcher = archive.Fetcher()
        page.LoadBytes(entry.Body, contentType: entry.ContentType, baseURL: archive.Page)
    } else {
        do {
            try page.LoadFile(args[1])
        } catch {
            print("cannot read \(args[1])")
            return 1
        }
    }
    let pw = int32(width * scale)
    let ph = int32(height * scale)
    var pixels = [uint8](repeating: 0, count: int(pw) * int(ph) * 4)
    page.Draw(into: &pixels, width: pw, height: ph, scale: scale)
    let encoded = png.Encode(image.RGBA(width: int(pw), height: int(ph), pixels: pixels))
    do {
        try fs.WriteFile(fs.Path(args[2]), encoded)
    } catch {
        print("cannot write \(args[2])")
        return 1
    }
    let elapsed = start.Elapsed()
    let content = page.ContentSize()
    print("rendered \(args[1]): \(pw)x\(ph) pixels, content \(content.Width)x\(content.Height) points, in \(elapsed)")
    return 0
}
