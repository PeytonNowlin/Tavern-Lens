import Foundation

/// Battle.net account names (`Name#1234`), which committed goldens and exported cases must never hold.
public enum BattleTag {
    /// Whether `text` holds anything shaped like a BattleTag.
    public static func appears(in text: String) -> Bool {
        text.contains(/[\p{L}\p{N}_]+#\d{3,}/)
    }
}

extension TimelineEntry {
    /// Opponents' display names are real account names: keeps only that one is known, as `Opp-P<PlayerID>`.
    public func redactingNames() -> TimelineEntry {
        var entry = self
        if var game = entry.state.game {
            for index in game.lobby.indices where game.lobby[index].displayName != nil {
                game.lobby[index].displayName = "Opp-P\(game.lobby[index].playerID)"
            }
            entry.state.game = game
        }
        return entry
    }
}

extension GameRecord {
    /// Display names become `Opp-P<PlayerID>`, as in `TimelineEntry.redactingNames()`; bookmarks are dropped.
    public func redactingNames() -> GameRecord {
        var record = self
        record.journal.displayNames = Dictionary(uniqueKeysWithValues: journal.displayNames.keys.map { ($0, "Opp-P\($0)") })
        record.bookmarks = []
        return record
    }
}
