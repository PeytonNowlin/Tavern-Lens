import BGState
import EntityStore
import Testing
import TavernEngine

/// Seam 1 on synthetic logs: the simulator input the engine takes at combat start
/// (docs/research/simulator-input-mapping.md §4–§6), for the rules the captured games don't exercise.
@Suite("Combat simulator input on synthetic logs")
struct CombatInputSyntheticTests {
    static let local = SyntheticLog.localPlayerID
    static let slot = SyntheticLog.slotPlayerID
    static let opponentName = "Some Opponent"

    /// A lobby game in recruit, then combat against PlayerID 3; `local` adds to the local side
    /// during recruit, `opponent` to the opponent's combat copies. Ends at the 2022 1→0 edge.
    static func combat(
        local addLocal: (inout SyntheticLog) -> Void = { _ in },
        opponent addOpponent: (inout SyntheticLog) -> Void = { _ in }
    ) -> SyntheticLog {
        var log = LobbySyntheticTests.lobbyGame()
        addLocal(&log)
        log.endTaskList()
        log.combatSetup(bgTurn: 1, opponent: 3, name: opponentName, heroID: 800) { addOpponent(&$0) }
        log.combatStarts()
        return log
    }

    static func request(_ log: SyntheticLog, tribes: (any LobbyTribesProvider)? = nil, cards: CardDB? = nil) throws
        -> CombatSimulationRequest {
        var engine = TavernEngine(cards: cards, tribes: tribes)
        for line in log.lines { engine.ingest(line) }
        engine.finish()
        #expect(engine.combatRequests.count == 1)
        return try #require(engine.combatRequests.first)
    }

    static func minion(_ log: inout SyntheticLog, _ id: Int, _ cardID: String, controller: Int, position: Int,
                       atk: Int = 2, health: Int = 3, extra: [String] = []) {
        log.card(id, cardID, controller: controller, zone: "PLAY", position: position, atk: atk, health: health, extra: extra)
    }

    static func enchantment(_ log: inout SyntheticLog, _ id: Int, _ cardID: String, on target: Int, controller: Int,
                            extra: [String] = []) {
        log.card(id, cardID, controller: controller, zone: "PLAY", position: 0, type: "ENCHANTMENT",
                 extra: ["ATTACHED=\(target)"] + extra)
    }

    @Test("One request at the 2022 edge, for the combat's turn and opponent, with both boards in position order")
    func basics() throws {
        let log = Self.combat(local: { log in
            Self.minion(&log, 501, "BG_B", controller: Self.local, position: 2, atk: 5, health: 6, extra: ["DAMAGE=2", "TAUNT=1"])
            Self.minion(&log, 500, "BG_A", controller: Self.local, position: 1, extra: ["NUM_TURNS_IN_PLAY=4", "WINDFURY=3"])
        }, opponent: { log in
            Self.minion(&log, 811, "BG_Y", controller: Self.slot, position: 2, extra: ["NUM_TURNS_IN_PLAY=1", "DIVINE_SHIELD=1"])
            Self.minion(&log, 810, "BG_X", controller: Self.slot, position: 1)
        })
        let request = try Self.request(log)
        #expect(request.bgTurn == 1 && request.opponentPlayerID == 3)
        #expect(request.position.line == log.lines.count - 1)
        let input = request.input
        #expect(input.playerBoard.board.map(\.cardId) == ["BG_A", "BG_B"])
        let b = input.playerBoard.board[1]
        #expect(b.attack == 5 && b.health == 4 && b.maxHealth == 6 && b.taunt && !b.divineShield)
        #expect(input.playerBoard.board[0].windfury)  // WINDFURY=3 is mega-windfury
        #expect(input.opponentBoard.board.map(\.cardId) == ["BG_X", "BG_Y"])
        #expect(input.opponentBoard.board[1].divineShield)
        #expect(input.opponentBoard.player.cardId == "BG_HERO_3" && input.opponentBoard.player.entityId == 800)
        #expect(input.playerBoard.player.cardId == "TB_BaconShop_HERO_15" && input.playerBoard.player.hpLeft == 30)
        #expect(input.gameState.currentTurn == 1 && input.gameState.numberOfPlayersAlive == 8)
    }

    @Test("Opponent minions that have been in play for more than a turn are ghost or reconnect leftovers, left out")
    func staleOpponentMinions() throws {
        let log = Self.combat(opponent: { log in
            Self.minion(&log, 810, "BG_Fresh", controller: Self.slot, position: 1, extra: ["NUM_TURNS_IN_PLAY=1"])
            Self.minion(&log, 811, "BG_Stale", controller: Self.slot, position: 2, extra: ["NUM_TURNS_IN_PLAY=3"])
        })
        #expect(try Self.request(log).input.opponentBoard.board.map(\.cardId) == ["BG_Fresh"])
    }

