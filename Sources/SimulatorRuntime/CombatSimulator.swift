import Foundation
import JavaScriptCore

/// The result of a simulation so far (or final), as percentages and damage.
public struct CombatOdds: Codable, Hashable, Sendable {
    public struct DamageRange: Codable, Hashable, Sendable {
        public var min: Int
        public var max: Int

        public init(min: Int, max: Int) {
            self.min = min
            self.max = max
        }
    }

    /// Percent of simulations won, tied and lost (they add up to 100).
    public var won: Double
    public var tied: Double
    public var lost: Double
    /// Percent of simulations where the damage dealt kills the opponent, or the damage taken kills us.
    public var wonLethal: Double
    public var lostLethal: Double
    /// Average damage to the loser's hero, over the simulations won (dealt) or lost (taken).
    public var averageDamageWon: Double
    public var averageDamageLost: Double
    /// The simulator's 90% range of that damage; nil when no simulation was won (or lost).
    public var damageWonRange: DamageRange?
    public var damageLostRange: DamageRange?
    public var simulations: Int
    /// Since the simulation started.
    public var elapsedMilliseconds: Int
    /// The last result: the budget was spent or every simulation ran.
    public var isFinal: Bool

    public init(
        won: Double, tied: Double, lost: Double, wonLethal: Double = 0, lostLethal: Double = 0,
        averageDamageWon: Double = 0, averageDamageLost: Double = 0, damageWonRange: DamageRange? = nil,
        damageLostRange: DamageRange? = nil, simulations: Int, elapsedMilliseconds: Int = 0, isFinal: Bool
    ) {
        self.won = won
        self.tied = tied
        self.lost = lost
        self.wonLethal = wonLethal
        self.lostLethal = lostLethal
        self.averageDamageWon = averageDamageWon
        self.averageDamageLost = averageDamageLost
        self.damageWonRange = damageWonRange
        self.damageLostRange = damageLostRange
        self.simulations = simulations
        self.elapsedMilliseconds = elapsedMilliseconds
        self.isFinal = isFinal
    }
}

/// How much work one simulation may do. The simulator yields a partial result every
/// `intermediateResults` simulations; the first yield is what the overlay shows first.
public struct SimulationBudget: Codable, Hashable, Sendable {
    public var simulations: Int
    /// A hard stop, in milliseconds (the simulator checks it after every simulation).
    public var maxDurationMilliseconds: Int
    public var intermediateResults: Int

    /// 8000 simulations within 2 s, refined every 50 (mapping §5.1, §8.1: a late 7v7 board
    /// runs about 8000 in 1.5 s).
    public static let standard = SimulationBudget(simulations: 8000, maxDurationMilliseconds: 2000, intermediateResults: 50)

    public init(simulations: Int, maxDurationMilliseconds: Int, intermediateResults: Int) {
        self.simulations = simulations
        self.maxDurationMilliseconds = maxDurationMilliseconds
        self.intermediateResults = intermediateResults
    }
}

public enum CombatSimulatorError: Error, Equatable, CustomStringConvertible {
    /// The script threw; the message is JavaScript's.
    case javaScript(String)
    case cardsNotLoaded
    case badResult(String)

    public var description: String {
        switch self {
        case .javaScript(let message): "Simulator error: \(message)"
        case .cardsNotLoaded: "The simulator's card data isn't loaded"
        case .badResult(let text): "Unexpected simulator result: \(text.prefix(200))"
        }
    }
}

/// Firestone's Battlegrounds combat simulator in its own JavaScriptCore VM and context.
///
/// All JavaScript runs on one serial background queue (shared by every simulator in the process),
/// one simulation at a time; the card DB
/// is loaded once and kept. A simulation runs in steps of `intermediateResults` simulations
/// and reports each step, so results refine in place; cancelling the task stops it at the next step.
///
/// JavaScriptCore only JITs in a process signed with `com.apple.security.cs.allow-jit`
/// (Packaging/TavernLens.entitlements); without it, as under `swift test`, it interprets and
/// runs several times slower (a late board: about 8000 simulations in 1.7 s with the JIT, 12 s without).
public final class CombatSimulator: @unchecked Sendable {
    /// One queue for every simulator in the process: JavaScriptCore crashed (in its allocator)
    /// with several VMs evaluating the bundle at once on different threads, so JavaScript runs
    /// on one thread at a time. The app has a single simulator anyway.
    private static let sharedQueue = DispatchQueue(label: "TavernLens.CombatSimulator", qos: .userInitiated)
    private var queue: DispatchQueue { Self.sharedQueue }
    // Confined to `queue`.
    private let virtualMachine: JSVirtualMachine
    private let context: JSContext
    private var api: JSValue
    private var warnings: [String] = []
    private var cardCount = 0

