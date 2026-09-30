import AppKit
import OverlayLayout
import Testing

/// The advisor: its ranked list at the bottom of the right margin (near the gold bar, above
/// Hearthstone's journal and settings buttons), and rank badges on the cards and buttons its
/// suggestions point at.
@Suite("Advisor overlays")
struct AdvisorLayoutTests {
    @Test("The list sits at the bottom of the right margin, right-aligned with the HUD, clear of the board and HS UI",
          arguments: ReferenceFrame.all)
    func panelPlacement(frame: ReferenceFrame) {
        let l = frame.layout
        let panel = l.advisorPanel
        #expect(CGRect(origin: .zero, size: l.size).contains(panel))
        expectNear(panel.maxX, l.hud.maxX, 1e-9, "right-aligned with the HUD")
        #expect(panel.width > l.hud.width, "wider than the HUD, for legible text")
        #expect(panel.maxY < l.rect(.journalButton).minY && panel.maxY < l.rect(.settingsButton).minY)
        #expect(panel.minY > l.buildTipsPanel.maxY, "under the build tips")
        // Near the gold bar: just above the gold coins' row, to the right of the gold pill.
        #expect(panel.maxY < l.goldCoin(0).minY && panel.maxY > l.goldCoin(0).minY - 3 * l.constants.panelGap * l.panelScale)
        #expect(panel.minX > l.rect(.goldPill).maxX)
        for element in HSElement.allCases { #expect(!panel.intersects(l.rect(element)), "list overlaps \(element)") }
        for k in 0..<7 {
            #expect(!panel.intersects(l.boardSlot(.top, index: k, of: 7)))
            #expect(!panel.intersects(l.boardSlot(.player, index: k, of: 7)))
            #expect(!panel.intersects(l.shopCell(k, of: 7)))
        }
        for i in 0..<10 { #expect(!panel.intersects(l.goldCoin(i))) }
        for i in 0..<8 { #expect(!panel.intersects(l.leaderboardHitRect(i, isNextOpponent: true))) }

        let header = l.advisorHeader
        #expect(panel.contains(header))
        expectNear(header.maxY, panel.maxY, 1e-9, "the header is the panel's bottom strip")
    }

    @Test("Details reuse the side column without covering game controls or other active panels",
          arguments: ReferenceFrame.all)
    func detailsPlacement(frame: ReferenceFrame) {
        let l = frame.layout
        let panel = l.advisorDetailsPanel
        #expect(panel == l.buildTipsPanel, "build guidance is replaced, not covered by another wider panel")
        #expect(CGRect(origin: .zero, size: l.size).contains(panel))
        for other in [l.advisorPanel, l.hud, l.nextOpponentPreview, l.tribesPanel, l.alignmentWarning] {
            #expect(!panel.intersects(other))
        }
        for element in HSElement.allCases {
            #expect(!panel.intersects(l.rect(element)), "details overlap \(element)")
        }
        for k in 0..<7 {
            #expect(!panel.intersects(l.boardSlot(.top, index: k, of: 7)))
            #expect(!panel.intersects(l.boardSlot(.player, index: k, of: 7)))
            #expect(!panel.intersects(l.shopCell(k, of: 7)))
        }
        for k in 0..<8 { #expect(!panel.intersects(l.leaderboardHitRect(k, isNextOpponent: true))) }
        for k in 0..<10 { #expect(!panel.intersects(l.goldCoin(k))) }
    }

    @Test("Advisor clicks stay within visible controls and the open details scroll surface",
          arguments: ReferenceFrame.all)
    func interactiveRegions(frame: ReferenceFrame) {
        let l = frame.layout
        let details = l.advisorDetailsButton
        let collapse = l.advisorCollapseButton
        #expect(!details.intersects(collapse))
        let controls = details.union(collapse)
        expectNear(controls.minX, l.advisorHeader.minX, 1e-9)
        expectNear(controls.minY, l.advisorHeader.minY, 1e-9)
        expectNear(controls.width, l.advisorHeader.width, 1e-9)
        expectNear(controls.height, l.advisorHeader.height, 1e-9)
        #expect(l.advisorInteractiveRegions(collapsed: false, detailsExpanded: false) == [details, collapse])
        #expect(l.advisorInteractiveRegions(collapsed: false, detailsExpanded: true)
                == [details, collapse, l.advisorDetailsPanel])
        // A stale expanded flag must not leave an invisible scroll surface intercepting clicks.
        for expanded in [false, true] {
            #expect(l.advisorInteractiveRegions(collapsed: true, detailsExpanded: expanded) == [l.advisorHeader])
        }
        let cardCentre = CGPoint(x: l.advisorPanel.midX, y: l.advisorPanel.minY + 10)
        for expanded in [false, true] {
            #expect(!l.advisorInteractiveRegions(collapsed: false, detailsExpanded: expanded)
                .contains { $0.contains(cardCentre) }, "the recommendation body is click-through")
        }
    }

    @Test("Both density presets preserve readable actual-point type at the panel scale limits",
          arguments: [600.0, 872, 1073, 1080, 3000])
    func readableDensity(height: CGFloat) {
        let l = OverlayLayout(contentSize: CGSize(width: height * 16 / 10, height: height))!
        for density in OverlayDensity.allCases {
            let type = l.advisorTypography(density: density)
            #expect(type.titleFontSize >= 16)
            #expect(type.bodyFontSize >= 12 && type.labelFontSize >= 12 && type.headerFontSize >= 12)
            #expect(HUDFitTests.lineHeight(type.headerFontSize, .semibold) < l.advisorHeader.height)
            let detailsLabel = HUDFitTests.text("Hide details", type.headerFontSize, .semibold)
            #expect(detailsLabel + 2 * l.constants.advisor.padding.width * l.panelScale
                    < l.advisorDetailsButton.width)
        }
        let compact = l.advisorTypography(density: .compact)
        let comfortable = l.advisorTypography(density: .comfortable)
        #expect(compact.reasonLines < comfortable.reasonLines)
        #expect(compact.contextLines < comfortable.contextLines)
        // Presets are content choices; they do not widen the safe area or move its controls.
        expectNear(l.advisorPanel.width, 250 * l.panelScale, 1e-9)
        expectNear(l.advisorPanel.height, 262 * l.panelScale, 1e-9)
        expectNear(l.advisorHeader.height, 34 * l.panelScale, 1e-9)
    }

    /// The minimum summary keeps the action, confidence and caveat visible. ViewThatFits may
    /// drop context and the ordinary reason, but must preserve the warning and readable type.
    static func summaryHeight(_ l: OverlayLayout, density: OverlayDensity, titleLines: Int,
                              reasonLines: Int, caveatLines: Int = 2) -> CGFloat {
        let type = l.advisorTypography(density: density)
        let title = CGFloat(titleLines) * HUDFitTests.lineHeight(type.titleFontSize, .semibold)
        let label = HUDFitTests.lineHeight(type.labelFontSize, .medium)
        let reason = CGFloat(reasonLines) * HUDFitTests.lineHeight(type.bodyFontSize, .regular)
        let caveat = CGFloat(caveatLines) * HUDFitTests.lineHeight(type.labelFontSize, .regular)
        // Eyebrow, action and confidence always show; each optional text block adds a gap.
        let gaps = 2 + (reasonLines > 0 ? 1 : 0) + (caveatLines > 0 ? 1 : 0)
        return label + title + label + reason + caveat + CGFloat(gaps) * 7 * l.panelScale
            + 20 * l.panelScale + 1 + l.advisorHeader.height
    }

    static func wrappedHeight(_ value: String, width: CGFloat, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let string = NSAttributedString(string: value, attributes: [
            .font: HUDFitTests.font(size, weight), .paragraphStyle: paragraph,
        ])
        return ceil(string.boundingRect(with: CGSize(width: width, height: 1000),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    @Test("The readable action, confidence and two-line caveat fit when secondary content is omitted",
          arguments: [600.0, 872, 1073, 1080, 3000])
    func summaryFits(height: CGFloat) {
        let l = OverlayLayout(contentSize: CGSize(width: height * 16 / 10, height: height))!
        let column = l.advisorPanel.width - 2 * l.constants.advisor.padding.width * l.panelScale
        for density in OverlayDensity.allCases {
            let type = l.advisorTypography(density: density)
            #expect(Self.summaryHeight(l, density: density, titleLines: 4, reasonLines: 0)
                    <= l.advisorPanel.height, "a long action must retain confidence and its caveat without shrinking text")
            #expect(Self.summaryHeight(l, density: density, titleLines: 2, reasonLines: type.reasonLines)
                    <= l.advisorPanel.height, "ordinary actions keep both their reason and their caveat")
            #expect(Self.summaryHeight(l, density: density, titleLines: 4, reasonLines: 1, caveatLines: 0)
                    <= l.advisorPanel.height, "long actions keep their reason when there is no caveat")
            for title in [
                "Sell Fleet Admiral Tethys, buy Brann Bronzebeard",
                "Sell Defiant Shipwright, buy Recurring Nightmare",
                "Buy Transmuted Bramblewitch", "No strong recommendation", "Updating advice…",
            ] {
                let needed = Self.wrappedHeight(title, width: column, size: type.titleFontSize, weight: .semibold)
                #expect(needed <= 4 * HUDFitTests.lineHeight(type.titleFontSize, .semibold),
                        "action \(title) needs \(needed) points; its sale prerequisite must stay visible")
            }
            let confidence = HUDFitTests.text("Medium confidence", type.labelFontSize, .regular)
            let limits = HUDFitTests.text("· 3 limits", type.labelFontSize, .regular)
            #expect(confidence + 4 + limits <= column, "confidence and the limitation cue fit beside one another")
            for caveat in ["Their board is from turn 12", "Some effects are not modelled",
                           "Scored vs turn 10 opponent (next one unseen)"] {
                let needed = Self.wrappedHeight(caveat, width: column, size: type.labelFontSize, weight: .regular)
                #expect(needed <= 2 * HUDFitTests.lineHeight(type.labelFontSize, .regular),
                        "the actual caveat must be readable beside the action")
            }
            // The full explanation remains in details; these common primary reasons fit the
            // comfortable two-line allowance without introducing the former rank gutter.
            for reason in ["Frees the gold to level now", "Core card for Aberration Tavern Spells",
                           "Your position changed. Checking the next action."] {
                let needed = Self.wrappedHeight(reason, width: column, size: type.bodyFontSize, weight: .regular)
                #expect(needed <= 2 * HUDFitTests.lineHeight(type.bodyFontSize, .regular))
            }
        }
    }

