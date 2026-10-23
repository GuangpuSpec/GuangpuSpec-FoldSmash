import Foundation
import CoreGraphics
import Observation
import DuoKit

enum GamePhase: Sendable {
    case menu, playing, over
}

// MARK: - Content

/// Food scraps. Roaches swarm them and eat them down: whole → half → crumbs.
enum FoodKind: Int, CaseIterable, Sendable {
    case pizza, banana, fries, bread, apple, fishbone, rice, cookie
}

enum GameMap: String, CaseIterable, Identifiable, Sendable {
    case kitchen, fridge, closet, office, desktop, homeScreen

    var id: Self { self }

    var label: String {
        switch self {
        case .kitchen: String(localized: "Kitchen")
        case .fridge: String(localized: "Fridge")
        case .closet: String(localized: "Closet")
        case .office: String(localized: "Office Desk")
        case .desktop: String(localized: "Desktop")
        case .homeScreen: String(localized: "Home Screen")
        }
    }

    /// Seconds between swarm bursts on the inner screen.
    var burstInterval: ClosedRange<Double> {
        switch self {
        case .kitchen: 1.2...2.0
        case .fridge: 1.8...2.6      // cold, sluggish roaches
        case .closet: 1.0...1.8
        case .office: 0.9...1.5
        case .desktop: 0.7...1.2
        case .homeScreen: 0.8...1.3
        }
    }

    /// Crawl speed in points per second, before the species factor.
    var speed: ClosedRange<Double> {
        switch self {
        case .kitchen: 60...100
        case .fridge: 40...70
        case .closet: 70...110
        case .office: 80...130
        case .desktop: 80...130
        case .homeScreen: 75...125
        }
    }

    var maxRoaches: Int {
        switch self {
        case .kitchen: 60
        case .fridge: 40
        case .closet: 70
        case .office: 80
        case .desktop: 110
        case .homeScreen: 90
        }
    }

    /// The Home Screen has app icons to protect instead of food and a bin.
    var hasTrash: Bool { self != .homeScreen }
}

// MARK: - Entities

struct Roach: Identifiable {
    let id = UUID()
    var species: Species
    var pos: CGPoint
    var heading: Double          // radians, 0 = facing right
    var baseSpeed: Double
    var nextTurn: TimeInterval
    var legPhase: Double
    var born: TimeInterval
    var lifetime: TimeInterval   // outer roaches run off after this
    var scale: CGFloat
    /// Which screen it lives on: inner (phone open) or outer (phone closed).
    var inner: Bool
    var hp: Int
    var hungry: Bool
    var leaving = false
    var trapped = false
    var eating = false
    /// Rummaging in the trash bin (crushable by the lid).
    var atBin = false
    var sprintUntil: TimeInterval = 0
    var curledUntil: TimeInterval = 0
    var hitUntil: TimeInterval = 0
}

struct Food: Identifiable {
    let id = UUID()
    var kind: FoodKind
    var pos: CGPoint
    var angle: Double
    var scale: CGFloat
    var born: TimeInterval
    /// 1 = untouched, 0 = gone.
    var amount: Double = 1
    /// Being dragged by a finger.
    var held = false
    /// Trash breeds roaches: the next hatching from this scrap.
    var nextHatch: TimeInterval = 0
}

struct Splat: Identifiable {
    let id = UUID()
    var species: Species
    var pos: CGPoint
    var inner: Bool
    var seed: UInt64
    var born: TimeInterval
    var scale: CGFloat
    var angle: Double
}

struct Pop: Identifiable {
    let id = UUID()
    var text: String
    var pos: CGPoint
    var inner: Bool
    var born: TimeInterval
    var hot: Bool
}

/// A droplet of goo flying out of a squash. Moves on its own from its
/// launch values, so the model doesn't have to step it.
struct Particle {
    enum Tint { case goo, gooDark, spark, white }
    var origin: CGPoint
    var velocity: CGVector
    var born: TimeInterval
    var life: Double
    var size: CGFloat
    var tint: Tint
    var inner: Bool

    /// Where it is `age` seconds after launch (it slows to a stop on the floor).
    func position(age: Double) -> CGPoint {
        let k = 7.0
        let travel = (1 - exp(-k * age)) / k
        return CGPoint(x: origin.x + velocity.dx * travel, y: origin.y + velocity.dy * travel)
    }
}

/// An expanding shockwave ring.
struct Ring {
    var pos: CGPoint
    var born: TimeInterval
    var radius: CGFloat
    var width: CGFloat
    var gold: Bool
    var inner: Bool
    static let life: Double = 0.35
}

struct Banner {
    var title: String
    var subtitle: String
    var born: TimeInterval
}

// MARK: - Game

/// The whole game. Positions are in the current screen's points; when the
/// screen changes size everything is rescaled, so things keep their place.
@MainActor
@Observable
final class GameModel {
    static let roundLength: TimeInterval = 60

