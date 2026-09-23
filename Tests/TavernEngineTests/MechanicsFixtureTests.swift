import Foundation
import Testing
import TavernEngine

/// Seam 1 on the captured games: the Deity, trinkets, hero powers, counters and damage cap
/// against docs/research/simulator-input-mapping.md §8. Skipped when the fixtures are absent.
@Suite("Battlegrounds mechanics in captured games")
struct MechanicsFixtureTests {
    /// The simulator's own cap formula, which matched the log at every change (mapping §5.1).
    static func formulaCap(bgTurn: Int) -> Int { bgTurn < 4 ? 5 : bgTurn < 8 ? 10 : 15 }

    static func endOfRecruit(_ timeline: [TimelineEntry], _ bgTurn: Int) throws -> GameView {
        try #require(GoldenHarness.Checkpoint.endOfPhase(bgTurn, .recruit).select(from: timeline)?.state.game)
    }

    /// The opponent's mechanics as captured at the start of the combat of `bgTurn`.
    static func seenAt(_ timeline: [TimelineEntry], bgTurn: Int) -> (playerID: Int, mechanics: MechanicsView?)? {
        for entry in timeline {
            guard let lobby = entry.state.game?.lobby else { continue }
            if let seen = lobby.first(where: { $0.lastSeenBoard?.bgTurn == bgTurn }) {
                return (seen.playerID, seen.lastSeenBoard?.mechanics)
            }
        }
        return nil
    }

    @Test(
        "Full game: damage cap, Deity and trinkets per turn; the turn-11 combat matches the worked example",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGame() throws {
        let result = try FixtureReplays.result(Fixtures.fullGame)
        let timeline = result.timeline

        for bgTurn in 1...12 {
            let game = try Self.endOfRecruit(timeline, bgTurn)
            let mechanics = try #require(game.mechanics)
            #expect(mechanics.damageCap == Self.formulaCap(bgTurn: bgTurn), "turn \(bgTurn)")
            // The cap turns off once four or fewer heroes are left.
            #expect(mechanics.damageCapEnabled == (mechanics.playersAlive > 4), "turn \(bgTurn)")
            #expect(mechanics.deityDbfID == 130_610)  // C'Thun
            let local = try #require(game.player?.mechanics)
            #expect(local.deity?.dbfID == 130_610, "turn \(bgTurn)")
            #expect(local.heroPowers.map(\.cardID) == ["TB_BaconShop_HP_010"], "turn \(bgTurn)")
        }

        // Local, end of recruit 11 (the §8.1 snapshot follows it): Deity 236/222, both Corrupted Batons.
        let turn11 = try Self.endOfRecruit(timeline, 11)
        let local = try #require(turn11.player?.mechanics)
        #expect(local.deity == DeityView(dbfID: 130_610, attack: 236, health: 222, progress: 3))
        #expect(local.trinkets.map(\.cardID) == ["BG36_MagicItem_404", "BG36_MagicItem_404t"])
        #expect(local.trinkets.map(\.slot) == [1, 2])
        #expect(local.trinkets.map { Array(($0.scriptData ?? []).prefix(2)) } == [[4, 4], [10, 10]])
        #expect(local.counters[3088] == 20 && local.counters[1780] == 20 && local.counters[4212] == 86)
        #expect(local.counters[4639] == 24 && local.counters[4799] == 2 && local.counters[4768] == 2)
        #expect(!local.countersFromTagTransfer)
        #expect(try Self.endOfRecruit(timeline, 11).mechanics?.playersAlive == 6)

        // Opponent (Drest'agath, P7) at the turn-11 combat: Deity 230/338, Corrupted Baton and
        // Hammer of Twilight 34/17, counters from the tag transfer.
        let seen = try #require(Self.seenAt(timeline, bgTurn: 11))
        #expect(seen.playerID == 7)
        let opponent = try #require(seen.mechanics)
        #expect(opponent.countersFromTagTransfer)
        #expect(opponent.deity == DeityView(dbfID: 130_610, attack: 230, health: 338, progress: 3))
        #expect(opponent.trinkets.map(\.cardID) == ["BG36_MagicItem_404", "BG36_MagicItem_403t"])
        #expect(opponent.trinkets.map { Array(($0.scriptData ?? []).prefix(2)) } == [[4, 4], [34, 17]])
        #expect(opponent.heroPowers == [HeroPowerView(cardID: "BG36_HERO_000p", used: true)])
        #expect(opponent.counters[3088] == 32 && opponent.counters[4212] == 101)
        #expect(opponent.counters[3873] == 5 && opponent.counters[4639] == 13)
        #expect(opponent.counters[4799] == 1 && opponent.counters[4768] == 16)
        // Spells played (1780) isn't set on the opponent side.
        #expect(opponent.counters[1780] == nil)

        // Every combat's opponent counters came from the tag transfer, and every opponent had the Deity.
        for bgTurn in 1...12 {
            let seen = try #require(Self.seenAt(timeline, bgTurn: bgTurn), "turn \(bgTurn)")
            let mechanics = try #require(seen.mechanics, "turn \(bgTurn)")
            #expect(mechanics.countersFromTagTransfer, "turn \(bgTurn)")
            #expect(mechanics.deity?.dbfID == 130_610, "turn \(bgTurn)")
            #expect(mechanics.heroPowers.count == 1, "turn \(bgTurn)")
        }
    }

    @Test(
        "Counters are recorded by numeric tag ID even where the client prints no name",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func unnamedCounters() throws {
        let result = try FixtureReplays.result(Fixtures.fullGame)
        let counters = try #require(result.timeline.last?.state.game?.player?.mechanics?.counters)

        // The local Player entity at end of log, with tag names as the pinned enums resolve them.
        let player = try #require(result.entities.first { row in
            row.tags.contains { $0.tag == "CARDTYPE" && $0.value == "PLAYER" }
                && row.tags.contains { $0.tag == "CONTROLLER" && $0.value == "6" }
        })
        for number in [3088, 4212, 4639, 4768, 4799] {
            let tag = try #require(player.tags.first { $0.number == number }, "tag \(number)")
            #expect(tag.tag == String(number), "tag \(number) has no name in the pinned enums")
            #expect(counters[number].map(String.init) == tag.value, "tag \(number)")
        }
        // A named counter lands under its number too.
        let named = try #require(player.tags.first { $0.number == 1780 })
        #expect(named.tag == "NUM_SPELLS_PLAYED_THIS_GAME")
        #expect(counters[1780].map(String.init) == named.value)
    }

