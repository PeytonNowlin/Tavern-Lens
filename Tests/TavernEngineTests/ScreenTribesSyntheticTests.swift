import Foundation
import HSData
import Testing
import TavernEngine

/// Seam 1 with a screen reading (#14): the hero-pick banner settles the tribes at once, and
/// when the log later contradicts it, the overlay flags it and falls back to the inference.
@Suite("Screen-read tribes on synthetic logs")
struct ScreenTribesSyntheticTests {
    static let utc = TimeZone(identifier: "UTC")!
    static let banner: [HS.Race] = [.aberration, .demon, .elemental, .murloc, .quilboar]

    /// Tier-1 minions whose only gate is `tribe`: each draw is evidence for it.
    static func tierOne(_ tribe: HS.Race) -> [String] {
        PoolFixture.pool.minions.values.filter { $0.tier == 1 && $0.lobbyGate == [tribe] && !$0.isOutOfRotation }
            .map(\.cardID).sorted()
    }

    static func confirmed(_ engine: TavernEngine) -> [String] {
        (engine.state.game?.tribes?.tribes ?? []).filter { $0.confidence == .confirmed }.map(\.tribe).sorted()
    }

    @Test("A complete reading at the hero pick settles the tribes before any shop")
    func settlesAtHeroPick() throws {
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        var engine = TavernEngine(pool: PoolFixture.pool, timeZone: Self.utc)
        for line in log.lines { engine.ingest(line) }
        #expect(engine.state.game?.phase == .heroPick)
        #expect(engine.state.game?.tribes?.isResolved == false)

        engine.ingestScreenTribes(ScreenTribeReading(tribes: Self.banner))
        let tribes = try #require(engine.state.game?.tribes)
        #expect(tribes.isResolved)
        #expect(tribes.source == .screen)
        #expect(!tribes.screenConflict)
        #expect(Self.confirmed(engine) == Self.banner.map(\.description).sorted())
    }

    @Test("When the log contradicts the reading, the overlay flags it and shows the inferred tribes")
    func conflictFallsBackToInference() throws {
        let beasts = Self.tierOne(.beast)
        try #require(beasts.count >= 2)
        var log = SyntheticLog()
        log.createGame(gameType: "GT_BATTLEGROUNDS")
        var engine = TavernEngine(pool: PoolFixture.pool, timeZone: Self.utc)
        for line in log.lines { engine.ingest(line) }
        // The banner (misread) leaves Beasts out.
        engine.ingestScreenTribes(ScreenTribeReading(tribes: Self.banner))

        var more = SyntheticLog()
        more.pickHero()
        more.tag(SyntheticLog.pickedHeroID, "PLAYER_TECH_LEVEL", "1")
        more.turn(1)
        // Bob offers four Beasts at tier 1 (two of each): the lobby has Beasts.
        for (i, id) in (beasts.prefix(2) + beasts.prefix(2)).enumerated() {
            more.shopCard(300 + i, id, position: i + 1, extra: ["TECH_LEVEL=1", "IS_BACON_POOL_MINION=1"])
        }
        more.endTaskList()
        for line in more.lines { engine.ingest(line) }
        engine.finish()

        let tribes = try #require(engine.state.game?.tribes)
        #expect(tribes.screenConflict)
        #expect(tribes.source == .inferred)
        let beast = try #require(tribes.tribes.first { $0.tribe == "BEAST" })
        #expect(beast.confidence == .confirmed, "\(beast)")
        // Not the reading's answer: the screen's own tribes (other than the forced one) aren't confirmed.
        #expect(tribes.tribes.filter { $0.confidence == .confirmed && !$0.isForced }.map(\.tribe) == ["BEAST"])
    }
}
