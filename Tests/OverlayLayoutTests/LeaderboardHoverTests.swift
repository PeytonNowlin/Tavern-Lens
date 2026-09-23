import CoreGraphics
import OverlayLayout
import Testing

/// Seam 2: leaderboard hover. Hearthstone's hovered portrait can't be read without game
/// memory, so the overlay hit-tests the cursor against these rects.
@Suite("Leaderboard hover geometry")
struct LeaderboardHoverTests {
    static let slots = 0..<8

    @Test("Each slot's portrait, centre and rank badge hit that slot", arguments: ReferenceFrame.all)
    func everySlotHits(frame: ReferenceFrame) {
        let l = frame.layout
        for i in Self.slots {
            let art = l.leaderboardArt(i)
            #expect(l.leaderboardSlot(at: CGPoint(x: art.midX, y: art.midY)) == i, "art centre \(i)")
            #expect(l.leaderboardSlot(at: CGPoint(x: l.leaderboardSlot(i).midX, y: l.leaderboardSlot(i).midY)) == i,
                    "tile centre \(i)")
            // Rank badges stick out to kx −0.665 (§8c).
            #expect(l.leaderboardSlot(at: CGPoint(x: l.x(kx: -0.664), y: art.midY)) == i, "badge \(i)")
            #expect(l.leaderboardHitRect(i).contains(art), "art inside hit rect \(i)")
        }
    }

    @Test("Hit rects stack without gaps or overlap down the column", arguments: ReferenceFrame.all)
    func contiguousBands(frame: ReferenceFrame) {
        let l = frame.layout
        for i in 1..<8 {
            let above = l.leaderboardHitRect(i - 1), below = l.leaderboardHitRect(i)
            expectNear(below.minY, above.maxY, 1e-9, "band \(i) meets band \(i - 1)")
            #expect(above.intersection(below).height < 1e-9, "bands \(i - 1) and \(i) overlap")
        }
        expectNear(l.leaderboardHitRect(0).minY, 0.15 * l.height, 1e-9, "top")
        expectNear(l.leaderboardHitRect(7).maxY, 0.84 * l.height, 1e-9, "bottom")
        // Every point down the column's left edge lands in exactly one slot.
        let x = l.leaderboardSlot(0).minX + 2
        var hits: [Int] = []
        for y in stride(from: 0.151 * l.height, to: 0.839 * l.height, by: 2) {
            guard let slot = l.leaderboardSlot(at: CGPoint(x: x, y: y)) else {
                Issue.record("gap at y \(y)")
                continue
            }
            hits.append(slot)
        }
        #expect(hits == hits.sorted(), "slots run top to bottom")
        #expect(Set(hits) == Set(Self.slots))
    }

    @Test("Outside the leaderboard nothing is hovered", arguments: ReferenceFrame.all)
    func misses(frame: ReferenceFrame) {
        let l = frame.layout
        let midY = l.leaderboardSlot(3).midY
        let misses: [(String, CGPoint)] = [
            ("above", CGPoint(x: l.leaderboardArt(0).midX, y: 0.149 * l.height)),
            ("below", CGPoint(x: l.leaderboardArt(7).midX, y: 0.841 * l.height)),
            ("left margin", CGPoint(x: l.x(kx: -0.668), y: midY)),
            ("board", CGPoint(x: l.x(kx: -0.50), y: midY)),
            ("centre", CGPoint(x: l.centreX, y: midY)),
            ("HUD", CGPoint(x: l.hud.midX, y: l.hud.midY)),
        ]
        for (what, point) in misses {
            #expect(l.leaderboardSlot(at: point, nextOpponent: 3) == nil, "\(what)")
        }
        // Only as many slots as there are heroes.
        #expect(l.leaderboardSlot(at: CGPoint(x: l.leaderboardArt(6).midX, y: l.leaderboardArt(6).midY), count: 6)
                == nil)
    }

    @Test("The next opponent's popped-out portrait hits its slot, even where it overlaps a neighbour",
          arguments: ReferenceFrame.all)
    func nextOpponentPopOut(frame: ReferenceFrame) {
        let l = frame.layout
        for next in Self.slots {
            let popped = l.leaderboardArt(next, isNextOpponent: true)
            let normal = l.leaderboardArt(next)
            #expect(popped.midX > normal.midX && popped.width > normal.width && popped.height > normal.height)
            #expect(l.leaderboardHitRect(next, isNextOpponent: true).contains(popped))
            // Its right edge only hits when it's the one popped out.
            let rightEdge = CGPoint(x: popped.maxX - 1, y: popped.midY)
            #expect(l.leaderboardSlot(at: rightEdge, nextOpponent: next) == next)
            #expect(l.leaderboardSlot(at: rightEdge) == nil)
            // The popped portrait is taller than a band and wins its overhang into the neighbours.
            if next > 0 {
                let overhang = CGPoint(x: popped.midX, y: popped.minY + 1)
                #expect(l.leaderboardSlot(at: overhang) == next - 1)
                #expect(l.leaderboardSlot(at: overhang, nextOpponent: next) == next)
            }
            // Every other slot's own portrait still hits that slot.
            for i in Self.slots where i != next {
                let art = l.leaderboardArt(i)
                #expect(l.leaderboardSlot(at: CGPoint(x: art.midX, y: art.midY), nextOpponent: next) == i,
                        "slot \(i) with next \(next)")
            }
        }
    }

    /// §8c on the 1710×1073 captures: visible frame centres kx −0.601 (slot 1) … −0.623 (slot 6),
    /// 0.0013 h above the model's slot centres, 0.056 × 0.074 h.
    @Test("1710x1073: portraits match the captures")
    func notchedCaptures() {
        let l = ReferenceFrame.notched.layout
        let tol = MeasuredGeometryTests.tolerance(l)
        let kx = (1...6).map { (l.leaderboardArt($0).midX - l.centreX) / l.height }
        expectNear(kx.first!, -0.601, 0.004, "slot 1 kx")
        expectNear(kx.last!, -0.623, 0.004, "slot 6 kx")
        #expect(kx == kx.sorted(by: >), "leans left going down")
        let visible: [CGFloat] = [0.2781, 0.3637, 0.4498, 0.5359, 0.6227, 0.7096]
        expectNear((1...6).map { l.leaderboardArt($0).midY }, visible.map { $0 * l.height }, tol, "frame y")
        expectNear(l.leaderboardArt(1).width, 0.056 * l.height, tol, "frame width")
        expectNear(l.leaderboardArt(1).height, 0.074 * l.height, tol, "frame height")
        // Measured frame left edges (kx −0.629 at slot 1, −0.660 at slot 6) are inside the hit rects.
        #expect(l.leaderboardHitRect(1).minX <= l.x(kx: -0.629))
        #expect(l.leaderboardHitRect(6).minX <= l.x(kx: -0.660))
        // U4 slot 7, popped out as next opponent: 0.100 × 0.109 h.
        let popped = l.leaderboardArt(7, isNextOpponent: true)
        expectNear(popped.width, 0.100 * l.height, tol, "popped width")
        expectNear(popped.height, 0.109 * l.height, tol, "popped height")
    }

    @Test("Hit rects stay clear of the board, the shop and Hearthstone's UI", arguments: ReferenceFrame.all)
    func clearOfBoard(frame: ReferenceFrame) {
        let l = frame.layout
        let bounds = CGRect(origin: .zero, size: l.size)
        var others = HSElement.allCases.filter { $0 != .leaderboardCrown }.map { ($0.rawValue, l.rect($0)) }
        others += (0..<7).flatMap { k in [("top \(k)", l.boardSlot(.top, index: k, of: 7)),
                                          ("player \(k)", l.boardSlot(.player, index: k, of: 7)),
                                          ("shop \(k)", l.shopCell(k, of: 7))] }
        others += [("hud", l.hud), ("preview", l.nextOpponentPreview), ("panel", l.opponentPanel)]
        for i in Self.slots {
            for rect in [l.leaderboardHitRect(i), l.leaderboardHitRect(i, isNextOpponent: true)] {
                #expect(bounds.contains(rect), "slot \(i) outside")
                for (name, other) in others {
                    #expect(!rect.intersects(other), "slot \(i) overlaps \(name)")
                }
            }
        }
    }
}

