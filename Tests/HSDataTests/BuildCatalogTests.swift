import Foundation
import HSData
import Testing

/// The build catalog: Firestone's comp stats and curated strategies joined, cards the
/// 36.6.1 pool no longer has taken out, gutted builds left out, and our override file's
/// builds used for tribes the sources don't cover. Uses the data HSData ships.
@Suite("Build catalog")
struct BuildCatalogTests {
    static let pool = MinionPoolTests.pool()
    static let stats = FirestoneCompStats.bundled()!
    static let strategies = FirestoneStrategies.bundled()!
    static let overrides = BuildOverrides.current(at: MinionPoolTests.date("2026-09-23T01:00:00Z"), local: [])!

    static func catalog(
        stats: FirestoneCompStats? = stats, strategies: FirestoneStrategies? = strategies,
        overrides: BuildOverrides? = overrides
    ) -> BuildCatalog {
        BuildCatalog.compose(stats: stats, strategies: strategies, overrides: overrides, pool: pool)
    }

    @Test("The shipped comp stats, strategies and override file decode")
    func bundledData() {
        #expect(Self.stats.timePeriod == "last-patch")
        #expect(Self.stats.dataPoints == 728_692)
        #expect(Self.stats.comps.count == 21)
        let lobster = Self.stats.comps.first { $0.archetype == "beast_lobster" }
        #expect(lobster?.sampledBoards == 995)
        #expect(lobster.map { (($0.averagePlacement * 100).rounded()) } == 382)
        #expect(lobster?.averagePlacement(mmr: 10).map { ($0 * 100).rounded() } == 388)

        // The file's blank placeholders are dropped; names stand in for the `#N/A` card IDs.
        #expect(Self.strategies.comps.count == 18)
        #expect(Self.strategies.comp("undead_butcher")?.tips.first?.whenToCommit == "Deathrattle/reborn minions + Drustfallen Butcher")
        #expect(Self.strategies.comp("undead_butcher")?.patchNumber == 248_022)

        #expect(Self.overrides.patch == "36.6.1")
        #expect(Self.overrides.builds.map(\.id) == [
            "aberration_tea_set_deity", "aberration_discard_deity", "aberration_spell_deity", "aberration_cthun_poet",
        ])
        #expect(Self.overrides.builds.allSatisfy { $0.use == .whenSourcesLackTribe && $0.tip != nil })
    }

    @Test("Exactly the builds whose core left the pool in 36.6.1 are left out (research §3: gutted or unavailable)")
    func gutted() {
        let catalog = Self.catalog()
        let dropped = Set(catalog.dropped.filter { !$0.id.hasPrefix("aberration_") }.map(\.id))
        #expect(dropped == [
            "dragon_evoker", "elemental_cycle", "mech_automaton", "murloc_mrrglton", "naga_end_of_turn",
            "naga_groundbreaker",
        ])
        #expect(catalog.dropped.first { $0.id == "elemental_cycle" }?.reason.contains("BG36_351") == true)
        // Intact, nerfed and weakened builds stay.
        for id in [
            "murloc_handbuff", "beast_beetle", "demon_boost_shop", "beast_leviathan", "undead_butcher", "neutral_tea_set",
            "demon_self_damage", "pirate_discover", "mech_magnet", "beast_lobster", "quilboar_choose_one",
            "dragon_kalecgos",
        ] {
            #expect(catalog.build(id)?.source == .firestone, "\(id) should be in the catalog")
        }
        // Firestone lists comps with 0-2 sampled boards; they're noise.
        #expect(catalog.build("elemental_boost") == nil && catalog.build("quilboar_felboar") == nil)
    }

    @Test("No build names a card the pool doesn't have; the ones it lost are listed")
    func onlyPoolCards() {
        let catalog = Self.catalog()
        for build in catalog.builds {
            for card in build.core + build.addons {
                let known = Self.pool.cards[card]
                if known?.type == "MINION", (known?.techLevel ?? 0) > 0 {
                    #expect(Self.pool.contains(card), "\(build.id) names \(card), which isn't in the pool")
                }
            }
        }
        let magnet = catalog.build("mech_magnet")
        // Weakened: Scrap Scraper, Clunker Junker and Deflect-o-Bot are gone, the curated core stays.
        #expect(Set(magnet?.removedCards ?? []) == ["BG26_148", "BG29_503", "BGS_071"])
        #expect(magnet?.core.first == "BG36_506")
        // Neutral Tea Set lost Fauna Whisperer (Naga) and Warpwing.
        #expect(catalog.build("neutral_tea_set")?.core == ["BG36_640", "BG35_883"])
        // Demon Boost Shop's curated cycle card Oozeling Gladiator was removed.
        #expect(catalog.build("demon_boost_shop")?.addons.contains("BG27_002") == false)
    }

    @Test("Curated cards resolve by name; golden boards fold into the base card")
    func joins() throws {
        let catalog = Self.catalog()
        let kalecgos = try #require(catalog.build("dragon_kalecgos"))
        // "Kalecgos Arcane Aspect" is "Kalecgos, Arcane Aspect".
        #expect(kalecgos.core.first == "BGS_041")
        #expect(kalecgos.tribes.map(\.name) == ["DRAGON"])
        let pirate = try #require(catalog.build("pirate_discover"))
        #expect(pirate.core.prefix(3) == ["BG36_344", "BG36_523", "BG26_817"])
        #expect(pirate.addons.contains("BG36_521") && pirate.addons.contains("BG24_715"))
        #expect(pirate.whenToCommit == "Enterprising Escapee + Hooktusk Master Marauder")
        #expect(pirate.difficulty == "Hard" && pirate.powerLevel == "S")
        #expect(pirate.popularity.map { ($0 * 1000).rounded() } == 121)
        // Wrath Weaver is on 75% of Demon Self Damage boards only as a golden (`TB_BaconUps_079`).
        let selfDamage = try #require(catalog.build("demon_self_damage"))
        #expect(selfDamage.core.contains("BGS_004"))
        #expect(catalog.baseCardID("TB_BaconUps_079") == "BGS_004")
        #expect(catalog.baseCardID("BGS_004_G") == "BGS_004")
        #expect(catalog.build("neutral_tea_set")?.tribes == [])
        // Best average placement first.
        let placements = catalog.builds.compactMap(\.averagePlacement)
        #expect(placements == placements.sorted())
        #expect(catalog.builds.first?.id == "murloc_handbuff")
    }

    @Test("Override builds are used when the sources lack their tribe, and retire when a source covers it")
    func overrideBuilds() throws {
        let catalog = Self.catalog()
        let ours = catalog.builds.filter { $0.source == .overrides }.map(\.id).sorted()
        #expect(ours == ["aberration_cthun_poet", "aberration_discard_deity", "aberration_spell_deity", "aberration_tea_set_deity"])
        let discard = try #require(catalog.build("aberration_discard_deity"))
        #expect(discard.tribes.map(\.name) == ["ABERRATION"])
        #expect(discard.core == ["BG36_099", "BG36_106", "BG36_097", "BGFYM_005"])
        #expect(discard.whenToCommit != nil && discard.tip != nil)
        #expect(catalog.build("aberration_cthun_poet")?.requiresDeityDbfID == 130_610)

        // Firestone publishes an Aberration archetype: the hypotheses step aside, except one marked `always`.
        var stats = Self.stats
        stats.comps.append(.init(
            archetype: "aberration_shadow", dataPoints: 5000, averagePlacement: 3.9, sampledBoards: 400,
            boardsWithCard: ["BG36_109": 360, "BG36_109_G": 20, "BG36_110": 200]
        ))
        var overrides = Self.overrides
        overrides.builds[2].use = .always
        let later = Self.catalog(stats: stats, overrides: overrides)
        let shadow = try #require(later.build("aberration_shadow"))
        #expect(shadow.source == .firestone && shadow.tribes.map(\.name) == ["ABERRATION"])
        #expect(shadow.core == ["BG36_109"] && shadow.addons == ["BG36_110"])
        #expect(shadow.name == "Aberration Shadow")
        #expect(later.builds.filter { $0.source == .overrides }.map(\.id) == ["aberration_spell_deity"])
        #expect(later.dropped.first { $0.id == "aberration_discard_deity" }?.reason == "the sources cover its tribe")
    }

    @Test("Override builds that lost a core card are left out; disabled source builds too")
    func overrideFiltering() {
        var overrides = Self.overrides
        overrides.builds.append(.init(
            id: "dragon_warpwing", name: "Warpwing", tribes: ["DRAGON"], use: .always, core: ["BG24_004", "BG29_813"]
        ))
        overrides.disabled = ["beast_lobster"]
        let catalog = Self.catalog(overrides: overrides)
        #expect(catalog.build("dragon_warpwing") == nil)
        #expect(catalog.dropped.first { $0.id == "dragon_warpwing" }?.reason.contains("BG24_004") == true)
        #expect(catalog.build("beast_lobster") == nil)
        #expect(catalog.dropped.contains { $0.id == "beast_lobster" && $0.reason.contains("disabled") })
    }

    @Test("Either source alone still gives builds; neither gives only the override builds")
    func partialSources() {
        let strategiesOnly = Self.catalog(stats: nil)
        #expect(strategiesOnly.build("beast_lobster")?.core == ["BG36_202"])
        #expect(strategiesOnly.build("beast_lobster")?.averagePlacement == nil)
        let statsOnly = Self.catalog(strategies: nil)
        #expect(statsOnly.build("beast_lobster")?.core.contains("BG36_208") == true)
        #expect(statsOnly.build("beast_lobster")?.name == "Beast Lobster")
        let none = Self.catalog(stats: nil, strategies: nil)
        #expect(none.builds.allSatisfy { $0.source == .overrides } && none.builds.count == 4)
        #expect(none.provenance.isStale)
    }
}

