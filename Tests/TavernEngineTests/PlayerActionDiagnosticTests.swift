import Foundation
import Testing
import TavernEngine
import PowerParser

@Suite("Local player action evidence")
struct PlayerActionDiagnosticTests {
    static func record(line: Int = 100) throws -> PlayerActionDiagnostic {
        let request = try RecruitPlannerTests.request(gold: 3)
        let sent = SentOption(timestamp: "16:42:51.2485580", optionsID: 1, selectedOption: 8,
                              selectedSubOption: -1, selectedTarget: 435, selectedPosition: 0)
        return PlayerActionDiagnostic(request: request, selection: .option(sent),
            position: .init(line: line, time: sent.timestamp), capturedAt: Date(timeIntervalSince1970: 100))
    }

    @Test("Atomic local archive and offline export retain the pre-action request without account names")
    func roundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let request = try RecruitPlannerTests.request(gold: 3)
        let sent = SentChoices(timestamp: "16:45:29.8624760", id: 3, choiceType: "GENERAL",
                               chosen: [ActionEntity(entityID: 1711, cardID: "BG36_201")])
        let offered = EntityChoice(id: 3, choiceType: "GENERAL", source: .playerName("Private#1234"),
                                   options: [ChoiceOption(entityID: 1711, cardID: "BG36_201")])
        let record = PlayerActionDiagnostic(request: request, selection: .choices(sent),
            position: .init(line: 100, time: sent.timestamp), choice: offered,
            capturedAt: Date(timeIntervalSince1970: 100))
        let store = PlayerActionDiagnosticStore(directory: dir)
        try await store.save(record)
        #expect(try await store.load(gameSeed: 1, turn: request.preview.bgTurn, line: 100) == record)
        #expect(try await store.records(gameSeed: 1).count == 1)
        let export = try await store.export(gameSeed: 1)
        let text = String(decoding: export, as: UTF8.self)
        #expect(text.split(separator: "\n").count == 1)
        #expect(!text.contains("Private#1234") && !text.contains("GameAccountId") && !text.contains("entityName"))
        let decoded = try JSONDecoder().decode(PlayerActionDiagnostic.self, from: export)
        #expect(decoded.request.gold == 3 && decoded.choice?.source == nil)
        #expect(decoded.displayedAdvice == nil)
    }

    @Test("Retention keeps the latest action within its record bound and leaves unrelated files alone")
    func countBound() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let unrelated = dir.appending(path: "action-not-an-archive.json")
        try Data("keep me".utf8).write(to: unrelated)
        let store = PlayerActionDiagnosticStore(directory: dir, maximumRecords: 1)
        try await store.save(Self.record(line: 100))
        let latest = try Self.record(line: 101)
        try await store.save(latest)
        #expect(try await store.records() == [latest])
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("Byte retention removes an older action even when the count bound permits both")
    func byteBound() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try Self.record(line: 100), second = try Self.record(line: 101)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let budget = try encoder.encode(first).count + encoder.encode(second).count - 1
        let store = PlayerActionDiagnosticStore(directory: dir, maximumRecords: 20, maximumBytes: budget)
        try await store.save(first); try await store.save(second)
        #expect(try await store.records() == [second])
    }

    @Test("An oversized replacement fails before altering the existing complete atomic record")
    func oversizedReplacement() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = try Self.record()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let store = PlayerActionDiagnosticStore(directory: dir, maximumBytes: try encoder.encode(original).count + 64)
        try await store.save(original)
        var request = original.request
        let definitions = Array(repeating: try #require(request.recruit?.definitions.values.first), count: 200)
        request.recruit?.definitions = Dictionary(uniqueKeysWithValues: definitions.enumerated().map { ("extra\($0.offset)", $0.element) })
        let oversized = PlayerActionDiagnostic(request: request, selection: original.selection, position: original.position,
                                              capturedAt: original.capturedAt)
        await #expect(throws: PlayerActionDiagnosticError.recordTooLarge) { try await store.save(oversized) }
        #expect(try await store.load(gameSeed: 1, turn: original.bgTurn, line: 100) == original)
        #expect(try await store.records().count == 1)
    }

    @Test("Advice association requires a dated outgoing action and preceding matching displayed advice")
    func adviceAssociation() throws {
        let original = try Self.record(), request = original.request
        let displayed = AdviceView(request: request, plan: .live, advice: .noData)
        let captured = Date(timeIntervalSince1970: 100), action = Date(timeIntervalSince1970: 90)
        let preceding = Date(timeIntervalSince1970: 80), afterAction = Date(timeIntervalSince1970: 95)
        func evidence(actionAt: Date? = action, displayedAt: Date? = preceding, view: AdviceView = displayed) -> PlayerActionDiagnostic {
            PlayerActionDiagnostic(request: request, selection: original.selection, position: original.position,
                capturedAt: captured, actionAt: actionAt, displayed: view, displayedAt: displayedAt)
        }
        #expect(evidence().displayedAdvice?.fingerprint == displayed.fingerprint)
        #expect(evidence(actionAt: nil).displayedAdvice == nil)
        #expect(evidence(displayedAt: nil).displayedAdvice == nil)
        #expect(evidence(displayedAt: afterAction).displayedAdvice == nil)
        var other = request; other.gold += 1
        #expect(evidence(view: AdviceView(request: other, plan: .live, advice: .noData)).displayedAdvice == nil)
    }

    @Test("An unrelated offered group is excluded while the selection remains usable")
    func unrelatedOffer() throws {
        let original = try Self.record()
        let evidence = PlayerActionDiagnostic(request: original.request, selection: original.selection,
            position: original.position, options: PowerOptions(id: 999, timestamp: "16:42:48.1795170"))
        #expect(evidence.options == nil && evidence.selection == original.selection)
    }
}