    var phase: GamePhase = .menu
    var map: GameMap = .kitchen
    /// True while the app is on the outer display (phone closed or tent).
    var isOuter = false {
        didSet { if isOuter != oldValue { nextSpawn = now + 0.8 } }
    }

    private(set) var now: TimeInterval = ProcessInfo.processInfo.systemUptime
    private(set) var roaches: [Roach] = []
    private(set) var foods: [Food] = []
    private(set) var splats: [Splat] = []
    private(set) var pops: [Pop] = []
    private(set) var banner: Banner?
    private(set) var score = 0
    private(set) var squashed = 0
    private(set) var escaped = 0
    private(set) var foodLost = 0
    private(set) var bestSlam = 0
    private(set) var kills: [Species: Int] = [:]
    private(set) var isNewBest = false
    private(set) var shakeUntil: TimeInterval = 0
    private(set) var binOpenUntil: TimeInterval = 0
    private(set) var lidSlamUntil: TimeInterval = 0
    private(set) var endTime: TimeInterval = 0
    private(set) var paused = false
    /// Garbage in the bin. The fuller, the smellier, the more roaches it pulls in.
    private(set) var binFill = 0
    private(set) var cleaned = 0
    private(set) var lidKills = 0
    nonisolated static let binCapacity = 6
    /// Home Screen map: the app icons the bugs are eating.
    private(set) var icons: [AppIcon] = []
    private(set) var appsEaten = 0
    /// Every app got eaten: the round ended early.
    private(set) var takenOver = false
    /// Apps left at the end (Home Screen map), each worth a bonus.
    private(set) var appsSaved = 0
    static let appBonus = 10
    @ObservationIgnored private var warnedOverrun = false
    private(set) var particles: [Particle] = []
    private(set) var rings: [Ring] = []
    /// Brief white flash over the screen (fold kills).
    private(set) var flashUntil: TimeInterval = 0
    /// Kills chained within a short window of each other.
    private(set) var combo = 0
    private(set) var comboUntil: TimeInterval = 0
    private(set) var bestCombo = 0
    /// When the score last went up, for the HUD's bump.
    private(set) var scoreBumpAt: TimeInterval = 0
    /// Hit stop: the world freezes for a beat on impact, so hits feel heavy.
    @ObservationIgnored private var freezeUntil: TimeInterval = 0
    static let comboWindow: TimeInterval = 1.4

    @ObservationIgnored private var size = CGSize(width: 890, height: 626)
    @ObservationIgnored private var nextSpawn: TimeInterval = 0
    @ObservationIgnored private var nextFood: TimeInterval = 0
    @ObservationIgnored private var lidReadyAt: TimeInterval = 0
    @ObservationIgnored private var carryingID: UUID?
    @ObservationIgnored private var dragDecided = false
    @ObservationIgnored private var roundStart: TimeInterval = 0
    @ObservationIgnored private var lastStep: TimeInterval = 0
    @ObservationIgnored private var lastStatus: HingeStatus?
    @ObservationIgnored private var peakCloseVelocity: Double = 0
    @ObservationIgnored private var lastDodgeHint: TimeInterval = 0

    var timeLeft: Int { max(0, Int((endTime - now).rounded(.up))) }

    var shakeOffset: CGSize {
        guard now < shakeUntil else { return .zero }
        let k = (shakeUntil - now) / 0.45
        return CGSize(width: sin(now * 90) * 16 * k, height: cos(now * 73) * 11 * k)
    }

    /// The bin's spot on the inner screen, bottom right.
    var binRect: CGRect {
        CGRect(x: size.width - 96, y: size.height - 118, width: 72, height: 84)
    }

    /// Hints shown until the player gets the idea.
    var trashHint: String? {
        guard phase == .playing, !paused, !isOuter else { return nil }
        if map == .homeScreen {
            if icons.contains(where: { !$0.eaten && now - $0.lastBite < 0.3 && $0.health < 0.8 }) {
                return String(localized: "They're eating your apps! Swat them!")
            }
            return nil
        }
        if cleaned == 0, !foods.isEmpty, now - roundStart > 2 {
            return String(localized: "Drag trash into the bin!")
        }
        if lidKills == 0, roaches.filter(\.atBin).count >= 3 {
            return String(localized: "Tap the bin lid to crush them!")
        }
        return nil
    }

    // MARK: Round

    func start(map: GameMap) {
        self.map = map
        now = ProcessInfo.processInfo.systemUptime
        roaches = []
        foods = []
        splats = []
        pops = []
        banner = nil
        score = 0
        squashed = 0
        escaped = 0
        foodLost = 0
        bestSlam = 0
        kills = [:]
        isNewBest = false
        combo = 0
        comboUntil = 0
        bestCombo = 0
        particles = []
        rings = []
        icons = map == .homeScreen ? (0..<AppIcon.count).map { AppIcon(id: $0) } : []
        appsEaten = 0
        appsSaved = 0
        takenOver = false
        warnedOverrun = false
        flashUntil = 0
        freezeUntil = 0
        binFill = 0
        cleaned = 0
        lidKills = 0
        paused = false
        carryingID = nil
        dragDecided = false
        roundStart = now
        endTime = now + Self.roundLength
        nextSpawn = now + 0.4
        nextFood = now + .random(in: 9...13)
        lidReadyAt = 0
        lastStep = 0
        phase = .playing
        SoundBoard.shared.prepare()
        Haptics.shared.prepare()
        if map.hasTrash {
            addFood()
            addFood()
        }
    }

