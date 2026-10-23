import SwiftUI

// Shared by the app and the widget extension: the five bugs and how to draw them.

/// Five kinds of bug. The rarer, the stranger, the more points.
enum Species: Int, CaseIterable, Identifiable, Sendable {
    case common, beetle, red, isopod, boss

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .common: String(localized: "Roach")
        case .beetle: String(localized: "Jade Beetle")
        case .red: String(localized: "Red Runner")
        case .isopod: String(localized: "Stripy Pillbug")
        case .boss: String(localized: "Purple Overlord")
        }
    }

    var points: Int {
        switch self {
        case .common: 1
        case .beetle: 2
        case .red: 3
        case .isopod: 5
        case .boss: 20
        }
    }

    /// Taps needed. The pillbug curls up first; the overlord shrugs off two.
    var hp: Int {
        switch self {
        case .isopod: 2
        case .boss: 3
        default: 1
        }
    }

    /// Spawn weight out of 100.
    var weight: Double {
        switch self {
        case .common: 70
        case .beetle: 14
        case .red: 10
        case .isopod: 5
        case .boss: 1
        }
    }

    var sizeRange: ClosedRange<CGFloat> {
        switch self {
        case .common: 0.55...0.75
        case .beetle: 0.75...0.9
        case .red: 0.7...0.85
        case .isopod: 0.8...0.95
        case .boss: 1.9...2.2
        }
    }

    var speedFactor: Double {
        switch self {
        case .common: 1
        case .beetle: 0.75
        case .red: 1.6
        case .isopod: 0.6
        case .boss: 0.55
        }
    }

    /// How fast it eats food, relative to a common roach.
    var appetite: Double {
        self == .boss ? 4 : 1
    }
}

/// Small seeded generator so each splat keeps the same shape every frame.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Draws the five bugs. All face +x at heading 0.
enum BugArt {

    static func bug(_ gc: GraphicsContext, _ species: Species, at pos: CGPoint, heading: Double,
                    scale: CGFloat, legPhase: Double, flattened: Bool = false,
                    curled: Bool = false, flash: Bool = false) {
        var c = gc
        c.translateBy(x: pos.x, y: pos.y)
        c.rotate(by: .radians(heading))
        c.scaleBy(x: scale, y: flattened ? scale * 1.3 : scale)
        if flash { c.addFilter(.brightness(0.45)) }
        let swing = flattened ? 0.9 : sin(legPhase)

        switch species {
        case .common: roach(c, swing: swing, legPhase: legPhase)
        case .beetle: beetle(c, swing: swing, legPhase: legPhase)
        case .red: redRunner(c, swing: swing, legPhase: legPhase)
        case .isopod: curled ? pillBall(c) : pillbug(c, swing: swing, legPhase: legPhase)
        case .boss: overlord(c, swing: swing, legPhase: legPhase)
        }
    }

    private static func legs(_ c: GraphicsContext, pairs: Int, spacing: CGFloat, start: CGFloat,
                             body: CGFloat, knee: CGFloat, reach: CGFloat, swing: Double,
                             color: Color, width: CGFloat) {
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        for i in 0..<pairs {
            let x = start + CGFloat(i) * spacing
            let phase = CGFloat(i % 2 == 0 ? swing : -swing)
            let splay = CGFloat(i) - CGFloat(pairs - 1) / 2
            for side in [-1.0, 1.0] {
                let s = CGFloat(side)
                var p = Path()
                p.move(to: CGPoint(x: x, y: s * body * 0.5))
                p.addLine(to: CGPoint(x: x + knee * 0.4 + phase * s * 3, y: s * (body + knee)))
                p.addLine(to: CGPoint(x: x + splay * knee * 0.8 + phase * s * 5, y: s * (body + reach)))
                c.stroke(p, with: .color(color), style: style)
            }
        }
    }

    private static func antennae(_ c: GraphicsContext, from x: CGFloat, length: CGFloat, spread: CGFloat,
                                 legPhase: Double, color: Color, width: CGFloat = 1) {
        let wave = CGFloat(sin(legPhase * 0.6))
        for side in [-1.0, 1.0] {
            let s = CGFloat(side)
            var a = Path()
            a.move(to: CGPoint(x: x, y: s * 1.5))
            a.addQuadCurve(to: CGPoint(x: x + length, y: s * (spread + wave * 3)),
                           control: CGPoint(x: x + length * 0.55, y: s * 1))
            c.stroke(a, with: .color(color), lineWidth: width)
        }
    }

