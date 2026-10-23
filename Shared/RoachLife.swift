import Foundation
import ActivityKit
import AppIntents
import WidgetKit

// Shared by the app and the widget extension: where the roach lives outside
// the game. State sits in an App Group so the widgets and the app agree.

enum RoachLife {
    static let appGroup = "group.com.example.duovibes.foldsmash"
    static let holeCount = 4
    static let widgetKind = "RoachHole"
    static let huntURL = URL(string: "foldsmash://hunt")!
    /// Background refresh that lets the roach peek out while the app is closed.
    static let peekTaskID = "com.example.duovibes.cockroachsmasher.peek"

    /// How long the roach stays in one hole on its own, in seconds.
    static let slotLength: TimeInterval = 150

    static var store: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: Which hole

    /// Where the roach is at `date`: 0 = hiding somewhere, 1...holeCount = in
    /// that hole. Follows a fixed pseudo-random schedule, so every widget
    /// agrees without talking, unless a swat sent it somewhere for a while.
    static func hole(at date: Date) -> Int {
        let s = store
        if let until = s.object(forKey: "overrideUntil") as? Date, date < until {
            return s.integer(forKey: "overrideHole")
        }
        let slot = Int(date.timeIntervalSince1970 / slotLength)
        var rng = SplitMix64(state: UInt64(truncatingIfNeeded: slot) &* 7919)
        return Int(rng.next() % UInt64(holeCount + 1))
    }

    /// Send the roach to `hole` (0 = hidden) for `duration` seconds.
    static func move(to hole: Int, for duration: TimeInterval) {
        store.set(hole, forKey: "overrideHole")
        store.set(Date().addingTimeInterval(duration), forKey: "overrideUntil")
    }

    /// Next times the roach changes hole, for widget timelines.
    static func changeDates(after date: Date, count: Int) -> [Date] {
        var dates: [Date] = []
        if let until = store.object(forKey: "overrideUntil") as? Date, until > date {
            dates.append(until)
        }
        let firstSlot = (date.timeIntervalSince1970 / slotLength).rounded(.down) + 1
        for k in 0..<count {
            dates.append(Date(timeIntervalSince1970: (firstSlot + Double(k)) * slotLength))
        }
        return dates.sorted()
    }

    // MARK: Splats and score

    static func isSplatted(hole: Int, at date: Date) -> Bool {
        guard store.integer(forKey: "splatHole") == hole,
              let until = store.object(forKey: "splatUntil") as? Date else { return false }
        return date < until
    }

    static var kills: Int {
        get { store.integer(forKey: "kills") }
        set { store.set(newValue, forKey: "kills") }
    }

    /// A tap on a hole. Usually it bolts to another hole; sometimes you get it.
    static func swat(hole: Int) {
        let now = Date()
        guard Self.hole(at: now) == hole, !isSplatted(hole: hole, at: now) else { return }
        if Double.random(in: 0...1) < 0.3 {
            store.set(hole, forKey: "splatHole")
            store.set(now.addingTimeInterval(90), forKey: "splatUntil")
            kills += 1
            move(to: 0, for: 240)       // the next one takes a while to show up
        } else {
            let others = (1...holeCount).filter { $0 != hole }
            move(to: others.randomElement() ?? 1, for: 120)
        }
    }

    // MARK: Dynamic Island

    /// A swat from the island. Runs in the app's process.
    static func swatIsland() async {
        for activity in Activity<RoachActivityAttributes>.activities {
            var state = activity.content.state
            let roll = Double.random(in: 0...1)
            if roll < 0.3 {
                state.mood = .dead
                kills += 1
            } else if roll < 0.6 {
                state.mood = .outer       // it ran off to the outer screen
            } else {
                state.mood = .run
            }
            state.kills = kills
            state.since = Date()
            state.flinch()
            if state.mood == .dead {
                // Squashed: limp antennae left hanging out of the island.
                state.upper = 50; state.lower = 75
                state.upperTip = 35; state.lowerTip = 25
                state.reach = 0.85; state.lowerReach = 0.7
                state.beat = .still
            }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}

/// The roach living in the Dynamic Island. Most of the time it hides inside
/// and nothing shows; now and then its antennae poke out and feel around.
struct RoachActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var mood: Mood
        var kills: Int
        var since: Date
        /// Antenna pose, in degrees. 0 = straight out from the island,
        /// negative = up, positive = down. `tip` bends the outer half.
        var upper: Double = -14
        var lower: Double = 14
        var upperTip: Double = -8
        var lowerTip: Double = 8
        /// How far each antenna pokes out, 0 (inside the island) ... 1.
        var reach: Double = 0
        var lowerReach: Double = 0
        /// What this update is, which picks how the island animates to it.
        var beat: Beat = .still
        /// Seconds to glide to this pose (for `.feel`).
        var glide: Double = 0.9

        init(mood: Mood, kills: Int, since: Date) {
            self.mood = mood
            self.kills = kills
            self.since = since
        }

        // Tolerates states saved by older builds that lack some fields.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mood = try c.decodeIfPresent(Mood.self, forKey: .mood) ?? .peek
            kills = try c.decodeIfPresent(Int.self, forKey: .kills) ?? 0
            since = try c.decodeIfPresent(Date.self, forKey: .since) ?? .now
            upper = try c.decodeIfPresent(Double.self, forKey: .upper) ?? -14
            lower = try c.decodeIfPresent(Double.self, forKey: .lower) ?? 14
            upperTip = try c.decodeIfPresent(Double.self, forKey: .upperTip) ?? -8
            lowerTip = try c.decodeIfPresent(Double.self, forKey: .lowerTip) ?? 8
            reach = try c.decodeIfPresent(Double.self, forKey: .reach) ?? 0
            lowerReach = try c.decodeIfPresent(Double.self, forKey: .lowerReach) ?? 0
            beat = (try? c.decodeIfPresent(Beat.self, forKey: .beat)) ?? .still
            glide = try c.decodeIfPresent(Double.self, forKey: .glide) ?? 0.9
        }
    }

    enum Mood: String, Codable, Hashable {
        case peek, run, hide, outer, dead
    }

    enum Beat: String, Codable, Hashable {
        /// Pops out of the island.
        case emerge
        /// Feeling around.
        case feel
        /// A quick nervous flick.
        case flick
        /// Snaps back inside.
        case retreat
        /// Resting.
        case still
    }

    var name: String
}

extension RoachActivityAttributes.ContentState {
    /// Startled: antennae snap back into the island.
    mutating func flinch() {
        upper = -40
        lower = 40
        upperTip = 20
        lowerTip = -20
        reach = 0
        lowerReach = 0
        beat = .retreat
    }

    var isOut: Bool { reach > 0.02 || lowerReach > 0.02 }
}

// MARK: - Intents

/// Tap a roach hole widget.
struct SwatHoleIntent: AppIntent {
    static let title: LocalizedStringResource = "Swat"
    static let isDiscoverable = false

    @Parameter(title: "Hole")
    var hole: Int

    init() {}

    init(hole: Int) {
        self.hole = hole
    }

    func perform() async throws -> some IntentResult {
        RoachLife.swat(hole: hole)
        WidgetCenter.shared.reloadTimelines(ofKind: RoachLife.widgetKind)
        return .result()
    }
}

/// The 拍它！ button in the expanded Dynamic Island.
struct SwatIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Swat the roach"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RoachLife.swatIsland()
        return .result()
    }
}
