package web

import (
    "image/draw"
    "time"
    "web/css"
    "web/dom"
    "web/html"
    "web/layout"
    "web/paint"
)

// What a form control opens in the page itself: a <select>'s list, and a
// calendar, a list of times or a palette where the host has no panels of its
// own (OnPickDate, OnPickColor). A panel paints over everything, and while
// it is open it takes the pointer and the keys.

/// What a panel is showing.
enum PickerKind {
    case options
    case calendar
    case months
    case times
    case colors
}

final class Picker {
    let node: html.Node
    let kind: PickerKind
    var year: int = 2000
    var month: int = 1
    /// The list's first row showing, and the row under the pointer or keys.
    var first: int = 0
    var highlight: int = -1
    var cells: [paint.PanelCell] = []
    var actions: [(() -> Void)?] = []
    var frame: draw.Rect = draw.Rect.zero

    init(node: html.Node, kind: PickerKind) {
        self.node = node
        self.kind = kind
    }
}

let panelRow: float32 = 24
let panelMaxRows = 12
let dayCell: float32 = 30

func daysIn(month: int, year: int) -> int {
    switch month {
    case 4, 6, 9, 11: return 30
    case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    default: return 31
    }
}

/// 0 for Sunday.
func weekday(year: int, month: int, day: int) -> int {
    let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    let y = month < 3 ? year - 1 : year
    return (y + y / 4 - y / 100 + y / 400 + t[month - 1] + day) % 7
}

func dayOfYear(year: int, month: int, day: int) -> int {
    var n = day
    var m = 1
    while m < month {
        n += daysIn(month: m, year: year)
        m += 1
    }
    return n
}

/// The ISO year and week a day falls in.
func isoWeek(year: int, month: int, day: int) -> (year: int, week: int) {
    let wd = (weekday(year: year, month: month, day: day) + 6) % 7
    let week = (dayOfYear(year: year, month: month, day: day) - wd + 9) / 7
    if week < 1 {
        let last = isoWeek(year: year - 1, month: 12, day: 31)
        return last
    }
    if week == 53 && (weekday(year: year + 1, month: 1, day: 1) + 6) % 7 <= 3 { return (year: year + 1, week: 1) }
    return (year: year, week: week)
}

/// The year and month a count of days since 1970 falls in.
func yearAndMonth(unixDays: int) -> (year: int, month: int) {
    var left = unixDays
    var y = 1970
    while true {
        let days = daysIn(month: 2, year: y) == 29 ? 366 : 365
        if left < days { break }
        left -= days
        y += 1
    }
    var m = 1
    while left >= daysIn(month: m, year: y) {
        left -= daysIn(month: m, year: y)
        m += 1
    }
    return (year: y, month: m)
}

func twoDigits(n: int) -> string { return n < 10 ? "0\(n)" : "\(n)" }

let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

extension Page {
    /// Whether a select has rich options of its own: appearance: base-select.
    func isBaseSelect(node: html.Node) -> bool {
        return builder.byNode[node.Id]?.Style.Appearance == "base-select"
    }

    /// The box's place on the page, where a panel hangs from.
    func anchorOf(node: html.Node) -> draw.Rect {
        guard let b = builder.byNode[node.Id] else { return draw.Rect(scroll.X, scroll.Y, 0, 0) }
        let p = layout.PagePosition(b)
        return draw.Rect(p.x, p.y, b.Width, b.Height)
    }

    func closePicker() {
        picker = nil
        needsPaint = true
        needsRepaint = true
    }

    /// Puts a choice in: the option chosen, input and change sent.
    func chooseOption(select: html.Node, option: html.Node) {
        guard let doc = Document else { return }
        if option.HasAttribute("disabled") { return }
        let already = option.HasAttribute("selected")
        for o in dom.Descendants(select, tag: "option") { doc.RemoveAttribute(o, "selected") }
        doc.SetAttribute(option, "selected", "")
        needsStyle = true
        if already { return }
        _ = dispatch(dom.Event("input"), to: select)
        _ = dispatch(dom.Event("change"), to: select)
    }

    // MARK: - appearance: base-select

    /// A click in a base-select: on an option, chooses it and closes; on
    /// the rest, opens or closes.
    func clickBaseSelect(select: html.Node, target: html.Node?) {
        if select.HasAttribute("disabled") { return }
        Focus(select)
        if let t = target, let option = dom.Ancestor(t, "option"), context.PickerOpen.contains(select.Id) {
            if option.HasAttribute("disabled") { return }
            chooseOption(select, option)
            setBasePicker(select, open: false)
            return
        }
        setBasePicker(select, open: !context.PickerOpen.contains(select.Id))
    }

