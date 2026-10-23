import DuoKit
import SwiftUI

/// Root: menu, round, results. Owns the hinge monitor and feeds the game.
struct GameView: View {
    @State private var model = GameModel()
    @State private var monitor = HingeMonitor()
    @State private var tab = HomeTab.play
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Between rounds: system tabs (a floating bar at the bottom in
        // portrait, the lower half of the vertical bar on the side). A round
        // and its results take the whole screen, with no tab bar.
        Group {
            switch model.phase {
            case .menu:
                TabView(selection: $tab) {
                    Tab("Play", systemImage: "gamecontroller", value: HomeTab.play) {
                        NavigationStack { MenuView(model: model) }
                    }
                    Tab("Release", systemImage: "ant", value: HomeTab.release) {
                        NavigationStack { ReleaseView() }
                    }
                    Tab("Records", systemImage: "trophy", value: HomeTab.records) {
                        NavigationStack { RecordsView(model: model) }
                    }
                }
            case .playing:
                NavigationStack { ArenaView(model: model) }
            case .over:
                NavigationStack { ResultsView(model: model) }
            }
        }
        .readsHinge(into: monitor)
        .onAppear {
            monitor.onReading = { [model] reading, velocity in
                model.observeHinge(reading, velocity: velocity)
            }
        }
        .onChange(of: monitor.pose, initial: true) { _, pose in
            model.isOuter = pose == .closed || pose == .tent
        }
        // From the island ("Go squash"), a widget, or the PiP window.
        .onOpenURL { url in
            if url.host == "hunt" { model.startHunt() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .roachHunt)) { _ in
            model.startHunt()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause() }
        }
    }
}

enum HomeTab: Hashable {
    case play, release, records
}

/// A round, full screen: the field runs edge to edge with no bars and no
/// status bar. The one control while playing is Pause, in the corner with the
/// score (games keep it there so the whole screen stays playable). Paused, the
/// system toolbar comes back with Resume, Restart and Quit.
struct ArenaView: View {
    let model: GameModel

