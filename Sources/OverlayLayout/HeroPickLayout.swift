import CoreGraphics

/// The hero-pick screen: where Hearthstone draws the offered heroes (measured, §8 of
/// docs/research/overlay-coordinates.md) and where our stats plates go.
///
/// Board-relative like the board: `kx` from the window's centre and `fy` from the top, in
/// units of the content height. The plates sit in the free band between the "Choose a Hero"
/// banner and the portraits' arched tops, one per hero and centred on it, so they never
/// cover the portrait, its name plate, the reroll buttons or Confirm. The placement chart
/// drops down from a hovered plate over the top of its own portrait.
public struct HeroPickMetrics: Hashable, Sendable {
    // Hearthstone's hero-pick screen (patch 36.6.1, measured on the player's capture U3).
    /// Portrait centres (arch apex x) for a 4-hero offer, left to right.
    public var portraitCentreKx: [CGFloat] = [-0.461, -0.150, 0.166, 0.481]
    /// The pitch between portraits, for offers of other sizes (unverified for 2–3 heroes).
    public var portraitPitch: CGFloat = 0.314
    /// The arch top and name-plate bottom of each portrait, and its width.
    public var portraitTop: CGFloat = 0.298
    public var portraitBottom: CGFloat = 0.622
    public var portraitWidth: CGFloat = 0.235
    public var bannerPlate = NormalizedRect(kx: 0.010, fy: 0.152, w: 0.343, h: 0.123)
    public var trinketMedallion = NormalizedRect(kx: -0.229, fy: 0.149, w: 0.111, h: 0.110)
    public var deityOrb = NormalizedRect(kx: 0.239, fy: 0.149, w: 0.113, h: 0.116)
    /// The crest under the banner, between the middle two heroes (size estimated).
    public var crest = NormalizedRect(kx: 0.005, fy: 0.218, w: 0.050, h: 0.050)
    /// Reroll buttons, under the unlocked heroes only.
    public var rerollPlateFy: CGFloat = 0.676
    public var rerollPlateSize = CGSize(width: 0.171, height: 0.063)
    public var confirm = NormalizedRect(kx: 0.004, fy: 0.792, w: 0.131, h: 0.069)

    // Our plates, in units of h.
    public var plateWidth: CGFloat = 0.200
    public var plateTop: CGFloat = 0.224
    public var plateHeight: CGFloat = 0.066
    /// The placement chart, under the hovered plate.
    public var chartHeight: CGFloat = 0.175
    public var chartGap: CGFloat = 0.004

    // Type and spacing in points at a 1080-high window (multiplied by `h / 1080`).
    public var tierFontSize: CGFloat = 15
    public var tierBadgeSize: CGFloat = 24
    public var averageFontSize: CGFloat = 20
    public var captionFontSize: CGFloat = 10
    public var detailFontSize: CGFloat = 11
    public var itemSpacing: CGFloat = 6
    public var rowSpacing: CGFloat = 2
    public var padding = CGSize(width: 9, height: 6)
    public var cornerRadius: CGFloat = 8
    public var chartFontSize: CGFloat = 9.5
    public var chartTitleFontSize: CGFloat = 10.5

    public init() {}

    /// Patch 36.6.1 (build 251952), measured 2026-09-22.
    public static let patch36_6 = HeroPickMetrics()
}

extension LayoutConstants {
    /// The hero-pick screen's measurements and our plates.
    public var heroPick: HeroPickMetrics { .patch36_6 }
}

extension OverlayLayout {
    /// The centre `kx` of hero `index` of an offer of `count` (0 = leftmost). Four heroes use
    /// the measured centres; other counts keep the pitch, centred on the same point.
    public func heroPickCentreKx(_ index: Int, of count: Int) -> CGFloat {
        let m = constants.heroPick
        if count == m.portraitCentreKx.count, m.portraitCentreKx.indices.contains(index) {
            return m.portraitCentreKx[index]
        }
        let middle = m.portraitCentreKx.reduce(0, +) / CGFloat(max(m.portraitCentreKx.count, 1))
        return middle + (CGFloat(index) - CGFloat(count - 1) / 2) * m.portraitPitch
    }

    /// Hero `index`'s portrait, from its arch top to the bottom of its name plate.
    public func heroPickPortrait(_ index: Int, of count: Int) -> CGRect {
        let m = constants.heroPick
        let midX = x(kx: heroPickCentreKx(index, of: count))
        return CGRect(
            x: midX - m.portraitWidth * height / 2, y: m.portraitTop * height,
            width: m.portraitWidth * height, height: (m.portraitBottom - m.portraitTop) * height
        )
    }

    /// Our stats plate for hero `index`: centred over its portrait, under the banner.
    public func heroPickPlate(_ index: Int, of count: Int) -> CGRect {
        let m = constants.heroPick
        let midX = x(kx: heroPickCentreKx(index, of: count))
        return CGRect(
            x: midX - m.plateWidth * height / 2, y: m.plateTop * height,
            width: m.plateWidth * height, height: m.plateHeight * height
        )
    }

    /// The placement chart shown while plate `index` is hovered: just under the plate, over
    /// the top of the same hero's portrait.
    public func heroPickChart(_ index: Int, of count: Int) -> CGRect {
        let m = constants.heroPick
        let plate = heroPickPlate(index, of: count)
        return CGRect(x: plate.minX, y: plate.maxY + m.chartGap * height, width: plate.width, height: m.chartHeight * height)
    }

    /// The plate under `point` (content-local, top-left origin), or nil.
    public func heroPickPlate(at point: CGPoint, count: Int) -> Int? {
        (0..<max(count, 0)).first { heroPickPlate($0, of: count).contains(point) }
    }

    /// The hero-pick screen's own UI the plates must stay clear of.
    public var heroPickScreenElements: [CGRect] {
        let m = constants.heroPick
        var rects = [rect(m.bannerPlate), rect(m.trinketMedallion), rect(m.deityOrb), rect(m.crest), rect(m.confirm)]
        for i in 0..<m.portraitCentreKx.count {
            let midX = x(kx: heroPickCentreKx(i, of: m.portraitCentreKx.count))
            rects.append(CGRect(
                x: midX - m.rerollPlateSize.width * height / 2,
                y: (m.rerollPlateFy - m.rerollPlateSize.height / 2) * height,
                width: m.rerollPlateSize.width * height, height: m.rerollPlateSize.height * height
            ))
        }
        return rects
    }
}
