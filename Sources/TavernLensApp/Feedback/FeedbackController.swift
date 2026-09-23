import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import TavernEngine

/// The feedback hotkey (⌃⌥F): bookmarks the moment on screen, then asks for a one-line note.
///
/// The moment is captured when the key is pressed, before the note is typed: the engine's
/// published state, the Power.log stretch that replays to it, and what the overlay showed.
/// The note box is a non-activating panel, so it takes the keyboard without bringing
/// Tavern Lens forward; Hearthstone stays the active app and gets the keyboard back when
/// the box closes. Return saves, Esc discards, and clicking away saves what was typed.
@MainActor
@Observable
final class FeedbackController {
    static let hotKeyName = "⌃⌥F"

    private(set) var hotKeyAvailable = false
    /// The last bookmark saved this launch, for the menu.
    private(set) var lastSaved: FeedbackBookmark?

    @ObservationIgnored private let live: LiveTrackingModel
    @ObservationIgnored private let overlay: OverlayController
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var panel: NoteBoxPanel?

    init(live: LiveTrackingModel, overlay: OverlayController) {
        self.live = live
        self.overlay = overlay
    }

    func start() {
        hotKey = GlobalHotKey(
            keyCode: kVK_ANSI_F, modifiers: controlKey | optionKey, displayName: Self.hotKeyName
        ) { [weak self] in self?.bookmarkNow() }
        hotKeyAvailable = hotKey != nil
    }

    /// Captures the moment and opens the note box; with no game shown, says so briefly.
    func bookmarkNow() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        guard var bookmark = live.captureBookmark() else {
            show(NoteBoxPanel(message: "No Battlegrounds game to bookmark yet"), autoClose: 1.6)
            return
        }
        bookmark.overlay = overlay.bookmarkContext(shown: bookmark.shown.state)
        let captured = bookmark
        let box = NoteBoxPanel(bookmark: captured) { [weak self] outcome in
            self?.finish(captured, outcome)
        }
        show(box, autoClose: nil)
    }

    private func finish(_ bookmark: FeedbackBookmark, _ outcome: NoteBoxOutcome) {
        panel?.orderOut(nil)
        panel = nil
        guard case .save(let note) = outcome else { return }
        var bookmark = bookmark
        bookmark.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if live.save(bookmark) {
            lastSaved = bookmark
        } else {
            NSSound.beep()
        }
    }

    private func show(_ box: NoteBoxPanel, autoClose: TimeInterval?) {
        panel = box
        let size = box.frame.size
        let area = overlay.contentScreenFrame ?? NSScreen.main?.visibleFrame ?? .zero
        // Upper middle of Hearthstone's window, clear of Bob and the board.
        box.setFrameOrigin(CGPoint(x: area.midX - size.width / 2, y: area.maxY - area.height * 0.34 - size.height / 2))
        box.makeKeyAndOrderFront(nil)
        if let autoClose {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoClose) { [weak self, weak box] in
                guard let self, let box, self.panel === box else { return }
                box.orderOut(nil)
                self.panel = nil
            }
        }
    }
}

enum NoteBoxOutcome {
    case save(String)
    case discard
}

/// A small floating box with one text field. Non-activating: it becomes key (so it gets the
/// keyboard) without activating Tavern Lens.
final class NoteBoxPanel: NSPanel, NSWindowDelegate {
    private var onFinish: ((NoteBoxOutcome) -> Void)?
    private let model = NoteBoxModel()

    convenience init(bookmark: FeedbackBookmark, onFinish: @escaping (NoteBoxOutcome) -> Void) {
        self.init(title: Self.title(for: bookmark), message: nil)
        self.onFinish = onFinish
    }

    convenience init(message: String) {
        self.init(title: message, message: message)
    }

    private init(title: String, message: String?) {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: message == nil ? 92 : 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        isExcludedFromWindowsMenu = true
        delegate = self
        model.title = title
        model.isMessage = message != nil
        model.submit = { [weak self] in self?.finish(.save(self?.model.note ?? "")) }
        model.cancel = { [weak self] in self?.finish(.discard) }
        contentView = NSHostingView(rootView: NoteBoxView(model: model))
    }

    override var canBecomeKey: Bool { !model.isMessage }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        finish(.discard)
    }

    /// Clicking back into Hearthstone keeps the bookmark with whatever was typed.
    func windowDidResignKey(_ notification: Notification) {
        finish(.save(model.note))
    }

    private func finish(_ outcome: NoteBoxOutcome) {
        guard let onFinish else { return }
        self.onFinish = nil
        onFinish(outcome)
    }

    static func title(for bookmark: FeedbackBookmark) -> String {
        var parts = ["Bookmarked"]
        if let turn = bookmark.bgTurn { parts.append(turn > 0 ? "turn \(turn)" : "hero pick") }
        if let phase = bookmark.phase, bookmark.bgTurn ?? 0 > 0 { parts.append(phase.rawValue) }
        if bookmark.shown.state.status == .gameOver { parts.append("game over") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class NoteBoxModel {
    var title = ""
    var note = ""
    var isMessage = false
    @ObservationIgnored var submit: () -> Void = {}
    @ObservationIgnored var cancel: () -> Void = {}
}

struct NoteBoxView: View {
    @Bindable var model: NoteBoxModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: model.isMessage ? "bookmark.slash" : "bookmark.fill")
                    .foregroundStyle(model.isMessage ? Color.secondary : Color.orange)
                Text(model.title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if !model.isMessage {
                    Text("Return saves · Esc discards")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            if !model.isMessage {
                TextField("What's wrong or worth checking here?", text: $model.note)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { model.submit() }
                    .onExitCommand { model.cancel() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HUDMaterial(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
    }
}
