import CryptoKit
import Dispatch
import Foundation
import Testing
import TavernEngine

@Suite("Opt-in recruit planner benchmark", .serialized)
struct AdvisorPerformanceTests {
    static let environment = ProcessInfo.processInfo.environment

    struct BenchmarkCase {
        var fixture: String?
        var request: AdvisorRequest
        var policy: Int
        var id: String
    }

    struct Timing: Encodable {
        var firstSearchMS: Double
        var warmSamplesMS: [Double]
        var warmMedianMS: Double
        var warmP95MS: Double
    }

    struct Row: Encodable {
        var caseID: String
        var policy: Int
        var expanded: Int
        var retainedPlans: Int
        var behaviorSHA256: String
        var timing: Timing
    }

    struct Report: Encodable {
        var schemaVersion = 1
        var timingScope = "Search only. First search is the first invocation for this case in this process; shared caches are not reset. Warm samples reuse the same request."
        var depth: Int
        var width: Int
        var maximumExpansions: Int
        var repetitions: Int
        var rows: [Row]
    }

    struct SearchSnapshot: Encodable {
        var baseline: PlanSnapshot
        var plans: [PlanSnapshot]
        var limitations: [String]
        var expanded: Int

        init(_ result: RecruitSearch) {
            baseline = PlanSnapshot(result.baseline)
            plans = result.plans.map(PlanSnapshot.init)
            limitations = result.limitations
            expanded = result.expanded
        }
    }

    struct PlanSnapshot: Encodable {
        var state: StateSnapshot
        var projection: StateSnapshot
        var value: ValueSnapshot
        var id: String

        init(_ plan: RecruitPlan) {
            state = StateSnapshot(plan.state)
            projection = StateSnapshot(plan.projection)
            value = ValueSnapshot(plan.value)
            id = plan.id
        }
    }

    struct ValueSnapshot: Encodable {
        var tempo: Double
        var scaling: Double
        var economy: Double
        var synergy: Double
        var total: Double

        init(_ value: RecruitValue) {
            tempo = value.tempo
            scaling = value.scaling
            economy = value.economy
            synergy = value.synergy
            total = value.total
        }
    }

    struct StateSnapshot: Encodable {
        let state: RecruitState

