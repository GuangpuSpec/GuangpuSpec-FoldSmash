import SwiftUI

// The "Home Screen" map: laid out like iPhone Duo's inner-screen Home Screen.
// Widgets on the left, an app grid on the right, a vertical dock at the
// right edge, page dots at the bottom, over a dusk-dunes wallpaper. The apps
// and widget designs are our own. Bugs pour in and chew everything up.

/// Picks English or Chinese, following the app's language.
func tr(_ en: String, _ zh: String) -> String {
    (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("zh") ? zh : en
}

/// A made-up app.
struct HomeApp {
    let name: String
    let symbol: String
    let top: Color
    let bottom: Color
    var glyph: Color = .white
    var badge: Int = 0

    /// 15 grid apps.
    static let grid: [HomeApp] = [
        HomeApp(name: tr("FaceChat", "视频聊"), symbol: "video.fill",
                top: Color(red: 0.45, green: 0.9, blue: 0.5), bottom: Color(red: 0.15, green: 0.72, blue: 0.3)),
        HomeApp(name: tr("Days", "日程"), symbol: "calendar",
                top: .white, bottom: Color(white: 0.93), glyph: Color(red: 0.95, green: 0.25, blue: 0.2)),
        HomeApp(name: tr("Album", "相册集"), symbol: "photo.on.rectangle.angled",
                top: Color(red: 1, green: 0.78, blue: 0.35), bottom: Color(red: 0.98, green: 0.45, blue: 0.4)),
        HomeApp(name: tr("Snapshot", "快拍"), symbol: "camera.aperture",
                top: Color(white: 0.55), bottom: Color(white: 0.28)),
        HomeApp(name: tr("Letters", "邮箱"), symbol: "envelope.fill",
                top: Color(red: 0.35, green: 0.7, blue: 1), bottom: Color(red: 0.1, green: 0.42, blue: 0.95), badge: 3),
        HomeApp(name: tr("Jot", "便签"), symbol: "list.bullet.rectangle.portrait.fill",
                top: Color(red: 1, green: 0.93, blue: 0.55), bottom: Color(red: 1, green: 0.8, blue: 0.25),
                glyph: Color(red: 0.45, green: 0.35, blue: 0.1)),
        HomeApp(name: tr("Clocky", "时间"), symbol: "clock.fill",
                top: Color(white: 0.2), bottom: .black, glyph: .white),
        HomeApp(name: tr("Wayfinder", "地图通"), symbol: "location.north.circle.fill",
                top: Color(red: 0.45, green: 0.88, blue: 0.7), bottom: Color(red: 0.15, green: 0.6, blue: 0.55)),
        HomeApp(name: tr("Screen", "影视"), symbol: "play.rectangle.fill",
                top: Color(white: 0.24), bottom: Color(white: 0.05)),
        HomeApp(name: tr("App Mall", "应用商城"), symbol: "square.grid.2x2.fill",
                top: Color(red: 0.3, green: 0.75, blue: 1), bottom: Color(red: 0.1, green: 0.45, blue: 1)),
        HomeApp(name: tr("Arcade", "游戏厅"), symbol: "gamecontroller.fill",
                top: Color(red: 1, green: 0.45, blue: 0.45), bottom: Color(red: 0.88, green: 0.18, blue: 0.3)),
        HomeApp(name: tr("Vitals", "健康"), symbol: "heart.fill",
                top: .white, bottom: Color(white: 0.94), glyph: Color(red: 1, green: 0.25, blue: 0.4)),
        HomeApp(name: tr("Coins", "钱包"), symbol: "creditcard.fill",
                top: Color(white: 0.22), bottom: Color(white: 0.06), glyph: Color(red: 1, green: 0.82, blue: 0.4)),
        HomeApp(name: tr("Settings", "设置"), symbol: "gearshape.fill",
                top: Color(white: 0.7), bottom: Color(white: 0.45)),
        HomeApp(name: tr("Fold Smash", "广东模拟器"), symbol: "ant.fill",
                top: Color(red: 0.95, green: 0.62, blue: 0.25), bottom: Color(red: 0.55, green: 0.3, blue: 0.1)),
    ]

    /// The dock, top to bottom.
    static let dock: [HomeApp] = [
        HomeApp(name: tr("Call", "电话"), symbol: "phone.fill",
                top: Color(red: 0.45, green: 0.9, blue: 0.45), bottom: Color(red: 0.15, green: 0.7, blue: 0.25)),
        HomeApp(name: tr("Surf", "浏览器"), symbol: "globe",
                top: Color(red: 0.4, green: 0.75, blue: 1), bottom: Color(red: 0.15, green: 0.45, blue: 0.95)),
        HomeApp(name: tr("Chatty", "聊聊"), symbol: "message.fill",
                top: Color(red: 0.45, green: 0.9, blue: 0.5), bottom: Color(red: 0.15, green: 0.72, blue: 0.3), badge: 1),
        HomeApp(name: tr("Tunes", "音乐盒"), symbol: "music.note",
                top: Color(red: 1, green: 0.42, blue: 0.55), bottom: Color(red: 0.95, green: 0.15, blue: 0.35)),
    ]
}

/// Everything on the Home Screen the bugs can eat.
enum HomeTile {
    case calendar, notes, reminders, map, weather, photo
    case app(Int)
    case dock(Int)

    static let all: [HomeTile] = [.calendar, .notes, .reminders, .map, .weather, .photo]
        + HomeApp.grid.indices.map { .app($0) }
        + HomeApp.dock.indices.map { .dock($0) }

    var name: String {
        switch self {
        case .calendar: tr("Days", "日程")
        case .notes: tr("Jot", "便签")
        case .reminders: tr("To-Do", "待办")
        case .map: tr("Wayfinder", "地图通")
        case .weather: tr("Skyline", "天气晴")
        case .photo: tr("Album", "相册集")
        case .app(let i): HomeApp.grid[i].name
        case .dock(let i): HomeApp.dock[i].name
        }
    }

    var isWidget: Bool {
        switch self {
        case .app, .dock: false
        default: true
        }
    }

    /// How much longer than an app icon it takes to eat.
    var toughness: Double {
        switch self {
        case .calendar, .map: 3
        case .notes, .reminders, .weather, .photo: 2
        case .app, .dock: 1
        }
    }

    /// Grid cell (col, row, width, height) on the 8×6 grid; nil for the dock.
    var cell: (Int, Int, Int, Int)? {
        switch self {
        case .calendar: (0, 0, 4, 2)
        case .notes: (0, 2, 2, 2)
        case .reminders: (2, 2, 2, 2)
        case .map: (0, 4, 4, 2)
        case .weather: (4, 0, 2, 2)
        case .photo: (6, 0, 2, 2)
        case .app(let i): (4 + i % 4, 2 + i / 4, 1, 1)
        case .dock: nil
        }
    }
}

/// One edible thing on the Home Screen, and how much of it is left.
struct AppIcon: Identifiable {
    let id: Int
    /// 1 = whole, 0 = eaten.
    var health: Double = 1
    var biteSeed = UInt64.random(in: 1 ... .max)
    var lastBite: TimeInterval = -10
    var eaten: Bool { health <= 0 }
    var tile: HomeTile { HomeTile.all[id] }
    var name: String { tile.name }

    static var count: Int { HomeTile.all.count }
}

/// Where everything sits for a screen size.
enum HomeLayout {
    /// The 8×6 grid left of the dock.
    static func gridRect(in size: CGSize) -> CGRect {
        let dock = dockRect(in: size)
        let left: CGFloat = size.width * 0.035
        let top: CGFloat = size.height * 0.07
        let bottom: CGFloat = size.height * 0.09
        return CGRect(x: left, y: top, width: dock.minX - left - size.width * 0.03,
                      height: size.height - top - bottom)
    }

    /// The vertical dock on the right edge.
    static func dockRect(in size: CGSize) -> CGRect {
        let w = max(60, size.width * 0.075)
        let h = min(size.height * 0.4, w * 4.3)
        return CGRect(x: size.width - w - size.width * 0.025, y: size.height * 0.36, width: w, height: h)
    }

    /// Icon side for this screen.
    static func iconSide(in size: CGSize) -> CGFloat {
        let g = gridRect(in: size)
        return min(g.width / 8 * 0.62, g.height / 6 * 0.62)
    }

    /// One frame per tile, in `HomeTile.all` order. Widgets fill their cells
    /// (less a gutter); icons sit centred in their cell, a little high to
    /// leave room for the label.
    static func frames(in size: CGSize) -> [CGRect] {
        let g = gridRect(in: size)
        let cw = g.width / 8
        let ch = g.height / 6
        let gutter = min(cw, ch) * 0.16
        let side = iconSide(in: size)
        let dock = dockRect(in: size)
        let dockSide = min(side, dock.width * 0.74)
        let dockStep = dock.height / CGFloat(HomeApp.dock.count)

        return HomeTile.all.map { tile in
            if case .dock(let i) = tile {
                return CGRect(x: dock.midX - dockSide / 2, y: dock.minY + dockStep * (CGFloat(i) + 0.5) - dockSide / 2,
                              width: dockSide, height: dockSide)
            }
            let (c, r, w, h) = tile.cell!
            let cellRect = CGRect(x: g.minX + CGFloat(c) * cw, y: g.minY + CGFloat(r) * ch,
                                  width: CGFloat(w) * cw, height: CGFloat(h) * ch)
            if tile.isWidget {
                // Leave room under the widget for its label.
                return CGRect(x: cellRect.minX + gutter, y: cellRect.minY + gutter * 0.5,
                              width: cellRect.width - gutter * 2, height: cellRect.height - gutter * 2.4)
            }
            return CGRect(x: cellRect.midX - side / 2, y: cellRect.midY - side * 0.62, width: side, height: side)
        }
    }
}

// MARK: - Drawing

extension Art {
    /// Dusk dunes wallpaper, page dots and the dock (no tiles).
    static func homeScreen(_ gc: GraphicsContext, _ rect: CGRect, dock: Bool = true) {
        let w = rect.width, h = rect.height
        // Evening sky.
        gc.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(red: 0.1, green: 0.11, blue: 0.2),
                              Color(red: 0.32, green: 0.3, blue: 0.45),
                              Color(red: 0.62, green: 0.55, blue: 0.62)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.75)))
        // A few stars.
        var rng = SplitMix64(state: 42)
        for _ in 0..<40 {
            let x = CGFloat.random(in: 0...1, using: &rng) * w
            let y = CGFloat.random(in: 0...0.35, using: &rng) * h
            let r = CGFloat.random(in: 0.5...1.3, using: &rng)
            gc.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(Double.random(in: 0.3...0.8, using: &rng))))
        }
        // Layered dunes, far (light) to near (dark).
        let layers: [(CGFloat, CGFloat, Color)] = [
            (0.42, 0.06, Color(red: 0.42, green: 0.38, blue: 0.5)),
            (0.52, 0.08, Color(red: 0.34, green: 0.3, blue: 0.42)),
            (0.64, 0.07, Color(red: 0.25, green: 0.22, blue: 0.33)),
            (0.78, 0.06, Color(red: 0.17, green: 0.15, blue: 0.24)),
        ]
        for (k, (base, amp, color)) in layers.enumerated() {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: h))
            let phase = Double(k) * 1.7
            for i in 0...60 {
                let x = w * CGFloat(i) / 60
                let t = Double(i) / 60
                let y = h * (base + amp * CGFloat(sin(t * 5.2 + phase) * 0.6 + sin(t * 11 + phase * 2) * 0.25))
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
            gc.fill(p, with: .linearGradient(Gradient(colors: [color, color.opacity(0.85)]),
                                             startPoint: CGPoint(x: 0, y: h * base), endPoint: CGPoint(x: 0, y: h)))
        }

        guard dock else { return }
        // Page dots under the grid.
        let g = HomeLayout.gridRect(in: rect.size)
        for k in 0..<2 {
            let x = g.midX + CGFloat(k) * 14 - 7
            gc.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: g.maxY + h * 0.035, width: 7, height: 7)),
                    with: .color(.white.opacity(k == 0 ? 0.95 : 0.4)))
        }
        // Vertical dock.
        let d = HomeLayout.dockRect(in: rect.size)
        let shape = Path(roundedRect: d, cornerRadius: d.width * 0.36, style: .continuous)
        gc.fill(shape, with: .color(.white.opacity(0.22)))
        gc.stroke(shape, with: .color(.white.opacity(0.25)), lineWidth: 1)
    }

    /// Every tile, chewed according to its health.
    static func homeIcons(_ gc: GraphicsContext, _ icons: [AppIcon], size: CGSize, now: TimeInterval) {
        let frames = HomeLayout.frames(in: size)
        for icon in icons where icon.id < frames.count {
            var frame = frames[icon.id]
            if now - icon.lastBite < 0.25, !icon.eaten {
                // Shudders while it's being eaten.
                frame = frame.offsetBy(dx: sin(now * 70) * 1.6, dy: cos(now * 53) * 1.2)
            }
            tile(gc, icon, in: frame)
        }
    }

    static func tile(_ gc: GraphicsContext, _ icon: AppIcon, in frame: CGRect) {
        let isWidget = icon.tile.isWidget
        let radius = isWidget ? min(frame.width, frame.height) * 0.14 : frame.width * 0.225
        let shape = Path(roundedRect: frame, cornerRadius: radius, style: .continuous)
        let unit = isWidget ? min(frame.width, frame.height) : frame.width

        if icon.eaten {
            // An empty slot and crumbs where it used to be.
            gc.stroke(shape, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            var rng = SplitMix64(state: icon.biteSeed)
            for _ in 0..<(isWidget ? 14 : 7) {
                let x = frame.minX + CGFloat.random(in: 0.1...0.9, using: &rng) * frame.width
                let y = frame.minY + CGFloat.random(in: 0.45...1, using: &rng) * frame.height
                let r = CGFloat.random(in: 1.5...3.5, using: &rng)
                gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(0.55)))
            }
        } else {
            gc.drawLayer { layer in
                // A soft drop shadow under the tile only (not its text).
                var shadowed = layer
                shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: 6, y: 2))
                shadowed.fill(shape, with: .color(.black.opacity(0.4)))
                switch icon.tile {
                case .calendar: calendarWidget(layer, frame, shape)
                case .notes: notesWidget(layer, frame, shape)
                case .reminders: remindersWidget(layer, frame, shape)
                case .map: mapWidget(layer, frame, shape)
                case .weather: weatherWidget(layer, frame, shape)
                case .photo: photoWidget(layer, frame, shape)
                case .app(let i): appIcon(layer, HomeApp.grid[i], frame, shape)
                case .dock(let i): appIcon(layer, HomeApp.dock[i], frame, shape)
                }
                if icon.health < 1 { chew(layer, icon, frame, shape, unit: unit) }
            }
            if case .app(let i) = icon.tile, HomeApp.grid[i].badge > 0 { badge(gc, HomeApp.grid[i].badge, frame) }
            if case .dock(let i) = icon.tile, HomeApp.dock[i].badge > 0 { badge(gc, HomeApp.dock[i].badge, frame) }
        }

        // Label under everything except dock apps.
        if case .dock = icon.tile { return }
        var c = gc
        c.addFilter(.shadow(color: .black.opacity(0.55), radius: 2))
        let fontSize = max(9, (isWidget ? 0 : unit * 0.18) + (isWidget ? 11 : 0))
        c.draw(Text(icon.name).font(.system(size: fontSize, weight: .medium)).foregroundStyle(.white),
               at: CGPoint(x: frame.midX, y: frame.maxY + (isWidget ? 11 : unit * 0.2)))
    }

    /// Bites out of the edge with tooth marks; more and bigger as it's eaten.
    private static func chew(_ layer: GraphicsContext, _ icon: AppIcon, _ frame: CGRect, _ shape: Path, unit: CGFloat) {
        var rng = SplitMix64(state: icon.biteSeed)
        let bites = Int(((1 - icon.health) * (icon.tile.isWidget ? 14 : 10)).rounded(.up))
        var cut = layer
        cut.blendMode = .destinationOut
        for k in 0..<bites {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            let r = unit * CGFloat.random(in: 0.13...0.21, using: &rng) * (k > 5 ? 1.25 : 1)
            // On the edge of the (roughly rectangular) tile.
            let ex = cos(a), ey = sin(a)
            let s = 1 / max(abs(ex) / (frame.width / 2), abs(ey) / (frame.height / 2))
            let c = CGPoint(x: frame.midX + ex * s, y: frame.midY + ey * s)
            cut.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.black))
            for t in -1...1 {
                let ta = a + .pi + Double(t) * 0.5
                let tc = CGPoint(x: c.x + cos(ta) * r, y: c.y + sin(ta) * r)
                cut.fill(Path(ellipseIn: CGRect(x: tc.x - r * 0.18, y: tc.y - r * 0.18, width: r * 0.36, height: r * 0.36)),
                         with: .color(.black))
            }
        }
        if icon.health < 0.4 {
            var dim = layer
            dim.blendMode = .sourceAtop
            dim.fill(shape, with: .color(.black.opacity(0.3)))
        }
    }

    private static func badge(_ gc: GraphicsContext, _ n: Int, _ frame: CGRect) {
        let d = frame.width * 0.34
        let c = CGPoint(x: frame.maxX - d * 0.25, y: frame.minY + d * 0.25)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(.red))
        gc.draw(Text("\(n)").font(.system(size: d * 0.62, weight: .semibold)).foregroundStyle(.white), at: c)
    }

    // MARK: Icons and widgets

    private static func appIcon(_ gc: GraphicsContext, _ app: HomeApp, _ frame: CGRect, _ shape: Path) {
        gc.fill(shape, with: .linearGradient(Gradient(colors: [app.top, app.bottom]),
                                             startPoint: CGPoint(x: frame.midX, y: frame.minY),
                                             endPoint: CGPoint(x: frame.midX, y: frame.maxY)))
        gc.draw(Text(Image(systemName: app.symbol))
                       .font(.system(size: frame.width * 0.46, weight: .semibold))
                       .foregroundStyle(app.glyph),
                   at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private static func card(_ gc: GraphicsContext, _ shape: Path, _ color: Color = .white) {
        gc.fill(shape, with: .color(color))
    }

    private static func text(_ gc: GraphicsContext, _ s: String, _ size: CGFloat, _ weight: Font.Weight,
                             _ color: Color, at p: CGPoint, anchor: UnitPoint = .topLeading) {
        gc.draw(Text(s).font(.system(size: size, weight: weight)).foregroundStyle(color), at: p, anchor: anchor)
    }

    /// Wide calendar: today's date on the left, what's next on the right.
    private static func calendarWidget(_ gc: GraphicsContext, _ f: CGRect, _ shape: Path) {
        card(gc, shape)
        let u = f.height / 10
        let now = Date.now
        let day = now.formatted(.dateTime.day())
        let weekday = now.formatted(.dateTime.weekday(.abbreviated))
        let pad = u * 0.9
        text(gc, day, u * 3.2, .regular, .black, at: CGPoint(x: f.minX + pad, y: f.minY + pad * 0.6))
        text(gc, weekday, u * 1.25, .semibold, .red, at: CGPoint(x: f.minX + pad + u * 3.6, y: f.minY + pad * 1.1))
        pill(gc, tr("Team sync 10:00", "团队例会 10:00"), CGRect(x: f.minX + pad, y: f.minY + u * 5.4, width: f.width * 0.42, height: u * 1.6), u)
        pill(gc, tr("Lunch with Mia", "和小米吃午饭"), CGRect(x: f.minX + pad, y: f.minY + u * 7.4, width: f.width * 0.42, height: u * 1.6), u)
        let rx = f.midX + u * 0.6
        text(gc, Calendar.current.date(byAdding: .day, value: 5, to: now)!.formatted(.dateTime.month().day().weekday(.abbreviated)),
             u * 1.05, .medium, .gray, at: CGPoint(x: rx, y: f.minY + pad * 1.1))
        pill(gc, tr("Dentist", "看牙医"), CGRect(x: rx, y: f.minY + u * 3, width: f.width * 0.42, height: u * 1.6), u)
    }

    private static func pill(_ gc: GraphicsContext, _ s: String, _ r: CGRect, _ u: CGFloat) {
        gc.fill(Path(roundedRect: r, cornerRadius: r.height / 2.4), with: .color(Color(red: 0.88, green: 0.93, blue: 1)))
        gc.fill(Path(ellipseIn: CGRect(x: r.minX + u * 0.5, y: r.midY - u * 0.4, width: u * 0.8, height: u * 0.8)), with: .color(.blue))
        text(gc, s, u * 0.95, .medium, Color(red: 0.1, green: 0.3, blue: 0.7), at: CGPoint(x: r.minX + u * 1.7, y: r.midY), anchor: .leading)
    }

    private static func notesWidget(_ gc: GraphicsContext, _ f: CGRect, _ shape: Path) {
        card(gc, shape)
        let u = f.height / 10
        var top = gc
        top.clip(to: shape)
        top.fill(Path(CGRect(x: f.minX, y: f.minY, width: f.width, height: u * 2.6)), with: .color(Color(red: 1, green: 0.8, blue: 0.2)))
        text(gc, tr("Jot", "便签"), u * 1.25, .semibold, .white, at: CGPoint(x: f.minX + u * 1.2, y: f.minY + u * 1.3), anchor: .leading)
        text(gc, tr("Buy bug spray", "买杀虫剂"), u * 1.1, .semibold, .black, at: CGPoint(x: f.minX + u, y: f.minY + u * 3.6))
        text(gc, tr("and a bigger shoe", "再买一只大拖鞋"), u * 0.95, .regular, .gray, at: CGPoint(x: f.minX + u, y: f.minY + u * 5.1))
        text(gc, tr("Today", "今天"), u * 0.9, .regular, .gray, at: CGPoint(x: f.minX + u, y: f.maxY - u * 2))
    }

    private static func remindersWidget(_ gc: GraphicsContext, _ f: CGRect, _ shape: Path) {
        card(gc, shape)
        let u = f.height / 10
        text(gc, tr("To-Do", "待办"), u * 1.25, .semibold, .orange, at: CGPoint(x: f.minX + u, y: f.minY + u * 0.9))
        text(gc, "3", u * 1.6, .semibold, .black, at: CGPoint(x: f.maxX - u, y: f.minY + u * 0.7), anchor: .topTrailing)
        let items = [tr("Clean kitchen", "打扫厨房"), tr("Take out trash", "倒垃圾"), tr("Call exterminator", "叫灭虫公司")]
        for (k, s) in items.enumerated() {
            let y = f.minY + u * (3.8 + CGFloat(k) * 2)
            gc.stroke(Path(ellipseIn: CGRect(x: f.minX + u, y: y - u * 0.5, width: u, height: u)), with: .color(.orange), lineWidth: 1.2)
            text(gc, s, u * 0.95, .regular, .black, at: CGPoint(x: f.minX + u * 2.5, y: y), anchor: .leading)
        }
    }

    /// Wide map: streets, a park, a river, you-are-here.
    private static func mapWidget(_ gc: GraphicsContext, _ f: CGRect, _ shape: Path) {
        card(gc, shape, Color(red: 0.95, green: 0.94, blue: 0.9))
        var m = gc
        m.clip(to: shape)
        m.fill(Path(ellipseIn: CGRect(x: f.minX + f.width * 0.55, y: f.minY + f.height * 0.1, width: f.width * 0.3, height: f.height * 0.45)),
               with: .color(Color(red: 0.75, green: 0.9, blue: 0.7)))
        var river = Path()
        river.move(to: CGPoint(x: f.minX, y: f.minY + f.height * 0.75))
        river.addCurve(to: CGPoint(x: f.maxX, y: f.minY + f.height * 0.55),
                       control1: CGPoint(x: f.minX + f.width * 0.35, y: f.minY + f.height * 0.95),
                       control2: CGPoint(x: f.minX + f.width * 0.6, y: f.minY + f.height * 0.35))
        m.stroke(river, with: .color(Color(red: 0.6, green: 0.8, blue: 0.98)), lineWidth: f.height * 0.07)
        var rng = SplitMix64(state: 9)
        for k in 0..<9 {
            var road = Path()
            if k % 2 == 0 {
                let y = f.minY + f.height * CGFloat.random(in: 0.05...0.95, using: &rng)
                road.move(to: CGPoint(x: f.minX, y: y)); road.addLine(to: CGPoint(x: f.maxX, y: y + CGFloat.random(in: -20...20, using: &rng)))
            } else {
                let x = f.minX + f.width * CGFloat.random(in: 0.05...0.95, using: &rng)
                road.move(to: CGPoint(x: x, y: f.minY)); road.addLine(to: CGPoint(x: x + CGFloat.random(in: -30...30, using: &rng), y: f.maxY))
            }
            m.stroke(road, with: .color(.white), lineWidth: k == 3 ? 5 : 2.5)
            if k == 3 { m.stroke(road, with: .color(Color(red: 1, green: 0.85, blue: 0.45)), lineWidth: 3) }
        }
        let dot = CGPoint(x: f.minX + f.width * 0.45, y: f.midY)
        m.fill(Path(ellipseIn: CGRect(x: dot.x - 14, y: dot.y - 14, width: 28, height: 28)), with: .color(.blue.opacity(0.18)))
        m.fill(Path(ellipseIn: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12)), with: .color(.white))
        m.fill(Path(ellipseIn: CGRect(x: dot.x - 4.5, y: dot.y - 4.5, width: 9, height: 9)), with: .color(.blue))
    }

    private static func weatherWidget(_ gc: GraphicsContext, _ f: CGRect, _ shape: Path) {
        gc.fill(shape, with: .linearGradient(Gradient(colors: [Color(red: 0.28, green: 0.5, blue: 0.85), Color(red: 0.18, green: 0.32, blue: 0.62)]),
                                             startPoint: CGPoint(x: f.midX, y: f.minY), endPoint: CGPoint(x: f.midX, y: f.maxY)))
        let u = f.height / 10
        text(gc, tr("Home", "家"), u * 1.05, .semibold, .white, at: CGPoint(x: f.minX + u, y: f.minY + u * 0.9))
        text(gc, "26°", u * 3.1, .light, .white, at: CGPoint(x: f.minX + u * 0.8, y: f.minY + u * 2.2))
        gc.draw(Text(Image(systemName: "sun.max.fill")).font(.system(size: u * 1.3)).foregroundStyle(.yellow),
                at: CGPoint(x: f.minX + u * 1.6, y: f.minY + u * 6.6))
        text(gc, tr("Sunny", "晴"), u * 0.95, .medium, .white, at: CGPoint(x: f.minX + u, y: f.minY + u * 7.6))
        text(gc, tr("H:29° L:21°", "最高29° 最低21°"), u * 0.9, .medium, .white, at: CGPoint(x: f.minX + u, y: f.minY + u * 8.7))
    }

    /// A little painted landscape, with a roach sunbathing on a rock.
    private static func photoWidget(_ gc: GraphicsContext, _ f: CGRect, _ shape: Path) {
        var p = gc
        p.clip(to: shape)
        p.fill(Path(f), with: .linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.7, blue: 0.45), Color(red: 0.95, green: 0.45, blue: 0.45)]),
                                              startPoint: CGPoint(x: f.midX, y: f.minY), endPoint: CGPoint(x: f.midX, y: f.maxY)))
        p.fill(Path(ellipseIn: CGRect(x: f.midX - f.width * 0.14, y: f.minY + f.height * 0.25, width: f.width * 0.28, height: f.width * 0.28)),
               with: .color(Color(red: 1, green: 0.92, blue: 0.6)))
        var hill = Path()
        hill.move(to: CGPoint(x: f.minX, y: f.maxY))
        hill.addCurve(to: CGPoint(x: f.maxX, y: f.minY + f.height * 0.62),
                      control1: CGPoint(x: f.minX + f.width * 0.3, y: f.minY + f.height * 0.45),
                      control2: CGPoint(x: f.minX + f.width * 0.7, y: f.minY + f.height * 0.8))
        hill.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
        p.fill(hill, with: .color(Color(red: 0.35, green: 0.25, blue: 0.35)))
        p.fill(Path(ellipseIn: CGRect(x: f.minX + f.width * 0.18, y: f.minY + f.height * 0.7, width: f.width * 0.3, height: f.height * 0.14)),
               with: .color(Color(red: 0.25, green: 0.18, blue: 0.25)))
        bug(p, .common, at: CGPoint(x: f.minX + f.width * 0.33, y: f.minY + f.height * 0.7), heading: -0.3,
            scale: f.width / 160, legPhase: 0)
    }

    /// The map card's thumbnail: the whole screen, shrunk.
    static func homePreview(_ gc: GraphicsContext, size: CGSize) {
        let virtual = CGSize(width: 900, height: 640)
        let k = max(size.width / virtual.width, size.height / virtual.height)
        var c = gc
        c.scaleBy(x: k, y: k)
        homeScreen(c, CGRect(origin: .zero, size: virtual))
        var icons = (0..<AppIcon.count).map { AppIcon(id: $0) }
        icons[6].health = 0.45
        icons[3].health = 0.6
        homeIcons(c, icons, size: virtual, now: 0)
    }
}
