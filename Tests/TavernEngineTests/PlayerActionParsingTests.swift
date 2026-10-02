import Foundation
import Testing
import PowerParser
import GzipSupport
import HSLog
import TavernEngine

@Suite("Client action packets")
struct PlayerActionParsingTests {
    @Test("Outgoing selection retains its offered group, target, position and original timestamp")
    func optionSelection() throws {
        var parser = PowerLogParser()
        var events: [PowerEvent] = []
        let lines = [
            "D 16:42:48.1795170 GameState.DebugPrintOptions() - id=1",
            "D 16:42:48.1795170 GameState.DebugPrintOptions() -   option 0 type=END_TURN mainEntity= error=INVALID errorParam=",
            "D 16:42:48.1795170 GameState.DebugPrintOptions() -   option 8 type=POWER mainEntity=[entityName=Private Name [tag] id=436 zone=PLAY zonePos=0 cardId=TB_BaconShop_DragBuy player=6] error=NONE errorParam=",
            "D 16:42:48.1795170 GameState.DebugPrintOptions() -     target 0 entity=[entityName=Buzzing Vermin id=435 zone=PLAY zonePos=3 cardId=BG31_803 player=14] error=NONE errorParam=",
            "D 16:42:48.1795170 GameState.DebugPrintOptions() -     target 1 entity=[entityName=Other Private Name id=91 zone=PLAY zonePos=0 cardId=BG27_HERO_801 player=6] error=REQ_ENEMY_TARGET errorParam=",
            "D 16:42:51.2485580 GameState.SendOption() - selectedOption=8 selectedSubOption=-1 selectedTarget=435 selectedPosition=0",
        ]
        for line in lines { parser.feed(line) { events.append($0) } }
        parser.finish { events.append($0) }
        let offers = events.compactMap { event -> PowerOptions? in
            if case .options(let options) = event { return options }; return nil
        }
        let offer = try #require(offers.first)
        #expect(offers.count == 1)
        #expect(offer.id == 1 && offer.timestamp == "16:42:48.1795170")
        #expect(offer.options.first?.mainEntity == nil)
        #expect(offer.options.first?.error == "INVALID")
        #expect(offer.options.last?.mainEntity?.entityID == 436)
        #expect(offer.options.last?.targets.map(\.entity.entityID) == [435, 91])
        #expect(offer.options.last?.targets.last?.error == "REQ_ENEMY_TARGET")
        let sent = try #require(events.compactMap { event -> SentOption? in
            if case .sendOption(let selection) = event { return selection }; return nil
        }.first)
        #expect(sent.optionsID == 1)
        #expect(sent.timestamp == "16:42:51.2485580")
        #expect(sent.selectedOption == 8 && sent.selectedSubOption == -1)
        #expect(sent.selectedTarget == 435 && sent.selectedPosition == 0)
        let archive = String(decoding: try JSONEncoder().encode(offer), as: UTF8.self)
        #expect(!archive.contains("Private Name") && !archive.contains("entityName"))
    }

    @Test("Multiline client choices preserve header position before the following effect")
    func choicesSelection() throws {
        var parser = PowerLogParser()
        var events: [PowerEvent] = []
        let lines = [
            "D 16:45:29.8624760 GameState.SendChoices() - id=3 ChoiceType=GENERAL",
            "D 16:45:29.8624760 GameState.SendChoices() -   m_chosenEntities[0]=[entityName=Private#1234 id=1711 zone=SETASIDE zonePos=0 cardId=BG36_201 player=6]",
            "D 16:45:29.9000000 PowerTaskList.DebugPrintPower() - TAG_CHANGE Entity=1711 tag=ZONE value=HAND",
        ]
        for (offset, line) in lines.enumerated() {
            parser.feed(line, lineNumber: 100 + offset) { events.append($0) }
        }
        let sent = try #require(events.compactMap { event -> SentChoices? in
            if case .sendChoices(let selection) = event { return selection }; return nil
        }.first)
        #expect(sent.id == 3 && sent.choiceType == "GENERAL")
        #expect(sent.position == LogPosition(line: 100, time: "16:45:29.8624760"))
        #expect(sent.chosen == [ActionEntity(entityID: 1711, cardID: "BG36_201")])
        #expect(events.first == .sendChoices(sent))
        #expect(events.last == .tagChange(.id(1711), .init(tag: .zone, value: .name("HAND"))))
        let data = try JSONEncoder().encode(sent)
        #expect(!String(decoding: data, as: UTF8.self).contains("Private#1234"))
    }

    @Test("Suboption targets remain attached to their own option and retain rejection details")
    func subOptionTargets() throws {
        var parser = PowerLogParser()
        var offers: [PowerOptions] = []
        let payloads = [
            "id=77",
            "option 9 type=POWER mainEntity=5 error=NONE errorParam=",
            "target 0 entity=6 error=NONE errorParam=",
            "subOption 0 entity=10610 error=NONE errorParam=",
            "target 0 entity=8 error=128 errorParam=52",
            "subOption 1 entity=10611 error=NONE errorParam=",
            "target 0 entity=9 error=NONE errorParam=",
        ]
        for payload in payloads {
            parser.feed("D 16:52:01.1234567 GameState.DebugPrintOptions() - \(payload)") {
                if case .options(let options) = $0 { offers.append(options) }
            }
        }
        parser.finish { if case .options(let options) = $0 { offers.append(options) } }
        let option = try #require(offers.first?.options.first)
        #expect(option.targets.map(\.entity.entityID) == [6])
        #expect(option.subOptions.map(\.entity.entityID) == [10610, 10611])
        #expect(option.subOptions[0].targets.first?.entity.entityID == 8)
        #expect(option.subOptions[0].targets.first?.error == "128")
        #expect(option.subOptions[0].targets.first?.errorParam == "52")
        #expect(option.subOptions[1].targets.map(\.entity.entityID) == [9])
        #expect(option.errorParam == "")
    }

    @Test("A missing or previous game's offer is never attributed to a new selection")
    func missingAndResetGroup() {
        var parser = PowerLogParser()
        var selections: [SentOption] = []
        let outgoing = "selectedOption=1 selectedSubOption=-1 selectedTarget=0 selectedPosition=0"
        let lines = [
            "D 12:00:00.0000000 GameState.SendOption() - \(outgoing)",
            "D 12:00:00.0000000 GameState.DebugPrintOptions() - id=7",
            "D 12:00:00.0000000 GameState.DebugPrintOptions() - option 1 type=POWER mainEntity=9 error=NONE errorParam=",
            "D 12:00:00.0000000 GameState.SendOption() - \(outgoing)",
            "D 12:00:00.0000000 GameState.DebugPrintPower() - CREATE_GAME",
            "D 12:00:00.0000000 GameState.SendOption() - \(outgoing)",
            "D 12:00:00.0000000 GameState.SendOption() - selectedOption=bad selectedSubOption=-1 selectedTarget=0 selectedPosition=0",
        ]
        for line in lines { parser.feed(line) { if case .sendOption(let selection) = $0 { selections.append(selection) } } }
        #expect(selections.count == 3)
        #expect(selections.map(\.optionsID) == [nil, 7, nil])
    }

    @Test("Excessive offered rows are bounded and explicitly incomplete")
    func optionBound() throws {
        var parser = PowerLogParser()
        var offers: [PowerOptions] = []
        parser.feed("D 12:00:00.0000000 GameState.DebugPrintOptions() - id=7") { _ in }
        for index in 0..<140 {
            parser.feed("D 12:00:00.0000000 GameState.DebugPrintOptions() - option \(index) type=POWER mainEntity=\(index + 1) error=NONE errorParam=") { _ in }
        }
        parser.finish { if case .options(let offer) = $0 { offers.append(offer) } }
        let offer = try #require(offers.first)
        #expect(offer.options.count == 128 && !offer.isComplete)
    }

    @Test("Targets following an unreadable suboption cannot be reassigned to its parent")
    func malformedSubOption() throws {
        var parser = PowerLogParser()
        var offers: [PowerOptions] = []
        for payload in ["id=7", "option 1 type=POWER mainEntity=9 error=NONE errorParam=",
                        "subOption 0 entity=unreadable error=NONE errorParam=",
                        "target 0 entity=99 error=NONE errorParam=",
                        "subOption 1 entity=11 error=NONE errorParam=",
                        "target 0 entity=12 error=NONE errorParam="] {
            parser.feed("D 12:00:00.0000000 GameState.DebugPrintOptions() - \(payload)") { _ in }
        }
        parser.finish { if case .options(let offer) = $0 { offers.append(offer) } }
        let offer = try #require(offers.first), option = try #require(offer.options.first)
        #expect(!offer.isComplete && option.targets.isEmpty)
        #expect(option.subOptions.first?.targets.map(\.entity.entityID) == [12])
    }

    @Test("Optional saved replay verifies client packet counts without publishing private log text")
    func savedReplayPackets() throws {
        guard let path = ProcessInfo.processInfo.environment["TAVERN_ACTION_REPLAY"] else { return }
        let replay = try #require(ReplayFile(url: URL(filePath: path)))
        #expect(replay.gameSeed == 2095227427)
        let data = try Gzip.decompress(Data(contentsOf: replay.url))
        var parser = PowerLogParser(), splitter = LogLineSplitter()
        var groups = 0, options = 0, choices = 0, incompleteGroups = 0
        var lineNumber = replay.line
        func count(_ event: PowerEvent) {
            switch event {
            case .options(let offer): groups += 1; if !offer.isComplete { incompleteGroups += 1 }
            case .sendOption: options += 1
            case .sendChoices: choices += 1
            default: break
            }
        }
        splitter.append(data) { line in
            parser.feed(line, lineNumber: lineNumber, emit: count); lineNumber += 1
        }
        if let last = splitter.finish() { parser.feed(last, lineNumber: lineNumber, emit: count) }
        parser.finish(emit: count)
        #expect(groups == 129 && options == 117 && choices == 11)
        #expect(incompleteGroups == 0)
    }
}
