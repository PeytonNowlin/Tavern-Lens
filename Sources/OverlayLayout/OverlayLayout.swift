import CoreGraphics

/// Where things are inside Hearthstone's client area: a pure function of the content size.
///
/// All rects are in points, local to the content area, with the origin at the top-left
/// and y pointing down (a flipped view or a SwiftUI canvas can use them as they are).
/// Everything scales with the content height `h`. Board elements sit at fixed
/// multiples of `h` from the horizontal centre, so a wider window only adds side margin;
/// Hearthstone's chrome and our own panels are anchored to the window edges instead.
public struct OverlayLayout: Hashable, Sendable {
    public let size: CGSize
    public let constants: LayoutConstants

    /// Nil for a degenerate or non-finite size, which must never reach a view.
    public init?(contentSize: CGSize, constants: LayoutConstants = .current) {
        guard contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width >= 1, contentSize.height >= 1
        else { return nil }
        self.size = contentSize
        self.constants = constants
    }

    public var width: CGFloat { size.width }
    public var height: CGFloat { size.height }
    public var centreX: CGFloat { size.width / 2 }

    /// `h / 1080`: the scale of the 1080-high reference canvas.
    public var referenceScale: CGFloat { height / 1080 }

    /// The scale of our own panels: `h / 1080`, clamped so they stay legible and unobtrusive.
    public var panelScale: CGFloat {
        min(max(referenceScale, constants.panelScaleRange.lowerBound), constants.panelScaleRange.upperBound)
    }

    /// The centred 4:3 region the board is drawn in.
    public var boardRegion: CGRect {
        let w = height * constants.boardAspect
        return CGRect(x: centreX - w / 2, y: 0, width: w, height: height)
    }

    /// A board-relative x: `kx` multiples of `h` from the centre.
    public func x(kx: CGFloat) -> CGFloat { centreX + kx * height }

    /// A fixed Hearthstone UI element.
    public func rect(_ element: HSElement) -> CGRect {
        guard let r = constants.elements[element] else { return .null }
        return rect(r)
    }

    /// A normalized rect resolved against this content size.
    public func rect(_ r: NormalizedRect) -> CGRect {
        let midX: CGFloat = switch r.anchor {
        case .centre: x(kx: r.kx)
        case .leftEdge: r.kx * height
        case .rightEdge: width - r.kx * height
        }
        return centred(midX: midX, midY: r.fy * height, width: r.w * height, height: r.h * height)
    }

    /// Solo leaderboard tile `index` (0 = first place, top). Slot index is
    /// `PLAYER_LEADERBOARD_PLACE - 1`. The tile is square and contains the portrait art.
    public func leaderboardSlot(_ index: Int) -> CGRect {
        let tile = constants.leaderboardSpan / CGFloat(constants.leaderboardSlots) * height
        return CGRect(
            x: x(kx: constants.leaderboardLeftKx),
            y: constants.leaderboardTop * height + CGFloat(index) * tile,
            width: tile, height: tile
        )
    }

    public enum BoardRow: Hashable, Sendable {
        /// Bob's shop in recruit, the opponent's warband in combat.
        case top
        /// The local player's warband.
        case player
    }

    /// The hover band of minion `index` (0 = leftmost) in a row of `count` minions.
    /// Hearthstone centres the occupied slots on the window's centre.
    public func boardSlot(_ row: BoardRow, index: Int, of count: Int) -> CGRect {
        let top = row == .top ? constants.topRowTop : constants.playerRowTop
        let midX = x(kx: slotOffset(index, of: count))
        return CGRect(
            x: midX - constants.minionWidth * height / 2, y: top * height,
            width: constants.minionWidth * height, height: constants.rowHeight * height
        )
    }

    /// The whole card of shop item `index` of `count`, including its tier shield.
    public func shopCell(_ index: Int, of count: Int) -> CGRect {
        centred(
            midX: x(kx: slotOffset(index, of: count)), midY: constants.shopCellCentreY * height,
            width: constants.shopCellWidth * height, height: constants.shopCellHeight * height
        )
    }

    /// Gold coin `index` (0-based, left to right) next to the gold pill.
    public func goldCoin(_ index: Int) -> CGRect {
        let d = constants.goldCoinDiameter * height
        return centred(
            midX: x(kx: constants.goldCoinFirstKx + CGFloat(index) * constants.goldCoinPitch),
            midY: constants.goldCoinFy * height, width: d, height: d
        )
    }

    /// Our status HUD (turn, phase, tier, gold): top-right corner of the window, in the
    /// margin right of the board.
    public var hud: CGRect {
        let s = panelScale
        let size = CGSize(width: constants.hudSize.width * s, height: constants.hudSize.height * s)
        let inset = constants.hudInset * s
        return CGRect(x: width - inset - size.width, y: inset, width: size.width, height: size.height)
    }

    private func slotOffset(_ index: Int, of count: Int) -> CGFloat {
        (CGFloat(index) - CGFloat(count - 1) / 2) * constants.slotPitch
    }

    private func centred(midX: CGFloat, midY: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }
}
