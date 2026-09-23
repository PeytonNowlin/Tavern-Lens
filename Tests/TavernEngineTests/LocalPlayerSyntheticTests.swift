import Testing
import TavernEngine

/// Seam 1 on synthetic logs: the local player's stats, board, hand and Bob's shop,
/// covered without the private fixtures.
@Suite("Local player state on synthetic logs")
struct LocalPlayerSyntheticTests {
    static let local = SyntheticLog.localPlayerID
    static let hero = SyntheticLog.pickedHeroID

    /// A game with the hero picked and the first recruit phase started.
    static func recruiting() -> SyntheticLog {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.pickHero()
        log.turn(1)
        return log
    }

    static func lastGame(_ log: SyntheticLog) throws -> GameView {
        try #require(TavernEngine.replay(lines: log.lines).timeline.last?.state.game)
    }

    static func render(_ cards: [CardView]) -> [String] { cards.map(LocalPlayerFixtureTests.render) }

    @Test("HP is health − damage + armor; gold, cap, tier and triples come from the hero and Player entities")
    func stats() throws {
        var log = Self.recruiting()
        log.tag(Self.hero, "ARMOR", "15")
        log.tag(Self.hero, "DAMAGE", "3")
        log.tag(Self.hero, "PLAYER_TECH_LEVEL", "2")
        log.tag(Self.hero, "PLAYER_TRIPLES", "1")
        log.localTag("RESOURCES", "4")
        log.localTag("RESOURCES_USED", "3")
        log.localTag("TEMP_RESOURCES", "1")
        log.localTag("3148", "10")
        log.localTag("MAXRESOURCES", "99")
        log.endTaskList()

        let player = try #require(try Self.lastGame(log).player)
        #expect(player.hero == HeroStatsView(hp: 42, health: 30, damage: 3, armor: 15, triples: 1))
        #expect(player.gold == GoldView(available: 2, thisTurn: 4, used: 3, temporary: 1, cap: 10))
        #expect(player.tier == 2)
    }

    @Test("Before the hero pick there are no hero stats, and the hero options aren't in the hand")
    func heroPickPhase() throws {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        log.card(90, "BG20_HERO_283", controller: Self.local, zone: "HAND", position: 1, type: "HERO", health: 30)
        log.card(91, "BG35_HERO_001", controller: Self.local, zone: "HAND", position: 2, type: "HERO", health: 30)
        log.endTaskList()

        let game = try Self.lastGame(log)
        #expect(game.phase == .heroPick)
        #expect(game.player?.hero == nil)
        #expect(game.player?.hand == [])
    }

    @Test("Phase follows TURN: hero pick, then odd is recruit and even is combat")
    func phases() {
        let result = TavernEngine.replay(lines: SyntheticLog.soloGame(bgTurns: 2, complete: false).lines)
        var phases: [BGPhase] = []
        for phase in result.timeline.compactMap({ $0.state.game?.phase }) where phases.last != phase {
            phases.append(phase)
        }
        #expect(phases == [.heroPick, .recruit, .combat, .recruit, .combat])
    }

    @Test("The board is the local minions in PLAY by position, with stats, golden and keywords; nothing else")
    func board() throws {
        var log = Self.recruiting()
        log.card(201, "BG_B", controller: Self.local, zone: "PLAY", position: 2, atk: 3, health: 4, extra: ["DAMAGE=1", "REBORN=1"])
        log.card(200, "BG_A_G", controller: Self.local, zone: "PLAY", position: 1, atk: 6, health: 4, extra: ["PREMIUM=1", "TAUNT=1", "DIVINE_SHIELD=1"])
        // Not minions on the board: an enchantment, a hero power, and a SETASIDE preview copy.
        log.card(202, "BG_Ench", controller: Self.local, zone: "PLAY", position: 0, type: "ENCHANTMENT")
        log.card(203, "TB_BaconShop_HP_010", controller: Self.local, zone: "PLAY", position: 0, type: "HERO_POWER")
        log.card(204, "BG_Preview", controller: Self.local, zone: "SETASIDE", position: 0, atk: 9, health: 9, extra: ["COPIED_FROM_ENTITY_ID=150"])
        log.endTaskList()

        let player = try #require(try Self.lastGame(log).player)
        #expect(player.board.map(\.cardID) == ["BG_A_G", "BG_B"])
        #expect(Self.render(player.board) == ["*6/4 T,DS", "3/3 R"])
        #expect(player.board.first?.golden == true)
        #expect(player.board.first?.kind == .minion)
    }

