import CoreGraphics
import Foundation
import XCTest
@testable import DinkyLayout

/// A pretend window server: windows hold frames, some refuse widths below a minimum, writes can be held.
private final class FakeWindows: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [WindowID: CGRect] = [:]
    private var minWidths: [WindowID: CGFloat] = [:]
    private(set) var writes: [(WindowID, CGRect)] = []
    private(set) var prepared: [Int32] = []
    /// Writes to windows in here block until the semaphore is signalled.
    var holds: [WindowID: DispatchSemaphore] = [:]

    init(_ frames: [WindowID: CGRect] = [:], minWidths: [WindowID: CGFloat] = [:]) {
        self.frames = frames
        self.minWidths = minWidths
    }

    func writes(to id: WindowID) -> [CGRect] { lock.withLock { writes.filter { $0.0 == id }.map(\.1) } }

    func scheduler() -> FrameScheduler {
        FrameScheduler(
            settle: 0,
            prepare: { pid in self.lock.withLock { self.prepared.append(pid) } },
            read: { job in self.lock.withLock { self.frames[job.id] } },
            write: { job in
                self.holds[job.id]?.wait()
                self.lock.withLock {
                    self.writes.append((job.id, job.frame))
                    var frame = job.frame
                    frame.size.width = max(frame.width, self.minWidths[job.id] ?? 0)
                    self.frames[job.id] = frame
                }
            })
    }
}

private func job(_ pid: Int32, _ id: WindowID, _ x: CGFloat) -> FrameJob {
    FrameJob(pid: pid, id: id, frame: CGRect(x: x, y: 0, width: 100, height: 100))
}

private func submitAndWait(_ scheduler: FrameScheduler, _ jobs: [FrameJob], file: StaticString = #filePath, line: UInt = #line) -> [FrameResult] {
    let done = XCTestExpectation(description: "results")
    var results: [FrameResult] = []
    scheduler.submit(jobs) { results = $0; done.fulfill() }
    XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 2), .completed, file: file, line: line)
    return results.sorted { $0.job.id < $1.job.id }
}

final class FrameSchedulerTests: XCTestCase {
    func testWritesAndReadsBack() {
        let fake = FakeWindows()
        let results = submitAndWait(fake.scheduler(), [job(1, 10, 0), job(2, 20, 100)])
        XCTAssertEqual(results.map(\.matched), [true, true])
        XCTAssertEqual(results.map(\.written), [true, true])
        XCTAssertEqual(results.map(\.retried), [false, false])
        XCTAssertEqual(results.map(\.got), [job(1, 10, 0).frame, job(2, 20, 100).frame])
    }

    func testSkipsWindowAlreadyInPlaceWithinOnePoint() {
        let fake = FakeWindows([10: CGRect(x: 0.5, y: 0, width: 100, height: 100.5)])
        let results = submitAndWait(fake.scheduler(), [job(1, 10, 0)])
        XCTAssertEqual(results.map(\.written), [false])
        XCTAssertEqual(results.map(\.matched), [true])
        XCTAssertTrue(fake.writes(to: 10).isEmpty)
    }

