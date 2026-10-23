import DuoKit
import SwiftUI

@main
struct CockroachSmasherApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .tint(Duo.ink)
        }
        // iOS occasionally wakes the app so the roach can peek out of the
        // Dynamic Island even while the app is closed.
        .backgroundTask(.appRefresh(RoachLife.peekTaskID)) {
            await LifeDirector.shared.backgroundPeek()
        }
    }
}
