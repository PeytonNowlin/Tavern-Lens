import Foundation
import Testing
@testable import TavernEngine
import HSData
import EntityStore

/// Pins the exact scores the rater gives every trinket it knows, using real card IDs and
/// card text, so the table can be refactored without moving a rating.
@Suite("Trinket rater scores")
struct TrinketRaterScoreTests {
    static let sludge = "BG36_MagicItem_430", endOfTurn = "BG32_MagicItem_367", mallet = "BG36_MagicItem_302",
               malletImproved = "BG36_MagicItem_302t", gauntlet = "BG36_MagicItem_414", stand = "BG30_MagicItem_888",
               binoculars = "BG32_MagicItem_858", stone = "BG36_MagicItem_206", sticker = "BG36_MagicItem_852",
               ring = "BG36_MagicItem_371"

    static let texts: [String: String] = [
        sludge: "[x]Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion.",
        endOfTurn: "Your end of turn effects trigger an extra time.",
        mallet: "[x]At the end of your turn, give your minions +1/+1. (Improved by Golden minions you've played this game!)",
        malletImproved: "[x]At the end of your turn, give your minions +4/+2. (Improved by Golden minions you've played this game!)",
        gauntlet: "[x]At the end of your turn, give your minions +1/+1. (Doubles at the start of each turn!)",
        stand: "[x]When you buy a Greater Trinket, this transforms into a copy of it.",
        binoculars: "Get three random Tier 4 minions.",
        stone: "[x]Discover a Tier 4 minion of your most common type with a Dark Gift.",
        sticker: "[x]Get 2 random Tavern spells. When you play one, discard the other. At the start of your turn, repeat this.",
        ring: "[x]Your Tavern spells give an extra +1/+1. After you cast a spell on a minion, improve for this turn only.",
    ]

    func trinket(_ id: String) -> Card {
        var c = Card(id: id, dbfId: 1, name: id)
        c.type = "BATTLEGROUND_TRINKET"; c.text = Self.texts[id]
        return c
    }

    /// Board: a discarder, an end-of-turn minion and a plain one; two spells in hand.
    func scenario(hp: Int? = nil, owning: [String] = []) -> (GameView, CardDB) {
        var discarder = Card(id: "discarder", dbfId: 2, name: "D")
        discarder.text = "Activate (0): Discard a card to get a random Tavern spell."
        var eot = Card(id: "eot", dbfId: 3, name: "E")
        eot.text = "At the end of your turn, give your minions +1/+1."
        let plain = Card(id: "plain", dbfId: 4, name: "P")
        var spell = Card(id: "spell", dbfId: 5, name: "S"); spell.type = "BATTLEGROUND_SPELL"
        let g = GameView(gameType: "GT_BATTLEGROUNDS", localPlayerID: 1, localHeroCardID: nil, bgTurn: 9, phase: .recruit,
            player: PlayerView(hero: hp.map { HeroStatsView(hp: $0, health: 40, damage: 0, armor: 0, triples: 0) },
                gold: .init(available: 10, thisTurn: 10, used: 0, temporary: 0, cap: 10), tier: 4,
                board: ["discarder", "eot", "plain"].map { CardView(cardID: $0, kind: .minion) },
                hand: ["spell", "spell"].map { CardView(cardID: $0, kind: .tavernSpell) },
                mechanics: MechanicsView(trinkets: owning.map { TrinketView(cardID: $0, slot: 2) })))
        let ids = Array(Self.texts.keys)
        return (g, CardDB(build: 1, cards: [discarder, eot, plain, spell] + ids.map(trinket)))
    }

    func rate(_ id: String, cost: Int? = 2, hp: Int? = nil, owning: [String] = [], stats: TrinketStats? = nil, now: Date = Date()) -> TrinketOfferRating {
        let (g, db) = scenario(hp: hp, owning: owning)
        return TrinketRater.rate(choiceID: 1, offers: [(1, trinket(id), cost)], game: g, cards: db, stats: stats, now: now).offers[0]
    }

    @Test("Each known trinket keeps its score at full health")
    func fullHealth() {
        // board 3, discarders 1, end-of-turn 1, horizon 3, cost 2 (-3).
        let expected: [(String, Double, String)] = [
            (Self.sludge, 9, "Good fit"), (Self.endOfTurn, 9, "Good fit"),
            (Self.mallet, 6, "Good fit"), (Self.gauntlet, 6, "Good fit"), (Self.malletImproved, 24, "Strong fit"),
            (Self.binoculars, 6, "Good fit"), (Self.stone, 5, "Weak fit"), (Self.sticker, 4, "Weak fit"), (Self.ring, 15, "Good fit"),
        ]
        for (id, score, rating) in expected {
            let r = rate(id)
            #expect(r.score == score && r.rating == rating, "\(id) scored \(String(describing: r.score)) \(r.rating)")
        }
        #expect(rate(Self.stand).score == 6 && rate(Self.stand).reason.contains("Invests"))
        #expect(rate(Self.stand, hp: 20).score == -1 && rate(Self.stand, hp: 20).reason.contains("risky"))
    }

    @Test("Health shortens the horizon at 20 and 10 hp")
    func horizon() {
        #expect(rate(Self.sludge, hp: 20).score == 6.0)
        #expect(rate(Self.sludge, hp: 10).score == 3.0)
        #expect(rate(Self.endOfTurn, hp: 20).score == 8 - 3 && rate(Self.endOfTurn, hp: 10).score == 4 - 3)
        #expect(rate(Self.malletImproved, hp: 20).score == 6 * 3 * 0.5 * 2 - 3)
        #expect(rate(Self.sticker, hp: 20).score == 4 + 1 - 3 && rate(Self.sticker, hp: 10).score == 2 + 1 - 3)
        #expect(rate(Self.ring, hp: 10).score == 3.0)
    }

    @Test("Souvenir Stand doubles other trinkets, not itself")
    func souvenirStand() {
        let r = rate(Self.sludge, owning: [Self.stand])
        #expect(r.score == 12 * 2 - 3 && r.reason.hasSuffix("; Souvenir Stand copies it"))
        #expect(rate(Self.stand, owning: [Self.stand]).score == 6.0)
        #expect(rate("unknown", owning: [Self.stand]).score == nil)
    }

    @Test("Cost, affordability and a missing cost")
    func cost() {
        #expect(rate(Self.binoculars, cost: 0).score == 9)
        #expect(rate(Self.binoculars, cost: nil).score == 9 && rate(Self.binoculars, cost: nil).rating == "Unavailable")
        #expect(rate(Self.binoculars, cost: 11).rating == "Unavailable")
    }

    @Test("Population prior is clamped to +-8 and added to board fit")
    func prior() throws {
        let json = #"{"trinketStats":[{"trinketCardId":"BG32_MagicItem_858","dataPoints":800,"averagePlacement":3.0},{"trinketCardId":"BG36_MagicItem_206","dataPoints":800,"averagePlacement":4.0},{"trinketCardId":"mystery","dataPoints":800,"averagePlacement":5.0}],"lastUpdateDate":"2026-09-25T00:10:27.592Z","dataPoints":2400,"timePeriod":"past-three"}"#
        let stats = try JSONDecoder().decode(TrinketStats.self, from: Data(json.utf8))
        let now = try #require(stats.updatedAt)
        #expect(rate(Self.binoculars, stats: stats, now: now).score == 14.0)
        #expect(rate(Self.stone, stats: stats, now: now).score == 9.0)
        let unknown = rate("mystery", stats: stats, now: now)
        #expect(unknown.score == 8 + (-4) - 3 && unknown.rating == "Meta baseline")
    }
}
