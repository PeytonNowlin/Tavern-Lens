import BGIntel
import Foundation

/// A recruit-phase state and the advice once shown for it: one case the weight tuning replays.
///
/// Cases come from feedback bookmarks (the app's saved ones, or the committed golden cases),
/// which keep the state the advice was for (`FeedbackBookmark.adviceRequest`), and from the
/// advisor's committed golden states. None needs its log.
public struct AdvisorCase: Codable, Hashable, Sendable {
    public var name: String
    public var note: String
    public var request: AdvisorRequest
    /// The advice as it was shown (with the plan and how far scoring had got); nil when there's
    /// none, and the case is scored with the tuning's fallback plan.
    public var recorded: AdviceView?

    public init(name: String, note: String = "", request: AdvisorRequest, recorded: AdviceView? = nil) {
        self.name = name
        self.note = note
        self.request = request
        self.recorded = recorded
    }

    /// A bookmark's case, when it kept the advice and the state it was for.
    public init?(bookmark: FeedbackBookmark, name: String? = nil) {
        guard let request = bookmark.adviceRequest, let advice = bookmark.advice,
              AdviceView.fingerprint(of: request, version: advice.plan.version) == advice.fingerprint
        else { return nil }
        self.init(name: name ?? BookmarkExport.defaultName(for: bookmark), note: bookmark.note, request: request, recorded: advice)
    }

    /// A committed golden bookmark case's, when it has advice and the state it was for.
    public init?(goldenCase: BookmarkGoldenCase) {
        guard let request = goldenCase.adviceRequest, let advice = goldenCase.expectedAdvice,
              AdviceView.fingerprint(of: request, version: advice.plan.version) == advice.fingerprint
        else { return nil }
        self.init(name: goldenCase.name, note: goldenCase.note, request: request, recorded: advice)
    }

    /// The cases among the golden bookmark cases in `directory` (`*.json`); others are skipped.
    public static func goldenCases(in directory: URL) -> [AdvisorCase] {
        jsonFiles(in: directory).compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? BookmarkGoldenCase.decode($0) }.flatMap(AdvisorCase.init(goldenCase:))
        }
    }

    /// The cases among every bookmark saved in the record store at `directory` (the app's
    /// `Application Support/TavernLens/Games`).
    public static func savedBookmarks(in directory: URL) -> [AdvisorCase] {
        GameRecordStore(directory: directory).allBookmarks().compactMap { AdvisorCase(bookmark: $0.bookmark) }
    }

    /// Automatic turn evidence can be replayed through the same interface as manual bookmarks.
    public static func savedDiagnostics(in directory: URL) -> [AdvisorCase] {
        jsonFiles(in: directory).compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(AdvisorTurnDiagnostic.self, from: data),
                  let request = record.request, let displayed = record.displayed,
                  AdviceView.fingerprint(of: request, version: displayed.plan.version) == displayed.fingerprint else { return nil }
            return AdvisorCase(name: "game-\(record.gameSeed)-turn-\(record.bgTurn)",
                               note: "Automatically captured displayed advice", request: request, recorded: displayed)
        }
    }

    /// The case files (`AdvisorCase` JSON) in `directory`.
    public static func caseFiles(in directory: URL) -> [AdvisorCase] {
        jsonFiles(in: directory).compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AdvisorCase.self, from: $0) }
        }
    }

    static func jsonFiles(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Replays bookmarked cases under other weights and reports how the advice changes: the tool for
/// tuning `AdvisorWeights` from playtest feedback (`scripts/advisor-tune.sh`).
///
/// Each case is re-scored with its recorded plan (seed, simulations, passes) and exactly as far as
/// it was scored when shown, but with the new weights, so the only difference is the weights
/// (the candidates refined and scored against the lobby can change with them, as they would live).
public enum AdvisorTuning {
    /// One case's advice before and after.
    public struct Row: Codable, Hashable, Sendable {
        public var name: String
        public var note: String
        public var before: Advice
        public var after: Advice
        /// Sanity rules the new advice breaks (should be none).
        public var violations: [AdvisorSanityNote]

        /// The top suggestion or the status changed.
        public var topChanged: Bool {
            before.status != after.status || before.suggestions.first?.action != after.suggestions.first?.action
        }

        /// Anything shown changed: the suggestions (in order), the status or the note.
        public var changed: Bool {
            before.status != after.status || before.note != after.note
                || before.suggestions.map(\.action) != after.suggestions.map(\.action)
        }
    }

    public struct Report: Codable, Hashable, Sendable {
        public var weights: AdvisorWeights
        public var rows: [Row]

        public var changed: [Row] { rows.filter(\.changed) }
        public var topChanged: [Row] { rows.filter(\.topChanged) }

        /// A readable report: a summary line, then each case (changed ones in full).
        public var text: String {
            var lines = ["\(rows.count) cases: \(topChanged.count) with a new top suggestion or status, \(changed.count) changed at all"]
            let violated = rows.filter { !$0.violations.isEmpty }
            if !violated.isEmpty { lines.append("\(violated.count) break a sanity rule") }
            for row in rows {
                lines.append("")
                lines.append("\(row.changed ? "CHANGED" : "same   ") \(row.name)\(row.note.isEmpty ? "" : " — \(row.note)")")
                guard row.changed || !row.violations.isEmpty else { continue }
                lines.append("  before: \(Self.describe(row.before))")
                lines.append("  after:  \(Self.describe(row.after))")
                for note in row.violations { lines.append("  breaks \(note.rule.rawValue) (\(note.candidate))") }
            }
            return lines.joined(separator: "\n")
        }

        static func describe(_ advice: Advice) -> String {
            let head = advice.status.rawValue + (advice.note.map { " (\($0))" } ?? "")
            let list = advice.suggestions.map { s in
                "\(s.rank). \(s.action.id) \(String(format: "%+.1f", s.gain)) [\(s.confidence.rawValue)]"
            }
            return ([head] + list).joined(separator: "; ")
        }
    }

    /// Re-scores every case under `weights` (each with its recorded plan, or `fallbackPlan` when it
    /// has none) and compares with the advice recorded (or, without one, the advice under the plan's
    /// own weights).
    public static func replay(
        _ cases: [AdvisorCase], weights: AdvisorWeights, fallbackPlan: AdvisorPlan = .live,
        simulate: AdvisorEvaluation.Simulate
    ) async throws -> Report {
        var rows: [Row] = []
        for item in cases {
            let plan = item.recorded?.plan ?? fallbackPlan
            let limit = item.recorded.flatMap { $0.isComplete ? nil : $0.evaluations }
            let before: Advice
            if let recorded = item.recorded {
                before = recorded.advice
            } else {
                before = try await AdvisorEvaluation.run(item.request, plan: plan, limit: limit, simulate: simulate).advice
            }
            let after = try await AdvisorEvaluation.run(
                item.request, plan: plan.with(weights: weights), limit: limit, simulate: simulate
            ).advice
            rows.append(Row(
                name: item.name, note: item.note, before: before, after: after,
                violations: AdvisorSanity.violations(after, request: item.request, weights: weights)
            ))
        }
        return Report(weights: weights, rows: rows)
    }
}
