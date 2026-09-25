import Observation
import OverlayLayout
import SwiftUI
import TavernEngine

/// What the overlay draws. Owned by `OverlayController`, which keeps it in step with
/// Hearthstone's window and the live view state.
@MainActor
@Observable
final class OverlayModel {
    var layout: OverlayLayout?
    var view: ViewState = .noGame
    var showsLayoutGuides = false
    /// Set when this game's alignment check failed (the hero-pick banner wasn't where expected).
    var alignmentWarning: String?
    /// The latest combat's odds, from `CombatOddsModel`.
    var combatOdds: CombatOddsView?
    /// The recruit-phase odds preview, from `CombatOddsModel`.
    var oddsPreview: OddsPreviewView?
    /// The advisor's suggestions, from `CombatOddsModel`.
    var advice: AdviceView?
    /// The player collapsed the advisor's list to its header. Remembered across launches.
    var advisorCollapsed = false
    @ObservationIgnored var hide: () -> Void = {}
    @ObservationIgnored var toggleAdvisor: () -> Void = {}

    /// The advisor shows during the recruit phase it was scored for.
    var shownAdvice: AdviceView? {
        guard view.status == .inGame, let game = view.game, let advice, advice.isFor(game) else { return nil }
        return advice
    }

    /// The preview's odds show in the next opponent preview during the recruit phase they're for.
    var shownOddsPreview: OddsPreviewView? {
        guard view.status == .inGame, let game = view.game, let preview = oddsPreview, preview.isFor(game)
        else { return nil }
        return preview
    }

    /// The status HUD shows during a solo Battlegrounds game and on its game-over screen.
    var game: GameView? {
        switch view.status {
        case .inGame, .gameOver: view.game
        case .noGame: nil
        }
    }

    /// The odds panel shows during the combat it was simulated for. It never takes clicks.
    var shownCombatOdds: CombatOddsView? {
        guard view.status == .inGame, let game = view.game, let odds = combatOdds, odds.isFor(game) else { return nil }
        return odds
    }

    /// Where the cursor makes the panel take clicks, in content-local top-left points.
    var interactiveRegions: [CGRect] {
        guard let layout, game != nil else { return [] }
        // The advisor's header collapses and expands its list.
        return [layout.hud] + (shownAdvice == nil ? [] : [layout.advisorHeader])
    }

    /// The leaderboard slot under the cursor, set by `OverlayController` from mouse moves.
    /// Hover never makes the panel take clicks: the opponent panels ignore the mouse.
    var hoveredSlot: Int?
    /// The hero-pick plate under the cursor (its placement chart shows), set the same way.
    var hoveredHeroPlate: Int?

    /// The game while Hearthstone shows its leaderboard: recruit and combat of a game in progress.
    var leaderboardGame: GameView? {
        guard view.status == .inGame, let game = view.game, game.phase != .heroPick, !game.lobby.isEmpty
        else { return nil }
        return game
    }

    /// The lobby by leaderboard slot (`place - 1`; the lobby's order when a place is missing).
    var slots: [Int: LobbyEntryView] {
        guard let game = leaderboardGame else { return [:] }
        var slots: [Int: LobbyEntryView] = [:]
        for (index, entry) in game.lobby.enumerated() {
            let slot = entry.place.map { $0 - 1 } ?? index
            if (0..<(layout?.constants.leaderboardSlots ?? 8)).contains(slot), slots[slot] == nil {
                slots[slot] = entry
            }
        }
        return slots
    }

    /// The next opponent's slot, whose portrait Hearthstone pops out.
    var nextOpponentSlot: Int? {
        guard let id = leaderboardGame?.nextOpponentPlayerID else { return nil }
        return slots.first { $0.value.playerID == id && !$0.value.isLocal }?.key
    }

    /// The opponent whose portrait is hovered; nil over the local player's own portrait.
    var hoveredOpponent: LobbyEntryView? {
        guard let hoveredSlot, let entry = slots[hoveredSlot], !entry.isLocal else { return nil }
        return entry
    }

    /// The leaderboard slot at a content-local point, or nil when the leaderboard isn't up.
    func leaderboardSlot(at point: CGPoint) -> Int? {
        guard let layout, let game = leaderboardGame else { return nil }
        return layout.leaderboardSlot(at: point, count: game.lobby.count, nextOpponent: nextOpponentSlot)
    }
}

