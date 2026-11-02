package web

import (
    "web/cascade"
    "web/dom"
    "web/html"
)

// CSS Transitions 1 and Animations 1. The cascade hands every element's
// settled style to Animator.apply (StyleResolver.Animate): it starts a
// transition where a property's own value changed, keeps @keyframes
// animations by name, and writes their values at the page's time into
// the style before the children inherit. While anything runs, each frame
// restyles the page (Page.Advance).

/// A transition of one property of one element.
struct RunningTransition {
    var prop: cascade.AnimatableProperty
    var from: cascade.AnimValue
    var to: cascade.AnimValue
    /// When it began, in the page's seconds; -1 until the next frame.
    var start: float64
    var delay: float64
    var duration: float64
    var easing: cascade.Easing
    var started: bool = false

    func valueAt(now: float64) -> cascade.AnimValue {
        if start < 0 { return from }
        let t = now - start - delay
        if t <= 0 { return from }
        if t >= duration { return to }
        return cascade.Interpolate(from, to, easing.Progress(float32(t / duration)))
    }

    func done(now: float64) -> bool { return start >= 0 && now - start >= delay + duration }
}

/// A @keyframes animation running on an element.
final class RunningAnimation {
    let name: string
    var index: int
    var start: float64 = -1
    var pausedAt: float64 = -1
    var duration: float64 = 0
    var delay: float64 = 0
    var count: float64 = 1
    var direction: string = "normal"
    var fill: string = "none"
    var easing: cascade.Easing = cascade.Easing.ease
    /// The frames, each with its values for this element.
    var frames: [(offset: float32, values: [string: cascade.AnimValue], easing: cascade.Easing?)] = []
    var properties: [cascade.AnimatableProperty] = []
    var announcedStart = false
    var iteration: int64 = 0
    var ended = false
    /// animation-timeline, "auto" for time, and animation-range.
    var timeline: string = "auto"
    var range: string = "normal"

    init(name: string, index: int) {
        self.name = name
        self.index = index
    }

    /// The time it has been active, at now: negative in its delay.
    func activeTime(now: float64) -> float64 {
        if start < 0 { return -delay }
        let at = pausedAt >= 0 ? pausedAt : now
        return at - start - delay
    }

    var total: float64 { return count < 0 ? 1e300 : duration * count }

    func finished(now: float64) -> bool { return start >= 0 && activeTime(now) >= total }

    /// The progress through the keyframes and the iteration at now; nil
    /// where nothing applies (before or after, without a fill there).
    func progress(now: float64) -> (p: float32, iteration: int64)? {
        let t = activeTime(now)
        var iterationProgress: float64 = 0
        var iteration: int64 = 0
        if t < 0 {
            if fill != "backwards" && fill != "both" { return nil }
        } else if t >= total {
            if fill != "forwards" && fill != "both" { return nil }
            if count < 0 { return nil }
            // The end of the last iteration: its 100%, or 0% where the
            // count stops partway.
            let whole = count - float64(int64(count))
            iteration = int64(count) - (whole == 0 && count > 0 ? 1 : 0)
            iterationProgress = whole == 0 ? 1 : whole
        } else if duration > 0 {
            let n = t / duration
            iteration = int64(n)
            iterationProgress = n - float64(iteration)
        }
        var forward = true
        switch direction {
        case "reverse": forward = false
        case "alternate": forward = iteration % 2 == 0
        case "alternate-reverse": forward = iteration % 2 == 1
        default: break
        }
        let p = forward ? iterationProgress : 1 - iterationProgress
        return (p: float32(p), iteration: iteration)
    }

    /// A property's value at progress p, with the element's own value
    /// (base) standing in for a 0% or 100% the keyframes leave out.
    func value(prop: cascade.AnimatableProperty, at p: float32, base: cascade.AnimValue) -> cascade.AnimValue {
        var stops: [(offset: float32, value: cascade.AnimValue, easing: cascade.Easing?)] = []
        for f in frames {
            if let v = f.values[prop.Name] { stops.append((offset: f.offset, value: v, easing: f.easing)) }
        }
        if stops.isEmpty || stops[0].offset > 0 { stops.insert((offset: 0, value: base, easing: nil), at: 0) }
        if stops[stops.count - 1].offset < 1 { stops.append((offset: 1, value: base, easing: nil)) }
        var i = 0
        while i + 1 < stops.count && stops[i + 1].offset <= p && !(p >= 1 && i + 2 == stops.count) { i += 1 }
        if i + 1 >= stops.count { return stops[stops.count - 1].value }
        let a = stops[i]
        let b = stops[i + 1]
        let span = b.offset - a.offset
        let local = span <= 0 ? 1 : (p - a.offset) / span
        let e = a.easing ?? easing
        return cascade.Interpolate(a.value, b.value, e.Progress(local))
    }
}

