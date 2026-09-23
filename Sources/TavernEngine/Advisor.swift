import BGIntel
import Foundation
import SimulatorRuntime

/// How the advisor spends simulations on one recruit-phase state, and the seed that makes it
/// reproducible.
///
/// Scoring runs in passes over the candidates (`AdvisorEvaluation`): stage 0 (the baseline and
/// every basic action), then stage 1 (other placements, targets and sells of the best, moves,
/// and the shop cards too dear for now), each at `simulations` per candidate; then the best
/// `refinedGroups` and the baseline get `refineSimulations` more; then the lobby pass: the
/// baseline and the best `lobbyGroups` board changes against each other opponent's last-seen
/// board, `lobbySimulations` each; then the lobby sweep: every other group's best board change
/// (the too-dear buys a freeze keeps too) against the same boards, `lobbySweepSimulations` each,
/// so every suggestion's blend has its lobby term. Every simulation of a pass uses the same seed (common random
/// numbers, so boards are compared on the same dice), and a candidate's result depends only on
/// its input, the pass and the seed. So the advice after the first N evaluations is the same on
/// any machine, however fast: a bookmark records N and replays to the same advice.
public struct AdvisorPlan: Codable, Hashable, Sendable {
    public var seed: UInt32
    /// Per candidate, in stages 0 and 1.
    public var simulations: Int
    /// Added for the best groups and the baseline in the refine pass; 0 skips it.
    public var refineSimulations: Int
    public var refinedGroups: Int
    /// Per candidate and lobby opponent in the lobby pass; 0 skips it.
    public var lobbySimulations: Int
    /// How many of the best board changes (with the baseline) the lobby pass scores.
    public var lobbyGroups: Int
    /// Per candidate and lobby opponent in the lobby sweep (every board change the lobby pass
    /// left out); 0 skips it, leaving those without a lobby term.
    public var lobbySweepSimulations: Int
    public var weights: AdvisorWeights

    /// The app's: about 5 s of simulation for a late-game state with the JIT, less early on.
    public static let live = AdvisorPlan(
        seed: 0x19AD_7150, simulations: 300, refineSimulations: 900, refinedGroups: 4, lobbySimulations: 150,
        lobbyGroups: 3, lobbySweepSimulations: 30
    )

    public init(
        seed: UInt32, simulations: Int, refineSimulations: Int, refinedGroups: Int, lobbySimulations: Int = 0,
        lobbyGroups: Int = 3, lobbySweepSimulations: Int = 0, weights: AdvisorWeights = .standard
    ) {
        self.seed = seed
        self.simulations = simulations
        self.refineSimulations = refineSimulations
        self.refinedGroups = refinedGroups
        self.lobbySimulations = lobbySimulations
        self.lobbyGroups = lobbyGroups
        self.lobbySweepSimulations = lobbySweepSimulations
        self.weights = weights
    }

    private enum CodingKeys: String, CodingKey {
        case seed, simulations, refineSimulations, refinedGroups, lobbySimulations, lobbyGroups, lobbySweepSimulations
        case weights
    }

    /// A plan saved before the lobby pass (or its sweep) existed had none.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seed = try c.decode(UInt32.self, forKey: .seed)
        simulations = try c.decode(Int.self, forKey: .simulations)
        refineSimulations = try c.decode(Int.self, forKey: .refineSimulations)
        refinedGroups = try c.decode(Int.self, forKey: .refinedGroups)
        lobbySimulations = try c.decodeIfPresent(Int.self, forKey: .lobbySimulations) ?? 0
        lobbyGroups = try c.decodeIfPresent(Int.self, forKey: .lobbyGroups) ?? 3
        lobbySweepSimulations = try c.decodeIfPresent(Int.self, forKey: .lobbySweepSimulations) ?? 0
        weights = try c.decodeIfPresent(AdvisorWeights.self, forKey: .weights) ?? .standard
    }

    /// The same plan scored with other weights.
    public func with(weights: AdvisorWeights) -> AdvisorPlan {
        var plan = self
        plan.weights = weights
        return plan
    }

    /// The budget of one candidate's pass: all its simulations, with no time limit that could cut
    /// it short (which would make the result depend on the machine). The runner's time budget
    /// stops between evaluations instead.
    func budget(_ simulations: Int) -> SimulationBudget {
        SimulationBudget(simulations: simulations, maxDurationMilliseconds: 600_000, intermediateResults: 50)
    }

    func seed(pass: Int) -> UInt32 { seed &+ UInt32(pass) &* 0x9E37_79B9 }
}

