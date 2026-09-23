import Foundation
import HSLog
import Testing
import TavernEngine

/// Seam 1: the local player's state in the captured games, checked against the per-turn
/// tables in docs/research/log-validation-2026-09-22.md. Skipped when the fixtures are absent.
@Suite("Local player state in captured games")
struct LocalPlayerFixtureTests {
    /// One row of the research table, at the end of the recruit phase.
    /// Cards are `ATK/HP` (health left), `*` = golden, `spell` = tavern spell, then keywords
    /// in the table's abbreviations.
    struct Row: CustomStringConvertible {
        var bgTurn: Int
        /// `RESOURCES/RESOURCES_USED`.
        var gold: String
        var tier: Int
        var hp: Int
        var board: [String]
        var hand: [String]
        var shop: [String]
        var frozen: Bool

        init(_ bgTurn: Int, gold: String, tier: Int, hp: Int, board: [String], hand: [String], shop: [String], frozen: Bool) {
            self.bgTurn = bgTurn
            self.gold = gold
            self.tier = tier
            self.hp = hp
            self.board = board
            self.hand = hand
            self.shop = shop
            self.frozen = frozen
        }

        var description: String { "BG turn \(bgTurn)" }
    }

    static let fullGame: [Row] = [
        Row(1, gold: "3/3", tier: 1, hp: 45, board: ["3/2"], hand: [], shop: ["1/1 DR", "2/3 RALLY", "spell"], frozen: false),
        Row(2, gold: "4/4", tier: 2, hp: 45, board: ["3/2"], hand: [], shop: ["3/3 FRZ", "3/2 FRZ", "2/1 BC,FRZ", "spell FRZ"], frozen: true),
        Row(3, gold: "5/5", tier: 2, hp: 42, board: ["7/1 DR", "3/2", "3/2"], hand: [], shop: ["3/3", "2/1 BC", "3/4"], frozen: false),
        Row(4, gold: "6/6", tier: 3, hp: 37, board: ["7/1 DS,DR", "3/2", "3/2"], hand: ["spell"], shop: ["4/2", "3/4", "3/3", "3/4 BC", "spell"], frozen: false),
        Row(5, gold: "7/7", tier: 4, hp: 33, board: ["14/4 DS,DR", "3/2 DS", "3/2"], hand: [], shop: ["3/2 FRZ", "3/3 BC,FRZ", "5/1 DR,FRZ", "4/3 FRZ", "spell FRZ"], frozen: true),
        Row(6, gold: "8/8", tier: 4, hp: 25, board: ["30/5 DS,DR", "6/2 R,DR", "*7/5 DS", "7/11 DS"], hand: ["spell"], shop: ["3/3 BC", "5/1 DR", "4/3", "spell", "4/6 DR,BC"], frozen: false),
        Row(7, gold: "9/9", tier: 4, hp: 25, board: ["20/4 R,DR", "3/3 DR", "44/7 DS,DR", "22/22", "5/6", "*9/7 DS", "9/13 DS"], hand: ["spell"], shop: ["3/7", "6/3 DR", "3/6", "1/4 RALLY", "4/7", "spell"], frozen: false),
        Row(8, gold: "10/10", tier: 5, hp: 25, board: ["27/5 R,DR", "4/4 DR", "6/7", "51/8 DS,DR", "35/35 DS", "*10/8 DS", "10/14 DS"], hand: ["spell"], shop: ["6/2", "3/3", "3/3", "5/5 DS", "2/4 RALLY", "spell"], frozen: false),
        Row(9, gold: "10/9", tier: 5, hp: 25, board: ["41/7 R,DR", "6/6 DR", "65/10 DS,DR", "43/43 DS", "*12/10 DS", "12/16 DS", "3/9 DS"], hand: ["spell"], shop: ["1/1 DR,FRZ", "5/2 DR,FRZ", "4/12 FRZ", "2/2 BC,FRZ", "4/5 BC,FRZ", "spell FRZ"], frozen: true),
        Row(10, gold: "10/10", tier: 6, hp: 25, board: ["62/10 R,DR", "*87/17 DS,DR", "7/9", "56/56 DS", "*13/11 DS", "13/17 DS", "4/10 DS"], hand: ["spell"], shop: ["5/2 DR", "4/12", "2/2 BC", "4/5 BC", "spell"], frozen: false),
        Row(11, gold: "10/10", tier: 6, hp: 16, board: ["21/21 DS", "81/11 R,DR", "*106/18 DS,DR", "67/67 DS", "*14/12 DS", "14/18 DS", "5/11 DS"], hand: ["spell"], shop: ["7/7 RALLY", "4/5", "2/3 RALLY", "8/4 DR", "4/5 BC", "3/4 DS,WF,RALLY", "spell"], frozen: false),
        Row(12, gold: "10/10", tier: 6, hp: 6, board: ["24/24 DS", "8/8 DR", "102/14 DS,R,DR", "*127/21 DS,DR", "80/80 DS", "*17/15 DS", "8/14 DS"], hand: [], shop: ["1/1 V", "3/3 BC", "20/20 DS", "4/5", "3/1 R,MAG", "3/3 BC", "spell"], frozen: false),
    ]

