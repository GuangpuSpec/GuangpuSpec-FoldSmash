import SwiftUI

/// Everything is drawn in code: five bugs, eight food scraps, splats, maps.
enum Art {

    // MARK: - Bugs (drawing lives in Shared/BugArt.swift, used by the widgets too)

    static func bug(_ gc: GraphicsContext, _ species: Species, at pos: CGPoint, heading: Double,
                    scale: CGFloat, legPhase: Double, flattened: Bool = false,
                    curled: Bool = false, flash: Bool = false) {
        BugArt.bug(gc, species, at: pos, heading: heading, scale: scale, legPhase: legPhase,
                   flattened: flattened, curled: curled, flash: flash)
    }

    // MARK: - Food

    static func food(_ gc: GraphicsContext, _ f: Food, now: TimeInterval) {
        var c = gc
        // Tossed scraps drop in with a little bounce.
        let age = now - f.born
        let drop = age < 0.35 ? age / 0.35 : 1
        let lift = CGFloat(sin(drop * .pi)) * 30
        c.translateBy(x: f.pos.x, y: f.pos.y - lift)
        c.rotate(by: .radians(f.angle))
        c.scaleBy(x: f.scale * (0.5 + 0.5 * drop), y: f.scale * (0.5 + 0.5 * drop))
        c.addFilter(.shadow(color: .black.opacity(0.3), radius: 3, x: 1, y: 2))

        let kind = f.kind
        let seed = UInt64(truncatingIfNeeded: f.id.hashValue)
        if f.amount > 0.66 {
            drawFood(c, kind)
        } else {
            // Bitten: erase a scalloped chunk, scatter crumbs.
            let crumbs = f.amount <= 0.33
            c.drawLayer { layer in
                drawFood(layer, kind)
                layer.blendMode = .destinationOut
                let cut: CGFloat = crumbs ? -22 : 4
                layer.fill(Path(CGRect(x: cut + 4, y: -60, width: 80, height: 120)), with: .color(.black))
                for y in stride(from: -30.0, through: 30.0, by: 12.0) {
                    layer.fill(Path(ellipseIn: CGRect(x: cut - 3, y: y - 7, width: 14, height: 14)), with: .color(.black))
                }
            }
            var rng = SplitMix64(state: seed)
            let color = crumbColor(kind)
            for _ in 0..<(crumbs ? 9 : 5) {
                let x = CGFloat.random(in: 2...30, using: &rng)
                let y = CGFloat.random(in: -24...24, using: &rng)
                let r = CGFloat.random(in: 1.5...3.5, using: &rng)
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 1.6)), with: .color(color))
            }
        }
    }

    private static func crumbColor(_ kind: FoodKind) -> Color {
        switch kind {
        case .pizza, .fries: Color(red: 0.98, green: 0.78, blue: 0.25)
        case .banana: Color(red: 0.98, green: 0.88, blue: 0.45)
        case .bread, .cookie: Color(red: 0.85, green: 0.68, blue: 0.42)
        case .apple, .fishbone, .rice: Color(red: 0.97, green: 0.95, blue: 0.88)
        }
    }

    private static func drawFood(_ c: GraphicsContext, _ kind: FoodKind) {
        let outline = Color.black.opacity(0.18)
        switch kind {
        case .pizza:
            var slice = Path()
            slice.move(to: CGPoint(x: -24, y: -24))
            slice.addLine(to: CGPoint(x: 30, y: 0))
            slice.addLine(to: CGPoint(x: -24, y: 24))
            slice.closeSubpath()
            c.fill(slice, with: .color(Color(red: 0.99, green: 0.80, blue: 0.25)))
            var crust = Path()
            crust.move(to: CGPoint(x: -24, y: -24))
            crust.addLine(to: CGPoint(x: -24, y: 24))
            c.stroke(crust, with: .color(Color(red: 0.62, green: 0.36, blue: 0.15)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            for (x, y) in [(-12.0, -8.0), (-10.0, 10.0), (4.0, 1.0)] {
                c.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(Color(red: 0.8, green: 0.15, blue: 0.1)))
            }
            for (x, y) in [(-4.0, -9.0), (-16.0, 2.0), (10.0, 4.0)] {
                c.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(Color(red: 0.2, green: 0.6, blue: 0.2)))
            }
        case .banana:
            for k in 0..<3 {
                var petal = c
                petal.rotate(by: .degrees(Double(k) * 120 + 10))
                let leaf = Path(ellipseIn: CGRect(x: 2, y: -6, width: 30, height: 12))
                petal.fill(leaf, with: .color(Color(red: 0.98, green: 0.88, blue: 0.42)))
                petal.stroke(leaf, with: .color(Color(red: 0.75, green: 0.6, blue: 0.2)), lineWidth: 1)
                petal.fill(Path(ellipseIn: CGRect(x: 27, y: -3, width: 6, height: 6)), with: .color(Color(red: 0.4, green: 0.25, blue: 0.1)))
            }
            c.fill(Path(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10)), with: .color(Color(red: 0.55, green: 0.42, blue: 0.15)))
        case .fries:
            for (x, y, a) in [(-14.0, -6.0, -10.0), (-6.0, 4.0, 15.0), (2.0, -8.0, -25.0), (10.0, 6.0, 5.0), (16.0, -4.0, 30.0)] {
                var fry = c
                fry.translateBy(x: x, y: y)
                fry.rotate(by: .degrees(a))
                let r = Path(roundedRect: CGRect(x: -3, y: -18, width: 6, height: 36), cornerRadius: 1.5)
                fry.fill(r, with: .color(Color(red: 0.98, green: 0.76, blue: 0.22)))
                fry.stroke(r, with: .color(Color(red: 0.8, green: 0.5, blue: 0.1)), lineWidth: 1)
            }
        case .bread:
            let slice = Path(roundedRect: CGRect(x: -20, y: -24, width: 40, height: 48), cornerRadius: 13)
            c.fill(slice, with: .color(Color(red: 0.94, green: 0.84, blue: 0.62)))
            c.stroke(slice, with: .color(Color(red: 0.66, green: 0.42, blue: 0.2)), lineWidth: 4.5)
            for (x, y) in [(-6.0, -8.0), (5.0, 3.0), (-3.0, 12.0), (8.0, -12.0)] {
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)), with: .color(Color(red: 0.7, green: 0.55, blue: 0.35)))
            }
        case .apple:
            c.fill(Path(ellipseIn: CGRect(x: -20, y: -12, width: 12, height: 24)), with: .color(Color(red: 0.85, green: 0.12, blue: 0.12)))
            c.fill(Path(ellipseIn: CGRect(x: 8, y: -12, width: 12, height: 24)), with: .color(Color(red: 0.85, green: 0.12, blue: 0.12)))
            var core = Path()
            core.move(to: CGPoint(x: -14, y: -11))
            core.addQuadCurve(to: CGPoint(x: 14, y: -11), control: CGPoint(x: 0, y: -3))
            core.addLine(to: CGPoint(x: 14, y: 11))
            core.addQuadCurve(to: CGPoint(x: -14, y: 11), control: CGPoint(x: 0, y: 3))
            core.closeSubpath()
            c.fill(core, with: .color(Color(red: 0.98, green: 0.95, blue: 0.85)))
            c.stroke(core, with: .color(outline), lineWidth: 1)
            for x in [-3.0, 2.0] {
                c.fill(Path(ellipseIn: CGRect(x: x, y: -2, width: 3, height: 4)), with: .color(Color(red: 0.35, green: 0.2, blue: 0.1)))
            }
        case .fishbone:
            let bone = Color(red: 0.97, green: 0.96, blue: 0.9)
            var spine = Path()
            spine.move(to: CGPoint(x: -24, y: 0))
            spine.addLine(to: CGPoint(x: 18, y: 0))
            c.stroke(spine, with: .color(bone), lineWidth: 3)
            for x in stride(from: -16.0, through: 12.0, by: 6.0) {
                for s in [-1.0, 1.0] {
                    var rib = Path()
                    rib.move(to: CGPoint(x: x, y: 0))
                    rib.addQuadCurve(to: CGPoint(x: x - 5, y: s * 13), control: CGPoint(x: x + 2, y: s * 8))
                    c.stroke(rib, with: .color(bone), lineWidth: 1.8)
                }
            }
            var head = Path()
            head.move(to: CGPoint(x: 16, y: -9))
            head.addLine(to: CGPoint(x: 32, y: 0))
            head.addLine(to: CGPoint(x: 16, y: 9))
            head.closeSubpath()
            c.fill(head, with: .color(bone))
            var tail = Path()
            tail.move(to: CGPoint(x: -24, y: 0))
            tail.addLine(to: CGPoint(x: -34, y: -9))
            tail.addLine(to: CGPoint(x: -34, y: 9))
            tail.closeSubpath()
            c.fill(tail, with: .color(bone))
        case .rice:
            var rng = SplitMix64(state: 42)
            for _ in 0..<22 {
                var grain = c
                grain.translateBy(x: CGFloat.random(in: -20...20, using: &rng), y: CGFloat.random(in: -16...16, using: &rng))
                grain.rotate(by: .radians(Double.random(in: 0..<(2 * .pi), using: &rng)))
                grain.fill(Path(ellipseIn: CGRect(x: -4, y: -2, width: 8, height: 4)),
                           with: .color(Color(red: 0.98, green: 0.97, blue: 0.92)))
            }
            for (x, y, color) in [(-8.0, 4.0, Color.orange), (6.0, -6.0, Color.green), (10.0, 8.0, Color.orange)] {
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 4, height: 4)), with: .color(color))
            }
        case .cookie:
            let disc = Path(ellipseIn: CGRect(x: -20, y: -20, width: 40, height: 40))
            c.fill(disc, with: .color(Color(red: 0.86, green: 0.66, blue: 0.40)))
            c.stroke(disc, with: .color(Color(red: 0.65, green: 0.45, blue: 0.22)), lineWidth: 2)
            for (x, y) in [(-9.0, -8.0), (4.0, -11.0), (8.0, 4.0), (-5.0, 7.0), (-12.0, 2.0)] {
                c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 5, height: 4)), with: .color(Color(red: 0.3, green: 0.17, blue: 0.08)))
            }
        }
    }

    // MARK: - Splat

    static func splat(_ gc: GraphicsContext, _ s: Splat, now: TimeInterval) {
        let age = now - s.born
        var c = gc
        c.opacity = age > 9 ? max(0, 1 - (age - 9) / 5) : 1
        // Squash and stretch: lands flattened (wide and low), then springs
        // back with a small elastic wobble, settled within ~250 ms.
        let a = max(0, age)
        let wobble = exp(-a * 14) * cos(a * 36)
        let grow = min(1, 0.7 + a * 8)
        c.translateBy(x: s.pos.x, y: s.pos.y)
        c.rotate(by: .radians(s.angle))
        c.scaleBy(x: s.scale * grow * (1 + 0.34 * wobble), y: s.scale * grow * (1 - 0.3 * wobble))

        var rng = SplitMix64(state: s.seed)
        let goo = Color(red: 0.80, green: 0.75, blue: 0.28).opacity(0.88)
        let gooDark = Color(red: 0.55, green: 0.44, blue: 0.12).opacity(0.85)

        c.fill(Path(ellipseIn: CGRect(x: -21, y: -15, width: 42, height: 30)), with: .color(goo))
        for _ in 0..<10 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let d = CGFloat.random(in: 16...32, using: &rng)
            let r = CGFloat.random(in: 2...6.5, using: &rng)
            let color = Bool.random(using: &rng) ? goo : gooDark
            c.fill(Path(ellipseIn: CGRect(x: cos(a) * d - r, y: sin(a) * d - r, width: r * 2, height: r * 2)),
                   with: .color(color))
        }
        let bodyScale: CGFloat = s.species == .boss ? 0.55 : 0.95
        bug(c, s.species, at: .zero, heading: Double.random(in: 0..<(2 * .pi), using: &rng),
            scale: bodyScale, legPhase: 0, flattened: true)
        c.fill(Path(ellipseIn: CGRect(x: -11, y: -8, width: 20, height: 16)), with: .color(gooDark.opacity(0.4)))
    }

    // MARK: - Impact effects

    static func particles(_ gc: GraphicsContext, _ list: [Particle], inner: Bool, now: TimeInterval) {
        let goo = Color(red: 0.84, green: 0.78, blue: 0.3)
        let gooDark = Color(red: 0.55, green: 0.44, blue: 0.12)
        for p in list where p.inner == inner {
            let age = now - p.born
            guard age >= 0 else { continue }
            let k = age / p.life
            let pos = p.position(age: age)
            // Stretched along its flight while fast, round once it lands.
            let speed = exp(-7 * age)
            let len = p.size * (1 + 2.2 * speed)
            let angle = atan2(p.velocity.dy, p.velocity.dx)
            var c = gc
            c.opacity = k > 0.6 ? max(0, 1 - (k - 0.6) / 0.4) : 1
            c.translateBy(x: pos.x, y: pos.y)
            c.rotate(by: .radians(angle))
            let color: Color = switch p.tint {
            case .goo: goo
            case .gooDark: gooDark
            case .spark: .yellow
            case .white: .white
            }
            c.fill(Path(ellipseIn: CGRect(x: -len / 2, y: -p.size / 2, width: len, height: p.size)), with: .color(color))
        }
    }

    static func rings(_ gc: GraphicsContext, _ list: [Ring], inner: Bool, now: TimeInterval) {
        for r in list where r.inner == inner {
            let k = min(1, (now - r.born) / Ring.life)
            let ease = 1 - pow(1 - k, 3)
            let radius = r.radius * (0.25 + 0.75 * ease)
            var c = gc
            c.opacity = 1 - k
            let color: Color = r.gold ? .yellow : .white
            c.stroke(Path(ellipseIn: CGRect(x: r.pos.x - radius, y: r.pos.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(color), lineWidth: r.width * (1 - k * 0.6))
        }
    }

    // MARK: - Hideouts

    static func background(_ map: GameMap, _ gc: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        switch map {
        case .kitchen: kitchen(gc, rect)
        case .fridge: fridge(gc, rect)
        case .closet: closet(gc, rect)
        case .office: office(gc, rect)
        case .desktop: desktop(gc, rect)
        case .homeScreen: homeScreen(gc, rect)
        }
    }

    /// Checkered floor tiles with grout.
    private static func kitchen(_ gc: GraphicsContext, _ rect: CGRect) {
        gc.fill(Path(rect), with: .color(Color(red: 0.93, green: 0.89, blue: 0.80)))
        let t: CGFloat = 56
        var dark = Path()
        var grout = Path()
        var row = 0
        var y: CGFloat = 0
        while y < rect.height {
            var col = 0
            var x: CGFloat = 0
            while x < rect.width {
                if (row + col) % 2 == 0 { dark.addRect(CGRect(x: x, y: y, width: t, height: t)) }
                x += t
                col += 1
            }
            grout.addRect(CGRect(x: 0, y: y, width: rect.width, height: 2))
            y += t
            row += 1
        }
        var x: CGFloat = 0
        while x < rect.width {
            grout.addRect(CGRect(x: x, y: 0, width: 2, height: rect.height))
            x += t
        }
        gc.fill(dark, with: .color(Color(red: 0.84, green: 0.77, blue: 0.64)))
        gc.fill(grout, with: .color(Color(red: 0.62, green: 0.58, blue: 0.52).opacity(0.6)))
    }

    /// Cold white interior, glass shelves, some groceries.
    private static func fridge(_ gc: GraphicsContext, _ rect: CGRect) {
        gc.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.80, green: 0.89, blue: 0.97)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: rect.height)))
        let shelves = [rect.height / 3, rect.height * 2 / 3, rect.height - 6]
        for y in shelves.dropLast() {
            gc.fill(Path(CGRect(x: 0, y: y - 3, width: rect.width, height: 6)), with: .color(.white.opacity(0.8)))
            gc.fill(Path(CGRect(x: 0, y: y + 3, width: rect.width, height: 2)),
                    with: .color(Color(red: 0.5, green: 0.65, blue: 0.8).opacity(0.35)))
        }
        // (x fraction, shelf, width, height, round?, color)
        let items: [(CGFloat, Int, CGFloat, CGFloat, Bool, Color)] = [
            (0.12, 0, 42, 78, false, .white),
            (0.30, 0, 36, 36, true, Color(red: 0.86, green: 0.2, blue: 0.15)),
            (0.72, 0, 24, 88, false, Color(red: 0.2, green: 0.55, blue: 0.3)),
            (0.50, 1, 76, 32, false, Color(red: 0.98, green: 0.82, blue: 0.3)),
            (0.86, 1, 42, 42, true, Color(red: 0.98, green: 0.6, blue: 0.15)),
            (0.22, 2, 90, 50, false, Color(red: 0.7, green: 0.85, blue: 0.6)),
            (0.66, 2, 50, 30, true, Color(red: 0.95, green: 0.9, blue: 0.85)),
        ]
        for (fx, shelf, w, h, round, color) in items {
            let floor = shelves[shelf] - 3
            let r = CGRect(x: rect.width * fx - w / 2, y: floor - h, width: w, height: h)
            let path = round ? Path(ellipseIn: r) : Path(roundedRect: r, cornerRadius: 6)
            gc.fill(path, with: .color(color.opacity(0.85)))
            gc.stroke(path, with: .color(.black.opacity(0.12)), lineWidth: 1)
        }
    }

    /// Vertical wooden planks with grain.
    private static func closet(_ gc: GraphicsContext, _ rect: CGRect) {
        var rng = SplitMix64(state: 7)
        let w: CGFloat = 74
        var x: CGFloat = 0
        while x < rect.width {
            let shade = Double.random(in: 0...0.07, using: &rng)
            gc.fill(Path(CGRect(x: x, y: 0, width: w, height: rect.height)),
                    with: .color(Color(red: 0.56 - shade, green: 0.37 - shade, blue: 0.21 - shade / 2)))
            for _ in 0..<4 {
                var g = Path()
                let gx = x + CGFloat.random(in: 6...(w - 6), using: &rng)
                g.move(to: CGPoint(x: gx, y: 0))
                g.addCurve(to: CGPoint(x: gx + CGFloat.random(in: -10...10, using: &rng), y: rect.height),
                           control1: CGPoint(x: gx + CGFloat.random(in: -14...14, using: &rng), y: rect.height * 0.33),
                           control2: CGPoint(x: gx + CGFloat.random(in: -14...14, using: &rng), y: rect.height * 0.66))
                gc.stroke(g, with: .color(.black.opacity(0.12)), lineWidth: 1)
            }
            gc.fill(Path(CGRect(x: x, y: 0, width: 2, height: rect.height)), with: .color(.black.opacity(0.35)))
            x += w
        }
    }

    /// Desk mat, coffee rings, a sticky note.
    private static func office(_ gc: GraphicsContext, _ rect: CGRect) {
        gc.fill(Path(rect), with: .color(Color(red: 0.20, green: 0.22, blue: 0.25)))
        let mat = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.08)
        gc.fill(Path(roundedRect: mat, cornerRadius: 14), with: .color(Color(red: 0.13, green: 0.32, blue: 0.27)))
        var grid = Path()
        var gx = mat.minX + 20
        while gx < mat.maxX {
            grid.addRect(CGRect(x: gx, y: mat.minY, width: 0.8, height: mat.height))
            gx += 20
        }
        var gy = mat.minY + 20
        while gy < mat.maxY {
            grid.addRect(CGRect(x: mat.minX, y: gy, width: mat.width, height: 0.8))
            gy += 20
        }
        gc.fill(grid, with: .color(.white.opacity(0.08)))
        for (fx, fy, r) in [(0.8, 0.25, 34.0), (0.84, 0.32, 26.0), (0.2, 0.8, 30.0)] {
            let c = CGPoint(x: rect.width * fx, y: rect.height * fy)
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                      with: .color(Color(red: 0.45, green: 0.28, blue: 0.12).opacity(0.45)), lineWidth: 5)
        }
        var note = gc
        note.translateBy(x: rect.width * 0.12, y: rect.height * 0.22)
        note.rotate(by: .degrees(-8))
        note.fill(Path(CGRect(x: -36, y: -36, width: 72, height: 72)),
                  with: .color(Color(red: 1.0, green: 0.88, blue: 0.35)))
    }

    /// A computer screen: an app window with text, the bugs' new home.
    private static func desktop(_ gc: GraphicsContext, _ rect: CGRect) {
        gc.fill(Path(rect), with: .color(Color(red: 0.97, green: 0.97, blue: 0.98)))
        let sidebarW = rect.width * 0.18
        gc.fill(Path(CGRect(x: 0, y: 0, width: sidebarW, height: rect.height)),
                with: .color(Color(red: 0.92, green: 0.92, blue: 0.94)))
        gc.fill(Path(CGRect(x: 0, y: 0, width: rect.width, height: 40)),
                with: .color(Color(red: 0.94, green: 0.94, blue: 0.96)))
        for (k, color) in [Color.red, Color.yellow, Color.green].enumerated() {
            gc.fill(Path(ellipseIn: CGRect(x: 14 + CGFloat(k) * 18, y: 14, width: 11, height: 11)),
                    with: .color(color.opacity(0.75)))
        }
        var rng = SplitMix64(state: 11)
        let ink = Color(red: 0.55, green: 0.56, blue: 0.6).opacity(0.45)
        var y: CGFloat = 70
        while y < rect.height - 20 {
            gc.fill(Path(roundedRect: CGRect(x: 14, y: y, width: sidebarW - 28, height: 7), cornerRadius: 3.5), with: .color(ink))
            y += 30
        }
        y = 74
        let left = sidebarW + 30
        var paragraph = 0
        while y < rect.height - 30 {
            let isTitle = paragraph % 5 == 0
            let w = (rect.width - left - 40) * CGFloat.random(in: isTitle ? 0.35...0.5 : 0.55...0.95, using: &rng)
            gc.fill(Path(roundedRect: CGRect(x: left, y: y, width: w, height: isTitle ? 13 : 8), cornerRadius: 4),
                    with: .color(isTitle ? Color.black.opacity(0.55) : ink))
            y += isTitle ? 32 : 22
            paragraph += 1
        }
        let bubble = CGRect(x: rect.width * 0.62, y: rect.height * 0.45, width: 120, height: 34)
        gc.fill(Path(roundedRect: bubble, cornerRadius: 17), with: .color(.black.opacity(0.85)))
        gc.fill(Path(roundedRect: bubble.insetBy(dx: 20, dy: 13), cornerRadius: 4), with: .color(.white.opacity(0.8)))
    }

    // MARK: - Trash bin

    /// Teal bin with an orange lid. Garbage pokes out as it fills; the lid
    /// flips open when you bring trash near, and bangs down when slammed.
    static func bin(_ gc: GraphicsContext, in rect: CGRect, fill: Int, open: Bool, slammed: Bool) {
        let w = rect.width
        let h = rect.height
        var c = gc
        c.translateBy(x: rect.minX, y: rect.minY)
        c.addFilter(.shadow(color: .black.opacity(0.35), radius: 4, x: 1, y: 3))

        // Garbage peeking over the rim.
        let junk: [Color] = [Color(red: 0.98, green: 0.8, blue: 0.25), Color(red: 0.85, green: 0.15, blue: 0.12),
                             Color(red: 0.95, green: 0.93, blue: 0.85), Color(red: 0.2, green: 0.6, blue: 0.25),
                             Color(red: 0.86, green: 0.66, blue: 0.4), Color(red: 0.98, green: 0.88, blue: 0.42)]
        for k in 0..<min(fill, junk.count) {
            let x = w * (0.22 + CGFloat(k % 3) * 0.2)
            let y = h * 0.28 - CGFloat(k / 3) * 8
            c.fill(Path(roundedRect: CGRect(x: x, y: y - 6, width: 15, height: 12), cornerRadius: 4), with: .color(junk[k]))
        }

        let body = CGRect(x: w * 0.12, y: h * 0.3, width: w * 0.76, height: h * 0.7)
        c.fill(Path(roundedRect: body, cornerRadius: 7),
               with: .linearGradient(Gradient(colors: [Color(red: 0.25, green: 0.55, blue: 0.5), Color(red: 0.1, green: 0.3, blue: 0.28)]),
                                     startPoint: CGPoint(x: body.minX, y: 0), endPoint: CGPoint(x: body.maxX, y: 0)))
        for k in 1...3 {
            let x = body.minX + body.width * CGFloat(k) / 4
            c.fill(Path(CGRect(x: x - 1, y: body.minY + 8, width: 2, height: body.height - 16)),
                   with: .color(.black.opacity(0.2)))
        }

        var lid = c
        lid.translateBy(x: w * 0.06, y: h * 0.3)
        if open && !slammed { lid.rotate(by: .degrees(-40)) }
        lid.fill(Path(roundedRect: CGRect(x: 0, y: -h * 0.12, width: w * 0.88, height: h * 0.12), cornerRadius: 4),
                 with: .color(Color(red: 0.98, green: 0.55, blue: 0.15)))
        lid.fill(Path(roundedRect: CGRect(x: w * 0.33, y: -h * 0.2, width: w * 0.22, height: h * 0.09), cornerRadius: 3),
                 with: .color(Color(red: 0.8, green: 0.4, blue: 0.08)))

        if slammed {
            // Impact lines.
            var bang = Path()
            for (dx, dy) in [(-0.15, -0.05), (1.15, -0.05), (0.1, -0.35), (0.9, -0.35), (0.5, -0.45)] {
                let from = CGPoint(x: w * dx, y: h * (0.25 + dy))
                let to = CGPoint(x: w * (dx + (dx - 0.5) * 0.25), y: h * (0.25 + dy * 1.6))
                bang.move(to: from)
                bang.addLine(to: to)
            }
            c.stroke(bang, with: .color(.yellow), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // Fill gauge on the front.
        let gauge = CGRect(x: body.minX + 8, y: body.maxY - 14, width: body.width - 16, height: 6)
        c.fill(Path(roundedRect: gauge, cornerRadius: 3), with: .color(.black.opacity(0.35)))
        let filled = CGRect(x: gauge.minX, y: gauge.minY,
                            width: gauge.width * CGFloat(fill) / CGFloat(GameModel.binCapacity), height: gauge.height)
        c.fill(Path(roundedRect: filled, cornerRadius: 3), with: .color(Color(red: 0.98, green: 0.7, blue: 0.2)))
    }
}
