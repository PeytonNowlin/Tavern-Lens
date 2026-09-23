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
        .background(HUDMaterial(cornerRadius: m.cornerRadius * s))
        .overlay(
            RoundedRectangle(cornerRadius: m.cornerRadius * s, style: .continuous)
                .strokeBorder(odds.lethalRisk != nil ? .red.opacity(0.7) : .white.opacity(0.12), lineWidth: odds.lethalRisk != nil ? 1 : 0.5)
        )
        .help(odds.failure.map { "Combat odds unavailable: \($0)" } ?? "Combat odds from \(odds.odds?.simulations ?? 0) simulations")
    }

    private func column(_ label: String, _ percent: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: metrics.labelFontSize * scale, weight: .medium))
                .foregroundStyle(.secondary)
            Text(percent.map(Self.percent) ?? "…")
                .font(.system(size: metrics.percentFontSize * scale, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var warning: some View {
        let size = metrics.warningFontSize * scale
        if odds.failure != nil {
            Text("Unavailable").font(.system(size: size, weight: .semibold)).foregroundStyle(.orange)
        } else if let risk = odds.lethalRisk {
            Label("Lethal \(Self.percent(risk))", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.red)
                .help("Chance this combat eliminates you")
        } else if let chance = odds.lethalChance {
            Text("Lethal \(Self.percent(chance))")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.green)
                .help("Chance this combat eliminates the opponent")
        }
    }

    private var progressText: String {
        guard let result = odds.odds else { return odds.failure == nil ? "…" : "" }
        let count = result.simulations >= 1000
            ? String(format: "%.1fk", Double(result.simulations) / 1000) : String(result.simulations)
        return result.isFinal ? count : "\(count)…"
    }

    /// "74%", "<1%" for a small non-zero chance, ">99%" for a near-certain one.
    static func percent(_ value: Double) -> String {
        if value > 0, value < 1 { return "<1%" }
        if value < 100, value > 99 { return ">99%" }
        return "\(Int(value.rounded()))%"
    }

    /// "8.8 (7–13)", or "–" when no simulation ended that way.
    private func damage(_ average: Double?, _ range: CombatOdds.DamageRange?, any: Bool) -> String {
        guard any, let average else { return "–" }
        let mean = String(format: "%.1f", average)
        guard let range else { return mean }
        return range.min == range.max ? "\(mean) (\(range.min))" : "\(mean) (\(range.min)–\(range.max))"
    }
}

/// The win, tie and loss shares as one bar.
private struct OddsBar: View {
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