/// What the animator keeps for one element.
final class ElementAnimations {
    let node: html.Node
    var seen: int = 0
    /// Each transitionable property's value as the cascade last left it.
    var base: [string: cascade.AnimValue] = [:]
    var transitions: [string: RunningTransition] = [:]
    var animations: [RunningAnimation] = []

    init(node: html.Node) { self.node = node }
}

func isAutoLength(v: cascade.AnimValue) -> bool {
    if case .length(let l) = v { return l.IsAuto }
    return false
}

/// calc-size() on auto as the pixels it comes to, measured; nil for
/// anything else.
func autoCalcSize(v: cascade.AnimValue, node: html.Node, height: bool, measure: ((html.Node, bool) -> float32?)?) -> cascade.AnimValue? {
    guard case .length(let l) = v else { return nil }
    guard case .calcSize(let basis, let share, let px, let percent) = l else { return nil }
    if basis != "auto" || percent != 0 { return nil }
    guard let m = measure?(node, height) else { return nil }
    return .length(.px(share * m + px))
}

final class Animator {
    /// How big an element's auto height, or width, comes to.
    var measureAuto: ((html.Node, bool) -> float32?)? = nil
    /// How far along its timeline an element's animation is, 0 to 1, or
    /// past either end; nil where there's no such timeline.
    var timelineProgress: ((html.Node, string, string) -> float32?)? = nil
    /// What a transition starts from where an element first shows.
    var startingStyle: ((html.Node, cascade.ComputedStyle, cascade.ComputedStyle?) -> cascade.ComputedStyle?)? = nil
    /// The page's time, in seconds, as the host last gave it.
    var now: float64 = 0
    var elements: [int64: ElementAnimations] = [:]
    /// Each styled element's last style, for transitions that only the
    /// new style declares; dropped once the element leaves the document.
    var previous: [int64: cascade.ComputedStyle] = [:]
    var previousNodes: [int64: html.Node] = [:]
    var pass: int = 0
    var resolver: cascade.StyleResolver
    /// Events to dispatch once the frame's style is settled.
    var events: [(node: html.Node, event: dom.Event)] = []

    init(resolver: cascade.StyleResolver) {
        self.resolver = resolver
    }

    /// Whether anything is running or waiting to start.
    var Active: bool {
        for (_, e) in elements {
            if !e.transitions.isEmpty { return true }
            for a in e.animations where !a.ended && a.pausedAt < 0 && a.timeline == "auto" { return true }
        }
        return false
    }

    /// Whether an animation runs on a scroll's progress, not on time.
    var HasTimelines: bool {
        for (_, e) in elements {
            for a in e.animations where a.timeline != "auto" { return true }
        }
        return false
    }

    func beginPass() { pass += 1 }

    /// Forgets the elements a style pass didn't see: they're gone, or
    /// display: none, which cancels what ran on them.
    func endPass() {
        var gone: [int64] = []
        for (id, e) in elements where e.seen != pass {
            gone.append(id)
            for (name, t) in e.transitions where t.started {
                queue(e.node, dom.TransitionEvent("transitioncancel", PropertyName: name, ElapsedTime: 0))
            }
            for a in e.animations where a.announcedStart && !a.ended {
                queue(e.node, dom.AnimationEvent("animationcancel", AnimationName: a.name, ElapsedTime: 0))
            }
        }
        for id in gone { elements[id] = nil }
        // Styles of elements no longer in the document.
        var detached: [int64] = []
        for (id, n) in previousNodes where !connected(n) { detached.append(id) }
        for id in detached {
            previous[id] = nil
            previousNodes[id] = nil
        }
    }

    /// Whether a node is still in a document: its top ancestor is the
    /// document, or the root element (whose parent the tree leaves nil).
    func connected(n: html.Node) -> bool {
        var top = n
        while let p = top.Parent { top = p }
        return top.Kind == html.NodeKind.document || top.TagName == "html"
    }

