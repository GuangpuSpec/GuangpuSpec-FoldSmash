@preconcurrency import AVKit
import AVFoundation
import CoreMedia
import SwiftUI
import UIKit

/// What the floating window is doing, shown on the menu in debug builds.
@MainActor
@Observable
final class PiPStatus {
    static let shared = PiPStatus()
    var supported = AVPictureInPictureController.isPictureInPictureSupported()
    var possible = false
    var active = false
    var message = ""
}

extension Notification.Name {
    /// Someone wants to go squash the roach (PiP restored, island tapped).
    static let roachHunt = Notification.Name("roachHunt")
}

/// The roach in a floating Picture-in-Picture window.
///
/// We render our own frames into an AVSampleBufferDisplayLayer. Once PiP is
/// running, iOS keeps the app alive in the background, which also lets
/// `LifeDirector` keep the island roach and widget holes moving.
///
/// PiP's pause button is the swat button.
@MainActor
final class RoachPiP: NSObject {
    static let shared = RoachPiP()

    let displayLayer = AVSampleBufferDisplayLayer()
    private(set) var enabled = false
    private var controller: AVPictureInPictureController?
    private var timer: Timer?
    private var scene = PiPScene()
    private var lastTick = CACurrentMediaTime()
    private var formatDescription: CMVideoFormatDescription?
    private var possibleObservation: NSKeyValueObservation?
    private var pendingStart = false
    static let frameSize = CGSize(width: 400, height: 250)

    // MARK: Setup

    /// Called by the preview view on the menu; PiP needs the layer on screen.
    func attach(to view: UIView) {
        if displayLayer.superlayer !== view.layer {
            displayLayer.removeFromSuperlayer()
            view.layer.addSublayer(displayLayer)
        }
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspectFill
        makeControllerIfNeeded()
        startRendering()
    }

    private func makeControllerIfNeeded() {
        guard controller == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer,
                                                                playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        c.canStartPictureInPictureAutomaticallyFromInline = enabled
        controller = c
        possibleObservation = c.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { c, _ in
            let possible = c.isPictureInPicturePossible
            Task { @MainActor in
                PiPStatus.shared.possible = possible
                // A start asked for before PiP was ready goes through now.
                if possible, RoachPiP.shared.pendingStart {
                    RoachPiP.shared.pendingStart = false
                    RoachPiP.shared.controller?.startPictureInPicture()
                }
            }
        }
    }

    /// Let it loose: PiP pops up by itself when you leave the app.
    func enable() {
        enabled = true
        // Off the main thread: Xcode flags session setup there as a hang risk.
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        startRendering()
    }

    func disable() {
        enabled = false
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        controller?.stopPictureInPicture()
    }

    func popOutNow() {
        enable()
        guard let controller else {
            PiPStatus.shared.message = PiPStatus.shared.supported
                ? "No PiP controller yet (preview not on screen?)"
                : "Picture in Picture isn't supported here"
            return
        }
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            pendingStart = true
            PiPStatus.shared.message = "Waiting for PiP to become possible…"
        }
    }

    // MARK: Frames

    private func startRendering() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderFrame() }
        }
    }

    private func renderFrame() {
        let now = CACurrentMediaTime()
        scene.step(dt: min(now - lastTick, 0.1), size: Self.frameSize)
        lastTick = now

        let renderer = ImageRenderer(content: PiPSceneView(scene: scene)
            .frame(width: Self.frameSize.width, height: Self.frameSize.height))
        renderer.scale = 2
        guard let image = renderer.cgImage, let buffer = sampleBuffer(from: image) else { return }

        let output = displayLayer.sampleBufferRenderer
        if output.status == .failed { output.flush() }
        output.enqueue(buffer)
    }

    private func sampleBuffer(from image: CGImage) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
                                  kCVPixelFormatType_32BGRA, attrs, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                         imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                 formatDescription: formatDescription,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        if let sample, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    // MARK: Swat

    fileprivate func swat() {
        if scene.swat() {
            RoachLife.kills += 1
            SoundBoard.shared.play(.crunch)
        }
        controller?.invalidatePlaybackState()
    }
}

