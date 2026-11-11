import Foundation

enum Clock {
    /// Seconds on the clock CGEvent timestamps use (nanoseconds since boot, excluding sleep).
    static func now() -> TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
    }

    /// Converts a CGEvent timestamp, falling back to now if it is missing or on another clock.
    static func eventTime(_ timestamp: UInt64) -> TimeInterval {
        let now = now()
        let time = Double(timestamp) / 1e9
        return abs(time - now) < 1 ? time : now
    }
}
