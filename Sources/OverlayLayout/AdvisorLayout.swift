import CoreGraphics

/// Sizes for the advisor: its ranked list and the rank badges it puts on Hearthstone's cards and buttons.
public struct AdvisorMetrics: Hashable, Sendable {
    // The panel, in reference points (multiplied by `panelScale`): a header strip at the bottom
    // (the top suggestion, or the status, and the collapse toggle) with up to `rows` suggestions
    // listed above it when expanded. Each row: a rank badge, a title line and a reason line.
    public var headerFontSize: CGFloat = 10
    public var titleFontSize: CGFloat = 10
    public var reasonFontSize: CGFloat = 9
    public var rankFontSize: CGFloat = 9
    /// The rank badge in the list.
    public var rankDiameter: CGFloat = 15
    public var rows = 3
    /// Between a title and its reason.
    public var lineSpacing: CGFloat = 1
    /// Between rows, and between the list and the header.
    public var rowSpacing: CGFloat = 5
    /// Between the rank badge and the text.
    public var badgeSpacing: CGFloat = 5
    public var padding = CGSize(width: 9, height: 7)
    public var cornerRadius: CGFloat = 10
    /// The header strip's height.
    public var headerHeight: CGFloat = 28
    /// Lines a reason may wrap to before it's cut.
    public var reasonLines = 2
    /// The whole panel when expanded (its width is the HUD's); the header, `rows` rows and a note
    /// line must fit (checked in the layout tests).
    public var panelHeight: CGFloat = 186

    // In-place highlights, in units of `h` (they sit on Hearthstone's cards, so they scale with the board).
    /// The ring's stroke, drawn inside the target (inset so a build highlight's ring shows around it).
    public var ringLineWidth: CGFloat = 0.003
    public var ringInset: CGFloat = 0.006
    public var ringCornerRadius: CGFloat = 0.010
    /// The rank badge, in the target's top-right corner (clear of a shop card's tier shield, top-left,
    /// and of a build highlight's badge, bottom centre).
    public var badgeDiameter: CGFloat = 0.028

    public init() {}
}

extension OverlayLayout {
    /// What an advisor suggestion can point at.
    public enum AdvisorElement: Hashable, Sendable {
        /// Shop item `index` of `count`.
        case shop(index: Int, count: Int)
        /// The local player's minion `index` of `count`.
        case board(index: Int, count: Int)
        /// Card `index` of `count` in the local player's hand.
        case hand(index: Int, count: Int)
        case levelButton, rollButton, freezeButton
    }

    /// The advisor's ranked list: at the bottom of the right margin, near the gold bar, above
    /// Hearthstone's journal and settings buttons, aligned with the HUD. It's the whole expanded
    /// panel; collapsed, only `advisorHeader` (its bottom strip) shows.
    public var advisorPanel: CGRect {
        let s = panelScale
        let hud = self.hud
        let height = constants.advisor.panelHeight * s
        let chrome = min(rect(.journalButton).minY, rect(.settingsButton).minY)
        return CGRect(x: hud.minX, y: chrome - constants.panelGap * s - height, width: hud.width, height: height)
    }

    /// The panel's header strip: always shown while there's advice, and the one part of the panel
    /// that takes clicks (it collapses and expands the list).
    public var advisorHeader: CGRect {
        let panel = advisorPanel
        let height = constants.advisor.headerHeight * panelScale
        return CGRect(x: panel.minX, y: panel.maxY - height, width: panel.width, height: height)
    }

    /// The Hearthstone element a suggestion highlights.
    public func advisorTarget(_ element: AdvisorElement) -> CGRect {
        switch element {
        case .shop(let index, let count): shopCell(index, of: count)
        case .board(let index, let count): boardSlot(.player, index: index, of: count)
        case .hand(let index, let count): handCard(index, of: count)
        case .levelButton: rect(.tavernUpgradeButton)
        case .rollButton: rect(.refreshButton)
        case .freezeButton: rect(.freezeButton)
        }
    }

    /// The advisor's ring on a target: the target, inset.
    public func advisorRing(_ element: AdvisorElement) -> CGRect {
        let inset = constants.advisor.ringInset * height
        return advisorTarget(element).insetBy(dx: inset, dy: inset)
    }

    /// The rank badge of a target: a circle in the top-right corner of its ring (inset from the
    /// target's edge, since neighbouring shop cells overlap by a hair).
    public func advisorBadge(_ element: AdvisorElement) -> CGRect {
        let ring = advisorRing(element)
        let d = constants.advisor.badgeDiameter * height
        return CGRect(x: ring.maxX - d, y: ring.minY, width: d, height: d)
    }

    /// Card `index` of `count` in the local player's hand, unrotated: the trackers' fan (research
    /// §2b: centre at kx −0.035, 0.95 h; spacing min(0.127 h, 0.36 × the board's width / n)),
    /// without the fan's tilt and drop. Only the advisor's badges use it. Estimated: ±0.02 h.
    public func handCard(_ index: Int, of count: Int) -> CGRect {
        let n = max(count, 1)
        let spacing = min(constants.handCardPitch * height, 0.36 * boardRegion.width / CGFloat(n))
        let midX = x(kx: constants.handCentreKx) - spacing / 2 * CGFloat(n - 1 - 2 * index)
        let size = CGSize(width: constants.handCardSize.width * height, height: constants.handCardSize.height * height)
        return CGRect(x: midX - size.width / 2, y: constants.handCentreFy * height - size.height / 2,
                      width: size.width, height: size.height)
    }
}