struct OverlayRootView: View {
    let model: OverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let layout = model.layout {
                if model.showsLayoutGuides {
                    LayoutGuides(layout: layout)
                }
                if let game = model.game {
                    StatusHUD(game: game, isOver: model.view.status == .gameOver, scale: layout.panelScale,
                              metrics: layout.constants.hudMetrics, hide: model.hide)
                        .frame(width: layout.hud.width, height: layout.hud.height)
                        .offset(x: layout.hud.minX, y: layout.hud.minY)
                }
                if let tribes = model.game?.tribes {
                    TribesPanel(tribes: tribes, scale: layout.panelScale, metrics: layout.constants.tribesPanel)
                        .frame(width: layout.tribesPanel.width, height: layout.tribesPanel.height)
                        .offset(x: layout.tribesPanel.minX, y: layout.tribesPanel.minY)
                        .allowsHitTesting(false)
                }
                if let warning = model.alignmentWarning, model.game != nil {
                    AlignmentWarningBadge(text: warning, scale: layout.panelScale, layout: layout)
                }
                if let odds = model.shownCombatOdds {
                    CombatOddsPanel(odds: odds, scale: layout.panelScale, metrics: layout.constants.combatOddsMetrics)
                        .frame(width: layout.combatOddsPanel.width, height: layout.combatOddsPanel.height)
                        .offset(x: layout.combatOddsPanel.minX, y: layout.combatOddsPanel.minY)
                        .allowsHitTesting(false)
                }
                if let game = model.game, model.view.status == .inGame, game.phase == .recruit, let builds = game.builds {
                    BuildOverlays(
                        builds: builds, shopCount: game.shop.cards.count, layout: layout, cards: CardDataModel.shared.cards
                    )
                }
                if let advice = model.shownAdvice, let game = model.game, game.trinketPick == nil {
                    AdvisorOverlays(
                        advice: advice, game: game, layout: layout, collapsed: model.advisorCollapsed,
                        cards: CardDataModel.shared.cards, toggle: model.toggleAdvisor
                    )
                }
                if let pick = model.game?.trinketPick, model.view.status == .inGame {
                    TrinketPickPanel(pick: pick, scale: layout.panelScale)
                        .frame(width: max(layout.advisorPanel.width, 360 * layout.panelScale))
                        .offset(x: max(0, layout.advisorPanel.maxX - max(layout.advisorPanel.width, 360 * layout.panelScale)),
                                y: max(0, layout.advisorPanel.minY - 130 * layout.panelScale))
                        .allowsHitTesting(false)
                }
                if let game = model.leaderboardGame {
                    OpponentOverlays(model: model, game: game, layout: layout, cards: CardDataModel.shared.cards)
                }
                if let pick = model.heroPick {
                    HeroPickOverlays(pick: pick, layout: layout, hovered: model.hoveredHeroPlate, cards: CardDataModel.shared.cards)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }
}

/// Turn, phase, tavern tier and gold, in a small dark translucent panel. Its type and
/// spacing come from `HUDMetrics`, which the layout tests check against the HUD's size.
struct StatusHUD: View {
    let game: GameView
    let isOver: Bool
    let scale: CGFloat
    var metrics = HUDMetrics()
    let hide: () -> Void

