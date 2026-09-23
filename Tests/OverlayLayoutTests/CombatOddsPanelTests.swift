import AppKit
import OverlayLayout
import Testing

/// The combat odds panel sits under the HUD in the right margin during combat, clear of the
/// opponent's board and Hearthstone's combat UI, and its widest content fits it.
@Suite("Combat odds panel")
struct CombatOddsPanelTests {
    @Test("Under the HUD in the right margin, clear of the board and Hearthstone's UI", arguments: ReferenceFrame.all)
    func placement(frame: ReferenceFrame) {
        let l = frame.layout
        let panel = l.combatOddsPanel
        #expect(CGRect(origin: .zero, size: l.size).contains(panel))
        #expect(panel.minY > l.hud.maxY)
        expectNear(panel.minX, l.hud.minX, 1e-9, "aligned with the HUD")
        expectNear(panel.width, l.hud.width, 1e-9, "as wide as the HUD")
        #expect(panel.minX >= l.x(kx: 0.65))
        for element in HSElement.allCases {
            #expect(!panel.intersects(l.rect(element)), "panel overlaps \(element)")
        }
        for k in 0..<7 {
            #expect(!panel.intersects(l.boardSlot(.top, index: k, of: 7)))
            #expect(!panel.intersects(l.boardSlot(.player, index: k, of: 7)))
        }
        for i in 0..<8 { #expect(!panel.intersects(l.leaderboardHitRect(i, isNextOpponent: true))) }
        expectNear(panel.height, 104 * l.panelScale, 1e-6, "height")
    }

    @Test("The widest content fits", arguments: ReferenceFrame.all)
    func fits(frame: ReferenceFrame) {
        let l = frame.layout
        let needed = Self.contentSize(l.constants.combatOddsMetrics, scale: l.panelScale)
        #expect(needed.width <= l.combatOddsPanel.width, "needs \(needed.width) pt, has \(l.combatOddsPanel.width)")
        #expect(needed.height <= l.combatOddsPanel.height, "needs \(needed.height) pt tall, has \(l.combatOddsPanel.height)")
    }

    /// Laid out as `CombatOddsPanel` does, with the widest values each row can show.
    static func contentSize(_ m: CombatOddsMetrics, scale s: CGFloat) -> CGSize {
        typealias F = HUDFitTests
        let column = max(F.text("Loss", m.labelFontSize * s, .medium), F.text("100%", m.percentFontSize * s, .semibold))
        let columns = 3 * column + 2 * m.columnSpacing * s
        let damage = F.text("Take 10.7 (10–15)", m.damageFontSize * s, .medium)
        let footer = F.text("Lethal 100%", m.warningFontSize * s, .semibold) + m.columnSpacing * s
            + F.text("8.0k", m.footnoteFontSize * s, .regular)
        let width = max(columns, damage, footer) + 2 * m.padding.width * s
        let height = F.lineHeight(m.labelFontSize * s, .medium) + F.lineHeight(m.percentFontSize * s, .semibold)
            + m.barHeight * s + 2 * F.lineHeight(m.damageFontSize * s, .medium)
            + max(F.lineHeight(m.warningFontSize * s, .semibold), F.lineHeight(m.footnoteFontSize * s, .regular))
            + 4 * m.rowSpacing * s + 2 * m.padding.height * s
        return CGSize(width: width, height: height)
    }
}
