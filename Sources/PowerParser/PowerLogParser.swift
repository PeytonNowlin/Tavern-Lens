/// Counts of lines the parser tolerated rather than understood.
public struct ParseDiagnostics: Hashable, Sendable, Codable {
    /// Lines that don't match the `<Level> <time> <Method>() - <payload>` grammar.
    public var unparsableLines = 0
    /// `tag=` lines with no entity header to attach to.
    public var orphanTagLines = 0
    /// Power lines whose packet type was recognised but whose shape wasn't.
    public var malformedPowerLines = 0
    /// Entity references in bracket form that lacked a readable `id`.
    public var unreadableEntityRefs = 0

    public init() {}
}

/// Turns Power.log lines into `PowerEvent`s.
///
/// Rules (validated in docs/research/log-validation-2026-09-22.md):
/// - State comes from `PowerTaskList.DebugPrintPower` only; `GameState.DebugPrintPower`
///   is dropped except for its `CREATE_GAME`, which announces the next game.
/// - Indentation is ignored. A `tag=` line belongs to the most recent
///   `GameEntity`/`Player`/`FULL_ENTITY`/`SHOW_ENTITY`/`CHANGE_ENTITY` header;
///   any other power line closes that header.
/// - Only `id` is read from bracketed entity references; nested brackets in the
///   entity name are tolerated by anchoring on the tail.
///
/// Header events are emitted once the header closes, so they carry all their tags.
public struct PowerLogParser: Sendable {
    public private(set) var diagnostics = ParseDiagnostics()
    /// The number of the task list that ended last (`EndCurrentTaskList() - m_currentTaskList=N`),
    /// which a choice's `TaskList=` refers to.
    public private(set) var lastTaskListEnded: Int?

    private enum Header: Sendable {
        case gameEntity(id: Int)
        case player(entityID: Int, playerID: Int, hi: UInt64, lo: UInt64)
        case full(EntityRef, cardID: String)
        case show(EntityRef, cardID: String)
        case change(EntityRef, cardID: String)
    }

    private var header: Header?
    private var headerTags: [TagAssignment] = []

    /// A multi-line choice block being read: its header, then `Source=` and `Entities[n]=` lines.
    private enum PendingChoice: Sendable {
        case choices(EntityChoice)
        case chosen(id: Int, [ChoiceOption])
    }

    private var pendingChoice: PendingChoice?
    private var actionPackets = ActionPacketParser()

    public init() {}

    /// Parses a raw line. Returns the parsed line (for its timestamp) or nil if unparsable.
    @discardableResult
    public mutating func feed(_ text: String, lineNumber: Int? = nil, emit: (PowerEvent) -> Void) -> LogLine? {
        guard let line = LogLine(text) else {
            diagnostics.unparsableLines += 1
            return nil
        }
        feed(line, lineNumber: lineNumber, emit: emit)
        return line
    }

    public mutating func feed(_ line: LogLine, lineNumber: Int? = nil, emit: (PowerEvent) -> Void) {
        if pendingChoice != nil, !continuesChoice(line) { flushChoice(emit: emit) }
        actionPackets.feed(line, lineNumber: lineNumber, emit: emit)
        switch line.method {
        case "PowerTaskList.DebugPrintPower":
            feedPower(line.payload, emit: emit)
        case "GameState.DebugPrintGame":
            if let field = Self.metadata(line.payload) { emit(.gameMetadata(field)) }
        case "PowerProcessor.EndCurrentTaskList":
            flushHeader(emit: emit)
            if let number = Self.intField(line.payload.trimmingSpaces(), "m_currentTaskList=") { lastTaskListEnded = number }
            emit(.taskListEnd)
        case "GameState.DebugPrintPower":
            if line.payload.trimmingSpaces() == "CREATE_GAME" {
                lastTaskListEnded = nil
                emit(.newGameAnnounced)
            }
        case Self.choicesMethod:
            feedChoices(line.payload)
        case Self.chosenMethod:
            feedChosen(line.payload)
        default:
            break
        }
    }

    /// Call at end of input so a trailing header is not lost.
    public mutating func finish(emit: (PowerEvent) -> Void) {
        flushChoice(emit: emit)
        actionPackets.finish(emit: emit)
        flushHeader(emit: emit)
    }

    // MARK: - Choices

