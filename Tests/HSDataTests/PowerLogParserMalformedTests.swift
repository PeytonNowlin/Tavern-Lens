import PowerParser
import Testing

/// Malformed and truncated lines of each header type: they must be counted, never crash,
/// and never emit a half-built event.
@Suite("Power log parser: malformed lines")
struct PowerLogParserMalformedTests {
    private static func power(_ payload: String) -> String {
        "D 12:00:00.0000000 PowerTaskList.DebugPrintPower() - \(payload)"
    }

    private func parse(_ payloads: [String], method: String = "PowerTaskList.DebugPrintPower")
        -> (events: [PowerEvent], diagnostics: ParseDiagnostics) {
        var parser = PowerLogParser()
        var events: [PowerEvent] = []
        for payload in payloads {
            parser.feed("D 12:00:00.0000000 \(method)() - \(payload)") { events.append($0) }
        }
        parser.finish { events.append($0) }
        return (events, parser.diagnostics)
    }

    @Test("Truncated or malformed power headers count as malformed and emit nothing", arguments: [
        "TAG_CHANGE Entity=",
        "TAG_CHANGE Entity=[id=1] tag=ZONE",
        "TAG_CHANGE Entity= tag=ZONE value=HAND",
        "TAG_CHANGE Entity=5 tag= value=HAND",
        "FULL_ENTITY - Updating 5",
        "FULL_ENTITY - Creating ID=",
        "FULL_ENTITY - Creating ID=abc CardID=X",
        "FULL_ENTITY - Creating ID=12",
        "SHOW_ENTITY - Updating Entity=",
        "SHOW_ENTITY - Updating Entity=5",
        "CHANGE_ENTITY - Updating Entity=",
        "CHANGE_ENTITY - Updating Entity=5 CardID",
        "HIDE_ENTITY - Entity=",
        "HIDE_ENTITY - Entity=5",
        "GameEntity EntityID=",
        "GameEntity EntityID=x",
        "Player EntityID=",
        "Player EntityID=3",
    ])
    func malformedHeader(payload: String) {
        let result = parse([payload])
        #expect(result.events.isEmpty)
        #expect(result.diagnostics.malformedPowerLines == 1)
    }

    @Test("Well-formed lines of each header type parse")
    func wellFormed() {
        let result = parse([
            "TAG_CHANGE Entity=5 tag=ZONE value=HAND",
            "TAG_CHANGE Entity=5 tag=ZONE value=HAND DEF CHANGE",
            "FULL_ENTITY - Creating ID=12 CardID=BG_X",
            "SHOW_ENTITY - Updating Entity=5 CardID=BG_Y",
            "HIDE_ENTITY - Entity=5 tag=ZONE value=HAND",
            "BLOCK_START BlockType=PLAY Entity=5 EffectCardId=",
            "BLOCK_END",
        ])
        #expect(result.diagnostics.malformedPowerLines == 0)
        #expect(result.events.contains(.fullEntity(.id(12), cardID: "BG_X", tags: [])))
        #expect(result.events.contains(.hideEntity(.id(5))))
        #expect(result.events.contains(.blockStart(type: "PLAY", entity: .id(5))))
        #expect(result.events.last == .blockEnd)
    }

    @Test("A truncated header still flushes the previous one and drops no tags")
    func truncatedAfterHeader() {
        let result = parse([
            "GameEntity EntityID=1",
            "tag=STATE value=RUNNING",
            "FULL_ENTITY - Creating ID=",
        ])
        #expect(result.events.count == 1)
        #expect(result.diagnostics.malformedPowerLines == 1)
    }

    @Test("A tag line with no header, or without a value, is an orphan")
    func orphanTags() {
        let result = parse(["tag=ZONE value=HAND", "GameEntity EntityID=1", "tag=ZONE"])
        #expect(result.diagnostics.orphanTagLines == 2)
    }

    @Test("BLOCK_START with an unreadable entity keeps the type and drops the entity")
    func blockStartUnreadable() {
        let result = parse(["BLOCK_START BlockType=TRIGGER Entity=[broken"])
        #expect(result.events == [.blockStart(type: "TRIGGER", entity: nil)])
        #expect(result.diagnostics.unreadableEntityRefs == 1)
    }

    @Test("Unrecognised power lines are ignored without a diagnostic")
    func unknownIgnored() {
        let result = parse(["META_DATA - Meta=OVERRIDE_HISTORY", "Info[0] = [x]", ""])
        #expect(result.events.isEmpty)
        #expect(result.diagnostics.malformedPowerLines == 0)
    }

    @Test("Truncated choice lines are malformed", arguments: [
        "id=1 Player=x TaskList=7",
        "id= Player=x ChoiceType=GENERAL",
        "Source=GameEntity",
        "Entities[0]=",
        "garbage",
    ])
    func choiceMalformed(payload: String) {
        let result = parse([payload], method: "GameState.DebugPrintEntityChoices")
        #expect(result.events.isEmpty)
        #expect(result.diagnostics.malformedPowerLines >= 1)
    }

    @Test("Truncated chosen lines are malformed", arguments: ["id=", "id=x EntitiesCount=1", "Entities[0]=[bad", "garbage"])
    func chosenMalformed(payload: String) {
        let result = parse([payload], method: "GameState.DebugPrintEntitiesChosen")
        #expect(result.events.isEmpty)
        #expect(result.diagnostics.malformedPowerLines >= 1)
    }

    @Test("Option packets with bad rows are flagged incomplete, not dropped")
    func optionRowsIncomplete() {
        let result = parse([
            "id=3",
            "option 0 type=END_TURN mainEntity=",
            "option x type=POWER mainEntity=5",
            "subOption 0 entity=5",
            "target 0 entity=5",
            "mystery row",
        ], method: "GameState.DebugPrintOptions")
        guard case .options(let packet)? = result.events.first else {
            Issue.record("expected an options packet")
            return
        }
        #expect(packet.id == 3)
        #expect(!packet.isComplete)
        #expect(packet.options.count == 1)
    }

    @Test("An options header without an id emits nothing; truncated SendOption is dropped")
    func truncatedActions() {
        #expect(parse(["id="], method: "GameState.DebugPrintOptions").events.isEmpty)
        let sent = parse(["selectedOption=1 selectedSubOption=0 selectedTarget="], method: "GameState.SendOption")
        #expect(sent.events.isEmpty)
    }

    @Test("SendChoices: a bad entity row marks the packet incomplete; a missing ChoiceType drops it")
    func sendChoices() {
        let bad = parse(["id=2 ChoiceType=GENERAL", "m_chosenEntities[0]=[bad"], method: "GameState.SendChoices")
        guard case .sendChoices(let packet)? = bad.events.first else {
            Issue.record("expected a sendChoices packet")
            return
        }
        #expect(!packet.isComplete)
        #expect(parse(["id=2"], method: "GameState.SendChoices").events.isEmpty)
    }

    @Test("SendChoices caps the chosen entities")
    func chosenCap() {
        var lines = ["id=2 ChoiceType=GENERAL"]
        for i in 0...64 { lines.append("m_chosenEntities[\(i)]=\(i + 1)") }
        let result = parse(lines, method: "GameState.SendChoices")
        guard case .sendChoices(let packet)? = result.events.first else {
            Issue.record("expected a sendChoices packet")
            return
        }
        #expect(packet.chosen.count == 64)
        #expect(!packet.isComplete)
    }
}
