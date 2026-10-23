import Foundation

/// Hinge status, mirrored from Apple's `DeviceHinge` status so the rest of
/// DuoKit (and its tests) never touches iOS 27.1 types directly.
public enum HingeStatus: String, Sendable, CaseIterable, Codable {
    case closed
    case partiallyOpen
    case fullyOpen
    case unknown
}

/// One hinge reading. `degrees`: 0 = folded shut, 180 = flat.
public struct HingeReading: Equatable, Sendable {
    public var degrees: Double
    public var status: HingeStatus

    public init(degrees: Double, status: HingeStatus) {
        self.degrees = degrees
        self.status = status
    }
}

/// How the device is being held, as far as an app can tell.
public enum Pose: String, Sendable, CaseIterable {
    /// Folded shut; the app is on the outer display.
    case closed
    /// Partially open and standing on its edges, outer display facing out.
    /// In this pose the system puts the app's main UI on the outer display.
    case tent
    /// Partially open like a book or laptop; the app is on the inner display.
    case book
    /// Fully open, inner display.
    case flat
    /// No hinge data (regular iPhone, old SDK, or no updates yet).
    case unknown

    public var label: String {
        switch self {
        case .closed: "Closed"
        case .tent: "Tent"
        case .book: "Book"
        case .flat: "Flat"
        case .unknown: "No hinge"
        }
    }
}

public enum PoseClassifier {
    /// Decide the pose from hinge status plus which display the app is on.
    ///
    /// Tent and book are both `partiallyOpen`; what separates them is that in
    /// tent mode the system shows the app on the outer display.
    /// Caveat: a Split View pane on the inner display is also compact width,
    /// so callers should only pass `isOnOuterDisplay = true` for the full
    /// outer display (see `DisplaySide`).
    public static func pose(status: HingeStatus?, isOnOuterDisplay: Bool) -> Pose {
        switch status {
        case .closed?: return .closed
        case .partiallyOpen?: return isOnOuterDisplay ? .tent : .book
        case .fullyOpen?: return .flat
        // No hinge reading yet (an app launched while the phone is shut may
        // not get one until the hinge moves): the outer display means closed.
        case .unknown?, nil: return isOnOuterDisplay ? .closed : .unknown
        }
    }

    /// Status for a simulated angle, matching what the system reports.
    /// Thresholds are guesses; tune them against the real device.
    public static func status(forDegrees degrees: Double) -> HingeStatus {
        if degrees <= 5 { return .closed }
        if degrees >= 175 { return .fullyOpen }
        return .partiallyOpen
    }
}
