import Foundation

/// Turns a stream of hinge angles into angular velocity (degrees per second).
/// Negative = closing, positive = opening.
///
/// Uses the oldest and newest samples inside a short time window, which is
/// steadier than differencing two adjacent samples when events arrive unevenly.
public struct VelocityTracker: Sendable {
    public struct Sample: Equatable, Sendable {
        public var degrees: Double
        public var time: TimeInterval
    }

    /// How far back to look, in seconds.
    public var window: TimeInterval
    public private(set) var samples: [Sample] = []

    public init(window: TimeInterval = 0.12) {
        self.window = window
    }

    public mutating func add(degrees: Double, at time: TimeInterval) {
        // Drop out-of-order samples rather than produce nonsense velocities.
        if let last = samples.last, time <= last.time { return }
        samples.append(Sample(degrees: degrees, time: time))
        let cutoff = time - window
        // Keep one sample at or before the cutoff so the window stays full.
        while samples.count > 2, samples[1].time <= cutoff {
            samples.removeFirst()
        }
    }

    /// Degrees per second over the window, or 0 with fewer than two samples.
    public var velocity: Double {
        guard let first = samples.first, let last = samples.last,
              last.time > first.time else { return 0 }
        return (last.degrees - first.degrees) / (last.time - first.time)
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