        struct FieldKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(_ state: RecruitState) {
            self.state = state
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: FieldKey.self)
            for field in Mirror(reflecting: state).children {
                guard let name = field.label else {
                    throw EncodingError.invalidValue(field.value, .init(codingPath: encoder.codingPath,
                        debugDescription: "RecruitState has an unnamed field"))
                }
                let key = FieldKey(stringValue: name)
                guard let value = field.value as? any Encodable else {
                    throw EncodingError.invalidValue(field.value, .init(codingPath: encoder.codingPath + [key],
                        debugDescription: "RecruitState field cannot be encoded"))
                }
                let reflected = Mirror(reflecting: field.value)
                if reflected.displayStyle == .optional && reflected.children.isEmpty { continue }
                if let set = field.value as? Set<Int> {
                    try container.encode(set.sorted(), forKey: key)
                } else {
                    guard reflected.displayStyle != .set else {
                        throw EncodingError.invalidValue(field.value, .init(codingPath: encoder.codingPath + [key],
                            debugDescription: "RecruitState set has no deterministic encoding"))
                    }
                    try value.encode(to: container.superEncoder(forKey: key))
                }
            }
        }
    }

    static func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func digest(_ value: some Encodable) throws -> String {
        SHA256.hash(data: try encoded(value)).map { String(format: "%02x", $0) }.joined()
    }

    static func fields(_ value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    static func validateSnapshotCoverage(_ search: RecruitSearch) {
        let snapshot = SearchSnapshot(search)
        #expect(fields(search) == fields(snapshot))
        #expect(fields(search.baseline) == fields(snapshot.baseline).subtracting(["id"]))
        #expect(fields(search.baseline.value) == fields(snapshot.baseline.value).subtracting(["total"]))
    }

    static func syntheticCases() throws -> [(String, AdvisorRequest)] {
        typealias S = AdvisorSynthetic
        let upgrade = try RecruitPlannerTests.request(
            board: (1...7).map { S.boardMinion($0, "body\($0)", attack: $0, health: $0) },
            shop: [S.shopMinion(20, attack: 30, health: 30, cardID: "upgrade")], gold: 2)

        let dense = try RecruitPlannerTests.request(
            board: (1...7).map { S.boardMinion($0, "body\($0)", attack: 5 + $0, health: 6 + $0) },
            hand: [S.spell(20, "targetBuff", cost: 0), S.spell(21, "allBuff", cost: 0)],
            shop: [S.shopMinion(30, attack: 22, health: 24, cardID: "upgrade"),
                   S.shopMinion(31, attack: 1, health: 1, cardID: "battlecry"),
                   S.spell(32, "targetBuff", cost: 1)], gold: 8,
            texts: ["targetBuff": "Give a minion +4/+5.", "allBuff": "Give your minions +2/+2.",
                    "battlecry": "Battlecry: Give a minion +4/+5."])

        let endOfTurn = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "buffer", attack: 2, health: 2),
                    S.boardMinion(2, "multiplier", attack: 2, health: 2)] +
                   (3...7).map { S.boardMinion($0, "body\($0)", attack: $0, health: $0) },
            hand: [S.spell(20, "allBuff", cost: 0)],
            shop: [S.shopMinion(30, attack: 12, health: 14, cardID: "upgrade")], gold: 5,
            texts: ["buffer": "At the end of your turn, give your other minions +2/+3.",
                    "multiplier": "Your end of turn effects trigger twice.",
                    "allBuff": "Give your minions +2/+2."])

        var triple = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "pair", attack: 3, health: 4),
                    S.boardMinion(2, "pair", attack: 2, health: 3),
                    S.boardMinion(4, "already_G", attack: 8, health: 10, golden: true)],
            shop: [S.shopMinion(3, attack: 2, health: 3, cardID: "pair")], gold: 3)
        var normal = triple.recruit!.definitions["pair"]!
        normal.attack = 2; normal.health = 3; normal.dbfId = 10; normal.battlegroundsPremiumDbfId = 11
        var golden = Card(id: "pair_G", dbfId: 11, name: "Golden pair")
        golden.type = "MINION"; golden.attack = 4; golden.health = 6; golden.battlegroundsNormalDbfId = 10
        triple.recruit!.definitions["pair"] = normal
        triple.recruit!.definitions["pair_G"] = golden

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Golden/Advisor/benchmark-tier-shop.json")
        let tierShop = try JSONDecoder().decode(AdvisorRequest.self, from: Data(contentsOf: fixture))
        return [("full-board-upgrade", upgrade), ("dense-buffs", dense),
                ("end-of-turn", endOfTurn), ("triple", triple), ("tier-shop", tierShop)]
    }

    static func cases() throws -> [BenchmarkCase] {
        var result: [BenchmarkCase] = []
        for (fixture, base) in try syntheticCases() {
            let id = try digest(base)
            for policy in [10, AdvisorPolicy.live.version] {
                var request = base
                request.recruit?.evaluationVersion = policy
                result.append(BenchmarkCase(fixture: fixture, request: request, policy: policy, id: id))
            }
        }
        if let directory = environment["TAVERN_ADVISOR_BENCHMARK_DIAGNOSTICS"] {
            let captured = AdvisorCase.savedDiagnostics(in: URL(fileURLWithPath: directory))
            #expect(!captured.isEmpty, "The configured diagnostic directory must contain valid captured decisions")
            let maximum = Int(environment["TAVERN_ADVISOR_BENCHMARK_MAX_CAPTURED"] ?? "12") ?? 0
            #expect((1...1000).contains(maximum), "Maximum captured requests must be between 1 and 1000")
            guard (1...1000).contains(maximum) else { return result }
            var unique: [String: AdvisorCase] = [:]
            for item in captured where item.request.recruit != nil {
                let id = try digest(item.request)
                if unique[id] == nil { unique[id] = item }
            }
            #expect(!unique.isEmpty, "The configured diagnostic directory must contain recruit requests")
            let identities = unique.keys.sorted()
            let count = min(maximum, identities.count)
            let selected = (0..<count).map { index in
                identities[count == 1 ? 0 : index * (identities.count - 1) / (count - 1)]
            }
            for id in selected {
                let item = unique[id]!
                let versions = Set([item.recorded?.plan.version ?? item.request.policy.version, AdvisorPolicy.live.version])
                for policy in versions.sorted() {
                    var request = item.request
                    request.recruit?.evaluationVersion = policy
                    result.append(BenchmarkCase(request: request, policy: policy, id: id))
                }
            }
        }
        return result.sorted { ($0.id, $0.policy) < ($1.id, $1.policy) }
    }

    static func validateBehavior(_ result: RecruitSearch, fixture: String?) throws {
        switch fixture {
        case "full-board-upgrade":
            let upgrade = try #require(result.plans.first { $0.state.board.contains { $0.cardID == "upgrade" } })
            #expect(upgrade.state.steps.contains { $0.kind == .sell })
            #expect(upgrade.state.board.count == 7)
            #expect(upgrade.state.board.contains { $0.entity.entityId == 7 })
            #expect(upgrade.value.total > result.baseline.value.total)
        case "end-of-turn":
            #expect(result.baseline.state.board[1].entity.attack == 2)
            #expect(result.baseline.projection.board[1].entity.attack == 6)
            #expect(result.baseline.projection.board[1].entity.health == 8)
        case "triple":
            let plan = try #require(result.plans.first { $0.state.board.contains { $0.cardID == "pair_G" } })
            let golden = try #require(plan.state.board.first { $0.cardID == "pair_G" })
            #expect(golden.entity.attack == 5 && golden.entity.health == 7)
            #expect(plan.state.pendingDiscover == 0 && plan.state.terminal)
            #expect(plan.state.limitations.contains("Triple reward is unknown; choose it and replan"))
        default: break
        }
    }

    static func measured(_ item: BenchmarkCase, budget: RecruitPlanner.Budget) throws -> (RecruitSearch, Double) {
        let context = try #require(item.request.recruit)
        let start = DispatchTime.now().uptimeNanoseconds
        let result = RecruitPlanner.search(item.request, context: context, budget: budget)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return (result, elapsed)
    }

    @Test("Search timing and exact ordered behavior signatures",
          .enabled(if: environment["TAVERN_ADVISOR_BENCHMARK"] == "1", "Run scripts/benchmark-advisor.sh"))
    func benchmark() throws {
        let output = try #require(Self.environment["TAVERN_ADVISOR_BENCHMARK_OUTPUT"])
        let repetitions = Int(Self.environment["TAVERN_ADVISOR_BENCHMARK_REPETITIONS"] ?? "5") ?? 0
        #expect((1...100).contains(repetitions), "Repetitions must be between 1 and 100")
        guard (1...100).contains(repetitions) else { return }
        let budget = RecruitPlanner.Budget()
        var rows: [Row] = []
        for item in try Self.cases() {
            let (first, firstMS) = try Self.measured(item, budget: budget)
            Self.validateSnapshotCoverage(first)
            try Self.validateBehavior(first, fixture: item.fixture)
            let signature = try Self.digest(SearchSnapshot(first))
            var samples: [Double] = []
            for _ in 0..<repetitions {
                let (result, milliseconds) = try Self.measured(item, budget: budget)
                #expect(try Self.digest(SearchSnapshot(result)) == signature,
                        "Repeated search must preserve every ordered plan, state, projection, value and limitation")
                samples.append(milliseconds)
            }
            let ordered = samples.sorted()
            let middle = ordered.count / 2
            let median = ordered.count.isMultiple(of: 2) ? (ordered[middle - 1] + ordered[middle]) / 2 : ordered[middle]
            let p95 = ordered[max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)]
            rows.append(Row(caseID: item.id, policy: item.policy, expanded: first.expanded,
                            retainedPlans: first.plans.count, behaviorSHA256: signature,
                            timing: Timing(firstSearchMS: firstMS, warmSamplesMS: samples,
                                           warmMedianMS: median, warmP95MS: p95)))
        }
        let report = Report(depth: budget.depth, width: budget.width, maximumExpansions: budget.expansions,
                            repetitions: repetitions, rows: rows)
        try Self.encoded(report).write(to: URL(fileURLWithPath: output), options: .atomic)
        print("Advisor benchmark wrote \(rows.count) case/policy rows to \(output)")
    }
}