/// Scores an `AdvisorRequest`'s candidates by simulating each one's next combat, in the plan's
/// deterministic order, and ranks them after every evaluation.
public enum AdvisorEvaluation {
    /// Simulates one candidate's combat: its input, how many simulations, the pass's seed.
    public typealias Simulate = @Sendable (BattleInput, SimulationBudget, UInt32) async throws -> CombatOdds

    public struct Progress: Sendable {
        public var advice: Advice
        /// Evaluations (simulations of one candidate in one pass) done so far.
        public var evaluations: Int
        /// Every pass has finished.
        public var isComplete: Bool
    }

    /// Runs the plan, calling `report` with the ranked advice after every evaluation (and once
    /// at the start). Stops after `limit` evaluations when given (a replay of a bookmark), or when
    /// `shouldContinue` says so between evaluations (the runner's time budget). Cancelling the
    /// task throws `CancellationError`; the evaluation in progress then doesn't count.
    @discardableResult
    public static func run(
        _ request: AdvisorRequest, plan: AdvisorPlan, limit: Int? = nil,
        shouldContinue: @Sendable () -> Bool = { true }, simulate: Simulate,
        isolation: isolated (any Actor)? = #isolation, report: (Progress) -> Void = { _ in }
    ) async throws -> Progress {
        guard let base = request.preview.input else {
            let done = Progress(advice: .noData, evaluations: 0, isComplete: true)
            report(done)
            return done
        }
        var candidates = Advisor.initialCandidates(for: request)
        var tallies: [String: CombatTally] = [:]
        var lobby: [String: [Int: CombatTally]] = [:]
        var evaluations = 0
        func advice(complete: Bool) -> Advice {
            Advisor.rank(
                request, candidates: candidates, tallies: tallies, lobby: lobby, weights: plan.weights, isComplete: complete
            )
        }
        func mayGoOn() -> Bool { (limit.map { evaluations < $0 } ?? true) && shouldContinue() }
        func stopped() -> Progress { Progress(advice: advice(complete: false), evaluations: evaluations, isComplete: false) }

        report(Progress(advice: advice(complete: false), evaluations: 0, isComplete: false))
        func score(_ list: [AdvisorCandidate], pass: Int, simulations: Int) async throws -> Bool {
            for candidate in list where candidate.isSimulated {
                guard mayGoOn() else { return false }
                try Task.checkCancellation()
                let odds = try await simulate(candidate.input ?? base, plan.budget(simulations), plan.seed(pass: pass))
                try Task.checkCancellation()
                tallies[candidate.id, default: CombatTally()].add(odds)
                evaluations += 1
                report(Progress(advice: advice(complete: false), evaluations: evaluations, isComplete: false))
            }
            return true
        }

        guard try await score(candidates, pass: 0, simulations: plan.simulations) else { return stopped() }
        let refinements = Advisor.refinements(
            for: request, bestFirst: Advisor.groupsByValue(request, candidates, tallies: tallies, weights: plan.weights)
        )
        candidates += refinements
        guard try await score(refinements, pass: 1, simulations: plan.simulations) else { return stopped() }
        let keep = candidates.filter { $0.action == .keep }
        if plan.refineSimulations > 0 {
            let best = Advisor.bestCandidates(request, candidates, tallies: tallies, weights: plan.weights)
                .filter { !$0.isForNextTurn }
                .prefix(plan.refinedGroups)
            guard try await score(keep + best, pass: 2, simulations: plan.refineSimulations) else { return stopped() }
        }
        // The lobby pass: the baseline and the best board changes against every other opponent
        // seen; then the sweep: every other group's best, fewer simulations each, best first (so
        // the time budget cuts the least likely first).
        let opponents = Advisor.lobbyOpponents(for: request)
        func scoreLobby(_ list: [AdvisorCandidate], pass: Int, simulations: Int) async throws -> Bool {
            for candidate in list {
                for opponent in opponents {
                    guard mayGoOn() else { return false }
                    try Task.checkCancellation()
                    let input = request.input(candidate.input ?? base, against: opponent)
                    let odds = try await simulate(input, plan.budget(simulations), plan.seed(pass: pass))
                    try Task.checkCancellation()
                    lobby[candidate.id, default: [:]][opponent.playerID, default: CombatTally()].add(odds)
                    evaluations += 1
                    report(Progress(advice: advice(complete: false), evaluations: evaluations, isComplete: false))
                }
            }
            return true
        }
        if plan.lobbySimulations > 0, !opponents.isEmpty {
            let ranked = Advisor.bestCandidates(request, candidates, tallies: tallies, weights: plan.weights)
            let best = Array(ranked.filter { !$0.isForNextTurn }.prefix(plan.lobbyGroups))
            guard try await scoreLobby(keep + best, pass: 3, simulations: plan.lobbySimulations) else { return stopped() }
            if plan.lobbySweepSimulations > 0 {
                let done = Set(best.map(\.id))
                let rest = ranked.filter { !done.contains($0.id) }
                guard try await scoreLobby(rest, pass: 4, simulations: plan.lobbySweepSimulations) else { return stopped() }
            }
        }
        let done = Progress(advice: advice(complete: true), evaluations: evaluations, isComplete: true)
        report(done)
        return done
    }

