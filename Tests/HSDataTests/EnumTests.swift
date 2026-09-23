import Foundation
import HSData
import PowerParser
import Testing

/// The generated enums against the committed, build-pinned HearthstoneJSON `enums.json`.
@Suite("Generated enums")
struct EnumTests {
    static let dataDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Data/HearthstoneJSON", directoryHint: .isDirectory)

    static func enumsJSON() throws -> [String: [String: Int]] {
        let data = try Data(contentsOf: dataDirectory.appending(path: "enums.json"))
        return try JSONDecoder().decode([String: [String: Int]].self, from: data)
    }

    @Test("Every GameTag name in enums.json resolves to its number")
    func everyTagNameResolves() throws {
        let tags = try #require(try Self.enumsJSON()["GameTag"])
        #expect(tags.count > 1000)
        for (name, number) in tags {
            #expect(GameTag(token: Substring(name)) == .id(number), "\(name)")
        }
    }

    @Test("Tag numbers print as their canonical name; aliases resolve to the same number")
    func tagNames() {
        #expect(GameTag(token: "1440").description == "TECH_LEVEL")
        #expect(GameTag(token: "BACON_DUO_TEAM_ID") == .id(3095))
        // A tag the old hand-written table didn't have.
        #expect(GameTag(token: "BACON_HERO_CAN_BE_DRAFTED") != .unresolved("BACON_HERO_CAN_BE_DRAFTED"))
    }

    @Test("Unknown tags are kept: numbers as numbers, names as names")
    func unknownTagsPreserved() {
        let number = GameTag(token: "987654")
        #expect(number == .id(987_654))
        #expect(number.number == 987_654)
        #expect(number.description == "987654")

        let name = GameTag(token: "SOME_TAG_FROM_A_FUTURE_PATCH")
        #expect(name == .unresolved("SOME_TAG_FROM_A_FUTURE_PATCH"))
        #expect(name.description == "SOME_TAG_FROM_A_FUTURE_PATCH")
    }

    @Test("The engine's named tags match the generated table")
    func namedTagsMatch() {
        let expected: [(GameTag, String)] = [
            (.premium, "PREMIUM"), (.playState, "PLAYSTATE"), (.step, "STEP"), (.turn, "TURN"),
            (.currentPlayer, "CURRENT_PLAYER"), (.resourcesUsed, "RESOURCES_USED"), (.resources, "RESOURCES"),
            (.heroEntity, "HERO_ENTITY"), (.playerID, "PLAYER_ID"), (.damage, "DAMAGE"), (.health, "HEALTH"),
            (.atk, "ATK"), (.zone, "ZONE"), (.controller, "CONTROLLER"), (.entityID, "ENTITY_ID"),
            (.maxResources, "MAXRESOURCES"), (.cardType, "CARDTYPE"), (.state, "STATE"), (.frozen, "FROZEN"),
            (.zonePosition, "ZONE_POSITION"), (.armor, "ARMOR"), (.tempResources, "TEMP_RESOURCES"),
            (.boardVisualState, "BOARD_VISUAL_STATE"), (.baconDummyPlayer, "BACON_DUMMY_PLAYER"),
            (.nextOpponentPlayerID, "NEXT_OPPONENT_PLAYER_ID"), (.playerLeaderboardPlace, "PLAYER_LEADERBOARD_PLACE"),
            (.playerTechLevel, "PLAYER_TECH_LEVEL"), (.techLevel, "TECH_LEVEL"), (.playerTriples, "PLAYER_TRIPLES"),
            (.copiedFromEntityID, "COPIED_FROM_ENTITY_ID"), (.gameSeed, "GAME_SEED"),
            (.baconCurrentCombatPlayerID, "BACON_CURRENT_COMBAT_PLAYER_ID"), (.baconDuoTeamID, "BACON_DUO_TEAM_ID"),
        ]
        for (tag, name) in expected {
            #expect(GameTag(token: Substring(name)) == tag, "\(name)")
        }
    }

    @Test("The other enum groups are generated with names and values from enums.json")
    func otherGroups() throws {
        let json = try Self.enumsJSON()
        func check<E: HSEnumeration>(_: E.Type, _ group: String) throws {
            let members = try #require(json[group], "\(group)")
            #expect(E.valuesByName == members, "\(group)")
            for (name, value) in members {
                #expect(E(name: name)?.rawValue == value, "\(group).\(name)")
                #expect(E(rawValue: value).name != nil, "\(group).\(name)")
            }
        }
        try check(HS.CardType.self, "CardType")
        try check(HS.Zone.self, "Zone")
        try check(HS.Race.self, "Race")
        try check(HS.Step.self, "Step")
        try check(HS.State.self, "State")
        try check(HS.PlayState.self, "PlayState")
        try check(HS.GameType.self, "GameType")
        try check(HS.CardSet.self, "CardSet")
        try check(HS.SpellSchool.self, "SpellSchool")
        try check(HS.TagType.self, "Type")  // renamed: `HS.Type` isn't a legal Swift name

        #expect(HS.CardType.minion.rawValue == 4)
        #expect(HS.Race.quilboar.name == "QUILBOAR")
        #expect(HS.Zone.play == HS.Zone(name: "PLAY"))
    }

    @Test("With aliases, the first name in enums.json is canonical")
    func aliases() {
        #expect(HS.CardType(name: "ABILITY") == HS.CardType.spell)
        #expect(HS.CardType(rawValue: 5).description == "SPELL")
        #expect(HS.Race(rawValue: 20).description == "BEAST")
        #expect(HS.Zone(rawValue: 8).description == "LETTUCE_ABILITY")
    }

    @Test("Unknown enum numbers are kept, including through Codable")
    func unknownEnumValues() throws {
        let future = HS.Race(rawValue: 4242)
        #expect(!future.isKnown)
        #expect(future.description == "4242")
        #expect(HS.Race(name: "NOT_A_TRIBE") == nil)
        let data = try JSONEncoder().encode([future, .murloc])
        #expect(String(decoding: data, as: UTF8.self) == "[4242,14]")
        #expect(try JSONDecoder().decode([HS.Race].self, from: data) == [future, .murloc])
    }

    @Test("Both tables carry the pinned build")
    func pinnedBuild() throws {
        let pinned = try String(contentsOf: Self.dataDirectory.appending(path: "enums.build"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(String(GameTag.enumsBuild) == pinned)
        #expect(String(HS.enumsBuild) == pinned)
    }
}