    /// Moves to a frame's time: what was waiting starts, what is done
    /// ends. Answers whether anything is still running.
    func advance(time: float64) -> bool {
        now = time
        for (_, e) in elements {
            var finished: [string] = []
            for (name, running) in e.transitions {
                var t = running
                if t.start < 0 {
                    t.start = time
                    e.transitions[name] = t
                    queue(e.node, dom.TransitionEvent("transitionrun", PropertyName: name, ElapsedTime: 0))
                }
                if !t.started && time - t.start >= t.delay {
                    t.started = true
                    e.transitions[name] = t
                    queue(e.node, dom.TransitionEvent("transitionstart", PropertyName: name, ElapsedTime: 0))
                }
                if t.done(time) {
                    finished.append(name)
                    queue(e.node, dom.TransitionEvent("transitionend", PropertyName: name, ElapsedTime: t.duration))
                }
            }
            for name in finished { e.transitions[name] = nil }
            for a in e.animations {
                if a.timeline != "auto" { continue }
                if a.start < 0 { a.start = time }
                if a.ended || a.pausedAt >= 0 { continue }
                let t = a.activeTime(time)
                if t >= 0 && !a.announcedStart {
                    a.announcedStart = true
                    queue(e.node, dom.AnimationEvent("animationstart", AnimationName: a.name, ElapsedTime: 0))
                }
                if a.finished(time) {
                    a.ended = true
                    queue(e.node, dom.AnimationEvent("animationend", AnimationName: a.name, ElapsedTime: a.total))
                } else if t > 0 && a.duration > 0 {
                    let iteration = int64(t / a.duration)
                    if iteration > a.iteration {
                        a.iteration = iteration
                        queue(e.node, dom.AnimationEvent("animationiteration", AnimationName: a.name, ElapsedTime: float64(iteration) * a.duration))
                    }
                }
            }
        }
        return Active
    }

    /// The cascade's hook: an element's settled style, and its parent's.
    func apply(node: html.Node, style: cascade.ComputedStyle, parent: cascade.ComputedStyle?) {
        let spec = style.Transition
        let anims = style.Animation
        let known = elements[node.Id]
        // The style it had: what a transition the new style declares
        // starts from (the before-change style), even where the old one
        // declared none.
        var prior = previous[node.Id]
        // Showing for the first time, @starting-style says what it was.
        if prior == nil || prior!.Display == .none, style.Display != .none, let starting = startingStyle {
            if let s = starting(node, style, parent) {
                prior = s
                elements[node.Id]?.base = [:]
            }
        }
        previous[node.Id] = style
        previousNodes[node.Id] = node
        // Elements with nothing to run, and nothing running, cost nothing.
        if known == nil && !spec.Runs && !anims.HasAnimations { return }
        let e = known ?? ElementAnimations(node: node)
        let first = known == nil
        if first { elements[node.Id] = e }
        e.seen = pass
        updateTransitions(e, style, first: first, prior: prior)
        updateAnimations(e, style, parent)

        // Transitions, then animations over them.
        for (_, t) in e.transitions {
            cascade.SetAnimatedValue(t.prop.Prop, t.valueAt(now), on: style)
        }
        for a in e.animations {
            // On a timeline, the scroll says how far along it is.
            if a.timeline != "auto" {
                guard let raw = timelineProgress?(node, a.timeline, a.range) else { continue }
                if (raw < 0 && a.fill != "backwards" && a.fill != "both") || (raw > 1 && a.fill != "forwards" && a.fill != "both") { continue }
                var p = raw < 0 ? 0 : (raw > 1 ? 1 : raw)
                if a.direction == "reverse" { p = 1 - p }
                for prop in a.properties {
                    if let base = cascade.AnimatedValue(prop.Prop, of: style) {
                        cascade.SetAnimatedValue(prop.Prop, a.value(prop, at: p, base: base), on: style)
                    }
                }
                continue
            }
            if a.start < 0 && a.delay <= 0 && a.fill != "backwards" && a.fill != "both" {
                // Starting this frame: its 0% shows at once.
                for prop in a.properties {
                    if let base = cascade.AnimatedValue(prop.Prop, of: style) {
                        cascade.SetAnimatedValue(prop.Prop, a.value(prop, at: a.direction == "reverse" || a.direction == "alternate-reverse" ? 1 : 0, base: base), on: style)
                    }
                }
                continue
            }
            guard let pr = a.progress(now) else { continue }
            for prop in a.properties {
                if let base = cascade.AnimatedValue(prop.Prop, of: style) {
                    cascade.SetAnimatedValue(prop.Prop, a.value(prop, at: pr.p, base: base), on: style)
                }
            }
        }
        if e.transitions.isEmpty && e.animations.isEmpty && !spec.Runs { elements[node.Id] = nil }
    }