    /// Scores on a simulator (seeded, so reproducible).
    public static func simulate(on simulator: @escaping @Sendable () async throws -> CombatSimulator) -> Simulate {
        { input, budget, seed in try await simulator().simulate(input, budget: budget, seed: seed) }
    }
}

extension CombatTally {
    mutating func add(_ odds: CombatOdds) {
        add(
            simulations: odds.simulations, won: odds.won, tied: odds.tied, lost: odds.lost, wonLethal: odds.wonLethal,
            lostLethal: odds.lostLethal, averageDamageWon: odds.averageDamageWon, averageDamageLost: odds.averageDamageLost
        )
    }
}

/// What the advisor panel shows for the recruit phase on screen, and what a bookmark keeps of it.
public struct AdviceView: Codable, Hashable, Sendable {
    /// `AdvisorRequest.id`: one per game, BG turn and next opponent.
    public var requestID: String
    public var bgTurn: Int
    public var opponentPlayerID: Int
    /// Identifies the exact state the advice is for (a hash of the request), so a replay can check
    /// it reached the same one.
    public var fingerprint: String
    public var advice: Advice
    /// The state changed since; new advice is on its way.
    public var isUpdating = false
    /// Set when scoring failed.
    public var failure: String?
    /// The plan it was scored with and how far it got: replaying `evaluations` of `plan` on the
    /// same request gives the same `advice`.
    public var plan: AdvisorPlan
    public var evaluations: Int
    /// Every pass finished (not cut short by the time budget).
    public var isComplete: Bool

    public init(request: AdvisorRequest, plan: AdvisorPlan, advice: Advice, evaluations: Int = 0, isComplete: Bool = false) {
        requestID = request.id
        bgTurn = request.preview.bgTurn
        opponentPlayerID = request.preview.opponentPlayerID
        fingerprint = Self.fingerprint(of: request)
        self.advice = advice
        self.plan = plan
        self.evaluations = evaluations
        self.isComplete = isComplete
    }

    /// Whether this is for the recruit phase on screen and its next opponent.
    public func isFor(_ game: GameView) -> Bool {
        game.phase == .recruit && game.bgTurn == bgTurn && game.nextOpponentPlayerID == opponentPlayerID
    }

    /// FNV-1a (64-bit) of the request's sorted-keys JSON: stable across processes and runs.
    public static func fingerprint(of request: AdvisorRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(request)) ?? Data()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// Scores `request` exactly as far as this advice was scored and returns the result, which
    /// equals this one when the request is the same state (`fingerprint`).
    public func replaying(
        _ request: AdvisorRequest, simulate: AdvisorEvaluation.Simulate
    ) async throws -> AdviceView {
        let progress = try await AdvisorEvaluation.run(request, plan: plan, limit: evaluations, simulate: simulate)
        return AdviceView(
            request: request, plan: plan, advice: progress.advice, evaluations: progress.evaluations,
            isComplete: progress.isComplete
        )
    }
}

