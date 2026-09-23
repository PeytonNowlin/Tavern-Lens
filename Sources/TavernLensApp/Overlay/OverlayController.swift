import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation
import OverlayLayout
import SwiftUI
import TavernEngine

/// Keeps the overlay panel on Hearthstone's client area and decides when it shows.
///
/// - Visible only while Hearthstone or Tavern Lens is frontmost, Hearthstone has a window,
///   and the player hasn't hidden it with the hotkey.
/// - Follows the window by polling it at 10 Hz while visible (CGWindowList, plus AX when
///   Accessibility is granted), so moves, resizes and fullscreen transitions are picked up.
/// - Re-shows the panel after fullscreen transitions and Space changes, because a window
///   shown before the transition isn't moved into the new Space on its own.
/// - Click-through, except while the cursor is inside one of the model's interactive regions.
/// - Tracks which leaderboard portrait the cursor is over from global mouse moves, which need
///   no permission and arrive while the panel is click-through (Hearthstone gets the events).
@MainActor
@Observable
final class OverlayController {
    static let hotKeyName = "⌃⌥H"
    private static let hiddenDefaultsKey = "overlayHiddenByUser"
    private static let guidesDefaultsKey = "overlayShowsLayoutGuides"

    /// The player hid the overlay (hotkey or HUD button). Remembered across launches.
    private(set) var isHiddenByUser: Bool
    private(set) var accessibilityTrusted = AXIsProcessTrusted()
    private(set) var hotKeyAvailable = false
    /// The last window seen, for the menu.
    private(set) var window: HearthstoneWindow?

    var showsLayoutGuides: Bool {
        get { model.showsLayoutGuides }
        set {
            model.showsLayoutGuides = newValue
            UserDefaults.standard.set(newValue, forKey: Self.guidesDefaultsKey)
        }
    }

    @ObservationIgnored private let live: LiveTrackingModel
    @ObservationIgnored private let model = OverlayModel()
    @ObservationIgnored private var panel: OverlayPanel?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var mouseMonitors: [Any] = []
    @ObservationIgnored private var isShown = false
    @ObservationIgnored private var needsReshow = false

    init(live: LiveTrackingModel) {
        self.live = live
        isHiddenByUser = UserDefaults.standard.bool(forKey: Self.hiddenDefaultsKey)
        model.showsLayoutGuides = UserDefaults.standard.bool(forKey: Self.guidesDefaultsKey)
    }

