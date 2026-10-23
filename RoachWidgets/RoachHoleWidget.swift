import AppIntents
import SwiftUI
import WidgetKit

/// Which hole this widget is. Put four on the Home Screen, numbered 1–4.
struct HoleConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Roach Hole"
    static let description = IntentDescription("A crack in your Home Screen. Add up to four and number them 1–4.")

    @Parameter(title: "Hole number", default: 1, inclusiveRange: (1, 4))
    var hole: Int
}

struct HoleEntry: TimelineEntry {
    let date: Date
    let hole: Int
    let roachHere: Bool
    let splat: Bool
}

struct HoleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HoleEntry {
        HoleEntry(date: .now, hole: 1, roachHere: true, splat: false)
    }

    func snapshot(for configuration: HoleConfigIntent, in context: Context) async -> HoleEntry {
        entry(for: configuration.hole, at: .now)
    }

    func timeline(for configuration: HoleConfigIntent, in context: Context) async -> Timeline<HoleEntry> {
        // One entry now, then one each time the roach changes hole.
        let now = Date()
        var entries = [entry(for: configuration.hole, at: now)]
        for date in RoachLife.changeDates(after: now, count: 24) {
            entries.append(entry(for: configuration.hole, at: date.addingTimeInterval(0.5)))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(for hole: Int, at date: Date) -> HoleEntry {
        HoleEntry(date: date, hole: hole,
                  roachHere: RoachLife.hole(at: date) == hole,
                  splat: RoachLife.isSplatted(hole: hole, at: date))
    }
}

struct RoachHoleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: RoachLife.widgetKind, intent: HoleConfigIntent.self,
                               provider: HoleProvider()) { entry in
            RoachHoleView(entry: entry)
        }
        .configurationDisplayName("Roach Hole")
        .description("A crack in your Home Screen. Add up to four and number them 1–4.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct RoachHoleView: View {
    let entry: HoleEntry

    var body: some View {
        Button(intent: SwatHoleIntent(hole: entry.hole)) {
            ZStack {
                Crack()
                if entry.splat {
                    SplatMark()
                        .transition(.scale.combined(with: .opacity))
                } else if entry.roachHere {
                    PeekingRoach(seed: Int(entry.date.timeIntervalSince1970))
                        .transition(.push(from: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)],
                           startPoint: .top, endPoint: .bottom)
        }
        .widgetURL(RoachLife.huntURL)
    }
}

/// A dark crack the roach lives in.
private struct Crack: View {
    var body: some View {
        Canvas { gc, size in
            var crack = Path()
            let y = size.height * 0.72
            crack.move(to: CGPoint(x: size.width * 0.12, y: y))
            crack.addLine(to: CGPoint(x: size.width * 0.3, y: y - 8))
            crack.addLine(to: CGPoint(x: size.width * 0.45, y: y + 4))
            crack.addLine(to: CGPoint(x: size.width * 0.6, y: y - 6))
            crack.addLine(to: CGPoint(x: size.width * 0.78, y: y + 5))
            crack.addLine(to: CGPoint(x: size.width * 0.9, y: y - 2))
            crack.addLine(to: CGPoint(x: size.width * 0.78, y: y + 12))
            crack.addLine(to: CGPoint(x: size.width * 0.6, y: y + 6))
            crack.addLine(to: CGPoint(x: size.width * 0.45, y: y + 14))
            crack.addLine(to: CGPoint(x: size.width * 0.3, y: y + 4))
            crack.closeSubpath()
            gc.fill(crack, with: .color(.black))
            gc.stroke(crack, with: .color(.white.opacity(0.12)), lineWidth: 1)
        }
    }
}

/// Head and antennae poking up out of the crack.
private struct PeekingRoach: View {
    let seed: Int

    var body: some View {
        Canvas { gc, size in
            var rng = SplitMix64(state: UInt64(truncatingIfNeeded: seed))
            let species: Species = Int(rng.next() % 10) == 0 ? .boss : (Int(rng.next() % 4) == 0 ? .beetle : .common)
            let tilt = Double(rng.next() % 40) / 100 - 0.2
            let x = size.width * (0.35 + CGFloat(rng.next() % 30) / 100)
            BugArt.bug(gc, species, at: CGPoint(x: x, y: size.height * 0.6),
                       heading: -.pi / 2 + tilt,
                       scale: species == .boss ? 1.6 : 2.4, legPhase: 1.2)
        }
        .mask(alignment: .top) {
            // Hide the back half below the crack line.
            Rectangle().frame(maxHeight: .infinity).padding(.bottom, 34)
        }
    }
}

private struct SplatMark: View {
    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
            let goo = Color(red: 0.80, green: 0.75, blue: 0.28).opacity(0.9)
            gc.fill(Path(ellipseIn: CGRect(x: center.x - 44, y: center.y - 30, width: 88, height: 60)), with: .color(goo))
            for (dx, dy, r) in [(-52.0, -10.0, 9.0), (48.0, 14.0, 7.0), (10.0, -40.0, 6.0), (-20.0, 34.0, 8.0)] {
                gc.fill(Path(ellipseIn: CGRect(x: center.x + dx - r, y: center.y + dy - r, width: r * 2, height: r * 2)), with: .color(goo))
            }
            BugArt.bug(gc, .common, at: center, heading: 0.4, scale: 2.2, legPhase: 0, flattened: true)
        }
        .overlay(alignment: .top) {
            Text("SPLAT!")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.yellow)
                .padding(.top, 10)
        }
    }
}
