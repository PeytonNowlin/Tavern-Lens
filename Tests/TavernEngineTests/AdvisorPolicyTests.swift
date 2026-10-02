import Foundation
import Testing
import TavernEngine

@Suite("Advisor policy versions")
struct AdvisorPolicyTests {
    /// Fields every policy's fingerprint has always included. A field missing from here and from
    /// `AdvisorPolicy.addedFields` is new: add it to `addedFields` at the policy that introduces
    /// it, or older policies' fingerprints change and archived advice stops matching its replays.
    static let fingerprintedByEveryPolicy: Set<String> = [
        "AdvisorRequest.preview", "AdvisorRequest.gold", "AdvisorRequest.tier", "AdvisorRequest.board",
        "AdvisorRequest.hand", "AdvisorRequest.shop", "AdvisorRequest.levelCost", "AdvisorRequest.rollCost",
        "AdvisorRequest.canFreeze", "AdvisorRequest.shopFrozen", "AdvisorRequest.income", "AdvisorRequest.goldCap",
        "AdvisorRequest.lobby", "AdvisorRequest.builds", "AdvisorRequest.baseCardIDs", "AdvisorRequest.standIn",
        "OddsPreviewRequest.gameSeed", "OddsPreviewRequest.bgTurn", "OddsPreviewRequest.opponentPlayerID",
        "OddsPreviewRequest.opponentSeenTurn", "OddsPreviewRequest.opponentSource", "OddsPreviewRequest.input",
        "OddsPreviewRequest.tribesKnown",
        "RecruitContext.input", "RecruitContext.definitions", "RecruitContext.powerCosts", "RecruitContext.build",
        "RecruitContext.darkDiscovery", "RecruitContext.pendingChoice", "RecruitContext.strategicEvaluation",
        "RecruitContext.linkedDiscards", "RecruitContext.activations",
        "RecruitContext.Activation.ready", "RecruitContext.Activation.cost",
        "BattleGameState.currentTurn", "BattleGameState.anomalies", "BattleGameState.anomalyDbfIds",
        "BattleGameState.numberOfPlayersAlive", "BattleGameState.validTribes",
    ]

    static func fields(_ value: Any, as type: String) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap { $0.label.map { "\(type).\($0)" } })
    }

    @Test("Every request field is either fingerprinted by every policy or registered with its policy")
    func everyFieldDeclared() throws {
        let request = try AdvisorCardTurnPriorTests.request()
        let context = try #require(request.recruit)
        let declared = Self.fingerprintedByEveryPolicy.union(AdvisorPolicy.addedFields.map(\.name))
        let actual = Self.fields(request, as: "AdvisorRequest")
            .union(Self.fields(request.preview, as: "OddsPreviewRequest"))
            .union(Self.fields(context, as: "RecruitContext"))
            .union(Self.fields(RecruitContext.Activation(ready: true, cost: 1), as: "RecruitContext.Activation"))
            .union(Self.fields(context.input.gameState, as: "BattleGameState"))
        #expect(actual.subtracting(declared).sorted() == [], "New request fields need an AdvisorPolicy.addedFields entry")
        #expect(declared.subtracting(actual).sorted() == [], "Declared fields that no longer exist")
    }

    @Test("A policy's fingerprint ignores fields added after it")
    func addedFieldsIgnoredByOlderPolicies() throws {
        let request = try AdvisorCardTurnPriorTests.request()
        for field in AdvisorPolicy.addedFields {
            var without = request
            field.clear(&without)
            #expect(AdviceView.fingerprint(of: without, version: field.introduced - 1)
                == AdviceView.fingerprint(of: request, version: field.introduced - 1), "\(field.name)")
        }
    }

    @Test("Features are introduced by released policies")
    func featureVersions() {
        for feature in AdvisorPolicy.Feature.allCases {
            #expect((2...AdvisorPolicy.live.version).contains(feature.introduced), "\(feature)")
            #expect(AdvisorPolicy.live.has(feature))
            #expect(!AdvisorPolicy(version: feature.introduced - 1).has(feature))
        }
        #expect(AdvisorPolicy(nil).version == 0)
        #expect(AdvisorPlan.live.policy == .live)
    }
}
