import AppKit
import OverlayLayout
import Testing

/// Seam 2: the hero-pick stats plates line up with the four hero portraits of the pick
/// screen, stay clear of the screen's own UI and our panels, and fit their content.
@Suite("Hero-pick plates")
struct HeroPickLayoutTests {
    /// §8 of the coordinates note, on the player's 1710×1073 capture (U3): arch apex x of each
    /// portrait, and the portraits' vertical extent.
    static let measuredCentreKx: [CGFloat] = [-0.461, -0.150, 0.166, 0.481]

    @Test("Each plate is centred on its portrait and sits just above it", arguments: ReferenceFrame.all)
    func alignsWithPortraits(frame: ReferenceFrame) {
        let l = frame.layout
        for i in 0..<4 {
            let plate = l.heroPickPlate(i, of: 4)
            let portrait = l.heroPickPortrait(i, of: 4)
            expectNear(plate.midX, l.x(kx: Self.measuredCentreKx[i]), 0.004 * l.height, "plate \(i) centre x")
            expectNear(plate.midX, portrait.midX, 1e-9, "plate \(i) over its portrait")
            #expect(plate.width <= portrait.width, "plate \(i) no wider than the portrait")
            #expect(plate.maxY <= portrait.minY, "plate \(i) above the arch")
            #expect(portrait.minY - plate.maxY <= 0.02 * l.height, "plate \(i) close to its portrait")
            expectNear(portrait.minY, 0.298 * l.height, 0.5, "arch top")
            expectNear(portrait.maxY, 0.622 * l.height, 0.5, "name plate bottom")
        }
    }

    @Test("At 1920×1080 the portraits match the trackers' stats-plate formula (cx + (7 + (i − 1.5)·340)·s)")
    func matchesTrackerFormula() {
        let l = ReferenceFrame.fullHD.layout
        for i in 0..<4 {
            let tracker = l.centreX + (7 + (CGFloat(i) - 1.5) * 340) * l.referenceScale
            // The measured arch apexes sit within 0.005 h of the trackers' plates.
            expectNear(l.heroPickPlate(i, of: 4).midX, tracker, 0.006 * l.height, "hero \(i)")
        }
    }

    @Test("Plates and their charts don't overlap each other, the pick screen's UI or our panels", arguments: ReferenceFrame.all)
    func clearOfEverything(frame: ReferenceFrame) {
        let l = frame.layout
        let content = CGRect(origin: .zero, size: l.size)
        let plates = (0..<4).map { l.heroPickPlate($0, of: 4) }
        for (i, plate) in plates.enumerated() {
            #expect(content.contains(plate))
            #expect(content.contains(l.heroPickChart(i, of: 4)))
            for (j, other) in plates.enumerated() where j != i {
                #expect(!plate.intersects(other), "plates \(i) and \(j)")
                #expect(!l.heroPickChart(i, of: 4).intersects(other), "chart \(i) and plate \(j)")
            }
            for element in l.heroPickScreenElements {
                #expect(!plate.intersects(element), "plate \(i) overlaps \(element)")
            }
            for portrait in (0..<4).map({ l.heroPickPortrait($0, of: 4) }) {
                #expect(!plate.intersects(portrait), "plate \(i) overlaps a portrait")
            }
            for panel in [l.hud, l.tribesPanel, l.nextOpponentPreview] {
                #expect(!plate.intersects(panel) && !l.heroPickChart(i, of: 4).intersects(panel), "plate \(i) overlaps a panel")
            }
        }
    }

    @Test("The hover hit-test finds each plate at its centre and nothing between or below them", arguments: ReferenceFrame.all)
    func hitTest(frame: ReferenceFrame) {
        let l = frame.layout
        for i in 0..<4 {
            let plate = l.heroPickPlate(i, of: 4)
            #expect(l.heroPickPlate(at: CGPoint(x: plate.midX, y: plate.midY), count: 4) == i)
            #expect(l.heroPickPlate(at: CGPoint(x: plate.minX + 1, y: plate.maxY - 1), count: 4) == i)
            // The portrait itself stays Hearthstone's (its hero-power tooltip).
            let portrait = l.heroPickPortrait(i, of: 4)
            #expect(l.heroPickPlate(at: CGPoint(x: portrait.midX, y: portrait.midY), count: 4) == nil)
        }
        let gap = (l.heroPickPlate(0, of: 4).maxX + l.heroPickPlate(1, of: 4).minX) / 2
        #expect(l.heroPickPlate(at: CGPoint(x: gap, y: l.heroPickPlate(0, of: 4).midY), count: 4) == nil)
        #expect(l.heroPickPlate(at: CGPoint(x: l.centreX, y: 10), count: 4) == nil)
    }

    @Test("Offers of 2 or 3 heroes keep the pitch, centred where the four are")
    func otherCounts() {
        let l = ReferenceFrame.fullHD.layout
        let middle = Self.measuredCentreKx.reduce(0, +) / 4
        for count in [2, 3] {
            let centres = (0..<count).map { l.heroPickCentreKx($0, of: count) }
            expectNear(centres.reduce(0, +) / CGFloat(count), middle, 1e-9, "\(count) heroes centred")
            for k in 1..<count { expectNear(centres[k] - centres[k - 1], 0.314, 1e-9, "pitch") }
        }
    }

    /// The widest plate: a tier letter, "8.00", its caption, the stale and lock marks, and the
    /// widest top-4 / win row.
    static func plateContent(_ m: HeroPickMetrics, scale s: CGFloat) -> CGSize {
        let top = m.tierBadgeSize * s + m.itemSpacing * s + HUDFitTests.text("8.00", m.averageFontSize * s, .bold)
            + m.itemSpacing * s + HUDFitTests.text("avg place", m.captionFontSize * s, .regular)
            + m.itemSpacing * s + HUDFitTests.symbol("clock.badge.exclamationmark", m.captionFontSize * s)
            + m.itemSpacing * s + HUDFitTests.symbol("lock.fill", m.captionFontSize * s)
        let bottom = HUDFitTests.text("Top 4 100.0%  ·  Win 100.0%", m.detailFontSize * s, .medium)
        let height = max(m.tierBadgeSize * s, HUDFitTests.lineHeight(m.averageFontSize * s, .bold)) + m.rowSpacing * s
            + HUDFitTests.lineHeight(m.detailFontSize * s, .medium) + 2 * m.padding.height * s
        return CGSize(width: max(top, bottom) + 2 * m.padding.width * s, height: height)
    }

    @Test("The widest plate content fits its plate", arguments: ReferenceFrame.all)
    func contentFits(frame: ReferenceFrame) {
        let l = frame.layout
        let needed = Self.plateContent(l.constants.heroPick, scale: l.referenceScale)
        let plate = l.heroPickPlate(0, of: 4)
        #expect(needed.width <= plate.width, "needs \(needed.width) pt, has \(plate.width) at \(frame.name)")
        #expect(needed.height <= plate.height, "needs \(needed.height) pt tall, has \(plate.height)")
    }
}
