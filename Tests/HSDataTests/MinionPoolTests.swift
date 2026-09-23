import Foundation
import HSData
import Testing

/// The live minion pool composed from the build's card data, HSReplay's meta period and
/// our override file (research §A.8/§A.9). Uses a BG-only trim of the real build 251952
/// `cards.json` and the meta-period snapshot and override file shipped in HSData.
@Suite("Minion pool")
struct MinionPoolTests {
    static let cardsURL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/HearthstoneJSON/cards.251952.bg.json")

    static let cards: CardDB = try! CardDB(build: 251_952, json: Data(contentsOf: cardsURL))
    static let meta = MetaPeriod.bundled()!
    static let overrides = PoolOverrides.current(at: date("2026-09-23T01:00:00Z"), local: [])!

    static func date(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

    static func pool(_ mode: PoolMode = .solo) -> MinionPool {
        MinionPool.compose(cards: cards, metaPeriod: meta, overrides: overrides, mode: mode)
    }

    /// Blizzard's 36.6.1 removed minions (§A.10).
    static let removed = [
        "BG_TTN_401", "BG32_172", "BG36_507", "BG36_760", "BG29_503", "BG35_142", "BG26_162", "BG35_143", "BGS_071",
        "BG31_824", "BG33_323", "BG32_822", "BG32_842", "BG28_595", "BGS_012", "BG35_140", "BG32_170", "BG31_843",
        "BG36_351", "BGS_127", "BG27_080", "BGS_104", "BG27_002", "BG35_141", "BG33_893", "BG36_509", "BG33_140",
        "BG32_841", "BG26_148", "BG25_806", "BG29_810", "BG32_846", "BG36_510", "BG35_152", "BG24_004",
    ]
    /// The pure Naga shop minions rotated out (§A.10).
    static let nagaRotatedOut = [
        "BG36_921", "BG23_000", "BG23_009", "BG23_002", "BG31_924", "BG23_004", "BG23_007", "BG35_921", "BG36_508",
        "BGDUO31_209", "BG33_319", "BG34_925", "BG26_505", "BG31_920", "BG23_008", "BG31_925", "BGDUO_122",
        "BG32_835", "BG32_837", "BG31_035", "BG36_622", "BG27_514",
    ]
    /// Returning and new minions the build leaves unflagged.
    static let returningAndNew = [
        "BG31_815", "BG34_170t", "BGS_034", "BG30_121", "BG31_810", "BG35_881", "BG35_882", "BG36_849", "BG36_364",
        "BG28_582", "BG28_707", "BG31_812", "BG36_370", "BG36_369", "BG36_362", "BG36_700", "BG36_848", "BG36_366",
        "BG36_367",
    ]

    @Test("The shipped override file and meta-period snapshot decode, card IDs intact")
    func bundledData() throws {
        #expect(Self.overrides.patch == "36.6.1")
        #expect(Self.overrides.tribesPerLobby == 5)
        #expect(Self.overrides.forcedTribes == [.init(tribe: "ABERRATION", until: Self.date("2026-10-06T17:00:00Z"))])
        #expect(Self.overrides.minionPool["BG32_172"] == 0)
        #expect(Self.overrides.minionPool["BG36_849"] == 1)
        #expect(Self.overrides.heroTribeRules["TB_BaconShop_HERO_53"]?.needsAny == ["DRAGON"])
        #expect(Self.overrides.minionTribeGates["BG28_303"] == ["UNDEAD"])

        #expect(Self.meta.name == "Real 36.6.1")
        #expect(Self.meta.periodStart == Date(timeIntervalSince1970: 1_790_097_494))
        #expect(Self.meta.tagOverrides.count == 58)
        #expect(Set(Self.meta.tribesInRotation.compactMap(\.name)) == [
            "BEAST", "DRAGON", "DEMON", "ELEMENTAL", "MECHANICAL", "MURLOC", "PIRATE", "QUILBOAR", "UNDEAD", "ABERRATION",
        ])
    }

    @Test("The solo pool is the research's 251 minions, 21/34/43/59/49/33/12 by tier; Duos adds 28")
    func composition() {
        let solo = Self.pool()
        #expect(solo.minions.count == 251)
        let byTier = Dictionary(grouping: solo.minions.values, by: \.tier).mapValues(\.count)
        #expect(byTier == [1: 21, 2: 34, 3: 43, 4: 59, 5: 49, 6: 33, 7: 12])
        let duos = Self.pool(.duos)
        #expect(duos.minions.count == 279)
        #expect(duos.minions.values.filter(\.isDuosOnly).count == 28)
        #expect(solo.tribesPerLobby == 5)
        #expect(solo.forcedTribes(at: Self.date("2026-09-23T01:00:00Z")) == [.aberration])
        #expect(solo.forcedTribes(at: Self.date("2026-10-07T00:00:00Z")) == [])
        #expect(!solo.tribesInRotation.contains(.naga))
        #expect(solo.provenance.metaPeriodName == "Real 36.6.1")
    }

    @Test("No removed or rotated-out minion is in the pool; Naga dual-types stay through their other tribe")
    func removedAndRotated() throws {
        for mode in [PoolMode.solo, .duos] {
            let pool = Self.pool(mode)
            for id in Self.removed + Self.nagaRotatedOut {
                #expect(!pool.contains(id), "\(id) (\(Self.cards.name(of: id) ?? "?")) is in the \(mode) pool")
                // Nor its golden.
                if let golden = Self.cards[id]?.battlegroundsPremiumDbfId.flatMap(Self.cards.card(dbfID:)) {
                    #expect(!pool.contains(golden.id))
                }
            }
            #expect(!pool.contains("BG25_013"), "Rot Hide Gnoll's raw pool value is 2")
            #expect(!pool.contains("BGFYM_000") && !pool.contains("BGFYM_011"), "Deities aren't sold")
        }
        let pool = Self.pool()
        #expect(try #require(pool.minion("BG31_330")).tribes == [.demon])  // Ominous Seer (Demon/Naga)
        #expect(try #require(pool.minion("BG32_820")).tribes == [.dragon])  // Firescale Hoarder (Dragon/Naga)
        #expect(try #require(pool.minion("BG28_303")).lobbyGate == [.undead])  // Disguised Graverobber, gated
        #expect(try #require(pool.minion("BG32_111")).isAllTribes)
    }

    @Test("Each layer wins over the one before: card data, then HSReplay, then our file")
    func layers() throws {
        let buildOnly = MinionPool.compose(cards: Self.cards, metaPeriod: nil, overrides: nil)
        #expect(buildOnly.contains("BG32_822"))  // Fire-forged Evoker: removed, still flagged in the build
        #expect(!buildOnly.contains("BG31_815"))  // Dune Dweller: returning, not flagged yet
        #expect(buildOnly.tribesInRotation.contains(.naga))

        let withMeta = MinionPool.compose(cards: Self.cards, metaPeriod: Self.meta, overrides: nil)
        #expect(!withMeta.contains("BG32_822"))
        #expect(try #require(withMeta.minion("BG31_815")).source == .metaPeriod)
        #expect(withMeta.contains("BG32_172"))  // Auto Assembler: HSReplay missed it
        #expect(!withMeta.contains("BG36_849"))  // Heroic Broodmother: HSReplay missed it

        let pool = Self.pool()
        #expect(!pool.contains("BG32_172"))
        #expect(try #require(pool.minion("BG36_849")).source == .overrides)
        for id in Self.returningAndNew { #expect(pool.contains(id), "\(id) missing") }
        // Golden cards resolve to their normal card.
        let golden = try #require(Self.cards["BG31_815"]?.battlegroundsPremiumDbfId.flatMap(Self.cards.card(dbfID:)))
        #expect(pool.minion(golden.id)?.cardID == "BG31_815")

        // Our file wins over HSReplay even where HSReplay has an opinion.
        var ours = Self.overrides
        ours.minionPool["BG31_815"] = 0
        #expect(!MinionPool.compose(cards: Self.cards, metaPeriod: Self.meta, overrides: ours).contains("BG31_815"))
    }

    @Test("Tavern spells: removed ones out, returning Seafood Stew in, Duos-only spells only in Duos")
    func spells() {
        let solo = Self.pool()
        #expect(!solo.spells.contains("BG33_899") && !solo.spells.contains("BG35_149"))
        #expect(solo.spells.contains("BG32_337"))
        #expect(solo.spells.contains("BG36_303"))  // Corrupted Coin, new
        #expect(!solo.spells.contains("BG31_243"))
        #expect(Self.pool(.duos).spells.contains("BG31_243"))  // Portal in a Fountain (Duos)
        #expect(Self.pool(.duos).spells.count == 76)
    }

    @Test("The tribes in rotation come from the newer of the meta period and our file")
    func rotationSource() {
        var older = Self.overrides
        older.tribesInRotation = ["BEAST", "NAGA", "DEMON", "DRAGON", "MURLOC"]
        // A file older than the meta period: HSReplay's list, which knows a later patch.
        older.validFrom = Self.date("2026-09-01T00:00:00Z")
        #expect(!MinionPool.compose(cards: Self.cards, metaPeriod: Self.meta, overrides: older).tribesInRotation.contains(.naga))
        // As new or newer (the shipped file starts with the period): ours.
        older.validFrom = Self.meta.periodStart
        let newer = MinionPool.compose(cards: Self.cards, metaPeriod: Self.meta, overrides: older)
        #expect(newer.tribesInRotation == [.beast, .demon, .dragon, .murloc, .naga])
        // Without a meta period, our list.
        #expect(MinionPool.compose(cards: Self.cards, metaPeriod: nil, overrides: Self.overrides).tribesInRotation.count == 10)
    }

    @Test("A card the game flags that the pool lacks is adopted once, at the game's tier, never removed")
    func adopt() throws {
        var pool = Self.pool()
        let known = pool.adopt("BG31_815", tier: 1)
        #expect(known == nil)  // already in
        let drift = pool.adopt("BG36_360t3", tier: 3, gameSeed: 7)  // a Dark Paradox variant
        #expect(drift == PoolDrift(cardID: "BG36_360t3", name: "Dark Paradox", tier: 3, gameSeed: 7))
        #expect(try #require(pool.minion("BG36_360t3")).source == .sessionDrift)
        let again = pool.adopt("BG36_360t3", tier: 3)
        #expect(again == nil)
        #expect(pool.minions.count == 252)
        // A flagged Naga comes in marked out of rotation, so the resolver treats it as a contradiction.
        let naga = pool.adopt("BG23_000", tier: 1)
        #expect(naga != nil)
        #expect(pool.minion("BG23_000")?.isOutOfRotation == true)
    }

    @Test("Hero rules resolve skins to their hero")
    func heroRules() {
        let pool = Self.pool()
        #expect(pool.heroRule("TB_BaconShop_HERO_53_SKIN_F") == HeroTribeRule(needsAny: [.dragon]))
        #expect(pool.heroRule("TB_BaconShop_HERO_08")?.bannedWithAny == [.dragon])  // Illidan
        #expect(pool.heroRule("TB_BaconShop_HERO_15") == nil)
    }

    @Test("The override file for a date: newest started one, a local file winning a tie")
    func overrideSelection() {
        let base = Self.overrides
        var next = base
        next.patch = "36.8"
        next.validFrom = Self.date("2026-10-20T17:00:00Z")
        var local = base
        local.patch = "36.6.1-local"
        #expect(PoolOverrides.current(at: Self.date("2026-09-25T00:00:00Z"), bundled: [base, next], local: [])?.patch == "36.6.1")
        #expect(PoolOverrides.current(at: Self.date("2026-10-21T00:00:00Z"), bundled: [base, next], local: [])?.patch == "36.8")
        #expect(PoolOverrides.current(at: Self.date("2026-09-25T00:00:00Z"), bundled: [base], local: [local])?.patch == "36.6.1-local")
        #expect(PoolOverrides.current(at: Self.date("2020-01-01T00:00:00Z"), bundled: [next, base], local: [])?.patch == "36.6.1")
    }
}
