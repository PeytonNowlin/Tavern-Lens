import Foundation
import Testing
import TavernEngine

/// The blended score on synthetic states with the stub scorer: the lobby term (the best board
/// changes against the other opponents' last-seen boards), the build term, the economy term
/// (levelling tempo 1-2 turns ahead), how they add up and how they're weighted.
@Suite("Advisor blended scoring")
struct AdvisorBlendTests {
    typealias S = AdvisorSynthetic

    /// The synthetic plan with a lobby pass.
    static let plan = AdvisorPlan(
        seed: 42, simulations: 400, refineSimulations: 800, refinedGroups: 2, lobbySimulations: 300, lobbyGroups: 2
    )

    static func run(
        _ request: AdvisorRequest, _ stub: S.Stub, plan: AdvisorPlan = plan, calls: S.Calls = S.Calls()
    ) async throws -> Advice {
        try await AdvisorEvaluation.run(request, plan: plan, simulate: S.simulate(stub, calls: calls)).advice
    }

    /// A build whose core cards aren't on the turn-11 board (BG36_997 and BG36_998 are made up).
    static func discard(coreTiers: [String: Int] = [:]) -> AdvisorBuild {
        AdvisorBuild(
            id: "aberration_discard_deity", name: "Aberration Discard", share: 1, core: ["BG36_997", "BG36_998"],
            addons: ["BG36_311"], coreTiers: coreTiers
        )
    }

    // MARK: Lobby

    @Test("A lobby opponent counts less when fought last turn and as their board gets old")
    func lobbyWeights() throws {
        let w = AdvisorWeights.standard
        let weight = { (seen: Int) in Advisor.lobbyWeight(try S.lobbyOpponent(2, seenTurn: seen), bgTurn: 11, weights: w) }
        #expect(try weight(10) == 0.5, "fought last turn: less likely next")
        #expect(try weight(9) == pow(0.5, 1.0 / 3))
        #expect(try weight(7) == 0.5, "a board 4 turns old counts half")
        #expect(try weight(4) == 0.25)

        // The next opponent (the combat term's) and dead opponents aren't the lobby term's.
        let request = try S.request(lobby: [
            try S.lobbyOpponent(7, seenTurn: 10), try S.lobbyOpponent(3, seenTurn: 5),
            try S.lobbyOpponent(2, seenTurn: 9), try S.lobbyOpponent(5, seenTurn: 8, hp: 0),
        ])
        #expect(Advisor.lobbyOpponents(for: request).map(\.playerID) == [2, 3])
    }

    @Test("The stand-in for an unseen next opponent is the most recently seen living one, fought at combat start first")
    func standInChoice() throws {
        var rebuilt = try S.lobbyOpponent(4, seenTurn: 10)
        rebuilt.source = .lastSeenBoard
        let lobby = [
            try S.lobbyOpponent(2, seenTurn: 9), rebuilt, try S.lobbyOpponent(6, seenTurn: 10),
            try S.lobbyOpponent(3, seenTurn: 10), try S.lobbyOpponent(5, seenTurn: 10, hp: 0),
        ]
        #expect(AdvisorRequest.standIn(from: lobby)?.playerID == 3)
        #expect(AdvisorRequest.standIn(from: [rebuilt])?.playerID == 4)
        #expect(AdvisorRequest.standIn(from: []) == nil)
    }

    @Test("Scored against a stand-in, a clear buy says who it's against, at most medium confidence, and the stand-in isn't in the lobby term")
    func standIn() async throws {
        let shop = [S.shopMinion(901, attack: 2, health: 2), S.shopMinion(902, attack: 20, health: 20)]
        let standIn = try S.lobbyOpponent(3, seenTurn: 10)
        var request = try S.request(boardCount: 5, shop: shop, gold: 3, lobby: [try S.lobbyOpponent(2, seenTurn: 8), standIn])
        request.standIn = standIn
        #expect(Advisor.lobbyOpponents(for: request).map(\.playerID) == [2])

        let advice = try await Self.run(request, AdvisorSyntheticTests.stub(request))
        #expect(advice.status == .recommendation)
        let top = try #require(advice.suggestions.first)
        #expect(top.reason == "+20% win vs last opponent")
        #expect(top.confidence == .medium, "a stand-in's board is a guess: no more than medium")
        #expect(advice.note == "Scored vs last opponent (next one unseen)")

        request.standIn?.seenTurn = 8
        #expect(request.opponentLabel == "turn 8 opponent")
    }

