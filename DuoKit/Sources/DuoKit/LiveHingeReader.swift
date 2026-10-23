import SwiftUI

// The only file in DuoKit that touches Apple's iPhone Duo API.
//
// API shape (onHingeChange, DeviceHinge, .closed/.partiallyOpen/.fullyOpen,
// angle as SwiftUI `Angle`) follows Apple's Tech Talks and the open-source
// examples built on the iOS 27.1 SDK. If Xcode 27.1 disagrees, fix it here
// and nowhere else.

#if os(iOS)

public extension View {
    /// Feeds live hinge readings and the current display side into `monitor`.
    /// Put it once near the root of each window.
    func readsHinge(into monitor: HingeMonitor) -> some View {
        modifier(LiveHingeReader(monitor: monitor))
    }
}

struct LiveHingeReader: ViewModifier {
    let monitor: HingeMonitor
    @Environment(\.horizontalSizeClass) private var horizontal

    func body(content: Content) -> some View {
        hinged(content)
            .onAppear { report() }
            .onChange(of: horizontal) { report() }
    }

    @ViewBuilder
    private func hinged(_ content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, newContext in
                guard let hinge = newContext.hinge else {
                    monitor.ingestLive(nil)
                    return
                }
                let status: HingeStatus = switch hinge.status {
                case .closed: .closed
                case .partiallyOpen: .partiallyOpen
                case .fullyOpen: .fullyOpen
                default: .unknown
                }
                monitor.ingestLive(HingeReading(
                    // `Angle` handles the radians-vs-degrees question for us.
                    degrees: hinge.angle.degrees,
                    status: status
                ))
            }
        } else {
            content
        }
    }

    /// Outer display = compact width. The inner display reports regular in
    /// both dimensions when the app is full screen. A Split View pane on the
    /// inner display can also be compact, so with Split View this can be
    /// wrong; DeskSign doesn't care, a game might.
    private func report() {
        monitor.ingestLiveDisplay(isOuter: horizontal == .compact)
    }
}

#else

// macOS: no hinge. Exists so `swift test` can build the package on a Mac.
public extension View {
    func readsHinge(into monitor: HingeMonitor) -> some View { self }
}

#endif
