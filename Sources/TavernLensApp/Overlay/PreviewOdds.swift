import OverlayLayout
import SwiftUI
import TavernEngine

/// The next-opponent preview's odds section: win / tie / loss of the board as it is now against
/// their last-seen board, a bar, and a footnote with the likelier damage or lethal warning.
/// A changed board replaces the previous odds with an explicit updating state. Unseen and
/// stale boards explain why no odds are shown. Sizes from `OddsPreviewMetrics`.
struct PreviewOdds: View {
    let odds: OddsPreviewView?
    /// Whether the opponent's board has been seen (the preview knows before the first request).
    let seen: Bool
    let scale: CGFloat
    var metrics = OddsPreviewMetrics()

    var body: some View {
        let m = metrics
        let s = scale
        VStack(alignment: .leading, spacing: m.rowSpacing * s) {
            switch OverlayText.previewState(previewInput, staleBoardTurns: AdvisorRequest.staleBoardTurns) {
            case .status(let title, let detail, let isWarning, let help):
                if let help {
                    status(title, detail: detail, warning: isWarning).help(help)
                } else {
                    status(title, detail: detail, warning: isWarning)
                }
            case .odds:
                let result = odds?.odds
                HStack(spacing: m.columnSpacing * s) {
                    value("W", result?.won, .green)
                    value("T", result?.tied, .secondary)
                    value("L", result?.lost, .red)
                }
                OddsBar(won: result?.won ?? 0, tied: result?.tied ?? 0, lost: result?.lost ?? 0)
                    .frame(height: m.barHeight * s)
                footnote
                    .font(.system(size: m.footnoteSize(at: s)))
                    .frame(height: m.lineHeight(at: s), alignment: .leading)
            }
        }
        .lineLimit(1)
        .monospacedDigit()
        .help(helpText)
    }

    private func status(_ title: String, detail: String, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing * scale) {
            Text(title)
                .font(.system(size: metrics.percentSize(at: scale), weight: .semibold))
                .foregroundStyle(warning ? Color.orange : Color.primary)
                .frame(height: metrics.lineHeight(at: scale), alignment: .leading)
            Text(detail)
                .font(.system(size: metrics.footnoteSize(at: scale)))
                .foregroundStyle(.secondary)
                .frame(height: metrics.lineHeight(at: scale), alignment: .leading)
        }
    }

    private func value(_ label: String, _ percent: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).foregroundStyle(.secondary)
                .frame(height: metrics.lineHeight(at: scale))
            Text(percent.map(OverlayText.percent) ?? "…").foregroundStyle(color)
                .frame(height: metrics.lineHeight(at: scale))
        }
        .font(.system(size: metrics.percentSize(at: scale), weight: .semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewInput: OverlayText.PreviewInput {
        OverlayText.PreviewInput(seen: seen, request: odds.map {
            .init(hasData: $0.hasData, bgTurn: $0.bgTurn, opponentSeenTurn: $0.opponentSeenTurn,
                  failure: $0.failure, isUpdating: $0.isUpdating, hasResult: $0.odds != nil)
        })
    }

    @ViewBuilder private var footnote: some View {
        if let result = odds?.odds {
            switch OverlayText.previewFootnote(
                won: result.won, lost: result.lost, averageDamageWon: result.averageDamageWon,
                averageDamageLost: result.averageDamageLost, lethalRisk: odds?.lethalRisk) {
            case .lethal(let text): Text(text).foregroundStyle(.red).fontWeight(.semibold)
            case .take(let text), .deal(let text): Text(text).foregroundStyle(.secondary)
            case nil: EmptyView()
            }
        }
    }

    private var progressText: String {
        OverlayText.progress(simulations: odds?.odds?.simulations, isFinal: odds?.odds?.isFinal == true,
                             isUpdating: odds?.isUpdating == true)
    }

    private var helpText: String {
        guard seen, odds?.hasData != false else { return "You haven't fought this opponent yet" }
        guard let odds else { return "Calculating your current board against their last-seen board" }
        let seen = odds.opponentSeenTurn.map { "their board from turn \($0)" } ?? "their last-seen board"
        if odds.isUpdating { return "Your board changed. Calculating new odds against \(seen)" }
        return "Your board now against \(seen). \(progressText) simulations"
    }
}
