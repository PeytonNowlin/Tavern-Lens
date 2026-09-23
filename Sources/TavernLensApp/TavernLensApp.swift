import AppKit
import SwiftUI
import TavernEngine

@main
struct TavernLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var debugReplay = DebugReplayModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(live: appDelegate.live, debugReplay: debugReplay)
        } label: {
            MenuBarLabel(live: appDelegate.live)
        }

        Window("Tavern Lens Debug", id: WindowID.debug) {
            DebugWindow(model: debugReplay)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 980, height: 640)
    }
}

enum WindowID {
    static let debug = "debug"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let live = LiveTrackingModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only. The bundle's Info.plist sets LSUIElement too; this also
        // covers running the bare executable with `swift run`.
        NSApp.setActivationPolicy(.accessory)
        live.start()
    }
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
    let debugReplay: DebugReplayModel
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
        Divider()
        if debugReplay.isReplaying || debugReplay.result != nil {
            Text(debugReplay.menuStatus)
        }
        Button("Open Debug Window…") {
            openWindow(id: WindowID.debug)
            NSApp.activate()
        }
        .keyboardShortcut("d")
        Divider()
        Button("Quit Tavern Lens") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
