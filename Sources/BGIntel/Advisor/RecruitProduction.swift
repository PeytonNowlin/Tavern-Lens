import Foundation

enum RecruitProduction {
    static func value(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double {
        RecruitMechanics.production(card, state: state, context: context)
            + base(card, state: state, context: context)
    }

    private enum Role: Sendable {
        case resolvedCycle, handGems, gemsOnBoard
        case conditionalTail(gemBonus: Bool, fallback: Fallback)
    }
    private enum Fallback: Sendable {
        case gemSupply, endOfTurn(all: Bool), gold, sludge, none
    }
    private final class Description: Sendable {
        let mentionsBloodGem: Bool
        let suppliesBloodGems: Bool
        let role: Role

        init(_ normalized: String) {
            let text = normalized.lowercased()
            mentionsBloodGem = text.contains("blood gem")
            suppliesBloodGems = text.contains("get") && mentionsBloodGem
            if text.hasPrefix("battlecry:") || text.hasPrefix("when you sell this") { role = .resolvedCycle }
            else if text.contains("blood gems played from your hand") { role = .handGems }
            else if text.contains("plays a blood gem on all") || text.contains("plays 2 blood gems on all") {
                role = .gemsOnBoard
            } else {
                let fallback: Fallback
                if suppliesBloodGems { fallback = .gemSupply }
                else if text.contains("end of your turn") {
                    fallback = .endOfTurn(all: text.contains("all") || text.contains("your minions"))
                } else if text.contains("get"), text.contains("gold") || text.contains("coin") { fallback = .gold }
                else if text.contains("sludge corrosion") { fallback = .sludge }
                else { fallback = .none }
                role = .conditionalTail(gemBonus: text.contains("blood gems give an extra"), fallback: fallback)
            }
        }
    }

    private final class Descriptions: @unchecked Sendable {
        private let values = NSCache<NSString, Description>()
        init() { values.countLimit = 2048 }
        func get(_ normalized: String) -> Description {
            let key = normalized as NSString
            if let existing = values.object(forKey: key) { return existing }
            let result = Description(normalized)
            values.setObject(result, forKey: key)
            return result
        }
    }
    private static let descriptions = Descriptions()

    private static func base(_ card: AdvisorCard, state: RecruitState, context: RecruitContext) -> Double {
        if let value = RecruitElementalValue.production(card, state: state, context: context) { return value }
        if let value = RecruitDiscardEffects.fleshlingProduction(card, state: state, context: context) { return value }
        let description = descriptions.get(context.text(card.cardID))
        if case .resolvedCycle = description.role { return 0 }
        let gemValue = Double(2 + (state.input.playerBoard.player.globalInfo["BloodGemAttackBonus"] ?? 0)
                                + (state.input.playerBoard.player.globalInfo["BloodGemHealthBonus"] ?? 0)).squareRoot()
        switch description.role {
        case .resolvedCycle: return 0
        case .handGems:
            let supply = state.hand.filter { $0.cardID == "BG20_GEM" }.count
                + state.board.filter { descriptions.get(context.text($0.cardID)).suppliesBloodGems }.count * 2
            return Double(min(supply, 8)) * gemValue
        case .gemsOnBoard:
            return Double(max(0, state.board.count - 1)) * gemValue * (card.golden ? 2 : 1)
        case .conditionalTail(let gemBonus, let fallback):
            if gemBonus, state.board.contains(where: { descriptions.get(context.text($0.cardID)).mentionsBloodGem }) {
                return gemValue * 4
            }
            switch fallback {
            case .gemSupply: return gemValue * (card.golden ? 4 : 2)
            case .endOfTurn(let all):
                return (all ? Double(state.board.count) * 2 : 3)
                    * (card.golden ? 2 : 1) * Double(RecruitEffects.endOfTurnRepeats(state, context: context))
            case .gold: return 3
            case .sludge: return Double(state.board.count) * (card.golden ? 1.2 : 0.6)
            case .none: return 0
            }
        }
    }
}