    private static let choicesMethod: Substring = "GameState.DebugPrintEntityChoices"
    private static let chosenMethod: Substring = "GameState.DebugPrintEntitiesChosen"

    /// A `Source=` or `Entities[n]=` line of the choice block being read.
    private func continuesChoice(_ line: LogLine) -> Bool {
        let method: Substring = switch pendingChoice {
        case .choices?: Self.choicesMethod
        case .chosen?: Self.chosenMethod
        case nil: ""
        }
        guard line.method == method else { return false }
        let s = line.payload.trimmingSpaces()
        return s.hasASCIIPrefix("Source=") || s.hasASCIIPrefix("Entities[")
    }

    /// `id=1 Player=<name> TaskList=7 ChoiceType=MULLIGAN CountMin=1 CountMax=1`, then its lines.
    private mutating func feedChoices(_ payload: Substring) {
        let s = payload.trimmingSpaces()
        if s.hasASCIIPrefix("Source="), case .choices(var choice)? = pendingChoice {
            let text = s.dropFirst("Source=".count)
            choice.source = entityRef(text)
            choice.sourceCardID = Self.bracketCardID(text.trimmingSpaces())
            pendingChoice = .choices(choice)
        } else if s.hasASCIIPrefix("Entities["), case .choices(var choice)? = pendingChoice {
            if let option = choiceOption(s) { choice.options.append(option) }
            pendingChoice = .choices(choice)
        } else if s.hasASCIIPrefix("id="), let id = Self.intField(s, "id="),
                  let type = Self.field(s, " ChoiceType=") {
            pendingChoice = .choices(EntityChoice(
                id: id, choiceType: String(type), taskList: Self.intField(s, " TaskList=")
            ))
        } else {
            malformed()
        }
    }

    /// `id=1 Player=<name> EntitiesCount=1`, then its `Entities[n]=` lines.
    private mutating func feedChosen(_ payload: Substring) {
        let s = payload.trimmingSpaces()
        if s.hasASCIIPrefix("Entities["), case .chosen(let id, var options)? = pendingChoice {
            if let option = choiceOption(s) { options.append(option) }
            pendingChoice = .chosen(id: id, options)
        } else if s.hasASCIIPrefix("id="), let id = Self.intField(s, "id=") {
            pendingChoice = .chosen(id: id, [])
        } else {
            malformed()
        }
    }

    private mutating func flushChoice(emit: (PowerEvent) -> Void) {
        guard let pending = pendingChoice else { return }
        pendingChoice = nil
        switch pending {
        case .choices(let choice): emit(.entityChoices(choice))
        case .chosen(let id, let options): emit(.entitiesChosen(choiceID: id, chosen: options))
        }
    }

    /// `Entities[0]=[entityName=… id=105 zone=HAND zonePos=1 cardId=BG35_HERO_001 player=6]`.
    private mutating func choiceOption(_ s: Substring) -> ChoiceOption? {
        guard let equals = s.firstRange(of: "]=") else {
            malformed()
            return nil
        }
        let text = s[equals.upperBound...].trimmingSpaces()
        guard case .id(let id)? = entityRef(text) else {
            malformed()
            return nil
        }
        return ChoiceOption(entityID: id, cardID: Self.bracketCardID(text) ?? "")
    }

    /// The integer after `key` (up to the next space).
    private static func intField(_ s: Substring, _ key: StaticString) -> Int? {
        s.fieldValue(after: key, allowEmpty: false).flatMap { Int($0) }
    }

    /// The value after `key` up to the next space; nil when `key` is absent or the value empty.
    private static func field(_ s: Substring, _ key: StaticString) -> Substring? {
        s.fieldValue(after: key, allowEmpty: false)
    }

    // MARK: - Power payloads

    private mutating func feedPower(_ payload: Substring, emit: (PowerEvent) -> Void) {
        let s = payload.trimmingSpaces()
        if s.hasASCIIPrefix("tag=") {
            guard header != nil, let (tag, value) = Self.tagAndValue(s.dropFirst(4)) else {
                diagnostics.orphanTagLines += 1
                return
            }
            headerTags.append(TagAssignment(tag: GameTag(token: tag), value: TagValue(token: value)))
            return
        }
        flushHeader(emit: emit)

        if s == "BLOCK_END" {
            emit(.blockEnd)
        } else if s == "CREATE_GAME" {
            emit(.createGame)
        } else if let row = Self.powerRows.first(where: { s.hasASCIIPrefix($0.prefix) }) {
            let body = s.dropFirst(row.prefix.utf8CodeUnitCount)
            if !row.parse(&self, body, s, emit) { malformed() }
        }
        // Everything else (META_DATA, SUB_SPELL_*, Info[n], Source, Targets, …) is ignored for now.
    }

