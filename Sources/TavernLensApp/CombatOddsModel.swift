import Foundation
import Observation
import os
import TavernEngine

/// Runs the engine's combat requests through the simulator and holds the odds of the latest one.
///
/// The simulator (its own JavaScriptCore VM, off the main thread) is created and given its
/// card DB once, at launch, so a combat's first result comes within tens of milliseconds of
/// its start. A new combat cancels the one before. Partial results refine `current` in place,
/// at most about 10 times a second.
@MainActor
@Observable
final class CombatOddsModel {
    /// The latest combat's odds; the overlay shows them while that combat is on screen.
    private(set) var current: CombatOddsView?
    /// Why the simulator couldn't start, if it couldn't.
    private(set) var unavailableReason: String?
    private(set) var diagnosticFailure: String?
    @ObservationIgnored private var lastPreview: OddsPreviewView?
    @ObservationIgnored private var lastAdvice: AdviceView?
    @ObservationIgnored private var lastRequest: AdvisorRequest?
    @ObservationIgnored private var diagnostic: AdvisorTurnDiagnostic?
    @ObservationIgnored private var diagnosticWrite: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "advisor-diagnostics")
    /// The recruit-phase preview: the board now against the next opponent's last-seen board.
    private(set) var preview: OddsPreviewView?
    /// Runs the preview on the same simulator (debounced, latest board only). The advisor can
    /// score hypothetical boards with its `score(_:budget:)`.
    @ObservationIgnored private(set) lazy var previewRunner: OddsPreviewRunner = {
        let runner = OddsPreviewRunner(simulator: { [weak self] in
            guard let task = await self?.simulator else { throw CancellationError() }
            return try await task.value
        })
        runner.onChange = { [weak self] view in
            self?.preview = view
            if let view { self?.lastPreview = view }
        }
        return runner
    }()

    /// The advisor's ranked suggestions for the recruit phase on screen.
    private(set) var advice: AdviceView?
    /// Scores the advisor's candidate actions on the same simulator (debounced, latest state
    /// only, within a time budget per state).
    @ObservationIgnored private(set) lazy var advisorRunner: AdvisorRunner = {
        let runner = AdvisorRunner(simulator: { [weak self] in
            guard let task = await self?.simulator else { throw CancellationError() }
            return try await task.value
        })
        runner.onChange = { [weak self] view in
            guard let self else { return }
            self.advice = view
            if let view, let request = self.advisorRunner.currentRequest,
               AdviceView.fingerprint(of: request) == view.fingerprint {
                self.lastAdvice = view
                self.lastRequest = request
            }
        }
        return runner
    }()

    @ObservationIgnored private var simulator: Task<CombatSimulator, any Error>?
    @ObservationIgnored private var running: Task<Void, Never>?
    static let refreshInterval: Duration = .milliseconds(100)

    /// Creates the simulator and loads its card DB in the background. Call once, at launch.
    func warmUp() {
        guard simulator == nil else { return }
        simulator = Task.detached(priority: .utility) {
            let simulator = try CombatSimulator()
            try simulator.loadPinnedCards()
            return simulator
        }
        Task {
            do {
                _ = try await simulator?.value
            } catch {
                unavailableReason = "\(error)"
            }
        }
    }

    /// Simulates a combat that just started, replacing any earlier one.
    func start(_ request: CombatSimulationRequest) {
        guard current?.requestID != request.id else { return }
        warmUp()
        diagnostic = AdvisorTurnDiagnostic(combat: request, request: lastRequest, displayed: lastAdvice)
        if let lastPreview, lastPreview.requestID == "\(request.gameSeed.map(String.init) ?? "-")/\(request.bgTurn)/P\(request.opponentPlayerID)" {
            diagnostic?.preview = lastPreview
        }
        persistDiagnostic()
        lastPreview = nil; lastAdvice = nil; lastRequest = nil
        // The combat's odds come first: the preview and the advisor share the simulator's one thread.
        previewRunner.cancel()
        advisorRunner.cancel()
        running?.cancel()
        current = CombatOddsView(request: request)
        let id = request.id
        let simulatorTask = simulator
        let refine: @Sendable (CombatOdds) -> Void = { [weak self] partial in
            Task { @MainActor in self?.update(id, odds: partial) }
        }
        running = Task { [weak self] in
            do {
                let input = try JSONEncoder().encode(request.input)
                guard let simulator = try await simulatorTask?.value else { return }
                let throttle = Throttle(interval: Self.refreshInterval)
                let odds = try await simulator.simulate(input: input) { partial in
                    if throttle.allows() { refine(partial) }
                }
                self?.update(id, odds: odds)
            } catch is CancellationError {
                // A newer combat replaced this one.
            } catch {
                self?.fail(id, error)
            }
        }
    }

    /// The recruit-phase preview's latest input (nil outside recruit).
    func preview(_ request: OddsPreviewRequest?) {
        if request != nil { warmUp() }
        previewRunner.update(request)
    }

    /// The advisor's latest state (nil outside recruit).
    func advise(_ request: AdvisorRequest?) {
        if request != nil { warmUp() }
        advisorRunner.update(request)
    }

    private func persistDiagnostic() {
        guard let record = diagnostic else { return }
        let previous = diagnosticWrite
        diagnosticWrite = Task { [weak self] in
            await previous?.value
            do {
                try await AdvisorDiagnosticStore.standard.save(record)
                self?.diagnosticFailure = nil
            } catch {
                let message = error.localizedDescription
                self?.diagnosticFailure = message
                Self.log.error("Could not save advisor evidence: \(message, privacy: .public)")
            }
        }
    }

    private func update(_ id: String, odds: CombatOdds) {
        guard current?.requestID == id, current?.isFinal == false else { return }
        current?.odds = odds
        if odds.isFinal {
            diagnostic?.odds = current
            persistDiagnostic()
        }
    }

    private func fail(_ id: String, _ error: any Error) {
        guard current?.requestID == id else { return }
        current?.failure = "\(error)"
        diagnostic?.failure = "\(error)"
        persistDiagnostic()
    }
}

/// Lets a call through at most once per interval (the first always).
private final class Throttle: @unchecked Sendable {
    private let interval: Duration
    private let clock = ContinuousClock()
    private var last: ContinuousClock.Instant?
    private let lock = NSLock()

    init(interval: Duration) { self.interval = interval }

    func allows() -> Bool {
        lock.withLock {
            let now = clock.now
            if let last, now - last < interval { return false }
            last = now
            return true
        }
    }
}