    /// Evaluates the bundled simulator script (by default the pinned bundle).
    public init(script: String? = nil) throws {
        let source = try script ?? SimulatorResources.script()
        (virtualMachine, context, api) = Self.sharedQueue.sync {
            let virtualMachine = JSVirtualMachine()!
            let context = JSContext(virtualMachine: virtualMachine)!
            context.name = "Tavern Lens combat simulator"
            return (virtualMachine, context, JSValue(undefinedIn: context))
        }
        var failure: CombatSimulatorError?
        queue.sync {
            installConsole()
            context.evaluateScript(source, withSourceURL: URL(string: "bgs-simulator.js"))
            if let error = takeException() {
                failure = error
                return
            }
            api = context.objectForKeyedSubscript("TavernSim")
            if api.isUndefined { failure = .javaScript("TavernSim is not defined") }
        }
        if let failure { throw failure }
    }

    deinit {
        // The VM is torn down on the JavaScript queue too, never alongside another VM's work.
        let retained = Retained(virtualMachine: virtualMachine, context: context, api: api)
        Self.sharedQueue.async { withExtendedLifetime(retained) {} }
    }

    private struct Retained: @unchecked Sendable {
        var virtualMachine: JSVirtualMachine
        var context: JSContext
        var api: JSValue
    }

    /// The versions the loaded script reports.
    public var versions: [String: String] {
        queue.sync { (api.objectForKeyedSubscript("versions").toDictionary() as? [String: String]) ?? [:] }
    }

    /// Warnings and errors the simulator logged (the latest 50).
    public var loggedWarnings: [String] { queue.sync { warnings } }

    /// Loads Firestone's card DB (a JSON array). Returns the number of cards.
    @discardableResult
    public func loadCards(json: Data) throws -> Int {
        let text = String(decoding: json, as: UTF8.self)
        return try queue.sync {
            let count = api.invokeMethod("loadCards", withArguments: [text])
            if let error = takeException() { throw error }
            cardCount = Int(count?.toInt32() ?? 0)
            return cardCount
        }
    }

    /// Loads the card DB pinned with the simulator.
    @discardableResult
    public func loadPinnedCards() throws -> Int {
        try loadCards(json: SimulatorResources.cardsJSON())
    }

    public var isReady: Bool { queue.sync { cardCount > 0 } }

