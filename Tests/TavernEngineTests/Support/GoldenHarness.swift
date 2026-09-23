import Foundation
import Testing
import TavernEngine

/// Seam 1 golden tests: replay a log through `TavernEngine` and compare chosen
/// checkpoints of the emitted timeline, plus the game records, to expected JSON in
/// `Tests/TavernEngineTests/Golden/<name>.json`.
///
/// Record or refresh a golden with `TAVERN_RECORD_GOLDENS=1 swift test`, then review
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
            selected[checkpoint.description] = .some(checkpoint.select(from: result.timeline))
        }
        return Golden(games: result.games, checkpoints: selected)
    }

    static func encode(_ golden: Golden) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(golden)
        data.append(0x0A)
        return data
    }

    /// Compares `result` to the named golden, or records it when recording is on.
    static func verify(
        _ result: ReplayResult,
        golden name: String,
        checkpoints: [Checkpoint],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let actual = golden(from: result, checkpoints: checkpoints)
        let actualData = try encode(actual)
        let actualText = String(decoding: actualData, as: UTF8.self)
        try #require(!containsBattleTag(actualText), "golden '\(name)' would contain a BattleTag", sourceLocation: sourceLocation)

        let url = goldenDirectory.appending(path: "\(name).json")
        if isRecording {
            try FileManager.default.createDirectory(at: goldenDirectory, withIntermediateDirectories: true)
            try actualData.write(to: url)
            return
        }

        let expectedData = try #require(
            try? Data(contentsOf: url),
            "missing golden \(url.lastPathComponent); run with TAVERN_RECORD_GOLDENS=1 to create it",
            sourceLocation: sourceLocation
        )
        let expected = try JSONDecoder().decode(Golden.self, from: expectedData)
        #expect(!containsBattleTag(String(decoding: expectedData, as: UTF8.self)), "golden '\(name)' contains a BattleTag", sourceLocation: sourceLocation)

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

    /// `Name#1234`-shaped text. Goldens must be redacted.
    static func containsBattleTag(_ text: String) -> Bool {
        text.contains(/[\p{L}\p{N}_]+#\d{3,}/)
    }

    private static func describe(_ entry: TimelineEntry?) -> String {
        guard let entry else { return "nil" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(entry)).map { String(decoding: $0, as: UTF8.self) } ?? "\(entry)"
    }
}