    /// Arrived from the roach living in the phone: straight into a round on
    /// the desktop map, with a nudge to do the fold trap.
    func startHunt() {
        guard phase != .playing else { return }
        start(map: .desktop)
        banner = Banner(title: String(localized: "It's in here!"),
                        subtitle: String(localized: "Close the phone, then open it to trap it."),
                        born: now)
    }

    func quit() {
        roaches = []
        banner = nil
        paused = false
        phase = .menu
    }

    func pause() {
        guard phase == .playing else { return }
        paused = true
    }

    func resume() {
        paused = false
        lastStep = 0
    }

    private func finish() {
        Haptics.shared.stop()
        if map == .homeScreen {
            appsSaved = icons.filter { !$0.eaten }.count
            score += appsSaved * Self.appBonus
        }
        roaches = []
        banner = nil
        let key = "best.\(map.rawValue)"
        if score > UserDefaults.standard.integer(forKey: key) {
            UserDefaults.standard.set(score, forKey: key)
            isNewBest = score > 0
        }
        phase = .over
    }

    func best(for map: GameMap) -> Int {
        UserDefaults.standard.integer(forKey: "best.\(map.rawValue)")
    }

    // MARK: Screen

    func setFieldSize(_ new: CGSize) {
        guard new.width > 0, new.height > 0, new != size else { return }
        let sx = new.width / size.width
        let sy = new.height / size.height
        for i in roaches.indices { roaches[i].pos = scaled(roaches[i].pos, sx, sy) }
        for i in foods.indices { foods[i].pos = scaled(foods[i].pos, sx, sy) }
        for i in splats.indices { splats[i].pos = scaled(splats[i].pos, sx, sy) }
        for i in pops.indices { pops[i].pos = scaled(pops[i].pos, sx, sy) }
        particles.removeAll()
        rings.removeAll()
        size = new
    }

    private func scaled(_ p: CGPoint, _ sx: CGFloat, _ sy: CGFloat) -> CGPoint {
        CGPoint(x: p.x * sx, y: p.y * sy)
    }

    // MARK: Hinge

    /// Fed every hinge reading. Watches for the two moves that matter:
    /// closed → open (trap the outside roaches) and open → closed (the slam).
    func observeHinge(_ reading: HingeReading, velocity: Double) {
        defer { lastStatus = reading.status }
        if paused { return }
        if reading.status == .closed {
            if let last = lastStatus, last != .closed {
                slam(closingSpeed: -peakCloseVelocity)
            }
            peakCloseVelocity = 0
        } else {
            if lastStatus == .closed {
                trapOutsideRoaches()
                peakCloseVelocity = 0
            }
            peakCloseVelocity = min(peakCloseVelocity, velocity)
        }
    }

    private func slam(closingSpeed speed: Double) {
        guard phase == .playing else { return }
        let inside = roaches.filter(\.inner)
        roaches.removeAll(where: \.inner)

        guard !inside.isEmpty else {
            SoundBoard.shared.play(.foldWhiff)
            Haptics.shared.play(.foldWhiff)
            shakeUntil = now + 0.15
            banner = Banner(title: String(localized: "Whiff!"),
                            subtitle: String(localized: "Nothing inside."),
                            born: now)
            return
        }

        // A quick, decisive close earns the bonus; anything faster than
        // "quick" earns nothing extra, so there's no reason to slam the
        // hinge hard. No speed reading (it happened between samples) counts
        // as quick.
        let multiplier: Int
        let rating: String
        if speed >= 400 || speed == 0 {
            multiplier = 3
            rating = String(localized: "Perfect snap ×3")
        } else if speed >= 150 {
            multiplier = 2
            rating = String(localized: "Nice snap ×2")
        } else {
            multiplier = 1
            rating = String(localized: "Slow close ×1")
        }

        // The fold's signature: snap + crush sound, two-stage haptic, a longer
        // hit stop, a flash and a big shake.
        let strength: Float = multiplier == 3 ? 1 : multiplier == 2 ? 0.75 : 0.5
        SoundBoard.shared.play(.foldKill(strength: strength))
        Haptics.shared.play(.foldKill(strength: strength))
        freezeUntil = now + 0.08
        flashUntil = now + 0.12
        shakeUntil = now + 0.45

        // Stains stay on the inner screen for later (a sample, so a huge
        // swarm doesn't bury the floor). One big one outside, where the
        // player is looking now.
        for r in inside.shuffled().prefix(40) {
            addSplat(r.species, at: r.pos, inner: true, scale: r.scale)
        }
        let biggest = inside.max { $0.species.points < $1.species.points }?.species ?? .common
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        addSplat(biggest, at: center, inner: false, scale: 3.2)
        burst(at: center, inner: false, power: 2.4, count: 36)
        ring(at: center, inner: false, radius: max(size.width, size.height) * 0.7, width: 14, gold: true)

        for r in inside { kills[r.species, default: 0] += 1 }
        let points = inside.reduce(0) { $0 + $1.species.points } * multiplier
        addScore(points)
        squashed += inside.count
        bestSlam = max(bestSlam, inside.count)
        chain(inside.count, at: center, inner: false)
        banner = Banner(
            title: String(localized: "SPLAT!"),
            subtitle: String(localized: "Squashed \(inside.count)") + " · " + rating + " · +\(points)",
            born: now
        )
    }