/// Firestone's raw comp-stats file reduced to what's cached and bundled.
@Suite("Firestone comp stats")
struct FirestoneCompStatsTests {
    static let raw = Data("""
    {"lastUpdateDate":"2026-09-23T00:10:30.054Z","dataPoints":1000,"timePeriod":"past-three","compStats":[
      {"archetype":"beast_lobster","dataPoints":600,"averagePlacement":3.5,
       "averagePlacementAtMmr":[{"mmr":100,"dataPoints":600,"placement":3.5},{"mmr":10,"dataPoints":60,"placement":3.1}],
       "placementDistribution":[{"rank":1,"totalMatches":9}],
       "heroStats":[
         {"heroCardId":"H1","finalBoards":[
           {"mmr":7000,"finalComp":{"turn":12,"board":[
             {"cardID":"BG36_202","tags":{"ATK":5}},{"cardID":"BG36_202_G","tags":{}},{"cardID":"BG36_208"}]}},
           {"mmr":6000,"finalComp":{"board":[{"cardID":"BG36_202_G"},{"cardID":"TB_BaconUps_079"}]}}]},
         {"heroCardId":"H2","finalBoards":[{"finalComp":{"board":[{"cardID":"BG36_208"}]}}]}]},
      {"archetype":"empty","heroStats":[]}]}
    """.utf8)

