package web

import (
    "image/draw"
    "web/dom"
    "web/html"
    "web/layout"
    "web/paint"
)

// <video> and <audio>: what the engine keeps of them. It decodes nothing:
// a host hands it players (Page.SetMediaOpener), and it runs what the HTML
// standard asks around them -- which source is used, autoplay, muted and
// loop, the events, :playing and :paused, the controls and the frames.

/// One loaded media resource, playing on the host's terms. Frame answers
/// the newest picture when there is one the page hasn't seen, else nil.
public protocol MediaPlayer: AnyObject {
    var Ready: bool { get }
    var Failed: bool { get }
    var Paused: bool { get }
    var Ended: bool { get }
    /// Seconds; 0 until known.
    var Duration: float64 { get }
    var CurrentTime: float64 { get }
    /// The picture's size in pixels; 0 for audio.
    var VideoWidth: int32 { get }
    var VideoHeight: int32 { get }
    func Play()
    func Pause()
    func Seek(to seconds: float64)
    func SetVolume(volume: float32)
    func SetMuted(muted: bool)
    func SetLoop(loop: bool)
    func Frame() -> draw.Image?
    func Close()
}

/// What the page knows of an element's player, to tell what changed.
final class MediaState {
    let node: html.Node
    let player: any MediaPlayer
    /// The URL it was opened for.
    let source: string
    var ready = false
    var failed = false
    var paused = true
    var ended = false
    var lastTime: float64 = -1
    var lastReported: float64 = -1
    /// Where a seek is going, -1 for none; when a playing element's time last
    /// moved, for :buffering and :stalled.
    var seekingTo: float64 = -1
    var movedAt: float64 = -1

    init(node: html.Node, player: any MediaPlayer, source: string) {
        self.node = node
        self.player = player
        self.source = source
    }
}

extension Page {
    /// Where players come from. A page with none shows posters and bars
    /// at rest, as it did before a host could play them.
    public func SetMediaOpener(opener: (string) -> (any MediaPlayer)?) {
        mediaOpener = opener
        if let doc = Document { syncMedia(doc.Tree) }
    }

    /// The URL an element plays: its src, or the first <source>'s.
    func mediaSource(node: html.Node) -> string? {
        if let src = node.GetAttribute("src") { return src }
        for c in node.Children where c.TagName == "source" {
            if let src = c.GetAttribute("src") { return src }
        }
        return nil
    }

    /// Gives every media element in the document its player, whenever
    /// markup comes or goes: one whose source changed starts again, and one
    /// that has left is closed.
    func syncMedia(doc: html.Document) {
        guard let opener = mediaOpener else { return }
        var kept = Set<int64>()
        for tag in ["video", "audio"] {
            for n in doc.ElementsByTagName(tag) {
                guard let src = mediaSource(n) else { continue }
                kept.insert(n.Id)
                let url = Resolve(src)
                if let m = media[n.Id] {
                    if m.source == url { continue }
                    m.player.Close()
                    media[n.Id] = nil
                    mediaFrames[n.Id] = nil
                    context.Playing.remove(n.Id)
                }
                if mediaRefused[n.Id] == url { continue }
                guard let player = opener(url) else {
                    mediaRefused[n.Id] = url
                    mediaErrors.append(n)
                    continue
                }
                player.SetMuted(n.HasAttribute("muted"))
                player.SetLoop(n.HasAttribute("loop"))
                media[n.Id] = MediaState(node: n, player: player, source: url)
            }
        }
        for (id, m) in media where !kept.contains(id) {
            m.player.Close()
            media[id] = nil
            mediaFrames[id] = nil
            context.Playing.remove(id)
        }
    }

    func closeMedia() {
        for (_, m) in media { m.player.Close() }
        media = [:]
        mediaFrames = [:]
        mediaRefused = [:]
        mediaErrors = []
        context.Playing = Set<int64>()
    }

    /// Whether a media element is playing: what keeps frames coming.
    var mediaPlaying: bool {
        if !mediaErrors.isEmpty { return true }
        for (_, m) in media where !m.player.Paused { return true }
        for (_, m) in media where !m.ready && !m.failed { return true }
        return false
    }

    func dispatchMedia(type: string, to node: html.Node) -> bool {
        return dispatch(dom.Event(type, bubbles: false), to: node)
    }

    /// Starts an element playing, from the start where it had ended.
    public func PlayMedia(node: html.Node) {
        guard let m = media[node.Id] else { return }
        if m.player.Ended { m.player.Seek(to: 0) }
        m.player.Play()
    }

    public func PauseMedia(node: html.Node) {
        media[node.Id]?.player.Pause()
    }

