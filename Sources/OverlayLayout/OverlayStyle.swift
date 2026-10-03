import CoreGraphics

/// A colour as plain components, so the palette can live with the layout; the app turns it into
/// a SwiftUI `Color`.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The overlay's custom colours (system colours such as orange and green stay in the views).
public enum OverlayPalette {
    /// Medium-confidence labels and the advisor's caveat line.
    public static let caution = RGB(0.88, 0.75, 0.48)
    /// A triple count.
    public static let triple = RGB(0.95, 0.78, 0.35)
    /// A golden minion's name and outline.
    public static let golden = RGB(1.0, 0.8, 0.3)
    public static let attack = RGB(1.0, 0.85, 0.45)
    public static let health = RGB(1.0, 0.45, 0.42)
    /// A board's likely build.
    public static let likelyBuild = RGB(0.35, 0.85, 0.85)
    /// The advisor card's opaque surface.
    public static let advisorSurface = RGB(0.10, 0.12, 0.13)
    /// A build highlight for a core card and for an add-on.
    public static let buildCore = RGB(0.9, 0.76, 0.45)
    public static let buildAddon = RGB(0.72, 0.68, 0.82)
}

/// The hairline every panel is outlined with. One opacity for all of them: they used to drift
/// between 0.12 and 0.14.
public struct PanelChromeMetrics: Hashable, Sendable {
    public var strokeOpacity: Double = 0.12
    public var strokeWidth: CGFloat = 0.5

    public init() {}
}

/// The opponent panels' type and spacing, in reference points (multiplied by `panelScale`).
public struct OpponentPanelMetrics: Hashable, Sendable {
    // The hovered opponent's panel.
    public var panelSpacing: CGFloat = 8
    public var panelPadding = CGSize(width: 12, height: 10)
    public var cornerRadius: CGFloat = 10
    public var heroNameFontSize: CGFloat = 15
    public var playerNameFontSize: CGFloat = 12
    public var seenFontSize: CGFloat = 11
    public var tileSpacing: CGFloat = 6
    public var placeholderMinWidth: CGFloat = 320
    public var placeholderFontSize: CGFloat = 12
    public var placeholderPadding: CGFloat = 4
    public var statSymbolFontSize: CGFloat = 10
    public var statFontSize: CGFloat = 13
    public var tagFontSize: CGFloat = 9.5
    public var tagPadding = CGSize(width: 5, height: 1.5)
    public var ringCornerRadius: CGFloat = 8
    public var ringLineWidth: CGFloat = 2
    public var ringInset: CGFloat = 2
    public var ringGlowRadius: CGFloat = 5

    // A minion's tile.
    public var tileSize = CGSize(width: 92, height: 88)
    public var tilePadding = CGSize(width: 6, height: 5)
    public var tileCornerRadius: CGFloat = 7
    public var tileRowSpacing: CGFloat = 3
    public var tileTierFontSize: CGFloat = 9.5
    public var tileKeywordFontSize: CGFloat = 8.5
    public var tileNameFontSize: CGFloat = 10.5
    public var tileStatFontSize: CGFloat = 15

    public init() {}
}

/// Where the trinket-pick panel sits, in reference points: as wide as the advisor panel but at
/// least `minWidth`, right-aligned with it, `rise` above its top edge.
public struct TrinketPickMetrics: Hashable, Sendable {
    public var minWidth: CGFloat = 360
    public var rise: CGFloat = 130

    public init() {}
}

/// The build tips panel's type, resolved to actual points. Views must not multiply these by
/// `panelScale` again.
public struct BuildTipsTypography: Hashable, Sendable {
    public let headerFontSize: CGFloat
    public let nameFontSize: CGFloat
    public let bodyFontSize: CGFloat

    public init(panelScale: CGFloat) {
        headerFontSize = max(12, 12 * panelScale)
        nameFontSize = max(14, 14 * panelScale)
        bodyFontSize = max(12, 12 * panelScale)
    }
}

/// How many of Hearthstone's things the layout guides draw (the full board, the gold bar, the hero choices).
public enum LayoutCounts {
    public static let boardMinions = 7
    public static let goldCoins = 10
    public static let heroChoices = 4
}