    @Test("A stand-in for the next opponent's old board: their old board is the lobby term's, and the note says how old")
    func standInForOldBoard() async throws {
        let shop = [S.shopMinion(901, attack: 2, health: 2), S.shopMinion(902, attack: 20, health: 20)]
        let standIn = try S.lobbyOpponent(3, seenTurn: 10)
        // P7 (the next opponent) was last seen on turn 5.
        var request = try S.request(boardCount: 5, shop: shop, gold: 3, lobby: [try S.lobbyOpponent(7, seenTurn: 5), standIn])
        request.standIn = standIn
        #expect(request.replacedSeenTurn == 5)
        #expect(Advisor.lobbyOpponents(for: request).map(\.playerID) == [7])

        let advice = try await Self.run(request, AdvisorSyntheticTests.stub(request))
        #expect(advice.note == "Scored vs last opponent (theirs is from turn 5)")
        #expect(advice.suggestions.first?.reason == "+20% win vs last opponent")
    }

    @Test("A buy that's even against the next opponent but strong against the rest of the lobby comes first")
    func lobby() async throws {
        let shop = [S.shopMinion(901, attack: 6, health: 6), S.shopMinion(902, attack: 6, health: 6)]
        let lobby = [try S.lobbyOpponent(2, seenTurn: 9), try S.lobbyOpponent(3, seenTurn: 5)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3, lobby: lobby)
        var stub = AdvisorSyntheticTests.stub(request)
        stub.versus = [1002: (902, 30)]  // the second one beats P2's board
        let calls = S.Calls()
        let advice = try await Self.run(request, stub, calls: calls)

        let top = try #require(advice.suggestions.first)
        #expect(top.action == .buy(shop: 1, cardID: "BG36_106", place: 5))
        #expect(top.reason == "Stronger vs the rest of the lobby")
        // Against P2 (weight 0.79) its stats and the +30 are worth 40, against P3 (0.31) its stats
        // 6.7: a weighted mean of 30.5, at half weight.
        let lobbyTerm = try #require(top.terms.lobby)
        #expect(abs(lobbyTerm - 15.25) < 0.2, "lobby term \(lobbyTerm)")
        #expect(abs(top.gain - (top.terms.combat + lobbyTerm + (top.terms.economy ?? 0))) < 0.02)
        let other = try #require(advice.suggestions.first { $0.action == .buy(shop: 0, cardID: "BG36_106", place: 5) })
        #expect(other.terms.lobby.map { abs($0 - 3.33) < 0.1 } == true, "scored against the lobby too: its stats only")

        // The lobby pass: the baseline and the best two groups against each opponent, on one seed.
        let lobbyCalls = calls.all.filter { $0.simulations == Self.plan.lobbySimulations }
        #expect(lobbyCalls.count == 3 * 2)
        #expect(Set(lobbyCalls.map(\.seed)).count == 1)
        #expect(Set(lobbyCalls.map(\.input.opponentBoard.player.entityId)) == [1002, 1003])

        // Lobby weight 0 (or no lobby pass) leaves the two buys even.
        var weights = AdvisorWeights.standard
        weights.lobby = 0
        let flat = try await Self.run(request, stub, plan: Self.plan.with(weights: weights))
        #expect(flat.status == .noStrongRecommendation && flat.note == "Options are close")
        let noPass = AdvisorPlan(seed: 42, simulations: 400, refineSimulations: 800, refinedGroups: 2)
        let noPassCalls = S.Calls()
        let combatOnly = try await Self.run(request, stub, plan: noPass, calls: noPassCalls)
        #expect(combatOnly.suggestions.allSatisfy { $0.terms.lobby == nil })
        #expect(noPassCalls.all.allSatisfy { $0.input.opponentBoard.player.entityId != 1002 })
    }