    @Test("Boards are counted per card, goldens with _G folded, once per board")
    func derive() throws {
        let stats = try FirestoneCompStats.derive(fromFirestone: Self.raw)
        #expect(stats.timePeriod == "past-three" && stats.dataPoints == 1000)
        #expect(abs((stats.updatedAt?.timeIntervalSince1970 ?? 0) - 1_790_122_230.054) < 0.001)
        #expect(stats.comps.map(\.archetype) == ["beast_lobster", "empty"])
        let lobster = stats.comps[0]
        #expect(lobster.sampledBoards == 3)
        #expect(lobster.boardsWithCard == ["BG36_202": 2, "BG36_208": 2, "TB_BaconUps_079": 1])
        #expect(lobster.averagePlacement(mmr: 10) == 3.1)
        #expect(stats.comps[1].sampledBoards == 0 && stats.comps[1].boardsWithCard.isEmpty)
        // The derived form round-trips.
        #expect(try FirestoneCompStats(json: stats.encoded()) == stats)
    }

    @Test("A CDN error page or another file isn't taken for comp stats")
    func rejectsOtherBodies() {
        #expect(throws: (any Error).self) {
            try FirestoneCompStats.derive(fromFirestone: Data("<html><body>Error</body></html>".utf8))
        }
        #expect(throws: (any Error).self) { try FirestoneCompStats.derive(fromFirestone: Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try FirestoneStrategies(json: Data("{\"a\":1}".utf8)) }
    }
}