    private func trapOutsideRoaches() {
        guard phase == .playing else { return }
        var trappedAny = false
        for i in roaches.indices where !roaches[i].inner {
            // They fall into the fold: middle of the screen, dazed.
            roaches[i].inner = true
            roaches[i].trapped = true
            roaches[i].leaving = false
            roaches[i].hungry = false
            roaches[i].born = now
            roaches[i].pos = CGPoint(
                x: size.width / 2 + .random(in: -14...14),
                y: size.height * .random(in: 0.3...0.7)
            )
            trappedAny = true
        }
        if trappedAny {
            banner = Banner(title: String(localized: "Trapped!"),
                            subtitle: String(localized: "It's in the crease. Slam it shut!"),
                            born: now)
        }
    }

    // MARK: Touch

    func tap(at p: CGPoint) {
        guard phase == .playing, !paused else { return }
        if !isOuter, map.hasTrash, binRect.insetBy(dx: -10, dy: -10).contains(p) {
            slamLid()
            return
        }
        let onScreen = roaches.indices.filter { roaches[$0].inner != isOuter }
        guard let i = onScreen.min(by: { distance(roaches[$0].pos, p) < distance(roaches[$1].pos, p) }),
              distance(roaches[i].pos, p) < max(30, 24 * roaches[i].scale) else { return }

        if isOuter {
            // Outside roaches are too quick to tap. That's the point.
            scatter(from: p, radius: 140, except: nil)
            if now - lastDodgeHint > 1.2 {
                pop(String(localized: "Too fast!"), at: p, hot: false)
                lastDodgeHint = now
            }
            return
        }

        let id = roaches[i].id
        roaches[i].hp -= 1
        scatter(from: p, radius: 110, except: id)

        if roaches[i].hp > 0 {
            switch roaches[i].species {
            case .isopod:
                roaches[i].curledUntil = now + 1.6
                pop(String(localized: "Curled up!"), at: p, hot: false)
            default:
                roaches[i].hitUntil = now + 0.15
                roaches[i].sprintUntil = now + 0.5
                pop(String(localized: "Hits left \(roaches[i].hp)"), at: p, hot: true)
            }
            SoundBoard.shared.play(.hit)
            Haptics.shared.play(.hit)
            ring(at: roaches[i].pos, inner: true, radius: 34 * roaches[i].scale, width: 3, gold: false)
            return
        }

        // Sound and haptic land on the touch (0 ms); the world freezes ~50 ms,
        // then the flattened body pops in with its goo and score.
        SoundBoard.shared.play(.tapKill)
        Haptics.shared.play(.tapKill)
        freezeUntil = now + 0.05
        let r = roaches.remove(at: i)
        addSplat(r.species, at: r.pos, inner: true, scale: r.scale)
        burst(at: r.pos, inner: true, power: r.scale, count: combo >= 4 ? 18 : 11)
        ring(at: r.pos, inner: true, radius: 46 * r.scale, width: 4, gold: false)
        chain(1, at: r.pos, inner: true)
        let multiplier = min(combo, 5)
        let points = r.species.points * multiplier
        addScore(points)
        squashed += 1
        kills[r.species, default: 0] += 1
        pop(multiplier > 1 ? "+\(points)  ×\(multiplier)" : "+\(points)", at: r.pos,
            hot: multiplier > 2 || r.species.points >= 5)
    }

    // MARK: Trash

    /// Finger down/moving. Grabbing a scrap carries it.
    func dragChanged(start: CGPoint, location: CGPoint) {
        guard phase == .playing, !paused, !isOuter else { return }
        if !dragDecided {
            dragDecided = true
            if let i = foods.indices.min(by: { distance(foods[$0].pos, start) < distance(foods[$1].pos, start) }),
               distance(foods[i].pos, start) < 40 * foods[i].scale {
                carryingID = foods[i].id
                foods[i].held = true
                SoundBoard.shared.play(.pickup)
                Haptics.shared.play(.pickup)
            }
        }
        if let id = carryingID, let i = foods.firstIndex(where: { $0.id == id }) {
            foods[i].pos = location
            binOpenUntil = binRect.insetBy(dx: -30, dy: -30).contains(location) ? now + 0.2 : binOpenUntil
        }
    }

