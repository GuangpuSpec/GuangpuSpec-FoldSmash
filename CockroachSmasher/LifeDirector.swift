import ActivityKit
import BackgroundTasks
import CoreMotion
import Foundation
import Observation
import UIKit
import WidgetKit

/// Runs the roach's life outside the game: starts the Dynamic Island roach,
/// lets the PiP roach loose, and moves the widget roach between holes.
///
/// The island roach hides inside the island almost all the time. At random,
/// unpredictable moments it pokes its antennae out, feels around for a few
/// seconds and snaps back in. Gaps, number of moves, speeds and angles are
/// all drawn fresh every time (random walk, freezes, flicks, double takes,
/// long lulls), so it never settles into a visible loop.
///
/// iOS only lets the app update the island while it is running, so peeks
/// happen: while the app is open; while the floating window keeps it alive;
/// for ~30 s after you leave it; and when iOS grants a background refresh
/// (opportunistic, roughly every 15 min to a few hours, chosen by iOS).
/// Every peek ends with the antennae back inside, so whenever iOS stops
/// the app the island is left looking empty.
@MainActor
@Observable
final class LifeDirector {
    static let shared = LifeDirector()

    private(set) var isLoose = false
    private(set) var islandAvailable = ActivityAuthorizationInfo().areActivitiesEnabled
    @ObservationIgnored private var moodLoop: Task<Void, Never>?
    @ObservationIgnored private var peekLoop: Task<Void, Never>?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var startledUntil = Date.distantPast
    @ObservationIgnored private var isPeeking = false
    @ObservationIgnored private var lastPeekEnded = Date.distantPast
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        isLoose = !Activity<RoachActivityAttributes>.activities.isEmpty
        if isLoose { startLoops() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LifeDirector.shared.didEnterBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LifeDirector.shared.endBackgroundTask() }
        })
    }

    func letLoose() {
        guard !isLoose else { return }
        isLoose = true
        if Activity<RoachActivityAttributes>.activities.isEmpty, islandAvailable {
            // Starts hidden: nothing shows until the first peek.
            let state = RoachActivityAttributes.ContentState(mood: .peek, kills: RoachLife.kills, since: .now)
            _ = try? Activity.request(attributes: RoachActivityAttributes(name: "roach"),
                                      content: ActivityContent(state: state, staleDate: nil),
                                      pushType: nil)
        }
        RoachPiP.shared.enable()
        RoachLife.move(to: Int.random(in: 1...RoachLife.holeCount), for: 120)
        WidgetCenter.shared.reloadTimelines(ofKind: RoachLife.widgetKind)
        startLoops()
        Self.scheduleBackgroundPeek()
    }

    func callBack() {
        isLoose = false
        moodLoop?.cancel()
        peekLoop?.cancel()
        moodLoop = nil
        peekLoop = nil
        motion.stopDeviceMotionUpdates()
        RoachPiP.shared.disable()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: RoachLife.peekTaskID)
        Task {
            for activity in Activity<RoachActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func startLoops() {
        if moodLoop == nil {
            moodLoop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 15...45)))
                    await self?.moodTick()
                }
            }
        }
        if peekLoop == nil {
            peekLoop = Task { [weak self] in
                // The first peek comes quickly, so you see it's in there.
                try? await Task.sleep(for: .seconds(Double.random(in: 2...5)))
                var justPeeked = false
                while !Task.isCancelled {
                    guard let self else { return }
                    if await self.peek() { justPeeked = true }
                    let gap = self.nextGap(justPeeked: justPeeked)
                    justPeeked = false
                    try? await Task.sleep(for: .seconds(gap))
                }
            }
        }
        startShakeSensing()
    }

    // MARK: Background

    private func didEnterBackground() {
        guard isLoose else { return }
        Self.scheduleBackgroundPeek()
        // A little extra time so it can still surprise you just after you leave.
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "roach peek") {
                MainActor.assumeIsolated { LifeDirector.shared.backgroundTimeUp() }
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        // Never leave the antennae sticking out when iOS freezes the app.
        Task {
            await retreatNow()
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    /// iOS is about to freeze the app: pull the antennae in and let go.
    private func backgroundTimeUp() {
        if let s = currentState, s.isOut, s.mood != .dead {
            var hidden = s
            hidden.reach = 0
            hidden.lowerReach = 0
            hidden.beat = .retreat
            Task { await push(hidden) }
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Asks iOS for a background refresh at some random later time.
    nonisolated static func scheduleBackgroundPeek() {
        let request = BGAppRefreshTaskRequest(identifier: RoachLife.peekTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(.random(in: 8 * 60...40 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    /// iOS woke the app in the background: maybe peek once, then back in.
    func backgroundPeek() async {
        Self.scheduleBackgroundPeek()
        guard !Activity<RoachActivityAttributes>.activities.isEmpty else { return }
        // Not every wake: keeps it unpredictable.
        if Double.random(in: 0...1) < 0.8 {
            try? await Task.sleep(for: .seconds(Double.random(in: 0...6)))
            _ = await peek()
        }
        await retreatNow()
    }

    // MARK: Surroundings

    /// A jolt of the phone scares the antennae back in.
    private func startShakeSensing() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let a = data?.userAcceleration else { return }
            let jolt = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            MainActor.assumeIsolated {
                guard let self, jolt > 0.7, Date() > self.startledUntil else { return }
                self.startledUntil = Date().addingTimeInterval(.random(in: 4...12))
            }
        }
    }

    private var startled: Bool { Date() < startledUntil }

    // MARK: Peeking

    private var currentState: RoachActivityAttributes.ContentState? {
        Activity<RoachActivityAttributes>.activities.first?.content.state
    }

    private func push(_ s: RoachActivityAttributes.ContentState) async {
        for activity in Activity<RoachActivityAttributes>.activities {
            await activity.update(ActivityContent(state: s, staleDate: nil))
        }
    }

    /// Sleeps, but wakes early if the roach gets scared. False if scared.
    private func nap(_ seconds: Double) async -> Bool {
        var left = seconds
        while left > 0 {
            if startled || Task.isCancelled { return false }
            let step = min(0.15, left)
            try? await Task.sleep(for: .seconds(step))
            left -= step
        }
        return !startled
    }

    /// Seconds until the next peek. Mostly a random wait (exponential, so
    /// short and long waits mix with no rhythm), sometimes a quick double
    /// take right after a peek, sometimes a long lull.
    private func nextGap(justPeeked: Bool) -> Double {
        let mood = currentState?.mood ?? .peek
        let mean: Double = switch mood {
        case .peek: 22
        case .run: 14
        case .hide: 45
        case .outer, .dead: 30
        }
        let r = Double.random(in: 0...1)
        if justPeeked, r < 0.18 { return .random(in: 1.2...4) }
        if r < 0.12 { return .random(in: 90...240) }
        let wait = -log(Double.random(in: 0.0001...1)) * mean
        return min(180, max(4, wait))
    }

    /// One peek: out, feel around, back in. Returns whether it happened.
    @discardableResult
    private func peek() async -> Bool {
        guard !isPeeking, !startled, var s = currentState else { return false }
        // Out on the outer screen, or squashed: nothing in the island for now.
        let linger: TimeInterval = s.mood == .outer ? 20 : s.mood == .dead ? 8 : 0
        guard Date().timeIntervalSince(s.since) >= linger else { return false }
        if s.mood == .outer || s.mood == .dead {
            s.mood = .peek
            s.since = .now
        }
        isPeeking = true
        defer { isPeeking = false; lastPeekEnded = .now }

        // How bold this peek is.
        let boldness: Double = switch s.mood {
        case .peek: .random(in: 0.7...1)
        case .run: .random(in: 0.5...0.9)
        default: .random(in: 0.25...0.6)
        }
        let reachTo: () -> Double = { Double.random(in: 0.55...1) * (0.5 + 0.5 * boldness) }

        // 1. Emerge. Sometimes one antenna tests the air before the other.
        s.upper = .random(in: -40...5)
        s.lower = .random(in: -5...40)
        s.upperTip = .random(in: -20...20)
        s.lowerTip = .random(in: -20...20)
        s.beat = .emerge
        let oneFirst = Double.random(in: 0...1) < 0.35
        if oneFirst {
            if Bool.random() { s.reach = reachTo() * 0.7 } else { s.lowerReach = reachTo() * 0.7 }
            await push(s)
            guard await nap(.random(in: 0.6...1.6)) else { return await retreat(s) }
            // Sometimes that's all: a quick sniff and gone.
            if Double.random(in: 0...1) < 0.2 { return await retreat(s) }
        }
        s.reach = reachTo()
        s.lowerReach = reachTo()
        await push(s)
        guard await nap(.random(in: 0.45...0.9)) else { return await retreat(s) }

        // 2. Feel around for a few seconds: a random walk with pauses and flicks.
        let duration = Double.random(in: 1.5...7) * (0.6 + 0.6 * boldness)
        let start = Date()
        while Date().timeIntervalSince(start) < duration {
            let r = Double.random(in: 0...1)
            if r < 0.15 {
                // Freeze, listening.
                guard await nap(.random(in: 0.5...1.6)) else { break }
                continue
            }
            if r < 0.32 {
                // Nervous flick of one or both tips.
                s.beat = .flick
                s.upperTip = clamp(s.upperTip + .random(in: -25...25), -30, 30)
                if Bool.random() { s.lowerTip = clamp(s.lowerTip + .random(in: -25...25), -30, 30) }
                s.glide = .random(in: 0.12...0.25)
            } else {
                // Slow sweep, the two antennae out of step.
                s.beat = .feel
                s.upper = clamp(s.upper + .random(in: -28...28), -55, 15)
                s.lower = clamp(s.lower + .random(in: -28...28), -15, 55)
                s.upperTip = clamp(s.upperTip + .random(in: -18...18), -30, 30)
                s.lowerTip = clamp(s.lowerTip + .random(in: -18...18), -30, 30)
                // Now and then it pulls one in a bit, or stretches further.
                if Double.random(in: 0...1) < 0.2 { s.reach = clamp(s.reach * .random(in: 0.5...1.25), 0.3, 1) }
                if Double.random(in: 0...1) < 0.2 { s.lowerReach = clamp(s.lowerReach * .random(in: 0.5...1.25), 0.3, 1) }
                s.glide = .random(in: 0.5...1.4)
            }
            await push(s)
            guard await nap(s.glide * .random(in: 0.8...1.15)) else { break }
        }

        // 3. Snap back in.
        return await retreat(s)
    }

    private func retreat(_ state: RoachActivityAttributes.ContentState) async -> Bool {
        var s = state
        s.reach = 0
        s.lowerReach = 0
        s.upper -= 15
        s.lower += 15
        s.beat = .retreat
        await push(s)
        return true
    }

    /// Pull the antennae in right away (if they're out).
    private func retreatNow() async {
        guard let s = currentState, s.isOut, s.mood != .dead else { return }
        _ = await retreat(s)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    // MARK: Mood

    /// Every so often the roach's mood shifts, which changes how often and
    /// how boldly it peeks.
    private func moodTick() async {
        ticks += 1
        if !isPeeking, var state = currentState {
            let linger: TimeInterval = state.mood == .outer ? 20 : state.mood == .dead ? 8 : 0
            if Date().timeIntervalSince(state.since) >= linger {
                let roll = Double.random(in: 0...1)
                state.mood = roll < 0.45 ? .peek : roll < 0.7 ? .run : roll < 0.94 ? .hide : .outer
                state.kills = RoachLife.kills
                state.since = .now
                if state.mood != .dead {
                    state.reach = 0
                    state.lowerReach = 0
                }
                state.beat = .still
                await push(state)
            }
        }
        // Every ~3 minutes, the widget roach scuttles to another hole.
        if ticks % 6 == 0 {
            RoachLife.move(to: Int.random(in: 0...RoachLife.holeCount), for: 90)
            WidgetCenter.shared.reloadTimelines(ofKind: RoachLife.widgetKind)
        }
    }
}
