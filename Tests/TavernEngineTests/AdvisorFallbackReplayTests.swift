import Foundation
import Testing
import TavernEngine

@Suite("Captured no-option advisor follow-up")
struct AdvisorFallbackReplayTests {
    static let directory = ProcessInfo.processInfo.environment["TAVERN_FALLBACK_AUDIT_DIAGNOSTICS"]

    @Test("Captured empty advice gains explicit contextual guidance without inventing combat odds",
          .enabled(if: directory != nil, "set TAVERN_FALLBACK_AUDIT_DIAGNOSTICS for local game evidence"))
    func capturedEmptyAdvice() async throws {
        let cases = AdvisorCase.savedDiagnostics(in: URL(filePath: Self.directory!))
        let samples = [10, 12, 13].compactMap { turn in
            cases.first {
                $0.name.hasPrefix("game-859420031-turn-\(turn)-decision-")
                    && $0.request.recruit?.pendingChoice != true && $0.request.gold >= 3
                    && $0.recorded?.evaluations == 0 && $0.recorded?.advice.suggestions.isEmpty == true
            }
        }
        #expect(!samples.isEmpty)
        var savedPreview = false
        for sample in samples {
            let archived = try #require(sample.recorded)
            let replay = try await archived.replaying(sample.request, simulate: { _, _, _ in
                throw CocoaError(.featureUnsupported)
            })
            #expect(replay.advice == archived.advice)
            let current = try await AdvisorEvaluation.run(sample.request, plan: .live, limit: 0,
                simulate: { _, _, _ in throw CocoaError(.featureUnsupported) })
            #expect(!current.advice.suggestions.isEmpty)
            #expect(current.advice.suggestions.allSatisfy { $0.confidence == .low && $0.odds == nil })
            if sample.request.recruit!.input.playerBoard.player.hpLeft <= 15 {
                #expect(current.advice.suggestions.allSatisfy {
                    $0.continuation?.contains(where: { $0.hasPrefix("Level to") }) != true
                })
            }
            let view = AdviceView(request: sample.request, plan: .live, advice: current.advice,
                                  evaluations: 0, isComplete: current.isComplete)
            let presentation = AdvisorPresentation(advice: view, request: sample.request)
            #expect(presentation.state == .estimated && presentation.primary != nil)
            print("FALLBACK AUDIT \(sample.name): \(presentation.title); \(presentation.reason)")
            if !savedPreview, let path = ProcessInfo.processInfo.environment["TAVERN_FALLBACK_PREVIEW"] {
                struct Preview: Encodable { let request: AdvisorRequest; let displayed: AdviceView }
                try JSONEncoder().encode(Preview(request: sample.request, displayed: view))
                    .write(to: URL(filePath: path))
                savedPreview = true
            }
        }
    }
}
