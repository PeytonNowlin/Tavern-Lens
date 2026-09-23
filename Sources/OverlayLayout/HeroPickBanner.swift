import CoreGraphics

/// The hero-pick banner ("Choose a Hero", with the lobby's tribes under it), where the
/// screen reader captures and what it checks the layout against.
///
/// Measured on the player's own hero-pick capture (patch 36.6.1, U3 in
/// `docs/research/overlay-coordinates.md` §8d). The title's text box and the tribes' text
/// block are the glyph bounds, which is what text recognition reports.
public struct HeroPickBannerMetrics: Hashable, Sendable {
    /// "Choose a Hero": the text box, not the plate.
    public var title = NormalizedRect(kx: 0.003, fy: 0.124, w: 0.257, h: 0.030)
    /// The lobby's tribes: up to 3 centred lines under the title (fy ≈ 0.152, 0.169, 0.187).
    public var tribesText = NormalizedRect(kx: 0.002, fy: 0.171, w: 0.175, h: 0.049)
    /// What is captured: the title and the tribes with about 0.03 h to spare on every side,
    /// so a banner a patch moved is still found (and measured), but short of the medallions
    /// either side of the plate.
    public var capture = NormalizedRect(kx: 0, fy: 0.1525, w: 0.32, h: 0.145)
    /// How far (in `h`) the title's centre may sit from where it's predicted before the
    /// layout counts as moved. The measurements are good to about ±0.004 h.
    public var alignmentTolerance: CGFloat = 0.012
    /// How far the title's size may differ from the predicted size (as a fraction) before
    /// the layout counts as rescaled.
    public var sizeTolerance: CGFloat = 0.12
    /// The overlay's "misaligned" notice, under the tribes panel (in reference points; its width is the HUD's).
    public var warningHeight: CGFloat = 22
    public var warningFontSize: CGFloat = 10

    public init() {}
}

/// Where the banner's title was found against where the layout predicts it.
public struct BannerAlignment: Hashable, Sendable, Codable {
    /// Found minus predicted centre, in units of `h` (positive: right, down).
    public var dx: Double
    public var dy: Double
    /// Found over predicted width.
    public var widthRatio: Double
    /// Within the tolerances: the layout still matches the game.
    public var isAligned: Bool

    public init(dx: Double, dy: Double, widthRatio: Double, isAligned: Bool) {
        self.dx = dx
        self.dy = dy
        self.widthRatio = widthRatio
        self.isAligned = isAligned
    }

    /// The larger of the two offsets, in units of `h`.
    public var offset: Double { max(abs(dx), abs(dy)) }
}

extension OverlayLayout {
    /// Where "Choose a Hero" is drawn at the hero pick.
    public var heroPickTitle: CGRect { rect(constants.heroPickBanner.title) }

    /// Where the lobby's tribes are listed at the hero pick.
    public var heroPickTribes: CGRect { rect(constants.heroPickBanner.tribesText) }

    /// The strip of the window the screen reader captures at the hero pick: the banner's
    /// title and tribes with some margin, kept inside the content, in whole points.
    public var heroPickCapture: CGRect {
        rect(constants.heroPickBanner.capture).integral.intersection(CGRect(origin: .zero, size: size))
    }

    /// Checks the layout against where the banner's title was actually found
    /// (content-local points, as `heroPickTitle`).
    public func alignment(ofTitleFoundAt found: CGRect) -> BannerAlignment {
        let predicted = heroPickTitle
        let m = constants.heroPickBanner
        let dx = (found.midX - predicted.midX) / height
        let dy = (found.midY - predicted.midY) / height
        let ratio = predicted.width > 0 ? found.width / predicted.width : 0
        let aligned = abs(dx) <= m.alignmentTolerance && abs(dy) <= m.alignmentTolerance
            && abs(ratio - 1) <= m.sizeTolerance
        return BannerAlignment(dx: Double(dx), dy: Double(dy), widthRatio: Double(ratio), isAligned: aligned)
    }

    /// The overlay's "misaligned" notice: under the tribes panel, in the right margin.
    public var alignmentWarning: CGRect {
        let s = panelScale
        let tribes = tribesPanel
        return CGRect(x: tribes.minX, y: tribes.maxY + constants.panelGap * s,
                      width: tribes.width, height: constants.heroPickBanner.warningHeight * s)
    }
}
