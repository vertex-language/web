package dom

import "web/html"

/// An event dispatched to an element: what happened, where, and whether
/// a listener asked for the default action not to be taken. Listeners are
/// called at the target and then at each ancestor in turn -- the event
/// bubbles -- until one stops it.
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
    var stopped = false

    public init(_ type: string, bubbles: bool = true) {
        Type = type
        Bubbles = bubbles
    }

    /// Asks that what the engine would do after the event -- submit the
    /// form, toggle the box, follow the link -- not be done.
    public func PreventDefault() { DefaultPrevented = true }

    /// Stops the event going on to the listeners of further ancestors.
    public func StopPropagation() { stopped = true }
}

/// A pointer press and release on the same element, and its kin.
public final class MouseEvent: Event {
    /// Where, in CSS pixels from the viewport's corner.
    public let X: float32
    public let Y: float32
    public let Clicks: int32

    public init(_ type: string, X: float32 = 0, Y: float32 = 0, Clicks: int32 = 1, bubbles: bool = true) {
        self.X = X
        self.Y = Y
        self.Clicks = Clicks
        super.init(type, bubbles: bubbles)
    }
}

/// A text control's value changed by the user.
public final class InputEvent: Event {
    /// The control's value after the change.
    public let Value: string
    /// What was typed, where something was.
    public let Data: string

    public init(_ type: string, Value: string, Data: string = "") {
        self.Value = Value
        self.Data = Data
        super.init(type)
    }
}

/// A key, as the W3C names keys and codes.
public final class KeyboardEvent: Event {
    public let Key: string
    public let Code: string

    public init(_ type: string, Key: string, Code: string) {
        self.Key = Key
        self.Code = Code
        super.init(type)
    }
}

/// A form about to be submitted.
public final class SubmitEvent: Event {
    /// The button that submitted it, where one did.
    public let Submitter: html.Node?

    public init(_ type: string, Submitter: html.Node?) {
        self.Submitter = Submitter
        super.init(type)
    }
}

/// Focus coming to or leaving an element. focus and blur do not bubble.
public final class FocusEvent: Event {
    public init(_ type: string) {
        super.init(type, bubbles: false)
    }
}

/// The events of other kinds this document knows by name: pointer,
/// wheel, composition, drag, and an element's box changing size.
public final class PointerEvent: Event {}
public final class WheelEvent: Event {}
public final class CompositionEvent: Event {}
public final class DragEvent: Event {}
public final class LayoutEvent: Event {}

/// A listener's handle, for removing it.
public struct ListenerID: Equatable {
    let value: int
}

struct listener {
    let id: int
    let type: string
    let handler: (Event) -> void
}

extension Document {
    /// Calls handler with each event of a type dispatched to node or,
    /// bubbling, to any element inside it.
    public func AddEventListener(_ node: html.Node, _ type: string, _ handler: (Event) -> void) -> ListenerID {
        nextListener += 1
        var list = listeners[node.Id] ?? []
        list.append(listener(id: nextListener, type: type, handler: handler))
        listeners[node.Id] = list
        return ListenerID(value: nextListener)
    }

    /// Removes one listener.
    public func RemoveEventListener(_ node: html.Node, _ id: ListenerID) {
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

    /// Dispatches an event to target: its listeners, then each ancestor's,
    /// until one stops it. Answers whether the default action should be
    /// taken -- no listener prevented it.
    public func Dispatch(_ event: Event, to target: html.Node) -> bool {
        event.Target = target
        if listeners.isEmpty { return true }
        var cur: html.Node? = target
        while let n = cur {
            if let list = listeners[n.Id] {
                event.CurrentTarget = n
                for l in list where l.type == event.Type {
                    l.handler(event)
                }
                if event.stopped { break }
            }
            if !event.Bubbles { break }
            cur = n.Parent
        }
        event.CurrentTarget = nil
        return !event.DefaultPrevented
    }
}
