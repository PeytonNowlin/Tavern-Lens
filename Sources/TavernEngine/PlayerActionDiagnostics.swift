import Foundation
import BGIntel
import PowerParser

public enum PlayerActionSelection: Codable, Hashable, Sendable {
    case option(SentOption)
    case choices(SentChoices)

    public var timestamp: String {
        switch self { case .option(let sent): sent.timestamp; case .choices(let sent): sent.timestamp }
    }
    public var position: LogPosition? {
        switch self { case .option(let sent): sent.position; case .choices(let sent): sent.position }
    }
}

/// Offered-choice context without EntityRef.playerName or any raw log text.
public struct PlayerActionChoice: Codable, Hashable, Sendable {
    public let id: Int
    public let choiceType: String
    public let taskList: Int?
    public let source: ActionEntity?
    public let options: [ActionEntity]
    public let isComplete: Bool

    public init(_ choice: EntityChoice) {
        id = choice.id; choiceType = choice.choiceType; taskList = choice.taskList
        if case .id(let entityID)? = choice.source {
            source = ActionEntity(entityID: entityID, cardID: choice.sourceCardID ?? "")
        } else { source = nil }
        options = choice.options.prefix(64).map { ActionEntity(entityID: $0.entityID, cardID: $0.cardID) }
        isComplete = choice.options.count <= 64
    }
}

/// Association evidence only. It makes no claim that the player followed the advice.
public struct PlayerActionDisplayedAdvice: Codable, Hashable, Sendable {
    public let displayedAt: Date
    public let fingerprint: String
    public let policyVersion: Int
}

/// A pre-action recruit request paired with a client selection, locally retained by game seed.
/// Game results can be joined from GameRecord later; no opponent account names are copied here.
public struct PlayerActionDiagnostic: Codable, Hashable, Sendable {
    public let format: Int
    public let capturedAt: Date
    /// A dated outgoing timestamp, when the caller can reconstruct it from the session clock.
    /// Receipt time alone cannot prove that advice preceded an action.
    public let actionAt: Date?
    public let gameSeed: Int
    public let bgTurn: Int
    public let position: LogPosition
    public let request: AdvisorRequest
    public let selection: PlayerActionSelection
    public let options: PowerOptions?
    public let choice: PlayerActionChoice?
    public let displayedAdvice: PlayerActionDisplayedAdvice?

    public init(request: AdvisorRequest, selection: PlayerActionSelection, position: LogPosition,
                options: PowerOptions? = nil, choice: EntityChoice? = nil, capturedAt: Date = Date(),
                actionAt: Date? = nil, displayed: AdviceView? = nil, displayedAt: Date? = nil) {
        format = 1; self.capturedAt = capturedAt; self.actionAt = actionAt
        gameSeed = request.preview.gameSeed ?? 0; bgTurn = request.preview.bgTurn
        self.position = selection.position ?? position; self.request = request; self.selection = selection
        switch selection {
        case .option(let sent):
            self.options = sent.optionsID == options?.id ? options : nil
            self.choice = nil
        case .choices(let sent):
            self.options = nil
            self.choice = choice.flatMap { $0.id == sent.id && $0.choiceType == sent.choiceType ? PlayerActionChoice($0) : nil }
        }
        if let displayed, let displayedAt, let actionAt,
           displayedAt.timeIntervalSinceReferenceDate.isFinite,
           actionAt.timeIntervalSinceReferenceDate.isFinite,
           capturedAt.timeIntervalSinceReferenceDate.isFinite,
           displayedAt <= actionAt, actionAt <= capturedAt,
           !displayed.isUpdating, displayed.advice.status != .thinking,
           displayed.fingerprint == AdviceView.fingerprint(of: request, version: displayed.plan.version) {
            displayedAdvice = PlayerActionDisplayedAdvice(displayedAt: displayedAt,
                fingerprint: displayed.fingerprint, policyVersion: displayed.plan.version)
        } else { displayedAdvice = nil }
    }

    /// Stable across repeated reads of the same selection; the timestamp distinguishes reconnect logs.
    public var id: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in selection.timestamp.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return "action-\(gameSeed)_\(bgTurn)_\(position.line)_\(String(hash, radix: 16))"
    }

    fileprivate var isValid: Bool {
        format == 1 && gameSeed != 0 && gameSeed == request.preview.gameSeed
            && bgTurn > 0 && bgTurn == request.preview.bgTurn && position.line > 0
            && capturedAt.timeIntervalSinceReferenceDate.isFinite
            && (actionAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }
}

