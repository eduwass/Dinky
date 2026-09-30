import CoreGraphics

/// A damped spring on one value, SwiftUI style: `response` is roughly the time to arrive,
/// `damping` 1 arrives without overshoot. Semi-implicit Euler with substeps short enough to stay stable.
public struct Spring: Equatable, Sendable {
    public let stiffness: Double
    public let friction: Double

    public init(response: Double, damping: Double) {
        let omega = 2 * Double.pi / max(response, 0.001)
        stiffness = omega * omega
        friction = 2 * damping * omega
    }

    /// Advance `value` and `velocity` towards `target` by `dt` seconds.
    public func step(_ value: inout Double, _ velocity: inout Double, to target: Double, dt: Double) {
        let limit = 0.5 / max(stiffness.squareRoot(), friction)
        let steps = max(1, Int((dt / limit).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            velocity += (stiffness * (target - value) - friction * velocity) * h
            value += velocity * h
        }
    }
}

/// One window moving from where it is to its tile: x, y, width and height each on the same spring,
/// so shared edges of neighbouring windows move together.
public struct FrameAnimation: Equatable, Sendable {
    private var target: CGRect
    private var value: [Double]
    private var velocity: [Double] = [0, 0, 0, 0]
    /// Seconds since the target last changed, to give up on one that never settles.
    private var age: Double = 0

    public init(from start: CGRect, to target: CGRect) {
        self.target = target
        value = Self.components(start)
    }

    /// The frame now, rounded to whole points so a pure move does not jitter the size.
    public var frame: CGRect {
        CGRect(x: value[0].rounded(), y: value[1].rounded(), width: value[2].rounded(), height: value[3].rounded())
    }

    /// Head somewhere else, keeping the current position and speed so the motion stays continuous.
    public mutating func retarget(_ new: CGRect) {
        guard new != target else { return }
        target = new
        age = 0
    }

    /// Advance by `dt` seconds. True once at rest on the target, or after `timeout` seconds.
    public mutating func step(_ spring: Spring, dt: Double, timeout: Double) -> Bool {
        age += dt
        let goal = Self.components(target)
        for i in 0..<4 { spring.step(&value[i], &velocity[i], to: goal[i], dt: dt) }
        let settled = (0..<4).allSatisfy { abs(value[$0] - goal[$0]) < 0.5 && abs(velocity[$0]) < 10 }
        if settled || age >= timeout {
            value = goal
            velocity = [0, 0, 0, 0]
            return true
        }
        return false
    }

    private static func components(_ r: CGRect) -> [Double] {
        [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)]
    }
}
