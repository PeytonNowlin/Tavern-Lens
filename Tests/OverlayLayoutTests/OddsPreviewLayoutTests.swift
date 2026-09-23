import AppKit
import OverlayLayout
import Testing

/// The live odds section of the next-opponent preview: the preview grows by it (rather than a
/// new panel), it stays in the right margin clear of the board and HS UI, and its rows fit.
@Suite("Next opponent odds")
struct OddsPreviewLayoutTests {
    @Test("The odds section is the foot of the next opponent preview, which stays clear of the board",
          arguments: ReferenceFrame.all)
    func placement(frame: ReferenceFrame) {
        let l = frame.layout
        let odds = l.nextOpponentOdds
        let preview = l.nextOpponentPreview
        #expect(preview.contains(odds))
        expectNear(odds.maxY, preview.maxY, 1e-9, "at the preview's foot")
        expectNear(odds.width, preview.width, 1e-9, "the preview's width")
        expectNear(preview.height, (l.constants.nextOpponentPreviewHeight + l.constants.oddsPreview.height) * l.panelScale,
                   1e-9, "the preview grew by the section")
        #expect(CGRect(origin: .zero, size: l.size).contains(preview))
        for element in HSElement.allCases {
            #expect(!preview.intersects(l.rect(element)), "preview overlaps \(element)")
        }
        for k in 0..<7 {
            #expect(!preview.intersects(l.boardSlot(.top, index: k, of: 7)))
            #expect(!preview.intersects(l.boardSlot(.player, index: k, of: 7)))
            #expect(!preview.intersects(l.shopCell(k, of: 7)))
        }
        #expect(l.tribesPanel.minY > preview.maxY)
    }

    /// The preview's own padding and row spacing (`NextOpponentPreview`).
    static let previewPadding: CGFloat = 9
    static let previewSpacing: CGFloat = 4

    static func contentSize(_ m: OddsPreviewMetrics, scale s: CGFloat) -> CGSize {
        let percent = m.percentFontSize * s
        let footnote = m.footnoteFontSize * s
        // Three equal columns, each "L 100%".
        let column = HUDFitTests.text("L", percent, .semibold) + 2 * s + HUDFitTests.text("100%", percent, .semibold)
        let values = 3 * column + 2 * m.columnSpacing * s
        let foot = HUDFitTests.text("Lethal 100%", footnote, .semibold) + m.columnSpacing * s
            + HUDFitTests.text("8.0k…", footnote, .regular)
        let noData = HUDFitTests.text("No data: not fought yet", percent, .medium)
        let width = max(values, foot, noData) + 2 * previewPadding * s

        let above = 2 * previewSpacing * s + 1  // the divider and the spacing around it
        let withOdds = HUDFitTests.lineHeight(percent, .semibold) + m.barHeight * s
            + HUDFitTests.lineHeight(footnote, .semibold) + 2 * m.rowSpacing * s
        let withoutData = HUDFitTests.lineHeight(footnote, .medium) + HUDFitTests.lineHeight(percent, .medium)
            + m.rowSpacing * s
        return CGSize(width: width, height: above + max(withOdds, withoutData))
    }

    @Test("Win / tie / loss, the footnote and \"no data\" fit, at every reference frame and at the scale limits")
    func fits() {
        let layouts = ReferenceFrame.all.map(\.layout) + [600.0, 3000.0].map {
            OverlayLayout(contentSize: CGSize(width: $0 * 16 / 9, height: $0))!
        }
        for l in layouts {
            let needed = Self.contentSize(l.constants.oddsPreview, scale: l.panelScale)
            #expect(needed.width <= l.nextOpponentOdds.width, "needs \(needed.width) pt wide, has \(l.nextOpponentOdds.width)")
            #expect(needed.height <= l.nextOpponentOdds.height,
                    "needs \(needed.height) pt tall, has \(l.nextOpponentOdds.height)")
        }
    }
}