    /// Finger up: drop the scrap (in the bin = cleaned), or it was a tap.
    func dragEnded(start: CGPoint, location: CGPoint) {
        defer {
            dragDecided = false
            carryingID = nil
        }
        if let id = carryingID, let i = foods.firstIndex(where: { $0.id == id }) {
            if binRect.insetBy(dx: -24, dy: -24).contains(location) {
                cleanUp(at: i)
            } else {
                foods[i].held = false
                foods[i].nextHatch = now + .random(in: 5...8)
            }
            return
        }
        if distance(start, location) < 14 { tap(at: location) }
    }

    /// A scrap goes in the bin: no more roaches hatching from it.
    private func cleanUp(at i: Int) {
        let f = foods.remove(at: i)
        binFill = min(binFill + 1, Self.binCapacity)
        cleaned += 1
        addScore(5)
        binOpenUntil = now + 0.4
        pop(String(localized: "Cleaned up!") + " +5", at: CGPoint(x: binRect.midX, y: binRect.minY - 10), hot: false)
        // Whoever was eating it scatters.
        scatter(from: f.pos, radius: 60, except: nil)
        SoundBoard.shared.play(.clean)
        Haptics.shared.play(.pickup)
    }

    /// Slam the bin lid: crushes every roach rummaging in or on the bin.
    private func slamLid() {
        guard now >= lidReadyAt else { return }
        lidReadyAt = now + 1.0
        lidSlamUntil = now + 0.3
        let zone = binRect.insetBy(dx: -22, dy: -30)
        let caught = roaches.filter { $0.inner && zone.contains($0.pos) }
        roaches.removeAll { $0.inner && zone.contains($0.pos) }
        SoundBoard.shared.play(.lidSlam(count: caught.count))
        Haptics.shared.play(.lidSlam(count: caught.count))
        shakeUntil = now + (caught.count >= 3 ? 0.35 : 0.2)
        let top = CGPoint(x: binRect.midX, y: binRect.minY - 16)
        let mid = CGPoint(x: binRect.midX, y: binRect.midY)
        ring(at: mid, inner: true, radius: 70 + CGFloat(min(caught.count, 8)) * 14, width: 6, gold: true)
        guard !caught.isEmpty else {
            pop(String(localized: "Empty…"), at: top, hot: false)
            return
        }
        freezeUntil = now + 0.07
        for r in caught {
            addSplat(r.species, at: r.pos, inner: true, scale: r.scale)
            kills[r.species, default: 0] += 1
        }
        // The bigger the pile-up, the bigger the show.
        burst(at: mid, inner: true, power: 1.2 + CGFloat(min(caught.count, 8)) * 0.15,
              count: min(14 + caught.count * 5, 48), sparks: true)
        if caught.count >= 3 { flashUntil = now + 0.08 }
        let points = caught.reduce(0) { $0 + $1.species.points } * 2
        addScore(points)
        squashed += caught.count
        lidKills += caught.count
        chain(caught.count, at: top, inner: true)
        let title = caught.count >= 5 ? String(localized: "BIN-SLAM ×\(caught.count)!")
            : String(localized: "Lid crushed \(caught.count)!")
        pop(title + " +\(points)", at: top, hot: true)
    }

    private func scatter(from p: CGPoint, radius: CGFloat, except id: UUID?) {
        for j in roaches.indices where roaches[j].inner != isOuter && roaches[j].id != id {
            let d = distance(roaches[j].pos, p)
            guard d < radius else { continue }
            roaches[j].sprintUntil = now + .random(in: 0.5...0.9)
            roaches[j].heading = atan2(roaches[j].pos.y - p.y, roaches[j].pos.x - p.x) + .random(in: -0.4...0.4)
            roaches[j].eating = false
        }
    }

    // MARK: Loop

    func step(now t: TimeInterval) {
        let dt = lastStep == 0 ? 0 : min(t - lastStep, 0.05)
        lastStep = t
        if phase == .playing && paused {
            // Freeze the round: keep the clock and every timer where they were.
            endTime += t - now
            now = t
            return
        }
        now = t

        pops.removeAll { t - $0.born > 1.1 }
        particles.removeAll { t - $0.born > $0.life }
        rings.removeAll { t - $0.born > Ring.life }
        if combo > 0, t > comboUntil, !paused { combo = 0 }
        splats.removeAll { t - $0.born > 14 }
        if splats.count > 80 { splats.removeFirst(splats.count - 80) }
        if let b = banner, t - b.born > 1.9 { banner = nil }

        guard phase == .playing else { return }
        if t < freezeUntil {
            // Hit stop: everything holds still for a beat (the clock too).
            endTime += dt
            return
        }
        if t >= endTime {
            finish()
            return
        }
        if t >= nextFood {
            if foods.count < 4, map.hasTrash { addFood() }
            nextFood = t + .random(in: 9...13)
        }
        spawnIfNeeded(t)
        hatch(t)
        moveRoaches(dt: dt, t: t)
        eatFood(dt: dt)
        eatIcons(dt: dt)
        if map == .homeScreen, !icons.isEmpty, icons.allSatisfy(\.eaten) {
            takenOver = true
            finish()
        }
    }

