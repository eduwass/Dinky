import CoreGraphics
import XCTest
@testable import DinkyLayout

final class AnimationTests: XCTestCase {
    let spring = Spring(response: 0.2, damping: 0.85)

    /// Steps at 60 Hz until settled; the frames on the way.
    func run(_ animation: inout FrameAnimation, dt: Double = 1.0 / 60, timeout: Double = 5) -> [CGRect] {
        var frames: [CGRect] = []
        while !animation.step(spring, dt: dt, timeout: timeout) { frames.append(animation.frame) }
        return frames
    }

    func testSettlesExactlyOnTheTarget() {
        var a = FrameAnimation(from: rect(0, 0, 500, 500), to: rect(500, 0, 500, 1000))
        let frames = run(&a)
        XCTAssertEqual(a.frame, rect(500, 0, 500, 1000))
        XCTAssertGreaterThan(frames.count, 5)
        XCTAssertLessThan(frames.count, 60)
    }

    func testAMoveKeepsItsSize() {
        var a = FrameAnimation(from: rect(0, 0, 500, 500), to: rect(300, 100, 500, 500))
        XCTAssertTrue(run(&a).allSatisfy { $0.size == CGSize(width: 500, height: 500) })
    }

    func testStaysStableWithLongFrames() {
        let stiff = Spring(response: 0.03, damping: 0.85)
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        for _ in 0..<30 { _ = a.step(stiff, dt: 1.0 / 30, timeout: 5) }
        XCTAssertEqual(a.frame, rect(1000, 0, 100, 100))
    }

    func testRetargetingKeepsGoingFromWhereItIs() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        for _ in 0..<5 { _ = a.step(spring, dt: 1.0 / 60, timeout: 5) }
        var fresh = FrameAnimation(from: a.frame, to: rect(0, 0, 100, 100))
        a.retarget(rect(0, 0, 100, 100))
        _ = a.step(spring, dt: 1.0 / 60, timeout: 5)
        _ = fresh.step(spring, dt: 1.0 / 60, timeout: 5)
        // The rightward speed carries over, so it turns around later than a window starting at rest.
        XCTAssertGreaterThan(a.frame.minX, fresh.frame.minX)
        _ = run(&a)
        XCTAssertEqual(a.frame, rect(0, 0, 100, 100))
    }

    func testGivesUpAfterTheTimeout() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        XCTAssertTrue(a.step(spring, dt: 0.1, timeout: 0.1))
        XCTAssertEqual(a.frame, rect(1000, 0, 100, 100))
    }
}
