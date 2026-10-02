/// Independent client-packet decoder. It never reduces early GameState power into visible entities.
struct ActionPacketParser: Sendable {
    private var pendingOptions: PowerOptions?
    private var currentOption: Int?
    private var currentSubOption: Int?
    private var canAppendTargets = false
    private var detailRows = 0
    private var latestOptionsID: Int?
    private var pendingChoices: SentChoices?
    private static let optionsMethod: Substring = "GameState.DebugPrintOptions"
    private static let choicesMethod: Substring = "GameState.SendChoices"

    mutating func feed(_ line: LogLine, lineNumber: Int?, emit: (PowerEvent) -> Void) {
        let s = line.payload.trimmingSpaces()
        if pendingOptions != nil, line.method != Self.optionsMethod || s.hasASCIIPrefix("id=") {
            flushOptions(emit: emit)
        }
        if pendingChoices != nil, line.method != Self.choicesMethod || !s.hasASCIIPrefix("m_chosenEntities[") {
            flushChoices(emit: emit)
        }
        if (line.method == "GameState.DebugPrintPower" || line.method == "PowerTaskList.DebugPrintPower"), s == "CREATE_GAME" {
            latestOptionsID = nil
        }
        let position = lineNumber.map { LogPosition(line: $0, time: String(line.timestamp)) }
        switch line.method {
        case Self.optionsMethod:
            if s.hasASCIIPrefix("id=") {
                latestOptionsID = nil
                if let id = Self.intField(s, "id=") {
                    pendingOptions = PowerOptions(id: id, timestamp: String(line.timestamp), position: position)
                    currentOption = nil; currentSubOption = nil; canAppendTargets = false; detailRows = 0
                }
            } else {
                appendOptionRow(s)
            }
        case "GameState.SendOption":
            guard let option = Self.intField(s, "selectedOption="),
                  let subOption = Self.intField(s, "selectedSubOption="),
                  let target = Self.intField(s, "selectedTarget="),
                  let selectedPosition = Self.intField(s, "selectedPosition=") else { return }
            emit(.sendOption(SentOption(timestamp: String(line.timestamp), position: position,
                optionsID: latestOptionsID, selectedOption: option, selectedSubOption: subOption,
                selectedTarget: target, selectedPosition: selectedPosition)))
        case Self.choicesMethod:
            if s.hasASCIIPrefix("id=") {
                if let id = Self.intField(s, "id="), let type = Self.field(s, "ChoiceType=") {
                    pendingChoices = SentChoices(timestamp: String(line.timestamp), position: position,
                                                 id: id, choiceType: String(type))
                }
            } else if s.hasASCIIPrefix("m_chosenEntities["), pendingChoices != nil {
                guard pendingChoices!.chosen.count < 64,
                      let equals = s.firstRange(of: "]="), let entity = Self.entity(s[equals.upperBound...]) else {
                    pendingChoices?.isComplete = false; return
                }
                pendingChoices?.chosen.append(entity)
            }
        default: break
        }
    }

    mutating func finish(emit: (PowerEvent) -> Void) {
        flushChoices(emit: emit)
        flushOptions(emit: emit)
    }

    private mutating func flushOptions(emit: (PowerEvent) -> Void) {
        guard let packet = pendingOptions else { return }
        pendingOptions = nil; currentOption = nil; currentSubOption = nil; canAppendTargets = false; detailRows = 0
        latestOptionsID = packet.id
        emit(.options(packet))
    }

    private mutating func flushChoices(emit: (PowerEvent) -> Void) {
        guard let packet = pendingChoices else { return }
        pendingChoices = nil
        emit(.sendChoices(packet))
    }

    private mutating func appendOptionRow(_ s: Substring) {
        guard pendingOptions != nil else { return }
        if s.hasASCIIPrefix("option ") {
            currentOption = nil; currentSubOption = nil; canAppendTargets = false
            guard pendingOptions!.options.count < 128,
                  let index = Self.rowIndex(s), let type = Self.field(s, "type="),
                  let body = Self.entityBody(s, key: " mainEntity="),
                  body.isEmpty || Self.entity(body) != nil else {
                pendingOptions?.isComplete = false; return
            }
            let row = PowerOption(index: index, type: String(type), mainEntity: Self.entity(body),
                                  error: Self.error(s), errorParam: Self.errorParam(s))
            pendingOptions?.options.append(row)
            currentOption = pendingOptions!.options.count - 1
            canAppendTargets = true
        } else if s.hasASCIIPrefix("subOption ") {
            currentSubOption = nil; canAppendTargets = false
            guard let option = currentOption, detailRows < 4096, let index = Self.rowIndex(s),
                  let body = Self.entityBody(s, key: " entity="), let entity = Self.entity(body) else {
                pendingOptions?.isComplete = false; return
            }
            detailRows += 1
            pendingOptions?.options[option].subOptions.append(PowerSubOption(index: index, entity: entity,
                error: Self.error(s), errorParam: Self.errorParam(s)))
            currentSubOption = pendingOptions!.options[option].subOptions.count - 1
            canAppendTargets = true
        } else if s.hasASCIIPrefix("target ") {
            guard canAppendTargets, let option = currentOption, detailRows < 4096, let index = Self.rowIndex(s),
                  let body = Self.entityBody(s, key: " entity="), let entity = Self.entity(body) else {
                pendingOptions?.isComplete = false; return
            }
            detailRows += 1
            let target = PowerOptionTarget(index: index, entity: entity, error: Self.error(s), errorParam: Self.errorParam(s))
            if let sub = currentSubOption { pendingOptions?.options[option].subOptions[sub].targets.append(target) }
            else { pendingOptions?.options[option].targets.append(target) }
        } else {
            pendingOptions?.isComplete = false
        }
    }

    private static func entity(_ raw: Substring) -> ActionEntity? {
        let text = raw.trimmingSpaces()
        if let id = Int(text) { return ActionEntity(entityID: id) }
        guard let id = PowerLogParser.bracketID(text) else { return nil }
        return ActionEntity(entityID: id, cardID: PowerLogParser.bracketCardID(text) ?? "")
    }

    private static func entityBody(_ s: Substring, key: StaticString) -> Substring? {
        guard let start = s.firstRange(of: key) else { return nil }
        let remainder = s[start.upperBound...]
        if let error = remainder.lastRange(of: " error=") { return remainder[..<error.lowerBound].trimmingSpaces() }
        return remainder.trimmingSpaces()
    }

    private static func rowIndex(_ s: Substring) -> Int? {
        let fields = s.split(separator: " ", maxSplits: 2)
        return fields.count >= 2 ? Int(fields[1]) : nil
    }

    private static func intField(_ s: Substring, _ key: StaticString) -> Int? { field(s, key).flatMap { Int($0) } }
    private static func field(_ s: Substring, _ key: StaticString) -> Substring? {
        guard let range = s.firstRange(of: key) else { return nil }
        return s[range.upperBound...].prefix { $0 != " " }
    }
    private static func error(_ s: Substring) -> String? {
        guard let range = s.lastRange(of: " error=") else { return nil }
        return String(s[range.upperBound...].prefix { $0 != " " })
    }
    private static func errorParam(_ s: Substring) -> String? {
        guard let range = s.lastRange(of: " errorParam=") else { return nil }
        return String(s[range.upperBound...].prefix { $0 != " " })
    }
}
