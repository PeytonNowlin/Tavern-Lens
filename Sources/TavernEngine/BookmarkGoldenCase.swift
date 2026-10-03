import Foundation

/// A bookmark turned into a regression test: replaying `cut` of `log` must publish `expected`.
///
/// The case JSON is committed (`Tests/TavernEngineTests/Golden/Bookmarks/<name>.json`), so it's
/// redacted: opponents' display names become `Opp-P<PlayerID>`. The log holds BattleTags and
/// stays in the git-ignored fixtures directory.
public struct BookmarkGoldenCase: Codable, Hashable, Sendable {
    public static let currentFormat = 1

    public var format = BookmarkGoldenCase.currentFormat
    public var name: String
    public var note: String
    public var bookmarkID: UUID?
    /// The Power.log, relative to the private fixtures directory (`fixtures/private-logs`).
    public var log: String
    public var cut: LogCut
    /// Redacted like `expected`.
    public var resumed: GameRecord?
    public var expected: TimelineEntry
    /// The advice shown at the moment, when there was any: replaying the case re-scores it
    /// (`TavernEngine.replayAdvice`) and must give exactly this.
    public var expectedAdvice: AdviceView?
    /// The state `expectedAdvice` is for, so the case can be re-scored under other weights
    /// without its log (`AdvisorTuning`); it holds no names.
    public var adviceRequest: AdvisorRequest?
    /// The bookmark's screen readings, taken in again at their lines.
    public var screenTribes: [LoggedScreenTribes]?

    public init(
        name: String, note: String, bookmarkID: UUID? = nil, log: String, cut: LogCut, resumed: GameRecord? = nil,
        expected: TimelineEntry, expectedAdvice: AdviceView? = nil, adviceRequest: AdvisorRequest? = nil,
        screenTribes: [LoggedScreenTribes]? = nil
    ) {
        self.name = name
        self.note = note
        self.bookmarkID = bookmarkID
        self.log = log
        self.cut = cut
        self.resumed = resumed.map { $0.redactingNames() }
        self.expected = expected.redactingNames()
        self.expectedAdvice = expectedAdvice
        self.adviceRequest = adviceRequest
        self.screenTribes = screenTribes
    }

    /// Replays the case from its log and returns the published moment, redacted like `expected`.
    /// `setup` is the engine setup the bookmark was taken with (the live app's data).
    public func replay(powerLog url: URL, setup: EngineSetup = EngineSetup()) throws -> TimelineEntry? {
        let engine = try TavernEngine.replay(
            cut, powerLog: url, resuming: resumed, screenTribes: screenTribes, setup: setup, timeZone: .gmt
        )
        return engine.timeline.last?.redactingNames()
    }

    /// Re-scores the case's advice from its log (`TavernEngine.replayAdvice`).
    public func replayAdvice(
        powerLog url: URL, setup: EngineSetup = EngineSetup(), simulate: AdvisorEvaluation.Simulate
    ) async throws -> AdviceView? {
        try await TavernEngine.replayAdvice(
            expectedAdvice, cut: cut, powerLog: url, resuming: resumed, screenTribes: screenTribes, setup: setup,
            simulate: simulate
        )
    }

    /// Re-records the advice and its request for the state the log replays to now, scored as far
    /// as the advice was (same plan and evaluations): after an intended change to the request,
    /// when `replayAdvice` no longer matches the state the advice was for.
    public mutating func rescoreAdvice(
        powerLog url: URL, setup: EngineSetup = EngineSetup(), simulate: AdvisorEvaluation.Simulate
    ) async throws {
        guard let advice = expectedAdvice else { return }
        let engine = try TavernEngine.replay(
            cut, powerLog: url, resuming: resumed, screenTribes: screenTribes, setup: setup, timeZone: .gmt
        )
        guard let request = engine.advisorRequest else { throw BookmarkReplayError.adviceForAnotherState }
        expectedAdvice = try await advice.replaying(request, simulate: simulate)
        if adviceRequest != nil { adviceRequest = request }
    }

    /// Pretty-printed with sorted keys, and dates as the record store writes them.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = GameRecordStore.encoder.dateEncodingStrategy
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) throws -> BookmarkGoldenCase {
        try GameRecordStore.decoder.decode(BookmarkGoldenCase.self, from: data)
    }

    /// `Name#1234`-shaped text.
    public static func containsBattleTag(_ text: String) -> Bool {
        BattleTag.appears(in: text)
    }
}
