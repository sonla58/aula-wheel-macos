import Foundation

/// Turns one scroll detent into a pixel delta, with acceleration for fast spins.
///
/// Deltas use CGEvent scroll-wheel signs: positive `dy` scrolls content toward the top
/// (like wheel-up), positive `dx` toward the left.
public struct ScrollPlanner: Sendable {
    public var config: ScrollConfig
    private var last: (time: TimeInterval, direction: ScrollDirection)?

    public init(config: ScrollConfig) {
        self.config = config
    }

    /// 1x at `accelerationThresholdMs` between detents, rising linearly to `maxAcceleration`
    /// at `accelerationFullMs` (about the fastest the firmware sends detents).
    func accelerationFactor(gap: TimeInterval) -> Double {
        let threshold = config.accelerationThresholdMs / 1000
        let full = min(config.accelerationFullMs / 1000, threshold)
        guard gap < threshold else { return 1 }
        guard threshold > full else { return config.maxAcceleration }
        let closeness = min((threshold - max(gap, 0)) / (threshold - full), 1)
        return 1 + closeness * (config.maxAcceleration - 1)
    }

    public mutating func delta(direction: ScrollDirection, scale: Double, speed: ScrollSpeed, time: TimeInterval)
        -> (dx: Double, dy: Double)
    {
        var factor = 1.0
        if let last, last.direction == direction {
            factor = accelerationFactor(gap: time - last.time)
        }
        last = (time, direction)

        var amount = config.pixels(for: speed) * scale * factor
        if config.invert { amount = -amount }
        switch direction {
        case .up: return (0, amount)
        case .down: return (0, -amount)
        case .left: return (amount, 0)
        case .right: return (-amount, 0)
        }
    }
}

/// Spreads queued scroll distance over time with an exponential ease-out.
public struct ScrollAnimator: Sendable {
    public var duration: TimeInterval
    private var remainingX = 0.0
    private var remainingY = 0.0
    private var carryX = 0.0
    private var carryY = 0.0

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    public var isIdle: Bool {
        remainingX == 0 && remainingY == 0
    }

    public mutating func add(dx: Double, dy: Double) {
        remainingX += dx
        remainingY += dy
    }

    /// Returns the whole-pixel delta to post for a frame lasting `dt` seconds.
    public mutating func step(dt: TimeInterval) -> (dx: Int32, dy: Int32) {
        let fraction: Double
        if duration <= 0 {
            fraction = 1
        } else {
            // Time constant of duration/4 drains ~98% of the distance within `duration`.
            fraction = 1 - exp(-dt / (duration / 4))
        }
        let x = take(&remainingX, fraction: fraction)
        let y = take(&remainingY, fraction: fraction)
        return (
            emit(x, carry: &carryX, final: remainingX == 0),
            emit(y, carry: &carryY, final: remainingY == 0)
        )
    }

    public mutating func reset() {
        remainingX = 0
        remainingY = 0
        carryX = 0
        carryY = 0
    }

    private func take(_ remaining: inout Double, fraction: Double) -> Double {
        var part = remaining * fraction
        if abs(remaining - part) < 0.5 { part = remaining }
        remaining -= part
        return part
    }

    private func emit(_ value: Double, carry: inout Double, final: Bool) -> Int32 {
        let total = value + carry
        let whole = final ? total.rounded() : total.rounded(.towardZero)
        carry = final ? 0 : total - whole
        return Int32(whole)
    }
}