public enum PlayerActionDiagnosticError: Error, Equatable, Sendable {
    case invalidRecord, recordTooLarge, exportTooLarge
}

/// A single local writer, atomic records, bounded disk and bounded export. No upload or log history.
public actor PlayerActionDiagnosticStore {
    public static let standard = PlayerActionDiagnosticStore(directory: GameRecordStore.standard.directory
        .deletingLastPathComponent().appending(path: "PlayerActions"))
    public let directory: URL
    public let maximumRecords: Int
    public let maximumBytes: Int

    public init(directory: URL, maximumRecords: Int = 1500, maximumBytes: Int = 64 * 1024 * 1024) {
        self.directory = directory; self.maximumRecords = max(1, maximumRecords); self.maximumBytes = max(1, maximumBytes)
    }

    public func save(_ record: PlayerActionDiagnostic) throws {
        guard record.isValid else { throw PlayerActionDiagnosticError.invalidRecord }
        let data = try Self.encoder().encode(record)
        guard data.count <= maximumBytes else { throw PlayerActionDiagnosticError.recordTooLarge }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: record.id + ".json")
        try data.write(to: target, options: .atomic)
        let files = try archiveFiles().sorted { a, b in
            if a.url == b.url { return false }
            if a.url == target { return true }; if b.url == target { return false }
            return a.modified == b.modified ? a.url.lastPathComponent > b.url.lastPathComponent : a.modified > b.modified
        }
        var records = 0, bytes = 0
        for file in files {
            if records >= maximumRecords || file.size > maximumBytes - bytes {
                try manager.removeItem(at: file.url)
            } else { records += 1; bytes += file.size }
        }
    }

    public func load(gameSeed: Int, turn: Int, line: Int) throws -> PlayerActionDiagnostic {
        let prefix = "action-\(gameSeed)_\(turn)_\(line)_"
        guard let file = try archiveFiles().first(where: { $0.url.lastPathComponent.hasPrefix(prefix) }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try read(file)
    }

    /// Valid bounded records in capture order. Unrelated files and unreadable records are excluded.
    public func records(gameSeed: Int? = nil) throws -> [PlayerActionDiagnostic] {
        var result: [PlayerActionDiagnostic] = [], bytes = 0
        for file in try archiveFiles() {
            if let gameSeed, !file.url.lastPathComponent.hasPrefix("action-\(gameSeed)_") { continue }
            guard result.count < maximumRecords, file.size <= maximumBytes - bytes else { continue }
            if let record = try? read(file) { result.append(record); bytes += file.size }
        }
        return result.sorted { a, b in
            a.capturedAt == b.capturedAt ? a.position.line < b.position.line : a.capturedAt < b.capturedAt
        }
    }

    /// Offline JSONL only. The caller chooses whether and where to write this data.
    public func export(gameSeed: Int? = nil) throws -> Data {
        let encoder = Self.encoder()
        var data = Data()
        for record in try records(gameSeed: gameSeed) {
            let row = try encoder.encode(record)
            guard row.count < maximumBytes - data.count else { throw PlayerActionDiagnosticError.exportTooLarge }
            data.append(row); data.append(0x0A)
        }
        return data
    }

    private struct ArchiveFile { let url: URL; let size: Int; let modified: Date }

    private func archiveFiles() throws -> [ArchiveFile] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)).compactMap { url in
            guard Self.isArchiveName(url.lastPathComponent) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { return nil }
            return ArchiveFile(url: url, size: size, modified: values.contentModificationDate ?? .distantPast)
        }.sorted { a, b in
            a.modified == b.modified ? a.url.lastPathComponent > b.url.lastPathComponent : a.modified > b.modified
        }
    }

    private func read(_ file: ArchiveFile) throws -> PlayerActionDiagnostic {
        guard file.size <= maximumBytes else { throw PlayerActionDiagnosticError.recordTooLarge }
        let record = try JSONDecoder().decode(PlayerActionDiagnostic.self, from: Data(contentsOf: file.url))
        guard record.isValid, file.url.lastPathComponent == record.id + ".json" else {
            throw PlayerActionDiagnosticError.invalidRecord
        }
        return record
    }

    private static func isArchiveName(_ name: String) -> Bool {
        guard name.hasPrefix("action-"), name.hasSuffix(".json") else { return false }
        let parts = name.dropFirst(7).dropLast(5).split(separator: "_", omittingEmptySubsequences: false)
        return parts.count == 4 && Int(parts[0]) != nil && Int(parts[1]) != nil && Int(parts[2]) != nil
            && (1...16).contains(parts[3].count) && parts[3].utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }
}