    private func spawnIfNeeded(_ t: TimeInterval) {
        guard t >= nextSpawn else { return }
        if isOuter {
            // A few at a time outside, never over a result banner.
            let outside = roaches.filter { !$0.inner }.count
            guard outside < 5, banner == nil else {
                nextSpawn = t + 0.5
                return
            }
            let edge = randomEdgePoint()
            for _ in 0..<Int.random(in: 1...3) where roaches.filter({ !$0.inner }).count < 5 {
                roaches.append(makeRoach(inner: false, near: edge, t: t))
            }
            nextSpawn = t + .random(in: 1.5...3)
        } else {
            let inside = roaches.filter(\.inner).count
            guard inside < map.maxRoaches else {
                nextSpawn = t + 0.4
                return
            }
            // Bursts from one edge, so they pour in like a swarm.
            let edge = randomEdgePoint()
            let count = min(Int.random(in: 3...7), map.maxRoaches - inside)
            for _ in 0..<count {
                roaches.append(makeRoach(inner: true, near: edge, t: t))
            }
            nextSpawn = t + .random(in: map.burstInterval) * 1.6
        }
    }

    /// Trash on the floor breeds roaches.
    private func hatch(_ t: TimeInterval) {
        guard !isOuter else { return }
        for i in foods.indices where !foods[i].held && t >= foods[i].nextHatch {
            foods[i].nextHatch = t + .random(in: 5...8)
            let inside = roaches.filter(\.inner).count
            guard inside < map.maxRoaches else { continue }
            let count = min(Int.random(in: 2...3), map.maxRoaches - inside)
            for _ in 0..<count {
                roaches.append(makeRoach(inner: true, near: foods[i].pos, t: t))
            }
        }
    }

    private func randomEdgePoint() -> CGPoint {
        let m: CGFloat = 18
        switch Int.random(in: 0..<4) {
        case 0: return CGPoint(x: m, y: .random(in: m...max(m, size.height - m)))
        case 1: return CGPoint(x: size.width - m, y: .random(in: m...max(m, size.height - m)))
        case 2: return CGPoint(x: .random(in: m...max(m, size.width - m)), y: m)
        default: return CGPoint(x: .random(in: m...max(m, size.width - m)), y: size.height - m)
        }
    }

    private func pickSpecies() -> Species {
        let bossAlive = roaches.contains { $0.species == .boss }
        let pool = Species.allCases.filter { !($0 == .boss && bossAlive) }
        var roll = Double.random(in: 0..<pool.reduce(0) { $0 + $1.weight })
        for s in pool {
            roll -= s.weight
            if roll < 0 { return s }
        }
        return .common
    }

    private func makeRoach(inner: Bool, near edge: CGPoint, t: TimeInterval) -> Roach {
        let species = pickSpecies()
        let pos = CGPoint(x: edge.x + .random(in: -20...20), y: edge.y + .random(in: -20...20))
        let toCenter = atan2(size.height / 2 - pos.y, size.width / 2 - pos.x)
        let speed = Double.random(in: map.speed) * species.speedFactor * (inner ? 1 : 1.6)
        return Roach(
            species: species,
            pos: pos,
            heading: toCenter + .random(in: -0.7...0.7),
            baseSpeed: speed,
            nextTurn: t + .random(in: 0.3...1),
            legPhase: .random(in: 0...6),
            born: t,
            lifetime: .random(in: 4.5...6),
            scale: CGFloat.random(in: species.sizeRange) * (inner ? 1 : 1.25),
            inner: inner,
            hp: species.hp,
            hungry: Double.random(in: 0...1) < (map == .homeScreen ? 0.85 : 0.75)
        )
    }

