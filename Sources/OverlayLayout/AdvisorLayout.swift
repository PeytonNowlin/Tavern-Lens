import CoreGraphics

/// Both presets use the same reserved overlay space. Compact shows less secondary content;
/// it does not reduce the minimum readable font size.
public enum OverlayDensity: String, CaseIterable, Codable, Sendable {
    case compact, comfortable
}

/// The advisor's new typography, resolved to actual points rather than reference points.
/// Views must not multiply these sizes by `panelScale` again.
public struct AdvisorTypography: Hashable, Sendable {
    public let titleFontSize: CGFloat
    public let bodyFontSize: CGFloat
    public let labelFontSize: CGFloat
    public let headerFontSize: CGFloat
    public let reasonLines: Int
    public let contextLines: Int

    public init(density: OverlayDensity, panelScale: CGFloat) {
        let comfortable = density == .comfortable
        titleFontSize = max(16, (comfortable ? 18 : 16) * panelScale)
        bodyFontSize = max(12, (comfortable ? 13 : 12) * panelScale)
        labelFontSize = max(12, 12 * panelScale)
        headerFontSize = max(12, 12 * panelScale)
        reasonLines = comfortable ? 2 : 1
        contextLines = comfortable ? 2 : 1
    }
}

/// Sizes for the advisor: its ranked list and the rank badges it puts on Hearthstone's cards and buttons.
public struct AdvisorMetrics: Hashable, Sendable {
    // The panel, in reference points (multiplied by `panelScale`): a header strip at the bottom
    // (the top suggestion, or the status, and the collapse toggle) with up to `rows` suggestions
    // listed above it when expanded. Each row: a rank badge, a title line and a reason line.
    public var headerFontSize: CGFloat = 14
    public var titleFontSize: CGFloat = 14
    public var reasonFontSize: CGFloat = 12.5
    public var rankFontSize: CGFloat = 12
    /// The rank badge in the list.
    public var rankDiameter: CGFloat = 20
    public var rows = 3
    /// Between a title and its reason.
    public var lineSpacing: CGFloat = 1
    /// Between rows, and between the list and the header.
    public var rowSpacing: CGFloat = 6
    /// Between the rank badge and the text.
    public var badgeSpacing: CGFloat = 7
    public var padding = CGSize(width: 11, height: 8)
    public var cornerRadius: CGFloat = 10
    /// The header strip's height.
    public var headerHeight: CGFloat = 34
    /// Lines a reason may wrap to before it's cut.
    public var reasonLines = 2
    /// Lines the note under the list may wrap to (a status and the stand-in caveat).
    public var noteLines = 3
    /// The whole panel when expanded, right-aligned with the HUD but wider (it reaches left into
    /// the free space beside the board, clear of the shop and the minions); the header, `rows`
    /// rows and a note line must fit (checked in the layout tests).
    public var panelSize = CGSize(width: 250, height: 262)

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
    /// Hearthstone's journal and settings buttons and the gold coins' row (it reaches over the
    /// last coins), right-aligned with the HUD. It's the whole expanded panel; collapsed, only
    /// `advisorHeader` (its bottom strip) shows.
    public var advisorPanel: CGRect {
        let s = panelScale
        let hud = self.hud
        let width = constants.advisor.panelSize.width * s, height = constants.advisor.panelSize.height * s
        let bottom = min(rect(.journalButton).minY, rect(.settingsButton).minY, goldCoin(0).minY)
        return CGRect(x: hud.maxX - width, y: bottom - constants.panelGap * s - height, width: width, height: height)
    }

    /// The panel's stable bottom strip: a Details control and a separate collapse control.
    public var advisorHeader: CGRect {
        let panel = advisorPanel
        let height = constants.advisor.headerHeight * panelScale
        return CGRect(x: panel.minX, y: panel.maxY - height, width: panel.width, height: height)
    }

    /// The trailing square of the expanded panel's bottom strip. When collapsed, the whole header expands it.
    public var advisorCollapseButton: CGRect {
        let header = advisorHeader
        return CGRect(x: header.maxX - header.height, y: header.minY,
                      width: header.height, height: header.height)
    }

    /// The rest of the bottom strip opens or closes details, without also collapsing the advisor.
    public var advisorDetailsButton: CGRect {
        let header = advisorHeader
        return CGRect(x: header.minX, y: header.minY,
                      width: header.width - advisorCollapseButton.width, height: header.height)
    }

    /// Detailed strategy and alternatives replace the build tips in their existing reserved space.
    /// Keeping this width avoids reaching into the seven-minion board or shop.
    public var advisorDetailsPanel: CGRect { buildTipsPanel }

    /// Only visible controls and the expanded details scroll surface receive pointer events.
    /// The recommendation card itself remains click-through, including while details are open.
    public func advisorInteractiveRegions(collapsed: Bool, detailsExpanded: Bool) -> [CGRect] {
        guard !collapsed else { return [advisorHeader] }
        var regions = [advisorDetailsButton, advisorCollapseButton]
        if detailsExpanded { regions.append(advisorDetailsPanel) }
        return regions
    }

    public func advisorTypography(density: OverlayDensity) -> AdvisorTypography {
        AdvisorTypography(density: density, panelScale: panelScale)
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

    /// A readable "Next" pill for the current action. It grows left from the existing badge
    /// anchor, stays inside its target, and keeps a 22-point minimum height for 12-point text.
    public func advisorNextBadge(_ element: AdvisorElement) -> CGRect {
        let ring = advisorRing(element)
        let d = constants.advisor.badgeDiameter * height
        let width = min(ring.width, max(38, d * 1.6))
        let height = min(ring.height, max(22, d))
        let top: CGFloat
        if case .shop = element {
            // The opponent hero power's lower edge reaches into the shop's top strip.
            // Keep every shop pill at the same height and clear of that reserved region,
            // including while the game transitions between recruit and combat.
            top = min(ring.maxY - height, max(ring.minY, rect(.opponentHeroPower).maxY + 2 * panelScale))
        } else {
            top = ring.minY
        }
        return CGRect(x: ring.maxX - width, y: top, width: width, height: height)
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
