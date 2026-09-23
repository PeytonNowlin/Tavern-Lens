import Foundation
import Testing
import TavernEngine

/// Seam 1 golden tests: replay a log through `TavernEngine` and compare chosen
/// checkpoints of the emitted timeline, plus the game records, to expected JSON in
/// `Tests/TavernEngineTests/Golden/<name>.json`.
///
/// Record or refresh a golden with `TAVERN_RECORD_GOLDENS=1 scripts/test.sh`, then review
/// the diff. Goldens are committed, so the harness refuses to write or accept JSON
/// that looks like it contains a BattleTag.
enum GoldenHarness {
    /// Picks one timeline entry.
    enum Checkpoint: Hashable, CustomStringConvertible {
        /// The first entry.
        case first
        /// The last entry (the state at end of log).
        case last
        /// The first entry showing this BG turn.
        case firstOfTurn(Int)
        /// The first entry with this status.
        case firstWithStatus(ViewState.Status)
        /// The first entry of this BG turn's phase.
        case startOfPhase(Int, BGPhase)
        /// The last entry of this BG turn's phase, e.g. the state at the end of a recruit phase.
        case endOfPhase(Int, BGPhase)

        var description: String {
            switch self {
            case .first: "first"
            case .last: "last"
            case .firstOfTurn(let n): "turn:\(n)"
            case .firstWithStatus(let s): "status:\(s.rawValue)"
            case .startOfPhase(let n, let phase): "turn:\(n):\(phase.rawValue):start"
            case .endOfPhase(let n, let phase): "turn:\(n):\(phase.rawValue):end"
            }
        }

        func select(from timeline: [TimelineEntry]) -> TimelineEntry? {
            switch self {
            case .first: timeline.first
            case .last: timeline.last
            case .firstOfTurn(let n): timeline.first { $0.state.game?.bgTurn == n }
            case .firstWithStatus(let s): timeline.first { $0.state.status == s }
            case .startOfPhase(let n, let phase): timeline.first { Self.isIn($0, n, phase) }
            case .endOfPhase(let n, let phase): timeline.last { Self.isIn($0, n, phase) }
            }
        }

        private static func isIn(_ entry: TimelineEntry, _ bgTurn: Int, _ phase: BGPhase) -> Bool {
            entry.state.game?.bgTurn == bgTurn && entry.state.game?.phase == phase
        }
    }

    struct Golden: Codable, Equatable {
        var games: [BGGameRecord]
        /// Checkpoint name -> the selected entry, or nil when the checkpoint matched nothing.
        var checkpoints: [String: TimelineEntry?]
    }

    static let goldenDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Golden", directoryHint: .isDirectory)

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["TAVERN_RECORD_GOLDENS"] == "1"
    }

    static func golden(from result: ReplayResult, checkpoints: [Checkpoint]) -> Golden {
        var selected: [String: TimelineEntry?] = [:]
        for checkpoint in checkpoints {
            selected[checkpoint.description] = .some(checkpoint.select(from: result.timeline).map(redacted))
        }
        return Golden(games: result.games, checkpoints: selected)
    }

    /// Opponents' display names are real account names: goldens keep only that one is
    /// known, as `Opp-P<PlayerID>`.
    static func redacted(_ entry: TimelineEntry) -> TimelineEntry {
        var entry = entry
        if var game = entry.state.game {
            for index in game.lobby.indices where game.lobby[index].displayName != nil {
                game.lobby[index].displayName = "Opp-P\(game.lobby[index].playerID)"
            }
            entry.state.game = game
        }
        return entry
    }

    static func encode(_ golden: Golden) throws -> Data {
        try encode(value: golden)
    }

    /// Pretty-printed with sorted keys and a final newline: the committed goldens' format.
    static func encode<T: Encodable>(value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    /// The one record-or-compare step every golden goes through: refuses JSON that looks like it
    /// holds a BattleTag; with `TAVERN_RECORD_GOLDENS=1` writes `value` to `url` and returns nil;
    /// otherwise returns the committed golden (failing when it's missing), and `value`'s JSON for
    /// the caller's failure messages.
    static func recordOrLoad<T: Codable>(
        _ value: T, at url: URL, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (expected: T, actualText: String)? {
        let data = try encode(value: value)
        let text = String(decoding: data, as: UTF8.self)
        let name = url.lastPathComponent
        try #require(!containsBattleTag(text), "golden '\(name)' would contain a BattleTag", sourceLocation: sourceLocation)
        if isRecording {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return nil
        }
        let expectedData = try #require(
            try? Data(contentsOf: url), "missing golden \(name); run with TAVERN_RECORD_GOLDENS=1 to create it",
            sourceLocation: sourceLocation
        )
        #expect(!containsBattleTag(String(decoding: expectedData, as: UTF8.self)), "golden '\(name)' contains a BattleTag",
                sourceLocation: sourceLocation)
        return (try JSONDecoder().decode(T.self, from: expectedData), text)
    }

    /// Compares `value` to the golden at `url` as a whole, or records it.
    static func verify<T: Codable & Equatable>(
        _ value: T, at url: URL, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        guard let (expected, text) = try recordOrLoad(value, at: url, sourceLocation: sourceLocation) else { return }
        #expect(expected == value, "differs from golden \(url.lastPathComponent):\n\(text)", sourceLocation: sourceLocation)
    }

    /// Compares `result` to the named golden, or records it when recording is on.
    static func verify(
        _ result: ReplayResult,
        golden name: String,
        checkpoints: [Checkpoint],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let actual = golden(from: result, checkpoints: checkpoints)
        let url = goldenDirectory.appending(path: "\(name).json")
        guard let (expected, actualText) = try recordOrLoad(actual, at: url, sourceLocation: sourceLocation) else { return }
        #expect(expected.games == actual.games, "games differ from golden '\(name)':\n\(actualText)", sourceLocation: sourceLocation)
        for checkpoint in checkpoints {
            let key = checkpoint.description
            let want = expected.checkpoints[key] ?? nil
            let got = actual.checkpoints[key] ?? nil
            #expect(
                want == got,
                "checkpoint \(key) differs from golden '\(name)'\nexpected: \(describe(want))\nactual:   \(describe(got))",
                sourceLocation: sourceLocation
            )
        }
    }

    /// `Name#1234`-shaped text. Goldens must be redacted. (The engine's own detector, which
    /// bookmark exports use.)
    static func containsBattleTag(_ text: String) -> Bool {
        BattleTag.appears(in: text)
    }

    private static func describe(_ entry: TimelineEntry?) -> String {
        guard let entry else { return "nil" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(entry)).map { String(decoding: $0, as: UTF8.self) } ?? "\(entry)"
    }
}
