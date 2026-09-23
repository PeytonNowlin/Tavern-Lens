import AppKit
import CoreGraphics

/// Screen Recording, which reading the hero-pick banner needs. Everything else works without it.
@MainActor
enum ScreenRecordingPermission {
    /// Granted. Never prompts.
    nonisolated static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Explains what the permission is for, then asks macOS for it. macOS shows its own
    /// prompt only the first time; after that the player turns it on in System Settings.
    /// - Returns: whether it's granted now (often only after Tavern Lens is reopened).
    @discardableResult
    static func request() -> Bool {
        guard !isGranted else { return true }
        let explain = NSAlert()
        explain.messageText = "Read the lobby's tribes from the screen?"
        explain.informativeText = """
            At the hero pick, Hearthstone lists the lobby's five tribes under “Choose a Hero”. With Screen \
            Recording allowed, Tavern Lens reads that line, so the tribes are exact from the start instead of \
            inferred by about turn 4. It also checks once per game that the overlay still lines up with the game.

            It captures only that small strip of Hearthstone's window, only during the hero pick. Nothing is \
            saved or sent anywhere. Without it, everything else works as before.
            """
        explain.addButton(withTitle: "Continue")
        explain.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard explain.runModal() == .alertFirstButtonReturn else { return false }

        if CGRequestScreenCaptureAccess() { return true }
        // Already asked once (or turned off): macOS won't prompt again, so point to Settings.
        let settings = NSAlert()
        settings.messageText = "Allow Screen Recording in System Settings"
        settings.informativeText = "Turn on Tavern Lens under Privacy & Security › Screen & System Audio Recording, "
            + "then quit and reopen Tavern Lens."
        settings.addButton(withTitle: "Open System Settings")
        settings.addButton(withTitle: "Cancel")
        if settings.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return isGranted
    }
}
