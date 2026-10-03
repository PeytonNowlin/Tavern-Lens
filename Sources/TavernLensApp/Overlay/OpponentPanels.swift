import OverlayLayout
import SwiftUI
import TavernEngine

/// The leaderboard's opponent info: the next opponent's highlight and board preview, and the
/// panel for the hovered portrait. None of it takes the mouse, so it never blocks a click.
struct OpponentOverlays: View {
    let model: OverlayModel
    let game: GameView
    let layout: OverlayLayout
    let cards: CardDB?

    var body: some View {
        let scale = layout.panelScale
        let ringInset = layout.constants.opponentPanels.ringInset
        ZStack(alignment: .topLeading) {
            if let slot = model.nextOpponentSlot {
                let art = layout.leaderboardArt(slot, isNextOpponent: true).insetBy(dx: -ringInset * scale, dy: -ringInset * scale)
                NextOpponentRing(scale: scale, metrics: layout.constants.opponentPanels)
                    .frame(width: art.width, height: art.height)
                    .offset(x: art.minX, y: art.minY)
            }
            if game.phase == .recruit, let next = game.nextOpponent, !next.isLocal {
                let rect = layout.nextOpponentPreview
                NextOpponentPreview(entry: next, currentTurn: game.bgTurn, cards: cards, scale: scale,
                                    odds: model.shownOddsPreview, oddsMetrics: layout.constants.oddsPreview)
                    .frame(width: rect.width, height: rect.height, alignment: .top)
                    .offset(x: rect.minX, y: rect.minY)
            }
            if let entry = model.hoveredOpponent {
                let rect = layout.opponentPanel
                OpponentPanel(
                    entry: entry, isNext: entry.playerID == game.nextOpponentPlayerID,
                    currentTurn: game.bgTurn, cards: cards, scale: scale, metrics: layout.constants.opponentPanels
                )
                .frame(width: rect.width, height: rect.height, alignment: .top)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Marks the next opponent's portrait on Hearthstone's leaderboard.
struct NextOpponentRing: View {
    let scale: CGFloat
    var metrics = OpponentPanelMetrics()

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.ringCornerRadius * scale, style: .continuous)
            .strokeBorder(Palette.next, lineWidth: metrics.ringLineWidth * scale)
            .shadow(color: Palette.next.opacity(0.7), radius: metrics.ringGlowRadius * scale)
    }
}

/// The hovered opponent: hero, name, tier, triples, health, and their last-seen board.
struct OpponentPanel: View {
    let entry: LobbyEntryView
    let isNext: Bool
    let currentTurn: Int
    let cards: CardDB?
    let scale: CGFloat
    var metrics = OpponentPanelMetrics()

    var body: some View {
        let m = metrics
        VStack(alignment: .leading, spacing: m.panelSpacing * scale) {
            HStack(alignment: .firstTextBaseline, spacing: m.panelSpacing * scale) {
                Text(OpponentText.heroName(entry, cards: cards))
                    .font(.system(size: m.heroNameFontSize * scale, weight: .semibold))
                if let name = entry.displayName {
                    Text(name)
                        .font(.system(size: m.playerNameFontSize * scale))
                        .foregroundStyle(.secondary)
                }
                if isNext {
                    Tag(text: "Next opponent", color: Palette.next, scale: scale, metrics: m)
                }
                if entry.isDead {
                    Tag(text: entry.place.map { "Out · \(OpponentText.ordinal($0))" } ?? "Out", color: .secondary,
                        scale: scale, metrics: m)
                }
                Spacer(minLength: m.panelPadding.width * scale)
                StatLabel(symbol: "star.fill", tint: Palette.tier, text: entry.tier.map(String.init) ?? "–",
                          scale: scale, metrics: m)
                StatLabel(symbol: "trophy.fill", tint: Palette.triple, text: "\(entry.hero.triples)", scale: scale, metrics: m)
                StatLabel(symbol: "heart.fill", tint: Palette.health, text: OpponentText.health(entry), scale: scale, metrics: m)
            }
            .lineLimit(1)

            if let board = entry.lastSeenBoard {
                HStack(spacing: m.tileSpacing * scale) {
                    Text(OpponentText.seen(board, currentTurn: currentTurn))
                        .font(.system(size: m.seenFontSize * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let seenHero = board.heroCardID, seenHero != entry.heroCardID {
                        Text("as \(cards?.name(of: seenHero) ?? seenHero)")
                            .font(.system(size: m.seenFontSize * scale))
                            .foregroundStyle(.tertiary)
                    }
                    if let likely = board.likelyBuild {
                        Text("Likely build: \(likely.name)")
                            .font(.system(size: m.seenFontSize * scale, weight: .semibold))
                            .foregroundStyle(Palette.build)
                    }
                }
                if board.cards.isEmpty {
                    Placeholder(text: "Empty board", scale: scale, metrics: m)
                } else {
                    HStack(spacing: m.tileSpacing * scale) {
                        ForEach(Array(board.cards.enumerated()), id: \.offset) { _, card in
                            MinionTile(card: card, cards: cards, scale: scale, metrics: m)
                        }
                    }
                }
            } else {
                Placeholder(text: "Not seen: you haven't fought them yet", scale: scale, metrics: m)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, m.panelPadding.width * scale)
        .padding(.vertical, m.panelPadding.height * scale)
        .fixedSize()
        .hudPanel(cornerRadius: m.cornerRadius * scale)
    }
}

/// One minion of a last-seen board: tier, combat keywords, name, attack and health.
struct MinionTile: View {
    let card: CardView
    let cards: CardDB?
    let scale: CGFloat
    var metrics = OpponentPanelMetrics()

    var body: some View {
        let m = metrics
        VStack(spacing: m.tileRowSpacing * scale) {
            HStack(spacing: 2 * scale) {
                if let tier = card.tier {
                    Text("\(tier)")
                        .font(.system(size: m.tileTierFontSize * scale, weight: .bold))
                        .foregroundStyle(Palette.tier)
                }
                Spacer(minLength: 0)
                ForEach(KeywordBadge.shown(card.keywords), id: \.self) { keyword in
                    Image(systemName: KeywordBadge.symbol(keyword))
                        .font(.system(size: m.tileKeywordFontSize * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(OpponentText.cardName(card, cards: cards))
                .font(.system(size: m.tileNameFontSize * scale, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(card.attack.map(String.init) ?? "–").foregroundStyle(Palette.attack)
                Spacer(minLength: 0)
                Text(card.health.map(String.init) ?? "–").foregroundStyle(Palette.health)
            }
            .font(.system(size: m.tileStatFontSize * scale, weight: .bold))
        }
        .padding(.horizontal, m.tilePadding.width * scale)
        .padding(.vertical, m.tilePadding.height * scale)
        .frame(width: m.tileSize.width * scale, height: m.tileSize.height * scale)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: m.tileCornerRadius * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: m.tileCornerRadius * scale, style: .continuous)
                .strokeBorder(card.golden ? Palette.golden : .white.opacity(0.1), lineWidth: card.golden ? 1.5 : 0.5)
        )
    }
}

/// The next opponent, compact: hero, tier, health, their last-seen board as a list, and the live
/// odds of the board as it is now against it.
struct NextOpponentPreview: View {
    let entry: LobbyEntryView
    let currentTurn: Int
    let cards: CardDB?
    let scale: CGFloat
    /// The recruit-phase odds preview for this opponent; nil until the first request reaches it.
    var odds: OddsPreviewView?
    var oddsMetrics = OddsPreviewMetrics()

    var body: some View {
        let m = NextOpponentPreviewMetrics(scale: scale)
        VStack(alignment: .leading, spacing: m.rowSpacing) {
            Text("Next · \(OpponentText.heroName(entry, cards: cards))")
                .font(.system(size: m.headerFontSize, weight: .semibold))
                .foregroundStyle(Palette.next)
                .frame(height: m.headerHeight, alignment: .leading)
            HStack(spacing: m.cardSpacing) {
                Text("T\(entry.tier.map(String.init) ?? "–")").foregroundStyle(Palette.tier)
                Text("\(OpponentText.health(entry))HP").foregroundStyle(Palette.health)
                Spacer(minLength: 0)
                Text(OpponentText.previewAge(entry.lastSeenBoard, currentTurn: currentTurn))
                    .foregroundStyle(isStale ? Color.orange : Color.secondary)
            }
            .font(.system(size: m.bodyFontSize, weight: .medium))
            .frame(height: m.rowHeight)

            VStack(alignment: .leading, spacing: 0) {
                if let board = entry.lastSeenBoard {
                    if board.cards.isEmpty {
                        Text("Empty board").foregroundStyle(.secondary)
                            .frame(height: m.rowHeight)
                    }
                    ForEach(Array(board.cards.prefix(7).enumerated()), id: \.offset) { _, card in
                        HStack(spacing: m.cardSpacing) {
                            Text(OpponentText.cardName(card, cards: cards))
                                .foregroundStyle(card.golden ? Palette.golden : .primary)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(OpponentText.stats(card))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                        }
                        .frame(height: m.rowHeight)
                    }
                } else {
                    Text("Not seen yet").foregroundStyle(.secondary)
                        .frame(height: m.rowHeight)
                }
            }
            .font(.system(size: m.bodyFontSize))
            .frame(height: 7 * m.rowHeight, alignment: .top)

            Divider().opacity(0.5).frame(height: 1)
            PreviewOdds(odds: odds, seen: entry.lastSeenBoard != nil, scale: scale, metrics: oddsMetrics)
                .frame(height: oddsMetrics.height * scale, alignment: .top)
        }
        .lineLimit(1)
        .monospacedDigit()
        .padding(.horizontal, m.padding.width)
        .padding(.vertical, m.padding.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hudPanel(cornerRadius: LayoutConstants.current.opponentPanels.cornerRadius * scale)
    }

    private var isStale: Bool {
        entry.lastSeenBoard.map { currentTurn - $0.bgTurn >= AdvisorRequest.staleBoardTurns } ?? false
    }
}

// MARK: - Pieces

/// Colour only where it carries meaning: the next fight, stats in Hearthstone's own colours, golden.
private enum Palette {
    static let next = Color.orange
    static let tier = Color.yellow.opacity(0.85)
    static let triple = Color(OverlayPalette.triple)
    static let golden = Color(OverlayPalette.golden)
    static let attack = Color(OverlayPalette.attack)
    static let health = Color(OverlayPalette.health)
    static let build = Color(OverlayPalette.likelyBuild)
}

private struct StatLabel: View {
    let symbol: String
    let tint: Color
    let text: String
    let scale: CGFloat
    let metrics: OpponentPanelMetrics

    var body: some View {
        HStack(spacing: 3 * scale) {
            Image(systemName: symbol)
                .font(.system(size: metrics.statSymbolFontSize * scale))
                .foregroundStyle(tint)
            Text(text).font(.system(size: metrics.statFontSize * scale, weight: .semibold))
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    let scale: CGFloat
    let metrics: OpponentPanelMetrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.tagFontSize * scale, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, metrics.tagPadding.width * scale)
            .padding(.vertical, metrics.tagPadding.height * scale)
            .background(color.opacity(0.18), in: Capsule())
    }
}

private struct Placeholder: View {
    let text: String
    let scale: CGFloat
    let metrics: OpponentPanelMetrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.placeholderFontSize * scale, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: metrics.placeholderMinWidth * scale, alignment: .leading)
            .padding(.vertical, metrics.placeholderPadding * scale)
    }
}

private enum KeywordBadge {
    /// The keywords that change a combat, in a fixed order.
    static let combat: [BGKeyword] = [.taunt, .divineShield, .reborn, .poisonous, .venomous, .windfury,
                                      .megaWindfury, .stealth]

    static func shown(_ keywords: [BGKeyword]) -> [BGKeyword] { combat.filter(keywords.contains) }

    static func symbol(_ keyword: BGKeyword) -> String {
        switch keyword {
        case .taunt: "shield.fill"
        case .divineShield: "sun.max.fill"
        case .reborn: "arrow.counterclockwise"
        case .poisonous, .venomous: "drop.fill"
        case .windfury, .megaWindfury: "wind"
        case .stealth: "eye.slash.fill"
        default: "circle.fill"
        }
    }
}

enum OpponentText {
    static func heroName(_ entry: LobbyEntryView, cards: CardDB?) -> String {
        entry.heroName ?? cards?.name(of: entry.heroCardID) ?? entry.heroCardID
    }

    /// The live engine may run without card data, so fall back to the app's card DB.
    static func cardName(_ card: CardView, cards: CardDB?) -> String {
        card.name ?? cards?.name(of: card.cardID) ?? card.cardID
    }

    static func health(_ entry: LobbyEntryView) -> String {
        OverlayText.health(hp: entry.hero.hp, isDead: entry.isDead)
    }

    static func stats(_ card: CardView) -> String {
        OverlayText.stats(attack: card.attack, health: card.health)
    }

    static func seen(_ board: LastSeenBoardView, currentTurn: Int) -> String {
        OverlayText.seen(bgTurn: board.bgTurn, currentTurn: currentTurn)
    }

    static func previewAge(_ board: LastSeenBoardView?, currentTurn: Int) -> String {
        OverlayText.previewAge(seenTurn: board?.bgTurn, currentTurn: currentTurn)
    }

    static func ordinal(_ n: Int) -> String { OverlayText.ordinal(n) }
}
