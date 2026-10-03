import AppKit
import OverlayLayout
import Testing

/// The build overlays: shop highlights on the right shop slots, and the tips panel in the
/// right margin, clear of the board and Hearthstone's own UI.
@Suite("Build overlays")
struct BuildOverlayLayoutTests {
    @Test("Each highlight sits on its own shop card, for every shop size", arguments: ReferenceFrame.all)
    func highlightsOnSlots(frame: ReferenceFrame) {
        let l = frame.layout
        for count in 1...7 {
            for k in 0..<count {
                let ring = l.shopHighlight(k, of: count)
                // Hearthstone centres the n shop items on the window; slot k of n.
                let expectedX = l.centreX + (CGFloat(k) - CGFloat(count - 1) / 2) * l.constants.slotPitch * l.height
                expectNear(ring.midX, expectedX, 1e-6, "slot \(k) of \(count)")
                #expect(ring == l.shopCell(k, of: count))
                // Only its own card: no other card's centre is inside it.
                for other in 0..<count where other != k {
                    let centre = CGPoint(x: l.shopCell(other, of: count).midX, y: l.shopCell(other, of: count).midY)
                    #expect(!ring.contains(centre))
                }
                let badge = l.shopHighlightBadge(k, of: count)
                #expect(badge.minX >= ring.minX && badge.maxX <= ring.maxX, "badge within its card")
                expectNear(badge.midY, ring.maxY, 1e-6, "badge on the card's bottom edge")
                if k + 1 < count { #expect(!badge.intersects(l.shopHighlightBadge(k + 1, of: count))) }
                for p in 0..<7 { #expect(!badge.intersects(l.boardSlot(.player, index: p, of: 7))) }
                for element in HSElement.allCases { #expect(!badge.intersects(l.rect(element)), "badge overlaps \(element)") }
            }
        }
    }

    @Test("1710x1073: highlights land on the four shop items of the capture (§8c)")
    func capture() {
        let l = ReferenceFrame.notched.layout
        let measured: [CGFloat] = [758, 922, 1083, 1241].map { $0 / 1.1696 }
        for (k, x) in measured.enumerated() {
            let ring = l.shopHighlight(k, of: 4)
            #expect(ring.contains(CGPoint(x: x, y: 0.372 * l.height)), "shop item \(k) centre inside its highlight")
        }
    }

    @Test("The tips panel sits under the tribes panel, aligned with the HUD, clear of the board and HS UI",
          arguments: ReferenceFrame.all)
    func tipsPlacement(frame: ReferenceFrame) {
        let l = frame.layout
        let panel = l.buildTipsPanel
        #expect(CGRect(origin: .zero, size: l.size).contains(panel))
        #expect(panel.minY > l.tribesPanel.maxY)
        expectNear(panel.minX, l.hud.minX, 1e-9, "aligned with the HUD")
        expectNear(panel.width, l.hud.width, 1e-9, "the HUD's width")
        for other in [l.hud, l.nextOpponentPreview, l.tribesPanel, l.opponentPanel] { #expect(!panel.intersects(other)) }
        for element in HSElement.allCases { #expect(!panel.intersects(l.rect(element)), "tips panel overlaps \(element)") }
        for k in 0..<7 {
            #expect(!panel.intersects(l.boardSlot(.top, index: k, of: 7)))
            #expect(!panel.intersects(l.boardSlot(.player, index: k, of: 7)))
            #expect(!panel.intersects(l.shopCell(k, of: 7)))
        }
        for i in 0..<8 { #expect(!panel.intersects(l.leaderboardHitRect(i, isNextOpponent: true))) }
    }

    /// `BuildTipsPanel`'s height for `cards` full build cards, laid out as the view does: a
    /// "Current fit" header, then per card the name, an "Experimental fit" line and the owned and
    /// missing core rows; between two cards a 1 pt divider, the card spacing on each side.
    static func contentHeight(cards: Int, _ m: BuildOverlayMetrics, scale s: CGFloat) -> CGFloat {
        let type = BuildTipsTypography(panelScale: s)
        let header = HUDFitTests.lineHeight(type.headerFontSize, .semibold)
        let name = HUDFitTests.lineHeight(type.nameFontSize, .semibold)
        let body = HUDFitTests.lineHeight(type.bodyFontSize, .regular)
        let card = name + 3 * body + 3 * m.partSpacing * s
        let spacing = m.cardSpacing * s
        let dividers = CGFloat(cards - 1) * (2 * spacing + 1)
        return header + spacing + CGFloat(cards) * card + dividers + 2 * m.padding.height * s
    }

    @Test("The tips panel's real type is at least its readable minimum, at every scale")
    func tipsTypography() {
        for scale in [0.8, 1.0, 1.3, 2.0] as [CGFloat] {
            let type = BuildTipsTypography(panelScale: scale)
            #expect(type.headerFontSize >= 12 && type.bodyFontSize >= 12 && type.nameFontSize >= 14)
        }
    }

    @Test("One full build card fits the tips panel, at every reference frame and at the scale limits")
    func tipsFit() {
        let layouts = ReferenceFrame.all.map(\.layout) + [600.0, 3000.0].map {
            OverlayLayout(contentSize: CGSize(width: $0 * 16 / 9, height: $0))!
        }
        for l in layouts {
            // The view shows two cards only when they fit; one must always fit.
            let needed = Self.contentHeight(cards: 1, l.constants.buildOverlay, scale: l.panelScale)
            #expect(needed <= l.buildTipsPanel.height, "needs \(needed) pt tall, has \(l.buildTipsPanel.height)")
            // The build name is one line, tail-truncated: at the real 14-point minimum a long
            // name such as "Aberration Tavern Spells" no longer fits the panel's width, by design.
        }
    }
}
