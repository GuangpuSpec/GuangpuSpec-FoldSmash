import SwiftUI

/// A floating panel: live readout plus a fake hinge you can drive with a
/// slider. Lets every app be built and played without the device.
public struct HingeDebugPanel: View {
    @Bindable var monitor: HingeMonitor
    @State private var expanded = false

    public init(monitor: HingeMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
                    Text(summary).monospacedDigit()
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)

            if expanded {
                Picker("Source", selection: $monitor.source) {
                    Text("Live").tag(HingeMonitor.Source.live)
                    Text("Fake").tag(HingeMonitor.Source.simulated)
                }
                .pickerStyle(.segmented)

                if monitor.source == .simulated {
                    Slider(value: $monitor.simulatedDegrees, in: 0...180)
                    Toggle("App on outer display", isOn: $monitor.simulatedOuterDisplay)
                        .font(.caption)
                    HStack {
                        preset("Shut", 0, outer: true)
                        preset("Tent", 100, outer: true)
                        preset("Book", 110, outer: false)
                        preset("Flat", 180, outer: false)
                    }
                } else if !monitor.hasLiveHinge {
                    Text("No live hinge yet. Fold in Device Hub, or switch to Fake.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(String(format: "%.0f°/s", monitor.velocity))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: expanded ? 280 : nil, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }

    private var summary: String {
        guard let r = monitor.reading else { return monitor.pose.label }
        return "\(monitor.pose.label) · \(Int(r.degrees.rounded()))°"
    }

    private func preset(_ title: String, _ degrees: Double, outer: Bool) -> some View {
        Button(title) {
            monitor.simulatedOuterDisplay = outer
            monitor.simulatedDegrees = degrees
        }
        .font(.caption2)
        .buttonStyle(.bordered)
    }
}
