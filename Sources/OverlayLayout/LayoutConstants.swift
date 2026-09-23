import CoreGraphics

/// A rect of Hearthstone's own UI, normalized to the client height `h`.
///
/// `kx` is the centre's horizontal offset in units of `h`, measured from `anchor`:
/// from the window's horizontal centre for board elements (the board scales with
/// height and stays centred), or inwards from a window edge for Hearthstone's chrome.
/// `fy` is the centre's distance from the top, and `w`/`h` the size, all in units of `h`.
public struct NormalizedRect: Hashable, Sendable {
    public enum Anchor: Hashable, Sendable {
        /// `kx` is relative to the window's horizontal centre (positive to the right).
        case centre
        /// `kx` is the distance from the window's left edge to the centre.
        case leftEdge
        /// `kx` is the distance from the window's right edge to the centre.
        case rightEdge
    }

    public var kx: CGFloat
    public var fy: CGFloat
    public var w: CGFloat
    public var h: CGFloat
    public var anchor: Anchor

    public init(kx: CGFloat, fy: CGFloat, w: CGFloat, h: CGFloat, anchor: Anchor = .centre) {
        self.kx = kx
        self.fy = fy
        self.w = w
        self.h = h
        self.anchor = anchor
    }
}

/// Hearthstone UI elements with a fixed place in a solo Battlegrounds game.
public enum HSElement: String, CaseIterable, Hashable, Sendable {
    // Tavern controls (recruit phase, top of the board)
    case tavernUpgradeButton, tavernUpgradeCost, bobTierBadge, bobPortrait
    case refreshButton, refreshCost, freezeButton, freezeCost
    // Right side of the board
    case timerPlate
    /// Seasonal (patch 36.x): moves or disappears with season changes.
    case deityOrb
    // The local player's hero cluster
    case heroPortrait, heroArmor, heroHealth, heroPower, heroPowerCost, trinketNear, trinketOuter
    case goldPill
    // The opponent's hero cluster (combat phase)
    case opponentHeroPortrait, opponentHeroArmor, opponentHeroHealth, opponentHeroPower
    case opponentTrinketNear, opponentTrinketOuter
    // Leaderboard
    case leaderboardCrown
    // Hearthstone chrome anchored to the window edges
    case journalButton, settingsButton
}

/// The measured layout constants for one Hearthstone UI version.
///
/// Every value is hand-measured (see `docs/research/overlay-coordinates.md`), so a
/// Battlegrounds patch can move things. When it does, add a new constants value with
/// a new `version` rather than editing an old one, and point `current` at it.
public struct LayoutConstants: Hashable, Sendable {
    /// Which Hearthstone UI these constants were measured against.
    public var version: String

    // Board model
    /// Width of the centred board region, as a multiple of `h` (4:3).
    public var boardAspect: CGFloat

    // Leaderboard (solo)
    public var leaderboardTop: CGFloat
    public var leaderboardSpan: CGFloat
    public var leaderboardSlots: Int
    /// Left edge of the leaderboard tiles, as `kx` (the left edge of the 4:3 region).
    public var leaderboardLeftKx: CGFloat
    /// Centre of slot 0's visible framed portrait, as `kx`. Lower slots lean left by
    /// `leaderboardArtLeanKx` each (the leaderboard is drawn in perspective).
    public var leaderboardArtCentreKx: CGFloat
    public var leaderboardArtLeanKx: CGFloat
    /// The visible frame's centre sits this far (in `h`) from the slot's centre (negative = higher).
    public var leaderboardArtCentreDy: CGFloat
    /// The visible framed portrait, in units of `h`.
    public var leaderboardArtSize: CGSize
    /// The next opponent's portrait pops out to the right by this much and grows to `leaderboardNextArtSize`.
    public var leaderboardNextPopoutKx: CGFloat
    public var leaderboardNextArtSize: CGSize

    // Board rows: the top row is Bob's shop in recruit and the opponent's warband in combat.
    public var rowHeight: CGFloat
    public var playerRowTop: CGFloat
    public var topRowTop: CGFloat
    public var minionWidth: CGFloat
    public var slotPitch: CGFloat
    /// Shop minion cells, including the tier shield (HDT's pinning cells).
    public var shopCellWidth: CGFloat
    public var shopCellHeight: CGFloat
    public var shopCellCentreY: CGFloat

    // Gold coins, left to right
    public var goldCoinFirstKx: CGFloat
    public var goldCoinPitch: CGFloat
    public var goldCoinFy: CGFloat
    public var goldCoinDiameter: CGFloat

    /// Fixed Hearthstone UI rects.
    public var elements: [HSElement: NormalizedRect]

