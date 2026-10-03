import OverlayLayout
import SwiftUI
import TavernEngine

/// Win / tie / loss, the damage dealt and taken with their ranges, and a lethal warning, for
/// the combat on screen. Shown from the combat's start ("…" until the first result, within
/// tens of milliseconds) and refined in place. Its sizes come from `CombatOddsMetrics`, which
/// the layout tests check against the panel's rect. Click-through.
struct CombatOddsPanel: View {
    let odds: CombatOddsView
    let scale: CGFloat
    var metrics = CombatOddsMetrics()

    var body: some View {
        let m = metrics
        let s = scale
        VStack(alignment: .leading, spacing: m.rowSpacing * s) {
            HStack(spacing: m.columnSpacing * s) {
                column("Win", odds.odds?.won, .green)
                column("Tie", odds.odds?.tied, .secondary)
                column("Loss", odds.odds?.lost, .red)
            }
            OddsBar(won: odds.odds?.won ?? 0, tied: odds.odds?.tied ?? 0, lost: odds.odds?.lost ?? 0)
                .frame(height: m.barHeight * s)
            Group {
                Text("Deal \(damage(odds.odds?.averageDamageWon, odds.odds?.damageWonRange, any: (odds.odds?.won ?? 0) > 0))")
                Text("Take \(damage(odds.odds?.averageDamageLost, odds.odds?.damageLostRange, any: (odds.odds?.lost ?? 0) > 0))")
            }
            .font(.system(size: m.damageFontSize * s, weight: .medium))
            HStack(spacing: m.columnSpacing * s) {
                warning
                Spacer(minLength: 0)
                Text(progressText)
                    .font(.system(size: m.footnoteFontSize * s))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, m.padding.width * s)
        .padding(.vertical, m.padding.height * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hudPanel(cornerRadius: m.cornerRadius * s,
                  border: odds.lethalRisk != nil ? .red.opacity(0.7) : nil,
                  borderWidth: odds.lethalRisk != nil ? 1 : nil)
        .help(odds.failure.map { "Combat odds unavailable: \($0)" } ?? "Combat odds from \(odds.odds?.simulations ?? 0) simulations")
    }

    private func column(_ label: String, _ percent: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: metrics.labelFontSize * scale, weight: .medium))
                .foregroundStyle(.secondary)
            Text(percent.map(OverlayText.percent) ?? "…")
                .font(.system(size: metrics.percentFontSize * scale, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var warning: some View {
        let size = metrics.warningFontSize * scale
        switch OverlayText.combatWarning(failed: odds.failure != nil, lethalRisk: odds.lethalRisk,
                                         lethalChance: odds.lethalChance) {
        case .unavailable:
            Text("Unavailable").font(.system(size: size, weight: .semibold)).foregroundStyle(.orange)
        case .lethalRisk(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.red)
                .help("Chance this combat eliminates you")
        case .lethalChance(let text):
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.green)
                .help("Chance this combat eliminates the opponent")
        case nil:
            EmptyView()
        }
    }

    private var progressText: String {
        OverlayText.progress(simulations: odds.odds?.simulations, isFinal: odds.odds?.isFinal == true,
                             failed: odds.failure != nil)
    }

    /// "8.8 (7–13)", or "–" when no simulation ended that way.
    private func damage(_ average: Double?, _ range: CombatOdds.DamageRange?, any: Bool) -> String {
        OverlayText.damage(average: average, range: range.map { $0.min...$0.max }, any: any)
    }
}
