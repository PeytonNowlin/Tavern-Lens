import Foundation
import TavernEngine

/// Firestone's mmr-100 hero stats as fetched on 2026-09-23 (rebuilt 00:10:26Z), trimmed by
/// `docs/research/validation-scripts/herostats/trim_hero_stats.py`: past-three has every hero,
/// past-seven and last-patch only the heroes past-three has under 300 games for plus the
/// full-game fixture's four offered heroes.
enum HeroStatsFixture {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Firestone", directoryHint: .isDirectory)

    static func file(_ window: HeroStatsWindow) -> FirestoneHeroStatsFile {
        let url = directory.appending(path: "hero-stats.mmr-100.\(window.rawValue).trimmed.json")
        return try! FirestoneHeroStatsFile(json: Data(contentsOf: url))
    }

    static let stats = HeroStatsSet(
        mmrPercentile: 100, files: Dictionary(uniqueKeysWithValues: HeroStatsWindow.allCases.map { ($0, file($0)) })
    )

    /// When the fixture files were rebuilt.
    static let updatedAt = Date(timeIntervalSince1970: 1_790_122_226.557)  // 2026-09-23T00:10:26.557Z
}

extension SyntheticLog {
    /// The hero-pick offer: the heroes are created in the local hand, then GameState prints the
    /// `MULLIGAN` choice listing them (ids from `firstID`), as in the captured logs.
    mutating func offerHeroes(
        _ cardIDs: [String], firstID: Int = 105, locked: Set<Int> = [], extra: [Int: [String]] = [:], choiceID: Int = 1
    ) {
        for (i, card) in cardIDs.enumerated() {
            let id = firstID + i
            power("FULL_ENTITY - Creating ID=\(id) CardID=\(card)")
            power("tag=CONTROLLER value=\(Self.localPlayerID)", indent: 8)
            power("tag=CARDTYPE value=HERO", indent: 8)
            power("tag=HEALTH value=30", indent: 8)
            power("tag=ZONE value=HAND", indent: 8)
            power("tag=ZONE_POSITION value=\(i + 1)", indent: 8)
            if locked.contains(id) { power("tag=BACON_LOCKED_MULLIGAN_HERO value=1", indent: 8) }
            for line in extra[id] ?? [] { power(line, indent: 8) }
        }
        endTaskList()
        choices(id: choiceID, type: "MULLIGAN", source: "GameEntity", options: cardIDs.enumerated().map { (firstID + $0, $1, "HAND") })
    }

    /// `GameState.DebugPrintEntityChoices` for the local player.
    mutating func choices(id: Int, type: String, source: String, options: [(id: Int, cardID: String, zone: String)]) {
        let method = "GameState.DebugPrintEntityChoices()"
        raw("D \(time) \(method) - id=\(id) Player=\(Self.localName) TaskList=1 ChoiceType=\(type) CountMin=1 CountMax=1")
        raw("D \(time) \(method) -   Source=\(source)")
        for (i, option) in options.enumerated() {
            raw("D \(time) \(method) -   Entities[\(i)]=[entityName=Option \(i) id=\(option.id) zone=\(option.zone) zonePos=\(i + 1) cardId=\(option.cardID) player=\(Self.localPlayerID)]")
        }
        raw("D \(time) ChoiceCardMgr.WaitThenShowChoices() - id=\(id) WAIT for taskList 1")
        endTaskList()
    }

    /// A hero reroll: the hand hero `id` becomes `cardID` in place.
    mutating func rerollHero(_ id: Int, from oldCardID: String, to cardID: String, extra: [String] = []) {
        power("CHANGE_ENTITY - Updating Entity=[entityName=Old Hero id=\(id) zone=HAND zonePos=2 cardId=\(oldCardID) player=\(Self.localPlayerID)] CardID=\(cardID)")
        power("tag=CARDTYPE value=HERO", indent: 8)
        for line in extra { power(line, indent: 8) }
        endTaskList()
    }

    /// `GameState.DebugPrintEntitiesChosen`: the player confirmed `id`.
    mutating func chooseHero(_ id: Int, cardID: String, choiceID: Int = 1) {
        let method = "GameState.DebugPrintEntitiesChosen()"
        raw("D \(time) \(method) - id=\(choiceID) Player=\(Self.localName) EntitiesCount=1")
        raw("D \(time) \(method) -   Entities[0]=[entityName=Chosen id=\(id) zone=HAND zonePos=1 cardId=\(cardID) player=\(Self.localPlayerID)]")
        raw("D \(time) ChoiceCardMgr.WaitThenHideChoicesFromPacket() - id=\(choiceID) END WAIT")
        endTaskList()
    }
}
