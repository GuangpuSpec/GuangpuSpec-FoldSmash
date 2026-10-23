import SwiftUI

// The shared design system for the three iPhone Duo apps.
//
// Controls are never drawn here: every screen uses NavigationStack and
// .toolbar, and the system lays the bar out (vertically on the side on
// iPhone Duo). This file only holds colour, spacing and type. Type is SF Pro
// on one scale; colour is warm paper and tinted ink with one sun-yellow accent.

public enum Duo {
    // MARK: Colour (tinted neutrals, never pure black or grey)

    public static let paper = adaptive(0xF5F4F0, 0x131210)
    /// The dock and grouped rows.
    public static let surface = adaptive(0xE9E7E1, 0x1F1E1B)
    /// Something selected or raised inside the content.
    public static let raised = adaptive(0xFFFFFF, 0x2A2925)
    public static let line = adaptive(0xDCD9D1, 0x34322E)
    public static let ink = adaptive(0x1C1B17, 0xEFEDE7)
    public static let ink2 = adaptive(0x4D4B45, 0xB5B2AA)
    /// Captions. Still 4.5:1 on paper.
    public static let ink3 = adaptive(0x67645D, 0x928F87)

    public static let sun = rgb(0xFFC52A)
    /// Text that sits on sun.
    public static let onSun = rgb(0x2A2105)
    /// Sun as text on paper.
    public static let sunInk = adaptive(0x775600, 0xFFC52A)

    /// LED screens (the desk sign, the game's night maps).
    public static let screen = rgb(0x100F0D)
    public static let screenText = rgb(0xF4F1E8)

    public static let approve = rgb(0x1FA75E)
    public static let reject = adaptive(0xD8342B, 0xFF5A50)
    public static let waiting = rgb(0xE08A00)

    // MARK: Spacing (8-point rhythm)

    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
        /// Distance kept from every physical edge of the screen.
        public static let edge: CGFloat = 24
    }

    // MARK: Type scale

    public enum TypeScale {
        /// One per screen: the screen's subject.
        public static let display = Font.system(size: 34, weight: .bold)
        public static let title = Font.system(size: 28, weight: .bold)
        public static let title2 = Font.system(size: 22, weight: .semibold)
        public static let headline = Font.system(size: 17, weight: .semibold)
        public static let body = Font.system(size: 17)
        public static let callout = Font.system(size: 15)
        public static let footnote = Font.system(size: 13)
        public static let caption = Font.system(size: 12, weight: .medium)
        /// Big numbers that change: scores, timers.
        public static func number(_ size: CGFloat) -> Font {
            .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
        }
    }

    // MARK: Helpers

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
        #else
        return rgb(light)
        #endif
    }
}

// MARK: - Content helpers

/// A small heading over a group of content.
public struct SectionHeading: View {
    let text: Text

    public init(_ key: LocalizedStringKey) { text = Text(key) }
    public init(verbatim: String) { text = Text(verbatim: verbatim) }

    public var body: some View {
        text
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Duo.ink3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Short name for the type scale: `DuoType.title`.
public typealias DuoType = Duo.TypeScale
