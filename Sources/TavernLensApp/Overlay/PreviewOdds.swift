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
            if !seen || odds?.hasData == false {
                status("No odds", detail: "Not fought yet")
            } else if let odds, let seenTurn = odds.opponentSeenTurn,
                      odds.bgTurn - seenTurn >= AdvisorRequest.staleBoardTurns {
                status("Board too old", detail: "No odds shown", warning: true)
            } else if let failure = odds?.failure {
                status("Odds unavailable", detail: "Calculation failed", warning: true)
                    .help(failure)
            } else if odds?.isUpdating == true || odds?.odds == nil {
                status("Updating…", detail: odds?.isUpdating == true ? "Board changed" : "Calculating…")
            } else {
                let result = odds?.odds
                HStack(spacing: m.columnSpacing * s) {
                    value("W", result?.won, .green)
                    value("T", result?.tied, .secondary)
                    value("L", result?.lost, .red)
                }
                PreviewOddsBar(won: result?.won ?? 0, tied: result?.tied ?? 0, lost: result?.lost ?? 0)
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
            Text(percent.map(CombatOddsPanel.percent) ?? "…").foregroundStyle(color)
                .frame(height: metrics.lineHeight(at: scale))
        }
        .font(.system(size: metrics.percentSize(at: scale), weight: .semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var footnote: some View {
        if let result = odds?.odds {
            if let risk = odds?.lethalRisk {
                Text("Lethal \(CombatOddsPanel.percent(risk))").foregroundStyle(.red).fontWeight(.semibold)
            } else if result.lost >= result.won, result.lost > 0 {
                Text("Take \(String(format: "%.1f", result.averageDamageLost))").foregroundStyle(.secondary)
            } else if result.won > 0 {
                Text("Deal \(String(format: "%.1f", result.averageDamageWon))").foregroundStyle(.secondary)
            }
        }
    }

    private var progressText: String {
        guard let result = odds?.odds else { return "…" }
        let count = result.simulations >= 1000
            ? String(format: "%.1fk", Double(result.simulations) / 1000) : String(result.simulations)
        return result.isFinal && odds?.isUpdating != true ? count : "\(count)…"
    }

    private var helpText: String {
        guard seen, odds?.hasData != false else { return "You haven't fought this opponent yet" }
        guard let odds else { return "Calculating your current board against their last-seen board" }
        let seen = odds.opponentSeenTurn.map { "their board from turn \($0)" } ?? "their last-seen board"
        if odds.isUpdating { return "Your board changed. Calculating new odds against \(seen)" }
        return "Your board now against \(seen). \(progressText) simulations"
    }
}

private struct PreviewOddsBar: View {
    var won: Double
    var tied: Double
    var lost: Double

    var body: some View {
        GeometryReader { geometry in
            let total = max(won + tied + lost, 1)
            HStack(spacing: 0) {
                Rectangle().fill(.green.opacity(0.85)).frame(width: geometry.size.width * won / total)
                Rectangle().fill(.gray.opacity(0.6)).frame(width: geometry.size.width * tied / total)
                Rectangle().fill(.red.opacity(0.85)).frame(width: geometry.size.width * lost / total)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
        }
    }
}
