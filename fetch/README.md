# web/fetch

URLs resolved against a base (through `net/url`), and a `Fetcher` that answers their bytes: files by default, or a host's handler. An `Archive` is a page and its resources recorded to a folder, shown again offline.

```vertex
import "web/fetch"
```

## Types

- **`ArchiveEntry`** (struct): One recorded response.
- **`Archive`** (struct): A page and the resources it refers to, recorded so it can be shown again without the network: for rendering a real site in a check, or working on one without waiting on it.
- **`Fetcher`** (struct): Answers the bytes of a resource by its resolved URL.

## Functions

- `func Resolve(_ reference: string, against base: string) -> string`: A URL made absolute against a base, as RFC 3986 resolves a reference (net/url): `/x` is rooted at the base's host, `//host/x` takes its scheme, `../x` climbs, `?q` keeps its path.
- `func Scheme(_ address: string) -> string`: The scheme of a URL, lowercase, or "" for a path.
- `func Directory(of path: string) -> string`: The folder a file path is in, with its trailing slash; "" for a bare file name. What a file's relative references resolve against.
- `func FilePath(_ address: string) -> string`: A file URL's path, its escapes decoded, or the path itself.

Part of the [`web`](https://github.com/vertex-language/web) repository.
