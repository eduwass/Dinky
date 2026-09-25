import CoreGraphics
import Foundation

/// A frame to write: a window, the process that owns it and where it should go (top-left origin).
public struct FrameJob: Equatable, Sendable {
    public var pid: Int32
    public var id: WindowID
    public var frame: CGRect

    public init(pid: Int32, id: WindowID, frame: CGRect) {
        self.pid = pid
        self.id = id
        self.frame = frame
    }
}

/// What a window ended up at after a write.
public struct FrameResult: Equatable, Sendable {
    public var job: FrameJob
    /// The frame read back, nil when the window could not be read.
    public var got: CGRect?
    /// False when the window was already in place and nothing was written.
    public var written = false
    /// True when the first write landed elsewhere and it was written once more.
    public var retried = false

    /// Landed within 2 pt on every edge.
    public var matched: Bool { got.map { $0.isClose(to: job.frame, within: 2) } ?? false }
}

/// Schedules frame writes: one serial queue per process so a slow app only stalls itself,
/// the newest frame per window wins, and a window that refuses its frame is written at most twice.
/// The actual reads and writes are injected, so this is testable without Accessibility.
public final class FrameScheduler: @unchecked Sendable {
    public typealias Completion = ([FrameResult]) -> Void

    private let settle: TimeInterval
    private let prepare: (Int32) -> Void
    private let read: (FrameJob) -> CGRect?
    private let write: (FrameJob) -> Void

    private let lock = NSLock()
    private var apps: [Int32: App] = [:]
    private var minimums: [WindowID: CGSize] = [:]
    /// Bumped by `cancel`; writes queued under an older generation are dropped.
    private var generation = 0

    /// `prepare` runs once per process before its first write; `read` and `write` run on that process's queue.
    public init(settle: TimeInterval = 0.1, prepare: @escaping (Int32) -> Void = { _ in },
                read: @escaping (FrameJob) -> CGRect?, write: @escaping (FrameJob) -> Void) {
        self.settle = settle
        self.prepare = prepare
        self.read = read
        self.write = write
    }

    /// Sizes windows refused to go below, observed on readback. Only dimensions that were refused are set.
    public var minimumSizes: [WindowID: CGSize] { lock.withLock { minimums } }

    /// Queue frames. `completion` gets the results of every process queue these jobs went to,
    /// once each has written them (or newer frames for the same windows).
    public func submit(_ jobs: [FrameJob], completion: Completion? = nil) {
        let byPid = Dictionary(grouping: jobs, by: \.pid)
        guard !byPid.isEmpty else { completion?([]); return }
        let batch = Batch(waiting: byPid.count, completion)
        lock.withLock {
            for (pid, jobs) in byPid {
                let app = apps[pid] ?? App(pid)
                apps[pid] = app
                for job in jobs {
                    if let i = app.pending.firstIndex(where: { $0.id == job.id }) { app.pending[i] = job } else { app.pending.append(job) }
                }
                app.batches.append(batch)
                if !app.scheduled {
                    app.scheduled = true
                    app.queue.async { self.drain(app) }
                }
            }
        }
    }

    /// Drops every frame not written yet, including a second try already under way. Completions still run,
    /// with the results of what was written.
    public func cancel() {
        lock.withLock {
            generation += 1
            for app in apps.values { app.pending = [] }
        }
    }

    /// Take everything pending for one process and write it. Runs on the process's queue.
    private func drain(_ app: App) {
        let (jobs, batches, needsPrepare, generation) = lock.withLock {
            defer { app.pending = []; app.batches = []; app.scheduled = false; app.prepared = true }
            return (app.pending, app.batches, !app.prepared, self.generation)
        }
        if needsPrepare { prepare(app.pid) }
        let results = run(jobs) { self.lock.withLock { self.generation } == generation }
        for batch in batches { batch.report(results) }
    }

    /// Write, settle, read back; write the misses once more, settle, read back again. Writes only while `live`.
    private func run(_ jobs: [FrameJob], live: () -> Bool) -> [FrameResult] {
        var results = jobs.map { job in
            let current = read(job)
            let write = live() && !(current?.isClose(to: job.frame, within: 1) ?? false)
            if write { self.write(job) }
            return FrameResult(job: job, got: current, written: write)
        }
        let written = results.indices.filter { results[$0].written }
        guard !written.isEmpty else { return results }
        wait()
        for i in written { results[i].got = read(results[i].job) }

        // Only windows that answered and landed elsewhere; an unreadable (possibly hung) one is not worth a second try.
        let misses = written.filter { results[$0].got != nil && !results[$0].matched }
        guard !misses.isEmpty, live() else { return results }
        for i in misses {
            write(results[i].job)
            results[i].retried = true
        }
        wait()
        for i in misses {
            results[i].got = read(results[i].job)
            recordMinimum(results[i])
        }
        return results
    }

    private func wait() {
        if settle > 0 { Thread.sleep(forTimeInterval: settle) }
    }

    /// A window that came back larger than asked has shown a minimum size in that dimension.
    private func recordMinimum(_ result: FrameResult) {
        guard let got = result.got else { return }
        let wanted = result.job.frame.size
        let minimum = CGSize(width: got.width > wanted.width + 2 ? got.width : 0,
                             height: got.height > wanted.height + 2 ? got.height : 0)
        guard minimum != .zero else { return }
        lock.withLock { minimums[result.job.id] = minimum }
    }

    /// One process's queue and what is waiting on it. Guarded by the scheduler's lock.
    private final class App {
        let pid: Int32
        let queue: DispatchQueue
        var pending: [FrameJob] = []
        var batches: [Batch] = []
        var scheduled = false
        var prepared = false

        init(_ pid: Int32) {
            self.pid = pid
            self.queue = DispatchQueue(label: "dinky.frames.\(pid)")
        }
    }

    /// Collects results from each process queue a submit went to, then calls its completion.
    private final class Batch {
        private let lock = NSLock()
        private var waiting: Int
        private var results: [FrameResult] = []
        private let completion: Completion?

        init(waiting: Int, _ completion: Completion?) {
            self.waiting = waiting
            self.completion = completion
        }

        func report(_ new: [FrameResult]) {
            let done: [FrameResult]? = lock.withLock {
                results += new
                waiting -= 1
                return waiting == 0 ? results : nil
            }
            if let done { completion?(done) }
        }
    }
}

extension CGRect {
    /// Every edge within `tolerance` points of the other rect's.
    public func isClose(to other: CGRect, within tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance &&
            abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