    private func moveRoaches(dt: Double, t: TimeInterval) {
        let m: CGFloat = 14
        for i in roaches.indices.reversed() {
            var r = roaches[i]
            guard r.inner != isOuter else { continue }   // off-screen ones wait
            r.eating = false
            r.atBin = false

            if t < r.curledUntil {
                roaches[i] = r
                continue
            }

            // Outer roaches give up and run off after a while.
            if !r.inner && !r.leaving && t - r.born > r.lifetime {
                r.leaving = true
                r.heading = headingToNearestEdge(r.pos)
            }

            var speed = t < r.sprintUntil ? r.baseSpeed * 2.6
                : r.trapped ? r.baseSpeed * 0.7
                : r.leaving ? r.baseSpeed * 1.5
                : r.baseSpeed

            if r.inner, r.hungry, t >= r.sprintUntil, let goal = target(for: r.pos) {
                let d = distance(goal.point, r.pos)
                if d < goal.reach {
                    // Munching (food) or rummaging (bin): barely moving.
                    if goal.isBin { r.atBin = true } else { r.eating = true }
                    speed *= 0.12
                    if t >= r.nextTurn {
                        r.heading += .random(in: -1.5...1.5)
                        r.nextTurn = t + .random(in: 0.3...0.9)
                    }
                } else {
                    let aim = atan2(goal.point.y - r.pos.y, goal.point.x - r.pos.x)
                    let diff = atan2(sin(aim - r.heading), cos(aim - r.heading))
                    r.heading += max(-4 * dt, min(4 * dt, diff))
                    if t >= r.nextTurn {
                        r.heading += .random(in: -0.5...0.5)
                        r.nextTurn = t + .random(in: 0.4...1.2)
                    }
                }
            } else if !r.leaving && t >= r.nextTurn {
                r.heading += .random(in: -1.3...1.3)
                r.nextTurn = t + .random(in: 0.35...1.4)
            }

            r.pos.x += cos(r.heading) * speed * dt
            r.pos.y += sin(r.heading) * speed * dt
            r.legPhase += max(speed, 20) * dt * 0.45

            if r.leaving {
                if r.pos.x < -50 || r.pos.y < -50 || r.pos.x > size.width + 50 || r.pos.y > size.height + 50 {
                    roaches.remove(at: i)
                    escaped += 1
                    let shown = CGPoint(x: min(max(r.pos.x, 60), size.width - 60),
                                        y: min(max(r.pos.y, 60), size.height - 60))
                    pop(String(localized: "Escaped!"), at: shown, hot: false)
                    continue
                }
            } else {
                if r.pos.x < m { r.pos.x = m; r.heading = .pi - r.heading }
                if r.pos.x > size.width - m { r.pos.x = size.width - m; r.heading = .pi - r.heading }
                if r.pos.y < m { r.pos.y = m; r.heading = -r.heading }
                if r.pos.y > size.height - m { r.pos.y = size.height - m; r.heading = -r.heading }
            }
            roaches[i] = r
        }
    }

    /// Every munching roach takes a bite. Eaten-up scraps are lost.
    /// Only so many mouths fit around one scrap: a full pile lasts about
    /// 14 seconds however big the swarm, so there's time to lure and slam.
    private func eatFood(dt: Double) {
        guard !foods.isEmpty, !isOuter else { return }
        var bites: [Int: Double] = [:]
        for r in roaches where r.eating {
            guard let k = nearestFoodIndex(to: r.pos) else { continue }
            bites[k, default: 0] += r.species.appetite
        }
        for (k, b) in bites {
            foods[k].amount -= 0.007 * min(b, 10) * dt
        }
        for f in foods where f.amount <= 0 {
            foodLost += 1
            pop(String(localized: "Eaten up!"), at: f.pos, hot: false)
        }
        foods.removeAll { $0.amount <= 0 }
    }

    /// Home Screen: munching bugs chew the nearest app icon. About 4 bugs
    /// finish an icon in 20 seconds, so there's time to swat them off.
    private func eatIcons(dt: Double) {
        guard map == .homeScreen, !isOuter, !icons.isEmpty else { return }
        let frames = HomeLayout.frames(in: size)
        var bites: [Int: Double] = [:]
        for r in roaches where r.eating && r.inner {
            let alive = icons.indices.filter { !icons[$0].eaten && icons[$0].id < frames.count }
            guard let k = alive.min(by: {
                distance(CGPoint(x: frames[icons[$0].id].midX, y: frames[icons[$0].id].midY), r.pos)
                    < distance(CGPoint(x: frames[icons[$1].id].midX, y: frames[icons[$1].id].midY), r.pos)
            }) else { continue }
            bites[k, default: 0] += r.species.appetite
        }
        for (k, b) in bites {
            // Widgets are bigger, so they take longer.
            icons[k].health -= 0.0125 * min(b, 8) * dt / icons[k].tile.toughness
            icons[k].lastBite = now
            if icons[k].health <= 0 {
                icons[k].health = 0
                appsEaten += 1
                let f = frames[icons[k].id]
                let c = CGPoint(x: f.midX, y: f.midY)
                pop(String(localized: "\(icons[k].name) eaten!"), at: c, hot: false)
                SoundBoard.shared.play(.hit)
                Haptics.shared.play(.hit)
                // The diners wander off to find the next app.
                scatter(from: c, radius: 50, except: nil)
            }
        }
        let left = icons.filter { !$0.eaten }.count
        if !warnedOverrun, left <= icons.count / 3, left > 0 {
            warnedOverrun = true
            banner = Banner(title: String(localized: "Overrun!"),
                            subtitle: String(localized: "Only \(left) apps left. Swat faster!"),
                            born: now)
        }
    }

