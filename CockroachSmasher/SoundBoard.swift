import AVFoundation
import CoreHaptics
import UIKit

// MARK: - Sound

/// Every hit is built from layers, each with several variations, so ten kills
/// in a row never sound like one file on repeat:
/// - attack: a short sharp slap or click that says "it connected";
/// - body: the wet crunch or squish that gives it texture;
/// - tail: a brief resonance that adds weight.
/// All synthesized at launch; the project ships no audio files.
@MainActor
final class SoundBoard {
    enum Sound {
        /// A finger squash.
        case tapKill
        /// A hit that didn't kill (armoured bug, curled isopod).
        case hit
        /// Folding the phone shut on roaches. Its own signature: snap, then crush.
        case foldKill(strength: Float)
        /// Folding shut on nothing.
        case foldWhiff
        /// The bin lid coming down, `count` roaches under it.
        case lidSlam(count: Int)
        /// Trash dropped in the bin.
        case clean
        /// A scrap picked up.
        case pickup
        /// Combo step: pitch rises with each kill in the chain.
        case combo(Int)
        /// Kept for the floating-window roach.
        case crunch
    }

    static let shared = SoundBoard()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var bank: [String: [AVAudioPCMBuffer]] = [:]
    private var lastVariant: [String: Int] = [:]
    private var recentPlays: [TimeInterval] = []
    private var started = false

    private init() {}

    /// Builds the sounds ahead of time so the first hit isn't late.
    func prepare() { startIfNeeded() }

    func play(_ sound: Sound) {
        startIfNeeded()
        guard started else { return }
        // Many kills in the same instant: one big layered hit, not a pile-up
        // that clips. At most 8 layers start within 30 ms.
        let t = ProcessInfo.processInfo.systemUptime
        recentPlays.removeAll { t - $0 > 0.03 }

        switch sound {
        case .tapKill, .crunch:
            layer("slap", 0.85, t)
            layer("crunch", 0.9, t)
            layer("squish", 0.45, t)
        case .hit:
            layer("click", 0.7, t)
            layer("crunch", 0.35, t)
        case .foldKill(let strength):
            layer("snap", 0.9, t)
            layer("boom", 0.75 + 0.25 * strength, t)
            layer("crunch", 1.0, t)
            layer("squish", 0.7, t)
        case .foldWhiff:
            layer("snap", 0.8, t)
            layer("thunk", 0.6, t)
        case .lidSlam(let count):
            layer("clang", 0.85, t)
            layer("boom", count > 0 ? 0.7 : 0.45, t)
            if count > 0 {
                layer("crunch", 1.0, t)
                if count >= 3 { layer("squish", 0.8, t) }
            }
        case .clean:
            layer("thunk", 0.8, t)
        case .pickup:
            layer("click", 0.4, t)
        case .combo(let n):
            let step = min(max(n - 2, 0), Self.chimeSteps - 1)
            play(buffer: bank["chime"]?[step], gain: 0.45, t)
        }
    }

    private func layer(_ name: String, _ gain: Float, _ t: TimeInterval) {
        guard let variants = bank[name], !variants.isEmpty else { return }
        // A different variation from last time.
        var i = Int.random(in: 0..<variants.count)
        if variants.count > 1, i == lastVariant[name] { i = (i + 1) % variants.count }
        lastVariant[name] = i
        play(buffer: variants[i], gain: gain * Float.random(in: 0.9...1.0), t)
    }

    private func play(buffer: AVAudioPCMBuffer?, gain: Float, _ t: TimeInterval) {
        guard let buffer, recentPlays.count < 8, !voices.isEmpty else { return }
        recentPlays.append(t)
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = gain
        voice.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.play()
    }

    private func startIfNeeded() {
        if started {
            if !engine.isRunning { try? engine.start() }
            return
        }
        // The PiP roach needs the playback session; don't knock it out.
        if !RoachPiP.shared.enabled {
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
        }
        for _ in 0..<16 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            voices.append(p)
        }
        // Headroom so stacked layers don't clip.
        engine.mainMixerNode.outputVolume = 0.8
        buildBank()
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    // MARK: Synthesis

    private static let chimeSteps = 10

    private func buildBank() {
        bank["slap"] = (0..<4).compactMap { slap(variant: $0) }
        bank["click"] = (0..<3).compactMap { click(variant: $0) }
        bank["crunch"] = (0..<4).compactMap { crunch(variant: $0) }
        bank["squish"] = (0..<3).compactMap { squish(variant: $0) }
        bank["snap"] = (0..<3).compactMap { snap(variant: $0) }
        bank["boom"] = (0..<3).compactMap { boom(variant: $0) }
        bank["clang"] = (0..<3).compactMap { clang(variant: $0) }
        bank["thunk"] = (0..<2).compactMap { thunk(variant: $0) }
        // Major-scale steps, so a long combo climbs like a little fanfare.
        let scale = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
        bank["chime"] = (0..<Self.chimeSteps).compactMap { chime(semitones: scale[$0]) }
    }