    @Test("A tavern spell bought into the hand is recognised by CARDTYPE=SPELL")
    func tavernSpellInHand() throws {
        var log = Self.recruiting()
        log.shopCard(300, "BG28_503", position: 1, type: "BATTLEGROUND_SPELL")
        log.card(301, "BG_Minion", controller: Self.local, zone: "HAND", position: 2, atk: 2, health: 3)
        log.endTaskList()
        #expect(try Self.lastGame(log).shop.cards.map(\.kind) == [.tavernSpell])

        // Buying: the card changes controller and zone, and its type is redefined.
        log.tag(300, "CONTROLLER", String(Self.local))
        log.tag(300, "ZONE", "HAND")
        log.tag(300, "ZONE_POSITION", "1")
        log.tag(300, "CARDTYPE", "SPELL", suffix: " DEF CHANGE")
        log.endTaskList()

        let game = try Self.lastGame(log)
        #expect(game.shop.cards.isEmpty)
        let hand = try #require(game.player?.hand)
        #expect(hand.map(\.cardID) == ["BG28_503", "BG_Minion"])
        #expect(hand.map(\.kind) == [.tavernSpell, .minion])
        #expect(Self.render(hand) == ["spell", "2/3"])
    }

    @Test("The shop is the bartender slot's minions and spells in PLAY during recruit, frozen when every card is")
    func shop() throws {
        var log = Self.recruiting()
        log.card(400, "TB_BaconShopBob_SKIN_AN", controller: SyntheticLog.slotPlayerID, zone: "PLAY", position: 0, type: "HERO", health: 40)
        log.shopCard(402, "BG_Two", position: 2, atk: 3, health: 3, extra: ["BATTLECRY=1", "TECH_LEVEL=2"])
        log.shopCard(401, "BG_One", position: 1, atk: 1, health: 1, extra: ["DEATHRATTLE=1", "TECH_LEVEL=1"])
        log.shopCard(403, "BG_Spell", position: 3, type: "BATTLEGROUND_SPELL")
        log.endTaskList()

        var shop = try Self.lastGame(log).shop
        #expect(shop.cards.map(\.cardID) == ["BG_One", "BG_Two", "BG_Spell"])
        #expect(Self.render(shop.cards) == ["1/1 DR", "3/3 BC", "spell"])
        #expect(shop.cards.map(\.tier) == [1, 2, nil])
        #expect(!shop.isFrozen)

        for id in 401...403 { log.tag(id, "FROZEN", "1") }
        log.endTaskList()
        shop = try Self.lastGame(log).shop
        #expect(shop.isFrozen)
        #expect(shop.cards.allSatisfy { $0.frozen })
    }

    @Test("The opponent's combat board, held by the same slot, never shows as the shop")
    func combatBoardIsNotShop() throws {
        var log = Self.recruiting()
        log.shopCard(500, "BG_ShopMinion", position: 1, atk: 2, health: 2)
        log.endTaskList()

        // TURN turns even before the client clears the shop.
        log.turn(2)
        log.tag(500, "ZONE", "REMOVEDFROMGAME")
        log.endTaskList()
        // Combat: the slot now fights as the opponent, and their minions are in PLAY under it.
        log.slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", "3", name: "Opponent Display Name")
        log.shopCard(600, "BG_Opponent", position: 1, atk: 9, health: 9)
        log.endTaskList()
        // Even if a recruit phase starts before the slot stops fighting, its board isn't for sale.
        log.turn(3)

        let result = TavernEngine.replay(lines: log.lines)
        let games = result.timeline.compactMap(\.state.game)
        #expect(games.contains { $0.shop.cards.map(\.cardID) == ["BG_ShopMinion"] })
        #expect(games.allSatisfy { !$0.shop.cards.map(\.cardID).contains("BG_Opponent") })
        #expect(games.filter { $0.phase == .combat }.allSatisfy { $0.shop.cards.isEmpty })

        // Once the slot stops fighting and the combat board is gone, the new shop shows.
        log.slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", "0")
        log.tag(600, "ZONE", "REMOVEDFROMGAME")
        log.shopCard(501, "BG_NewShop", position: 1, atk: 1, health: 2)
        log.endTaskList()
        #expect(try Self.lastGame(log).shop.cards.map(\.cardID) == ["BG_NewShop"])
    }

    @Test("Only settled task-list states are emitted: a card buffed in the same batch never shows unbuffed")
    func onlyBatchEnds() throws {
        var log = Self.recruiting()
        log.shopCard(700, "BG_Cyclone", position: 1, atk: 2, health: 1)
        log.tag(700, "ATK", "3")
        log.tag(700, "HEALTH", "2")
        log.endTaskList()

        let result = TavernEngine.replay(lines: log.lines)
        let shops = result.timeline.compactMap { $0.state.game.map { Self.render($0.shop.cards) } }
        #expect(shops.last == ["3/2"])
        #expect(!shops.contains(["2/1"]))
        let taskListEnds = Set(log.lines.indices.filter { log.lines[$0].contains("EndCurrentTaskList") }.map { $0 + 1 })
        #expect(result.timeline.allSatisfy { taskListEnds.contains($0.position.line) || $0.position.line == log.lines.count })
    }
}
