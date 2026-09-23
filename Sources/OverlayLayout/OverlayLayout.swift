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

    /// The visible framed portrait of leaderboard slot `index`. It leans left down the column,
    /// and the next opponent's portrait pops out to the right and grows.
    public func leaderboardArt(_ index: Int, isNextOpponent: Bool = false) -> CGRect {
        let c = constants
        let slot = leaderboardSlot(index)
        var kx = c.leaderboardArtCentreKx + CGFloat(index) * c.leaderboardArtLeanKx
        if isNextOpponent { kx += c.leaderboardNextPopoutKx }
        let size = isNextOpponent ? c.leaderboardNextArtSize : c.leaderboardArtSize
        return centred(
            midX: x(kx: kx), midY: slot.midY + c.leaderboardArtCentreDy * height,
            width: size.width * height, height: size.height * height
        )
    }

    /// Where the cursor counts as hovering leaderboard slot `index`: the slot's band of the
    /// column, from the tile's left edge (rank badges reach it) to the right of its portrait.
    /// The next opponent's popped-out portrait is covered whole, overlapping its neighbours'
    /// bands; `leaderboardSlot(at:)` gives it precedence there, since it's drawn on top.
    public func leaderboardHitRect(_ index: Int, isNextOpponent: Bool = false) -> CGRect {
        let slot = leaderboardSlot(index)
        let art = leaderboardArt(index, isNextOpponent: isNextOpponent)
        let band = CGRect(x: slot.minX, y: slot.minY, width: max(slot.maxX, art.maxX) - slot.minX, height: slot.height)
        return isNextOpponent ? band.union(art) : band
    }

    /// The leaderboard slot under `point` (content-local, top-left origin), or nil.
    /// - Parameters:
    ///   - count: how many heroes the leaderboard shows (8 in solo).
    ///   - nextOpponent: the next opponent's slot index, whose portrait is popped out.
    public func leaderboardSlot(at point: CGPoint, count: Int? = nil, nextOpponent: Int? = nil) -> Int? {
        let slots = 0..<min(count ?? constants.leaderboardSlots, constants.leaderboardSlots)
        if let next = nextOpponent, slots.contains(next),
           leaderboardHitRect(next, isNextOpponent: true).contains(point) {
            return next
        }
        // The next opponent's rect contains its own band, so it's done.
        return slots.first { $0 != nextOpponent && leaderboardHitRect($0).contains(point) }
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

    /// The opponent panel shown while a leaderboard portrait is hovered: pinned to the top
    /// edge and centred on the board, where the trackers put theirs. It shows only on hover
    /// and never takes clicks, so covering Bob's controls meanwhile is harmless.
    public var opponentPanel: CGRect {
        let s = panelScale
        let size = CGSize(width: constants.opponentPanelSize.width * s, height: constants.opponentPanelSize.height * s)
        return CGRect(x: centreX - size.width / 2, y: constants.hudInset * s, width: size.width, height: size.height)
    }

    /// The next opponent's compact board preview: under the HUD, in the right margin, with the
    /// live odds section (`nextOpponentOdds`) at its foot.
    public var nextOpponentPreview: CGRect {
        let s = panelScale
        let hud = self.hud
        return CGRect(x: hud.minX, y: hud.maxY + constants.panelGap * s, width: hud.width,
                      height: (constants.nextOpponentPreviewHeight + constants.oddsPreview.height) * s)
    }

    /// The live odds section: the bottom of the next opponent preview.
    public var nextOpponentOdds: CGRect {
        let preview = nextOpponentPreview
        let height = constants.oddsPreview.height * panelScale
        return CGRect(x: preview.minX, y: preview.maxY - height, width: preview.width, height: height)
    }

    /// The lobby's tribes: a small panel in the right margin, under the next opponent
    /// preview's place (which is empty outside recruit), so the two never move each other.
    public var tribesPanel: CGRect {
        let s = panelScale
        let preview = nextOpponentPreview
        return CGRect(x: preview.minX, y: preview.maxY + constants.panelGap * s,
                      width: preview.width, height: constants.tribesPanel.height * s)
    }

    /// The combat odds panel: under the HUD in the right margin, where the next opponent's preview
    /// sits during recruit (the two never show together).
    public var combatOddsPanel: CGRect {
        let s = panelScale
        let hud = self.hud
        return CGRect(x: hud.minX, y: hud.maxY + constants.panelGap * s,
                      width: hud.width, height: constants.combatOddsPanelHeight * s)
    }

    private func slotOffset(_ index: Int, of count: Int) -> CGFloat {
        (CGFloat(index) - CGFloat(count - 1) / 2) * constants.slotPitch
    }

    private func centred(midX: CGFloat, midY: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }
}
