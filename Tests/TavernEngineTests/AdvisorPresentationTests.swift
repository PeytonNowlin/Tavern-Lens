import Testing
import TavernEngine

@Suite("Advisor presentation")
struct AdvisorPresentationTests {
    private static func request() throws -> AdvisorRequest {
        var request = try AdvisorSynthetic.request(
            shop: [
                AdvisorSynthetic.shopMinion(3, attack: 2, health: 2, cost: 2, cardID: "cheap"),
                AdvisorSynthetic.shopMinion(4, attack: 2, health: 2, cost: 5, cardID: "expensive"),
                AdvisorSynthetic.shopMinion(5, attack: 2, health: 2, cost: 4, cardID: "tooDear"),
            ],
            hand: [AdvisorSynthetic.boardMinion(2, "hand_G", attack: 2, health: 2)], gold: 3,
            board: [AdvisorSynthetic.boardMinion(1, "TB_BaconUps_TEST", attack: 4, health: 4)]
        )
        request.baseCardIDs = ["TB_BaconUps_TEST": "engine"]
        var build = AdvisorBuild(id: "direction", name: "Suggested direction", share: 1,
                                 core: ["engine", "hand", "cheap", "tooDear"], addons: [])
        build.requirements = [
            BuildRequirement(role: "Engine", anyOf: ["engine", "unownedEngine"]),
            BuildRequirement(role: "Hand piece", anyOf: ["hand"]),
            BuildRequirement(role: "Payoff", anyOf: ["expensive", "cheap"]),
            BuildRequirement(role: "Reserve", anyOf: ["tooDear", "missing"]),
            BuildRequirement(role: "Seasonal condition", anyOf: []),
        ]
        request.strategyCatalog = [build]
        return request
    }

    private static func suggestion(rank: Int = 1) -> AdvisorSuggestion {
        let action = AdvisorAction.sell(board: 0, cardID: "engine")
        var suggestion = AdvisorSuggestion(
            rank: rank, action: action, targets: action.targets, reason: "Funds the stronger follow-up",
            confidence: .medium, odds: nil, gain: 3, terms: AdvisorTerms(combat: 3)
        )
        suggestion.continuation = ["Sell Engine", "Buy Payoff", "Play Payoff"]
        suggestion.limitations = ["Some effects are not modelled"]
        return suggestion
    }

    private static func view(_ request: AdvisorRequest, status: Advice.Status = .recommendation) -> AdviceView {
        var advice = Advice(status: status, note: "Combat evidence is limited",
                            suggestions: [suggestion(), suggestion(rank: 2)])
        advice.strategy = AdvisorStrategy.select(request)?.guidance
        return AdviceView(request: request, plan: .live, advice: advice, isComplete: true)
    }

    @Test("The next action and its reason stay separate from the exact ordered continuation")
    func recommendation() throws {
        let request = try Self.request()
        let presentation = AdvisorPresentation(advice: Self.view(request), request: request)
        #expect(presentation.state == .recommendation)
        #expect(presentation.title == "Sell Engine")
        #expect(presentation.reason == "Funds the stronger follow-up")
        #expect(presentation.note == "Combat evidence is limited")
        #expect(presentation.caveat == "Some effects are not modelled")
        let primary = try #require(presentation.primary)
        #expect(primary.steps == ["Sell Engine", "Buy Payoff", "Play Payoff"])
        #expect(primary.targets == [.init(.board, 0)])
        #expect(primary.limitations == ["Some effects are not modelled"])
        #expect(presentation.alternatives.map(\.rank) == [2])
    }

    @Test("Tentative advice does not become an imperative or a primary highlight")
    func tentative() throws {
        let request = try Self.request()
        let presentation = AdvisorPresentation(advice: Self.view(request, status: .noStrongRecommendation))
        #expect(presentation.state == .tentative)
        #expect(presentation.title == "No strong recommendation")
        #expect(presentation.reason == "Combat evidence is limited")
        #expect(presentation.primary == nil)
        #expect(presentation.alternatives.map(\.rank) == [1, 2])
        #expect(presentation.alternatives.first?.steps.first == "Sell Engine")
    }

    @Test("Changed, unavailable and missing-data states retract previous actions and direction")
    func retractsAdvice() throws {
        let request = try Self.request()
        var updating = Self.view(request); updating.isUpdating = true
        var failed = Self.view(request); failed.failure = "Simulation unavailable"
        let cases: [(AdviceView, AdvisorPresentation.State)] = [
            (updating, .updating), (failed, .unavailable),
            (Self.view(request, status: .thinking), .thinking),
            (Self.view(request, status: .noData), .noData),
        ]
        for (view, expected) in cases {
            let presentation = AdvisorPresentation(advice: view, request: request)
            #expect(presentation.state == expected)
            #expect(presentation.primary == nil)
            #expect(presentation.topSuggestion == nil)
            #expect(presentation.alternatives.isEmpty)
            #expect(presentation.direction == nil)
            #expect(presentation.requirements.isEmpty)
            #expect(presentation.note == nil)
            #expect(presentation.caveat == nil)
        }
        failed.isUpdating = true
        #expect(AdvisorPresentation(advice: failed).state == .unavailable)
    }

