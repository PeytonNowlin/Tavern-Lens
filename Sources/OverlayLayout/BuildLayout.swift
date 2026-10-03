import CoreGraphics

/// Sizes for the build overlays: the shop highlights and the build tips panel.
public struct BuildOverlayMetrics: Hashable, Sendable {
    // Shop highlights, in units of `h` (they sit on Hearthstone's cards, so they scale with the board).
    /// The ring's stroke, drawn inside the shop cell.
    public var highlightLineWidth: CGFloat = 0.004
    public var highlightCornerRadius: CGFloat = 0.012
    /// The "Core" / "Add-on" badge, centred on the cell's bottom edge.
    public var badgeSize = CGSize(width: 0.066, height: 0.021)

    /// The "Core fit" / "Fits" badge is never smaller than this (in points) or its text smaller
    /// than `badgeMinFontSize`; the text is `badgeFontShare` of the badge's height.
    public var badgeMinSize = CGSize(width: 58, height: 18)
    public var badgeMinFontSize: CGFloat = 12
    public var badgeFontShare: CGFloat = 0.62
    /// The ring is drawn this much thinner than `highlightLineWidth`, at this opacity, dashed in
    /// `highlightDash` (in units of `h`) for an add-on.
    public var highlightLineShare: CGFloat = 0.65
    public var highlightOpacity: Double = 0.55
    public var highlightDash: [CGFloat] = [0.012, 0.006]

    // The tips panel, in reference points (multiplied by `panelScale`); its type is
    // `BuildTipsTypography`. A "Current fit" header, then one build card (two in the comfortable
    // density, when they fit): the build's name, an optional "Experimental fit" line, and its
    // owned and missing core cards.
    /// Between a card's parts.
    public var partSpacing: CGFloat = 3
    /// Between two build cards.
    public var cardSpacing: CGFloat = 7
    public var padding = CGSize(width: 9, height: 7)
    public var cornerRadius: CGFloat = 10
    /// The panel's height (its width is the HUD's); a full card must fit it (checked in the layout tests).
    public var tipsPanelHeight: CGFloat = 250

    public init() {}
}

extension OverlayLayout {
    /// Where a shop card's highlight goes: the whole card of shop item `index` of `count`,
    /// the same cell the tier shield and portrait sit in.
    public func shopHighlight(_ index: Int, of count: Int) -> CGRect {
        shopCell(index, of: count)
    }

    /// The small "Core" / "Add-on" badge of a highlighted shop card: centred on the bottom
    /// edge of its cell, between the attack and health gems.
    public func shopHighlightBadge(_ index: Int, of count: Int) -> CGRect {
        let cell = shopCell(index, of: count)
        let size = constants.buildOverlay.badgeSize
        return CGRect(
            x: cell.midX - size.width * height / 2, y: cell.maxY - size.height * height / 2,
            width: size.width * height, height: size.height * height
        )
    }

    /// The detected builds' tips: in the right margin under the tribes panel, aligned with the HUD.
    /// It starts under the "misaligned" notice's place, which also sits under the tribes panel and
    /// stays up all game once the hero-pick check fails, so the two never cover each other.
    public var buildTipsPanel: CGRect {
        let s = panelScale
        let above = alignmentWarning
        return CGRect(x: above.minX, y: above.maxY + constants.panelGap * s,
                      width: above.width, height: constants.buildOverlay.tipsPanelHeight * s)
    }
}