    func setBasePicker(select: html.Node, open: bool) {
        if open { context.PickerOpen.insert(select.Id) } else { context.PickerOpen.remove(select.Id) }
        builder.PickersOpen = context.PickerOpen
        needsStyle = true
        needsLayout = true
        needsRepaint = true
        _ = dispatch(dom.ToggleEvent("toggle", OldState: open ? "closed" : "open", NewState: open ? "open" : "closed"), to: select)
    }

    /// A press outside an open base-select closes it.
    func dismissBasePickers(target: html.Node?) {
        for id in context.PickerOpen {
            guard let b = builder.byNode[id], let n = b.Node else { continue }
            if let t = target, dom.Ancestor(t, "select")?.Id == id { continue }
            setBasePicker(n, open: false)
        }
    }

    // MARK: - Opening

    func openSelectPanel(select: html.Node) {
        if select.HasAttribute("disabled") { return }
        let p = Picker(node: select, kind: .options)
        let options = dom.Descendants(select, tag: "option")
        var i = 0
        while i < options.count {
            if options[i].HasAttribute("selected") { p.highlight = i }
            i += 1
        }
        if p.highlight < 0 && !options.isEmpty { p.highlight = 0 }
        if p.highlight >= panelMaxRows { p.first = p.highlight - panelMaxRows + 1 }
        picker = p
        layoutPicker()
    }

    func openDatePanel(node: html.Node, type: string) {
        var kind = PickerKind.calendar
        if type == "month" { kind = .months }
        if type == "time" { kind = .times }
        let p = Picker(node: node, kind: kind)
        let parts = valueOf(node).split(separator: "-").map { string($0) }
        if parts.count >= 2, let y = int(parts[0]), type != "week", let m = int(parts[1].prefix(2)), m >= 1, m <= 12 {
            p.year = y
            p.month = m
        } else {
            let today = yearAndMonth(unixDays: int(time.Timestamp.Now().UnixSeconds / 86400))
            p.year = today.year
            p.month = today.month
        }
        if kind == .times { p.highlight = 18 }
        if kind == .times, let h = int(valueOf(node).prefix(2)) { p.highlight = h * 2 }
        if kind == .times { p.first = p.highlight > 4 ? p.highlight - 4 : 0 }
        picker = p
        layoutPicker()
    }

    func openColorPanel(node: html.Node) {
        picker = Picker(node: node, kind: .colors)
        layoutPicker()
    }

    // MARK: - Laying out

