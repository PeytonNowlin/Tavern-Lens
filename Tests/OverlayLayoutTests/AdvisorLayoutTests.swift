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

    /// The expanded panel's content: `rows` rows (a title line and up to `reasonLines` reason
    /// lines, beside the rank badge), the note (`noteLines`), the divider and the header.
    static func contentHeight(_ m: AdvisorMetrics, scale s: CGFloat) -> CGFloat {
        let title = HUDFitTests.lineHeight(m.titleFontSize * s, .semibold)
        let reason = HUDFitTests.lineHeight(m.reasonFontSize * s, .regular)
        let row = max(m.rankDiameter * s, title + m.lineSpacing * s + CGFloat(m.reasonLines) * reason)
        let rows = CGFloat(m.rows) * row
        // Between the rows, the note, the divider and the header: rows + 2 gaps.
        let gaps = CGFloat(m.rows + 2) * m.rowSpacing * s
        let header = HUDFitTests.lineHeight(m.headerFontSize * s, .semibold)
        return rows + CGFloat(m.noteLines) * reason + 1 + gaps + header + 2 * m.padding.height * s
    }

    @Test("Three suggestions, a note and the header fit the list; the reasons fit their lines",
          arguments: [600.0, 872, 1073, 1080, 3000])
    func fits(height: CGFloat) {
        let l = OverlayLayout(contentSize: CGSize(width: height * 16 / 10, height: height))!
        let m = l.constants.advisor, s = l.panelScale
        let needed = Self.contentHeight(m, scale: s)
        #expect(needed <= l.advisorPanel.height, "needs \(needed) pt tall, has \(l.advisorPanel.height)")
        // Collapsed, the panel is the header strip: its line and the padding.
        #expect(m.headerHeight * s >= HUDFitTests.lineHeight(m.headerFontSize * s, .semibold) + 2 * m.padding.height * s,
                "the header strip holds its line")
        // The reason column: the panel less its padding, the rank badge and the gap after it.
        let column = l.advisorPanel.width - 2 * m.padding.width * s - m.rankDiameter * s - m.badgeSpacing * s
        for reason in [
            "+100% win vs next opponent", "Takes 12 less damage vs next opponent",
            "No buy beats your board (100% win)", "Keeps your board as it is (100% win)", "Saves a +15% win buy for next turn",
            "Cuts lethal risk 100% → 50%", "Deals 12 more damage to next opponent",
            // The blended score's reasons, with the longest build name there is.
            "Core card for Aberration Tavern Spells", "Add-on for Aberration Tavern Spells",
            "Opens tier 6 for a core card you need", "Keeps a build card for next turn", "Stronger vs the rest of the lobby",
            "Behind the levelling curve (tier 4)", "Good tempo to level (costs 10)", "Frees the gold to level now",
            "No shop card helps (100% win)", "-100% loss vs turn 10 opponent", "+100% win vs turn 10 opponent",
        ] {
            let width = HUDFitTests.text(reason, m.reasonFontSize * s, .regular)
            #expect(width <= CGFloat(m.reasonLines) * column * 0.9, "\"\(reason)\" is \(width) pt; \(m.reasonLines) lines of \(column)")
        }
        // The notes fit their lines, at the panel's width less its padding.
        let noteWidth = l.advisorPanel.width - 2 * m.padding.width * s
        for note in [
            "Their board is from turn 12 · scored vs turn 10 opponent", "Next opponent unseen · scored vs turn 10 opponent",
            "Nothing clearly improves your odds", "Their board is from turn 12",
        ] {
            let width = HUDFitTests.text(note, m.reasonFontSize * s, .regular)
            #expect(width <= CGFloat(m.noteLines) * noteWidth * 0.9, "\"\(note)\" is \(width) pt; \(m.noteLines) lines of \(noteWidth)")
        }
        // The confidence label always shows beside a title (longer titles are cut to fit).
        let title = HUDFitTests.text("Level to tier 6", m.titleFontSize * s, .semibold)
            + 3 * s + HUDFitTests.text("Med", m.reasonFontSize * s, .semibold)
        #expect(title <= column, "title line \(title) pt of \(column)")
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