    private func nearestFoodIndex(to p: CGPoint) -> Int? {
        foods.indices.min { distance(foods[$0].pos, p) < distance(foods[$1].pos, p) }
    }

    /// Where a hungry roach heads: the nearest scrap, or the bin if it
    /// smells stronger. A fuller bin reaches further.
    private func target(for p: CGPoint) -> (point: CGPoint, reach: CGFloat, isBin: Bool)? {
        var best: (point: CGPoint, reach: CGFloat, isBin: Bool, score: CGFloat)?
        if map == .homeScreen {
            let frames = HomeLayout.frames(in: size)
            for icon in icons where !icon.eaten && icon.id < frames.count {
                let f = frames[icon.id]
                let c = CGPoint(x: f.midX, y: f.midY)
                // Half-eaten apps smell stronger.
                let d = distance(c, p) * CGFloat(0.6 + 0.4 * icon.health)
                if best == nil || d < best!.score { best = (c, f.width * 0.55, false, d) }
            }
            return best.map { ($0.point, $0.reach, $0.isBin) }
        }
        for f in foods {
            let d = distance(f.pos, p)
            if best == nil || d < best!.score { best = (f.pos, 24 * f.scale, false, d) }
        }
        if binFill > 0 {
            let mouth = CGPoint(x: binRect.midX, y: binRect.minY + 18)
            let d = distance(mouth, p) / (1 + 0.45 * CGFloat(binFill))
            if best == nil || d < best!.score { best = (mouth, 30, true, d) }
        }
        return best.map { ($0.point, $0.reach, $0.isBin) }
    }

    private func addFood() {
        let pos = CGPoint(x: size.width * .random(in: 0.18...0.82),
                          y: size.height * .random(in: 0.22...0.8))
        foods.append(Food(kind: FoodKind.allCases.randomElement()!, pos: pos,
                          angle: .random(in: 0...(2 * .pi)),
                          scale: .random(in: 0.9...1.2), born: now,
                          nextHatch: now + .random(in: 4...7)))
    }

    private func headingToNearestEdge(_ p: CGPoint) -> Double {
        let options: [(CGFloat, Double)] = [
            (p.x, .pi), (size.width - p.x, 0),
            (p.y, -.pi / 2), (size.height - p.y, .pi / 2),
        ]
        return options.min { $0.0 < $1.0 }!.1
    }

    private func addSplat(_ species: Species, at pos: CGPoint, inner: Bool, scale: CGFloat) {
        splats.append(Splat(species: species, pos: pos, inner: inner, seed: .random(in: .min ... .max),
                            born: now, scale: scale, angle: .random(in: 0...(2 * .pi))))
    }

    private func addScore(_ points: Int) {
        guard points > 0 else { return }
        score += points
        scoreBumpAt = now
    }

    /// Counts kills toward the combo. From 3 on, each step plays a rising
    /// note; every 5th calls it out.
    private func chain(_ kills: Int, at pos: CGPoint, inner: Bool) {
        let before = combo
        combo = now < comboUntil ? combo + kills : kills
        comboUntil = now + Self.comboWindow
        bestCombo = max(bestCombo, combo)
        guard combo >= 3 else { return }
        SoundBoard.shared.play(.combo(combo))
        if combo / 5 > before / 5 {
            Haptics.shared.play(.combo(combo))
            pop(String(localized: "COMBO ×\(combo)!"), at: CGPoint(x: pos.x, y: pos.y - 36), hot: true)
            ring(at: pos, inner: inner, radius: 120, width: 5, gold: true)
        }
    }

    /// Goo flying out of a squash. Launches after the hit stop.
    private func burst(at pos: CGPoint, inner: Bool, power: CGFloat, count: Int, sparks: Bool = false) {
        let start = max(now, freezeUntil)
        for k in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi))
            let speed = CGFloat.random(in: 160...520) * power
            let tint: Particle.Tint = sparks && k % 3 == 0 ? .spark : (Bool.random() ? .goo : .gooDark)
            particles.append(Particle(origin: pos,
                                      velocity: CGVector(dx: cos(a) * speed, dy: sin(a) * speed),
                                      born: start, life: .random(in: 0.35...0.6),
                                      size: CGFloat.random(in: 2.5...6.5) * min(power, 2.2),
                                      tint: tint, inner: inner))
        }
        if particles.count > 260 { particles.removeFirst(particles.count - 260) }
    }

    private func ring(at pos: CGPoint, inner: Bool, radius: CGFloat, width: CGFloat, gold: Bool) {
        rings.append(Ring(pos: pos, born: now, radius: radius, width: width, gold: gold, inner: inner))
    }

    private func pop(_ text: String, at pos: CGPoint, hot: Bool) {
        pops.append(Pop(text: text, pos: pos, inner: !isOuter, born: now, hot: hot))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