    /// One recognised power line: its prefix and the helper that reads the rest.
    /// A helper returns false when the line's shape is wrong, which counts as malformed.
    private struct PowerRow: Sendable {
        let prefix: StaticString
        /// `(parser, text after the prefix, the whole trimmed line, emit)`.
        let parse: @Sendable (inout PowerLogParser, Substring, Substring, (PowerEvent) -> Void) -> Bool
    }

    private static let powerRows: [PowerRow] = [
        PowerRow(prefix: "TAG_CHANGE Entity=") { $0.parseTagChange($1, $3) },
        PowerRow(prefix: "FULL_ENTITY - Updating ") { p, body, _, _ in
            guard let (ref, card) = p.refAndCard(body) else { return false }
            p.open(.full(ref, cardID: card))
            return true
        },
        PowerRow(prefix: "FULL_ENTITY - Creating ID=") { p, body, _, _ in
            guard let split = body.firstRange(of: " CardID="), let id = Int(body[..<split.lowerBound]) else {
                return false
            }
            p.open(.full(.id(id), cardID: String(body[split.upperBound...])))
            return true
        },
        PowerRow(prefix: "SHOW_ENTITY - Updating Entity=") { p, body, _, _ in
            guard let (ref, card) = p.refAndCard(body) else { return false }
            p.open(.show(ref, cardID: card))
            return true
        },
        PowerRow(prefix: "CHANGE_ENTITY - Updating Entity=") { p, body, _, _ in
            guard let (ref, card) = p.refAndCard(body) else { return false }
            p.open(.change(ref, cardID: card))
            return true
        },
        PowerRow(prefix: "HIDE_ENTITY - Entity=") { p, body, _, emit in
            guard let (ref, _, _) = p.refTagValue(body) else { return false }
            emit(.hideEntity(ref))
            return true
        },
        PowerRow(prefix: "BLOCK_START BlockType=") { p, body, _, emit in
            p.parseBlockStart(body, emit: emit)
            return true
        },
        PowerRow(prefix: "GameEntity EntityID=") { p, body, _, _ in
            guard let id = Int(body) else { return false }
            p.open(.gameEntity(id: id))
            return true
        },
        PowerRow(prefix: "Player EntityID=") { p, _, s, _ in
            guard let player = Self.playerHeader(s) else { return false }
            p.open(player)
            return true
        },
    ]

    /// `TAG_CHANGE Entity=<ref> tag=<T> value=<V>`, optionally ending ` DEF CHANGE`.
    private mutating func parseTagChange(_ rest: Substring, _ emit: (PowerEvent) -> Void) -> Bool {
        var body = rest
        if body.hasASCIISuffix(" DEF CHANGE") { body = body.dropLast(" DEF CHANGE".count).trimmingSpaces() }
        guard let (ref, tag, value) = refTagValue(body) else { return false }
        emit(.tagChange(ref, TagAssignment(tag: GameTag(token: tag), value: TagValue(token: value))))
        return true
    }

    /// `BLOCK_START BlockType=<T> Entity=<ref> EffectCardId=…`; the entity is optional.
    private mutating func parseBlockStart(_ body: Substring, emit: (PowerEvent) -> Void) {
        let type = body.prefix { $0 != " " }
        var ref: EntityRef?
        if let entityStart = body.firstRange(of: " Entity=") {
            let rest = body[entityStart.upperBound...]
            let refText = rest.firstRange(of: " EffectCardId=").map { rest[..<$0.lowerBound] } ?? rest
            ref = entityRef(refText)
        }
        emit(.blockStart(type: String(type), entity: ref))
    }

    private mutating func open(_ newHeader: Header) {
        header = newHeader
        headerTags = []
    }