    @Test("Enchantments come with their script data; removed ones are left out; magnetic ones bring their creator's")
    func enchantments() throws {
        let log = Self.combat(local: { log in
            Self.minion(&log, 500, "BG_A", controller: Self.local, position: 1)
            Self.enchantment(&log, 520, "BG_Buff_e", on: 500, controller: Self.local,
                             extra: ["TAG_SCRIPT_DATA_NUM_1=3", "TAG_SCRIPT_DATA_NUM_2=4"])
            Self.enchantment(&log, 521, "BG_Gone_e", on: 500, controller: Self.local)
            log.tag(521, "ZONE", "REMOVEDFROMGAME")
            // A magnetic minion (530, now gone) had been magnetized itself; its enchantment carries over.
            log.card(530, "BG_Magnet", controller: Self.local, zone: "REMOVEDFROMGAME", position: 0)
            Self.enchantment(&log, 531, "BG_Inner_e", on: 530, controller: Self.local, extra: ["MAGNETIC=1"])
            Self.enchantment(&log, 532, "BG_Magnet_e", on: 500, controller: Self.local, extra: ["MAGNETIC=1", "CREATOR=530"])
            // Polarizing Beatboxer also sends the magnetized card by dbfId, from its creator.
            log.card(540, "BG_Mech", controller: Self.local, zone: "REMOVEDFROMGAME", position: 0, extra: ["2787=77777"])
            Self.enchantment(&log, 541, "BG26_149e", on: 500, controller: Self.local, extra: ["CREATOR=540"])
        })
        let enchantments = try Self.request(log).input.playerBoard.board[0].enchantments
        #expect(enchantments.map(\.cardId) == ["BG_Buff_e", "BG_Magnet_e", "BG_Inner_e", "BG26_149e", "77777"])
        #expect(enchantments[0].tagScriptDataNum1 == 3 && enchantments[0].tagScriptDataNum2 == 4)
        #expect(enchantments[0].originEntityId == 520)
        #expect(enchantments[4].originEntityId == 540)
        #expect(enchantments.allSatisfy { $0.timing == 0 })
    }

