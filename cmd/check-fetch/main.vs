// Fetching checked: resolution as the page uses it. RFC 3986 itself is
// net/url's, checked by its url-test.
package main

import "web/fetch"

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func resolves(_ url: string, _ base: string, _ want: string) {
    let got = fetch.Resolve(url, against: base)
    check(got == want, "\(url) against \(base) is \(want)" + (got == want ? "" : " (got \(got))"))
}

func testSites() {
    print("Sites and files")
    resolves("/login", "https://github.com/", "https://github.com/login")
    resolves("login", "https://github.com", "https://github.com/login")
    resolves("//github.githubassets.com/a.css", "https://github.com/", "https://github.githubassets.com/a.css")
    resolves("images/x.png", "https://www.google.com/webhp?hl=en", "https://www.google.com/images/x.png")
    resolves("#top", "https://github.com/", "#top")
    resolves("data:image/png;base64,AAAA", "https://github.com/", "data:image/png;base64,AAAA")
    resolves("page2.html", "testdata/pages/", "testdata/pages/page2.html")
    resolves("../style.css", "testdata/pages/", "testdata/style.css")
    resolves("../../x.css", "pages/", "../x.css")
    resolves("x.css", "", "x.css")
    resolves("sub/x.png", "/Users/me/site/", "/Users/me/site/sub/x.png")
    resolves("x.png", "file:///Users/me/site/index.html", "file:///Users/me/site/x.png")
    check(fetch.Scheme("HTTPS://x") == "https" && fetch.Scheme("a/b.html") == "" && fetch.Scheme("C:/x") == "", "Scheme: lowercase, and none for paths")
    check(fetch.FilePath("file:///Users/me/My%20Site/a.html") == "/Users/me/My Site/a.html" && fetch.FilePath("docs/a.html") == "docs/a.html", "FilePath decodes a file URL, and leaves a path alone")
    resolves("", "https://github.com/x", "https://github.com/x")
    resolves("x.css", "", "x.css")
}

func main() -> int32 {
    testSites()
    if failures == 0 {
        print("ALL FETCH CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