    func start() {
        model.hide = { [weak self] in self?.setHidden(true) }
        // Card names for the opponent panels; the live engine runs without card data.
        CardDataModel.shared.loadIfNeeded()
        let panel = OverlayPanel()
        panel.contentView = OverlayHostingView(rootView: OverlayRootView(model: model))
        self.panel = panel

        hotKey = GlobalHotKey(
            keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey, displayName: Self.hotKeyName
        ) { [weak self] in self?.toggleHidden() }
        hotKeyAvailable = hotKey != nil

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.needsReshow = true
                self?.refresh()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        // Our own app becoming active (the debug window) also counts as "frontmost".
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.refresh() }
            })
        }

        let mouseMoved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }) {
            mouseMonitors.append(local)
        }

        observeLive()
        refresh()
    }

    func toggleHidden() { setHidden(!isHiddenByUser) }

    func setHidden(_ hidden: Bool) {
        isHiddenByUser = hidden
        UserDefaults.standard.set(hidden, forKey: Self.hiddenDefaultsKey)
        refresh()
    }

    /// Asks macOS for Accessibility (opens the system prompt once); the overlay works without it.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// What the overlay is showing, for a feedback bookmark of `shown`.
    func bookmarkContext(shown: ViewState) -> BookmarkOverlay {
        var panels: [String] = []
        if isShown, let game = model.game {
            panels.append("hud")
            if model.leaderboardGame != nil {
                if model.nextOpponentSlot != nil { panels.append("nextOpponentRing") }
                if game.phase == .recruit, let next = game.nextOpponent, !next.isLocal { panels.append("nextOpponentPreview") }
                if model.hoveredOpponent != nil { panels.append("opponentPanel") }
            }
        }
        return BookmarkOverlay(
            visible: isShown, hiddenByUser: isHiddenByUser, showsLayoutGuides: showsLayoutGuides,
            contentWidth: window.map { Double($0.contentFrame.width) },
            contentHeight: window.map { Double($0.contentFrame.height) },
            fullscreen: window?.isFullscreen, layoutVersion: model.layout?.constants.version, panels: panels,
            hoveredPlayerID: isShown ? model.hoveredOpponent?.playerID : nil, drewShownState: model.view == shown
        )
    }

    /// Hearthstone's client area in AppKit screen coordinates, while the overlay is on it.
    var contentScreenFrame: CGRect? {
        guard isShown, let panel else { return nil }
        return panel.frame
    }

    // MARK: - State

    private func observeLive() {
        withObservationTracking {
            _ = live.hearthstone
            _ = live.update.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.observeLive()
            }
        }
    }

    private var hearthstonePID: pid_t? { live.hearthstone?.processIdentifier }

    private var hearthstoneOrUsFrontmost: Bool {
        guard let pid = hearthstonePID else { return false }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return front == pid || front == ProcessInfo.processInfo.processIdentifier || NSApp.isActive
    }

    /// Re-reads the window and the view state, then shows, moves or hides the panel.
    private func refresh() {
        guard let panel else { return }
        if model.view != live.update.state { model.view = live.update.state }
        let wanted = !isHiddenByUser && hearthstoneOrUsFrontmost
        let located = wanted ? hearthstonePID.flatMap(HearthstoneWindowTracker.locate) : nil
        if !wanted || located == nil {
            accessibilityTrusted = AXIsProcessTrusted()
        }

        guard let located, let primaryHeight = NSScreen.screens.first?.frame.maxY,
              let layout = OverlayLayout(contentSize: located.contentFrame.size)
        else {
            hide(panel)
            // Keep polling while Hearthstone is frontmost but its window isn't found yet.
            setPolling(wanted)
            return
        }

        if let previous = window, previous.isFullscreen != located.isFullscreen { needsReshow = true }
        window = located
        if model.layout != layout { model.layout = layout }
        let frame = WindowGeometry.appKitRect(fromTopLeft: located.contentFrame, primaryScreenHeight: primaryHeight)
        if panel.frame != frame { panel.setFrame(frame, display: true) }

        if needsReshow, isShown {
            // A window shown before a fullscreen transition stays on the old Space until re-ordered.
            panel.orderOut(nil)
            isShown = false
        }
        needsReshow = false
        if !isShown {
            panel.orderFrontRegardless()
            isShown = true
        }
        updatePointer()
        setPolling(true)
    }

    private func hide(_ panel: OverlayPanel) {
        guard isShown else { return }
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
        isShown = false
        if model.hoveredSlot != nil { model.hoveredSlot = nil }
    }

    private func setPolling(_ on: Bool) {
        if on, pollTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !on, let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
    }

    /// Takes clicks only while the cursor is over an interactive region; otherwise clicks go to
    /// Hearthstone. Also hit-tests the leaderboard for the hovered portrait.
    private func updatePointer() {
        guard let panel, isShown, let content = window?.contentFrame,
              let primaryHeight = NSScreen.screens.first?.frame.maxY
        else { return }
        let point = WindowGeometry.localPoint(
            fromAppKit: NSEvent.mouseLocation, contentFrame: content, primaryScreenHeight: primaryHeight
        )
        let interactive = model.interactiveRegions.contains { $0.contains(point) }
        if panel.ignoresMouseEvents == interactive {
            panel.ignoresMouseEvents = !interactive
        }
        let hovered = model.leaderboardSlot(at: point)
        if model.hoveredSlot != hovered { model.hoveredSlot = hovered }
    }
}
