import TavernEngine

/// The debug window's "Lobby" pane: the leaderboard, next and current opponent,
/// last-seen boards, names and the final placement of the selected timeline entry.
enum DebugLobbyPane {
    static func describe(_ game: GameView) -> String {
        var lines = ["BG turn \(game.bgTurn), \(game.phase.rawValue)"]
        if let placement = game.placement {
            lines.append("Final placement: \(ordinal(placement.place))" + (placement.isEstimated ? " (estimated: conceded)" : ""))
        }
        lines.append("Next opponent: " + (game.nextOpponent.map(label) ?? game.nextOpponentPlayerID.map { "P\($0)" } ?? "–"))
        if let fighting = game.combatOpponentPlayerID {
            lines.append("Fighting now: " + (game.lobby.first { $0.playerID == fighting }.map(label) ?? "P\(fighting)"))
        }
        lines.append("")
        lines.append("Leaderboard (\(game.lobby.count)):")
        for entry in game.lobby {
            var row = "  \(entry.place.map { "\($0)." } ?? "–") \(label(entry))"
            row += "  HP \(entry.hero.hp)"
            if entry.hero.armor > 0 { row += " (armor \(entry.hero.armor))" }
            row += ", tier \(entry.tier.map(String.init) ?? "–"), triples \(entry.hero.triples)"
            if entry.isDead { row += ", dead" }
            if entry.isLocal { row += "  ← you" }
            if entry.playerID == game.nextOpponentPlayerID { row += "  ← next" }
            lines.append(row)
            if entry.isLocal { continue }
            if let board = entry.lastSeenBoard {
                lines.append("      last seen BG turn \(board.bgTurn) (\(board.cards.count) minions):")
                lines += board.cards.map { "        " + DebugWindow.describe($0) }
            } else {
                lines.append("      not seen")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "P3 Name — Hero" with whatever is known.
    static func label(_ entry: LobbyEntryView) -> String {
        var text = "P\(entry.playerID)"
        if let name = entry.displayName { text += " \(name)" }
        text += " — " + (entry.heroName ?? entry.heroCardID)
        return text
    }

    static func ordinal(_ place: Int) -> String {
        switch place {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(place)th"
        }
    }
}