    private static func gradient(_ light: Color, _ dark: Color, height h: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [light, dark]),
                        startPoint: CGPoint(x: 0, y: -h), endPoint: CGPoint(x: 0, y: h))
    }

    /// Stripes across an ellipse body (the bug faces +x, so stripes are vertical).
    private static func stripes(_ c: GraphicsContext, count: Int, from x0: CGFloat, step: CGFloat,
                                center cx: CGFloat, halfWidth a: CGFloat, halfHeight b: CGFloat,
                                color: Color, width: CGFloat) {
        for k in 0..<count {
            let x = x0 + CGFloat(k) * step
            let t = (x - cx) / a
            let h = b * sqrt(max(0, 1 - t * t)) * 0.92
            var p = Path()
            p.move(to: CGPoint(x: x, y: -h))
            p.addQuadCurve(to: CGPoint(x: x, y: h), control: CGPoint(x: x + 2.5, y: 0))
            c.stroke(p, with: .color(color), lineWidth: width)
        }
    }

    static let roachShell = Color(red: 0.47, green: 0.26, blue: 0.10)
    static let roachDark = Color(red: 0.24, green: 0.12, blue: 0.05)

    /// 小强: the classic brown roach.
    private static func roach(_ c: GraphicsContext, swing: Double, legPhase: Double) {
        legs(c, pairs: 3, spacing: 7, start: -6, body: 7, knee: 4, reach: 10,
             swing: swing, color: roachDark, width: 1.7)
        antennae(c, from: 19, length: 19, spread: 13, legPhase: legPhase, color: roachDark)
        c.fill(Path(ellipseIn: CGRect(x: -15, y: -7.5, width: 28, height: 15)),
               with: gradient(roachShell, roachDark, height: 7.5))
        var seam = Path()
        seam.move(to: CGPoint(x: -14, y: 0))
        seam.addLine(to: CGPoint(x: 9, y: 0))
        c.stroke(seam, with: .color(.black.opacity(0.35)), lineWidth: 0.8)
        c.fill(Path(ellipseIn: CGRect(x: 8, y: -6, width: 10, height: 12)), with: .color(roachDark))
        c.fill(Path(ellipseIn: CGRect(x: 10, y: -3.5, width: 5, height: 3)),
               with: .color(Color(red: 0.78, green: 0.58, blue: 0.32).opacity(0.7)))
        c.fill(Path(ellipseIn: CGRect(x: 16, y: -3, width: 5, height: 6)), with: .color(.black))
        c.fill(Path(ellipseIn: CGRect(x: -9, y: -5.5, width: 14, height: 3.5)), with: .color(.white.opacity(0.22)))
    }

    /// 翠甲虫: round, shiny teal-green beetle.
    private static func beetle(_ c: GraphicsContext, swing: Double, legPhase: Double) {
        let dark = Color(red: 0.03, green: 0.18, blue: 0.15)
        legs(c, pairs: 3, spacing: 6, start: -5, body: 7, knee: 3, reach: 7,
             swing: swing, color: dark, width: 1.6)
        antennae(c, from: 15, length: 8, spread: 7, legPhase: legPhase, color: dark)
        c.fill(Path(ellipseIn: CGRect(x: -11, y: -9, width: 22, height: 18)),
               with: gradient(Color(red: 0.30, green: 0.85, blue: 0.62), Color(red: 0.04, green: 0.38, blue: 0.32), height: 9))
        var seam = Path()
        seam.move(to: CGPoint(x: -10, y: 0))
        seam.addLine(to: CGPoint(x: 8, y: 0))
        c.stroke(seam, with: .color(dark.opacity(0.7)), lineWidth: 1)
        c.fill(Path(ellipseIn: CGRect(x: 7, y: -5.5, width: 7, height: 11)), with: .color(Color(red: 0.05, green: 0.3, blue: 0.26)))
        c.fill(Path(ellipseIn: CGRect(x: 12.5, y: -3, width: 4, height: 6)), with: .color(.black))
        c.fill(Path(ellipseIn: CGRect(x: -6, y: -7, width: 9, height: 4)), with: .color(.white.opacity(0.5)))
    }

    /// 红背飞毛腿: slim, red, long-legged, fast.
    private static func redRunner(_ c: GraphicsContext, swing: Double, legPhase: Double) {
        let dark = Color(red: 0.25, green: 0.03, blue: 0.03)
        legs(c, pairs: 3, spacing: 8, start: -8, body: 5, knee: 6, reach: 14,
             swing: swing, color: dark, width: 1.4)
        antennae(c, from: 18, length: 26, spread: 15, legPhase: legPhase, color: dark)
        c.fill(Path(ellipseIn: CGRect(x: -15, y: -5.5, width: 27, height: 11)),
               with: gradient(Color(red: 0.92, green: 0.22, blue: 0.16), Color(red: 0.45, green: 0.05, blue: 0.05), height: 5.5))
        c.fill(Path(ellipseIn: CGRect(x: 9, y: -4.5, width: 8, height: 9)), with: .color(dark))
        c.fill(Path(ellipseIn: CGRect(x: 15, y: -2.5, width: 5, height: 5)), with: .color(.black))
        c.fill(Path(ellipseIn: CGRect(x: -9, y: -4, width: 12, height: 2.5)), with: .color(.white.opacity(0.3)))
    }

    private static let pillDark = Color(red: 0.05, green: 0.10, blue: 0.30)
    private static let pillStripe = Color(red: 0.50, green: 0.75, blue: 1.0)

    /// 蓝纹球潮虫: segmented navy pillbug with pale blue bands and many legs.
    private static func pillbug(_ c: GraphicsContext, swing: Double, legPhase: Double) {
        legs(c, pairs: 7, spacing: 3.2, start: -10, body: 8, knee: 2, reach: 4,
             swing: swing, color: pillDark, width: 1.3)
        antennae(c, from: 14, length: 8, spread: 8, legPhase: legPhase, color: pillDark)
        c.fill(Path(ellipseIn: CGRect(x: -12.5, y: -9, width: 25, height: 18)),
               with: gradient(Color(red: 0.18, green: 0.32, blue: 0.70), pillDark, height: 9))
        stripes(c, count: 7, from: -9, step: 3.2, center: 0, halfWidth: 12.5, halfHeight: 9,
                color: pillStripe, width: 1.4)
        c.fill(Path(ellipseIn: CGRect(x: 10.5, y: -4, width: 4.5, height: 8)), with: .color(pillDark))
    }

    /// The pillbug rolled up after a tap.
    private static func pillBall(_ c: GraphicsContext) {
        c.fill(Path(ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20)),
               with: gradient(Color(red: 0.2, green: 0.35, blue: 0.75), pillDark, height: 10))
        for r in [7.0, 4.0] {
            c.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                     with: .color(pillStripe), lineWidth: 1.4)
        }
        c.fill(Path(ellipseIn: CGRect(x: -6, y: -8, width: 7, height: 4)), with: .color(.white.opacity(0.45)))
    }

    /// 紫纹霸王: big purple-and-gold striped boss with long spindly legs.
    private static func overlord(_ c: GraphicsContext, swing: Double, legPhase: Double) {
        let dark = Color(red: 0.16, green: 0.04, blue: 0.26)
        legs(c, pairs: 3, spacing: 9, start: -9, body: 10, knee: 10, reach: 24,
             swing: swing * 0.7, color: dark, width: 1.4)
        antennae(c, from: 25, length: 28, spread: 22, legPhase: legPhase, color: dark, width: 1.2)
        c.fill(Path(ellipseIn: CGRect(x: -17, y: -11.5, width: 34, height: 23)),
               with: gradient(Color(red: 0.62, green: 0.30, blue: 0.85), Color(red: 0.25, green: 0.07, blue: 0.40), height: 11.5))
        stripes(c, count: 6, from: -13, step: 5, center: 0, halfWidth: 17, halfHeight: 11.5,
                color: Color(red: 0.98, green: 0.80, blue: 0.30).opacity(0.9), width: 1.8)
        c.fill(Path(ellipseIn: CGRect(x: 13, y: -7, width: 9, height: 14)), with: .color(dark))
        c.fill(Path(ellipseIn: CGRect(x: 20, y: -4, width: 6, height: 8)), with: .color(.black))
        c.fill(Path(ellipseIn: CGRect(x: -10, y: -9, width: 16, height: 4)), with: .color(.white.opacity(0.25)))
    }
}
