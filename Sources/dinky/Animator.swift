import AppKit
import DinkyLayout

// Glides windows to their tiles. Each window rides a spring from where it is to its tile, stepped on every frame
// of the main display and written through the applier's per-app queues without readback. Once a tree's windows
// have arrived, its pass finishes as an unanimated one would: the full write with readback, retry and raises.
// A new pass mid-flight retargets the springs, so windows curve to their new tiles instead of restarting.
// Main thread only.
final class Animator: NSObject {
    private struct Entry {
        var animation: FrameAnimation
        let pid: pid_t
        var key: UInt64
    }

    private let applier: FrameApplier
    private var entries: [WindowID: Entry] = [:]
    /// By tree, the rest of its latest pass, run once its windows have arrived.
    private var finishes: [UInt64: () -> Void] = [:]
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var spring = Spring(response: 0.05, damping: 0.9)
    private var timeout = 1.0
    /// Where windows came to rest the last time they were written unanimated, by the frame they were asked for.
    /// An app that snaps to a grid (Terminal) or keeps a minimum size never reaches its tile exactly, and
    /// must not be sent gliding towards it on every pass.
    private var landed: [WindowID: (asked: CGRect, got: CGRect)] = [:]
    /// Called with the windows that just arrived.
    var onArrive: ([WindowID]) -> Void = { _ in }

    init(applier: FrameApplier) {
        self.applier = applier
    }

    /// How long a window takes to arrive, roughly.
    func setDuration(ms: Int) {
        let response = Double(ms) / 1000
        spring = Spring(response: response, damping: 0.9)
        timeout = max(1, 4 * response)
    }

    /// Whether dinky is moving the window right now, so its frame changes are not the user's.
    func isAnimating(_ id: WindowID) -> Bool { entries[id] != nil }

    /// The windows moving now.
    var animating: [WindowID] { Array(entries.keys) }

    /// Move the tree's windows from `starts` to `targets`, then run `finish`. Windows already there, or with
    /// no start, are left to `finish`; with none left to move, it runs at once.
    func animate(_ key: UInt64, from starts: [WindowID: CGRect], to targets: [WindowID: CGRect],
                 pids: [WindowID: pid_t], then finish: @escaping () -> Void) {
        for (id, entry) in entries where entry.key == key && targets[id] == nil { entries[id] = nil }
        for (id, target) in targets {
            if entries[id] != nil {
                entries[id]!.animation.retarget(target)
                entries[id]!.key = key
            } else if let start = starts[id], let pid = pids[id], !isResting(id, at: start, for: target) {
                entries[id] = Entry(animation: FrameAnimation(from: start, to: target), pid: pid, key: key)
            }
        }
        finishes[key] = finish
        finishArrived()
        if !entries.isEmpty { run() }
    }

    /// Whether a window at `start` is as close to `target` as it gets: on it, or where it came to rest when last asked for it.
    private func isResting(_ id: WindowID, at start: CGRect, for target: CGRect) -> Bool {
        if start.isClose(to: target, within: 1) { return true }
        guard let landed = landed[id], landed.asked == target else { return false }
        return start.isClose(to: landed.got, within: 1)
    }

    /// Note where written windows came to rest.
    func noteLanded(_ results: [FrameResult]) {
        for result in results { landed[result.job.id] = result.got.map { (result.job.frame, $0) } }
    }

    /// Forgets a window that is gone, so a new window given its id starts fresh.
    func forget(_ id: WindowID) {
        entries[id] = nil
        landed[id] = nil
    }

    /// Stops every animation where it is. Nothing is finished.
    func cancel() {
        entries = [:]
        finishes = [:]
        link?.isPaused = true
        lastTick = nil
    }

    private func run() {
        if link == nil {
            link = (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        // A stalled clock (sleep, a busy main thread) resumes where it was rather than leaping ahead.
        let dt = min(lastTick.map { link.timestamp - $0 } ?? link.duration, 1.0 / 30)
        lastTick = link.timestamp
        var jobs: [FrameJob] = [], arrived: [WindowID] = []
        for (id, entry) in entries {
            let done = entries[id]!.animation.step(spring, dt: dt, timeout: timeout)
            jobs.append(FrameJob(pid: entry.pid, id: id, frame: entries[id]!.animation.frame))
            if done { entries[id] = nil; arrived.append(id) }
        }
        applier.step(jobs)
        if !arrived.isEmpty { onArrive(arrived) }
        finishArrived()
        if entries.isEmpty {
            link.isPaused = true
            lastTick = nil
        }
    }

    /// Finish every tree none of whose windows is still moving.
    private func finishArrived() {
        let moving = Set(entries.values.map(\.key))
        for (key, finish) in finishes where !moving.contains(key) {
            finishes[key] = nil
            finish()
        }
    }
}