    private mutating func flushHeader(emit: (PowerEvent) -> Void) {
        guard let current = header else { return }
        let tags = headerTags
        header = nil
        headerTags = []
        switch current {
        case .gameEntity(let id): emit(.gameEntity(id: id, tags: tags))
        case .player(let eid, let pid, let hi, let lo):
            emit(.player(entityID: eid, playerID: pid, accountHi: hi, accountLo: lo, tags: tags))
        case .full(let ref, let card): emit(.fullEntity(ref, cardID: card, tags: tags))
        case .show(let ref, let card): emit(.showEntity(ref, cardID: card, tags: tags))
        case .change(let ref, let card): emit(.changeEntity(ref, cardID: card, tags: tags))
        }
    }

    private mutating func malformed() {
        diagnostics.malformedPowerLines += 1
    }

    // MARK: - Pieces

    /// `<ref> tag=<T> value=<V>`. Anchors on the last ` tag=` so names can't confuse it.
    private mutating func refTagValue(_ body: Substring) -> (EntityRef, Substring, Substring)? {
        guard let tagRange = body.lastRange(of: " tag="),
              let (tag, value) = Self.tagAndValue(body[tagRange.upperBound...]),
              let ref = entityRef(body[..<tagRange.lowerBound])
        else { return nil }
        return (ref, tag, value)
    }

    /// `<ref> CardID=<id>`.
    private mutating func refAndCard(_ body: Substring) -> (EntityRef, String)? {
        guard let cardRange = body.lastRange(of: " CardID="),
              let ref = entityRef(body[..<cardRange.lowerBound])
        else { return nil }
        return (ref, String(body[cardRange.upperBound...].trimmingSpaces()))
    }

    private mutating func entityRef(_ raw: Substring) -> EntityRef? {
        let text = raw.trimmingSpaces()
        if text.isEmpty { return nil }
        if text == "GameEntity" { return .gameEntity }
        if let id = Int(text) { return .id(id) }
        if text.first == "[" {
            if let id = Self.bracketID(text) { return .id(id) }
            diagnostics.unreadableEntityRefs += 1
            return nil
        }
        return .playerName(String(text))
    }

    /// Reads `id` from `[entityName=<anything> id=N zone=Z zonePos=P cardId=C player=Q]`.
    /// The name may itself contain brackets, so this works backwards from the tail.
    static func bracketID(_ text: Substring) -> Int? {
        guard text.last == "]",
              let playerRange = text.lastRange(of: " player="),
              let cardRange = text[..<playerRange.lowerBound].lastRange(of: " cardId="),
              let zonePosRange = text[..<cardRange.lowerBound].lastRange(of: " zonePos="),
              let zoneRange = text[..<zonePosRange.lowerBound].lastRange(of: " zone="),
              let idRange = text[..<zoneRange.lowerBound].lastRange(of: " id=")
        else { return nil }
        return Int(text[idRange.upperBound..<zoneRange.lowerBound])
    }

    /// Reads `cardId` from a bracketed entity reference, working backwards from the tail;
    /// nil when it isn't in bracket form or the card is hidden (empty).
    static func bracketCardID(_ text: Substring) -> String? {
        guard text.last == "]",
              let playerRange = text.lastRange(of: " player="),
              let cardRange = text[..<playerRange.lowerBound].lastRange(of: " cardId=")
        else { return nil }
        let card = text[cardRange.upperBound..<playerRange.lowerBound]
        return card.isEmpty ? nil : String(card)
    }

    /// `<T> value=<V>` with anything after the value's first space ignored.
    static func tagAndValue(_ text: Substring) -> (Substring, Substring)? {
        guard let valueRange = text.firstRange(of: " value=") else { return nil }
        let tag = text[..<valueRange.lowerBound]
        let value = text[valueRange.upperBound...].prefix { $0 != " " }
        guard !tag.isEmpty else { return nil }
        return (tag, value)
    }

    /// `Player EntityID=17 PlayerID=6 GameAccountId=[hi=1 lo=2]`.
    private static func playerHeader(_ s: Substring) -> Header? {
        var entityID: Int?, playerID: Int?, hi: UInt64?, lo: UInt64?
        for field in s.split(separator: " ") {
            if field.hasPrefix("EntityID=") { entityID = Int(field.dropFirst(9)) }
            else if field.hasPrefix("PlayerID=") { playerID = Int(field.dropFirst(9)) }
            else if field.hasPrefix("GameAccountId=[hi=") { hi = UInt64(field.dropFirst(18)) }
            else if field.hasPrefix("lo=") { lo = UInt64(field.dropFirst(3).prefix { $0 != "]" }) }
        }
        guard let entityID, let playerID else { return nil }
        return .player(entityID: entityID, playerID: playerID, hi: hi ?? 0, lo: lo ?? 0)
    }

