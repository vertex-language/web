package dom

import "web/html"

/// An event dispatched to an element: what happened, where, and whether
/// a listener asked for the default action not to be taken. As the DOM
/// dispatches it: the capturing listeners of the target's ancestors,
/// outermost first; the target's own; then, where it bubbles, the other
/// listeners of each ancestor in turn -- until one stops it.
public class Event {
    /// The event's name: "click", "input", "submit".
    public let Type: string
    /// The element the event happened to.
    public internal(set) var Target: html.Node? = nil
    /// The element whose listener is running now.
    public internal(set) var CurrentTarget: html.Node? = nil
    public internal(set) var DefaultPrevented = false
    /// Whether the event goes on to the ancestors' listeners. mouseenter,
    /// mouseleave, focus and blur do not: each is its element's own.
    public let Bubbles: bool
    /// Where the event is now: 1 capturing, 2 at the target, 3 bubbling, 0
    /// not being dispatched (the DOM's eventPhase).
    public internal(set) var Phase: int = 0
    var stopped = false
    var stoppedImmediately = false

    public init(type: string, bubbles: bool = true) {
        Type = type
        Bubbles = bubbles
    }

    /// Asks that what the engine would do after the event -- submit the
    /// form, toggle the box, follow the link -- not be done.
    public func PreventDefault() { DefaultPrevented = true }

    /// Stops the event going on to the listeners of further ancestors.
    public func StopPropagation() { stopped = true }

    /// Stops the event going on to any other listener, this element's too.
    public func StopImmediatePropagation() {
        stopped = true
        stoppedImmediately = true
    }
}

/// A pointer press and release on the same element, and its kin:
/// pointerdown, pointermove and pointerup too (a press's moves and its
/// release go to the element it began on).
public class MouseEvent: Event {
    /// Where, in CSS pixels from the viewport's corner.
    public let X: float32
    public let Y: float32
    public let Clicks: int32
    /// 0 primary, 1 middle, 2 secondary, as the DOM numbers them.
    public let Button: int32
    /// Whether a button is held (for pointermove).
    public let Pressed: bool
    /// The modifier keys held.
    public let Shift: bool
    public let Control: bool
    public let Alt: bool
    public let Meta: bool

    public init(type: string, X: float32 = 0, Y: float32 = 0, Clicks: int32 = 1, Button: int32 = 0, Pressed: bool = false,
                Shift: bool = false, Control: bool = false, Alt: bool = false, Meta: bool = false, bubbles: bool = true) {
        self.X = X
        self.Y = Y
        self.Clicks = Clicks
        self.Button = Button
        self.Pressed = Pressed
        self.Shift = Shift
        self.Control = Control
        self.Alt = Alt
        self.Meta = Meta
        super.init(type, bubbles: bubbles)
    }
}

/// A text control's value changed by the user.
public final class InputEvent: Event {
    /// The control's value after the change.
    public let Value: string
    /// What was typed, where something was.
    public let Data: string

    public init(type: string, Value: string, Data: string = "") {
        self.Value = Value
        self.Data = Data
        super.init(type)
    }
}

/// A key, as the W3C names keys and codes, and the modifiers held with it.
public final class KeyboardEvent: Event {
    public let Key: string
    public let Code: string
    public let Shift: bool
    public let Control: bool
    public let Alt: bool
    /// Command on a Mac, the Windows key elsewhere.
    public let Meta: bool
    /// Whether the key is held and repeating.
    public let Repeat: bool
    /// Whether an input method is composing text: the key is its.
    public let IsComposing: bool

    public init(type: string, Key: string, Code: string, Shift: bool = false, Control: bool = false, Alt: bool = false,
                Meta: bool = false, Repeat: bool = false, IsComposing: bool = false) {
        self.Key = Key
        self.Code = Code
        self.Shift = Shift
        self.Control = Control
        self.Alt = Alt
        self.Meta = Meta
        self.Repeat = Repeat
        self.IsComposing = IsComposing
        super.init(type)
    }
}

/// A form about to be submitted.
public final class SubmitEvent: Event {
    /// The button that submitted it, where one did.
    public let Submitter: html.Node?

    public init(type: string, Submitter: html.Node?) {
        self.Submitter = Submitter
        super.init(type)
    }
}

/// A popover or details opening or closing: beforetoggle and toggle,
/// with the state it leaves ("open" or "closed") and the one it takes.
public final class ToggleEvent: Event {
    public let OldState: string
    public let NewState: string

    public init(type: string, OldState: string, NewState: string) {
        self.OldState = OldState
        self.NewState = NewState
        super.init(type, bubbles: false)
    }
}