    private func render(_ seconds: Double, _ sample: (_ i: Int, _ t: Float) -> Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = b.floatChannelData?[0] else { return nil }
        b.frameLength = frames
        let rate = Float(format.sampleRate)
        var peak: Float = 0.0001
        for i in 0..<Int(frames) {
            let v = sample(i, Float(i) / rate)
            data[i] = v
            peak = max(peak, abs(v))
        }
        // Normalize, then a 2 ms fade-in so nothing pops.
        let norm = 0.95 / peak
        let fade = Int(0.002 * rate)
        for i in 0..<Int(frames) {
            data[i] *= norm * (i < fade ? Float(i) / Float(fade) : 1)
        }
        return b
    }

    /// Attack: a palm slap. Bright noise burst with a fast decay.
    private func slap(variant v: Int) -> AVAudioPCMBuffer? {
        var prev: Float = 0
        let decay = 70 + Float(v) * 12
        let tone = 900 + Float(v) * 160
        return render(0.06) { _, t in
            let n = Float.random(in: -1...1)
            let bright = n - prev * 0.85
            prev = n
            let body = sin(2 * .pi * tone * t) * exp(-t * 120) * 0.4
            return (bright * 0.8 + body) * exp(-t * decay)
        }
    }

    /// Attack: a small dry click.
    private func click(variant v: Int) -> AVAudioPCMBuffer? {
        let f = 2_400 + Float(v) * 500
        return render(0.025) { _, t in
            (sin(2 * .pi * f * t) * 0.6 + Float.random(in: -1...1) * 0.5) * exp(-t * 260)
        }
    }

    /// Body: the wet crunch of a shell giving way.
    private func crunch(variant v: Int) -> AVAudioPCMBuffer? {
        var lowpass: Float = 0
        let smooth = 0.28 + Float(v) * 0.05
        let squelchHz = 150 + Float(v) * 25
        let crackleRate: Float = 0.02 + Float(v) * 0.008
        return render(0.17) { _, t in
            let noise = Float.random(in: -1...1)
            lowpass += smooth * (noise - lowpass)
            let crackle: Float = Float.random(in: 0...1) < crackleRate ? Float.random(in: -1...1) : 0
            let squelch = sin(2 * .pi * (squelchHz - 280 * t) * t) * exp(-t * 20) * 0.4
            return (lowpass * 0.9 + crackle * 0.8) * exp(-t * 24) + squelch
        }
    }

    /// Tail: a short low squish that lingers a moment.
    private func squish(variant v: Int) -> AVAudioPCMBuffer? {
        var phase: Float = 0
        var lowpass: Float = 0
        let start = 130 + Float(v) * 18
        return render(0.16) { _, t in
            let f = start * exp(-t * 7) + 45
            phase += 2 * .pi * f / 44_100
            lowpass += 0.08 * (Float.random(in: -1...1) - lowpass)
            let wobble = 1 + 0.4 * sin(2 * .pi * 28 * t)
            return (sin(phase) * 0.7 + lowpass * 1.2) * wobble * exp(-t * 16) * min(1, t * 120)
        }
    }

    /// Fold signature, part 1: a mechanical snap (two quick clicks and a ping).
    private func snap(variant v: Int) -> AVAudioPCMBuffer? {
        let ping = 2_000 + Float(v) * 260
        let gap: Float = 0.011 + Float(v) * 0.002
        return render(0.09) { _, t in
            let click1 = Float.random(in: -1...1) * exp(-t * 900)
            let t2 = t - gap
            let click2: Float = t2 > 0 ? Float.random(in: -1...1) * exp(-t2 * 700) : 0
            let ring = sin(2 * .pi * ping * t) * exp(-t * 55) * 0.45
            return click1 + click2 * 0.9 + ring
        }
    }

    /// Weight: a deep falling boom.
    private func boom(variant v: Int) -> AVAudioPCMBuffer? {
        var phase: Float = 0
        let base = 100 + Float(v) * 14
        return render(0.42) { _, t in
            let f = base * exp(-t * 6) + 36
            phase += 2 * .pi * f / 44_100
            let hit = Float.random(in: -1...1) * exp(-t * 34)
            return sin(phase) * exp(-t * 6) + hit * 0.4
        }
    }

    /// The bin lid: inharmonic metal partials plus a hit.
    private func clang(variant v: Int) -> AVAudioPCMBuffer? {
        let k = 1 + Float(v) * 0.06
        let partials: [(Float, Float, Float)] = [(410, 1, 9), (1_090, 0.7, 12), (1_730, 0.5, 15), (2_620, 0.35, 20), (3_470, 0.2, 26)]
        return render(0.5) { _, t in
            var s: Float = 0
            for (f, a, d) in partials { s += sin(2 * .pi * f * k * t) * a * exp(-t * d) }
            return s * 0.5 + Float.random(in: -1...1) * exp(-t * 60) * 0.6
        }
    }