    /// `BuildNumber=…`, `GameType=…`, `FormatType=…`, `ScenarioID=…`, `PlayerID=n, PlayerName=…`.
    static func metadata(_ payload: Substring) -> GameMetadataField? {
        let s = payload.trimmingSpaces()
        if s.hasASCIIPrefix("PlayerID="), let comma = s.firstRange(of: ", PlayerName=") {
            guard let pid = Int(s[s.index(s.startIndex, offsetBy: 9)..<comma.lowerBound]) else { return nil }
            return .playerName(playerID: pid, name: String(s[comma.upperBound...]))
        }
        guard let eq = s.firstIndex(of: "=") else { return nil }
        let key = s[..<eq]
        let value = s[s.index(after: eq)...]
        switch key {
        case "BuildNumber": return Int(value).map(GameMetadataField.buildNumber)
        case "GameType": return .gameType(String(value))
        case "FormatType": return .formatType(String(value))
        case "ScenarioID": return Int(value).map(GameMetadataField.scenarioID)
        default: return .other(key: String(key), value: String(value))
        }
    }
}

extension Substring {
    func trimmingSpaces() -> Substring {
        let bytes = utf8
        var start = bytes.startIndex
        var end = bytes.endIndex
        while start != end, bytes[start] == 0x20 || bytes[start] == 0x09 { start = bytes.index(after: start) }
        while end != start {
            let before = bytes.index(before: end)
            guard bytes[before] == 0x20 || bytes[before] == 0x09 else { break }
            end = before
        }
        return self[start..<end]
    }

    /// First occurrence of an ASCII needle at or after `from`, compared byte-wise.
    func utf8FirstRange(of needle: StaticString, from: Index? = nil) -> Range<Index>? {
        let bytes = utf8
        let pattern = UnsafeBufferPointer(start: needle.utf8Start, count: needle.utf8CodeUnitCount)
        guard let first = pattern.first else { return nil }
        var cursor = from ?? bytes.startIndex
        while let hit = bytes[cursor...].firstIndex(of: first) {
            var a = hit, b = pattern.startIndex
            while b != pattern.endIndex, a != bytes.endIndex, bytes[a] == pattern[b] {
                a = bytes.index(after: a)
                b += 1
            }
            if b == pattern.endIndex { return hit..<a }
            cursor = bytes.index(after: hit)
        }
        return nil
    }

    func firstRange(of needle: StaticString) -> Range<Index>? {
        utf8FirstRange(of: needle)
    }

    /// Last occurrence of an ASCII needle, compared byte-wise.
    func lastRange(of needle: StaticString) -> Range<Index>? {
        let bytes = utf8
        let pattern = UnsafeBufferPointer(start: needle.utf8Start, count: needle.utf8CodeUnitCount)
        guard let first = pattern.first else { return nil }
        var cursor = bytes.endIndex
        while cursor != bytes.startIndex {
            cursor = bytes.index(before: cursor)
            guard bytes[cursor] == first else { continue }
            var a = cursor, b = pattern.startIndex
            while b != pattern.endIndex, a != bytes.endIndex, bytes[a] == pattern[b] {
                a = bytes.index(after: a)
                b += 1
            }
            if b == pattern.endIndex { return cursor..<a }
        }
        return nil
    }

    /// The value after the first occurrence of `key` up to the next space. An empty value
    /// is returned as-is unless `allowEmpty` is false, in which case it is nil.
    func fieldValue(after key: StaticString, allowEmpty: Bool) -> Substring? {
        guard let range = firstRange(of: key) else { return nil }
        let value = self[range.upperBound...].prefix { $0 != " " }
        return value.isEmpty && !allowEmpty ? nil : value
    }

    func hasASCIISuffix(_ suffix: StaticString) -> Bool {
        let pattern = UnsafeBufferPointer(start: suffix.utf8Start, count: suffix.utf8CodeUnitCount)
        return utf8.count >= pattern.count && utf8.suffix(pattern.count).elementsEqual(pattern)
    }

    func hasASCIIPrefix(_ prefix: StaticString) -> Bool {
        let pattern = UnsafeBufferPointer(start: prefix.utf8Start, count: prefix.utf8CodeUnitCount)
        return utf8.starts(with: pattern)
    }
}
