import Foundation
import BGIntel

/// One turn's actual displayed advice and combat result, separate from manual bookmarks. The
/// request is the one the displayed advice evaluated, even if it had become stale before combat.
public struct AdvisorTurnDiagnostic: Codable, Hashable, Sendable {
    public var format = 2
    public var capturedAt: Date
    public var gameSeed: Int
    public var bgTurn: Int
    public var request: AdvisorRequest?
    public var displayed: AdviceView?
    public var combat: CombatSimulationRequest
    public var odds: CombatOddsView?
    public var preview: OddsPreviewView?
    public var failure: String?
    public var decisions: [AdvisorDecision]?

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

public struct AdvisorDecision: Codable, Hashable, Sendable {
    public var request: AdvisorRequest
    public var displayed: AdviceView
    /// Publication time of this advice; absent in older diagnostic files.
    public var displayedAt: Date?
    public var coverage: AdvisorCoverageDiagnostic?
    public init(request: AdvisorRequest, displayed: AdviceView, displayedAt: Date? = nil) {
        self.request = request; self.displayed = displayed
        self.displayedAt = displayedAt
    }
}

/// Keeps the opening decision and the latest distinct decisions, never another turn's state.
public struct AdvisorDecisionTrace: Sendable {
    public private(set) var decisions: [AdvisorDecision] = []
    public let limit: Int
    public init(limit: Int = 12) { self.limit = max(2, limit) }

    public mutating func record(request: AdvisorRequest, displayed: AdviceView, displayedAt: Date = Date()) {
        guard displayed.advice.status != .thinking else { return }
        // The latest stored pair has already been validated. Refining its advice does not
        // require another JSON encoding; a changed request, policy or fingerprint does.
        let previous = decisions.last
        let alreadyValidated = previous?.request == request
            && previous?.displayed.plan.version == displayed.plan.version
            && previous?.displayed.fingerprint == displayed.fingerprint
        guard alreadyValidated
            || displayed.fingerprint == AdviceView.fingerprint(of: request, version: displayed.plan.version) else { return }
        if let first = decisions.first,
           first.request.preview.gameSeed != request.preview.gameSeed || first.request.preview.bgTurn != request.preview.bgTurn {
            decisions = []
        }
        var decision = AdvisorDecision(request: request, displayed: displayed, displayedAt: displayedAt)
        if displayed.plan.version >= 11 {
            decision.coverage = alreadyValidated ? previous?.coverage
                : AdvisorCoverageDiagnostic(request: request, policyVersion: displayed.plan.version)
        }
        if decisions.last?.displayed.fingerprint == displayed.fingerprint { decisions[decisions.count - 1] = decision }
        else { decisions.append(decision) }
        if decisions.count > limit { decisions.remove(at: 1) }
    }
}
