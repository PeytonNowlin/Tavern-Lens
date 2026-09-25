import BGIntel
import Foundation
import SimulatorRuntime

/// What the next-opponent preview shows about the coming combat during recruit: the odds of the
/// local board as it is now against the next opponent's last-seen board, refined in place, or
/// "no data" when that opponent hasn't been seen.
public struct OddsPreviewView: Codable, Hashable, Sendable {
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
/// most once per `refreshInterval`, in order: a partial that arrives after a later one, or after
/// the final one, is dropped (`LatestRunner`). While a new run starts, the previous board's odds stay up,
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

    /// Simulates one input, reporting each partial result.
    public typealias Simulate = @Sendable (
        BattleInput, SimulationBudget, _ progress: @escaping @Sendable (CombatOdds) -> Void
    ) async throws -> CombatOdds

    private let simulate: Simulate
    /// The input `current` is for (or is waiting on).
    private var latestInput: BattleInput?
    private let runner: LatestRunner<CombatOdds>

    /// - Parameters:
    ///   - simulator: the simulator, ready (card DB loaded); awaited on each run.
    ///   - debounce: how long a board must stay unchanged before it's simulated.
    ///   - replaceAfter: simulations a new run needs before its result replaces the previous board's.
    public convenience init(
        simulator: @escaping @Sendable () async throws -> CombatSimulator, debounce: Duration = .milliseconds(250),
        budget: SimulationBudget = .standard, refreshInterval: Duration = .milliseconds(100), replaceAfter: Int = 250
    ) {
        self.init(
            simulate: { input, budget, progress in try await simulator().simulate(input, budget: budget, progress: progress) },
            debounce: debounce, budget: budget, refreshInterval: refreshInterval, replaceAfter: replaceAfter
        )
    }

    /// Simulates with `simulate` (any scorer, such as a stub in tests).
    public init(
        simulate: @escaping Simulate, debounce: Duration = .milliseconds(250), budget: SimulationBudget = .standard,
        refreshInterval: Duration = .milliseconds(100), replaceAfter: Int = 250
    ) {
        self.simulate = simulate
        self.debounce = debounce
        self.budget = budget
        self.refreshInterval = refreshInterval
        self.replaceAfter = replaceAfter
        runner = LatestRunner(debounce: debounce, refreshInterval: refreshInterval) { $0.simulations >= replaceAfter }
        runner.onResult = { [weak self] odds, _ in self?.receive(odds) }
        runner.onFailure = { [weak self] error in self?.fail(error) }
    }

    /// The preview as of now; nil outside recruit.
    public func update(_ request: OddsPreviewRequest?) {
        guard let request else {
            cancel()
            return
        }
        let sameOpponent = current?.requestID == request.id
        if sameOpponent, latestInput == request.input, current?.hasData == request.hasData { return }
        latestInput = request.input

        guard let input = request.input else {
            runner.stop()
            current = OddsPreviewView(request: request)
            return
        }
        var replacing = false
        if sameOpponent, var view = current, view.odds != nil {
            view.isUpdating = true
            view.failure = nil
            current = view
            replacing = true
        } else {
            current = OddsPreviewView(request: request)
        }
        let simulate = self.simulate, budget = self.budget
        runner.submit(replacing: replacing) { emit in
            try await simulate(input, budget) { partial in emit(partial) }
        }
    }

    /// Stops any run and clears the preview (a combat is starting, or recruit ended).
    public func cancel() {
        runner.stop()
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
        try await simulate(input, budget, progress)
    }

    private func receive(_ odds: CombatOdds) {
        guard var view = current else { return }
        view.odds = odds
        view.isUpdating = false
        current = view
    }

    private func fail(_ error: any Error) {
        guard var view = current else { return }
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
