import AppKit
import HSLog
import SwiftUI
import TavernEngine

@main
struct TavernLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var debugReplay = DebugReplayModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                live: appDelegate.live, overlay: appDelegate.overlay, feedback: appDelegate.feedback,
                debugReplay: debugReplay, retention: appDelegate.retention, screenReader: appDelegate.screenReader
            )
        } label: {
            MenuBarLabel(live: appDelegate.live)
        }

        Window("Tavern Lens Debug", id: WindowID.debug) {
            DebugWindow(model: debugReplay)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 980, height: 640)

        Window("Tavern Lens Settings", id: WindowID.settings) {
            SettingsWindow(model: appDelegate.retention, housekeeping: appDelegate.housekeeping)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let debug = "debug"
    static let settings = "settings"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let live: LiveTrackingModel
    let overlay: OverlayController
    let retention = RetentionSettingsModel()
    let housekeeping: HousekeepingModel
    let feedback: FeedbackController
    let screenReader: HeroPickScreenReader

    override init() {
        live = LiveTrackingModel()
        overlay = OverlayController(live: live)
        housekeeping = HousekeepingModel(settings: retention, live: live)
        feedback = FeedbackController(live: live, overlay: overlay)
        screenReader = HeroPickScreenReader(live: live, overlay: overlay)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--simulator-benchmark") {
            Self.runSimulatorBenchmark()
            return
        }
        // Menu-bar only. The bundle's Info.plist sets LSUIElement too; this also
        // covers running the bare executable with `swift run`.
        NSApp.setActivationPolicy(.accessory)
        // Card data keeps as many earlier builds as the retention settings say.
        CardDataModel.shared.previousBuildsKept = { [retention] in retention.settings.previousCardDataBuilds }
        // The minion pool (card data + HSReplay + overrides) feeds the live tribe inference.
        PoolDataModel.shared.onPoolChanged = { [live] pool in live.pool = pool }
        PoolDataModel.shared.start()
        // Firestone's hero stats (fetched at launch and every 6 h) feed the hero-pick plates.
        HeroStatsModel.shared.onChanged = { [live] stats, cards in live.heroStats = (stats, cards) }
        HeroStatsModel.shared.start()
        // Build data (Firestone comps + our override file, filtered by the pool) feeds build detection.
        BuildDataModel.shared.onCatalogChanged = { [live] catalog in live.builds = catalog }
        BuildDataModel.shared.start()
        live.start()
        overlay.start()
        feedback.start()
        screenReader.start()
        // Log retention: a pass now, and one after every game.
        live.onGameEnded = { [housekeeping] in housekeeping.run() }
        housekeeping.run()
    }

    /// `TavernLens --simulator-benchmark`: runs the bundled simulator once, prints the time to the
    /// first and the final result, and quits. It checks the packaged app gets JavaScriptCore's JIT
    /// (its allow-jit entitlement): the final result should take well under a second.
    private static func runSimulatorBenchmark() {
        Task.detached {
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let simulator = try CombatSimulator()
                let cards = try simulator.loadPinnedCards()
                let loaded = clock.now - start
                let first = Locked<Duration?>(nil)
                let simulated = clock.now
                let odds = try await simulator.simulate(input: CombatSimulator.benchmarkInput) { _ in
                    first.update { $0 = $0 ?? (clock.now - simulated) }
                }
                print("simulator \(SimulatorResources.pin?.simulator ?? "?"): \(cards) cards loaded in \(loaded)")
                print("first result after \(first.value.map { "\($0)" } ?? "-"), \(odds.simulations) simulations in \(odds.elapsedMilliseconds) ms")
                print("won \(odds.won)% tied \(odds.tied)% lost \(odds.lost)%")
                exit(0)
            } catch {
                print("simulator failed: \(error)")
                exit(1)
            }
        }
    }
}

/// A value shared with a `@Sendable` callback.
private final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value { lock.withLock { stored } }

    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}

struct MenuBarLabel: View {
    let live: LiveTrackingModel

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("Tavern Lens: \(live.status.title)")
    }

    private var symbol: String {
        switch live.status {
        case .restartRequired: "exclamationmark.triangle.fill"
        case .tracking: "binoculars.fill"
        default: "binoculars"
        }
    }
}

struct MenuBarContent: View {
    let live: LiveTrackingModel
    let overlay: OverlayController
    let feedback: FeedbackController
    let debugReplay: DebugReplayModel
    let retention: RetentionSettingsModel
    let screenReader: HeroPickScreenReader
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(live.status.title)
        if live.status == .restartRequired {
            Text("Tavern Lens fixed Hearthstone's log settings. Quit and reopen Hearthstone to start tracking.")
        }
        if live.hstrackerRunning {
            Text("⚠︎ HSTracker is running. It can delete or rewrite the logs Tavern Lens reads. Quit it while playing.")
        }
        ForEach(live.configFailures, id: \.self) { failure in
            Text("⚠︎ \(failure)")
        }
        if let session = live.update.session {
            Text("Session \(session.name)")
        }
        if let bytes = live.powerLogBytes,
           let hint = PowerLogSizeHint.message(bytes: bytes, threshold: retention.settings.powerLogHintBytes) {
            Text("⚠︎ \(hint)")
        }
        Divider()
        OverlayMenuSection(overlay: overlay)
        ScreenReadingMenuSection(reader: screenReader)
        FeedbackMenuSection(feedback: feedback)
        if let failure = live.combatOdds.diagnosticFailure {
            Text("Advisor evidence could not be saved")
                .help(failure)
        }
        Divider()
        if debugReplay.isReplaying || debugReplay.result != nil {
            Text(debugReplay.menuStatus)
        }
        Button("Open Debug Window…") {
            openWindow(id: WindowID.debug)
            NSApp.activate()
        }
        .keyboardShortcut("d")
        Button("Settings…") {
            openWindow(id: WindowID.settings)
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Tavern Lens") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

struct OverlayMenuSection: View {
    @Bindable var overlay: OverlayController

    var body: some View {
        Button(overlay.isHiddenByUser ? "Show Overlay" : "Hide Overlay") {
            overlay.toggleHidden()
        }
        .keyboardShortcut("h", modifiers: [.control, .option])
        if !overlay.hotKeyAvailable {
            Text("⚠︎ The \(OverlayController.hotKeyName) hotkey is in use by another app")
        }
        Toggle("Show Layout Guides", isOn: $overlay.showsLayoutGuides)
        if !overlay.accessibilityTrusted {
            Button("Allow Accessibility for Better Window Tracking…") {
                overlay.requestAccessibility()
            }
        }
    }
}

struct FeedbackMenuSection: View {
    let feedback: FeedbackController

    var body: some View {
        Button("Bookmark This Moment…") { feedback.bookmarkNow() }
            .keyboardShortcut("f", modifiers: [.control, .option])
        if !feedback.hotKeyAvailable {
            Text("⚠︎ The \(FeedbackController.hotKeyName) hotkey is in use by another app")
        }
    }
}
