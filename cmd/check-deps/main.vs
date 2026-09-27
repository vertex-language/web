// The repository's shape, checked: what each package may import.
//
//   - Nothing in web imports ui/ or js: the engine runs without a window,
//     and scripting is a module a program opts into.
//   - Only web/script imports js, and nothing imports web/script.
//   - The pipeline's stages import only the stages before them:
//     html, css, cascade, layout, paint, then the page (package web).
//   - Every attribute the cascade, layout or paint reads by name is one
//     its ReadsAttribute lists, so that a change to it restyles: the
//     journal drops changes to attributes nothing reads.
//
//     vsc run check-deps
package main

import (
    "fs"
    "web/cascade"
    "web/layout"
    "web/paint"
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

/// Where each package stands in the pipeline; a package may import only
/// packages that stand lower. Packages not listed are outside it.
let stage: [string: int] = [
    "web/html": 0, "web/edit": 0, "web/fetch": 0,
    "web/css": 1, "web/dom": 1,
    "web/css/selector": 2,
    "web/cascade": 3,
    "web/layout": 4,
    "web/paint": 5,
    "web": 6,
]

/// The folder of the repository: the nearest one up from here whose
/// vs.mod names the web module.
func repositoryRoot() -> string? {
    var dir = "."
    var i = 0
    while i < 8 {
        if let mod = try? fs.ReadText(fs.Path(dir + "/vs.mod")), mod.contains("vertex-language/web") {
            return dir
        }
        dir = dir == "." ? ".." : dir + "/.."
        i += 1
    }
    return nil
}

/// The paths a source file imports.
func imports(_ source: string) -> [string] {
    var out: [string] = []
    var inBlock = false
    for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = trim(string(raw))
        if inBlock {
            if line == ")" { inBlock = false; continue }
            if let p = quoted(line) { out.append(p) }
            continue
        }
        if line.hasPrefix("import (") { inBlock = true; continue }
        if line.hasPrefix("import \"") {
            if let p = quoted(line) { out.append(p) }
            continue
        }
        // Imports come before the first declaration.
        if line.hasPrefix("func ") || line.hasPrefix("public ") || line.hasPrefix("struct ") ||
           line.hasPrefix("final ") || line.hasPrefix("enum ") || line.hasPrefix("let ") || line.hasPrefix("extension ") {
            break
        }
    }
    return out
}

func quoted(_ line: string) -> string? {
    let b = [uint8](line.utf8)
    var i = 0
    while i < b.count && b[i] != 34 { i += 1 }
    if i >= b.count { return nil }
    var j = i + 1
    while j < b.count && b[j] != 34 { j += 1 }
    if j >= b.count { return nil }
    return string(decoding: b[(i + 1)..<j], as: UTF8.self)
}

func trim(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var start = 0
    var end = b.count
    while start < end && (b[start] == 32 || b[start] == 9) { start += 1 }
    while end > start && (b[end - 1] == 32 || b[end - 1] == 9 || b[end - 1] == 13) { end -= 1 }
    return string(decoding: b[start..<end], as: UTF8.self)
}

/// The import path of the package a file is in, from its path in the
/// repository: "layout/box.vs" is web/layout, "page.vs" is web.
func packageOf(_ relative: string) -> string {
    let parts = relative.split(separator: "/").map { string($0) }
    var out = "web"
    var i = 0
    while i + 1 < parts.count {
        out += "/" + parts[i]
        i += 1
    }
    return out
}

/// The attribute names a source reads literally, by GetAttribute("x") or
/// HasAttribute("x").
func attributeReads(_ source: string) -> [string] {
    var out: [string] = []
    let b = [uint8](source.utf8)
    let needle = [uint8]("Attribute(\"".utf8)
    var i = 3
    while i + needle.count < b.count {
        var hit = true
        var k = 0
        while k < needle.count {
            if b[i + k] != needle[k] { hit = false; break }
            k += 1
        }
        // Get or Has before it.
        if hit && ((b[i - 3] == 71 && b[i - 2] == 101 && b[i - 1] == 116) || (b[i - 3] == 72 && b[i - 2] == 97 && b[i - 1] == 115)) {
            let start = i + needle.count
            var j = start
            while j < b.count && b[j] != 34 { j += 1 }
            out.append(string(decoding: b[start..<j], as: UTF8.self))
            i = j
        }
        i += 1
    }
    return out
}

/// Whether the package that reads an attribute lists it.
func listed(_ pkg: string, _ name: string) -> bool? {
    switch pkg {
    case "web/cascade": return cascade.ReadsAttribute(name) || name == "id" || name == "class"
    case "web/layout": return layout.ReadsAttribute(name)
    case "web/paint": return paint.ReadsAttribute(name)
    default: return nil
    }
}

func main() -> int32 {
    guard let root = repositoryRoot() else {
        print("run this inside the web repository")
        return 2
    }
    var files: [(path: string, relative: string)] = []
    let prefix = root + "/"
    do {
        try fs.Walk(fs.Path(root)) { entry in
            let path = entry.Path.String()
            var relative = path
            if relative.hasPrefix(prefix) { relative = string(relative.dropFirst(prefix.count)) }
            if entry.Kind == .directory {
                if entry.Name == "cmd" || entry.Name == "testdata" || entry.Name.hasPrefix(".") { return .skipDir }
                return .continue
            }
            if path.hasSuffix(".vs") { files.append((path: path, relative: relative)) }
            return .continue
        }
    } catch {
        print("cannot read the repository")
        return 1
    }
    check(!files.isEmpty, "found the repository's sources (\(files.count) files)")

    var windowFree = true
    var scriptFree = true
    var ordered = true
    var readsListed = true
    for f in files {
        guard let source = try? fs.ReadText(fs.Path(f.path)) else { continue }
        let pkg = packageOf(f.relative)
        for name in attributeReads(source) {
            if let ok = listed(pkg, name), !ok {
                print("      \(f.relative) reads the attribute \(name), which \(pkg).ReadsAttribute doesn't list")
                readsListed = false
            }
        }
        for imp in imports(source) {
            if imp.hasPrefix("ui/") {
                print("      \(f.relative) imports \(imp)")
                windowFree = false
            }
            if (imp == "js" || imp.hasPrefix("js/")) && pkg != "web/script" {
                print("      \(f.relative) imports \(imp)")
                scriptFree = false
            }
            if imp == "web/script" {
                print("      \(f.relative) imports \(imp)")
                scriptFree = false
            }
            if let mine = stage[pkg], let theirs = stage[imp], theirs >= mine, imp != pkg {
                print("      \(f.relative) (\(pkg)) imports \(imp), a later stage")
                ordered = false
            }
        }
    }
    check(windowFree, "nothing in web imports ui/")
    check(scriptFree, "only web/script imports js, and nothing imports web/script")
    check(ordered, "each stage imports only the stages before it")
    check(readsListed, "every attribute a stage reads is one its ReadsAttribute lists")
    if failures == 0 {
        print("ALL DEPENDENCY CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