    @Test("Hero power targets: Reborn Rites, Embrace Your Rage, Lock and Load and Rapid Reanimation")
    func heroPowerSpecialCases() throws {
        func info(_ hp: String, extra: [String] = [], setup: (inout SyntheticLog) -> Void = { _ in }) throws -> HeroPowerInfo? {
            let log = Self.combat(local: { log in
                Self.minion(&log, 500, "BG_A", controller: Self.local, position: 1)
                log.heroPower(300, hp, controller: Self.local, extra: extra)
                setup(&log)
            })
            return try Self.request(log).input.playerBoard.player.heroPowers.first?.info
        }
        #expect(try info("TB_BaconShop_HP_024", extra: ["EXHAUSTED=1", "CARD_TARGET=500"]) == .number(500))
        #expect(try info("TB_BaconShop_HP_024", extra: ["CARD_TARGET=500"]) == .number(0))  // not used
        #expect(try info("TB_BaconShop_HP_103", extra: ["1398=1"]) { log in
            log.card(510, "BG_Raged", controller: Self.local, zone: "HAND", position: 1, extra: ["CREATOR=300"])
        } == .cardID("BG_Raged"))
        let loaded = try info("BG22_HERO_000p_Alt", extra: ["EXHAUSTED=1"]) { log in
            log.card(510, "BG_Loaded", controller: Self.local, zone: "HAND", position: 1, atk: 4, health: 5, extra: ["CREATOR=300"])
        }
        guard case .entity(let minion)? = loaded else { Issue.record("Lock and Load: \(String(describing: loaded))"); return }
        #expect(minion.cardId == "BG_Loaded" && minion.attack == 4 && minion.health == 5)
        let marked = try info("BG25_HERO_103p") { log in
            Self.enchantment(&log, 520, "BG25_HERO_103pe", on: 500, controller: Self.local)
        }
        guard case .entity(let target)? = marked else { Issue.record("Rapid Reanimation: \(String(describing: marked))"); return }
        #expect(target.entityId == 500)
    }

    @Test("Choral Mrrrglr's buff is its enchantment's script data, halved when its creator is golden")
    func choral() throws {
        let log = Self.combat(local: { log in
            Self.minion(&log, 500, "BG26_354_G", controller: Self.local, position: 1, extra: ["PREMIUM=1"])
            Self.enchantment(&log, 520, "BG26_354e", on: 500, controller: Self.local,
                             extra: ["CREATOR=500", "TAG_SCRIPT_DATA_NUM_1=8", "TAG_SCRIPT_DATA_NUM_2=6"])
        })
        let info = try Self.request(log).input.playerBoard.player.globalInfo
        #expect(info["ChoralAttackBuff"] == 4 && info["ChoralHealthBuff"] == 3)
    }

    @Test("Counters, the Deity's stats and trinkets reach the input; placeholders don't")
    func mechanics() throws {
        let log = Self.combat(local: { log in
            log.localTag("3088", "7")
            log.localTag("BACON_BLOODGEMBUFFATKVALUE", "2")
            log.deitySigil(351, controller: Self.local, attack: 3, health: 3)
            log.localTag("4914", "12")
            log.localTag("4915", "9")
            log.trinket(348, "BG30_Trinket_1st", controller: Self.local, slot: 1)
            log.trinket(349, "BG36_MagicItem_404t", controller: Self.local, slot: 2, sdn1: 10, sdn2: 10)
        }, opponent: { log in
            log.playerEnchantment(806, "Bacon_TagTransferPlayerE", controller: Self.slot,
                                  attachedTo: SyntheticLog.slotPlayerEntityID, extra: ["4212=40"])
        })
        let input = try Self.request(log).input
        let player = input.playerBoard.player
        #expect(player.globalInfo["TavernSpellsCastThisGame"] == 7 && player.globalInfo["BloodGemAttackBonus"] == 2)
        #expect(player.secrets.map(\.cardId) == ["BG_OldGod"])
        #expect(player.secrets.first?.tags == ["4914": 12, "4915": 9])
        #expect(player.trinkets.map(\.cardId) == ["BG36_MagicItem_404t"])
        #expect(player.trinkets.first.map { [$0.scriptDataNum1, $0.scriptDataNum2, $0.scriptDataNum6] } == [10, 10, 2])
        #expect(input.opponentBoard.player.globalInfo["GoldSpentThisGame"] == 40)
    }

    @Test("A dead opponent (ghost) is sent as their real hero with no health left")
    func ghost() throws {
        var log = LobbySyntheticTests.lobbyGame()
        log.tag(153, "DAMAGE", "35")  // PlayerID 3's lobby hero
        log.endTaskList()
        log.turn(2)
        log.gameTag("2022", "1")
        log.slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", "3", name: Self.opponentName)
        log.card(800, "TB_BaconShop_HERO_KelThuzad", controller: Self.slot, zone: "PLAY", position: 0, type: "HERO",
                 health: 30, extra: ["PLAYER_ID=3"])
        log.slotTag("HERO_ENTITY", "800", name: Self.opponentName)
        log.endTaskList()
        log.combatStarts()
        let player = try Self.request(log).input.opponentBoard.player
        #expect(player.cardId == "BG_HERO_3")
        #expect(player.hpLeft <= 0)
        #expect(player.entityId == 800)
    }

    @Test("The anomaly goes as its dbfId, for the bundle to resolve")
    func anomaly() throws {
        let log = Self.combat(local: { $0.gameTag("2897", "123456") })
        #expect(try Self.request(log).input.gameState.anomalyDbfIds == [123_456])
    }

    // MARK: - Tribes

    struct FixedTribes: LobbyTribesProvider {
        var tribes: Set<HS.Race>?
        func lobbyTribes(store: EntityStore, snapshot: BGSnapshot) -> Set<HS.Race>? { tribes }
    }

    @Test("The injected tribe provider sets validTribes, as Race numbers")
    func injectedTribes() throws {
        let tribes: Set<HS.Race> = [.beast, .demon, .undead, .quilboar, .aberration]
        let request = try Self.request(Self.combat(), tribes: FixedTribes(tribes: tribes))
        #expect(request.input.gameState.validTribes == [11, 15, 20, 43, 126])
        #expect(request.tribesKnown)
        let unknown = try Self.request(Self.combat(), tribes: FixedTribes(tribes: nil))
        #expect(unknown.input.gameState.validTribes == nil && !unknown.tribesKnown)
    }

    @Test("Without a provider, the tribes of single-tribe pool minions seen, once all five are known")
    func seenPoolMinionTribes() throws {
        var cards: [Card] = []
        func add(_ id: String, _ races: [String], pool: Bool = true) {
            var card = Card(id: id, dbfId: 1000 + cards.count, name: id)
            card.type = "MINION"
            card.races = races
            card.isBattlegroundsPoolMinion = pool
            cards.append(card)
        }
        let singles = [("BG_Beast", "BEAST"), ("BG_Demon", "DEMON"), ("BG_Undead", "UNDEAD"), ("BG_Quil", "QUILBOAR")]
        for (id, race) in singles { add(id, [race]) }
        add("BG_Dual", ["NAGA", "PIRATE"])
        add("BG_Aberr", ["ABERRATION"])
        add("BG_NotPool", ["MURLOC"], pool: false)
        let db = CardDB(build: nil, cards: cards)

        func shop(_ ids: [String]) -> SyntheticLog {
            Self.combat(local: { log in
                for (index, id) in ids.enumerated() {
                    log.shopCard(600 + index, id, position: index + 1, extra: ["IS_BACON_POOL_MINION=1"])
                }
            })
        }
        let four = try Self.request(shop(singles.map(\.0) + ["BG_Dual", "BG_NotPool"]), cards: db)
        #expect(four.input.gameState.validTribes == nil)
        let five = try Self.request(shop(singles.map(\.0) + ["BG_Dual", "BG_NotPool", "BG_Aberr"]), cards: db)
        #expect(five.input.gameState.validTribes == [11, 15, 20, 43, 126])
    }
}