    @Test("The blend with the lobby is deterministic, and stopping partway through the lobby pass replays")
    func lobbyDeterministic() async throws {
        let shop = [S.shopMinion(901, attack: 6, health: 6), S.shopMinion(902, attack: 9, health: 3)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3, lobby: [try S.lobbyOpponent(2, seenTurn: 9)])
        var stub = AdvisorSyntheticTests.stub(request)
        stub.versus = [1002: (901, 12)]
        var reports: [AdvisorEvaluation.Progress] = []
        let done = try await AdvisorEvaluation.run(request, plan: Self.plan, simulate: S.simulate(stub)) { reports.append($0) }
        let again = try await AdvisorEvaluation.run(request, plan: Self.plan, simulate: S.simulate(stub))
        #expect(done.advice == again.advice && done.evaluations == again.evaluations)
        let partway = try #require(reports.first { $0.evaluations == done.evaluations - 1 })
        let view = AdviceView(request: request, plan: Self.plan, advice: partway.advice, evaluations: partway.evaluations)
        let replayed = try await view.replaying(request, simulate: S.simulate(stub))
        #expect(replayed.advice == partway.advice)
    }

    // MARK: Builds

    @Test("A core card of the detected build beats a slightly stronger buy; without the build term it doesn't")
    func build() async throws {
        // BG36_997 is core for the build; BG36_200 isn't in it.
        let shop = [
            S.shopMinion(901, attack: 1, health: 1, cardID: "BG36_997"), S.shopMinion(902, attack: 3, health: 3, cardID: "BG36_200"),
        ]
        let request = try S.request(boardCount: 5, shop: shop, gold: 3, builds: [Self.discard()])
        let stub = AdvisorSyntheticTests.stub(request)
        let advice = try await Self.run(request, stub)
        let top = try #require(advice.suggestions.first)
        #expect(top.action == .buy(shop: 0, cardID: "BG36_997", place: 5))
        #expect(top.reason == "Core card for Aberration Discard")
        #expect(top.terms.build == 6)
        #expect(top.confidence != .high, "mostly a rule of thumb: at most medium")

        let combatOnly = try await Self.run(request, stub, plan: Self.plan.with(weights: .combatOnly))
        #expect(combatOnly.suggestions.first?.action == .buy(shop: 1, cardID: "BG36_200", place: 5))
        #expect(combatOnly.suggestions.allSatisfy { ($0.terms.build ?? 0) == 0 && ($0.terms.economy ?? 0) == 0 })
    }

    @Test("Build progress: core and add-on cards once each, extra copies toward a triple, goldens done")
    func buildValue() throws {
        var build = Self.discard()
        build.share = 1
        var second = build
        second.id = "other"
        second.share = 0.6
        second.core = ["BG36_311"]
        second.addons = []
        let request = try S.request(builds: [build, second])
        let progress = AdvisorBuildProgress(request: request, weights: .standard)
        #expect(progress.value(of: []) == 0)
        #expect(progress.value(of: ["BG36_997"]) == 6)
        #expect(progress.value(of: ["BG36_997", "BG36_997"]) == 7.5, "a pair toward a triple")
        #expect(progress.value(of: ["BG36_997", "BG36_997", "BG36_997", "BG36_997"]) == 9, "two extra copies at most")
        #expect(progress.value(of: ["BG36_997_G", "BG36_997"]) == 6, "a golden is done")
        // BG36_311 is an add-on of the first (2) and core of the second (6 × 0.6).
        #expect(abs(progress.value(of: ["BG36_311"]) - 5.6) < 1e-9)
    }

