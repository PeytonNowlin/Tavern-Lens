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
        expectNear(preview.width, 148 * l.panelScale, 1e-9, "existing preview width")
        expectNear(preview.height, 228 * l.panelScale, 1e-9, "existing preview height")
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

    static var layouts: [OverlayLayout] {
        ReferenceFrame.all.map(\.layout) + [600.0, 3000.0].map {
            OverlayLayout(contentSize: CGSize(width: $0 * 16 / 9, height: $0))!
        }
    }

    static func contentSize(_ m: OddsPreviewMetrics, scale s: CGFloat) -> CGSize {
        let percent = m.percentSize(at: s)
        let footnote = m.footnoteSize(at: s)
        // Labels sit above values, so even all three widest values can fit at the text floor.
        let column = ["100%", ">99%", "<1%"].map { HUDFitTests.text($0, percent, .semibold) }.max()!
        let values = 3 * column + 2 * m.columnSpacing * s
        let foot = ["Lethal 100%", "Lethal >99%", "Take 99.9", "Deal 99.9"]
            .map { HUDFitTests.text($0, footnote, .semibold) }.max()!
        let titles = ["No odds", "Board too old", "Odds unavailable", "Updating…"]
            .map { HUDFitTests.text($0, percent, .semibold) }.max()!
        let details = ["Not fought yet", "No odds shown", "Calculation failed", "Board changed", "Calculating…"]
            .map { HUDFitTests.text($0, footnote, .regular) }.max()!
        let padding = NextOpponentPreviewMetrics(scale: s).padding.width
        let width = max(values, foot, titles, details) + 2 * padding
        let withOdds = 3 * m.lineHeight(at: s) + m.barHeight * s + 2 * m.rowSpacing * s
        let withoutData = 2 * m.lineHeight(at: s) + m.rowSpacing * s
        return CGSize(width: width, height: max(withOdds, withoutData))
    }

    @Test("Readable odds and every unavailable-data state fit at all reference scales")
    func fits() {
        for l in Self.layouts {
            let needed = Self.contentSize(l.constants.oddsPreview, scale: l.panelScale)
            #expect(needed.width <= l.nextOpponentOdds.width, "needs \(needed.width) pt wide, has \(l.nextOpponentOdds.width)")
            #expect(needed.height <= l.nextOpponentOdds.height,
                    "needs \(needed.height) pt tall, has \(l.nextOpponentOdds.height)")
        }
    }

    @Test("Seven minions, header, age and readable odds fit without growing the panel")
    func wholePreviewFits() {
        for l in Self.layouts {
            let s = l.panelScale
            let m = NextOpponentPreviewMetrics(scale: s)
            // Header, metadata, grouped board, divider and reserved odds: four outer gaps.
            let height = m.headerHeight + 8 * m.rowHeight + 1
                + l.constants.oddsPreview.height * s + 4 * m.rowSpacing + 2 * m.padding.height
            #expect(height <= l.nextOpponentPreview.height,
                    "seven-card preview needs \(height) pt, has \(l.nextOpponentPreview.height)")
            let width = l.nextOpponentPreview.width - 2 * m.padding.width
            let metadata = HUDFitTests.text("T6", m.bodyFontSize, .medium)
                + HUDFitTests.text("99HP", m.bodyFontSize, .medium)
                + ["This turn", "99t old", "Unseen"].map { HUDFitTests.text($0, m.bodyFontSize, .medium) }.max()!
                + 3 * m.cardSpacing  // includes the flexible space
            #expect(metadata <= width, "metadata needs \(metadata) pt, has \(width)")
            // Names yield first. Five-digit stats still leave room for a visibly truncated name.
            let statsAndName = HUDFitTests.text("99999/99999", m.bodyFontSize, .regular)
                + m.cardSpacing + HUDFitTests.text("M…", m.bodyFontSize, .regular)
            #expect(statsAndName <= width)
        }
    }

    @Test("Text retains its minimum size and each reserved row fits its system font")
    func typographyFitsRows() {
        // Include intermediate scales where a rounded font line height can change.
        for s in stride(from: CGFloat(0.8), through: 1.3, by: 0.01) {
            let m = NextOpponentPreviewMetrics(scale: s)
            let odds = OddsPreviewMetrics()
            #expect(m.bodyFontSize >= 11 && m.headerFontSize >= 12)
            #expect(odds.percentSize(at: s) >= 11 && odds.footnoteSize(at: s) >= 11)
            #expect(HUDFitTests.lineHeight(m.bodyFontSize, .medium) <= m.rowHeight)
            #expect(HUDFitTests.lineHeight(m.headerFontSize, .semibold) <= m.headerHeight)
            #expect(HUDFitTests.lineHeight(odds.percentSize(at: s), .semibold) <= odds.lineHeight(at: s))
            #expect(HUDFitTests.lineHeight(odds.footnoteSize(at: s), .regular) <= odds.lineHeight(at: s))
        }
    }
}