    /// A soft low thud (trash in the bin, an empty fold).
    private func thunk(variant v: Int) -> AVAudioPCMBuffer? {
        let f = 85 + Float(v) * 20
        return render(0.12) { _, t in
            sin(2 * .pi * f * t) * exp(-t * 30) + Float.random(in: -1...1) * exp(-t * 90) * 0.3
        }
    }

    /// A bright combo blip.
    private func chime(semitones: Int) -> AVAudioPCMBuffer? {
        let f = 740 * pow(2, Float(semitones) / 12)
        return render(0.2) { _, t in
            (sin(2 * .pi * f * t) + 0.35 * sin(2 * .pi * f * 2 * t) + 0.15 * sin(2 * .pi * f * 3 * t))
                * exp(-t * 14)
        }
    }
}

// MARK: - Haptics

/// Core Haptics patterns that line up with the sounds. Falls back to the
/// simple feedback generators on hardware without Core Haptics.
@MainActor
final class Haptics {
    static let shared = Haptics()

    enum Pattern {
        /// Two stages: a crisp hit, then a softer give.
        case tapKill
        /// A light tick for a hit that didn't kill.
        case hit
        /// Fold signature: sharp snap, heavy crush, short rumble.
        case foldKill(strength: Float)
        case foldWhiff
        /// Heavy lid slam, plus a little aftershock per extra roach.
        case lidSlam(count: Int)
        case pickup
        case combo(Int)
    }

    private var engine: CHHapticEngine?
    private var needsStart = true
    private var lastPlay: TimeInterval = 0
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {}

    /// Start the engine before the round so the first hit isn't late.
    func prepare() {
        guard supported else { return }
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.playsHapticsOnly = true
            engine?.isAutoShutdownEnabled = false
            // The system can stop or reset the engine (interruptions, going
            // to the background). Restart it on the next hit.
            engine?.stoppedHandler = { _ in
                Task { @MainActor in Haptics.shared.needsStart = true }
            }
            engine?.resetHandler = {
                Task { @MainActor in Haptics.shared.needsStart = true }
            }
        }
        if needsStart, (try? engine?.start()) != nil { needsStart = false }
    }

    /// Stop between rounds and in the background.
    func stop() {
        engine?.stop(completionHandler: nil)
        needsStart = true
    }

    func play(_ pattern: Pattern) {
        // Several kills in one frame should feel like one strong hit, not a
        // buzz. Big moments (fold, lid) always get through.
        let t = ProcessInfo.processInfo.systemUptime
        switch pattern {
        case .foldKill, .lidSlam, .foldWhiff: break
        default: if t - lastPlay < 0.045 { return }
        }
        lastPlay = t

        guard supported else { fallback(pattern); return }
        prepare()
        guard let engine, let events = try? Self.events(for: pattern),
              let player = try? engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])) else {
            fallback(pattern)
            return
        }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    private static func tap(_ time: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private static func rumble(_ time: Double, _ duration: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            CHHapticEventParameter(parameterID: .decayTime, value: Float(duration)),
            CHHapticEventParameter(parameterID: .sustained, value: 0),
        ], relativeTime: time, duration: duration)
    }

    private static func events(for pattern: Pattern) throws -> [CHHapticEvent] {
        switch pattern {
        case .tapKill:
            return [tap(0, 0.95, 0.85), tap(0.07, 0.6, 0.25)]
        case .hit:
            return [tap(0, 0.5, 0.95)]
        case .foldKill(let s):
            return [tap(0, 1, 1), tap(0.035, 0.85 + 0.15 * s, 0.25), rumble(0.05, 0.2, 0.55 * s + 0.2, 0.1)]
        case .foldWhiff:
            return [tap(0, 0.7, 0.9), tap(0.04, 0.35, 0.2)]
        case .lidSlam(let count):
            var e = [tap(0, 1, 0.75), tap(0.05, count > 0 ? 0.9 : 0.5, 0.2)]
            for i in 0..<min(count, 4) {
                e.append(tap(0.11 + Double(i) * 0.035, 0.45 - Float(i) * 0.08, 0.5))
            }
            return e
        case .pickup:
            return [tap(0, 0.35, 0.6)]
        case .combo(let n):
            return [tap(0, min(1, 0.35 + Float(n) * 0.05), 1)]
        }
    }

    private func fallback(_ pattern: Pattern) {
        switch pattern {
        case .foldKill, .lidSlam:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        case .tapKill, .foldWhiff:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .hit, .pickup, .combo:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
