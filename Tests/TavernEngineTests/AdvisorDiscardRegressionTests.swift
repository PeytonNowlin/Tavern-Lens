import Foundation
import Testing
import TavernEngine

@Suite("Logged discard advisor regressions")
struct AdvisorDiscardRegressionTests {
    typealias S = AdvisorSynthetic
    static let hammer = "BG36_MagicItem_403"
    static let hammerText = "[x]Your minions have\n+1 Attack. <i>(Improved by\neach card you've\ndiscarded this game!)</i>"
    static let timeTurning = "BG36_MidGameEffect_000t21e"
    static let timeText = "This minion's end of turn effects also trigger at start of turn."
    static let affinity = "BG36_MidGameEffect_000t82e"
    static let affinityText = "At the end of every 2\nturns, get a random\nminion of this type.\n<i>(2 turns left!)</i>2At the end of every 2\nturns, get a random\nminion of this type.\n<i>(End of this turn!)</i>"
    static let sludgeText = "Give your minions +1/+1. If you discard this, cast it twice."

    static func fleshlingText(golden: Bool) -> String {
        "[x]At the end of your turn, give your\nleft-most minion +\(golden ? 4 : 2)/+\(golden ? 4 : 2).\n<i>(Improved by each card you've\ndiscarded this game!)</i>"
    }

