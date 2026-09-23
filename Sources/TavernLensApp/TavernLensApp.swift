import AppKit
import SwiftUI
import TavernEngine

@main
struct TavernLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var debugReplay = DebugReplayModel()

    var body: some Scene {
        MenuBarExtra("Tavern Lens", systemImage: "binoculars.fill") {
            MenuBarContent(debugReplay: debugReplay)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only. The bundle's Info.plist sets LSUIElement too; this also
        // covers running the bare executable with `swift run`.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarContent: View {
    let debugReplay: DebugReplayModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(debugReplay.menuStatus)
        Divider()
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