    /// Runs one simulation of `input` (a `BgsBattleInfo` as JSON), reporting each partial result.
    /// Returns the final result; throws `CancellationError` if the task was cancelled first.
    public func simulate(
        input: Data, budget: SimulationBudget = .standard, progress: @escaping @Sendable (CombatOdds) -> Void = { _ in }
    ) async throws -> CombatOdds {
        let cancelled = CancelFlag()
        let inputText = String(decoding: input, as: UTF8.self)
        let options = """
            {"numberOfSimulations":\(budget.simulations),"maxAcceptableDuration":\(budget.maxDurationMilliseconds),\
            "intermediateResults":\(budget.intermediateResults)}
            """
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CombatOdds, any Error>) in
                queue.async { [self] in
                    continuation.resume(with: Result {
                        try run(input: inputText, options: options, cancelled: cancelled, progress: progress)
                    })
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    /// Call on `queue`.
    private func run(
        input: String, options: String, cancelled: CancelFlag, progress: @Sendable (CombatOdds) -> Void
    ) throws -> CombatOdds {
        guard cardCount > 0 else { throw CombatSimulatorError.cardsNotLoaded }
        if cancelled.isSet { throw CancellationError() }
        let handle = api.invokeMethod("start", withArguments: [input, options])
        if let error = takeException() { throw error }
        guard let handle else { throw CombatSimulatorError.badResult("no handle") }
        while true {
            if cancelled.isSet {
                api.invokeMethod("cancel", withArguments: [handle])
                _ = takeException()
                throw CancellationError()
            }
            let step = api.invokeMethod("step", withArguments: [handle])
            if let error = takeException() {
                api.invokeMethod("cancel", withArguments: [handle])
                throw error
            }
            let odds = try Self.decode(step?.toString() ?? "")
            if odds.isFinal { return odds }
            progress(odds)
        }
    }

    private struct Step: Decodable {
        var done: Bool
        var simulations: Int
        var elapsedMs: Int?
        var won, tied, lost, wonLethal, lostLethal: Double?
        var averageDamageWon, averageDamageLost: Double?
        var damageWonRange, damageLostRange: CombatOdds.DamageRange?
    }

    static func decode(_ text: String) throws -> CombatOdds {
        guard let step = try? JSONDecoder().decode(Step.self, from: Data(text.utf8)) else {
            throw CombatSimulatorError.badResult(text)
        }
        return CombatOdds(
            won: step.won ?? 0, tied: step.tied ?? 0, lost: step.lost ?? 0,
            wonLethal: step.wonLethal ?? 0, lostLethal: step.lostLethal ?? 0,
            averageDamageWon: step.averageDamageWon ?? 0, averageDamageLost: step.averageDamageLost ?? 0,
            damageWonRange: step.damageWonRange, damageLostRange: step.damageLostRange,
            simulations: step.simulations, elapsedMilliseconds: step.elapsedMs ?? 0, isFinal: step.done
        )
    }

    // MARK: - Context plumbing (on `queue`)

    private func takeException() -> CombatSimulatorError? {
        guard let exception = context.exception else { return nil }
        context.exception = nil
        let stack = exception.objectForKeyedSubscript("stack")?.toString() ?? ""
        return .javaScript([exception.toString() ?? "unknown", stack].filter { !$0.isEmpty && $0 != "undefined" }
            .joined(separator: "\n"))
    }

    /// A `console` whose warnings and errors are kept (the simulator warns about unknown cards).
    private func installConsole() {
        let record: @convention(block) () -> Void = { [weak self] in
            guard let self else { return }
            let parts = (JSContext.currentArguments() as? [JSValue] ?? []).map { $0.toString() ?? "" }
            self.warnings.append(parts.joined(separator: " "))
            if self.warnings.count > 50 { self.warnings.removeFirst(self.warnings.count - 50) }
        }
        let ignore: @convention(block) () -> Void = {}
        let console = JSValue(newObjectIn: context)!
        for name in ["log", "info", "debug", "time", "timeEnd"] {
            console.setObject(ignore, forKeyedSubscript: name as NSString)
        }
        for name in ["warn", "error"] {
            console.setObject(record, forKeyedSubscript: name as NSString)
        }
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }
}

/// Set once from any thread; read on the simulator's queue between steps.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

extension CombatSimulator {
    /// A mirror match of seven 4/8 minions, for checking that the simulator runs (and how fast)
    /// where no real combat is at hand: `TavernLens --simulator-benchmark`.
    public static let benchmarkInput: Data = {
        func minion(_ id: Int) -> String {
            #"{"entityId":\#(id),"cardId":"BG36_102","attack":4,"health":8,"maxHealth":8,"enchantments":[]}"#
        }
        func side(hero: Int, first: Int) -> String {
            #"{"player":{"cardId":"TB_BaconShop_HERO_15","entityId":\#(hero),"hpLeft":30,"tavernTier":5,"heroPowers":[],"#
                + #""questEntities":[],"hand":[],"secrets":[],"trinkets":[],"globalInfo":{}},"board":["#
                + (0..<7).map { minion(first + $0) }.joined(separator: ",") + "]}"
        }
        let input = #"{"playerBoard":\#(side(hero: 1, first: 10)),"opponentBoard":\#(side(hero: 2, first: 20)),"#
            + #""options":{"numberOfSimulations":8000,"skipInfoLogs":true,"includeOutcomeSamples":false},"#
            + #""gameState":{"currentTurn":10,"anomalies":[]}}"#
        return Data(input.utf8)
    }()
}
