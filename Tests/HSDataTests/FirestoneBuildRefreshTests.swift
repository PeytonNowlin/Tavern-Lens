import Foundation
import HSData
import Testing

@Suite("Firestone comp source normalization")
struct FirestoneBuildRefreshTests {
    static let raw = Data("""
    {"lastUpdateDate":"2026-10-02T18:10:36.245Z","dataPoints":150,"timePeriod":"last-patch","compStats":[
      {"archetype":"aberration_discard","dataPoints":100,"averagePlacement":3,
       "averagePlacementAtMmr":[{"mmr":100,"dataPoints":100,"placement":3},{"mmr":10,"dataPoints":20,"placement":2}],
       "heroStats":[{"finalBoards":[
          {"finalComp":{"board":[{"cardID":"BG_PAYOFF"},{"cardID":"BG_PAYOFF_G"},{"cardID":"BG_FILLER"}]}},
          {"finalComp":{"board":[{"cardID":"BG_FILLER"}]}},
          {"finalComp":{"board":[{"cardID":"BG_FILLER"}]}}]}]},
      {"archetype":"abberation_discard","dataPoints":50,"averagePlacement":6,
       "averagePlacementAtMmr":[{"mmr":100,"dataPoints":50,"placement":6},{"mmr":10,"dataPoints":10,"placement":5},
          {"mmr":1,"dataPoints":0,"placement":0}],
       "heroStats":[{"finalBoards":[
          {"finalComp":{"board":[{"cardID":"BG_PAYOFF"}]}},
          {"finalComp":{"board":[{"cardID":"BG_PAYOFF_G"}]}}]}]}]}
    """.utf8)

    @Test("Known spelling aliases merge game populations and independent MMR bucket populations")
    func aliases() throws {
        let stats = try FirestoneCompStats.derive(fromFirestone: Self.raw, minimumShare: 0.6)
        #expect(stats.comps.map(\.archetype) == ["aberration_discard"])
        let comp = try #require(stats.comps.first)
        #expect(stats.dataPoints == 150 && comp.dataPoints == 150)
        #expect(comp.averagePlacement == 4)
        #expect(comp.averagePlacementAtMmr.first { $0.mmr == 100 }?.dataPoints == 150)
        #expect(comp.averagePlacementAtMmr.first { $0.mmr == 10 }?.dataPoints == 30)
        #expect(comp.averagePlacement(mmr: 10) == 3)
        #expect(comp.averagePlacement(mmr: 1) == nil)
        #expect(stats.lastUpdateDate == "2026-10-02T18:10:36.245Z" && stats.timePeriod == "last-patch")
    }

    @Test("Board-presence counts merge before the share cutoff, without counting two copies twice")
    func shareCutoff() throws {
        let stats = try FirestoneCompStats.derive(fromFirestone: Self.raw, minimumShare: 0.6)
        let comp = try #require(stats.comps.first)
        #expect(comp.sampledBoards == 5)
        #expect(comp.boardsWithCard == ["BG_PAYOFF": 3, "BG_FILLER": 3])
        #expect(try FirestoneCompStats(json: stats.encoded()) == stats)
    }

    @Test("Old derived caches use the canonical IDs and preserve summed populations")
    func cachedAliases() throws {
        let stats = FirestoneCompStats(lastUpdateDate: "2026-10-02T18:10:36.245Z", timePeriod: "last-patch", dataPoints: 150,
            comps: [
                .init(archetype: "abberation_deathrattle", dataPoints: 50, averagePlacement: 6,
                    sampledBoards: 20, boardsWithCard: ["BG36_109": 20]),
                .init(archetype: "aberration_deathrattle", dataPoints: 100, averagePlacement: 3,
                    sampledBoards: 100, boardsWithCard: ["BG36_109": 60])])
        let cached = try FirestoneCompStats(json: stats.encoded())
        #expect(cached.comps.map(\.archetype) == ["aberration_deathrattle"])
        #expect(cached.comps.first?.dataPoints == 150 && cached.comps.first?.averagePlacement == 4)
        #expect(cached.comps.first?.sampledBoards == 120 && cached.comps.first?.boardsWithCard["BG36_109"] == 80)
        let catalog = BuildCatalog.compose(stats: cached, strategies: nil, overrides: nil, pool: MinionPoolTests.pool())
        #expect(catalog.build("aberration_deathrattle")?.tribes.map(\.name) == ["ABERRATION"])
        #expect(catalog.build("abberation_deathrattle") == nil)
    }

    @Test("Only demonstrated placeholder recipes are excluded; name-based card resolution remains available")
    func placeholders() throws {
        let raw = Data("""
        [{"compId":" ","name":"","cards":[]},
         {"compId":"elemental_boost","name":"#N/A","cards":[],"tips":[{"tip":"Unfinished"}]},
         {"compId":"mech_magnet","name":"","cards":[{"cardId":"#N/A","name":"","status":"CORE"}]},
         {"compId":"beast_lobster","name":"Beast Lobster","cards":[{"cardId":"#N/A","name":"Tasty Lobster","status":"CORE"}]},
         {"compId":"aberration_discard","name":"Aberration Discard","cards":[{"cardId":"BG36_109","name":"","status":"CORE"}]}]
        """.utf8)
        let strategies = try FirestoneStrategies(json: raw)
        #expect(strategies.comps.map(\.compId) == ["beast_lobster", "aberration_discard"])
        #expect(strategies.comp("beast_lobster")?.cards.first?.name == "Tasty Lobster")
    }

    @Test("The refreshed bundle carries real current archetypes and provider provenance")
    func bundled() throws {
        let stats = try #require(FirestoneCompStats.bundled())
        let strategies = try #require(FirestoneStrategies.bundled())
        #expect(stats.timePeriod == "last-patch" && stats.dataPoints > 0)
        #expect(stats.updatedAt != nil && stats.lastUpdateDate.hasPrefix("2026-10-02"))
        #expect(Set(stats.comps.map(\.archetype)).count == stats.comps.count)
        #expect(!stats.comps.contains { $0.archetype.hasPrefix("abberation_") })
        for id in ["aberration_deathrattle", "aberration_discard", "mech_volumizer", "mech_glambot"] {
            #expect(stats.comps.contains { $0.archetype == id && $0.dataPoints >= 50 })
            #expect(strategies.comp(id)?.cards.isEmpty == false)
        }
        #expect(!strategies.comps.contains { $0.name == "#N/A" && $0.cards.isEmpty })
    }
}
