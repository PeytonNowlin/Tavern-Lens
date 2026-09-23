import AppKit
import Observation
import os
import OverlayLayout
import ScreenReading
import TavernEngine

/// Reads the lobby's tribes from the hero-pick banner and checks the overlay's alignment
/// against it and against the board, once per game.
///
/// It does nothing without Screen Recording or while turned off. Otherwise, when a game
/// reaches its hero pick it captures just the banner strip of Hearthstone's window
/// (`OverlayLayout.heroPickCapture`) about once a second until it has a complete, confident
/// reading, which goes to the engine as screen evidence, and stops when the hero pick ends.
/// The first capture that finds the banner's title also checks the layout: if the title
/// isn't where the geometry predicts, the overlay shows a "misaligned" notice for that game.
/// At the game's first recruit phase it also captures two small strips of the board, around
/// the gold pill and the hero's health (`OverlayLayout.boardCheckCapture`), a few times until
/// their text is found, and shows the same notice if it isn't where the layout puts it.
/// Capture runs in ScreenCaptureKit's own process and recognition off the main thread.
@MainActor
@Observable
final class HeroPickScreenReader {
    private static let enabledDefaultsKey = "readsTribesFromScreen"
    private static let log = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "screen")
    /// Before the first capture: the banner animates in.
    static let firstDelay: Duration = .milliseconds(1500)
    static let interval: Duration = .seconds(1)
    static let maxAttempts = 25
    /// Before the board check's first capture: the recruit phase's board animates in.
    static let boardFirstDelay: Duration = .seconds(2)
    static let boardMaxAttempts = 10

    enum Status: Equatable {
        case idle
        case reading
        /// The tribes read, and how long the capture and the recognition took.
        case read(tribes: [String], capture: Duration, recognition: Duration)
        /// The hero pick ended without a trusted reading.
        case notRead(String)
    }

    private(set) var permissionGranted = ScreenRecordingPermission.isGranted
    private(set) var status: Status = .idle
    /// This game's alignment check; nil until the banner's title was found.
    private(set) var alignment: BannerAlignment?
    /// This game's board-position check; nil until an anchor was found.
    private(set) var boardAlignment: BoardAlignment?

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if !isEnabled {
                stop()
                stopBoardCheck()
            } else if inHeroPick, task == nil {
                beginHeroPick()  // turned on during a hero pick: the banner is still there
            } else {
                stateChanged()  // turned on during recruit: the board is there
            }
        }
    }

    @ObservationIgnored private let live: LiveTrackingModel
    @ObservationIgnored private let overlay: OverlayController
    @ObservationIgnored private var inHeroPick = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastFailure: String?
    /// This game's board check has started (it runs once, at the first recruit phase seen).
    @ObservationIgnored private var boardCheckStarted = false
    @ObservationIgnored private var boardTask: Task<Void, Never>?

    init(live: LiveTrackingModel, overlay: OverlayController) {
        self.live = live
        self.overlay = overlay
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    func start() {
        observeLive()
        stateChanged()
    }

    /// Explains and asks for Screen Recording.
    func requestPermission() {
        permissionGranted = ScreenRecordingPermission.request()
        if permissionGranted, inHeroPick, task == nil { beginHeroPick() }
        if permissionGranted { stateChanged() }
    }

    /// Re-checks the permission (it can be granted or revoked in System Settings at any time).
    func refreshPermission() {
        permissionGranted = ScreenRecordingPermission.isGranted
    }

    /// For the menu.
    var statusText: String? {
        switch status {
        case .idle: nil
        case .reading: "Reading the hero-pick banner…"
        case .read(let tribes, let capture, let recognition):
            "Banner read: \(tribes.joined(separator: ", ")) (\(Self.ms(capture)) + \(Self.ms(recognition)) ms)"
        case .notRead(let why): "Banner not read: \(why)"
        }
    }

    /// For the menu, while one of this game's checks failed.
    var alignmentWarning: String? {
        var parts: [String] = []
        if let alignment, !alignment.isAligned {
            parts.append(String(format: "the hero-pick banner is %.3f h off where it's expected", alignment.offset))
        }
        if let boardAlignment, !boardAlignment.isAligned {
            let off = boardAlignment.offsets.map { String(format: "%@ %.3f h", $0.anchor.rawValue, $0.offset) }
            parts.append("the board is off where it's expected (\(off.joined(separator: ", ")))")
        }
        guard !parts.isEmpty else { return nil }
        return "The overlay may be misaligned: \(parts.joined(separator: "; ")) (a patch may have moved it). "
            + "Turn on Show Layout Guides to check."
    }

    private func updateOverlayWarning() {
        let misaligned = alignment?.isAligned == false || boardAlignment?.isAligned == false
        overlay.alignmentWarning = misaligned ? "⚠︎ Overlay misaligned" : nil
    }

    // MARK: - Hero pick

    private func observeLive() {
        withObservationTracking {
            _ = live.update.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.stateChanged()
                self.observeLive()
            }
        }
    }

    private var isHeroPick: Bool {
        let state = live.update.state
        return state.status == .inGame && state.game?.phase == .heroPick
    }

    private var isRecruit: Bool {
        let state = live.update.state
        return state.status == .inGame && state.game?.phase == .recruit
    }

    private func stateChanged() {
        if live.update.state.status != .inGame {
            resetBoardCheck()  // between games: the next one gets its own check
        } else if isRecruit, !boardCheckStarted {
            beginBoardCheck()
        }
        let heroPick = isHeroPick
        if heroPick, !inHeroPick {
            inHeroPick = true
            beginHeroPick()
        } else if !heroPick, inHeroPick {
            inHeroPick = false
            stop()
        }
    }

    private func beginHeroPick() {
        // A new game: its own checks.
        alignment = nil
        resetBoardCheck()
        lastFailure = nil
        refreshPermission()
        guard isEnabled, permissionGranted else { return }
        status = .reading
        task?.cancel()
        task = Task { [weak self] in
            for attempt in 0..<Self.maxAttempts {
                try? await Task.sleep(for: attempt == 0 ? Self.firstDelay : Self.interval)
                guard let self, !Task.isCancelled, self.isHeroPick else { return }
                if await self.attempt() { return }
            }
            self?.finishUnread()
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        if status == .reading { finishUnread() }
    }

    private func finishUnread() {
        guard status == .reading else { return }
        status = .notRead(lastFailure ?? "no clear reading")
    }

    /// One capture and recognition. True once the tribes are read.
    private func attempt() async -> Bool {
        guard let pid = live.hearthstone?.processIdentifier,
              let window = HearthstoneWindowTracker.locate(pid: pid),
              let layout = OverlayLayout(contentSize: window.contentFrame.size)
        else {
            lastFailure = "Hearthstone's window wasn't found"
            return false
        }
        let rect = layout.heroPickCapture
        let content = window.contentFrame
        let expected = live.pool?.tribesPerLobby ?? 5
        let clock = ContinuousClock()
        let start = clock.now
        let image: CGImage
        do {
            image = try await BannerCapture.capture(pid: pid, rect: rect.offsetBy(dx: content.minX, dy: content.minY))
        } catch {
            lastFailure = "\(error)"
            Self.log.error("Banner capture failed: \(String(describing: error), privacy: .public)")
            if error as? BannerCapture.Failure == .noPermission { permissionGranted = false }
            return false
        }
        let captured = clock.now
        let reading: HeroPickBannerReading
        do {
            reading = try await Task.detached(priority: .userInitiated) {
                try HeroPickBannerReader.read(image, capturedRect: rect, layout: layout, expectedTribes: expected)
            }.value
        } catch {
            lastFailure = "text recognition failed"
            Self.log.error("Banner recognition failed: \(String(describing: error), privacy: .public)")
            return false
        }
        let recognised = clock.now
        let captureTime = captured - start, recognitionTime = recognised - captured
        Self.log.info(
            "Banner: capture \(Self.ms(captureTime)) ms, recognition \(Self.ms(recognitionTime)) ms, \(image.width)×\(image.height) px, lines \(reading.lines.map(\.text), privacy: .public)"
        )

        if alignment == nil, let found = reading.alignment {
            alignment = found
            updateOverlayWarning()
            if !found.isAligned {
                Self.log.notice(
                    "Layout check: banner title off by dx \(found.dx) h, dy \(found.dy) h, width ×\(found.widthRatio) (layout \(layout.constants.version, privacy: .public))"
                )
            }
        }
        guard let tribes = reading.trustedTribes, isHeroPick else {
            lastFailure = reading.tribes == nil ? "the tribes weren't found" : "the reading wasn't clear"
            return false
        }
        live.ingestScreenTribes(tribes)
        status = .read(
            tribes: tribes.tribes.map(TribeView.displayName), capture: captureTime, recognition: recognitionTime
        )
        return true
    }

    // MARK: - Board check

    private func resetBoardCheck() {
        boardTask?.cancel()
        boardTask = nil
        boardCheckStarted = false
        boardAlignment = nil
        updateOverlayWarning()
    }

    private func stopBoardCheck() {
        boardTask?.cancel()
        boardTask = nil
    }

    /// Once per game, at the first recruit phase: a few tries until an anchor is found.
    private func beginBoardCheck() {
        refreshPermission()
        guard isEnabled, permissionGranted else { return }
        boardCheckStarted = true
        boardTask?.cancel()
        boardTask = Task { [weak self] in
            for attempt in 0..<Self.boardMaxAttempts {
                try? await Task.sleep(for: attempt == 0 ? Self.boardFirstDelay : Self.interval)
                guard let self, !Task.isCancelled else { return }
                // Only while the board is up; a later recruit phase gets the tries left.
                guard self.isRecruit else { continue }
                if await self.attemptBoardCheck() { return }
            }
            Self.log.info("Board check: no anchor found this game")
        }
    }

    /// One capture of each anchor and recognition. True once an anchor was found.
    private func attemptBoardCheck() async -> Bool {
        guard let pid = live.hearthstone?.processIdentifier,
              let window = HearthstoneWindowTracker.locate(pid: pid),
              let layout = OverlayLayout(contentSize: window.contentFrame.size)
        else { return false }
        let content = window.contentFrame
        var captures: [BoardAnchor: (image: CGImage, rect: CGRect)] = [:]
        do {
            for anchor in BoardAnchor.allCases {
                let rect = layout.boardCheckCapture(anchor)
                let image = try await BannerCapture.capture(pid: pid, rect: rect.offsetBy(dx: content.minX, dy: content.minY))
                captures[anchor] = (image, rect)
            }
        } catch {
            Self.log.error("Board capture failed: \(String(describing: error), privacy: .public)")
            if error as? BannerCapture.Failure == .noPermission { permissionGranted = false }
            return false
        }
        let snapshot = captures
        guard let result = try? await Task.detached(priority: .userInitiated, operation: {
            try BoardCheckReader.read(snapshot, layout: layout)
        }).value, !Task.isCancelled, isRecruit else { return false }
        let lines = result.readings.mapValues { $0.lines.map(\.text) }
        Self.log.info("Board check: lines \(String(describing: lines), privacy: .public)")
        guard let found = result.alignment else { return false }
        boardAlignment = found
        updateOverlayWarning()
        let offsets = found.offsets.map { "\($0.anchor.rawValue) dx \($0.dx) dy \($0.dy)" }.joined(separator: ", ")
        if found.isAligned {
            Self.log.info("Board check: aligned (\(offsets, privacy: .public))")
        } else {
            Self.log.notice(
                "Layout check: board off (\(offsets, privacy: .public)) (layout \(layout.constants.version, privacy: .public))"
            )
        }
        return true
    }

    private static func ms(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
