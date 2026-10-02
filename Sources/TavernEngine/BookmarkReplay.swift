import Foundation
import HSLog

public enum BookmarkReplayError: Error, Equatable, CustomStringConvertible {
    /// The log ends before the cut's last line.
    case logTooShort(lines: Int, needed: Int)
    case invalidCut
    /// An exported case didn't replay to the bookmarked state.
    case replayDiffers
    /// The case JSON would contain a `Name#1234` BattleTag (in the note?).
    case containsBattleTag
    case missingLog(String)
    /// The advice shown was for another state than the bookmarked one (it was still catching up).
    case adviceForAnotherState

    public var description: String {
        switch self {
        case .logTooShort(let lines, let needed): "the log has \(lines) lines; the bookmark needs \(needed)"
        case .invalidCut: "the bookmark's log cut is invalid"
        case .replayDiffers: "replaying the log doesn't reach the bookmarked state"
        case .containsBattleTag: "the case would contain a BattleTag; remove it from the note"
        case .missingLog(let path): "the log \(path) isn't there any more"
        case .adviceForAnotherState: "the advice shown was for an earlier state than the bookmarked one"
        }
    }
}

extension TavernEngine {
    /// Replays `cut` of the Power.log at `url` the way the live pipeline read it: an engine set up
    /// as the live one was (`setup`), carry in `record` (the bookmark's `resumed`), start at the
    /// cut's first line, catch up to its last, taking in each screen reading at the line it came
    /// in at, and publish once. The returned engine's `state` is the moment.
    public static func replay(
        _ cut: LogCut, powerLog url: URL, resuming record: GameRecord? = nil, screenTribes: [LoggedScreenTribes]? = nil,
        setup: EngineSetup = EngineSetup(), timeZone: TimeZone = .current
    ) throws -> TavernEngine {
        guard cut.startLine >= 1, cut.endLine >= cut.startLine else { throw BookmarkReplayError.invalidCut }
        let session = cut.session.flatMap {
            LogSession(directory: URL(filePath: "/", directoryHint: .isDirectory).appending(path: $0), timeZone: timeZone)
        }
        var engine = TavernEngine(setup: setup, session: session, timeZone: timeZone)
        if let record { engine.resume(record) }
        let start = cut.startByteOffset ?? cut.locating(in: url).startByteOffset
        guard let start else { throw BookmarkReplayError.logTooShort(lines: 0, needed: cut.startLine) }
        engine.start(at: PowerLogEntryPoint(byteOffset: start, line: cut.startLine, gameSeed: cut.gameSeed))
        engine.beginCatchUp()
        var readings = (screenTribes ?? []).filter { $0.line <= cut.endLine }[...]
        // Readings from before the first line read (the app attached after them).
        while let next = readings.first, next.line < cut.startLine {
            engine.ingestScreenTribes(next.reading)
            readings = readings.dropFirst()
        }
        struct Reached: Error {}
        do {
            try LogFileReader.forEachLine(in: url, from: start) { line in
                engine.ingest(line)
                while let next = readings.first, next.line <= engine.linesRead {
                    engine.ingestScreenTribes(next.reading)
                    readings = readings.dropFirst()
                }
                if engine.linesRead >= cut.endLine { throw Reached() }
            }
            throw BookmarkReplayError.logTooShort(lines: engine.linesRead, needed: cut.endLine)
        } catch is Reached {}
        engine.endCatchUp()
        return engine
    }

    /// Re-scores `advice` for the moment `cut` replays to, exactly as far as it was scored (same
    /// plan, seed and number of evaluations), so it comes out identical. Nil when there's no
    /// advice; throws `adviceForAnotherState` when the advice was for an earlier state.
    ///
    /// `setup` must be the live engine's (card data, pool, builds and hero stats), since the
    /// request carries the builds and the lobby's tribes; a bookmark that kept its
    /// `adviceRequest` can be re-scored without the log at all (`AdviceView.replaying`).
    public static func replayAdvice(
        _ advice: AdviceView?, cut: LogCut, powerLog url: URL, resuming record: GameRecord? = nil,
        screenTribes: [LoggedScreenTribes]? = nil, setup: EngineSetup = EngineSetup(),
        simulate: AdvisorEvaluation.Simulate
    ) async throws -> AdviceView? {
        guard let advice else { return nil }
        let engine = try replay(
            cut, powerLog: url, resuming: record, screenTribes: screenTribes, setup: setup, timeZone: .gmt
        )
        guard let request = engine.advisorRequest, AdviceView.fingerprint(of: request, version: advice.plan.version) == advice.fingerprint else {
            throw BookmarkReplayError.adviceForAnotherState
        }
        return try await advice.replaying(request, simulate: simulate)
    }

    /// Replays a bookmark's moment from its Power.log (or another copy of it at `url`), with its
    /// carried-in record and screen readings. With the live engine's `setup`, the moment comes out
    /// exactly as it was shown.
    public static func replay(
        _ bookmark: FeedbackBookmark, powerLog url: URL, setup: EngineSetup = EngineSetup()
    ) throws -> TavernEngine {
        try replay(bookmark.cut, powerLog: url, resuming: bookmark.resumed, screenTribes: bookmark.screenTribes, setup: setup)
    }
}
