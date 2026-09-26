import Foundation
import HSData
import Testing

@Suite("Public composition knowledge")
struct HSReplayCompositionTests {
    @Test("All 16 captured guides resolve their cards and preserve separate guide and tier dates")
    func capturedGuides() throws {
        let source = try #require(HSReplayCompositions.bundled())
        #expect(source.comps.count == 16)
        let catalog = source.catalog(pool: MinionPoolTests.pool())
        let undead = try #require(catalog.build("hsreplay_14"))
        #expect(undead.core.contains("BG27_002") == false)
        #expect(undead.core.count == 5)
        #expect(undead.whenToCommit?.contains("Drustfallen Butcher") == true)
        #expect(undead.sourceEvidence?.sourceUpdated != nil)
        #expect(undead.sourceEvidence?.tierUpdated != nil)
        #expect(undead.averagePlacement == nil)
        #expect(catalog.builds.count + catalog.dropped.count == 16)
    }
    @Test("Public guide integration replaces duplicate archetypes without losing placement evidence")
    func mergedCatalog() throws {
        let catalog = BuildCatalog.compose(stats: BuildCatalogTests.stats, strategies: BuildCatalogTests.strategies,
            overrides: BuildCatalogTests.overrides, pool: MinionPoolTests.pool(), compositions: HSReplayCompositions.bundled())
        #expect(catalog.build("beast_lobster") == nil)
        #expect(catalog.build("hsreplay_87")?.averagePlacement != nil)
        #expect(catalog.build("hsreplay_87")?.requirements?.isEmpty == false)
        #expect(catalog.build("hsreplay_87")?.placementEvidence?.provider == "Firestone")
    }
}
