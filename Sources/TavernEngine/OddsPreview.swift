import BGIntel
import Foundation
import SimulatorRuntime

/// What the next-opponent preview shows about the coming combat during recruit: the odds of the
/// local board as it is now against the next opponent's last-seen board, refined in place, or
/// "no data" when that opponent hasn't been seen.
public struct OddsPreviewView: Hashable, Sendable {
    /// `OddsPreviewRequest.id`: one per game, BG turn and opponent.
    public var requestID: String
    public var bgTurn: Int
    public var opponentPlayerID: Int
    /// The BG turn the opponent's board is from; nil when they haven't been seen.
    public var opponentSeenTurn: Int?
    /// False when the next opponent hasn't been seen: there's nothing to simulate against.
    public var hasData: Bool
    /// The latest result; nil until the first one.
    public var odds: CombatOdds?
    /// The board changed since `odds` was simulated; a new result is on its way.
    public var isUpdating = false
    /// Set when the simulation failed.
    public var failure: String?

    public init(request: OddsPreviewRequest) {
        requestID = request.id
        bgTurn = request.bgTurn
        opponentPlayerID = request.opponentPlayerID
        opponentSeenTurn = request.opponentSeenTurn
        hasData = request.hasData
    }

    /// Whether this is for the recruit phase on screen and its next opponent.
    public func isFor(_ game: GameView) -> Bool {
        game.phase == .recruit && game.bgTurn == bgTurn && game.nextOpponentPlayerID == opponentPlayerID
    }

    /// The chance the coming combat eliminates the local player, when it's above zero.
    public var lethalRisk: Double? { odds.flatMap { $0.lostLethal > 0 ? $0.lostLethal : nil } }
}

/// Runs the recruit-phase odds preview: the latest board only, debounced, refined in place.
///
/// Give it each new `OddsPreviewRequest` (`TavernEngine.oddsPreview`) as the state changes. A
/// changed input waits `debounce` for the board to settle (a drag, a buy and its battlecry), then
/// cancels the run in progress and simulates the new one; partial results refine `current`, at
/// most once per `refreshInterval`. While a new run starts, the previous board's odds stay up,
/// marked updating, until the new run has `replaceAfter` simulations, so the numbers don't flicker.
/// A request without data (the next opponent unseen) shows "no data" and runs nothing; nil
/// (not recruit) stops everything.
///
/// It shares the simulator with the combat-start odds (one JavaScript thread for the process), so
/// call `cancel()` when a combat starts: its odds come first.
///
/// `score(_:budget:)` is the advisor's entry point: it simulates any input, such as
/// `OddsPreviewRequest.input(withBoard:hand:)` for a hypothetical board, on the same simulator.
@MainActor
public final class OddsPreviewRunner {
    public private(set) var current: OddsPreviewView? {
        didSet { if current != oldValue { onChange?(current) } }
    }
    /// Called on each change of `current`.
    public var onChange: ((OddsPreviewView?) -> Void)?

    public let debounce: Duration
    public let budget: SimulationBudget
    public let refreshInterval: Duration
    public let replaceAfter: Int

    private let simulator: @Sendable () async throws -> CombatSimulator
    /// The input `current` is for (or is waiting on).
    private var latestInput: BattleInput?
    /// Bumped for every input accepted; results of older ones are dropped.
    private var generation = 0
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?

    /// - Parameters:
    ///   - simulator: the simulator, ready (card DB loaded); awaited on each run.
    ///   - debounce: how long a board must stay unchanged before it's simulated.
    ///   - replaceAfter: simulations a new run needs before its result replaces the previous board's.
    public init(
        simulator: @escaping @Sendable () async throws -> CombatSimulator, debounce: Duration = .milliseconds(250),
        budget: SimulationBudget = .standard, refreshInterval: Duration = .milliseconds(100), replaceAfter: Int = 250
    ) {
        self.simulator = simulator
        self.debounce = debounce
        self.budget = budget
        self.refreshInterval = refreshInterval
        self.replaceAfter = replaceAfter
    }

    /// The preview as of now; nil outside recruit.
    public func update(_ request: OddsPreviewRequest?) {
        guard let request else {
            cancel()
            return
        }
        let sameOpponent = current?.requestID == request.id
        if sameOpponent, latestInput == request.input, current?.hasData == request.hasData { return }
        generation += 1
        latestInput = request.input
        pending?.cancel()
        pending = nil

        guard let input = request.input else {
            stopRunning()
            current = OddsPreviewView(request: request)
            return
        }
        if sameOpponent, var view = current, view.odds != nil {
            view.isUpdating = true
            view.failure = nil
            current = view
        } else {
            current = OddsPreviewView(request: request)
        }
        let token = generation
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.run(input, token: token)
        }
    }

    /// Stops any run and clears the preview (a combat is starting, or recruit ended).
    public func cancel() {
        generation += 1
        pending?.cancel()
        pending = nil
        stopRunning()
        latestInput = nil
        current = nil
    }

    /// Simulates `input` on the preview's simulator, such as a hypothetical board from
    /// `OddsPreviewRequest.input(withBoard:hand:)`. Independent of the preview; cancel the calling
    /// task to stop it.
    public func score(
        _ input: BattleInput, budget: SimulationBudget = .standard,
        progress: @escaping @Sendable (CombatOdds) -> Void = { _ in }
    ) async throws -> CombatOdds {
        try await simulator().simulate(input, budget: budget, progress: progress)
    }

    private func stopRunning() {
        running?.cancel()
        running = nil
    }

    private func run(_ input: BattleInput, token: Int) {
        guard token == generation else { return }
        stopRunning()
        let simulator = self.simulator
        let budget = self.budget
        let throttle = PreviewThrottle(interval: refreshInterval)
        let refine: @Sendable (CombatOdds) -> Void = { [weak self] partial in
            Task { @MainActor in self?.receive(partial, token: token) }
        }
        running = Task { [weak self] in
            do {
                let odds = try await simulator().simulate(input, budget: budget) { partial in
                    if throttle.allows() { refine(partial) }
                }
                self?.receive(odds, token: token)
            } catch is CancellationError {
                // A newer board replaced this one.
            } catch {
                self?.fail(error, token: token)
            }
        }
    }

    private func receive(_ odds: CombatOdds, token: Int) {
        guard token == generation, var view = current else { return }
        if view.isUpdating, !odds.isFinal, odds.simulations < replaceAfter { return }
        view.odds = odds
        view.isUpdating = false
        current = view
    }

    private func fail(_ error: any Error, token: Int) {
        guard token == generation, var view = current else { return }
        view.failure = "\(error)"
        view.isUpdating = false
        current = view
    }
}

extension CombatSimulator {
    /// Simulates a `BattleInput`, reporting each partial result (see `simulate(input:budget:seed:progress:)`).
    public func simulate(
        _ input: BattleInput, budget: SimulationBudget = .standard, seed: UInt32? = nil,
        progress: @escaping @Sendable (CombatOdds) -> Void = { _ in }
    ) async throws -> CombatOdds {
        // Sorted keys: the same input is the same text, so a seeded run is reproducible across processes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try await simulate(input: encoder.encode(input), budget: budget, seed: seed, progress: progress)
    }
}

/// Lets a call through at most once per interval (the first always).
private final class PreviewThrottle: @unchecked Sendable {
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