    static func gift(_ id: String, amount: Int? = nil) throws -> BattleEnchantment {
        var object: [String: Any] = ["cardId": id, "originEntityId": 100, "timing": 0]
        if let amount { object["tagScriptDataNum1"] = amount; object["tagScriptDataNum2"] = 0 }
        return try JSONDecoder().decode(BattleEnchantment.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func definition(_ id: String, _ text: String, request: inout AdvisorRequest) {
        var card = Card(id: id, dbfId: 100, name: id); card.text = text
        request.recruit!.definitions[id] = card
    }

    static func addHammer(to request: inout AdvisorRequest, discards: Int = 5) throws {
        let object: [String: Any] = ["cardId": hammer, "entityId": 101,
            "scriptDataNum1": discards + 1, "scriptDataNum2": 0, "scriptDataNum6": 1]
        request.recruit!.input.playerBoard.player.trinkets = [try JSONDecoder().decode(BattleTrinket.self,
            from: JSONSerialization.data(withJSONObject: object))]
        request.recruit!.input.playerBoard.player.globalInfo["CardsDiscardedThisGame"] = discards
        request.recruit!.evaluationVersion = 6
        definition(hammer, hammerText, request: &request)
        for i in request.board.indices {
            request.board[i].entity.enchantments.append(try gift("BG36_MagicItem_403e", amount: discards + 1))
        }
    }

    @Test("Hammer adds one attack per discard, alongside both Sludge casts", arguments: [false, true])
    func hammerDiscard(sludge: Bool) throws {
        let discarded = sludge ? S.spell(3, "BG36_301t") : S.shopMinion(3, attack: 2, health: 2, cardID: "fodder")
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "envoy", attack: 10, health: 4), S.boardMinion(2, "body", attack: 12, health: 6)],
            hand: [discarded], gold: 0,
            texts: ["envoy": "Activate (0): Discard a card to get a random Tavern spell.", "BG36_301t": Self.sludgeText])
        try Self.addHammer(to: &request)
        request.recruit!.activations = [1: .init(ready: true, cost: 0)]
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let action = try RecruitPlannerTests.action(.activate, state, context)
        let after = try #require(RecruitPlanner.applying(action, to: state, context: context))
        #expect(after.board.map { $0.entity.attack } == (sludge ? [13, 15] : [11, 13]))
        #expect(after.board.map { $0.entity.health } == (sludge ? [6, 8] : [4, 6]))
        #expect(after.input.playerBoard.player.globalInfo["CardsDiscardedThisGame"] == 6)
        #expect(after.input.playerBoard.player.globalInfo["TavernSpellsCastThisGame", default: 0] == (sludge ? 2 : 0))
        #expect(after.hand.isEmpty && after.unknownRewards == 1 && after.terminal)
        #expect(state.board[0].entity.attack == 10, "observed stats already contain the previous Hammer aura")
        var archived = context; archived.evaluationVersion = 5
        #expect(RecruitPlanner.applying(action, to: state, context: archived) == nil)
    }

    @Test("A newly played body gains Hammer once without changing held or existing bodies")
    func hammerPlay() throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 10, health: 4)],
            hand: [S.shopMinion(2, attack: 2, health: 3, cardID: "new"),
                   S.shopMinion(3, attack: 4, health: 5, cardID: "held")], gold: 0)
        try Self.addHammer(to: &request)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let action = try RecruitPlannerTests.action(.play, state, context, id: 2)
        let after = try #require(RecruitPlanner.applying(action, to: state, context: context))
        #expect(after.board.map { $0.entity.attack } == [10, 8])
        #expect(after.hand.first?.entity.attack == 4)
        let projection = RecruitEffects.combatProjection(after, context: context)
        #expect(projection.board.map { $0.entity.attack } == [10, 8])
        #expect(projection.limitations.isEmpty)
        let sold = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.sell, after, context, id: 2),
            to: after, context: context))
        #expect(sold.board.first?.entity.attack == 10)
    }

    @Test("A triple strips Hammer's board aura before combining buffs into a held golden")
    func hammerTriple() throws {
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "pair", attack: 8, health: 3), S.boardMinion(2, "pair", attack: 8, health: 3)],
            shop: [S.shopMinion(3, attack: 2, health: 3, cardID: "pair")])
        try Self.addHammer(to: &request)
        request.recruit!.definitions["pair"]!.attack = 2
        request.recruit!.definitions["pair"]!.health = 3
        request.recruit!.definitions["pair"]!.dbfId = 10
        request.recruit!.definitions["pair"]!.battlegroundsPremiumDbfId = 11
        var golden = Card(id: "pair_G", dbfId: 11, name: "Golden pair")
        golden.type = "MINION"; golden.attack = 4; golden.health = 6; golden.battlegroundsNormalDbfId = 10
        request.recruit!.definitions[golden.id] = golden
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let after = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.buy, state, context),
            to: state, context: context))
        #expect(after.board.isEmpty && after.hand.count == 1)
        #expect(after.hand[0].entity.attack == 4 && after.hand[0].entity.health == 6)
        #expect(after.hand[0].entity.enchantments.allSatisfy { $0.cardId != "BG36_MagicItem_403e" })
        let played = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.play, after, context),
            to: after, context: context))
        #expect(played.board[0].entity.attack == 10)
    }

    @Test("Fleshling uses the discard counter and Drakkari for only the pending end of turn",
          arguments: [(false, 5, 1), (false, 8, 2), (true, 12, 2), (true, 23, 3)])
    func fleshling(_ scenario: (Bool, Int, Int)) throws {
        let (golden, discards, repeats) = scenario
        let id = golden ? "BG36_114_G" : "BG36_114"
        var engine = S.boardMinion(2, id, attack: 20, health: 30, golden: golden)
        engine.entity.enchantments = [try Self.gift(Self.timeTurning)]
        // This observed value is stale after hypothetical discards; the global counter is authoritative.
        engine.entity.scriptDataNum1 = 2; engine.entity.scriptDataNum2 = 2
        var board = [S.boardMinion(1, "target", attack: 100, health: 80), engine]
        if repeats > 1 { board.append(S.boardMinion(3, "drakkari", attack: 1, health: 5)) }
        var request = try RecruitPlannerTests.request(board: board,
            texts: [id: Self.fleshlingText(golden: golden),
                    "drakkari": "Your end of turn effects trigger \(repeats == 3 ? "three times" : "twice")."])
        request.recruit!.evaluationVersion = 6
        request.recruit!.input.playerBoard.player.globalInfo["CardsDiscardedThisGame"] = discards
        Self.definition(Self.timeTurning, Self.timeText, request: &request)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let projected = RecruitEffects.combatProjection(state, context: context)
        let buff = (golden ? 4 : 2) * (1 + discards) * repeats
        #expect(projected.board[0].entity.attack == 100 + buff)
        #expect(projected.board[0].entity.health == 80 + buff)
        #expect(projected.board[1].entity.attack == 20 && projected.board[1].entity.health == 30)
        #expect(projected.limitations.isEmpty)
        #expect(state.board[0].entity.attack == 100, "Time Turning's start-of-turn buff is already observed")
        var archived = context; archived.evaluationVersion = 5
        let old = RecruitEffects.combatProjection(state, context: archived)
        #expect(old.board[0].entity.attack == 100 && !old.limitations.isEmpty)
    }

    @Test("Affinity leaves the pending random hand reward unknown without blocking current combat")
    func affinity() async throws {
        var body = S.boardMinion(1, "body", attack: 2, health: 2)
        body.entity.enchantments = [try Self.gift(Self.affinity)]
        var request = try RecruitPlannerTests.request(board: [body],
            shop: [S.shopMinion(2, attack: 8, health: 8, cardID: "upgrade")])
        request.recruit!.evaluationVersion = 6
        Self.definition(Self.affinity, Self.affinityText, request: &request)
        let projection = RecruitEffects.combatProjection(RecruitState(request: request, context: request.recruit!), context: request.recruit!)
        #expect(projection.hand.isEmpty && projection.board[0].entity.attack == 2)
        #expect(projection.limitations.isEmpty)
        var plan = AdvisorPlan.live; plan.version = 6
        let result = try await AdvisorEvaluation.run(request, plan: plan, simulate: S.simulate(.init(baseline: 0)))
        #expect(result.evaluations > 0)
        plan.version = 5
        let old = try await AdvisorEvaluation.run(request, plan: plan, simulate: S.simulate(.init(baseline: 0)))
        #expect(old.evaluations == 0)
    }

    @Test("The recorded Hammer, Fleshling, Time Turning and Drakkari combination restores combat checks")
    func combinedEngine() async throws {
        var engine = S.boardMinion(2, "BG36_114_G", attack: 60, health: 49, golden: true)
        engine.entity.enchantments = [try Self.gift(Self.timeTurning)]
        var request = try RecruitPlannerTests.request(
            board: [S.boardMinion(1, "target", attack: 100, health: 80), engine,
                    S.boardMinion(3, "BG26_ICC_901", attack: 20, health: 5)],
            shop: [S.shopMinion(4, attack: 8, health: 8, cardID: "upgrade")],
            texts: ["BG36_114_G": Self.fleshlingText(golden: true),
                    "BG26_ICC_901": "Your end of turn effects trigger twice."])
        try Self.addHammer(to: &request, discards: 18)
        Self.definition(Self.timeTurning, Self.timeText, request: &request)
        let calls = S.Calls()
        var plan = AdvisorPlan.live; plan.version = 6
        let current = try await AdvisorEvaluation.run(request, plan: plan,
            simulate: S.simulate(.init(baseline: 0), calls: calls))
        #expect(current.evaluations > 0)
        #expect(calls.all.first?.input.playerBoard.board[0].attack == 252)
        #expect(calls.all.first?.input.playerBoard.board[0].health == 232)
        plan.version = 5
        let old = try await AdvisorEvaluation.run(request, plan: plan, simulate: S.simulate(.init(baseline: 0)))
        #expect(old.evaluations == 0)
    }

    @Test("A stat-setting spell preserves Hammer's current attack aura")
    func hammerStatSet() throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 30, health: 20)],
            hand: [S.spell(2, "set", cost: 0)], gold: 0,
            texts: ["set": "Set a minion's stats to 2/2."])
        try Self.addHammer(to: &request)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let after = try #require(RecruitPlanner.applying(RecruitPlannerTests.action(.spell, state, context),
            to: state, context: context))
        #expect(after.board[0].entity.attack == 8 && after.board[0].entity.health == 2)
        #expect(after.board[0].entity.enchantments.first { $0.cardId == "BG36_MagicItem_403e" }?.tagScriptDataNum1 == 6)
    }

    @Test("Missing or inconsistent Hammer aura observations prevent invented transitions")
    func unknownHammerAura() throws {
        for aura in [Optional<Int>.none, 5] {
            var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "envoy", attack: 10, health: 4)],
                hand: [S.spell(2, "BG36_301t")],
                texts: ["envoy": "Activate (0): Discard a card to get a random Tavern spell.", "BG36_301t": Self.sludgeText])
            try Self.addHammer(to: &request)
            request.board[0].entity.enchantments = [try Self.gift("BG36_MagicItem_403e", amount: aura)]
            request.recruit!.activations = [1: .init(ready: true, cost: 0)]
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            let action = try RecruitPlannerTests.action(.activate, state, context)
            #expect(RecruitPlanner.applying(action, to: state, context: context) == nil)
        }
    }

    @Test("Duplicate Hammer trinkets stay unsupported until their stacking behavior is verified")
    func duplicateHammer() throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 10, health: 4)],
            hand: [S.shopMinion(2, attack: 2, health: 2, cardID: "new")])
        try Self.addHammer(to: &request)
        var second = request.recruit!.input.playerBoard.player.trinkets[0]
        second.entityId = 102
        request.recruit!.input.playerBoard.player.trinkets.append(second)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        #expect(RecruitPlanner.applying(try RecruitPlannerTests.action(.play, state, context),
            to: state, context: context) == nil)
    }

    @Test("Affinity stays uncertain when a hand summon or random triple can change the combat board")
    func affinityCanChangeCombatBoard() throws {
        for pair in [false, true] {
            var gifted = S.boardMinion(1, "murloc", attack: 2, health: 2)
            gifted.entity.enchantments = [try Self.gift(Self.affinity)]
            let other = pair ? S.boardMinion(2, "murloc", attack: 2, health: 2)
                : S.boardMinion(2, "BG26_350", attack: 5, health: 2)
            var request = try RecruitPlannerTests.request(board: [gifted, other],
                texts: ["BG26_350": "<b>Deathrattle:</b> Summon the highest-Health Murloc\nfrom your hand for this combat only."])
            request.recruit!.evaluationVersion = 6
            request.recruit!.definitions["murloc"]!.races = ["MURLOC"]
            Self.definition(Self.affinity, Self.affinityText, request: &request)
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            let projected = RecruitEffects.combatProjection(state, context: context)
            #expect(!projected.limitations.isEmpty)
            #expect(projected.hand.isEmpty && projected.board.count == 2)
        }
    }

    @Test("Time Turning does not whitelist an unsupported underlying end-of-turn effect")
    func unknownTimeTurningEffect() throws {
        var body = S.boardMinion(1, "unknown", attack: 2, health: 2)
        body.entity.enchantments = [try Self.gift(Self.timeTurning)]
        var request = try RecruitPlannerTests.request(board: [body],
            texts: ["unknown": "At the end of your turn, gain a random Bonus Keyword."])
        request.recruit!.evaluationVersion = 6
        Self.definition(Self.timeTurning, Self.timeText, request: &request)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let projected = RecruitEffects.combatProjection(state, context: context)
        #expect(!projected.limitations.isEmpty)
        #expect(projected.board[0].entity.attack == 2 && projected.board[0].entity.health == 2)
    }

    @Test("Fleshling's future production follows discard scaling and observed trigger multipliers")
    func fleshlingProduction() throws {
        func result(discards: Int, repeats: Int = 1, timeTurning: Bool = false) throws -> (production: Double, attack: Int) {
            var engine = S.boardMinion(2, "BG36_114", attack: 20, health: 30)
            if timeTurning { engine.entity.enchantments = [try Self.gift(Self.timeTurning)] }
            var board = [S.boardMinion(1, "target", attack: 100, health: 80), engine]
            if repeats > 1 {
                board.append(S.boardMinion(3, repeats == 3 ? "BG26_ICC_901_G" : "BG26_ICC_901",
                    attack: 1, health: 5, golden: repeats == 3))
            }
            var request = try RecruitPlannerTests.request(board: board,
                texts: ["BG36_114": Self.fleshlingText(golden: false),
                        "BG26_ICC_901": "Your end of turn effects trigger twice.",
                        "BG26_ICC_901_G": "Your end of turn effects trigger three times."])
            request.recruit!.evaluationVersion = 6
            request.recruit!.input.playerBoard.player.globalInfo["CardsDiscardedThisGame"] = discards
            Self.definition(Self.timeTurning, Self.timeText, request: &request)
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            return (RecruitPlanner.production(engine, state: state, context: context),
                    RecruitEffects.combatProjection(state, context: context).board[0].entity.attack)
        }
        let five = try result(discards: 5)
        let eight = try result(discards: 8)
        #expect(five.production > 0 && eight.production > five.production)
        #expect(five.attack == 112 && eight.attack == 118)
        let doubled = try result(discards: 5, repeats: 2)
        let tripled = try result(discards: 5, repeats: 3)
        #expect(doubled.production == five.production * 2)
        #expect(tripled.production == five.production * 3)
        let timeTurning = try result(discards: 5, repeats: 2, timeTurning: true)
        #expect(timeTurning.production == doubled.production * 2)
        #expect(timeTurning.attack == doubled.attack && doubled.attack == 124,
                "Future start-of-turn value must not add a second pending buff before this combat")
    }

    @Test("Time Turning keeps a pending effect with leading keywords unsupported")
    func prefixedTimeTurningEffect() throws {
        var body = S.boardMinion(1, "BG35_431", attack: 2, health: 2)
        body.entity.enchantments = [try Self.gift(Self.timeTurning)]
        var request = try RecruitPlannerTests.request(board: [body],
            texts: ["BG35_431": "Windfury. At the end of your turn, this plays a Blood Gem on your minions. Repeat for each Bonus Keyword this has."])
        request.recruit!.evaluationVersion = 6
        Self.definition(Self.timeTurning, Self.timeText, request: &request)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        #expect(!RecruitEffects.combatProjection(state, context: context).limitations.isEmpty)
    }

    @Test("Affinity's observed countdown ticks once despite Drakkari, preserving a pair until the reward is due",
          arguments: [1, 2])
    func affinityCountdown(_ countdown: Int) throws {
        var gifted = S.boardMinion(1, "murloc", attack: 2, health: 2)
        gifted.entity.enchantments = [try Self.gift(Self.affinity, amount: countdown)]
        var request = try RecruitPlannerTests.request(
            board: [gifted, S.boardMinion(2, "murloc", attack: 2, health: 2),
                    S.boardMinion(3, "BG26_ICC_901", attack: 1, health: 5)],
            texts: ["BG26_ICC_901": "Your end of turn effects trigger twice."])
        request.recruit!.evaluationVersion = 6
        Self.definition(Self.affinity, Self.affinityText, request: &request)
        let context = request.recruit!, state = RecruitState(request: request, context: context)
        let projected = RecruitEffects.combatProjection(state, context: context)
        #expect(projected.limitations.isEmpty == (countdown == 2))
        #expect(projected.board.count == 3 && projected.hand.isEmpty)
    }

    @Test("A triple cannot erase unresolved Hammer aura metadata and manufacture permanent stats")
    func unknownHammerTriple() throws {
        for amount in [Optional<Int>.none, 5] {
            var request = try RecruitPlannerTests.request(
                board: [S.boardMinion(1, "pair", attack: 8, health: 3), S.boardMinion(2, "pair", attack: 8, health: 3)],
                shop: [S.shopMinion(3, attack: 2, health: 3, cardID: "pair")])
            try Self.addHammer(to: &request)
            request.board[0].entity.enchantments = [try Self.gift("BG36_MagicItem_403e", amount: amount)]
            request.recruit!.definitions["pair"]!.attack = 2
            request.recruit!.definitions["pair"]!.health = 3
            request.recruit!.definitions["pair"]!.dbfId = 10
            request.recruit!.definitions["pair"]!.battlegroundsPremiumDbfId = 11
            var golden = Card(id: "pair_G", dbfId: 11, name: "Golden pair")
            golden.type = "MINION"; golden.attack = 4; golden.health = 6; golden.battlegroundsNormalDbfId = 10
            request.recruit!.definitions[golden.id] = golden
            let context = request.recruit!, state = RecruitState(request: request, context: context)
            let action = try RecruitPlannerTests.action(.buy, state, context)
            #expect(RecruitPlanner.applying(action, to: state, context: context) == nil)
        }
    }

    @Test("Changed effect text and missing discard data remain unsupported")
    func unknownEffects() throws {
        var request = try RecruitPlannerTests.request(board: [S.boardMinion(1, "BG36_114", attack: 4, health: 6)],
            texts: ["BG36_114": Self.fleshlingText(golden: false)])
        request.recruit!.evaluationVersion = 6
        var context = request.recruit!
        #expect(!RecruitEffects.combatProjection(RecruitState(request: request, context: context), context: context).limitations.isEmpty)
        context.input.playerBoard.player.globalInfo["CardsDiscardedThisGame"] = 5
        context.definitions["BG36_114"]!.text = "At the end of your turn, give your left-most minion +3/+3."
        #expect(!RecruitEffects.combatProjection(RecruitState(request: request, context: context), context: context).limitations.isEmpty)
        for (id, changed) in [(Self.timeTurning, "This minion's end of turn effects also trigger at start of combat."),
                              (Self.affinity, "At the end of every 2 turns, summon a random minion of this type.")] {
            var plain = try RecruitPlannerTests.request(board: [S.boardMinion(1, "body", attack: 2, health: 2)])
            plain.recruit!.evaluationVersion = 6
            plain.board[0].entity.enchantments = [try Self.gift(id)]
            Self.definition(id, changed, request: &plain)
            #expect(!RecruitEffects.combatProjection(RecruitState(request: plain, context: plain.recruit!), context: plain.recruit!).limitations.isEmpty)
        }
        var hammer = try RecruitPlannerTests.request(board: [S.boardMinion(1, "envoy", attack: 10, health: 4)],
            hand: [S.spell(2, "BG36_301t")],
            texts: ["envoy": "Activate (0): Discard a card to get a random Tavern spell.", "BG36_301t": Self.sludgeText])
        try Self.addHammer(to: &hammer)
        hammer.recruit!.activations = [1: .init(ready: true, cost: 0)]
        hammer.recruit!.definitions[Self.hammer]!.text = "Your minions have +2 Attack. (Improved by each card you've discarded this game!)"
        let changedContext = hammer.recruit!, state = RecruitState(request: hammer, context: changedContext)
        #expect(RecruitPlanner.applying(try RecruitPlannerTests.action(.activate, state, changedContext),
            to: state, context: changedContext) == nil)
    }
}
