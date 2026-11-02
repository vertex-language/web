package web

import (
    "image/draw"
    "web/dom"
    "web/html"
)

// HTML drag and drop: a press on a draggable="true" element that moves
// a few pixels is a drag. dragstart fires at it (with a DataTransfer for
// the data), then drag as it moves; what it moves over gets dragenter,
// dragover and dragleave; a dragover listener that calls PreventDefault
// takes the drop, and drop fires there on release; dragend at the source
// last. Files dropped from outside the page come through DropFiles.

/// A drag under way, or a press that may become one.
final class DragState {
    let source: html.Node
    let start: draw.Point
    let data = dom.DataTransfer()
    var started = false
    var over: html.Node? = nil
    var accepted = false

    init(source: html.Node, start: draw.Point) {
        self.source = source
        self.start = start
    }
}

/// How far a press moves before it is a drag.
let dragThreshold: float32 = 4

extension Page {
    /// The element a press on node drags: the nearest with draggable=true.
    func draggableAncestor(node: html.Node?) -> html.Node? {
        var cur = node
        while let n = cur {
            if n.Kind == html.NodeKind.element {
                let d = lower(n.GetAttribute("draggable") ?? "")
                if d == "true" { return n }
                if d == "false" { return nil }
            }
            cur = n.Parent
        }
        return nil
    }

    /// The element under a point, for a drag's events.
    func dragTarget(p: draw.Point) -> html.Node? {
        return hitAt(p)?.Node
    }

    /// A move while pressed: the drag starting, or going on. Answers
    /// whether the drag took the move.
    func dragMoved(p: draw.Point) -> bool {
        guard let d = dragging else { return false }
        if !d.started {
            let dx = p.X - d.start.X
            let dy = p.Y - d.start.Y
            if dx * dx + dy * dy < dragThreshold * dragThreshold { return false }
            d.data.EffectAllowed = "all"
            if !dispatch(dom.DragEvent("dragstart", X: d.start.X, Y: d.start.Y, Data: d.data), to: d.source) {
                dragging = nil
                return false
            }
            d.started = true
            // A drag is no selection and no click.
            selecting = false
            ClearSelection()
        }
        _ = dispatch(dom.DragEvent("drag", X: p.X, Y: p.Y, Data: d.data), to: d.source)
        let target = dragTarget(p)
        if target?.Id != d.over?.Id {
            if let old = d.over { _ = dispatch(dom.DragEvent("dragleave", X: p.X, Y: p.Y, Data: d.data), to: old) }
            if let t = target { _ = dispatch(dom.DragEvent("dragenter", X: p.X, Y: p.Y, Data: d.data), to: t) }
            d.over = target
        }
        d.accepted = false
        if let t = target {
            d.data.DropEffect = "none"
            // A listener that prevents dragover's default takes the drop.
            d.accepted = !dispatch(dom.DragEvent("dragover", X: p.X, Y: p.Y, Data: d.data), to: t)
            if d.accepted && d.data.DropEffect == "none" { d.data.DropEffect = "move" }
        }
        cursor = d.accepted ? Cursor.copy : Cursor.noDrop
        return true
    }

    /// The release: drop where it was taken, then dragend. Answers
    /// whether a drag ended (so the release is no click).
    func dragReleased(p: draw.Point) -> bool {
        guard let d = dragging else { return false }
        dragging = nil
        if !d.started { return false }
        if d.accepted, let t = d.over {
            _ = dispatch(dom.DragEvent("drop", X: p.X, Y: p.Y, Data: d.data), to: t)
        } else {
            d.data.DropEffect = "none"
            if let t = d.over { _ = dispatch(dom.DragEvent("dragleave", X: p.X, Y: p.Y, Data: d.data), to: t) }
        }
        _ = dispatch(dom.DragEvent("dragend", X: p.X, Y: p.Y, Data: d.data), to: d.source)
        cursor = Cursor.default
        needsPaint = true
        return true
    }

    /// Files dragged from outside the page and dropped at a point: the
    /// element there gets dragenter, dragover and, if it takes them,
    /// drop, its DataTransfer's Files the paths. Answers whether it took
    /// them.
    public func DropFiles(paths: [string], at p: draw.Point) -> bool {
        update()
        guard let t = dragTarget(p) else { return false }
        let data = dom.DataTransfer()
        data.Files = paths
        data.SetData("Files", "")
        data.EffectAllowed = "copy"
        _ = dispatch(dom.DragEvent("dragenter", X: p.X, Y: p.Y, Data: data), to: t)
        let taken = !dispatch(dom.DragEvent("dragover", X: p.X, Y: p.Y, Data: data), to: t)
        if !taken {
            _ = dispatch(dom.DragEvent("dragleave", X: p.X, Y: p.Y, Data: data), to: t)
            return false
        }
        data.DropEffect = "copy"
        _ = dispatch(dom.DragEvent("drop", X: p.X, Y: p.Y, Data: data), to: t)
        return true
    }
}
