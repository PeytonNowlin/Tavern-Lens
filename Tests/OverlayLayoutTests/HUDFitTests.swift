import AppKit
import OverlayLayout
import Testing

/// The status HUD is a fixed rect (`OverlayLayout.hud`), so its content must fit it at
/// every panel scale, or SwiftUI truncates the gold ("1/…"). These tests measure the
/// widest text and symbols the HUD shows with the system font at the HUD's sizes
/// (`HUDMetrics`) and lay them out the way `StatusHUD` does: two rows, each an HStack
/// with `itemSpacing` between items, the flexible space included.
@Suite("Status HUD fits its content")
struct HUDFitTests {
    /// The widest values each slot can show. Digits are monospaced, so two-digit gold is the widest.
    /// The title row: the turn and its phase capsule (none at the hero pick).
    static let titles: [(turn: String, phase: String?)] = [
        ("Turn 30", "Recruit"), ("Turn 30", "Combat"), ("Turn 30", "Game over"), ("Hero pick", nil),
    ]
    static let tiers = ["6", "–"]
    static let golds = ["40/40", "–"]

    @Test("Widest content fits the HUD's width and height", arguments: ReferenceFrame.all)
    func fits(frame: ReferenceFrame) {
        let l = frame.layout
        let needed = Self.contentSize(l.constants.hudMetrics, scale: l.panelScale)
        #expect(needed.width <= l.hud.width, "HUD needs \(needed.width) pt, has \(l.hud.width) at \(frame.name)")
        #expect(needed.height <= l.hud.height, "HUD needs \(needed.height) pt tall, has \(l.hud.height)")
    }

    @Test("Also fits at the ends of the panel-scale range")
    func fitsAtScaleLimits() {
        for height in [600.0, 3000.0] {
            let l = OverlayLayout(contentSize: CGSize(width: height * 16 / 9, height: height))!
            let needed = Self.contentSize(l.constants.hudMetrics, scale: l.panelScale)
            #expect(needed.width <= l.hud.width, "scale \(l.panelScale): needs \(needed.width), has \(l.hud.width)")
        }
    }

    @Test("At 1710×1073 two-digit gold fits (it was cut to \"10/…\")")
    func twoDigitGoldAtNotched() {
        let l = ReferenceFrame.notched.layout
        let m = l.constants.hudMetrics
        let s = l.panelScale
        let gold = Self.symbol("circle.circle.fill", m.iconSize * s) + m.iconSpacing * s
            + Self.text("10/10", m.valueFontSize * s, .medium)
        let tier = Self.symbol("star.fill", m.iconSize * s) + m.iconSpacing * s + Self.text("6", m.valueFontSize * s, .medium)
        let row = 2 * m.padding.width * s + tier + gold + 3 * m.itemSpacing * s
            + Self.symbol("eye.slash", m.iconSize * s, .medium)
        #expect(row <= l.hud.width)
    }

    static func contentSize(_ m: HUDMetrics, scale s: CGFloat) -> CGSize {
        let titleRow = titles.map { title in
            text(title.turn, m.turnFontSize * s, .semibold) + (title.phase.map {
                m.titleSpacing * s + text($0, m.phaseFontSize * s, .semibold) + 2 * m.phasePadding.width * s
            } ?? 0)
        }.max()!

        let value = m.valueFontSize * s
        let icon = m.iconSize * s
        let tier = symbol("star.fill", icon) + m.iconSpacing * s + tiers.map { text($0, value, .medium) }.max()!
        let gold = symbol("circle.circle.fill", icon) + m.iconSpacing * s + golds.map { text($0, value, .medium) }.max()!
        let hide = symbol("eye.slash", icon, .medium)
        // Tier, gold, the flexible space and the button: three gaps.
        let valueRow = tier + gold + hide + 3 * m.itemSpacing * s

        let titleHeight = max(lineHeight(m.turnFontSize * s, .semibold),
                              lineHeight(m.phaseFontSize * s, .semibold) + 2 * m.phasePadding.height * s)
        let height = titleHeight + m.rowSpacing * s + lineHeight(value, .medium) + 2 * m.padding.height * s
        return CGSize(width: max(titleRow, valueRow) + 2 * m.padding.width * s, height: height)
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    static func text(_ string: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font(size, weight)]).size().width)
    }

    static func lineHeight(_ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
        let f = font(size, weight)
        return ceil(f.ascender - f.descender + f.leading)
    }

    static func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CGFloat {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
        return ceil(image?.size.width ?? size * 1.6)
    }
}
