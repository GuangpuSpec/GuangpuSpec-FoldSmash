import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The roach hiding inside the Dynamic Island. Usually nothing shows; now and
/// then its two long antennae poke out, feel around and snap back in. No words.
struct RoachIslandActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoachActivityAttributes.self) { context in
            LockScreenRoach(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    // A roach peeking up from under the island, antennae out.
                    ZStack(alignment: .trailing) {
                        IslandRoach(state: context.state)
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 8) {
                            if context.state.mood == .outer {
                                Link(destination: RoachLife.huntURL) {
                                    RoundIcon(systemName: "iphone.gen3", color: .yellow)
                                }
                                .accessibilityLabel("Go squash")
                            }
                            Button(intent: SwatIslandIntent()) {
                                RoundIcon(systemName: "hand.raised.fill", color: .orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Swat it!")
                        }
                    }
                    .frame(height: 84)
                }
            } compactLeading: {
                Antennae(state: context.state, size: 30)
            } compactTrailing: {
                Color.clear.frame(width: 4, height: 4)
            } minimal: {
                Antennae(state: context.state, size: 22)
            }
            .widgetURL(RoachLife.huntURL)
            .keylineTint(Color(red: 0.55, green: 0.33, blue: 0.15))
        }
    }
}

/// Two jointed antennae rooted in the bottom-trailing corner (the island
/// side) and reaching diagonally out across the square. Diagonal reads right
/// on both the horizontal island and the iPhone Duo's vertical one. Each has
/// a base half and a tip half that bend separately, so it feels around rather
/// than swings.
struct Antennae: View {
    let state: RoachActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        let length = size * 1.2
        Color.clear
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .trailing) {
                    Antenna(base: state.upper, tip: state.upperTip, length: length, reach: state.reach, rootY: -1.5)
                    Antenna(base: state.lower, tip: state.lowerTip, length: length, reach: state.lowerReach, rootY: 1.5)
                }
                .frame(width: length * 1.05, height: 10, alignment: .trailing)
                .rotationEffect(.degrees(45), anchor: .trailing)
            }
            .animation(state.motion, value: state)
            .accessibilityHidden(true)
    }
}

extension RoachActivityAttributes.ContentState {
    /// How the island moves to this pose.
    var motion: Animation {
        switch beat {
        case .emerge: .spring(response: 0.42, dampingFraction: 0.55)
        case .feel: .easeInOut(duration: min(1.6, max(0.3, glide)))
        case .flick: .easeOut(duration: min(0.3, max(0.1, glide)))
        case .retreat: .easeIn(duration: 0.16)
        case .still: .easeInOut(duration: 0.8)
        }
    }
}

private struct Antenna: View {
    let base: Double
    let tip: Double
    let length: CGFloat
    let reach: Double
    let rootY: CGFloat
    var thickness: CGFloat = 2.8

    private static let color = Color(red: 0.72, green: 0.45, blue: 0.22)

    var body: some View {
        // Drawn pointing left from the root at the trailing edge.
        Segment(width: thickness, taper: thickness * 0.57)
            .fill(Self.color)
            .frame(width: length * 0.5, height: 5)
            .overlay(alignment: .leading) {
                Segment(width: thickness * 0.57, taper: thickness * 0.18)
                    .fill(Self.color.opacity(0.9))
                    .frame(width: length * 0.55, height: 5)
                    .offset(x: -length * 0.55)
                    .rotationEffect(.degrees(-tip), anchor: .leading)
            }
            .rotationEffect(.degrees(-base), anchor: .trailing)
            // Slides out of / back into the island at the root.
            .scaleEffect(x: max(0.01, reach), anchor: .trailing)
            .opacity(reach < 0.03 ? 0 : 1)
            .offset(y: rootY)
    }
}

/// A slightly curved, tapering stroke running right to left.
private struct Segment: Shape {
    let width: CGFloat
    let taper: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midY
        p.move(to: CGPoint(x: rect.maxX, y: mid - width / 2))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: mid - taper / 2),
                       control: CGPoint(x: rect.midX, y: mid - width / 2 - 1))
        p.addLine(to: CGPoint(x: rect.minX, y: mid + taper / 2))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: mid + width / 2),
                       control: CGPoint(x: rect.midX, y: mid + width / 2 - 1))
        p.closeSubpath()
        return p
    }
}

/// Lock Screen: the same peeking roach, and a swat button.
private struct LockScreenRoach: View {
    let state: RoachActivityAttributes.ContentState

    var body: some View {
        ZStack(alignment: .trailing) {
            IslandRoach(state: state)
                .frame(maxWidth: .infinity)
            Button(intent: SwatIslandIntent()) {
                RoundIcon(systemName: "hand.raised.fill", color: .orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swat it!")
        }
        .frame(height: 84)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A head half-hidden under the bottom edge, two long antennae sweeping out
/// to either side and feeling around. Pose comes from the content state.
struct IslandRoach: View {
    let state: RoachActivityAttributes.ContentState

    var body: some View {
        let length: CGFloat = 70
        ZStack(alignment: .bottom) {
            HStack(spacing: 6) {
                // Left antenna: up and out to the left.
                Antenna(base: -38 + state.upper * 0.7, tip: state.upperTip,
                        length: length, reach: max(0.25, state.reach), rootY: 0, thickness: 3.2)
                    .frame(width: length * 1.05, height: 10, alignment: .trailing)
                // Right antenna: mirrored, up and out to the right.
                Antenna(base: -38 - state.lower * 0.7, tip: -state.lowerTip,
                        length: length, reach: max(0.25, state.lowerReach), rootY: 0, thickness: 3.2)
                    .frame(width: length * 1.05, height: 10, alignment: .trailing)
                    .scaleEffect(x: -1)
            }
            .offset(y: -24)

            RoachHead()
                .frame(width: 46, height: 40)
                // Ducks lower when it's hiding.
                .offset(y: state.isOut || state.mood == .dead ? 12 : 26)
        }
        .frame(height: 84)
        .clipped()
        .animation(state.motion, value: state)
        .accessibilityHidden(true)
    }
}

/// Head and the front edge of the shell, seen from above.
private struct RoachHead: View {
    var body: some View {
        ZStack(alignment: .top) {
            Ellipse()
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.23, blue: 0.09),
                                              Color(red: 0.2, green: 0.1, blue: 0.04)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 46, height: 34)
                .offset(y: 10)
            Ellipse()
                .fill(Color(red: 0.12, green: 0.06, blue: 0.03))
                .frame(width: 22, height: 16)
            Ellipse()
                .fill(.white.opacity(0.25))
                .frame(width: 18, height: 5)
                .offset(x: -6, y: 16)
        }
    }
}

private struct RoundIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 46, height: 46)
            .background(color, in: .circle)
    }
}