    static let truncatedGame: [Row] = [
        Row(1, gold: "3/3", tier: 1, hp: 38, board: ["2/4 T,DS,WF"], hand: [], shop: ["3/3", "2/2 MAG", "3/3 BC"], frozen: false),
        Row(2, gold: "4/4", tier: 2, hp: 38, board: ["2/4 T,DS,WF"], hand: [], shop: ["2/1 BC", "3/3", "3/3", "spell"], frozen: false),
        Row(3, gold: "5/5", tier: 2, hp: 38, board: ["2/4 T,DS,WF", "3/3 BC", "2/2 DR"], hand: [], shop: ["4/4", "2/1 DS,R", "1/4 RALLY", "spell"], frozen: false),
        Row(4, gold: "6/6", tier: 2, hp: 34, board: ["*2/2 DR", "2/4 T,DS,WF", "2/3 BC", "3/3 BC", "2/2 DR"], hand: [], shop: ["3/2 DS,WF", "3/2", "3/1", "spell"], frozen: false),
        // The log ends mid-recruit; this is the state at end of file.
        Row(5, gold: "7/7", tier: 3, hp: 31, board: ["*2/2 DR", "2/4 T,DS,WF", "2/3 BC", "3/3 BC", "2/2 DR"], hand: ["spell", "spell", "spell", "8/7"], shop: ["3/3 BC", "2/8", "3/3", "2/2 MAG", "spell"], frozen: false),
    ]

