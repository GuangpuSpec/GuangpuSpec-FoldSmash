import DuoKit
import SwiftUI

/// Play tab. Tap a hideout to choose it (direct content interaction); Start
/// and the rules are system toolbar items.
struct MenuView: View {
    let model: GameModel
    @State private var director = LifeDirector.shared
    @State private var showingHelp = false

    var body: some View {
        ScrollView {
            // Two columns, so the fold falls between them when the phone bends.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Duo.Space.l), GridItem(.flexible(), spacing: Duo.Space.l)],
                      spacing: Duo.Space.xl) {
                ForEach(GameMap.allCases) { map in
                    tile(map)
                }
            }
            .padding(.horizontal, Duo.Space.l)
            .padding(.vertical, Duo.Space.m)
        }
        .scrollIndicators(.hidden)
        .background(Duo.paper)
        .navigationTitle(String(localized: "Fold Smash"))
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("Start", systemImage: "play.fill") { model.start(map: model.map) }
            }
            ToolbarOverflowMenu {
                Button("How to play", systemImage: "questionmark.circle") { showingHelp = true }
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView(islandAvailable: director.islandAvailable)
        }
    }

    private func tile(_ map: GameMap) -> some View {
        let selected = model.map == map
        return Button {
            model.map = map
        } label: {
            VStack(alignment: .leading, spacing: Duo.Space.s) {
                ZStack {
                    // The floating-window roach needs its layer on screen to pop out.
                    if selected { PiPPreview() }
                    MapPreview(map: map)
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(selected ? Duo.ink : .clear, lineWidth: 3)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(map.label)
                        .font(selected ? DuoType.headline : DuoType.body)
                        .foregroundStyle(Duo.ink)
                    Spacer(minLength: Duo.Space.s)
                    Text("Best \(model.best(for: map))")
                        .font(DuoType.footnote.monospacedDigit())
                        .foregroundStyle(Duo.ink3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The hideout with a couple of its residents.
private struct MapPreview: View {
    let map: GameMap

    var body: some View {
        Canvas { gc, size in
            if map == .homeScreen {
                Art.homePreview(gc, size: size)
            } else {
                Art.background(map, gc, size: size)
            }
            Art.bug(gc, .common, at: CGPoint(x: size.width * 0.62, y: size.height * 0.56),
                    heading: -0.5, scale: 1.1, legPhase: 1)
            Art.bug(gc, .beetle, at: CGPoint(x: size.width * 0.32, y: size.height * 0.36),
                    heading: 0.6, scale: 1.0, legPhase: 2)
        }
        .accessibilityHidden(true)
    }
}

/// Release tab: let a roach loose outside the app, or call it back.
struct ReleaseView: View {
    @State private var director = LifeDirector.shared

    var body: some View {
        List {
            Section {
                Label {
                    Text(director.isLoose ? "A roach is loose outside the app." : "The roach is in its box.")
                        .font(DuoType.headline)
                } icon: {
                    Image(systemName: director.isLoose ? "ant.fill" : "shippingbox")
                        .foregroundStyle(director.isLoose ? Duo.sunInk : Duo.ink3)
                }
            }
            Section {
                row("pip", "Go to the Home Screen: it crawls in a floating window. Its pause button swats.")
                row("capsule", "It hides in the Dynamic Island and pokes its antennae out when you least expect it. Long-press the island to swat it. Shake the phone to scare it back in.")
                row("square.grid.2x2", "Add up to four Roach Hole widgets (Hole 1–4). It scurries between them.")
            } header: {
                Text("Where it goes")
            } footer: {
                if !director.islandAvailable {
                    Text("Live Activities are off for this app in Settings, so the island roach can't appear.")
                }
            }
        }
        .navigationTitle("Release")
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                if director.isLoose {
                    Button("Call back", systemImage: "ant.fill") { director.callBack() }
                } else {
                    Button("Release", systemImage: "ant") { director.letLoose() }
                }
            }
        }
    }

    private func row(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(Duo.ink2)
        }
    }
}

/// Records tab: the best score on each hideout.
struct RecordsView: View {
    let model: GameModel

    var body: some View {
        List {
            Section {
                ForEach(GameMap.allCases) { map in
                    HStack {
                        Text(map.label)
                        Spacer()
                        Text(verbatim: "\(model.best(for: map))")
                            .font(DuoType.headline.monospacedDigit())
                            .foregroundStyle(model.best(for: map) > 0 ? Duo.ink : Duo.ink3)
                    }
                }
            } header: {
                Text("Best scores")
            }
        }
        .navigationTitle("Records")
        .toolbar {
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("Start", systemImage: "play.fill") { model.start(map: model.map) }
            }
        }
    }
}

/// The rules, short.
private struct HelpView: View {
    let islandAvailable: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Duo.Space.xxl) {
                    group("In a round", [
                        ("hand.tap", "Open: tap roaches to squash them."),
                        ("iphone.gen3", "Closed: a roach shows up outside. Open the phone to trap it, then slam it shut."),
                        ("bolt", "Slamming the phone shut squashes every roach inside at once."),
                        ("trash", "Trash breeds roaches. Drag scraps into the bin to clean up."),
                        ("apps.iphone", "Home Screen map: bugs eat your app icons. Swat them before they take over."),
                    ])
                    group("Release", [
                        ("pip", "Go to the Home Screen: it crawls in a floating window. Its pause button swats."),
                        ("capsule", "It hides in the Dynamic Island and pokes its antennae out when you least expect it. Long-press the island to swat it. Shake the phone to scare it back in."),
                        ("square.grid.2x2", "Add up to four Roach Hole widgets (Hole 1–4). It scurries between them."),
                    ])
                    if !islandAvailable {
                        Text("Live Activities are off for this app in Settings, so the island roach can't appear.")
                            .font(DuoType.callout)
                            .foregroundStyle(Duo.sunInk)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(Duo.Space.xl)
            }
            .background(Duo.paper)
            .navigationTitle("How to play")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private func group(_ title: LocalizedStringKey, _ rows: [(String, LocalizedStringKey)]) -> some View {
        VStack(alignment: .leading, spacing: Duo.Space.l) {
            SectionHeading(title)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: Duo.Space.m) {
                    Image(systemName: row.0)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Duo.ink2)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(row.1)
                        .font(DuoType.body)
                        .foregroundStyle(Duo.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// After a round: the score first, then the few numbers that explain it.
struct ResultsView: View {
    let model: GameModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Duo.Space.xxl) {
                VStack(alignment: .leading, spacing: Duo.Space.xs) {
                    Text(verbatim: "\(model.score)")
                        .font(DuoType.number(72))
                        .foregroundStyle(Duo.ink)
                    HStack(spacing: Duo.Space.s) {
                        Text("Score").foregroundStyle(Duo.ink3)
                        if model.isNewBest {
                            Text("New best!").foregroundStyle(Duo.sunInk).fontWeight(.semibold)
                        }
                    }
                    .font(DuoType.callout)
                    if model.map == .homeScreen {
                        Text("Apps saved \(model.appsSaved) of \(model.icons.count) · +\(model.appsSaved * GameModel.appBonus)")
                            .font(DuoType.callout)
                            .foregroundStyle(model.appsSaved > 0 ? Duo.approve : Duo.reject)
                            .padding(.top, Duo.Space.xs)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: Duo.Space.xxl, verticalSpacing: Duo.Space.m) {
                    stat("Squashed", model.squashed)
                    stat("Escaped", model.escaped)
                    if model.map == .homeScreen {
                        stat("Apps eaten", model.appsEaten)
                    } else {
                        stat("Food lost", model.foodLost)
                        stat("Cleaned", model.cleaned)
                    }
                    stat("Biggest slam", model.bestSlam)
                    stat("Best combo", model.bestCombo)
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Duo.Space.xl)
        }
        .background(Duo.paper)
        .navigationTitle(model.takenOver ? String(localized: "Your Home Screen was taken over!")
                                         : String(localized: "Time's up!"))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Change Map", systemImage: "square.grid.2x2") { model.quit() }
            }
            ToolbarItem(placement: .topBarPinnedTrailing) {
                Button("Play Again", systemImage: "arrow.counterclockwise") { model.start(map: model.map) }
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: Int) -> some View {
        GridRow {
            Text(title)
                .font(DuoType.body)
                .foregroundStyle(Duo.ink2)
            Text(verbatim: "\(value)")
                .font(DuoType.headline.monospacedDigit())
                .foregroundStyle(Duo.ink)
                .gridColumnAlignment(.trailing)
        }
    }
}