    /// The panel's cells for what it is showing now, hung under its control,
    /// or over it where there is no room below.
    func layoutPicker() {
        guard let p = picker else { return }
        p.cells = []
        p.actions = []
        let at = anchorOf(p.node)
        var w: float32 = 0
        var h: float32 = 0
        var rows: [(draw.Rect, string, draw.Color?, draw.Color, bool, (() -> Void)?)] = []
        func add(r: draw.Rect, text: string, fill: draw.Color? = nil, color: draw.Color = draw.Color(30, 30, 30), center: bool = true, action: (() -> Void)? = nil) {
            rows.append((r, text, fill, color, center, action))
        }
        let accent = css.SystemAccent
        switch p.kind {
        case .options:
            let options = dom.Descendants(p.node, tag: "option")
            let face = builder.byNode[p.node.Id]?.Style.Face
            w = at.Width
            for o in options {
                let tw = (face?.Measure(cascadeTrim(o.InnerText())) ?? 80) + 32
                if tw > w { w = tw }
            }
            let shown = options.count < panelMaxRows ? options.count : panelMaxRows
            h = float32(shown) * panelRow
            var row = 0
            while row < shown {
                let i = row + p.first
                if i >= options.count { break }
                let o = options[i]
                let off = o.HasAttribute("disabled")
                let lit = i == p.highlight && !off
                add(draw.Rect(0, float32(row) * panelRow, w, panelRow), (o.HasAttribute("selected") ? "✓ " : "   ") + cascadeTrim(o.InnerText()),
                    fill: lit ? accent : nil, color: off ? draw.Color(160, 160, 160) : (lit ? draw.Color.white : draw.Color(30, 30, 30)), center: false,
                    action: off ? nil : { [p] in self.pickOption(p, o) })
                row += 1
            }
        case .times:
            w = at.Width > 100 ? at.Width : 100
            let shown = panelMaxRows
            h = float32(shown) * panelRow
            var row = 0
            while row < shown {
                let i = row + p.first
                if i >= 48 { break }
                let text = "\(twoDigits(i / 2)):\(i % 2 == 0 ? "00" : "30")"
                let lit = i == p.highlight
                add(draw.Rect(0, float32(row) * panelRow, w, panelRow), text, fill: lit ? accent : nil, color: lit ? draw.Color.white : draw.Color(30, 30, 30),
                    action: { self.pickValue(p, text) })
                row += 1
            }
        case .months:
            w = 3 * 72
            h = panelRow + 4 * panelRow * 1.5
            add(draw.Rect(0, 0, panelRow, panelRow), "‹", action: { p.year -= 1; self.layoutPicker() })
            add(draw.Rect(panelRow, 0, w - 2 * panelRow, panelRow), "\(p.year)")
            add(draw.Rect(w - panelRow, 0, panelRow, panelRow), "›", action: { p.year += 1; self.layoutPicker() })
            var m = 0
            while m < 12 {
                let value = "\(p.year)-\(twoDigits(m + 1))"
                let chosen = valueOf(p.node) == value
                add(draw.Rect(float32(m % 3) * 72, panelRow + float32(m / 3) * panelRow * 1.5, 72, panelRow * 1.5), String(monthNames[m].prefix(3)),
                    fill: chosen ? accent : nil, color: chosen ? draw.Color.white : draw.Color(30, 30, 30), action: { self.pickValue(p, value) })
                m += 1
            }
        case .calendar:
            w = 7 * dayCell
            let weeks = (weekday(year: p.year, month: p.month, day: 1) + daysIn(month: p.month, year: p.year) + 6) / 7
            h = panelRow * 2 + float32(weeks) * dayCell
            add(draw.Rect(0, 0, panelRow, panelRow), "‹", action: { self.shiftMonth(p, -1) })
            add(draw.Rect(panelRow, 0, w - 2 * panelRow, panelRow), "\(monthNames[p.month - 1]) \(p.year)")
            add(draw.Rect(w - panelRow, 0, panelRow, panelRow), "›", action: { self.shiftMonth(p, 1) })
            let names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
            var d = 0
            while d < 7 {
                add(draw.Rect(float32(d) * dayCell, panelRow, dayCell, panelRow), names[d], color: draw.Color(120, 120, 120))
                d += 1
            }
            let type = dom.InputType(p.node)
            let start = weekday(year: p.year, month: p.month, day: 1)
            let count = daysIn(month: p.month, year: p.year)
            var day = 1
            while day <= count {
                let at = start + day - 1
                let value = dateValue(p, type: type, day: day)
                let chosen = valueOf(p.node) == value
                add(draw.Rect(float32(at % 7) * dayCell, panelRow * 2 + float32(at / 7) * dayCell, dayCell, dayCell), "\(day)",
                    fill: chosen ? accent : nil, color: chosen ? draw.Color.white : draw.Color(30, 30, 30), action: { self.pickValue(p, value) })
                day += 1
            }
        case .colors:
            let side: float32 = 24
            let hues = 8
            let shades = 6
            w = float32(hues) * side
            h = float32(shades) * side
            var row = 0
            while row < shades {
                var col = 0
                while col < hues {
                    let c = paletteColor(col, row, hues: hues, shades: shades)
                    let hex = "#\(hexByte(c.R))\(hexByte(c.G))\(hexByte(c.B))"
                    add(draw.Rect(float32(col) * side, float32(row) * side, side, side), "", fill: c, action: { self.pickValue(p, hex) })
                    col += 1
                }
                row += 1
            }
        }
        // Under the control, or over it, and kept on the page's view.
        var x = at.X
        if x + w > scroll.X + size.Width { x = scroll.X + size.Width - w }
        if x < scroll.X { x = scroll.X }
        var y = at.Bottom + 2
        if y + h > scroll.Y + size.Height && at.Y - h - 2 >= scroll.Y { y = at.Y - h - 2 }
        p.frame = draw.Rect(x, y, w, h)
        for r in rows {
            p.cells.append(paint.PanelCell(rect: draw.Rect(x + r.0.X, y + r.0.Y, r.0.Width, r.0.Height), text: r.1, fill: r.2, color: r.3, centered: r.4))
            p.actions.append(r.5)
        }
        needsPaint = true
        needsRepaint = true
    }

    func shiftMonth(p: Picker, by: int) {
        p.month += by
        if p.month < 1 {
            p.month = 12
            p.year -= 1
        }
        if p.month > 12 {
            p.month = 1
            p.year += 1
        }
        layoutPicker()
    }

    /// A day's value as the control's type writes it. A datetime-local
    /// keeps the time it had.
    func dateValue(p: Picker, type: string, day: int) -> string {
        let date = "\(p.year)-\(twoDigits(p.month))-\(twoDigits(day))"
        switch type {
        case "week":
            let w = isoWeek(year: p.year, month: p.month, day: day)
            return "\(w.year)-W\(twoDigits(w.week))"
        case "datetime-local":
            let parts = valueOf(p.node).split(separator: "T").map { string($0) }
            return date + "T" + (parts.count > 1 ? parts[1] : "00:00")
        default:
            return date
        }
    }

