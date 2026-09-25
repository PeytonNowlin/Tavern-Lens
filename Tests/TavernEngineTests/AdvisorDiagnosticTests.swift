import Foundation
import Testing
import TavernEngine

@Suite("Automatic advisor evidence")
struct AdvisorDiagnosticTests {
    func record(turn: Int = 11) throws -> AdvisorTurnDiagnostic {
        var request = try RecruitPlannerTests.request(shop: [AdvisorSynthetic.shopMinion(1, attack: 4, health: 4, cardID: "body")])
        request.preview.bgTurn = turn
        let displayed = AdviceView(request: request, plan: .live,
                                   advice: Advice(status: .noStrongRecommendation, note: "Incomplete"), evaluations: 3)
        let combat = CombatSimulationRequest(gameSeed: 1, bgTurn: turn, opponentPlayerID: 7,
                                             position: .init(line: 100, time: "12:00:00.0000000"), input: request.recruit!.input)
        return AdvisorTurnDiagnostic(combat: combat, request: request, displayed: displayed)
    }

    @Test("Atomic archive preserves the exact request, incomplete advice, and version")
    func roundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AdvisorDiagnosticStore(directory: dir)
        var evidence = try record()
        evidence.failure = "Simulation unavailable"
        try await store.save(evidence)
        let loaded = try await store.load(gameSeed: 1, turn: 11)
        #expect(loaded == evidence)
        #expect(loaded.displayed?.plan.version == 2)
        #expect(loaded.displayed?.isComplete == false)
        #expect(AdvisorCase.savedDiagnostics(in: dir).first?.request == loaded.request)
    }

    @Test("An unrelated game's advice is not attributed to this combat")
    func mismatchedEvidence() throws {
        let evidence = try record()
        var other = evidence.combat; other.gameSeed = 2
        let result = AdvisorTurnDiagnostic(combat: other, request: evidence.request, displayed: evidence.displayed)
        #expect(result.request == nil && result.displayed == nil)
    }

    @Test("Retention is bounded and leaves unrelated files untouched")
    func retention() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let unrelated = dir.appending(path: "notes.json")
        try Data("keep me".utf8).write(to: unrelated)
        let store = AdvisorDiagnosticStore(directory: dir, maximumRecords: 1)
        try await store.save(record(turn: 10))
        try await store.save(record(turn: 11))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains("notes.json"))
        #expect(files.filter { $0.hasPrefix("game-") }.count == 1)
        #expect(try await store.load(gameSeed: 1, turn: 11).bgTurn == 11)
    }

    @Test("Oversized evidence fails explicitly rather than silently dropping the write")
    func tooLarge() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AdvisorDiagnosticStore(directory: dir, maximumBytes: 1)
        await #expect(throws: (any Error).self) { try await store.save(record()) }
    }
    @Test("Version-1 fingerprints exclude planner metadata when an old bookmark is reconstructed")
    func legacyFingerprint() throws {
        let request = try RecruitPlannerTests.request(shop: [AdvisorSynthetic.shopMinion(1, attack: 4, health: 4, cardID: "body")])
        var old = request; old.recruit = nil
        #expect(AdviceView.fingerprint(of: request, version: 1) == AdviceView.fingerprint(of: old, version: 1))
        #expect(AdviceView.fingerprint(of: request, version: 2) != AdviceView.fingerprint(of: old, version: 2))
    }

}
