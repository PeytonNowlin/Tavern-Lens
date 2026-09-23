import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1: the lobby's tribes inferred from the captured games (research §B.3). Skipped
/// when the private fixtures are absent.
@Suite("Lobby tribes on captured games")
struct TribeFixtureTests {
    static let stressGame = "Hearthstone_2026_09_22_22_34_47/Power.log"

    struct Case: CustomTestStringConvertible, Sendable {
        var log: String
        var tribes: [String]
        var testDescription: String { log.components(separatedBy: "/").first ?? log }
    }

    static let cases = [
        Case(log: Fixtures.truncatedGame, tribes: ["ABERRATION", "DEMON", "DRAGON", "ELEMENTAL", "MECHANICAL"]),
        Case(log: Fixtures.fullGame, tribes: ["ABERRATION", "DRAGON", "ELEMENTAL", "QUILBOAR", "UNDEAD"]),
        Case(log: stressGame, tribes: ["ABERRATION", "DEMON", "MECHANICAL", "MURLOC", "PIRATE"]),
    ]

    static func replay(_ log: String, pool: MinionPool = PoolFixture.pool) throws -> ReplayResult {
        try TavernEngine.replay(fileAt: #require(Fixtures.url(log)), pool: pool)
    }

    @Test(
        "The inferred tribes resolve to the lobby's 5 by BG turn 4 and stay resolved",
        .enabled(if: cases.allSatisfy { Fixtures.isAvailable($0.log) }, "private fixture logs not present"),
        arguments: cases
    )
    func resolvesByTurnFour(_ fixture: Case) throws {
        let timeline = try Self.replay(fixture.log).timeline
        let firstResolved = try #require(timeline.first { $0.state.game?.tribes?.isResolved == true })
        let resolvedTurn = try #require(firstResolved.state.game?.bgTurn)
        #expect(resolvedTurn <= 4, "resolved only at BG turn \(resolvedTurn)")
        #expect(firstResolved.state.game?.tribes?.confirmedNames == fixture.tribes)

        let endOfTurnFour = try #require(timeline.last { $0.state.game?.bgTurn == 4 })
        let tribes = try #require(endOfTurnFour.state.game?.tribes)
        #expect(tribes.isResolved)
        #expect(!tribes.isUncertain)
        #expect(tribes.confirmedNames == fixture.tribes)
        #expect(tribes.tribes.filter { $0.confidence == .absent }.count == 5)
        #expect(tribes.tribes.first { $0.tribe == "ABERRATION" }?.isForced == true)

        // Once resolved it never changes its answer.
        for entry in timeline where entry.position.line >= firstResolved.position.line {
            #expect(entry.state.game?.tribes?.confirmedNames == fixture.tribes, "at line \(entry.position.line)")
        }
    }

    @Test(
        "The tribe display updates confidence as evidence arrives",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func confidenceUpdates() throws {
        let timeline = try Self.replay(Fixtures.fullGame).timeline
        let views = timeline.compactMap { $0.state.game?.tribes }
        // From the hero pick on, every game view carries the tribes.
        #expect(views.count == timeline.filter { $0.state.game != nil }.count)
        let first = try #require(views.first)
        // Before any evidence only the forced tribe is sure; the rest share 4 slots in 9.
        #expect(first.confirmedNames == ["ABERRATION"])
        #expect(first.tribes.filter { !$0.isForced }.allSatisfy { $0.percent == 44 && $0.confidence == .unlikely })
        #expect(!first.isResolved)

        // Undead climbs as its minions show up, through likely, to confirmed.
        let undead = views.compactMap { $0.tribes.first { $0.tribe == "UNDEAD" } }
        let states = undead.map(\.confidence).reduce(into: [TribeConfidence]()) { if $0.last != $1 { $0.append($1) } }
        #expect(states.first == .unlikely)
        #expect(states.last == .confirmed)
        #expect(Set(undead.map(\.percent)).count >= 3, "only \(Set(undead.map(\.percent)))")
        // A tribe that isn't there sinks to absent.
        let beast = views.compactMap { $0.tribes.first { $0.tribe == "BEAST" } }
        #expect(beast.last?.confidence == .absent)
        #expect(Set(beast.map(\.percent)).count >= 3)
        // Confirmed and likely tribes are listed first.
        let last = try #require(views.last)
        #expect(last.tribes.prefix(5).allSatisfy { $0.confidence == .confirmed })
    }

    @Test(
        "No removed or rotated-out minion shows up, and cards the pool lacks are adopted with a diagnostic",
        .enabled(if: cases.allSatisfy { Fixtures.isAvailable($0.log) }, "private fixture logs not present")
    )
    func poolDrift() throws {
        // With our override file, nothing the game flags as a pool minion is missing from the
        // pool except Dark Paradox variants (one per game, never tribe evidence).
        for fixture in Self.cases {
            let drift = try Self.replay(fixture.log).poolDrift
            #expect(drift.allSatisfy { $0.cardID.hasPrefix("BG36_360") }, "\(fixture.testDescription): \(drift)")
        }
        // Without our per-card fixes (what HDT and HSTracker ship) the game's own flag adds the
        // two new minions HSReplay missed, and the answer is still right.
        let result = try Self.replay(Fixtures.fullGame, pool: PoolFixture.poolWithoutOurCardFixes)
        let adopted = Set(result.poolDrift.map(\.cardID))
        #expect(adopted.isSuperset(of: ["BG36_849", "BG36_364"]), "\(result.poolDrift)")  // Heroic Broodmother, Hopebringer
        #expect(result.poolDrift.first { $0.cardID == "BG36_849" }?.tier == 6)
        let seed = try #require(result.games.first?.gameSeed)
        #expect(result.poolDrift.allSatisfy { $0.gameSeed == seed })
        #expect(result.timeline.last?.state.game?.tribes?.confirmedNames == Self.cases[1].tribes)
    }

    @Test(
        "A pool that arrives late weighs the game's evidence so far",
        .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func latePool() throws {
        var engine = TavernEngine()
        try LogFileReader.forEachLine(in: #require(Fixtures.url(Fixtures.truncatedGame))) { engine.ingest($0) }
        #expect(engine.state.game?.tribes == nil)
        engine.usePool(PoolFixture.pool)
        engine.finish()
        let expected = try Self.replay(Fixtures.truncatedGame).timeline.last?.state.game?.tribes
        #expect(engine.state.game?.tribes == expected)
        #expect(engine.tribeEstimate?.isResolved == true)
    }

    @Test(
        "A screen reading settles the tribes at the hero pick; the log cross-checks it",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func screenReading() throws {
        let url = try #require(Fixtures.url(Fixtures.fullGame))
        func replay(reading: ScreenTribeReading) throws -> [TimelineEntry] {
            var engine = TavernEngine(pool: PoolFixture.pool)
            var read = false
            try LogFileReader.forEachLine(in: url) { line in
                engine.ingest(line)
                // At the hero pick, before any shop.
                if !read, engine.state.game?.phase == .heroPick {
                    engine.ingestScreenTribes(reading)
                    read = true
                }
            }
            engine.finish()
            return engine.timeline
        }

        let right = try replay(reading: ScreenTribeReading(tribes: [.aberration, .dragon, .elemental, .quilboar, .undead]))
        let atPick = try #require(right.first { $0.state.game?.tribes?.source != .inferred }?.state.game)
        #expect(atPick.bgTurn == 0)
        #expect(atPick.tribes?.isResolved == true)
        #expect(atPick.tribes?.source == .screen)
        #expect(atPick.tribes?.confirmedNames == Self.cases[1].tribes)
        let end = try #require(right.last?.state.game?.tribes)
        #expect(end.source == .screenAndInferred)
        #expect(!end.screenConflict)

        // A misread banner: the log disagrees, and says so.
        let wrong = try replay(reading: ScreenTribeReading(tribes: [.aberration, .beast, .demon, .murloc, .pirate]))
        let misread = try #require(wrong.last?.state.game?.tribes)
        #expect(misread.screenConflict)
        #expect(misread.source == .screen)
    }
}