    public func SeekMedia(node: html.Node, to seconds: float64) {
        guard let m = media[node.Id] else { return }
        m.player.Seek(to: seconds)
        m.seekingTo = seconds
        context.MediaSeeking.insert(node.Id)
        needsStyle = true
    }

    public func SetMediaVolume(node: html.Node, volume: float32) {
        media[node.Id]?.player.SetVolume(volume)
    }

    public func MediaTime(node: html.Node) -> float64 {
        return media[node.Id]?.player.CurrentTime ?? 0
    }

    public func MediaDuration(node: html.Node) -> float64 {
        return media[node.Id]?.player.Duration ?? 0
    }

    public func MediaPaused(node: html.Node) -> bool {
        return media[node.Id]?.player.Paused ?? true
    }

    /// Reads each player: the changes as events, a new picture as a repaint.
    func advanceMedia(time: float64 = 0) -> bool {
        var repaint = false
        let refused = mediaErrors
        mediaErrors = []
        for n in refused { _ = dispatchMedia("error", to: n) }
        for (id, m) in media {
            let p = m.player
            if p.Failed && !m.failed {
                m.failed = true
                _ = dispatchMedia("error", to: m.node)
                continue
            }
            if p.Ready && !m.ready {
                m.ready = true
                if p.VideoWidth > 0 && p.VideoHeight > 0 {
                    needsStyle = true
                    needsLayout = true
                }
                _ = dispatchMedia("loadedmetadata", to: m.node)
                _ = dispatchMedia("canplay", to: m.node)
                _ = dispatchMedia("load", to: m.node)
                if m.node.HasAttribute("autoplay") { p.Play() }
            }
            if p.Paused != m.paused {
                m.paused = p.Paused
                if m.paused { context.Playing.remove(id) } else { context.Playing.insert(id) }
                needsStyle = true
                needsPaint = true
                repaint = true
                // A pause at the end is ended's, which comes after it.
                _ = dispatchMedia(m.paused ? "pause" : "play", to: m.node)
                if !m.paused { _ = dispatchMedia("playing", to: m.node) }
            }
            if p.Ended != m.ended {
                m.ended = p.Ended
                if m.ended { _ = dispatchMedia("ended", to: m.node) }
            }
            let t = p.CurrentTime
            // A seek has landed when the time has got there.
            if m.seekingTo >= 0 && (p.CurrentTime - m.seekingTo < 0.05 && m.seekingTo - p.CurrentTime < 0.05) {
                m.seekingTo = -1
                context.MediaSeeking.remove(id)
                needsStyle = true
                repaint = true
            }
            // Playing, with time standing still: waiting for data.
            if p.Paused || t != m.lastTime { m.movedAt = time }
            let waited = time - m.movedAt
            let buffering = (!p.Paused && !p.Ended && waited > 0.5) || (!p.Ready && !p.Failed)
            let stalled = !p.Paused && !p.Ended && waited > 3
            if buffering != context.MediaBuffering.contains(id) || stalled != context.MediaStalled.contains(id) {
                if buffering { context.MediaBuffering.insert(id) } else { context.MediaBuffering.remove(id) }
                if stalled { context.MediaStalled.insert(id) } else { context.MediaStalled.remove(id) }
                needsStyle = true
                repaint = true
            }
            if t != m.lastTime {
                m.lastTime = t
                // The bar shows it.
                if m.node.HasAttribute("controls") {
                    needsPaint = true
                    repaint = true
                }
                // Four times a second, as browsers do.
                if t < m.lastReported || t - m.lastReported >= 0.25 {
                    m.lastReported = t
                    _ = dispatchMedia("timeupdate", to: m.node)
                }
            }
            if let frame = p.Frame() {
                mediaFrames[id] = frame
                needsPaint = true
                repaint = true
            }
        }
        return repaint
    }

    /// A click on a media element's controls: the button plays and pauses,
    /// the track seeks. Answers whether it was on them.
    func clickMediaControls(node: html.Node, at p: draw.Point) -> bool {
        guard node.HasAttribute("controls"), let m = media[node.Id], let box = builder.byNode[node.Id] else { return false }
        let at = layout.PagePosition(box)
        let bar = paint.MediaBar(box, x: at.x, y: at.y)
        if !bar.Contains(p.X, p.Y) { return false }
        let track = paint.MediaTrack(bar)
        if p.X >= track.X && m.player.Duration > 0 {
            let k = (p.X - track.X) / track.Width
            m.player.Seek(to: float64(k < 0 ? 0 : (k > 1 ? 1 : k)) * m.player.Duration)
        } else if m.player.Paused {
            PlayMedia(node)
        } else {
            m.player.Pause()
        }
        return true
    }
}
