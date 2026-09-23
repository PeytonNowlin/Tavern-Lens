import Testing
import TavernEngine

/// Seam 1 on synthetic logs: hero powers, trinkets, the Deity, quests, per-player counters
/// and the damage cap (docs/research/simulator-input-mapping.md §4–§6), without the fixtures.
@Suite("Battlegrounds mechanics on synthetic logs")
struct MechanicsSyntheticTests {
    static let local = SyntheticLog.localPlayerID
    static let slot = SyntheticLog.slotPlayerID
    static let opponentName = "Some Opponent"

    static func lastGame(_ log: SyntheticLog) throws -> GameView {
        try #require(TavernEngine.replay(lines: log.lines).timeline.last?.state.game)
    }

    static func localMechanics(_ log: SyntheticLog) throws -> MechanicsView {
        try #require(try lastGame(log).player?.mechanics)
    }

    @Test("Hero powers show whether they were used, by EXHAUSTED or BACON_HERO_POWER_ACTIVATED, with their script data")
    func heroPowers() throws {
        var log = LobbySyntheticTests.lobbyGame()
        log.heroPower(300, "TB_BaconShop_HP_010", controller: Self.local, extra: ["EXHAUSTED=1"])
        log.heroPower(301, "TB_BaconShop_HP_086", controller: Self.local, extra: ["1398=1", "TAG_SCRIPT_DATA_NUM_1=4"])
        log.heroPower(302, "BG36_HERO_002p", controller: Self.local, extra: ["TAG_SCRIPT_DATA_NUM_3=2"])
        log.endTaskList()

        let powers = try Self.localMechanics(log).heroPowers
        #expect(powers == [
            HeroPowerView(cardID: "TB_BaconShop_HP_010", used: true),
            HeroPowerView(cardID: "TB_BaconShop_HP_086", used: true, scriptData: [4, 0, 0, 0, 0, 0]),
            HeroPowerView(cardID: "BG36_HERO_002p", used: false, scriptData: [0, 0, 2, 0, 0, 0]),
        ])
    }

    @Test("Trinket placeholders are left out until the pick reveals the real card; trinkets are lesser first")
    func trinkets() throws {
        var log = LobbySyntheticTests.lobbyGame()
        log.trinket(349, "BG30_Trinket_2nd", controller: Self.local, slot: 2)
        log.trinket(348, "BG30_Trinket_1st", controller: Self.local, slot: 1)
        log.endTaskList()
        #expect(try Self.localMechanics(log).trinkets.isEmpty)

        // The same slot entities are revealed as the picked trinkets.
        log.power("SHOW_ENTITY - Updating Entity=[entityName=Greater Trinket id=349 zone=PLAY zonePos=0 cardId=BG30_Trinket_2nd player=\(Self.local)] CardID=BG36_MagicItem_404t")
        log.power("tag=TAG_SCRIPT_DATA_NUM_1 value=10", indent: 8)
        log.power("tag=TAG_SCRIPT_DATA_NUM_2 value=10", indent: 8)
        log.endTaskList()
        #expect(try Self.localMechanics(log).trinkets == [
            TrinketView(cardID: "BG36_MagicItem_404t", slot: 2, scriptData: [10, 10, 0, 0, 0, 2]),
        ])

        log.power("SHOW_ENTITY - Updating Entity=[entityName=Lesser Trinket id=348 zone=PLAY zonePos=0 cardId=BG30_Trinket_1st player=\(Self.local)] CardID=BG36_MagicItem_404")
        log.power("tag=TAG_SCRIPT_DATA_NUM_1 value=4", indent: 8)
        log.power("tag=TAG_SCRIPT_DATA_NUM_2 value=4", indent: 8)
        log.endTaskList()
        #expect(try Self.localMechanics(log).trinkets.map(\.cardID) == ["BG36_MagicItem_404", "BG36_MagicItem_404t"])
    }

    @Test("The Deity's stats come from the Player's tags 4914/4915, printed by name or number, else the sigil's script data")
    func deity() throws {
        var log = LobbySyntheticTests.lobbyGame()
        log.deitySigil(351, controller: Self.local, attack: 5, health: 5)
        log.endTaskList()
        #expect(try Self.localMechanics(log).deity == DeityView(dbfID: 130_610, attack: 5, health: 5, progress: 3))

        log.localTag("BACON_OLD_GOD_ATTACK", "236")
        log.localTag("4915", "222")
        log.endTaskList()
        let mechanics = try Self.localMechanics(log)
        #expect(mechanics.deity == DeityView(dbfID: 130_610, attack: 236, health: 222, progress: 3))
        // The sigil is the Deity, not a secret.
        #expect(mechanics.secrets.isEmpty)
    }

    @Test("Quests, quest rewards and other secrets are told apart")
    func questsAndSecrets() throws {
        var log = LobbySyntheticTests.lobbyGame()
        log.card(400, "BG_Quest", controller: Self.local, zone: "SECRET", position: 0, type: "SPELL",
                 extra: ["QUEST=1", "QUEST_PROGRESS=2", "QUEST_PROGRESS_TOTAL=6", "QUEST_REWARD_DATABASE_ID=777"])
        log.card(401, "BG_BobQuest", controller: Self.local, zone: "SECRET", position: 0, type: "SPELL", extra: ["BACON_IS_BOB_QUEST=1"])
        log.card(402, "BG_Secret", controller: Self.local, zone: "SECRET", position: 0, type: "SPELL")
        log.card(403, "BG_Reward", controller: Self.local, zone: "PLAY", position: 0, type: "BATTLEGROUND_QUEST_REWARD",
                 extra: ["TAG_SCRIPT_DATA_NUM_1=3"])
        log.endTaskList()

        let mechanics = try Self.localMechanics(log)
        #expect(mechanics.quests == [QuestView(cardID: "BG_Quest", progress: 2, progressTotal: 6, rewardDbfID: 777)])
        #expect(mechanics.secrets == ["BG_Secret"])
        #expect(mechanics.questRewards == ["BG_Reward"])
    }

    @Test("Counters are keyed by numeric tag ID, whether the client printed a name or a bare number")
    func countersByNumber() throws {
        var log = LobbySyntheticTests.lobbyGame()
        log.localTag("3088", "20")  // tavern spells played: no name in enums.json
        log.localTag("4212", "86")  // gold spent: no name
        log.localTag("TAVERN_SPELL_ATTACK_INCREASE", "2")  // named: 3989
        log.localTag("3990", "3")
        log.localTag("BACON_BLOODGEMBUFFATKVALUE", "2")  // 1844
        log.localTag("2827", "4")
        log.localTag("4639", "0")  // zero counters are left out
        log.localTag("99999", "5")  // not a counter the simulator reads
        log.endTaskList()

        let mechanics = try Self.localMechanics(log)
        #expect(mechanics.counters == [3088: 20, 4212: 86, 3989: 2, 3990: 3, 1844: 2, 2827: 4])
        #expect(mechanics.tavernSpellBuff == StatBuffView(attack: 2, health: 3))
        #expect(mechanics.bloodGem == StatBuffView(attack: 2, health: 4))
        #expect(!mechanics.countersFromTagTransfer)

        // The blood gem enchantment wins where it is larger (HDT's max rule).
        log.playerEnchantment(410, "BG26_159pe", controller: Self.local, attachedTo: SyntheticLog.localPlayerEntityID,
                              extra: ["TAG_SCRIPT_DATA_NUM_1=5", "TAG_SCRIPT_DATA_NUM_2=1"])
        log.endTaskList()
        #expect(try Self.localMechanics(log).bloodGem == StatBuffView(attack: 5, health: 4))
    }

    @Test("The damage cap, anomaly and Deity come from the game entity, by name or number")
    func gameMechanics() throws {
        var log = LobbySyntheticTests.lobbyGame()
        #expect(try Self.lastGame(log).mechanics == GameMechanicsView(damageCap: nil, damageCapEnabled: false, playersAlive: 8))

        log.gameTag("BACON_COMBAT_DAMAGE_CAP", "5")
        log.gameTag("3403", "1")
        log.gameTag("4902", "130610")
        log.gameTag("BACON_GLOBAL_ANOMALY_DBID", "4242")
        log.tag(151, "DAMAGE", "30")  // P1 dies
        log.endTaskList()
        #expect(try Self.lastGame(log).mechanics == GameMechanicsView(
            damageCap: 5, damageCapEnabled: true, anomalyDbfID: 4242, deityDbfID: 130_610, playersAlive: 7
        ))

        log.gameTag("2089", "10")
        log.endTaskList()
        #expect(try Self.lastGame(log).mechanics?.damageCap == 10)
    }

    /// A combat against P3 whose counters differ between the slot Player (stale values)
    /// and the opponent's tag-transfer enchantment.
    static func combatAgainstP3(withTransfer: Bool) -> SyntheticLog {
        var log = LobbySyntheticTests.lobbyGame()
        // The slot Player still carries values from an earlier combat.
        log.slotTag("3088", "5")
        log.slotTag("4212", "40")
        log.endTaskList()
        log.combatSetup(bgTurn: 1, opponent: 3, name: opponentName, heroID: 800) { log in
            log.heroPower(801, "BG36_HERO_000p", controller: slot, extra: ["EXHAUSTED=1"])
            log.trinket(803, "BG36_MagicItem_403t", controller: slot, slot: 2, sdn1: 34, sdn2: 17)
            log.trinket(802, "BG36_MagicItem_404", controller: slot, slot: 1, sdn1: 4, sdn2: 4)
            log.trinket(804, "BG30_Trinket_1st", controller: slot, slot: 1)
            log.deitySigil(805, controller: slot, attack: 230, health: 338)
            log.slotTag("BACON_OLD_GOD_ATTACK", "230", name: opponentName)
            log.slotTag("BACON_OLD_GOD_HEALTH", "338", name: opponentName)
            // The game rewrites the tavern spell buff on the slot after the transfer.
            log.slotTag("3989", "3", name: opponentName)
            if withTransfer {
                log.playerEnchantment(806, "Bacon_TagTransferPlayerE", controller: slot,
                                      attachedTo: SyntheticLog.slotPlayerEntityID,
                                      extra: ["3088=32", "4212=101", "3989=1", "4768=16"])
            }
        }
        return log
    }

    @Test("Opponent counters come from the tag-transfer enchantment first, the tavern spell buff from the Player")
    func opponentPrefersTagTransfer() throws {
        var log = Self.combatAgainstP3(withTransfer: true)
        log.combatStarts()

        let game = try Self.lastGame(log)
        let opponent = try #require(game.combatOpponentMechanics)
        #expect(opponent.countersFromTagTransfer)
        #expect(opponent.counters == [3088: 32, 4212: 101, 3989: 3, 4768: 16])
        #expect(opponent.tavernSpellBuff == StatBuffView(attack: 3, health: 0))
        #expect(opponent.deity == DeityView(dbfID: 130_610, attack: 230, health: 338, progress: 3))
        #expect(opponent.trinkets == [
            TrinketView(cardID: "BG36_MagicItem_404", slot: 1, scriptData: [4, 4, 0, 0, 0, 1]),
            TrinketView(cardID: "BG36_MagicItem_403t", slot: 2, scriptData: [34, 17, 0, 0, 0, 2]),
        ])
        #expect(opponent.heroPowers == [HeroPowerView(cardID: "BG36_HERO_000p", used: true)])

        // The same mechanics are kept with the last-seen board, after the slot goes back to Bob.
        log.endCombat(board: [], nextOpponent: 4)
        log.turn(3)
        let later = try Self.lastGame(log)
        #expect(later.combatOpponentMechanics == nil)
        let entry = try #require(later.lobby.first { $0.playerID == 3 })
        #expect(entry.lastSeenBoard?.mechanics == opponent)
    }

    @Test("Without a tag-transfer enchantment, opponent counters fall back to the slot Player")
    func opponentWithoutTagTransfer() throws {
        var log = Self.combatAgainstP3(withTransfer: false)
        log.combatStarts()

        let opponent = try #require(try Self.lastGame(log).combatOpponentMechanics)
        #expect(!opponent.countersFromTagTransfer)
        #expect(opponent.counters == [3088: 5, 4212: 40, 3989: 3])
    }

    @Test("Outside combat the bartender slot's mechanics are Bob's, so no opponent mechanics are shown")
    func noOpponentMechanicsOutsideCombat() throws {
        var log = LobbySyntheticTests.lobbyGame()
        log.slotTag("3088", "5")
        log.heroPower(820, "TB_BaconShopBob_HP", controller: Self.slot)
        log.endTaskList()
        let game = try Self.lastGame(log)
        #expect(game.combatOpponentMechanics == nil)
        #expect(game.player?.mechanics?.heroPowers.isEmpty == true)
    }
}