    func testPreparesEachProcessOnce() {
        let fake = FakeWindows()
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0), job(1, 11, 100)])
        _ = submitAndWait(scheduler, [job(1, 10, 200), job(2, 20, 0)])
        XCTAssertEqual(fake.prepared.sorted(), [1, 2])
    }

    func testNewestFrameWinsWhileQueueIsBusy() {
        let fake = FakeWindows()
        let hold = DispatchSemaphore(value: 0)
        fake.holds[10] = hold
        let scheduler = fake.scheduler()
        let done = XCTestExpectation(description: "last batch")
        scheduler.submit([job(1, 10, 0)])
        Thread.sleep(forTimeInterval: 0.05)  // the queue is now stuck in window 10's write
        scheduler.submit([job(1, 10, 1), job(1, 11, 1)])
        scheduler.submit([job(1, 11, 2)])
        var last: [FrameResult] = []
        scheduler.submit([job(1, 10, 3), job(1, 11, 3)]) { last = $0; done.fulfill() }
        hold.signal()
        hold.signal()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(fake.writes(to: 10).map(\.minX), [0, 3])
        XCTAssertEqual(fake.writes(to: 11).map(\.minX), [3])
        XCTAssertEqual(last.map(\.job.frame.minX), [3, 3])
    }

    func testBusyAppDoesNotBlockOthers() {
        let fake = FakeWindows()
        let hold = DispatchSemaphore(value: 0)
        fake.holds[10] = hold
        let scheduler = fake.scheduler()
        scheduler.submit([job(1, 10, 0)])
        let results = submitAndWait(scheduler, [job(2, 20, 0)])
        XCTAssertEqual(results.map(\.matched), [true])
        XCTAssertTrue(fake.writes(to: 10).isEmpty)
        hold.signal()
    }

    func testCancelDropsQueuedFrames() {
        let fake = FakeWindows()
        let hold = DispatchSemaphore(value: 0)
        fake.holds[10] = hold
        let scheduler = fake.scheduler()
        let done = XCTestExpectation(description: "cancelled batch")
        scheduler.submit([job(1, 10, 0)])
        Thread.sleep(forTimeInterval: 0.05)  // the queue is now stuck in window 10's write
        var results: [FrameResult] = []
        scheduler.submit([job(1, 10, 1), job(1, 11, 1)]) { results = $0; done.fulfill() }
        scheduler.cancel()
        hold.signal()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(fake.writes(to: 10).map(\.minX), [0])
        XCTAssertTrue(fake.writes(to: 11).isEmpty)
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(submitAndWait(scheduler, [job(1, 11, 2)]).map(\.matched), [true])
    }

    func testCancelStopsTheSecondTry() {
        var writes = 0
        let scheduler = FrameScheduler(settle: 0.2, read: { _ in CGRect(x: 0, y: 0, width: 574, height: 100) },
                                       write: { _ in writes += 1 })
        let done = XCTestExpectation(description: "results")
        var results: [FrameResult] = []
        scheduler.submit([job(1, 10, 0)]) { results = $0; done.fulfill() }
        Thread.sleep(forTimeInterval: 0.1)  // the first write is done and settling
        scheduler.cancel()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(results.map(\.retried), [false])
    }

    func testCompletionWaitsForEveryProcess() {
        let fake = FakeWindows()
        let results = submitAndWait(fake.scheduler(), [job(1, 10, 0), job(2, 20, 0), job(3, 30, 0)])
        XCTAssertEqual(results.map(\.job.id), [10, 20, 30])
    }

    func testRefusedSizeIsRetriedOnceAndRecordedAsMinimum() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        let results = submitAndWait(scheduler, [job(1, 10, 0), job(1, 11, 100)])
        XCTAssertEqual(results.map(\.matched), [false, true])
        XCTAssertEqual(results.map(\.retried), [true, false])
        XCTAssertEqual(results[0].got?.width, 574)
        XCTAssertEqual(fake.writes(to: 10).count, 2)
        XCTAssertEqual(scheduler.minimumSizes, [10: CGSize(width: 574, height: 0)])
    }

    func testTwoRefusalsInOnePassCompleteOnceWithBothMinimums() {
        let fake = FakeWindows(minWidths: [10: 574, 20: 115])
        let scheduler = fake.scheduler()
        var completions = 0
        var minimums: [WindowID: CGSize] = [:]
        let done = XCTestExpectation(description: "results")
        scheduler.submit([job(1, 10, 0), job(2, 20, 100), job(2, 21, 200)]) { _ in
            completions += 1
            minimums = scheduler.minimumSizes
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(minimums, [10: CGSize(width: 574, height: 0), 20: CGSize(width: 115, height: 0)])
    }

    func testRecordedMinimumIsNotWrittenAgain() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        let again = submitAndWait(scheduler, [job(1, 10, 0)])
        XCTAssertEqual(fake.writes(to: 10).count, 2)
        XCTAssertEqual(again.map(\.written), [false])
    }

    func testMoveOfAWindowAtItsMinimumIsWrittenOnceWithoutRetry() {
        let fake = FakeWindows(minWidths: [10: 574])
        let scheduler = fake.scheduler()
        _ = submitAndWait(scheduler, [job(1, 10, 0)])
        let moved = submitAndWait(scheduler, [job(1, 10, 50)])
        XCTAssertEqual(fake.writes(to: 10).count, 3)
        XCTAssertEqual(moved.map(\.retried), [false])
    }

    func testMinimumsFoundInEachDimensionAreKept() {
        var frame = CGRect.zero
        let scheduler = FrameScheduler(settle: 0, read: { _ in frame }, write: { job in
            frame = CGRect(origin: job.frame.origin, size: job.frame.size.grown(to: CGSize(width: 574, height: 300)))
        })
        _ = submitAndWait(scheduler, [FrameJob(pid: 1, id: 10, frame: CGRect(x: 0, y: 0, width: 100, height: 400))])
        _ = submitAndWait(scheduler, [FrameJob(pid: 1, id: 10, frame: CGRect(x: 0, y: 0, width: 600, height: 100))])
        XCTAssertEqual(scheduler.minimumSizes, [10: CGSize(width: 574, height: 300)])
    }

    func testUnreadableWindowIsWrittenOnceAndReportedUnmatched() {
        var writes = 0
        let scheduler = FrameScheduler(settle: 0, read: { _ in nil }, write: { _ in writes += 1 })
        let results = submitAndWait(scheduler, [job(1, 10, 0)])
        XCTAssertEqual(results.map(\.matched), [false])
        XCTAssertEqual(results.map(\.retried), [false])
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(scheduler.minimumSizes, [:])
    }

    func testEmptySubmitCompletesImmediately() {
        let results = submitAndWait(FakeWindows().scheduler(), [])
        XCTAssertTrue(results.isEmpty)
    }

    func testPlainTilesNeedNoRaises() {
        let layout = workspace(3, gaps: Gaps(all: 8)).layout()
        XCTAssertEqual(layout.raises(current: [3, 1, 2]), [])
        XCTAssertEqual(workspace(3).layout().raises(current: [2, 3, 1]), [])
    }

    func testAccordionRaisesOnlyWhenOrderDiffers() {
        let layout = workspace(3, mode: .accordion).layout()
        XCTAssertEqual(layout.order, [3, 2, 1])
        XCTAssertEqual(layout.raises(current: [3, 99, 2, 1]), [])
        XCTAssertEqual(layout.raises(current: [1, 2, 3]), [1, 2, 3])
    }

    func testFullscreenRaisesWhenNotInFront() {
        var ws = workspace(2)
        ws.toggleFullscreen()
        let layout = ws.layout()
        XCTAssertEqual(layout.raises(current: [2, 1]), [])
        XCTAssertEqual(layout.raises(current: [1, 2]), [1, 2])
    }
}