extension RoachPiP: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                setPlaying playing: Bool) {
        Task { @MainActor in self.swat() }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)   // live, no scrubber
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension RoachPiP: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            PiPStatus.shared.active = true
            PiPStatus.shared.message = ""
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in PiPStatus.shared.active = false }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in PiPStatus.shared.message = "PiP failed: \(text)" }
    }

    /// The "back to app" button in the PiP window: go hunt it in the game.
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .roachHunt, object: nil)
        }
        completionHandler(true)
    }
}

// MARK: - The little world inside the PiP window

struct PiPScene {
    var pos = CGPoint(x: 80, y: 140)
    var heading = 0.3
    var speed = 70.0
    var legPhase = 0.0
    var nextTurn = 0.0
    var pauseUntil = 0.0
    var sprintUntil = 0.0
    var splatUntil = 0.0
    var clock = 0.0
    var species: Species = .common

    mutating func step(dt: Double, size: CGSize) {
        clock += dt
        if clock < splatUntil { return }
        if splatUntil > 0, clock >= splatUntil {
            // A new one wanders in from the edge.
            splatUntil = 0
            pos = CGPoint(x: -20, y: .random(in: 60...(size.height - 60)))
            heading = .random(in: -0.4...0.4)
            species = [.common, .common, .common, .beetle, .red, .isopod].randomElement()!
        }
        if clock < pauseUntil {
            legPhase += dt * 2    // grooming the antennae
            return
        }
        if clock >= nextTurn {
            heading += .random(in: -1.2...1.2)
            nextTurn = clock + .random(in: 0.5...1.6)
            if Double.random(in: 0...1) < 0.2 { pauseUntil = clock + .random(in: 0.6...1.8) }
        }
        let v = clock < sprintUntil ? speed * 3 : speed
        pos.x += cos(heading) * v * dt
        pos.y += sin(heading) * v * dt
        legPhase += v * dt * 0.45
        let m: CGFloat = 26
        if pos.x < m { pos.x = m; heading = .pi - heading }
        if pos.x > size.width - m { pos.x = size.width - m; heading = .pi - heading }
        if pos.y < m { pos.y = m; heading = -heading }
        if pos.y > size.height - m { pos.y = size.height - m; heading = -heading }
    }

    /// Returns true on a kill.
    mutating func swat() -> Bool {
        guard clock >= splatUntil else { return false }
        if Double.random(in: 0...1) < 0.35 {
            splatUntil = clock + 2.5
            return true
        }
        sprintUntil = clock + 0.8
        heading += .pi + .random(in: -0.6...0.6)
        pauseUntil = 0
        return false
    }
}

/// One frame of the PiP window: a grimy wall with a roach on it.
struct PiPSceneView: View {
    let scene: PiPScene

    var body: some View {
        Canvas { gc, size in
            gc.fill(Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.17, blue: 0.14),
                                                            Color(red: 0.09, green: 0.07, blue: 0.06)]),
                                          startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var crack = Path()
            crack.move(to: CGPoint(x: size.width * 0.62, y: 0))
            crack.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.3))
            crack.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.55))
            crack.addLine(to: CGPoint(x: size.width * 0.6, y: size.height))
            gc.stroke(crack, with: .color(.black.opacity(0.7)), lineWidth: 3)

            if scene.clock < scene.splatUntil {
                let goo = Color(red: 0.80, green: 0.75, blue: 0.28).opacity(0.9)
                gc.fill(Path(ellipseIn: CGRect(x: scene.pos.x - 40, y: scene.pos.y - 28, width: 80, height: 56)),
                        with: .color(goo))
                BugArt.bug(gc, scene.species, at: scene.pos, heading: scene.heading,
                           scale: 1.8, legPhase: 0, flattened: true)
            } else {
                BugArt.bug(gc, scene.species, at: scene.pos, heading: scene.heading,
                           scale: 1.8, legPhase: scene.legPhase)
            }
        }
        .overlay(alignment: .topLeading) {
            if scene.clock < scene.splatUntil {
                Text("SPLAT!")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black, radius: 0, x: 3, y: 3)
                    .padding(14)
            }
        }
    }
}

/// Hosts the PiP layer on the menu, doubling as a live preview.
struct PiPPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PiPHostView { PiPHostView() }
    func updateUIView(_ uiView: PiPHostView, context: Context) {}
}

final class PiPHostView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        RoachPiP.shared.attach(to: self)
    }
}