/// A transition starting, ending or cancelled: transitionrun,
/// transitionstart, transitionend, transitioncancel.
public final class TransitionEvent: Event {
    public let PropertyName: string
    /// Seconds the transition had run, not counting its delay.
    public let ElapsedTime: float64

    public init(type: string, PropertyName: string, ElapsedTime: float64) {
        self.PropertyName = PropertyName
        self.ElapsedTime = ElapsedTime
        super.init(type)
    }
}

/// An animation starting, repeating, ending or cancelled:
/// animationstart, animationiteration, animationend, animationcancel.
public final class AnimationEvent: Event {
    public let AnimationName: string
    public let ElapsedTime: float64

    public init(type: string, AnimationName: string, ElapsedTime: float64) {
        self.AnimationName = AnimationName
        self.ElapsedTime = ElapsedTime
        super.init(type)
    }
}

/// Focus coming to or leaving an element. focus and blur do not bubble.
public final class FocusEvent: Event {
    public init(type: string) {
        super.init(type, bubbles: false)
    }
}

/// The events of other kinds this document knows by name: pointer (a
/// MouseEvent, as the DOM has it), wheel, composition, drag, and an
/// element's box changing size.
public final class PointerEvent: MouseEvent {
    /// "mouse", "pen" or "touch", and the pointer's id; the first pointer
    /// of its kind is the primary one.
    public let PointerType: string
    public let PointerId: int32
    public let IsPrimary: bool
    /// How hard it presses, 0 to 1 (0.5 for a mouse button held), and a
    /// pen's tilt in degrees.
    public let Pressure: float32
    public let TiltX: float32
    public let TiltY: float32

    public override init(type: string, X: float32 = 0, Y: float32 = 0, Clicks: int32 = 1, Button: int32 = 0, Pressed: bool = false,
                         Shift: bool = false, Control: bool = false, Alt: bool = false, Meta: bool = false, bubbles: bool = true) {
        let p = CurrentPointer
        PointerType = p.Kind
        PointerId = p.Id
        IsPrimary = p.Id <= 1
        Pressure = p.Pressure >= 0 ? p.Pressure : (Pressed || type == "pointerdown" ? 0.5 : 0)
        TiltX = p.TiltX
        TiltY = p.TiltY
        super.init(type, X: X, Y: Y, Clicks: Clicks, Button: Button, Pressed: Pressed,
                   Shift: Shift, Control: Control, Alt: Alt, Meta: Meta, bubbles: bubbles)
    }
}

/// What the pointer is, as the host last said: the page sets it from the
/// input it is handling, and pointer events read it.
public struct PointerInfo {
    public var Kind: string = "mouse"
    public var Id: int32 = 1
    /// -1 where the device doesn't say.
    public var Pressure: float32 = -1
    public var TiltX: float32 = 0
    public var TiltY: float32 = 0

    public init() {}
}

public var CurrentPointer = PointerInfo()

/// The data a drag carries, by type ("text/plain", "text/uri-list",
/// "text/html", or the page's own), and what may be done with it.
public final class DataTransfer {
    var items: [(type: string, data: string)] = []
    /// copy, move, link (or none) -- what the drop target says it will do,
    /// and what the source allows ("all", "copyMove", …).
    public var DropEffect: string = "none"
    public var EffectAllowed: string = "uninitialized"
    /// Paths of files dropped from outside the page.
    public var Files: [string] = []

    public init() {}

    public var Types: [string] { return items.map { $0.type } }

    public func SetData(type: string, data: string) {
        let t = type.lowercased() == "text" ? "text/plain" : type.lowercased()
        items.removeAll(where: { $0.type == t })
        items.append((type: t, data: data))
    }

    public func GetData(type: string) -> string {
        let t = type.lowercased() == "text" ? "text/plain" : type.lowercased()
        for i in items where i.type == t { return i.data }
        return ""
    }

    public func ClearData(type: string? = nil) {
        if let t = type { items.removeAll(where: { $0.type == t.lowercased() }) } else { items = [] }
    }
}

/// A drag: dragstart, drag and dragend at what is dragged; dragenter,
/// dragover, dragleave and drop at what it is over.
public final class DragEvent: MouseEvent {
    public let Data: DataTransfer

