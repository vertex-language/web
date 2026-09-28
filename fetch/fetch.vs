package fetch

import (
    "unicode/utf8"
    "fs"
    "net/url"
)

// Resources a page refers to: URLs resolved against the page's base,
// and their bytes. Files are read from disk; any other scheme needs a
// handler from the host.

/// A URL made absolute against a base, as RFC 3986 resolves a reference
/// (net/url): `/x` is rooted at the base's host, `//host/x` takes its
/// scheme, `../x` climbs, `?q` keeps its path. A base with no scheme is
/// a file path, and resolves the same way. A fragment alone is left for
/// the page to scroll to, and what doesn't parse is left as it is.
public func Resolve(_ reference: string, against base: string) -> string {
    if reference.isEmpty { return base }
    if reference.hasPrefix("#") || base.isEmpty { return reference }
    guard let r = try? url.Parse(reference) else { return reference }
    if r.IsAbsolute { return r.String() }
    guard let b = try? url.Parse(base) else { return reference }
    return b.ResolveReference(r).String()
}

/// The scheme of a URL, lowercase, or "" for a path.
public func Scheme(_ address: string) -> string {
    guard let u = try? url.Parse(address) else { return "" }
    return u.Scheme
}

/// The folder a file path is in, with its trailing slash; "" for a bare
/// file name. What a file's relative references resolve against.
public func Directory(of path: string) -> string {
    let b = [uint8](path.utf8)
    var i = b.count - 1
    while i >= 0 && b[i] != 47 { i -= 1 }
    return i >= 0 ? stringOf(b, 0, i + 1) : ""
}

/// A file URL's path, its escapes decoded, or the path itself.
public func FilePath(_ address: string) -> string {
    if address.hasPrefix("file:"), let u = try? url.Parse(address) {
        return url.PathUnescape(u.Path)
    }
    return address
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

func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return utf8.Decode(bytes, start, end)
}