    func updateTransitions(e: ElementAnimations, style: cascade.ComputedStyle, first: bool, prior: cascade.ComputedStyle?) {
        let spec = style.Transition
        var covered: [string] = []
        var i = 0
        while i < spec.Properties.count {
            let name = spec.Properties[i]
            let duration = float64(cascade.Cycled(spec.Durations, i))
            let delay = float64(cascade.Cycled(spec.Delays, i))
            let easing = cascade.Cycled(spec.Timings, i)
            let discrete = cascade.Cycled(spec.Behaviors, i) == "allow-discrete"
            i += 1
            if name == "none" { continue }
            for prop in cascade.AnimatablePropertiesNamed(name) {
                if cascade.IsDiscreteProperty(prop.Prop) && !discrete { continue }
                guard let value = cascade.AnimatedValue(prop.Prop, of: style) else { continue }
                covered.append(prop.Name)
                var old = e.base[prop.Name]
                if old == nil, let p = prior { old = cascade.AnimatedValue(prop.Prop, of: p) }
                e.base[prop.Name] = value
                guard let before = old else { continue }
                if cascade.SameValue(before, value) { continue }
                if duration <= 0 && delay + duration <= 0 {
                    e.transitions[prop.Name] = nil
                    continue
                }
                // A change mid-transition starts from where it had got to.
                var from = before
                var to = value
                // interpolate-size: allow-keywords: auto as the size it is.
                if style.InterpolateKeywords && (prop.Prop == .width || prop.Prop == .height) {
                    if isAutoLength(from), let m = measureAuto?(e.node, prop.Prop == .height) { from = .length(.px(m)) }
                    if isAutoLength(to), let m = measureAuto?(e.node, prop.Prop == .height) { to = .length(.px(m)) }
                }
                // calc-size() on auto goes from and to the size it comes to,
                // whatever interpolate-size says.
                if prop.Prop == .width || prop.Prop == .height {
                    if let v = autoCalcSize(from, e.node, prop.Prop == .height, measureAuto) { from = v }
                    if let v = autoCalcSize(to, e.node, prop.Prop == .height, measureAuto) { to = v }
                }
                if let running = e.transitions[prop.Name] {
                    if cascade.SameValue(running.to, to) { continue }
                    from = running.valueAt(now)
                }
                e.transitions[prop.Name] = RunningTransition(prop: prop, from: from, to: to, start: -1,
                                                             delay: delay, duration: duration, easing: easing)
            }
        }
        // Properties no longer listed stop where they are.
        var dropped: [string] = []
        for (name, _) in e.transitions where !covered.contains(name) { dropped.append(name) }
        for name in dropped {
            if let t = e.transitions[name], t.started {
                queue(e.node, dom.TransitionEvent("transitioncancel", PropertyName: name, ElapsedTime: 0))
            }
            e.transitions[name] = nil
            e.base[name] = nil
        }
    }

    func updateAnimations(e: ElementAnimations, style: cascade.ComputedStyle, parent: cascade.ComputedStyle?) {
        let spec = style.Animation
        var kept: [RunningAnimation] = []
        var i = 0
        while i < spec.Names.count {
            let name = spec.Names[i]
            let index = i
            i += 1
            if name == "none" { continue }
            guard let frames = resolver.Keyframes(name) else { continue }
            // The same name at the same place is the same animation.
            var a: RunningAnimation? = nil
            for old in e.animations where old.name == name && old.index == index { a = old }
            let anim = a ?? RunningAnimation(name: name, index: index)
            if a == nil {
                var props: [cascade.AnimatableProperty] = []
                for f in frames {
                    let values = resolver.KeyframeValues(f.Declarations, over: style, parent: parent)
                    anim.frames.append((offset: f.Offset, values: values, easing: f.Easing))
                    for ap in cascade.AnimatableProperties where values[ap.Name] != nil {
                        if !props.contains(where: { $0.Name == ap.Name }) { props.append(ap) }
                    }
                }
                anim.properties = props
            }
            anim.duration = float64(cascade.Cycled(spec.Durations, index))
            anim.delay = float64(cascade.Cycled(spec.Delays, index))
            anim.count = float64(cascade.Cycled(spec.Counts, index))
            anim.direction = cascade.Cycled(spec.Directions, index)
            anim.fill = cascade.Cycled(spec.FillModes, index)
            anim.easing = cascade.Cycled(spec.Timings, index)
            anim.timeline = cascade.Cycled(spec.Timelines, index)
            anim.range = cascade.Cycled(spec.Ranges, index)
            let paused = cascade.Cycled(spec.PlayStates, index) == "paused"
            if paused && anim.pausedAt < 0 {
                if anim.start < 0 { anim.start = now }
                anim.pausedAt = now
            } else if !paused && anim.pausedAt >= 0 {
                anim.start += now - anim.pausedAt
                anim.pausedAt = -1
            }
            kept.append(anim)
        }
        for old in e.animations where !kept.contains(where: { $0 === old }) {
            if old.announcedStart && !old.ended {
                queue(e.node, dom.AnimationEvent("animationcancel", AnimationName: old.name, ElapsedTime: 0))
            }
        }
        e.animations = kept
    }

    func queue(node: html.Node, event: dom.Event) {
        events.append((node: node, event: event))
    }

    func takeEvents() -> [(node: html.Node, event: dom.Event)] {
        let out = events
        events = []
        return out
    }
}
