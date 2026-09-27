package fetch

import "fs"

/// One recorded response.
public struct ArchiveEntry {
    public var URL: string
    public var Status: int32
    public var ContentType: string
    public var Body: [uint8]

    public init(URL: string, Status: int32, ContentType: string, Body: [uint8]) {
        self.URL = URL
        self.Status = Status
        self.ContentType = ContentType
        self.Body = Body
    }
}

/// A page and the resources it refers to, recorded so it can be shown
/// again without the network: for rendering a real site in a check, or
/// working on one without waiting on it.
///
/// On disk it is a folder: `index.tsv` names the page, then one line per
/// resource -- status, content type, file, URL, tab-separated -- and
/// each body is a file of its own.
public struct Archive {
    /// The page's URL, after redirects.
    public var Page: string
    public var Entries: [string: ArchiveEntry]

    public init(page: string) {
        Page = page
        Entries = [:]
    }

    public mutating func Add(_ entry: ArchiveEntry) {
        Entries[entry.URL] = entry
    }

    /// A fetcher that answers from the archive: the body of a 2xx
    /// response, and nil for anything else.
    public func Fetcher() -> Fetcher {
        let entries = Entries
        return fetch.Fetcher({ u in
            if let e = entries[u], e.Status >= 200 && e.Status < 300 { return e.Body }
            return nil
        })
    }

    /// Writes the archive into a folder, made if missing.
    public func Write(to dir: string) throws {
        try fs.CreateDir(fs.Path(dir), all: true)
        var index = "page\t\(Page)\n"
        var urls: [string] = []
        for (u, _) in Entries { urls.append(u) }
        urls.sort()
        var n = 0
        for u in urls {
            guard let e = Entries[u] else { continue }
            n += 1
            let file = "\(n).bin"
            try fs.WriteFile(fs.Path(dir + "/" + file), e.Body)
            index += "\(e.Status)\t\(clean(e.ContentType))\t\(file)\t\(clean(u))\n"
        }
        try fs.WriteText(fs.Path(dir + "/index.tsv"), index)
    }

    /// Reads an archive a Write made.
    public static func Read(from dir: string) throws -> Archive {
        let index = try fs.ReadText(fs.Path(dir + "/index.tsv"))
        var archive = Archive(page: "")
        for raw in index.split(separator: "\n") {
            let fields = raw.split(separator: "\t", omittingEmptySubsequences: false).map { string($0) }
            if fields.count == 2 && fields[0] == "page" {
                archive.Page = fields[1]
                continue
            }
            if fields.count < 4 { continue }
            let body = try fs.ReadFile(fs.Path(dir + "/" + fields[2]))
            archive.Add(ArchiveEntry(URL: fields[3], Status: int32(fields[0]) ?? 0, ContentType: fields[1], Body: body))
        }
        return archive
    }
}

/// A field without the tabs and newlines that separate fields.
func clean(_ s: string) -> string {
    if !s.contains("\t") && !s.contains("\n") { return s }
    var b = [uint8](s.utf8)
    var i = 0
    while i < b.count {
        if b[i] == 9 || b[i] == 10 || b[i] == 13 { b[i] = 32 }
        i += 1
    }
    return stringOf(b, 0, b.count)
}
