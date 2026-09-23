import TavernEngine

/// The mechanics section of the debug window's "Player & shop" pane: damage cap, Deity,
/// trinkets, hero powers, quests and counters for the local player and the combat opponent.
enum DebugMechanicsPane {
    static func lines(_ game: GameView) -> [String] {
        var lines = ["", "Mechanics:"]
        if let mechanics = game.mechanics {
            var row = "  Damage cap " + (mechanics.damageCap.map(String.init) ?? "–")
            row += mechanics.damageCapEnabled ? "" : " (off)"
            row += ", \(mechanics.playersAlive) alive"
            if let deity = mechanics.deityCardID ?? mechanics.deityDbfID.map({ "dbf \($0)" }) { row += ", Deity \(deity)" }
            if let anomaly = mechanics.anomalyCardID ?? mechanics.anomalyDbfID.map({ "dbf \($0)" }) { row += ", anomaly \(anomaly)" }
            lines.append(row)
        }
        if let local = game.player?.mechanics {
            lines.append("  You:")
            lines += describe(local).map { "    " + $0 }
        }
        if let opponent = game.combatOpponentMechanics {
            lines.append("  Combat opponent" + (game.combatOpponentPlayerID.map { " P\($0)" } ?? "") + ":")
            lines += describe(opponent).map { "    " + $0 }
        }
        return lines
    }

    static func describe(_ mechanics: MechanicsView) -> [String] {
        var lines: [String] = []
        if let deity = mechanics.deity {
            lines.append("Deity \(deity.name ?? deity.cardID ?? deity.dbfID.map { "dbf \($0)" } ?? "?") \(deity.attack)/\(deity.health)")
        }
        for power in mechanics.heroPowers {
            lines.append("Hero power \(power.name ?? power.cardID)" + (power.used ? " (used)" : "") + data(power.scriptData))
        }
        for trinket in mechanics.trinkets {
            lines.append("Trinket \(trinket.slot == 2 ? "greater" : "lesser") \(trinket.name ?? trinket.cardID)" + data(trinket.scriptData))
        }
        for quest in mechanics.quests {
            lines.append("Quest \(quest.name ?? quest.cardID) \(quest.progress)/\(quest.progressTotal)")
        }
        if !mechanics.questRewards.isEmpty { lines.append("Quest rewards: " + mechanics.questRewards.joined(separator: ", ")) }
        if !mechanics.secrets.isEmpty { lines.append("Secrets: " + mechanics.secrets.joined(separator: ", ")) }
        if let gem = mechanics.bloodGem { lines.append("Blood gems +\(gem.attack)/+\(gem.health)") }
        if let spell = mechanics.tavernSpellBuff { lines.append("Tavern spells +\(spell.attack)/+\(spell.health)") }
        if !mechanics.counters.isEmpty {
            let counters = mechanics.counters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            lines.append("Counters" + (mechanics.countersFromTagTransfer ? " (tag transfer)" : "") + ": " + counters.joined(separator: " "))
        }
        return lines
    }

    private static func data(_ values: [Int]?) -> String {
        guard let values else { return "" }
        return " [" + values.map(String.init).joined(separator: " ") + "]"
    }
}