    @Test("Highlights sit on their targets: shop cards, board minions, hand cards and the tavern buttons",
          arguments: ReferenceFrame.all)
    func targets(frame: ReferenceFrame) {
        let l = frame.layout
        #expect(l.advisorTarget(.levelButton) == l.rect(.tavernUpgradeButton))
        #expect(l.advisorTarget(.rollButton) == l.rect(.refreshButton))
        #expect(l.advisorTarget(.freezeButton) == l.rect(.freezeButton))
        let bounds = CGRect(origin: .zero, size: l.size)
        for count in 1...7 {
            for k in 0..<count {
                #expect(l.advisorTarget(.shop(index: k, count: count)) == l.shopCell(k, of: count))
                #expect(l.advisorTarget(.board(index: k, count: count)) == l.boardSlot(.player, index: k, of: count))
                for element in [OverlayLayout.AdvisorElement.shop(index: k, count: count), .board(index: k, count: count)] {
                    let target = l.advisorTarget(element), badge = l.advisorBadge(element), ring = l.advisorRing(element)
                    #expect(target.contains(badge) && target.contains(ring))
                    #expect(bounds.contains(badge))
                }
                let badge = l.advisorBadge(.shop(index: k, count: count))
                // Clear of the build highlight's badge on the same card, and of the neighbour's card.
                #expect(!badge.intersects(l.shopHighlightBadge(k, of: count)))
                if k + 1 < count {
                    #expect(!badge.intersects(l.shopCell(k + 1, of: count)))
                    #expect(!l.advisorBadge(.board(index: k, count: count)).intersects(l.boardSlot(.player, index: k + 1, of: count)))
                }
                // In the card's top-right corner, away from the tier shield (top-left).
                #expect(badge.midX > l.shopCell(k, of: count).midX && badge.midY < l.shopCell(k, of: count).midY)
            }
        }
        for button in [OverlayLayout.AdvisorElement.levelButton, .rollButton, .freezeButton] {
            #expect(l.advisorTarget(button).contains(l.advisorBadge(button)))
        }
        // The three buttons' badges don't touch each other.
        let buttons = [l.advisorBadge(.levelButton), l.advisorBadge(.rollButton), l.advisorBadge(.freezeButton)]
        #expect(!buttons[0].intersects(buttons[1]) && !buttons[1].intersects(buttons[2]))
    }