    @Test(
        "Truncated game: trinket placeholders never show, the damage cap and Deity per turn match the log",
        .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func truncatedGame() throws {
        let result = try FixtureReplays.result(Fixtures.truncatedGame)
        let timeline = result.timeline

        // The placeholders exist in the log, but no view ever shows a trinket.
        #expect(result.entities.contains { $0.cardID == "BG30_Trinket_1st" })
        for entry in timeline {
            let game = entry.state.game
            #expect(game?.player?.mechanics?.trinkets.isEmpty ?? true)
            #expect(game?.combatOpponentMechanics?.trinkets.isEmpty ?? true)
        }

        for bgTurn in 1...4 {
            let game = try Self.endOfRecruit(timeline, bgTurn)
            #expect(game.mechanics?.damageCap == Self.formulaCap(bgTurn: bgTurn), "turn \(bgTurn)")
            #expect(game.mechanics?.deityDbfID == 132_532)  // Y'Shaarj
        }

        // §8.2: Kith'ix's hero power has sdn3 = 2; Y'Shaarj at 3/3 locally and 5/5 on Farseer Nobundo (P5).
        let local = try #require(try Self.endOfRecruit(timeline, 4).player?.mechanics)
        #expect(local.deity == DeityView(dbfID: 132_532, attack: 3, health: 3, progress: 3))
        #expect(local.heroPowers.map(\.cardID) == ["BG36_HERO_002p"])
        #expect(local.heroPowers.first?.scriptData?[2] == 2)
        let seen = try #require(Self.seenAt(timeline, bgTurn: 4))
        #expect(seen.playerID == 5)
        #expect(seen.mechanics?.deity == DeityView(dbfID: 132_532, attack: 5, health: 5, progress: 3))
        #expect(seen.mechanics?.countersFromTagTransfer == true)
    }
}