    var body: some View {
        ZStack {
            field
                .offset(model.shakeOffset)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { model.dragChanged(start: $0.startLocation, location: $0.location) }
                        .onEnded { model.dragEnded(start: $0.startLocation, location: $0.location) }
                )
                .onGeometryChange(for: CGSize.self) { $0.size } action: { model.setFieldSize($0) }
                .allowsHitTesting(!model.paused)
                .ignoresSafeArea()

            // Score and hints stay inside the safe area, clear of the camera.
            VStack {
                HStack(alignment: .top) {
                    Scoreboard(model: model)
                        .allowsHitTesting(false)
                    if !model.paused {
                        Button("Pause", systemImage: "pause.fill") { model.pause() }
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .semibold))
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                    }
                }
                Spacer()
                hint
                    .allowsHitTesting(false)
            }
            .padding(Duo.Space.l)

            if let banner = model.banner {
                BannerView(banner: banner, now: model.now)
                    .allowsHitTesting(false)
            }

            if model.paused {
                Duo.screen.opacity(0.6)
                    .ignoresSafeArea()
                Text("Paused")
                    .font(DuoType.title)
                    .foregroundStyle(Duo.screenText)
            }
        }
        .background(Duo.paper.ignoresSafeArea())
        .navigationTitle(model.map.label)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarVisibility(model.paused ? .visible : .hidden, for: .navigationBar)
        .statusBarHidden(!model.paused)
        .persistentSystemOverlays(.hidden)
        .toolbar {
            if model.paused {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Quit", systemImage: "xmark") { model.quit() }
                }
                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button("Resume", systemImage: "play.fill") { model.resume() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restart", systemImage: "arrow.counterclockwise") { model.start(map: model.map) }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.paused)
        .task {
            while !Task.isCancelled {
                model.step(now: ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var field: some View {
        TimelineView(.animation) { _ in
            Canvas { gc, size in
                Art.background(model.map, gc, size: size)
                let inner = !model.isOuter
                for s in model.splats where s.inner == inner {
                    Art.splat(gc, s, now: model.now)
                }
                if inner, model.map == .homeScreen {
                    Art.homeIcons(gc, model.icons, size: size, now: model.now)
                }
                if inner, model.map.hasTrash {
                    Art.bin(gc, in: model.binRect, fill: model.binFill,
                            open: model.now < model.binOpenUntil,
                            slammed: model.now < model.lidSlamUntil)
                    for f in model.foods where !f.held { Art.food(gc, f, now: model.now) }
                }
                // Small bugs first so the big ones walk over them.
                for r in model.roaches.sorted(by: { $0.scale < $1.scale }) where r.inner == inner {
                    Art.bug(gc, r.species, at: r.pos, heading: r.heading, scale: r.scale,
                            legPhase: r.legPhase,
                            curled: model.now < r.curledUntil,
                            flash: model.now < r.hitUntil)
                }
                if inner {
                    // A carried scrap floats above everything, bigger.
                    for var f in model.foods where f.held {
                        f.scale *= 1.25
                        Art.food(gc, f, now: model.now)
                    }
                }
                Art.rings(gc, model.rings, inner: inner, now: model.now)
                Art.particles(gc, model.particles, inner: inner, now: model.now)
                for p in model.pops where p.inner == inner {
                    let age = model.now - p.born
                    // Pops in big, settles, floats up and fades.
                    let pop = age < 0.12 ? 0.5 + age / 0.12 * 0.8 : max(1, 1.3 - (age - 0.12) * 2.5)
                    var c = gc
                    c.opacity = age > 0.7 ? max(0, 1 - (age - 0.7) / 0.4) : 1
                    c.translateBy(x: p.pos.x, y: p.pos.y - 24 - age * 46)
                    c.scaleBy(x: pop, y: pop)
                    c.addFilter(.shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1))
                    c.draw(
                        Text(p.text)
                            .font(.system(size: p.hot ? 26 : 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(p.hot ? Duo.sun : Color.white),
                        at: .zero
                    )
                }
                if model.now < model.flashUntil {
                    gc.fill(Path(CGRect(origin: .zero, size: size)),
                            with: .color(.white.opacity(0.55 * (model.flashUntil - model.now) / 0.12)))
                }
            }
        }
    }


    @ViewBuilder
    private var hint: some View {
        if model.isOuter && model.roaches.contains(where: { !$0.inner }) {
            HintLabel(text: String(localized: "Too fast! Open the phone to trap it!"))
        } else if !model.isOuter && model.roaches.contains(where: \.trapped) {
            HintLabel(text: String(localized: "Slam it shut!"))
        } else if let trash = model.trashHint {
            HintLabel(text: trash)
        }
    }
}

/// Time, score and combo: read-only, so they stay with the content.
private struct Scoreboard: View {
    let model: GameModel

    var body: some View {
        let left = model.timeLeft
        HStack(spacing: Duo.Space.l) {
            value(String(format: "%d:%02d", left / 60, left % 60), "Time", left <= 10 ? Duo.reject : Duo.screenText)
            value(String(model.score), "Score", Duo.sun)
            if model.combo >= 2, model.now < model.comboUntil {
                value("×\(model.combo)", "Combo", Duo.screenText)
            }
        }
        .padding(.horizontal, Duo.Space.l)
        .padding(.vertical, Duo.Space.s)
        .background(Duo.screen.opacity(0.78), in: .rect(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func value(_ v: String, _ label: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: v)
                .font(DuoType.number(model.isOuter ? 17 : 20))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Duo.screenText.opacity(0.7))
        }
    }
}

/// One line of guidance over the field.
private struct HintLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DuoType.headline)
            .foregroundStyle(Duo.onSun)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Duo.Space.l)
            .padding(.vertical, Duo.Space.m)
            .background(Duo.sun, in: .rect(cornerRadius: 14))
    }
}

/// "SPLAT!" after a slam or a trap.
private struct BannerView: View {
    let banner: Banner
    let now: TimeInterval

    var body: some View {
        let age = now - banner.born
        let scale = age < 0.16 ? 0.85 + age / 0.16 * 0.15 : 1.0
        let fade = age > 1.5 ? max(0, 1 - (age - 1.5) / 0.4) : min(1, age / 0.08)

        VStack(spacing: Duo.Space.s) {
            Text(banner.title)
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(Duo.sun)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(banner.subtitle)
                .font(DuoType.headline)
                .foregroundStyle(Duo.screenText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Duo.Space.xl)
        .padding(.vertical, Duo.Space.l)
        .background(Duo.screen.opacity(0.82), in: .rect(cornerRadius: 22))
        .padding(Duo.Space.xl)
        .scaleEffect(scale)
        .opacity(fade)
    }
}
