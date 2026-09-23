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

    private enum Header: Sendable {
        case gameEntity(id: Int)
        case player(entityID: Int, playerID: Int, hi: UInt64, lo: UInt64)
        case full(EntityRef, cardID: String)
        case show(EntityRef, cardID: String)
        case change(EntityRef, cardID: String)
    }

    private var header: Header?
    private var headerTags: [TagAssignment] = []

    public init() {}

    /// Parses a raw line. Returns the parsed line (for its timestamp) or nil if unparsable.
    @discardableResult
    public mutating func feed(_ text: String, emit: (PowerEvent) -> Void) -> LogLine? {
        guard let line = LogLine(text) else {
            diagnostics.unparsableLines += 1
            return nil
        }
        feed(line, emit: emit)
        return line
    }

    public mutating func feed(_ line: LogLine, emit: (PowerEvent) -> Void) {
        switch line.method {
        case "PowerTaskList.DebugPrintPower":
            feedPower(line.payload, emit: emit)
        case "GameState.DebugPrintGame":
            if let field = Self.metadata(line.payload) { emit(.gameMetadata(field)) }
        case "PowerProcessor.EndCurrentTaskList":
            flushHeader(emit: emit)
            emit(.taskListEnd)
        case "GameState.DebugPrintPower":
            if line.payload.trimmingSpaces() == "CREATE_GAME" { emit(.newGameAnnounced) }
        default:
            break
        }
    }

    /// Call at end of input so a trailing header is not lost.
    public mutating func finish(emit: (PowerEvent) -> Void) {
        flushHeader(emit: emit)
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

        if s.hasASCIIPrefix("TAG_CHANGE Entity=") {
            var body = s.dropFirst("TAG_CHANGE Entity=".count)
            if body.hasASCIISuffix(" DEF CHANGE") { body = body.dropLast(" DEF CHANGE".count).trimmingSpaces() }
            guard let (ref, tag, value) = refTagValue(body) else { return malformed() }
            emit(.tagChange(ref, TagAssignment(tag: GameTag(token: tag), value: TagValue(token: value))))
        } else if s.hasASCIIPrefix("FULL_ENTITY - Updating ") {
            guard let (ref, card) = refAndCard(s.dropFirst("FULL_ENTITY - Updating ".count)) else { return malformed() }
            open(.full(ref, cardID: card))
        } else if s.hasASCIIPrefix("FULL_ENTITY - Creating ID=") {
            let body = s.dropFirst("FULL_ENTITY - Creating ID=".count)
            guard let split = body.firstRange(of: " CardID="), let id = Int(body[..<split.lowerBound]) else {
                return malformed()
            }
            open(.full(.id(id), cardID: String(body[split.upperBound...])))
        } else if s.hasASCIIPrefix("SHOW_ENTITY - Updating Entity=") {
            guard let (ref, card) = refAndCard(s.dropFirst("SHOW_ENTITY - Updating Entity=".count)) else {
                return malformed()
            }
            open(.show(ref, cardID: card))
        } else if s.hasASCIIPrefix("CHANGE_ENTITY - Updating Entity=") {
            guard let (ref, card) = refAndCard(s.dropFirst("CHANGE_ENTITY - Updating Entity=".count)) else {
                return malformed()
            }
            open(.change(ref, cardID: card))
        } else if s.hasASCIIPrefix("HIDE_ENTITY - Entity=") {
            guard let (ref, _, _) = refTagValue(s.dropFirst("HIDE_ENTITY - Entity=".count)) else { return malformed() }
            emit(.hideEntity(ref))
        } else if s.hasASCIIPrefix("BLOCK_START BlockType=") {
            let body = s.dropFirst("BLOCK_START BlockType=".count)
            let type = body.prefix { $0 != " " }
            var ref: EntityRef?
            if let entityStart = body.firstRange(of: " Entity=") {
                let rest = body[entityStart.upperBound...]
                let refText = rest.firstRange(of: " EffectCardId=").map { rest[..<$0.lowerBound] } ?? rest
                ref = entityRef(refText)
            }
            emit(.blockStart(type: String(type), entity: ref))
        } else if s == "BLOCK_END" {
            emit(.blockEnd)
        } else if s == "CREATE_GAME" {
            emit(.createGame)
        } else if s.hasASCIIPrefix("GameEntity EntityID=") {
            guard let id = Int(s.dropFirst("GameEntity EntityID=".count)) else { return malformed() }
            open(.gameEntity(id: id))
        } else if s.hasASCIIPrefix("Player EntityID=") {
            guard let player = Self.playerHeader(s) else { return malformed() }
            open(player)
        }
        // Everything else (META_DATA, SUB_SPELL_*, Info[n], Source, Targets, …) is ignored for now.
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

    func hasASCIISuffix(_ suffix: StaticString) -> Bool {
        let pattern = UnsafeBufferPointer(start: suffix.utf8Start, count: suffix.utf8CodeUnitCount)
        return utf8.count >= pattern.count && utf8.suffix(pattern.count).elementsEqual(pattern)
    }

    func hasASCIIPrefix(_ prefix: StaticString) -> Bool {
        let pattern = UnsafeBufferPointer(start: prefix.utf8Start, count: prefix.utf8CodeUnitCount)
        return utf8.starts(with: pattern)
    }
}