@Suite("Opponent panels")
struct OpponentPanelTests {
    @Test("The hover panel is pinned to the top edge, centred, clear of the leaderboard and HUD",
          arguments: ReferenceFrame.all)
    func hoverPanel(frame: ReferenceFrame) {
        let l = frame.layout
        let panel = l.opponentPanel
        #expect(CGRect(origin: .zero, size: l.size).contains(panel))
        expectNear(panel.midX, l.centreX, 1e-9, "centred")
        #expect(panel.minY > 0 && panel.minY < 0.02 * l.height)
        #expect(!panel.intersects(l.hud))
        // It must not cover the portrait being hovered, nor the popped-out next opponent.
        for i in 0..<8 { #expect(!panel.intersects(l.leaderboardHitRect(i, isNextOpponent: true))) }
        // It grows with the panel scale.
        expectNear(panel.width, 760 * l.panelScale, 1e-6, "width")
    }

    @Test("The next opponent preview sits under the HUD in the right margin, clear of the board",
          arguments: ReferenceFrame.all)
    func nextOpponentPreview(frame: ReferenceFrame) {
        let l = frame.layout
        let preview = l.nextOpponentPreview
        #expect(CGRect(origin: .zero, size: l.size).contains(preview))
        #expect(preview.minY > l.hud.maxY)
        expectNear(preview.minX, l.hud.minX, 1e-9, "aligned with the HUD")
        #expect(preview.minX >= l.x(kx: 0.65))
        for element in HSElement.allCases {
            #expect(!preview.intersects(l.rect(element)), "preview overlaps \(element)")
        }
        for k in 0..<7 {
            #expect(!preview.intersects(l.boardSlot(.top, index: k, of: 7)))
            #expect(!preview.intersects(l.shopCell(k, of: 7)))
        }
    }
}
