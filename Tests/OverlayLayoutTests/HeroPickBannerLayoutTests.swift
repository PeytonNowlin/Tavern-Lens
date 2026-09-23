import AppKit
import OverlayLayout
import Testing

/// The hero-pick banner the screen reader captures, the alignment check against it, and
/// the overlay's "misaligned" notice.
@Suite("Hero-pick banner")
struct HeroPickBannerLayoutTests {
    /// §8d, U3 at 1710×1073: the tribes' text block and the title's text box.
    @Test("The banner's title and tribes sit where they were measured")
    func measured() {
        let l = ReferenceFrame.notched.layout
        let h = l.height
        let tribes = l.heroPickTribes, title = l.heroPickTitle
        expectNear((tribes.minX - l.centreX) / h, -0.085, 0.004, "tribes left kx")
        expectNear((tribes.maxX - l.centreX) / h, 0.089, 0.004, "tribes right kx")
        expectNear(tribes.minY / h, 0.146, 0.004, "tribes top fy")
        expectNear(tribes.maxY / h, 0.195, 0.004, "tribes bottom fy")
        expectNear(title.minY / h, 0.109, 0.004, "title top fy")
        expectNear(title.maxY / h, 0.139, 0.004, "title bottom fy")
    }

    @Test("The capture holds the title and tribes with margin, stays in the window and off the medallions",
          arguments: ReferenceFrame.all)
    func capture(frame: ReferenceFrame) {
        let l = frame.layout
        let capture = l.heroPickCapture
        let margin = 0.025 * l.height
        #expect(CGRect(origin: .zero, size: l.size).contains(capture))
        #expect(capture.insetBy(dx: margin, dy: margin).contains(l.heroPickTitle))
        #expect(capture.insetBy(dx: margin, dy: margin).contains(l.heroPickTribes))
        #expect(capture == capture.integral)
        // The trinket-style medallion (kx −0.229, Ø 0.111) and the Deity orb (kx +0.239, Ø 0.115) either side.
        #expect(capture.minX >= l.x(kx: -0.229 + 0.111 / 2))
        #expect(capture.maxX <= l.x(kx: 0.239 - 0.115 / 2))
        // Small: under 5% of the window.
        #expect(capture.width * capture.height < 0.05 * l.width * l.height)
    }

    @Test("The alignment check passes the predicted title and catches a moved or rescaled one",
          arguments: ReferenceFrame.all)
    func alignment(frame: ReferenceFrame) {
        let l = frame.layout
        let h = l.height
        let title = l.heroPickTitle
        let exact = l.alignment(ofTitleFoundAt: title)
        #expect(exact.isAligned && exact.offset < 1e-9 && abs(exact.widthRatio - 1) < 1e-9)
        #expect(l.alignment(ofTitleFoundAt: title.offsetBy(dx: 0.008 * h, dy: -0.008 * h)).isAligned)

        let moved = l.alignment(ofTitleFoundAt: title.offsetBy(dx: 0, dy: 0.02 * h))
        #expect(!moved.isAligned)
        expectNear(CGFloat(moved.dy), 0.02, 1e-9, "dy")
        #expect(!l.alignment(ofTitleFoundAt: title.offsetBy(dx: -0.02 * h, dy: 0)).isAligned)
        let wider = CGRect(x: title.midX - title.width * 0.6, y: title.minY, width: title.width * 1.2, height: title.height)
        #expect(!l.alignment(ofTitleFoundAt: wider).isAligned)
    }

    @Test("The misaligned notice sits under the tribes panel, clear of the board and HS UI",
          arguments: ReferenceFrame.all)
    func warning(frame: ReferenceFrame) {
        let l = frame.layout
        let notice = l.alignmentWarning
        #expect(CGRect(origin: .zero, size: l.size).contains(notice))
        #expect(notice.minY > l.tribesPanel.maxY)
        expectNear(notice.minX, l.hud.minX, 1e-9, "aligned with the HUD")
        for element in HSElement.allCases {
            #expect(!notice.intersects(l.rect(element)), "notice overlaps \(element)")
        }
        for k in 0..<7 {
            #expect(!notice.intersects(l.boardSlot(.player, index: k, of: 7)))
            #expect(!notice.intersects(l.shopCell(k, of: 7)))
        }
        let m = l.constants.heroPickBanner
        let s = l.panelScale
        let text = HUDFitTests.text("⚠︎ Overlay misaligned", m.warningFontSize * s, .semibold)
        #expect(text + 2 * l.constants.tribesPanel.padding.width * s <= notice.width)
        #expect(HUDFitTests.lineHeight(m.warningFontSize * s, .semibold) <= notice.height)
    }
}