    @Test(
        "Full game: gold, tier, HP, board, hand and shop at the end of every recruit phase",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func fullGameTurns() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.fullGame)))
        for row in Self.fullGame {
            try expect(result.timeline, matches: row)
        }
    }

    @Test(
        "Truncated game: every recruit phase, including the one the log cuts off",
        .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func truncatedGameTurns() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.truncatedGame)))
        for row in Self.truncatedGame {
            try expect(result.timeline, matches: row)
        }
        #expect(result.timeline.last?.state.game?.phase == .recruit)
    }

    @Test(
        "Full game: the shop is empty outside recruit, and preview copies never reach the board",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func shopAndBoardSeparation() throws {
        let result = try TavernEngine.replay(fileAt: #require(Fixtures.url(Fixtures.fullGame)))
        let games = result.timeline.compactMap(\.state.game)
        for game in games where game.phase != .recruit {
            #expect(game.shop.cards.isEmpty, "shop shown in \(game.phase) of BG turn \(game.bgTurn)")
        }
        #expect(games.allSatisfy { ($0.player?.board.count ?? 0) <= 7 })

        // The client makes SETASIDE copies of the opponent's board under the local
        // controller at combat setup. The board at the start of combat is still exactly
        // the board the recruit phase ended with.
        for turn in 1...12 {
            let recruitEnd = try #require(GoldenHarness.Checkpoint.endOfPhase(turn, .recruit).select(from: result.timeline))
            let combatStart = try #require(GoldenHarness.Checkpoint.startOfPhase(turn, .combat).select(from: result.timeline))
            #expect(combatStart.state.game?.player?.board == recruitEnd.state.game?.player?.board, "BG turn \(turn)")
        }
    }

    @Test(
        "Full game: every view state is published at a task-list end",
        .enabled(if: Fixtures.isAvailable(Fixtures.fullGame), "private fixture log not present")
    )
    func publishedAtTaskListEnds() throws {
        let url = try #require(Fixtures.url(Fixtures.fullGame))
        var taskListEnds: Set<Int> = []
        var lineNumber = 0
        try LogFileReader.forEachLine(in: url) { line in
            lineNumber += 1
            if line.contains("PowerProcessor.EndCurrentTaskList()") { taskListEnds.insert(lineNumber) }
        }
        let result = try TavernEngine.replay(fileAt: url)
        #expect(result.timeline.count > 100)
        let stray = result.timeline.map(\.position.line).filter { !taskListEnds.contains($0) && $0 != lineNumber }
        #expect(stray.isEmpty, "entries published mid-batch at lines \(stray.prefix(10))")
    }

    // MARK: - Helpers

    private func expect(_ timeline: [TimelineEntry], matches row: Row, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let entry = try #require(
            GoldenHarness.Checkpoint.endOfPhase(row.bgTurn, .recruit).select(from: timeline),
            "no recruit phase for \(row)", sourceLocation: sourceLocation
        )
        let game = try #require(entry.state.game, sourceLocation: sourceLocation)
        let player = try #require(game.player, sourceLocation: sourceLocation)
        #expect("\(player.gold.thisTurn)/\(player.gold.used)" == row.gold, "\(row) gold", sourceLocation: sourceLocation)
        #expect(player.gold.available == player.gold.thisTurn + player.gold.temporary - player.gold.used, sourceLocation: sourceLocation)
        #expect(player.gold.cap == 10, "\(row) gold cap", sourceLocation: sourceLocation)
        #expect(player.tier == row.tier, "\(row) tier", sourceLocation: sourceLocation)
        #expect(player.hero?.hp == row.hp, "\(row) HP", sourceLocation: sourceLocation)
        #expect(player.board.map(Self.render) == row.board, "\(row) board", sourceLocation: sourceLocation)
        #expect(player.hand.map(Self.render) == row.hand, "\(row) hand", sourceLocation: sourceLocation)
        #expect(game.shop.cards.map(Self.render) == row.shop, "\(row) shop", sourceLocation: sourceLocation)
        #expect(game.shop.isFrozen == row.frozen, "\(row) frozen", sourceLocation: sourceLocation)
    }

    static let abbreviations: [BGKeyword: String] = [
        .taunt: "T", .divineShield: "DS", .reborn: "R", .poisonous: "P", .venomous: "V", .windfury: "WF",
        .megaWindfury: "MWF", .stealth: "S", .deathrattle: "DR", .battlecry: "BC", .avenge: "AV",
        .magnetic: "MAG", .rally: "RALLY", .frozen: "FRZ",
    ]

    static func render(_ card: CardView) -> String {
        var text = switch card.kind {
        case .minion: (card.golden ? "*" : "") + "\(card.attack ?? 0)/\(card.health ?? 0)"
        case .tavernSpell: "spell"
        case .other: "other"
        }
        if !card.keywords.isEmpty {
            text += " " + card.keywords.map { abbreviations[$0] ?? $0.rawValue }.joined(separator: ",")
        }
        return text
    }
}