    // Our own panels, authored on a 1080-high reference canvas.
    public var panelScaleRange: ClosedRange<CGFloat>
    /// The status HUD, anchored to the window's top-right corner (in reference points).
    /// `hudSize.width` must fit `hudMetrics`' widest content (checked in the layout tests).
    public var hudSize: CGSize
    public var hudInset: CGFloat
    /// The HUD's type sizes and spacing, which the HUD view draws with.
    public var hudMetrics: HUDMetrics
    /// The opponent panel shown while a leaderboard portrait is hovered: pinned to the top
    /// edge and centred, like the trackers' (in reference points).
    public var opponentPanelSize: CGSize
    /// The next opponent's board preview, under the HUD (in reference points; its width is the HUD's).
    public var nextOpponentPreviewHeight: CGFloat
    /// The combat odds panel, under the HUD while combat runs (in reference points; its width is the HUD's).
    /// Its content (`combatOddsMetrics`) must fit it (checked in the layout tests).
    public var combatOddsPanelHeight: CGFloat = 104
    public var combatOddsMetrics = CombatOddsMetrics()
    /// Space between stacked panels (in reference points).
    public var panelGap: CGFloat
    /// The lobby's tribes panel, under the next opponent preview (its width is the HUD's).
    public var tribesPanel = TribesPanelMetrics()
    /// The hero-pick banner the screen reader captures and checks alignment against.
    public var heroPickBanner = HeroPickBannerMetrics()
    /// The shop highlights and the build tips panel (under the tribes panel, the HUD's width).
    public var buildOverlay = BuildOverlayMetrics()
}

/// The status HUD's type and spacing, in reference points (multiplied by `panelScale`).
///
/// Two rows: the turn and a phase capsule, then the tier, the gold and a hide button.
/// Kept with the layout so the HUD's size can be checked against the widest content it
/// shows without drawing it.
public struct HUDMetrics: Hashable, Sendable {
    public var turnFontSize: CGFloat = 13
    public var phaseFontSize: CGFloat = 9.5
    /// The phase capsule's horizontal and vertical padding.
    public var phasePadding: CGSize = CGSize(width: 5, height: 1.5)
    /// Between the turn and the phase capsule.
    public var titleSpacing: CGFloat = 6
    public var valueFontSize: CGFloat = 12.5
    public var iconSize: CGFloat = 10
    /// Between an icon and its value.
    public var iconSpacing: CGFloat = 4
    /// Between the tier, the gold, the flexible space and the hide button.
    public var itemSpacing: CGFloat = 9
    public var rowSpacing: CGFloat = 5
    /// Inside the HUD's edges.
    public var padding: CGSize = CGSize(width: 9, height: 7)
    public var cornerRadius: CGFloat = 10

    public init() {}
}

/// The combat odds panel's type and spacing, in reference points (multiplied by `panelScale`).
///
/// Rows: win / tie / loss (a small label over each percentage), a bar of the three, the damage
/// dealt and taken (average and range), then a footer with the lethal warning and the
/// number of simulations so far.
public struct CombatOddsMetrics: Hashable, Sendable {
    public var labelFontSize: CGFloat = 9
    public var percentFontSize: CGFloat = 13
    /// Between the win, tie and loss columns.
    public var columnSpacing: CGFloat = 4
    public var barHeight: CGFloat = 4
    public var damageFontSize: CGFloat = 11
    public var warningFontSize: CGFloat = 10.5
    public var footnoteFontSize: CGFloat = 9
    public var rowSpacing: CGFloat = 4
    public var padding: CGSize = CGSize(width: 9, height: 7)
    public var cornerRadius: CGFloat = 10

    public init() {}
}

extension LayoutConstants {
    /// The constants in use.
    public static let current = patch36_6

