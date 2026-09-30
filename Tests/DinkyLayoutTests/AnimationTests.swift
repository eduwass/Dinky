import CoreGraphics
import Testing
@testable import DinkyLayout

struct AnimationTests {
    let spring = Spring(response: 0.2, damping: 0.85)

    /// Steps at 60 Hz until settled; the frames on the way.
    func run(_ animation: inout FrameAnimation, dt: Double = 1.0 / 60, timeout: Double = 5) -> [CGRect] {
        var frames: [CGRect] = []
        while !animation.step(spring, dt: dt, timeout: timeout) { frames.append(animation.frame) }
        return frames
    }

    @Test func `Settles exactly on the target`() {
        var a = FrameAnimation(from: rect(0, 0, 500, 500), to: rect(500, 0, 500, 1000))
        let frames = run(&a)
        #expect(a.frame == rect(500, 0, 500, 1000))
        #expect(frames.count > 5)
        #expect(frames.count < 60)
    }

    @Test func `A move keeps its size`() {
        var a = FrameAnimation(from: rect(0, 0, 500, 500), to: rect(300, 100, 500, 500))
        #expect(run(&a).allSatisfy { $0.size == CGSize(width: 500, height: 500) })
    }

    @Test func `Stays stable with long frames`() {
        let stiff = Spring(response: 0.03, damping: 0.85)
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        for _ in 0..<30 { _ = a.step(stiff, dt: 1.0 / 30, timeout: 5) }
        #expect(a.frame == rect(1000, 0, 100, 100))
    }

    @Test func `Retargeting keeps going from where it is`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        for _ in 0..<5 { _ = a.step(spring, dt: 1.0 / 60, timeout: 5) }
        var fresh = FrameAnimation(from: a.frame, to: rect(0, 0, 100, 100))
        a.retarget(rect(0, 0, 100, 100))
        _ = a.step(spring, dt: 1.0 / 60, timeout: 5)
        _ = fresh.step(spring, dt: 1.0 / 60, timeout: 5)
        // The rightward speed carries over, so it turns around later than a window starting at rest.
        #expect(a.frame.minX > fresh.frame.minX)
        _ = run(&a)
        #expect(a.frame == rect(0, 0, 100, 100))
    }

    @Test func `Gives up after the timeout`() {
        var a = FrameAnimation(from: rect(0, 0, 100, 100), to: rect(1000, 0, 100, 100))
        #expect(a.step(spring, dt: 0.1, timeout: 0.1) == true)
        #expect(a.frame == rect(1000, 0, 100, 100))
    }
}