    @Test("The Next pill fits its label and target without spilling onto neighbouring controls",
          arguments: ReferenceFrame.all)
    func nextPill(frame: ReferenceFrame) {
        let l = frame.layout
        let bounds = CGRect(origin: .zero, size: l.size)
        func check(_ element: OverlayLayout.AdvisorElement) {
            let pill = l.advisorNextBadge(element)
            #expect(l.advisorTarget(element).contains(pill))
            #expect(bounds.contains(pill))
            let fontSize = max(12, pill.height * 0.48)
            #expect(HUDFitTests.text("Next", fontSize, .semibold) + 8 <= pill.width,
                    "the Next label keeps four-point horizontal padding")
            #expect(HUDFitTests.lineHeight(fontSize, .semibold) + 4 <= pill.height)
        }
        for count in 1...7 {
            for k in 0..<count {
                for element in [OverlayLayout.AdvisorElement.shop(index: k, count: count), .board(index: k, count: count)] {
                    check(element)
                    let pill = l.advisorNextBadge(element)
                    for other in 0..<count where other != k {
                        #expect(!pill.intersects(l.shopCell(other, of: count)))
                        #expect(!pill.intersects(l.boardSlot(.player, index: other, of: count)))
                    }
                    for control in HSElement.allCases {
                        #expect(!pill.intersects(l.rect(control)), "Next marker overlaps \(control)")
                    }
                }
                #expect(!l.advisorNextBadge(.shop(index: k, count: count))
                    .intersects(l.shopHighlightBadge(k, of: count)))
                #expect(l.advisorNextBadge(.shop(index: k, count: count)).minY
                        > l.rect(.opponentHeroPower).maxY)
            }
        }
        for element in [OverlayLayout.AdvisorElement.levelButton, .rollButton, .freezeButton] { check(element) }
        let buttons = [l.advisorNextBadge(.levelButton), l.advisorNextBadge(.rollButton), l.advisorNextBadge(.freezeButton)]
        #expect(!buttons[0].intersects(buttons[1]) && !buttons[1].intersects(buttons[2]))
        for count in 1...10 {
            for k in 0..<count {
                check(.hand(index: k, count: count))
                let pill = l.advisorNextBadge(.hand(index: k, count: count))
                #expect(pill.maxY < l.rect(.goldPill).minY)
                if k + 1 < count {
                    #expect(pill.maxX <= l.advisorNextBadge(.hand(index: k + 1, count: count)).minX)
                }
            }
        }
    }

    @Test("Hand badges follow the trackers' fan: left to right, apart, on screen and above the gold bar",
          arguments: ReferenceFrame.all)
    func hand(frame: ReferenceFrame) {
        let l = frame.layout
        let bounds = CGRect(origin: .zero, size: l.size)
        // The §2b worked example: 5 cards at 1920x1080 centred at 714.8, 818.5, 922.2, 1025.9, 1129.6.
        if frame.name == ReferenceFrame.fullHD.name {
            for (i, x) in [714.8, 818.5, 922.2, 1025.9, 1129.6].enumerated() {
                expectNear(l.handCard(i, of: 5).midX, x, 0.2, "hand card \(i) of 5")
            }
        }
        for count in 1...10 {
            let badges = (0..<count).map { l.advisorBadge(.hand(index: $0, count: count)) }
            for (i, badge) in badges.enumerated() {
                #expect(bounds.contains(badge))
                #expect(badge.maxY < l.rect(.goldPill).minY)
                if i + 1 < count { #expect(badge.maxX <= badges[i + 1].minX, "hand badges \(i), \(i + 1) of \(count)") }
            }
        }
    }
}
