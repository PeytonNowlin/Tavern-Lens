import Foundation
import BGIntel
import EntityStore
import HSData
import PowerParser

public struct TrinketOfferRating: Codable, Hashable, Sendable {
    public var entityID: Int
    public var cardID: String
    public var name: String
    public var cost: Int?
    public var rank: Int?
    public var rating: String
    public var reason: String
    public var score: Double?
    public var affordable: Bool
    public var averagePlacement: Double?
    public var sampleSize: Int?
}

public struct TrinketPickView: Codable, Hashable, Sendable {
    public var choiceID: Int
    /// Original left-to-right offer order; rank is separate from screen position.
    public var offers: [TrinketOfferRating]
    public var note: String
}

/// GENERAL choices include discovers as well as trinkets. Require every offered card to
/// actually be a trinket, wait for its display task, and clear on chosen/new choices/games.
struct TrinketPickTracker: Sendable {
    var choice: EntityChoice?
    mutating func observe(_ event: PowerEvent) {
        switch event {
        case .newGameAnnounced: choice = nil
        case .entityChoices(let c): choice = c.choiceType == "GENERAL" ? c : nil
        case .entitiesChosen(let id, _) where choice?.id == id: choice = nil
        default: break
        }
    }

    func project(store: EntityStore, cards: CardDB, game: GameView, lastTaskListEnded: Int?, stats: TrinketStats? = nil, now: Date = Date()) -> TrinketPickView? {
        guard game.phase == .recruit, let choice, !choice.options.isEmpty,
              choice.taskList.map({ (lastTaskListEnded ?? Int.min) >= $0 }) ?? true else { return nil }
        var offers: [(Int, Card, Int?)] = []
        for option in choice.options {
            let entity = store[option.entityID]
            let id = entity.map(\.cardID).flatMap { $0.isEmpty ? nil : $0 } ?? option.cardID
            guard let card = cards[id], card.type == "BATTLEGROUND_TRINKET" else { return nil }
            offers.append((option.entityID, card, entity?.int(TrinketRater.costTag) ?? card.cost))
        }
        return TrinketRater.rate(choiceID: choice.id, offers: offers, game: game, cards: cards, stats: stats, now: now)
    }
}

/// Explainable board-fit estimates. These are neither population win rates nor an optimal
/// policy. Unrecognised effects stay unrated instead of receiving an invented average score.
public enum TrinketRater {
    /// COST (tag 48); the live price of the offered trinket.
    static let costTag = GameTag.id(48)

    /// The board facts every trinket model draws on.
    private struct BoardFit {
        var boardCount: Int, discarders: Int, endOfTurns: Int, hp: Int, horizon: Double, heldSpells: Int
    }

    public static func rate(choiceID: Int, offers: [(Int, Card, Int?)], game: GameView, cards: CardDB, stats: TrinketStats? = nil, now: Date = Date()) -> TrinketPickView {
        let board = game.player?.board ?? []
        let texts = board.map { RecruitContext.plain(cards[$0.cardID]?.text ?? "").lowercased() }
        let gold = game.player?.gold.available ?? 0
        let hp = game.player?.hero?.hp ?? 30
        let fit = BoardFit(
            boardCount: board.count,
            discarders: texts.filter { $0.contains("activate (") && $0.contains("discard a card") }.count,
            endOfTurns: texts.filter { $0.contains("at the end of your turn") }.count,
            hp: hp, horizon: TrinketWeights.horizon(hp: hp),
            heldSpells: game.player?.hand.filter { cards[$0.cardID]?.type == "BATTLEGROUND_SPELL" || cards[$0.cardID]?.type == "SPELL" }.count ?? 0)
        let stand = game.player?.mechanics?.trinkets.contains { $0.cardID == TrinketRaterTable.souvenirStandID } ?? false
        var ratings = offers.map { entity, card, cost -> TrinketOfferRating in
            var value: Double?, reason = "Effect not rated yet; compare its text before choosing"
            if let effect = TrinketRaterTable.effects[card.id], let modelled = model(effect, card: card, fit: fit) {
                value = modelled.score; reason = modelled.reason
            }
            let copied = stand && card.id != TrinketRaterTable.souvenirStandID
            if let current = value {
                value = current * (copied ? TrinketWeights.standCopyMultiplier : 1) - Double(cost ?? 0) * TrinketWeights.costPenalty
                if copied { reason += "; Souvenir Stand copies it" }
            }
            let hasBoardModel = value != nil
            let meta = stats?.entry(card.id, now: now)
            if let meta {
                // A modest population prior; board-specific engine payoff can outweigh it.
                let prior = max(-TrinketWeights.priorLimit, min(TrinketWeights.priorLimit,
                    (TrinketWeights.priorNeutralPlacement - meta.averagePlacement) * TrinketWeights.priorPerPlacement))
                if let local = value { value = local + prior }
                else {
                    value = TrinketWeights.baselineScore + prior - Double(cost ?? 0) * TrinketWeights.costPenalty
                    reason = "Population baseline only; board interaction not modelled"
                }
            }
            let affordable = cost.map { $0 <= gold } ?? false
            let rating = !affordable ? "Unavailable" : value.map { hasBoardModel ? label($0) : "Meta baseline" } ?? "Unrated"
            return TrinketOfferRating(entityID: entity, cardID: card.id, name: card.name, cost: cost,
                rank: nil, rating: rating, reason: reason, score: value, affordable: affordable, averagePlacement: meta?.averagePlacement, sampleSize: meta?.dataPoints)
        }
        let order = ratings.indices.filter { ratings[$0].score != nil && ratings[$0].affordable }.sorted {
            let (a, b) = (ratings[$0].score ?? 0, ratings[$1].score ?? 0)
            return a == b ? $0 < $1 : a > b
        }
        for (i, index) in order.enumerated() { ratings[index].rank = i + 1 }
        return TrinketPickView(choiceID: choiceID, offers: ratings,
            note: (stats?.usable(now: now) == true ? "Firestone · past 3 days · all ranks + board fit" : "Local board-fit estimates · no fresh population data") + " · low confidence" + (ratings.contains { $0.score == nil } ? " · some choices unrated" : ""))
    }

