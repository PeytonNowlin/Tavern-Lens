import OverlayLayout
import SwiftUI
import TavernEngine

/// The next-opponent preview's odds section: win / tie / loss of the board as it is now against
/// their last-seen board, a bar, and a footnote (the likelier damage, a lethal warning, the
/// simulations so far). While a changed board is being simulated the previous odds stay,
/// dimmed. "No data" when the opponent hasn't been seen. Sizes from `OddsPreviewMetrics`.
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
                Text("Odds vs last seen")
                    .font(.system(size: m.footnoteFontSize * s, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("No data: not fought yet")
                    .font(.system(size: m.percentFontSize * s, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let failure = odds?.failure {
                Text("Odds unavailable")
                    .font(.system(size: m.percentFontSize * s, weight: .medium))
                    .foregroundStyle(.orange)
                    .help(failure)
            } else {
                let result = odds?.odds
                HStack(spacing: m.columnSpacing * s) {
                    value("W", result?.won, .green)
                    value("T", result?.tied, .secondary)
                    value("L", result?.lost, .red)
                }
                .font(.system(size: m.percentFontSize * s, weight: .semibold))
                PreviewOddsBar(won: result?.won ?? 0, tied: result?.tied ?? 0, lost: result?.lost ?? 0)
                    .frame(height: m.barHeight * s)
                HStack(spacing: m.columnSpacing * s) {
                    footnote
                    Spacer(minLength: 0)
                    Text(progressText).foregroundStyle(.tertiary)
                }
                .font(.system(size: m.footnoteFontSize * s))
            }
        }
        .opacity(odds?.isUpdating == true ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: odds?.isUpdating)
        .help(helpText)
    }

    private func value(_ label: String, _ percent: Double?, _ color: Color) -> some View {
        HStack(spacing: 2 * scale) {
            Text(label).foregroundStyle(.secondary)
            Text(percent.map(CombatOddsPanel.percent) ?? "…").foregroundStyle(color)
        }
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
        guard let odds, odds.hasData else { return "You haven't fought this opponent yet" }
        let seen = odds.opponentSeenTurn.map { "their board from turn \($0)" } ?? "their last-seen board"
        return "Your board now against \(seen)"
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
