import Foundation
import Observation
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

    private func update(_ id: String, odds: CombatOdds) {
        guard current?.requestID == id, current?.isFinal == false else { return }
        current?.odds = odds
    }

    private func fail(_ id: String, _ error: any Error) {
        guard current?.requestID == id else { return }
        current?.failure = "\(error)"
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
