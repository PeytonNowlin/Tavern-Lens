import Foundation
import BGIntel

/// One turn's actual displayed advice and combat result, separate from manual bookmarks. The
/// request is the one the displayed advice evaluated, even if it had become stale before combat.
public struct AdvisorTurnDiagnostic: Codable, Hashable, Sendable {
    public var format = 1
    public var capturedAt: Date
    public var gameSeed: Int
    public var bgTurn: Int
    public var request: AdvisorRequest?
    public var displayed: AdviceView?
    public var combat: CombatSimulationRequest
    public var odds: CombatOddsView?
    public var preview: OddsPreviewView?
    public var failure: String?

    public init(combat: CombatSimulationRequest, request: AdvisorRequest?, displayed: AdviceView?,
                capturedAt: Date = Date()) {
        self.capturedAt = capturedAt
        gameSeed = combat.gameSeed ?? 0; bgTurn = combat.bgTurn; self.combat = combat
        let matches = request?.preview.gameSeed == combat.gameSeed && request?.preview.bgTurn == combat.bgTurn
            && request.map { AdviceView.fingerprint(of: $0, version: displayed?.plan.version ?? 2) == displayed?.fingerprint } == true
        self.request = matches ? request : nil
        self.displayed = matches ? displayed : nil
    }
}

/// Single writer, atomic files, bounded retention. Independent of GameRecord writes, so an engine
/// checkpoint cannot overwrite asynchronously captured UI evidence.
public actor AdvisorDiagnosticStore {
    public static let standard = AdvisorDiagnosticStore(directory: GameRecordStore.standard.directory
        .deletingLastPathComponent().appending(path: "AdvisorDiagnostics"))
    public let directory: URL
    public let maximumRecords: Int
    public let maximumBytes: Int

    public init(directory: URL, maximumRecords: Int = 300, maximumBytes: Int = 64 * 1024 * 1024) {
        self.directory = directory; self.maximumRecords = max(1, maximumRecords); self.maximumBytes = max(1, maximumBytes)
    }

    public func save(_ record: AdvisorTurnDiagnostic) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= maximumBytes else { throw DiagnosticError.recordTooLarge }
        let target = directory.appending(path: "game-\(record.gameSeed)-turn-\(record.bgTurn).json")
        try data.write(to: target, options: .atomic)
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            .filter { $0.lastPathComponent.hasPrefix("game-") && $0.pathExtension == "json" }
            .map { url in (url, try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])) }
            .sorted { a, b in
                if a.0 == target { return true }; if b.0 == target { return false }
                return (a.1.contentModificationDate ?? .distantPast) > (b.1.contentModificationDate ?? .distantPast)
            }
        var bytes = 0
        for (index, file) in files.enumerated() {
            bytes += file.1.fileSize ?? 0
            if index >= maximumRecords || bytes > maximumBytes { try manager.removeItem(at: file.0) }
        }
    }

    public func load(gameSeed: Int, turn: Int) throws -> AdvisorTurnDiagnostic {
        try JSONDecoder().decode(AdvisorTurnDiagnostic.self,
            from: Data(contentsOf: directory.appending(path: "game-\(gameSeed)-turn-\(turn).json")))
    }

    enum DiagnosticError: Error { case recordTooLarge }
}
