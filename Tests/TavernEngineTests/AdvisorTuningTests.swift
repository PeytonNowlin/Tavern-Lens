import Foundation
import Testing
import TavernEngine

/// Weight tuning from bookmarked cases: every committed case re-scores to its recorded advice
/// (the regression check), none breaks a sanity rule, and a weight change is reported case by case.
///
/// `scripts/advisor-tune.sh <weights.json>` runs `tuningRun`, which replays every case it can find
/// under the given weights and prints the report (docs/advisor/scoring.md).
@Suite("Advisor weight tuning")
struct AdvisorTuningTests {
    typealias S = AdvisorSynthetic

    /// The committed cases: golden bookmark cases with advice, and the advisor's golden state.
    static func committedCases() throws -> [AdvisorCase] {
        let turn11 = AdvisorSimulatorTests.turn11
        let request = try AdvisorFixture.load(AdvisorRequest.self, golden: "\(turn11).request")
        let advice = try AdvisorFixture.load(AdviceView.self, golden: "\(turn11).advice")
        return AdvisorCase.goldenCases(in: BookmarkGoldenTests.directory)
            + [AdvisorCase(name: turn11, note: "Turn 11 against the opponent's actual board", request: request, recorded: advice)]
    }

    /// With the private fixture: the full game's late recruit phases, with their golden advice.
    static func fixtureCases() throws -> [AdvisorCase] {
        guard Fixtures.isAvailable(Fixtures.fullGame) else { return [] }
        let replay = try AdvisorFixture.replay(Fixtures.fullGame, builds: BuildFixture.catalog)
        let golden = try AdvisorFixture.load([String: AdviceView].self, golden: "full-game-advice")
        return (8...12).compactMap { turn in
            guard let request = replay.mostGold[turn] else { return nil }
            let recorded = golden["turn-\(turn)"].flatMap { $0.fingerprint == AdviceView.fingerprint(of: request) ? $0 : nil }
            return AdvisorCase(name: "full-game-turn-\(turn)", note: "Fixture: turn \(turn) as the shop opened",
                               request: request, recorded: recorded)
        }
    }

    @Test("A weight change is reported case by case; the recorded weights change nothing")
    func report() async throws {
        let shop = [
            S.shopMinion(901, attack: 1, health: 1, cardID: "BG36_997"), S.shopMinion(902, attack: 3, health: 3, cardID: "BG36_200"),
        ]
        let buildCase = try S.request(boardCount: 5, shop: shop, gold: 3, builds: [AdvisorBlendTests.discard()])
        let plainCase = try S.request(boardCount: 5, shop: [S.shopMinion(901, attack: 20, health: 20)], gold: 3)
        let stub = AdvisorSyntheticTests.stub(buildCase)
        let simulate = S.simulate(stub)
        var cases: [AdvisorCase] = []
        for (name, request) in [("build", buildCase), ("plain", plainCase)] {
            let done = try await AdvisorEvaluation.run(request, plan: AdvisorBlendTests.plan, simulate: simulate)
            let view = AdviceView(request: request, plan: AdvisorBlendTests.plan, advice: done.advice,
                                  evaluations: done.evaluations, isComplete: true)
            cases.append(AdvisorCase(name: name, request: request, recorded: view))
        }

        let same = try await AdvisorTuning.replay(cases, weights: .standard, simulate: simulate)
        #expect(same.rows.count == 2 && same.changed.isEmpty)
        #expect(same.rows.allSatisfy { $0.before == $0.after && $0.violations.isEmpty })

        var weights = AdvisorWeights.standard
        weights.build = 0
        let report = try await AdvisorTuning.replay(cases, weights: weights, simulate: simulate)
        #expect(report.topChanged.map(\.name) == ["build"], "the core card no longer beats the stronger buy")
        let row = try #require(report.rows.first)
        #expect(row.before.suggestions.first?.action.group == "buy:s0" && row.after.suggestions.first?.action.group == "buy:s1")
        #expect(report.text.contains("CHANGED build") && report.text.contains("same    plain"))
        #expect(report.text.hasPrefix("2 cases: 1 with a new top suggestion or status"))
        let decoded = try JSONDecoder().decode(AdvisorTuning.Report.self, from: JSONEncoder().encode(report))
        #expect(decoded == report)

        // Partway advice replays partway: a case cut short by the time budget is compared as it was.
        let partway = try await AdvisorEvaluation.run(buildCase, plan: AdvisorBlendTests.plan, limit: 5, simulate: simulate)
        let shown = AdviceView(request: buildCase, plan: AdvisorBlendTests.plan, advice: partway.advice, evaluations: 5)
        let cut = try await AdvisorTuning.replay([AdvisorCase(name: "cut", request: buildCase, recorded: shown)],
                                                 weights: .standard, simulate: simulate)
        #expect(cut.changed.isEmpty)
    }

