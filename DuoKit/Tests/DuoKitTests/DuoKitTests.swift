import Testing
@testable import DuoKit

@Suite("PoseClassifier")
struct PoseClassifierTests {
    @Test func closedIsClosedOnEitherDisplay() {
        #expect(PoseClassifier.pose(status: .closed, isOnOuterDisplay: true) == .closed)
        #expect(PoseClassifier.pose(status: .closed, isOnOuterDisplay: false) == .closed)
    }

    @Test func partiallyOpenSplitsByDisplay() {
        #expect(PoseClassifier.pose(status: .partiallyOpen, isOnOuterDisplay: true) == .tent)
        #expect(PoseClassifier.pose(status: .partiallyOpen, isOnOuterDisplay: false) == .book)
    }

    @Test func missingHingeIsUnknown() {
        #expect(PoseClassifier.pose(status: nil, isOnOuterDisplay: false) == .unknown)
        #expect(PoseClassifier.pose(status: .unknown, isOnOuterDisplay: false) == .unknown)
    }

    /// An app launched while the phone is shut may get no hinge reading until the hinge moves;
    /// being on the outer display is then enough to call it closed.
    @Test func missingHingeOnOuterDisplayIsClosed() {
        #expect(PoseClassifier.pose(status: nil, isOnOuterDisplay: true) == .closed)
        #expect(PoseClassifier.pose(status: .unknown, isOnOuterDisplay: true) == .closed)
    }

    @Test(arguments: zip(
        [0.0, 5, 6, 90, 174, 175, 180],
        [HingeStatus.closed, .closed, .partiallyOpen, .partiallyOpen, .partiallyOpen, .fullyOpen, .fullyOpen]
    ))
    func simulatedStatus(degrees: Double, expected: HingeStatus) {
        #expect(PoseClassifier.status(forDegrees: degrees) == expected)
    }
}

@Suite("VelocityTracker")
struct VelocityTrackerTests {
    @Test func needsTwoSamples() {
        var t = VelocityTracker()
        #expect(t.velocity == 0)
        t.add(degrees: 90, at: 1)
        #expect(t.velocity == 0)
    }

    @Test func closingIsNegative() {
        var t = VelocityTracker(window: 1)
        t.add(degrees: 120, at: 0)
        t.add(degrees: 60, at: 0.1)
        #expect(abs(t.velocity - -600) < 0.001)
    }

    @Test func oldSamplesFallOutOfTheWindow() {
        var t = VelocityTracker(window: 0.1)
        t.add(degrees: 0, at: 0)       // ancient, should be dropped
        t.add(degrees: 100, at: 1.0)
        t.add(degrees: 110, at: 1.05)
        t.add(degrees: 120, at: 1.1)
        // Window is 1.0...1.1 → 20° in 0.1 s.
        #expect(abs(t.velocity - 200) < 0.001)
        #expect(t.samples.first?.time == 1.0)
    }

    @Test func ignoresOutOfOrderSamples() {
        var t = VelocityTracker(window: 1)
        t.add(degrees: 10, at: 1)
        t.add(degrees: 99, at: 0.5)
        #expect(t.samples.count == 1)
    }
}
