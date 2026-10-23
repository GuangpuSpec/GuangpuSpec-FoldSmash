import Foundation
import Observation

/// The single source of hinge truth for an app.
///
/// Feed it from `.readsHinge(into:)` (live) or from `FakeHingePanel`
/// (simulated). Everything else reads `pose`, `reading` and `velocity`.
@MainActor
@Observable
public final class HingeMonitor {
    public enum Source: String, CaseIterable, Sendable {
        case live
        case simulated
    }

    /// Where readings come from. Live readings are ignored while simulated.
    public var source: Source = .live {
        didSet {
            guard source != oldValue else { return }
            tracker.reset()
            velocity = 0
            switch source {
            case .live: apply(lastLive)
            case .simulated: applySimulated()
            }
        }
    }

    public private(set) var reading: HingeReading?
    /// Degrees per second; negative while closing.
    public private(set) var velocity: Double = 0
    /// True once the system has delivered at least one live reading.
    public private(set) var hasLiveHinge = false

    /// Set by `.readsHinge(into:)` from the view's size classes, or by the
    /// fake panel in simulated mode.
    public var isOnOuterDisplay = false

    // Simulated controls.
    public var simulatedDegrees: Double = 180 {
        didSet { if source == .simulated { applySimulated() } }
    }
    public var simulatedOuterDisplay = false {
        didSet { if source == .simulated { applySimulated() } }
    }

    public var pose: Pose {
        PoseClassifier.pose(status: reading?.status, isOnOuterDisplay: isOnOuterDisplay)
    }

    /// Optional hook for games: called on every reading with its velocity.
    @ObservationIgnored
    public var onReading: (@MainActor (HingeReading, Double) -> Void)?

    @ObservationIgnored private var tracker = VelocityTracker()
    @ObservationIgnored private var lastLive: HingeReading?

    public init(source: Source = .live) {
        self.source = source
        if source == .simulated { applySimulated() }
    }

    /// Called by the live reader. `nil` means the window stopped providing
    /// hinge updates.
    public func ingestLive(_ reading: HingeReading?) {
        if reading != nil { hasLiveHinge = true }
        lastLive = reading
        guard source == .live else { return }
        apply(reading)
    }

    /// Called by the live reader when the view's display side changes.
    public func ingestLiveDisplay(isOuter: Bool) {
        guard source == .live else { return }
        isOnOuterDisplay = isOuter
    }

    private func applySimulated() {
        isOnOuterDisplay = simulatedOuterDisplay
        apply(HingeReading(
            degrees: simulatedDegrees,
            status: PoseClassifier.status(forDegrees: simulatedDegrees)
        ))
    }

    private func apply(_ new: HingeReading?) {
        reading = new
        guard let new else {
            tracker.reset()
            velocity = 0
            return
        }
        tracker.add(degrees: new.degrees, at: ProcessInfo.processInfo.systemUptime)
        velocity = tracker.velocity
        onReading?(new, velocity)
    }
}