    @Test("A bookmark keeps the state its advice was for, so it's a case without its log")
    func bookmarkCase() throws {
        let request = try S.request(boardCount: 5)
        let view = AdviceView(request: request, plan: S.plan, advice: Advice(status: .thinking))
        let cut = LogCut(session: nil, gameSeed: 1, startLine: 1, startByteOffset: 0, endLine: 1, endByteOffset: 0)
        var bookmark = FeedbackBookmark(cut: cut, shown: TimelineEntry(position: LogPosition(line: 1, time: ""), state: .noGame))
        #expect(AdvisorCase(bookmark: bookmark) == nil)
        bookmark.advice = view
        bookmark.adviceRequest = request
        #expect(AdvisorCase(bookmark: bookmark)?.request == request)
        bookmark.adviceRequest = try S.request(boardCount: 4)
        #expect(AdvisorCase(bookmark: bookmark) == nil, "the request must be the one the advice was for")
    }

    @Test("Every committed and fixture case re-scores to its recorded advice and breaks no sanity rule")
    func regression() async throws {
        let cases = try Self.committedCases() + Self.fixtureCases()
        #expect(cases.count >= 1)
        if Fixtures.isAvailable(Fixtures.fullGame) {
            #expect(cases.count >= 7, "the bookmark case, the turn-11 state and 5 fixture turns: \(cases.map(\.name))")
            #expect(cases.allSatisfy { $0.recorded != nil }, "every case has its golden advice")
        }
        for item in cases {
            if let advice = item.recorded?.advice {
                #expect(AdvisorSanity.violations(advice, request: item.request).isEmpty, "\(item.name)")
            }
        }
        let report = try await AdvisorTuning.replay(cases, weights: .standard, simulate: try AdvisorFixture.simulate())
        #expect(report.changed.isEmpty, "\(report.text)")
        #expect(report.rows.allSatisfy { $0.violations.isEmpty }, "\(report.text)")
    }

    /// `scripts/advisor-tune.sh`: replays every case under `TAVERN_ADVISOR_WEIGHTS` (a weights JSON
    /// file), with the app's saved bookmarks from `TAVERN_ADVISOR_BOOKMARKS` (a record store
    /// directory) when set, and prints the report (also to `TAVERN_ADVISOR_REPORT` when set).
    @Test("Tuning run", .enabled(if: ProcessInfo.processInfo.environment["TAVERN_ADVISOR_WEIGHTS"] != nil))
    func tuningRun() async throws {
        let env = ProcessInfo.processInfo.environment
        let weights = try JSONDecoder().decode(
            AdvisorWeights.self, from: Data(contentsOf: URL(filePath: try #require(env["TAVERN_ADVISOR_WEIGHTS"])))
        )
        var cases = try Self.committedCases() + Self.fixtureCases()
        if let saved = env["TAVERN_ADVISOR_BOOKMARKS"], !saved.isEmpty {
            cases += AdvisorCase.savedBookmarks(in: URL(filePath: saved, directoryHint: .isDirectory))
        }
        let report = try await AdvisorTuning.replay(cases, weights: weights, simulate: try AdvisorFixture.simulate())
        print("\n===== Advisor tuning report =====\n\(report.text)\n=================================")
        if let out = env["TAVERN_ADVISOR_REPORT"], !out.isEmpty {
            try Data((report.text + "\n").utf8).write(to: URL(filePath: out))
        }
    }
}