    /// Patch 36.6.1 (build 251952), measured 2026-09-22 from the player's own captures at
    /// 1710×1073 and cross-checked on 16:9 web captures. Tracker-derived values come from
    /// HSTracker c723bfd / HDT ef8ab6e. Uncertainty is about ±0.004 h unless noted.
    public static let patch36_6 = LayoutConstants(
        version: "36.6.1 (251952) measured 2026-09-22",
        boardAspect: 4.0 / 3.0,
        leaderboardTop: 0.15,
        leaderboardSpan: 0.69,
        leaderboardSlots: 8,
        leaderboardLeftKx: -2.0 / 3.0,
        // §8c: frame centres kx −0.601 (slot 1) … −0.623 (slot 6), so −0.0044 per slot from
        // −0.5966 at slot 0; visible centres 0.0013 h above the model; frame 0.056 × 0.074 h.
        leaderboardArtCentreKx: -0.5966,
        leaderboardArtLeanKx: -0.0044,
        leaderboardArtCentreDy: -0.0013,
        leaderboardArtSize: CGSize(width: 0.056, height: 0.074),
        // Pop-out from the trackers' next-opponent label nudge (+0.023 f ≈ +0.031 h); the popped
        // size from one capture (U4 slot 7: 0.100 × 0.109 h). Estimated: ±0.01 h.
        leaderboardNextPopoutKx: 0.031,
        leaderboardNextArtSize: CGSize(width: 0.100, height: 0.109),
        rowHeight: 0.158,
        playerRowTop: 0.47,
        topRowTop: 0.297,
        minionWidth: 0.12,
        slotPitch: 0.12 + 2 * 0.0029 * 4.0 / 3.0,
        shopCellWidth: 138.0 / 1080,
        shopCellHeight: 190.0 / 1080,
        shopCellCentreY: 395.0 / 1080,
        goldCoinFirstKx: 0.343,
        goldCoinPitch: 0.0282,
        goldCoinFy: 0.927,
        goldCoinDiameter: 0.025,
        elements: [
            .tavernUpgradeButton: .init(kx: -0.157, fy: 0.187, w: 0.088, h: 0.112),
            .tavernUpgradeCost: .init(kx: -0.158, fy: 0.139, w: 0.040, h: 0.040),
            .bobTierBadge: .init(kx: -0.071, fy: 0.209, w: 0.060, h: 0.062),
            .bobPortrait: .init(kx: 0.002, fy: 0.176, w: 0.139, h: 0.153),
            .refreshButton: .init(kx: 0.155, fy: 0.189, w: 0.088, h: 0.116),
            .refreshCost: .init(kx: 0.155, fy: 0.139, w: 0.040, h: 0.040),
            .freezeButton: .init(kx: 0.257, fy: 0.165, w: 0.076, h: 0.112),
            .freezeCost: .init(kx: 0.258, fy: 0.122, w: 0.033, h: 0.033),
            .timerPlate: .init(kx: 0.547, fy: 0.459, w: 0.137, h: 0.060),
            .deityOrb: .init(kx: 0.598, fy: 0.284, w: 0.096, h: 0.094),
            .heroPortrait: .init(kx: 0.000, fy: 0.763, w: 0.148, h: 0.165),
            .heroArmor: .init(kx: 0.066, fy: 0.782, w: 0.052, h: 0.049),
            .heroHealth: .init(kx: 0.068, fy: 0.835, w: 0.046, h: 0.040),
            .heroPower: .init(kx: 0.165, fy: 0.767, w: 0.134, h: 0.134),
            .heroPowerCost: .init(kx: 0.166, fy: 0.706, w: 0.048, h: 0.048),
            .trinketNear: .init(kx: -0.129, fy: 0.810, w: 0.094, h: 0.094),
            .trinketOuter: .init(kx: -0.200, fy: 0.742, w: 0.094, h: 0.094),
            .goldPill: .init(kx: 0.279, fy: 0.924, w: 0.080, h: 0.035),
            .opponentHeroPortrait: .init(kx: 0.000, fy: 0.178, w: 0.134, h: 0.148),
            .opponentHeroArmor: .init(kx: 0.067, fy: 0.193, w: 0.051, h: 0.048),
            .opponentHeroHealth: .init(kx: 0.067, fy: 0.244, w: 0.043, h: 0.036),
            .opponentHeroPower: .init(kx: 0.163, fy: 0.223, w: 0.129, h: 0.129),
            .opponentTrinketNear: .init(kx: -0.116, fy: 0.153, w: 0.092, h: 0.092),
            .opponentTrinketOuter: .init(kx: -0.190, fy: 0.214, w: 0.094, h: 0.094),
            .leaderboardCrown: .init(kx: -0.610, fy: 0.141, w: 0.060, h: 0.043),
            // Centres measured (§8b); sizes estimated from the captures (±0.01 h).
            .journalButton: .init(kx: 0.126, fy: 0.976, w: 0.060, h: 0.045, anchor: .rightEdge),
            .settingsButton: .init(kx: 0.040, fy: 0.976, w: 0.045, h: 0.045, anchor: .rightEdge),
        ],
        panelScaleRange: 0.8...1.3,
        // 148 fits "Turn 30 · Game over" and "★ 6  ◎ 40/40  👁" at every panel scale; 140 cut
        // two-digit gold ("10/…") at 1710×1073.
        hudSize: CGSize(width: 148, height: 60),
        hudInset: 8,
        hudMetrics: HUDMetrics(),
        opponentPanelSize: CGSize(width: 760, height: 160),
        nextOpponentPreviewHeight: 184,
        panelGap: 6
    )
}
