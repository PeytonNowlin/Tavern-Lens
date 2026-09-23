import AppKit
import OverlayLayout
import Testing

/// The lobby-tribes panel: in the right margin under the next-opponent preview's place,
/// clear of the board and Hearthstone's own UI, and big enough for a lobby of tribes.
@Suite("Tribes panel")
struct TribesPanelLayoutTests {
    @Test("It sits under the preview, aligned with the HUD, clear of the board and HS UI",
          arguments: ReferenceFrame.all)
    func placement(frame: ReferenceFrame) {
        let l = frame.layout
        let panel = l.tribesPanel
        #expect(CGRect(origin: .zero, size: l.size).contains(panel))
        #expect(panel.minY > l.nextOpponentPreview.maxY)
        expectNear(panel.minX, l.hud.minX, 1e-9, "aligned with the HUD")
        expectNear(panel.width, l.hud.width, 1e-9, "the HUD's width")
        #expect(panel.minX >= l.x(kx: 0.65))
        #expect(!panel.intersects(l.hud) && !panel.intersects(l.nextOpponentPreview) && !panel.intersects(l.opponentPanel))
        for element in HSElement.allCases {
            #expect(!panel.intersects(l.rect(element)), "tribes panel overlaps \(element)")
        }
        for k in 0..<7 {
            #expect(!panel.intersects(l.boardSlot(.top, index: k, of: 7)))
            #expect(!panel.intersects(l.boardSlot(.player, index: k, of: 7)))
            #expect(!panel.intersects(l.shopCell(k, of: 7)))
        }
        for i in 0..<8 { #expect(!panel.intersects(l.leaderboardHitRect(i, isNextOpponent: true))) }
    }

    /// The widest row: the longest tribe name with a percentage.
    static let names = ["Aberration", "Elemental", "Quilboar", "Undead", "Mech"]
    static let titles = [("Tribes", "uncertain"), ("Tribes", "3 of 5 sure"), ("Tribes", "⚠︎ screen ≠ log")]

    static func contentSize(_ m: TribesPanelMetrics, scale s: CGFloat) -> CGSize {
        let row = names.map { name in
            m.dotSize * s + m.dotSpacing * s + HUDFitTests.text(name, m.rowFontSize * s, .medium)
                + m.percentSpacing * s + HUDFitTests.text("100%", m.percentFontSize * s, .regular)
        }.max()!
        let title = titles.map {
            HUDFitTests.text($0.0, m.titleFontSize * s, .semibold) + m.percentSpacing * s
                + HUDFitTests.text($0.1, m.titleFontSize * s, .regular)
        }.max()!
        let rowHeight = max(HUDFitTests.lineHeight(m.rowFontSize * s, .medium), m.dotSize * s)
        let height = HUDFitTests.lineHeight(m.titleFontSize * s, .semibold) + m.titleSpacing * s
            + CGFloat(m.rows) * rowHeight + CGFloat(m.rows - 1) * m.rowSpacing * s + 2 * m.padding.height * s
        return CGSize(width: max(row, title) + 2 * m.padding.width * s, height: height)
    }

    @Test("A lobby's worth of tribes fits, at every reference frame and at the scale limits")
    func fits() {
        let layouts = ReferenceFrame.all.map(\.layout) + [600.0, 3000.0].map {
            OverlayLayout(contentSize: CGSize(width: $0 * 16 / 9, height: $0))!
        }
        for l in layouts {
            let needed = Self.contentSize(l.constants.tribesPanel, scale: l.panelScale)
            #expect(needed.width <= l.tribesPanel.width, "needs \(needed.width) pt wide, has \(l.tribesPanel.width)")
            #expect(needed.height <= l.tribesPanel.height, "needs \(needed.height) pt tall, has \(l.tribesPanel.height)")
        }
    }
}