    public init(type: string, X: float32, Y: float32, Data: DataTransfer, bubbles: bool = true) {
        self.Data = Data
        super.init(type, X: X, Y: Y, Clicks: 0, Button: 0, Pressed: type != "dragend" && type != "drop", bubbles: bubbles)
    }
}
public final class WheelEvent: Event {
    /// Where the pointer is, in CSS pixels from the viewport's corner.
    public let X: float32
    public let Y: float32
    /// How far, in CSS pixels; positive DeltaY scrolls down (the DOM's sense).
    public let DeltaX: float32
    public let DeltaY: float32
    /// The modifier keys held.
    public let Shift: bool
    public let Control: bool
    public let Alt: bool
    public let Meta: bool

    public init(type: string, X: float32 = 0, Y: float32 = 0, DeltaX: float32 = 0, DeltaY: float32 = 0,
                Shift: bool = false, Control: bool = false, Alt: bool = false, Meta: bool = false) {
        self.X = X
        self.Y = Y
        self.DeltaX = DeltaX
        self.DeltaY = DeltaY
        self.Shift = Shift
        self.Control = Control
        self.Alt = Alt
        self.Meta = Meta
        super.init(type)
    }
}
/// An input method composing text: compositionstart, then a
/// compositionupdate with each change to what it has, then
/// compositionend with what it committed.
public final class CompositionEvent: Event {
    /// The text being composed (compositionupdate) or committed
    /// (compositionend).
    public let Data: string

    public init(type: string, Data: string = "") {
        self.Data = Data
        super.init(type)
    }
}
public final class LayoutEvent: Event {}

/// A listener's handle, for removing it.
public struct ListenerID: Equatable {
    let value: int
}

struct listener {
    let id: int
    let type: string
    let handler: (Event) -> void
    /// Called as the event comes down to its target, not as it bubbles.
    let capture: bool
}

extension Document {
    /// Calls handler with each event of a type dispatched to node or,
    /// bubbling, to any element inside it.
    /// `capture`: called as the event comes down to an element inside node,
    /// before that element's own listeners, rather than as it bubbles.
    public func AddEventListener(node: html.Node, type: string, capture: bool = false, handler: (Event) -> void) -> ListenerID {
        nextListener += 1
        var list = listeners[node.Id] ?? []
        list.append(listener(id: nextListener, type: type, handler: handler, capture: capture))
        listeners[node.Id] = list
        return ListenerID(value: nextListener)
    }

    /// Removes one listener.
    public func RemoveEventListener(node: html.Node, id: ListenerID) {
        guard let list = listeners[node.Id] else { return }
        var kept: [listener] = []
        for l in list where l.id != id.value { kept.append(l) }
        listeners[node.Id] = kept.isEmpty ? nil : kept
    }

    /// Removes every listener of node and of everything inside it: what
    /// taking a subtree out of the document for good does.
    public func RemoveEventListeners(within node: html.Node) {
        if listeners.isEmpty { return }
        listeners[node.Id] = nil
        for c in node.Children { RemoveEventListeners(within: c) }
    }

    /// Whether any listener is registered: a document with none costs a
    /// dispatch nothing.
    public var HasEventListeners: bool { return !listeners.isEmpty }

    /// Dispatches an event to target as the DOM does: the capturing
    /// listeners of its ancestors, outermost first; its own; then, where
    /// the event bubbles, the other listeners of each ancestor -- until one
    /// stops it. Answers whether the default action should be taken -- no
    /// listener prevented it.
    public func Dispatch(event: Event, to target: html.Node) -> bool {
        event.Target = target
        if listeners.isEmpty { return true }
        var path: [html.Node] = []
        var cur: html.Node? = target
        while let n = cur {
            path.append(n)
            cur = n.Parent
        }
        // Capturing, from the outermost ancestor down to the target's parent.
        event.Phase = 1
        var i = path.count - 1
        while i >= 1 && !event.stopped {
            run(event, at: path[i], capture: true)
            i -= 1
        }
        // At the target: its capturing listeners, then the others.
        if !event.stopped {
            event.Phase = 2
            run(event, at: target, capture: nil)
        }
        // Bubbling, up from the target's parent.
        if event.Bubbles {
            event.Phase = 3
            i = 1
            while i < path.count && !event.stopped {
                run(event, at: path[i], capture: false)
                i += 1
            }
        }
        event.Phase = 0
        event.CurrentTarget = nil
        return !event.DefaultPrevented
    }

    /// Calls node's listeners for the event: the capturing ones, the
    /// others, or (capture nil, at the target) the capturing then the others.
    func run(event: Event, at node: html.Node, capture: bool?) {
        guard let list = listeners[node.Id] else { return }
        event.CurrentTarget = node
        for pass in capture == nil ? [true, false] : [capture!] {
            for l in list where l.type == event.Type && l.capture == pass {
                l.handler(event)
                if event.stoppedImmediately { return }
            }
        }
    }
}