/// Runs the advisor during recruit: for the latest state only, debounced, refined in place, within
/// a time budget per state.
///
/// Give it each new `AdvisorRequest` (`TavernEngine.advisorRequest`) as the state changes. A
/// changed state waits `debounce` for things to settle, cancels the scoring in progress, and scores
/// the new one progressively (`AdvisorEvaluation`), publishing the ranked advice at most once per
/// `refreshInterval`; it stops when the plan is done or `timeBudget` is spent. The previous
/// advice stays up, marked updating, until the new state has its first ranking. Nil (not recruit)
/// clears it.
///
/// It shares the simulator's one JavaScript thread with the combat-start odds and the preview.
/// Each evaluation is a few hundred simulations, so they get their turn between evaluations; call
/// `cancel()` when a combat starts, and the evaluation in progress stops at its next step.
@MainActor
public final class AdvisorRunner {
    public private(set) var current: AdviceView? {
        didSet { if current != oldValue { onChange?(current) } }
    }
    public var onChange: ((AdviceView?) -> Void)?
    /// The state `current` is advice for (the older one while `current.isUpdating`): what a
    /// bookmark keeps, so the case can be re-scored without the log (`AdvisorTuning`).
    public private(set) var currentRequest: AdvisorRequest?

    public let plan: AdvisorPlan
    public let debounce: Duration
    public let timeBudget: Duration
    public let refreshInterval: Duration

    private let simulate: AdvisorEvaluation.Simulate
    private var latest: AdvisorRequest?
    private let runner: LatestRunner<(progress: AdvisorEvaluation.Progress, request: AdvisorRequest)>

    /// - Parameters:
    ///   - simulator: the simulator, ready (card DB loaded); awaited for each evaluation.
    ///   - timeBudget: how long one state may be scored for; the plan stops between evaluations then.
    public convenience init(
        simulator: @escaping @Sendable () async throws -> CombatSimulator, plan: AdvisorPlan = .live,
        debounce: Duration = .milliseconds(300), timeBudget: Duration = .seconds(6),
        refreshInterval: Duration = .milliseconds(150)
    ) {
        self.init(
            simulate: AdvisorEvaluation.simulate(on: simulator), plan: plan, debounce: debounce,
            timeBudget: timeBudget, refreshInterval: refreshInterval
        )
    }

    /// Scores with `simulate` (any scorer, such as a stub in tests).
    public init(
        simulate: @escaping AdvisorEvaluation.Simulate, plan: AdvisorPlan = .live,
        debounce: Duration = .milliseconds(300), timeBudget: Duration = .seconds(6),
        refreshInterval: Duration = .milliseconds(150)
    ) {
        self.simulate = simulate
        self.plan = plan
        self.debounce = debounce
        self.timeBudget = timeBudget
        self.refreshInterval = refreshInterval
        // Keep the previous state's advice up until this one has a ranking.
        runner = LatestRunner(debounce: debounce, refreshInterval: refreshInterval) { $0.progress.advice.status != .thinking }
        runner.onResult = { [weak self] result, _ in self?.receive(result.progress, for: result.request) }
        runner.onFailure = { [weak self] error in self?.fail(error) }
    }

    /// The advisor's state as of now; nil outside recruit.
    public func update(_ request: AdvisorRequest?) {
        guard let request else {
            cancel()
            return
        }
        if request == latest { return }
        latest = request
        guard request.hasData else {
            runner.stop()
            currentRequest = request
            current = AdviceView(request: request, plan: plan, advice: .noData, isComplete: true)
            return
        }
        var replacing = false
        if var view = current, view.requestID == request.id {
            view.isUpdating = true
            current = view
            replacing = true
        } else {
            currentRequest = request
            current = AdviceView(request: request, plan: plan, advice: Advice(status: .thinking))
        }
        let plan = self.plan, simulate = self.simulate, timeBudget = self.timeBudget
        runner.submit(replacing: replacing) { emit in
            let deadline = ContinuousClock.now + timeBudget
            let done = try await AdvisorEvaluation.run(
                request, plan: plan, shouldContinue: { ContinuousClock.now < deadline }, simulate: simulate
            ) { progress in
                emit.onMain((progress, request))
            }
            return (done, request)
        }
    }

    /// Stops scoring and clears the advice (a combat is starting, or recruit ended).
    public func cancel() {
        runner.stop()
        latest = nil
        currentRequest = nil
        current = nil
    }

    private func receive(_ progress: AdvisorEvaluation.Progress, for request: AdvisorRequest) {
        currentRequest = request
        current = AdviceView(
            request: request, plan: plan, advice: progress.advice, evaluations: progress.evaluations,
            isComplete: progress.isComplete
        )
    }

    private func fail(_ error: any Error) {
        guard var view = current else { return }
        view.failure = "\(error)"
        view.isUpdating = false
        current = view
    }
}