    func pickOption(p: Picker, option: html.Node) {
        closePicker()
        chooseOption(p.node, option)
    }

    func pickValue(p: Picker, value: string) {
        closePicker()
        SetControlValue(p.node, value)
    }

    // MARK: - Input

    /// A press while a panel is open: it goes to a cell, or closes the panel.
    func pickerPressed(at p: draw.Point) {
        guard let k = picker else { return }
        let x = p.X + scroll.X
        let y = p.Y + scroll.Y
        var i = 0
        while i < k.cells.count {
            if k.cells[i].rect.Contains(x, y) {
                if let act = k.actions[i] { act() }
                return
            }
            i += 1
        }
        if !k.frame.Contains(x, y) { closePicker() }
    }

    func pickerMoved(to p: draw.Point) {
        guard let k = picker, k.kind == .options || k.kind == .times else { return }
        let y = p.Y + scroll.Y - k.frame.Y
        if !k.frame.Contains(p.X + scroll.X, p.Y + scroll.Y) { return }
        let row = k.first + int(y / panelRow)
        if row != k.highlight {
            k.highlight = row
            layoutPicker()
        }
    }

    func pickerWheel(dy: float32) {
        guard let k = picker, k.kind == .options || k.kind == .times else { return }
        let total = k.kind == .times ? 48 : dom.Descendants(k.node, tag: "option").count
        let most = total > panelMaxRows ? total - panelMaxRows : 0
        let step = dy > 0 ? 1 : -1
        let next = k.first + step
        k.first = next < 0 ? 0 : (next > most ? most : next)
        layoutPicker()
    }

    /// Presses the cell of an open panel that says this. Answers whether
    /// there was one: for a host driving a panel, as a test does.
    @discardableResult
    public func PressPanelCell(text: string) -> bool {
        guard let k = picker else { return false }
        var i = 0
        while i < k.cells.count {
            if k.cells[i].text == text, let act = k.actions[i] {
                act()
                return true
            }
            i += 1
        }
        return false
    }

    /// A key while a panel is open. Answers whether it took it.
    func pickerKey(k: Key) -> bool {
        guard let p = picker else { return false }
        if k.Code == "Escape" || k.Code == "Tab" {
            closePicker()
            return k.Code == "Escape"
        }
        if p.kind != .options && p.kind != .times { return true }
        let options = p.kind == .options ? dom.Descendants(p.node, tag: "option") : []
        let total = p.kind == .times ? 48 : options.count
        switch k.Code {
        case "ArrowDown": if p.highlight + 1 < total { p.highlight += 1 }
        case "ArrowUp": if p.highlight > 0 { p.highlight -= 1 }
        case "Home": p.highlight = 0
        case "End": p.highlight = total - 1
        case "Enter", "Space":
            if p.kind == .options {
                if p.highlight >= 0 && p.highlight < options.count && !options[p.highlight].HasAttribute("disabled") {
                    pickOption(p, options[p.highlight])
                }
            } else {
                pickValue(p, "\(twoDigits(p.highlight / 2)):\(p.highlight % 2 == 0 ? "00" : "30")")
            }
            return true
        default:
            return true
        }
        if p.highlight < p.first { p.first = p.highlight }
        if p.highlight >= p.first + panelMaxRows { p.first = p.highlight - panelMaxRows + 1 }
        layoutPicker()
        return true
    }
}

func cascadeTrim(s: string) -> string {
    return trimSpaces(s)
}

func hexByte(v: uint8) -> string {
    let digits = [uint8]("0123456789abcdef".utf8)
    return string(decoding: [digits[int(v >> 4)], digits[int(v & 15)]], as: UTF8.self)
}

/// A palette: hues across, light to dark down, with grays in the last column.
func paletteColor(col: int, row: int, hues: int, shades: int) -> draw.Color {
    let t = float32(row) / float32(shades - 1)
    if col == hues - 1 {
        let v = uint8((1 - t) * 255)
        return draw.Color(v, v, v)
    }
    let h = float32(col) / float32(hues - 1) * 6
    let i = int(h)
    let f = h - float32(i)
    var r: float32 = 0
    var g: float32 = 0
    var b: float32 = 0
    switch i % 6 {
    case 0: r = 1; g = f
    case 1: r = 1 - f; g = 1
    case 2: g = 1; b = f
    case 3: g = 1 - f; b = 1
    case 4: r = f; b = 1
    default: r = 1; b = 1 - f
    }
    // Pale at the top, full in the middle, dark below.
    func shade(c: float32) -> uint8 {
        let v = t < 0.5 ? c + (1 - c) * (1 - t * 2) * 0.8 : c * (1 - (t - 0.5) * 1.4)
        return uint8(v * 255)
    }
    return draw.Color(shade(r), shade(g), shade(b))
}