    var body: some View {
        let m = metrics
        VStack(alignment: .leading, spacing: m.rowSpacing * scale) {
            HStack(spacing: m.titleSpacing * scale) {
                Text(turnText)
                    .font(.system(size: m.turnFontSize * scale, weight: .semibold))
                if let phaseText {
                    Text(phaseText)
                        .font(.system(size: m.phaseFontSize * scale, weight: .semibold))
                        .foregroundStyle(phaseColor)
                        .padding(.horizontal, m.phasePadding.width * scale)
                        .padding(.vertical, m.phasePadding.height * scale)
                        .background(phaseColor.opacity(0.18), in: Capsule())
                }
            }
            .lineLimit(1)
            HStack(spacing: m.itemSpacing * scale) {
                Label {
                    Text(tierText)
                } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow.opacity(0.85))
                }
                .help("Tavern tier")
                Label {
                    Text(goldText)
                } icon: {
                    Image(systemName: "circle.circle.fill").foregroundStyle(.orange.opacity(0.9))
                }
                .help("Gold")
                Spacer(minLength: 0)
                Button(action: hide) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: m.iconSize * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide the overlay (⌃⌥H)")
            }
            .lineLimit(1)
            .labelStyle(CompactLabelStyle(spacing: m.iconSpacing * scale, iconSize: m.iconSize * scale))
            .font(.system(size: m.valueFontSize * scale, weight: .medium))
        }
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, m.padding.width * scale)
        .padding(.vertical, m.padding.height * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HUDMaterial(cornerRadius: m.cornerRadius * scale))
        .overlay(
            RoundedRectangle(cornerRadius: m.cornerRadius * scale, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var turnText: String { game.bgTurn > 0 ? "Turn \(game.bgTurn)" : "Hero pick" }

    /// Nil at the hero pick, which the turn text already says.
    private var phaseText: String? {
        if isOver { return "Game over" }
        return switch game.phase {
        case .heroPick: nil
        case .recruit: "Recruit"
        case .combat: "Combat"
        }
    }

    private var phaseColor: Color {
        if isOver { return .secondary }
        return switch game.phase {
        case .heroPick: .purple
        case .recruit: .green
        case .combat: .red
        }
    }

    private var tierText: String { game.player?.tier.map(String.init) ?? "–" }

    private var goldText: String {
        guard let gold = game.player?.gold, game.bgTurn > 0 else { return "–" }
        return "\(gold.available)/\(gold.thisTurn)"
    }
}

private struct CompactLabelStyle: LabelStyle {
    var spacing: CGFloat
    var iconSize: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon.font(.system(size: iconSize))
            configuration.title
        }
    }
}

/// Outlines every rect the layout knows, for checking alignment against the game.
struct LayoutGuides: View {
    let layout: OverlayLayout

    var body: some View {
        Canvas { context, _ in
            func stroke(_ rect: CGRect, _ color: Color, dash: Bool = false) {
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(color),
                               style: StrokeStyle(lineWidth: 1, dash: dash ? [4, 3] : []))
            }
            stroke(layout.boardRegion, .white.opacity(0.35), dash: true)
            for i in 0..<layout.constants.leaderboardSlots {
                stroke(layout.leaderboardSlot(i), .cyan)
                stroke(layout.leaderboardArt(i), .cyan, dash: true)
                stroke(layout.leaderboardHitRect(i), .mint.opacity(0.6))
            }
            for k in 0..<7 {
                stroke(layout.boardSlot(.top, index: k, of: 7), .orange)
                stroke(layout.boardSlot(.player, index: k, of: 7), .green)
            }
            for element in HSElement.allCases { stroke(layout.rect(element), .pink) }
            for i in 0..<10 { stroke(layout.goldCoin(i), .yellow) }
            stroke(layout.hud, .white)
            stroke(layout.nextOpponentPreview, .white, dash: true)
            stroke(layout.nextOpponentOdds, .green.opacity(0.6), dash: true)
            stroke(layout.combatOddsPanel, .red.opacity(0.6), dash: true)
            stroke(layout.opponentPanel, .white, dash: true)
            stroke(layout.tribesPanel, .white, dash: true)
            stroke(layout.heroPickCapture, .purple)
            for i in 0..<4 {
                stroke(layout.heroPickPortrait(i, of: 4), .purple, dash: true)
                stroke(layout.heroPickPlate(i, of: 4), .purple)
            }
            stroke(layout.buildTipsPanel, .white, dash: true)
            stroke(layout.advisorPanel, .blue.opacity(0.7), dash: true)
            stroke(layout.advisorHeader, .blue.opacity(0.7))
            for k in 0..<7 { stroke(layout.advisorBadge(.shop(index: k, count: 7)), .blue.opacity(0.7)) }
            for button in [OverlayLayout.AdvisorElement.levelButton, .rollButton, .freezeButton] {
                stroke(layout.advisorBadge(button), .blue.opacity(0.7))
            }
        }
        .allowsHitTesting(false)
    }
}
