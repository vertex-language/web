package fetch

import "fs"

// Resources a page refers to: URLs resolved against the page's base,
// and their bytes. Files are read from disk; any other scheme needs a
// handler from the host.

/// A URL made absolute against a base: absolute URLs, data: URLs, rooted
/// paths and fragments are left alone.
public func Resolve(_ url: string, against base: string) -> string {
    if url.isEmpty { return base }
    if url.hasPrefix("#") { return url }
    if url.contains("://") || url.hasPrefix("data:") || url.hasPrefix("/") || url.hasPrefix("about:") { return url }
    if base.isEmpty { return url }
    if base.hasSuffix("/") { return base + url }
    return base + "/" + url
}

/// The folder a file path is in, with its trailing slash; "" for a bare
/// file name. What a file's relative references resolve against.
public func Directory(of path: string) -> string {
    let b = [uint8](path.utf8)
    var i = b.count - 1
    while i >= 0 && b[i] != 47 { i -= 1 }
    return i >= 0 ? stringOf(b, 0, i + 1) : ""
}

/// A file URL's path, or the path itself.
public func FilePath(_ url: string) -> string {
    if url.hasPrefix("file://") {
        let b = [uint8](url.utf8)
        return stringOf(b, 7, b.count)
    }
    return url
}

/// Answers the bytes of a resource by its resolved URL.
public struct Fetcher {
    /// Answers a URL itself: every URL goes here when set, and nothing
    /// is read from disk.
    public var Handler: ((string) -> [uint8]?)?

    public init() {
        Handler = nil
    }

    public init(_ handler: (string) -> [uint8]?) {
        Handler = handler
    }

    /// The resource's bytes, or nil. Without a handler, file paths and
    /// file: URLs are read from disk, and other schemes answer nil.
    public func Fetch(_ url: string) -> [uint8]? {
        if let h = Handler {
            return h(url)
        }
        let path = FilePath(url)
        if path.contains("://") { return nil }
        if let bytes = try? fs.ReadFile(fs.Path(path)) {
            return bytes
        }
        return nil
    }
}

@_silgen_name("vertex_string_from_utf8")
func stringFromUtf8(_ ptr: UnsafeRawPointer, _ count: int64) -> string

func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return bytes.withUnsafeBytes { bp in
        stringFromUtf8(bp.baseAddress! + start, int64(end - start))
    }
}
