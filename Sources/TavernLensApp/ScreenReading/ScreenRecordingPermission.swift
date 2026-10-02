import AppKit
import CoreGraphics

/// Permission for tribe/alignment checks and automatic lobby MMR reading.
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
        explain.messageText = "Read tribes and MMR from Hearthstone?"
        explain.informativeText = """
            At the hero pick, Hearthstone lists the lobby's five tribes under “Choose a Hero”. With Screen \
            Recording allowed, Tavern Lens reads that line, so the tribes are exact from the start instead of \
            inferred by about turn 4. It also checks once per game that the overlay still lines up with the game.

            During play it captures only the hero-pick strip and two small board spots for alignment checks. \
            Between games it also reads Hearthstone's lobby window to record your visible MMR in local rating history. \
            Screenshots are never saved or sent anywhere. Without access, log tracking still works and you can \
            enter MMR manually.
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