    @Test("Compact caveats omit neutral planner context while details retain the complete note")
    func compactCaveats() throws {
        let request = try Self.request()
        var view = Self.view(request)
        view.advice.suggestions[0].limitations = nil
        view.advice.note = "Plans use your board, scaling and gold · No recent combat evidence"
        let presentation = AdvisorPresentation(advice: view)
        #expect(presentation.caveat == "No recent combat evidence")
        #expect(presentation.note == view.advice.note)

        view.advice.status = .noStrongRecommendation
        view.advice.note = "Plans use your board, scaling and gold · Combat checks use recent boards + stronger stress scenarios · Unmodelled effects; no confident recommendation · Evaluation incomplete"
        let tentative = AdvisorPresentation(advice: view)
        #expect(tentative.reason == "Unmodelled effects; no confident recommendation · Evaluation incomplete")
        #expect(tentative.caveat == "Unmodelled effects; no confident recommendation")
        #expect(tentative.note == view.advice.note)
    }

    @Test("Archived swap advice identifies the sale prerequisite before the shop target")
    func swapPrerequisite() throws {
        let request = try Self.request()
        var view = Self.view(request)
        let action = AdvisorAction.swap(shop: 1, cardID: "new", sell: 2, soldCardID: "old")
        view.advice.suggestions = [AdvisorSuggestion(rank: 1, action: action, targets: action.targets,
            reason: "Make room", confidence: .high, odds: nil, gain: 4, terms: AdvisorTerms(combat: 4))]
        let primary = try #require(AdvisorPresentation(advice: view, name: { $0.uppercased() }).primary)
        #expect(primary.title == "Sell OLD, buy NEW")
        #expect(primary.steps == ["Sell OLD", "Buy NEW"])
        #expect(primary.targets == [.init(.board, 2), .init(.shop, 1)])
        #expect(view.advice.suggestions[0].targets == [.init(.shop, 1), .init(.board, 2)])
    }

    @Test("Requirements distinguish held goldens, affordable alternatives and unverified roles")
    func requirements() throws {
        let request = try Self.request()
        let presentation = AdvisorPresentation(advice: Self.view(request), request: request, name: { $0.uppercased() })
        #expect(presentation.requirements.map(\.state) == [.owned, .owned, .available, .required, .unverified])
        #expect(presentation.requirements[0].cards == ["ENGINE"])
        #expect(presentation.requirements[1].cards == ["HAND"])
        #expect(presentation.requirements[2].cards == ["CHEAP"])
        #expect(presentation.requirements[3].cards == ["TOODEAR", "MISSING"])
        #expect(presentation.requirements[4].cards.isEmpty)
    }

    @Test("Only the matching request can support ownership or availability claims")
    func requestIdentity() throws {
        let request = try Self.request()
        let view = Self.view(request)
        #expect(AdvisorPresentation(advice: view).requirements.isEmpty)
        var changed = request; changed.gold += 1
        let presentation = AdvisorPresentation(advice: view, request: changed)
        #expect(presentation.requirements.isEmpty)
        #expect(presentation.direction?.buildID == "direction")
        // Older bookmark fingerprints intentionally omit fields added by newer planners.
        var archivedPlan = AdvisorPlan.live; archivedPlan.version = 2
        let archived = AdviceView(request: request, plan: archivedPlan, advice: view.advice)
        #expect(!AdvisorPresentation(advice: archived, request: request).requirements.isEmpty)
    }

    @Test("Current detector fits remain distinct from a proposed direction")
    func currentFits() throws {
        let request = try Self.request()
        let detected = ["current", "secondary"].map {
            DetectedBuildView(id: $0, name: $0, tribes: [], coreHave: ["held"], coreMissing: [],
                              addonsHave: [], tips: BuildTipsView(keyCards: ["held"]), source: .overrides)
        }
        let presentation = AdvisorPresentation(advice: Self.view(request), detectedBuilds: detected)
        #expect(presentation.currentFits.map(\.id) == ["current", "secondary"])
        #expect(presentation.direction?.buildID == "direction")
        var updating = Self.view(request); updating.isUpdating = true
        #expect(AdvisorPresentation(advice: updating, detectedBuilds: detected).currentFits == detected)
    }

    @Test("A seasonal choice uses its own reason and cannot highlight stale recruit actions")
    func choice() throws {
        let request = try Self.request()
        var view = Self.view(request, status: .noStrongRecommendation)
        view.advice.choice = AdvisorChoice(entityID: 22, cardID: "trinket", name: "Engine trinket", cost: 2,
                                          reason: "Supplies the engine", confidence: .low)
        let presentation = AdvisorPresentation(advice: view, request: request)
        #expect(presentation.state == .choice)
        #expect(presentation.title == "Consider Engine trinket")
        #expect(presentation.reason == "Supplies the engine")
        #expect(presentation.choice?.entityID == 22)
        #expect(presentation.primary == nil)
        #expect(presentation.topSuggestion == nil)
        #expect(presentation.alternatives.isEmpty)
    }
}