    @Test("Levelling to the tier of a missing core card counts as build progress")
    func unlock() async throws {
        var weights = AdvisorWeights.standard
        weights.buildUnlock = 10
        // Tier 4 on turn 7 is on the curve (levelling is worth 4); the missing BG36_997 is tier 5.
        let request = try S.request(
            boardCount: 7, shop: [S.shopMinion(901, attack: 0, health: 1)], gold: 8, tier: 4, levelCost: 8, bgTurn: 7,
            income: 9, builds: [Self.discard(coreTiers: ["BG36_997": 5, "BG36_998": 2])]
        )
        let advice = try await Self.run(request, AdvisorSyntheticTests.stub(request, base: 80), plan: Self.plan.with(weights: weights))
        let level = try #require(advice.suggestions.first)
        #expect(level.action == .level(cost: 8, toTier: 5))
        #expect(level.terms.build == 10 && level.terms.economy == 4)
        #expect(level.reason == "Opens tier 5 for a core card you need")
    }

    // MARK: Economy

    @Test("The levelling curve and the look ahead: level now against next turn, in two turns or never")
    func economyModel() throws {
        #expect((1...12).map(AdvisorEconomy.curveTier) == [1, 2, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6])
        let w = AdvisorWeights.standard
        // Tier 4 on turn 11 (behind: ×1.5), level 7, 8 gold: now 7.5×3−7 = 15.5, next turn 7.5×2−6 = 9.
        let behind = AdvisorEconomy(request: try S.request(gold: 8, tier: 4, levelCost: 7), weights: w)
        #expect(behind.urgency == 1.5 && behind.levelGain == 6.5)
        // A 3-gold buy leaves 5 and loses levelling now; with 10 gold it doesn't; a sale at 6 gold frees it.
        let buy = AdvisorAction.buy(shop: 0, cardID: "x", place: 0)
        let shop = [S.shopMinion(901, attack: 1, health: 1)]
        #expect(AdvisorEconomy(request: try S.request(shop: shop, gold: 8, tier: 4, levelCost: 7), weights: w).tempo(buy) == -6.5)
        #expect(AdvisorEconomy(request: try S.request(shop: shop, gold: 10, tier: 4, levelCost: 7), weights: w).tempo(buy) == 0)
        let sell = AdvisorAction.sell(board: 0, cardID: "x")
        #expect(AdvisorEconomy(request: try S.request(gold: 6, tier: 4, levelCost: 7), weights: w).tempo(sell) == 6.5)
        // Ahead of the curve (tier 5 on turn 7, ×0.5), level 9: waiting beats levelling now.
        let ahead = AdvisorEconomy(request: try S.request(gold: 10, tier: 5, levelCost: 9, bgTurn: 7, income: 9), weights: w)
        #expect(ahead.urgency == 0.5 && ahead.levelGain < 0)
        // Next turn's gold can't pay for the discounted level: only now or in two turns count.
        let poor = AdvisorEconomy(request: try S.request(gold: 7, tier: 2, levelCost: 7, bgTurn: 5, income: 4), weights: w)
        #expect(poor.levelGain == 7.5 * 3 - 7 - (7.5 - 5))
        // A refresh: a fresh shop's worth by the chance of losing, less its gold.
        #expect(abs(behind.roll(cost: 1, baseEquity: 25) - (6 * 0.75 - 1)) < 1e-9)
    }

    @Test("A buy that spends the levelling gold carries the tempo cost, and the level is suggested beside it")
    func tempo() async throws {
        let shop = [S.shopMinion(901, attack: 20, health: 20)]
        let request = try S.request(boardCount: 5, shop: shop, gold: 8, tier: 4, levelCost: 7)
        let advice = try await Self.run(request, AdvisorSyntheticTests.stub(request))
        let buy = try #require(advice.suggestions.first { if case .buy = $0.action { true } else { false } })
        #expect(buy.terms.economy == -6.5)
        #expect(abs(buy.gain - (buy.terms.combat - 6.5)) < 0.02)
        #expect(advice.suggestions.contains { $0.action == .level(cost: 7, toTier: 5) })
        #expect(advice.suggestions.first?.action == buy.action, "+22 combat − 6.5 tempo still beats levelling's 6.5")
    }
}
