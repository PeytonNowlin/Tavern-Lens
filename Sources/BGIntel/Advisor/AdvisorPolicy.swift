import Foundation

/// The advisor policy a piece of advice was scored with. Archived advice (feedback bookmarks,
/// replay goldens) records its version and must re-score exactly, so every change to what the
/// advisor recommends for the same request ships as a new version, and every behavior added
/// since version 1 is a `Feature` that older versions leave off.
///
/// To change the advice: add a `Feature` at the next version, ask `policy.has(.feature)` where it
/// applies, and raise `live`. A new request field goes in `addedFields` at that version too, so
/// an older policy's fingerprint leaves it out (`AdvisorPolicyTests` fails until it is).
public struct AdvisorPolicy: Hashable, Comparable, Sendable {
    public var version: Int

    /// The app's.
    public static let live = AdvisorPolicy(version: 11)

    public init(version: Int) { self.version = version }

    /// Before version 5, a request carried no policy (nil): it reads as version 0, which has no
    /// features.
    public init(_ evaluationVersion: Int?) { version = evaluationVersion ?? 0 }

    public func has(_ feature: Feature) -> Bool { version >= feature.introduced }

    public static func < (lhs: AdvisorPolicy, rhs: AdvisorPolicy) -> Bool { lhs.version < rhs.version }

    public enum Feature: CaseIterable, Sendable {
        /// Bounded recruit plans replace scoring single board changes.
        case recruitPlanner
        /// A strategic direction (build) is selected and drives planning; pending choices are
        /// advised; a changed state gets fresh advice instead of refining the previous one.
        case strategicDirection
        /// Exact recorded effect definitions; ranking covers supported plans despite unmodelled
        /// alternatives. The request carries its policy (`RecruitContext.evaluationVersion`).
        case recordedEffects
        /// Captured discard engines and their linked rewards.
        case discardEffects
        /// The fingerprint names the policy, so one request scored by two policies differs.
        case policyInFingerprint
        /// Minion Activate powers, and a note naming those left unmodelled.
        case activateEffects
        /// Trinkets whose remaining one-time effect is observed (first-Deathrattle counter,
        /// Faceless Manipulator reward).
        case observedTrinketState
        /// Fruit Vendor's Tavern Dish Bananas.
        case bananaActivate
        /// Lovely Locket's spell copies.
        case spellCopies
        /// Easterly Winds trinkets.
        case easterlyWindsTrinkets
        /// Effects of playing a hand minion before its Battlecry.
        case playedMinionEffects
        /// Contextual fallback suggestions when no plan is supported, shown as estimated advice.
        case fallbackAdvice
        /// Nomi Sticker's Tavern Elemental buffs.
        case nomiSticker
        /// Recurring Elemental engine value.
        case elementalEngineValue
        /// Locked hand cards don't complete a build; corrected captured build requirements.
        /// Strategy selection applies them when scoring an older captured request too.
        case buildReadinessCorrections
        /// An unused purchase is worth its resale, not more than its price.
        case unusedPurchaseValue
        /// Lionfish's Fishbait Activate.
        case lionfishActivate
        /// Living Prison's armed next-purchase buff.
        case livingPrison
        /// Firestone card win rates by turn as an early-turn prior.
        case cardTurnPrior
        /// Fortify, Arcane Absorption and the cards that grant Absorption.
        case arcaneAbsorption
        /// The greater-trinket gold trinket.
        case greaterTrinketGold
        /// Each displayed decision records which effects and state the planner couldn't model.
        case coverageDiagnostics

        /// The version that introduced it.
        public var introduced: Int {
            switch self {
            case .recruitPlanner: 2
            case .strategicDirection: 3
            case .recordedEffects: 5
            case .discardEffects, .policyInFingerprint: 6
            case .activateEffects, .observedTrinketState: 7
            case .bananaActivate, .spellCopies: 8
            case .easterlyWindsTrinkets, .playedMinionEffects, .fallbackAdvice: 9
            case .nomiSticker, .elementalEngineValue, .buildReadinessCorrections, .unusedPurchaseValue: 10
            case .lionfishActivate, .livingPrison, .cardTurnPrior, .arcaneAbsorption, .greaterTrinketGold,
                 .coverageDiagnostics: 11
            }
        }
    }

    /// A request field added after version 1, which policies before `introduced` don't see.
    public struct AddedField: Sendable {
        /// `Type.property`, as `Mirror` names it.
        public var name: String
        public var introduced: Int
        /// Removes the field from a request.
        public var clear: @Sendable (inout AdvisorRequest) -> Void
    }

    /// Every request field added after version 1. A request rebuilt from logs by today's code
    /// carries them, so an older policy's fingerprint must clear them to match its archived advice.
    public static let addedFields: [AddedField] = [
        AddedField(name: "AdvisorRequest.recruit", introduced: 2) { $0.recruit = nil },
        AddedField(name: "AdvisorRequest.strategyCatalog", introduced: 3) { $0.strategyCatalog = nil },
        AddedField(name: "AdvisorRequest.choice", introduced: 3) { $0.choice = nil },
        AddedField(name: "AdvisorRequest.poolTiers", introduced: 3) { $0.poolTiers = nil },
        AddedField(name: "RecruitContext.evaluationVersion", introduced: 5) { $0.recruit?.evaluationVersion = nil },
        AddedField(name: "AdvisorRequest.cardTurnStats", introduced: 11) { $0.cardTurnStats = nil },
        AddedField(name: "AdvisorRequest.cardTurnStatsCheckedAt", introduced: 11) { $0.cardTurnStatsCheckedAt = nil },
        AddedField(name: "BattleGameState.ruleset", introduced: 11) {
            $0.preview.input?.gameState.ruleset = nil
            $0.recruit?.input.gameState.ruleset = nil
        },
        AddedField(name: "RecruitContext.pendingPrisonBuys", introduced: 11) { $0.recruit?.pendingPrisonBuys = nil },
        AddedField(name: "RecruitContext.Activation.costObserved", introduced: 11) {
            let activations = $0.recruit?.activations?.mapValues { value in
                var activation = value
                activation.costObserved = nil
                return activation
            }
            $0.recruit?.activations = activations
        },
    ]

    /// `request` as this policy identifies it: without the fields it predates and, from
    /// `policyInFingerprint`, naming this policy (archived encodings through version 5 are kept).
    public func identifying(_ request: AdvisorRequest) -> AdvisorRequest {
        var request = request
        for field in Self.addedFields where version < field.introduced { field.clear(&request) }
        if has(.policyInFingerprint) { request.recruit?.evaluationVersion = version }
        return request
    }
}

extension RecruitContext {
    /// The policy this context is being evaluated with.
    public var policy: AdvisorPolicy { AdvisorPolicy(evaluationVersion) }
}

extension AdvisorRequest {
    /// The policy its recruit context is being evaluated with.
    public var policy: AdvisorPolicy { AdvisorPolicy(recruit?.evaluationVersion) }
}