    private static func label(_ score: Double) -> String {
        score >= TrinketWeights.strongFit ? "Strong fit" : score >= TrinketWeights.goodFit ? "Good fit" : "Weak fit"
    }

    /// Board-fit score and reason before cost, copying and the population prior; nil if the card text no longer fits the model.
    private static func model(_ effect: TrinketEffect, card: Card, fit: BoardFit) -> (score: Double, reason: String)? {
        switch effect {
        case .sludgeCorrosion:
            return (Double(fit.boardCount) * (1 + Double(fit.discarders) * fit.horizon),
                    fit.discarders > 0 ? "\(fit.discarders) discard minion(s) supply repeated board buffs" : "Immediate board buff; no discard engine yet")
        case .endOfTurnRepeat:
            return (Double(fit.endOfTurns) * TrinketWeights.endOfTurnRepeatValue * fit.horizon,
                    fit.endOfTurns > 0 ? "Repeats \(fit.endOfTurns) existing end-of-turn effect(s)" : "No end-of-turn engine on your board")
        case .endOfTurnBuff:
            let text = RecruitContext.plain(card.text ?? "")
            guard text.hasPrefix(TrinketRaterTable.buffPrefix), let regex = TrinketRaterTable.buffPattern,
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            let ns = text as NSString
            let a = Double(ns.substring(with: match.range(at: 1))) ?? 0
            let h = Double(ns.substring(with: match.range(at: 2))) ?? 0
            return ((a + h) * Double(fit.boardCount) * TrinketWeights.endOfTurnBuffShare * fit.horizon, "Buffs all \(fit.boardCount) minions every turn")
        case .souvenirStand:
            let invest = fit.hp > TrinketWeights.healthyHP
            return (invest ? TrinketWeights.standInvestScore : TrinketWeights.standRiskyScore,
                    invest ? "Invests in a second Greater Trinket; no immediate board strength" : "Delayed payoff is risky at your current health")
        case .tierFourMinions:
            return (TrinketWeights.tierFourMinionsScore, "Three immediate minion options; outcomes are random")
        case .darkGiftDiscover:
            return (TrinketWeights.darkGiftDiscoverScore, "A tailored Tier 4 minion plus a Dark Gift; choices are unknown")
        case .spellPairs:
            return (TrinketWeights.spellPairsPerTurn * fit.horizon + Double(fit.discarders), "Recurring spell supply; only one of each pair can be played")
        case .spellBuffs:
            let supply = fit.heldSpells + fit.discarders
            return (Double(supply) * fit.horizon * TrinketWeights.spellBuffValue,
                    supply > 0 ? "Supports your spell supply; needs targeted buff spells to ramp" : "Little spell supply visible on your board")
        }
    }
}
