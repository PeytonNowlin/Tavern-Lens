import CoreGraphics
import OverlayLayout
import Testing

/// Seam 2: Hearthstone's window frame and mode in, element rects out, checked against the
/// reference frames in docs/research/overlay-coordinates.md (§4 worked numbers, §8 measured).

/// A reference frame: the window as CGWindowList/AX report it, and how it's shown.
struct ReferenceFrame: CustomTestStringConvertible, Sendable {
    var name: String
    var window: CGRect
    var mode: WindowMode

    var content: CGRect { WindowGeometry.contentFrame(windowFrame: window, mode: mode) }
    var layout: OverlayLayout { OverlayLayout(contentSize: content.size)! }
    var testDescription: String { name }

    /// This Mac: native fullscreen below the notch strip of a 1710×1107 screen.
    static let notched = ReferenceFrame(
        name: "1710x1073 notched fullscreen", window: CGRect(x: 0, y: 34, width: 1710, height: 1073), mode: .fullscreen)
    static let fullHD = ReferenceFrame(
        name: "1920x1080", window: CGRect(x: 0, y: 0, width: 1920, height: 1080), mode: .fullscreen)
    /// A 1440×900 window with a 28-pt title bar: 1440×872 of content.
    static let windowed = ReferenceFrame(
        name: "1440x900 windowed", window: CGRect(x: 120, y: 60, width: 1440, height: 900),
        mode: .windowed(titleBarHeight: 28))
    static let ultrawide = ReferenceFrame(
        name: "2560x1080 (21:9)", window: CGRect(x: 0, y: 0, width: 2560, height: 1080), mode: .fullscreen)

    static let all: [ReferenceFrame] = [.notched, .fullHD, .windowed, .ultrawide]
}

/// Tracker-derived worked numbers are rounded to 0.1–1 pt in the research table.
let workedTolerance: CGFloat = 1.0

func expectNear(
    _ actual: CGFloat, _ expected: CGFloat, _ tolerance: CGFloat, _ what: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(abs(actual - expected) <= tolerance, "\(what): \(actual) vs \(expected) ± \(tolerance)",
            sourceLocation: sourceLocation)
}

func expectNear(
    _ actual: [CGFloat], _ expected: [CGFloat], _ tolerance: CGFloat, _ what: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(actual.count == expected.count, "\(what): count", sourceLocation: sourceLocation)
    for (a, e) in zip(actual, expected) { expectNear(a, e, tolerance, what, sourceLocation: sourceLocation) }
}

@Suite("Content frame")
struct ContentFrameTests {
    @Test("Notched fullscreen uses the AX frame below the notch as it is")
    func notchedFullscreen() {
        #expect(ReferenceFrame.notched.content == CGRect(x: 0, y: 34, width: 1710, height: 1073))
    }

    @Test("Windowed drops the title bar from the top and keeps the bottom")
    func windowedDropsTitleBar() {
        let content = ReferenceFrame.windowed.content
        #expect(content == CGRect(x: 120, y: 88, width: 1440, height: 872))
        #expect(content.maxY == ReferenceFrame.windowed.window.maxY)
    }

    @Test("Mode inference without Accessibility")
    func inferMode() {
        let notchedScreen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        #expect(WindowGeometry.inferMode(
            windowFrame: ReferenceFrame.notched.window, screenFrame: notchedScreen, screenTopInset: 34,
            titleBarHeight: 28) == .fullscreen)
        // The notched screen's full frame would shift every y by 3%; a window that
        // fills it is still fullscreen (a non-notched display).
        #expect(WindowGeometry.inferMode(
            windowFrame: notchedScreen, screenFrame: notchedScreen, screenTopInset: 34, titleBarHeight: 28)
            == .fullscreen)
        #expect(WindowGeometry.inferMode(
            windowFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1080),
            screenFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1080), screenTopInset: 0, titleBarHeight: 28)
            == .fullscreen)
        #expect(WindowGeometry.inferMode(
            windowFrame: CGRect(x: 120, y: 60, width: 1440, height: 900), screenFrame: notchedScreen,
            screenTopInset: 34, titleBarHeight: 28) == .windowed(titleBarHeight: 28))
        // A window as wide as the screen but below the menu bar is a maximized window, not fullscreen.
        #expect(WindowGeometry.inferMode(
            windowFrame: CGRect(x: 0, y: 40, width: 1710, height: 1067), screenFrame: notchedScreen,
            screenTopInset: 34, titleBarHeight: 28) == .windowed(titleBarHeight: 28))
    }

    @Test("AppKit placement flips against the primary screen")
    func appKitFlip() {
        #expect(WindowGeometry.appKitRect(fromTopLeft: ReferenceFrame.notched.content, primaryScreenHeight: 1107)
            == CGRect(x: 0, y: 0, width: 1710, height: 1073))
        #expect(WindowGeometry.appKitRect(fromTopLeft: ReferenceFrame.windowed.content, primaryScreenHeight: 1107)
            == CGRect(x: 120, y: 147, width: 1440, height: 872))
        // The cursor at AppKit (200, 1000) is 73 pt below the content's top edge (y = 34).
        #expect(WindowGeometry.localPoint(
            fromAppKit: CGPoint(x: 200, y: 1000), contentFrame: ReferenceFrame.notched.content,
            primaryScreenHeight: 1107) == CGPoint(x: 200, y: 73))
    }

    @Test("Degenerate sizes give no layout", arguments: [
        CGSize(width: 0, height: 0), CGSize(width: 1710, height: 0), CGSize(width: -5, height: 900),
        CGSize(width: CGFloat.nan, height: 900), CGSize(width: 1710, height: CGFloat.infinity),
    ])
    func degenerate(size: CGSize) {
        #expect(OverlayLayout(contentSize: size) == nil)
    }
}

@Suite("Tracker-derived geometry (§4 worked numbers)")
struct WorkedNumberTests {
    @Test func notchedFullscreen() {
        let l = ReferenceFrame.notched.layout
        expectNear(l.boardRegion.minX, 139.7, workedTolerance, "4:3 left")
        expectNear(l.boardRegion.maxX, 1570.3, workedTolerance, "4:3 right")
        expectNear(l.leaderboardSlot(0).minX, 139.7, workedTolerance, "leaderboard x")
        expectNear(l.leaderboardSlot(0).maxX, 232.2, workedTolerance, "leaderboard right")
        expectNear((0..<8).map { l.leaderboardSlot($0).minY }, [161, 253, 346, 439, 531, 624, 716, 809],
                   workedTolerance, "solo slot tops")
        expectNear(l.leaderboardSlot(7).maxY, 901, workedTolerance, "leaderboard bottom")
        expectNear(l.boardSlot(.player, index: 1, of: 7).midX - l.boardSlot(.player, index: 0, of: 7).midX,
                   137.1, 0.1, "slot pitch")
        expectNear(l.boardSlot(.player, index: 0, of: 7).width, 128.8, 0.1, "ellipse width")
        expectNear(l.boardSlot(.player, index: 0, of: 7).height, 169.5, 0.1, "row height")
        expectNear(l.boardSlot(.player, index: 0, of: 1).midY, 589.1, workedTolerance, "player row centre")
        expectNear(l.boardSlot(.top, index: 0, of: 1).midY, 403.4, workedTolerance, "top row centre")
        expectNear(l.shopCell(0, of: 3).midY, 392.4, workedTolerance, "shop cell centre")
        expectNear((0..<7).map { l.boardSlot(.player, index: $0, of: 7).midX },
                   [444, 581, 718, 855, 992, 1129, 1266], workedTolerance, "7 minions")
        expectNear((0..<3).map { l.boardSlot(.top, index: $0, of: 3).midX }, [718, 855, 992], workedTolerance,
                   "3 minions")
        expectNear((0..<4).map { l.boardSlot(.player, index: $0, of: 4).midX },
                   [649.4, 786.5, 923.5, 1060.6], workedTolerance, "4 minions")
        expectNear(l.referenceScale, 0.9935, 0.0001, "scale")
    }

    @Test func fullHD() {
        let l = ReferenceFrame.fullHD.layout
        expectNear(l.boardRegion.minX, 240, workedTolerance, "4:3 left")
        expectNear(l.boardRegion.maxX, 1680, workedTolerance, "4:3 right")
        expectNear(l.leaderboardSlot(0).maxX, 333.1, workedTolerance, "leaderboard right")
        expectNear((0..<8).map { l.leaderboardSlot($0).minY }, [162, 255, 348, 441, 535, 628, 721, 814],
                   workedTolerance, "solo slot tops")
        expectNear(l.leaderboardSlot(3).minY, 441.5, 0.1, "slot 3 spot check")
        expectNear(l.leaderboardSlot(7).maxY, 907, workedTolerance, "leaderboard bottom")
        expectNear(l.boardSlot(.player, index: 0, of: 1).midY, 592.9, workedTolerance, "player row centre")
        expectNear(l.boardSlot(.top, index: 0, of: 1).midY, 406.1, workedTolerance, "top row centre")
        expectNear(l.shopCell(0, of: 1).midY, 395.0, workedTolerance, "shop cell centre")
        expectNear((0..<7).map { l.boardSlot(.player, index: $0, of: 7).midX },
                   [546, 684, 822, 960, 1098, 1236, 1374], workedTolerance, "7 minions")
        expectNear((0..<3).map { l.boardSlot(.top, index: $0, of: 3).midX }, [822, 960, 1098], workedTolerance,
                   "3 minions")
        expectNear(l.shopCell(0, of: 1).width, 138, 0.01, "shop cell @1080")
        expectNear(l.shopCell(0, of: 1).height, 190, 0.01, "shop cell @1080")
    }

    @Test func windowed() {
        let l = ReferenceFrame.windowed.layout
        #expect(l.size == CGSize(width: 1440, height: 872))
        expectNear(l.boardRegion.minX, 138.7, workedTolerance, "4:3 left")
        expectNear(l.boardRegion.maxX, 1301.3, workedTolerance, "4:3 right")
        expectNear(l.leaderboardSlot(0).maxX, 213.9, workedTolerance, "leaderboard right")
        expectNear((0..<8).map { l.leaderboardSlot($0).minY }, [131, 206, 281, 356, 432, 507, 582, 657],
                   workedTolerance, "solo slot tops")
        expectNear(l.boardSlot(.player, index: 1, of: 7).midX - l.boardSlot(.player, index: 0, of: 7).midX,
                   111.4, 0.1, "slot pitch")
        expectNear(l.boardSlot(.player, index: 0, of: 7).width, 104.6, 0.1, "ellipse width")
        expectNear(l.boardSlot(.player, index: 0, of: 7).height, 137.8, 0.1, "row height")
        expectNear(l.boardSlot(.player, index: 0, of: 1).midY, 478.7, workedTolerance, "player row centre")
        expectNear(l.boardSlot(.top, index: 0, of: 1).midY, 327.9, workedTolerance, "top row centre")
        expectNear(l.shopCell(0, of: 1).midY, 318.9, workedTolerance, "shop cell centre")
        expectNear(l.boardSlot(.player, index: 0, of: 7).midX, 386, workedTolerance, "7 minions, first")
        expectNear(l.boardSlot(.player, index: 6, of: 7).midX, 1054, workedTolerance, "7 minions, last")
        expectNear((0..<3).map { l.boardSlot(.top, index: $0, of: 3).midX }, [609, 720, 831], workedTolerance,
                   "3 minions")
        expectNear(l.referenceScale, 0.8074, 0.0001, "scale")
    }

    @Test func ultrawide() {
        let l = ReferenceFrame.ultrawide.layout
        expectNear(l.boardRegion.minX, 560, workedTolerance, "4:3 left")
        expectNear(l.boardRegion.maxX, 2000, workedTolerance, "4:3 right")
        expectNear(l.leaderboardSlot(0).maxX, 653.1, workedTolerance, "leaderboard right")
        expectNear((0..<8).map { l.leaderboardSlot($0).minY }, [162, 255, 348, 441, 535, 628, 721, 814],
                   workedTolerance, "solo slot tops (= 1080p)")
        expectNear(l.boardSlot(.player, index: 0, of: 7).midX, 866, workedTolerance, "7 minions, first")
        expectNear(l.boardSlot(.player, index: 6, of: 7).midX, 1694, workedTolerance, "7 minions, last")
        expectNear((0..<3).map { l.boardSlot(.top, index: $0, of: 3).midX }, [1142, 1280, 1418], workedTolerance,
                   "3 minions")
    }
}

@Suite("Screenshot-measured geometry (§8)")
struct MeasuredGeometryTests {
    /// §8a: typical measurement uncertainty is ±0.002 h (circle fits) to ±0.004 h (edges by eye).
    static func tolerance(_ l: OverlayLayout) -> CGFloat { 0.004 * l.height }

    /// Points on the 1710×1073 frame, from the U4/U5 captures (2000-px frame ÷ 1.1696).
    @Test("1710x1073: shop, leaderboard and board rows match the captures")
    func notchedCaptures() {
        let l = ReferenceFrame.notched.layout
        let tol = Self.tolerance(l)
        // §8c: 4 shop items at 758, 922, 1083, 1241 px.
        expectNear((0..<4).map { l.shopCell($0, of: 4).midX }, [758, 922, 1083, 1241].map { $0 / 1.1696 }, tol,
                   "shop x")
        // §8c: visible leaderboard frame centres, slots 1–6, sit 0.0013 h above the model.
        let visible: [CGFloat] = [0.2781, 0.3637, 0.4498, 0.5359, 0.6227, 0.7096]
        expectNear((1...6).map { l.leaderboardSlot($0).midY }, visible.map { $0 * l.height }, tol, "leaderboard y")
        // §8c: shop minion oval centre 0.372 h lies inside both top-row rects.
        #expect(l.boardSlot(.top, index: 0, of: 1).contains(CGPoint(x: l.centreX, y: 0.372 * l.height)))
        #expect(l.shopCell(0, of: 1).contains(CGPoint(x: l.centreX, y: 0.372 * l.height)))
        // The whole shop card incl. tier shield spans 0.280–0.446 h.
        expectNear(l.shopCell(0, of: 1).minY, 0.280 * l.height, tol, "shop card top")
        expectNear(l.shopCell(0, of: 1).maxY, 0.446 * l.height, 2 * tol, "shop card bottom")
        // §8c: player minion oval 0.476–0.610 h fits in the 0.158 h hover band.
        let band = l.boardSlot(.player, index: 0, of: 1)
        #expect(band.minY <= 0.476 * l.height && band.maxY >= 0.610 * l.height)
    }

    /// Centres in points on 1710×1073 (§8d; kx relative to cx = 855).
    @Test("1710x1073: Hearthstone's own UI", arguments: [
        (HSElement.tavernUpgradeButton, CGPoint(x: 686.5, y: 200.7)),
        (.refreshButton, CGPoint(x: 1021.3, y: 202.8)),
        (.freezeButton, CGPoint(x: 1130.8, y: 177.0)),
        (.bobTierBadge, CGPoint(x: 778.8, y: 224.3)),
        (.timerPlate, CGPoint(x: 1441.9, y: 492.5)),
        (.heroPortrait, CGPoint(x: 855.0, y: 818.7)),
        (.heroHealth, CGPoint(x: 928.0, y: 896.0)),
        (.heroPower, CGPoint(x: 1032.0, y: 823.0)),
        (.trinketNear, CGPoint(x: 716.6, y: 869.1)),
        (.goldPill, CGPoint(x: 1154.4, y: 991.5)),
        (.opponentHeroPortrait, CGPoint(x: 855.0, y: 191.0)),
        (.leaderboardCrown, CGPoint(x: 200.5, y: 151.3)),
        // Window-edge chrome: 0.040 h / 0.126 h from the right edge.
        (.settingsButton, CGPoint(x: 1667.1, y: 1047.2)),
        (.journalButton, CGPoint(x: 1574.8, y: 1047.2)),
    ])
    func notchedElements(element: HSElement, centre: CGPoint) {
        let l = ReferenceFrame.notched.layout
        let r = l.rect(element)
        expectNear(r.midX, centre.x, Self.tolerance(l), "\(element) x")
        expectNear(r.midY, centre.y, Self.tolerance(l), "\(element) y")
    }

    @Test("Gold coins run right of the pill")
    func goldCoins() {
        let l = ReferenceFrame.notched.layout
        let pill = l.rect(.goldPill)
        #expect(l.goldCoin(0).minX > pill.maxX)
        expectNear(l.goldCoin(2).midX - l.goldCoin(0).midX, 2 * 0.0282 * l.height, 0.01, "pitch")
        expectNear(l.goldCoin(0).midY, pill.midY, Self.tolerance(l), "same row")
    }

    /// §8b: the 16:9 captures register to the 1710×1073 frame with height-only scaling about cx,
    /// so every board element keeps its (kx, fy) on every frame.
    @Test("Board elements scale with height about the centre", arguments: ReferenceFrame.all)
    func resolutionIndependent(frame: ReferenceFrame) {
        let reference = ReferenceFrame.notched.layout
        let l = frame.layout
        for element in HSElement.allCases where l.constants.elements[element]?.anchor == .centre {
            let a = reference.rect(element), b = l.rect(element)
            expectNear((b.midX - l.centreX) / l.height, (a.midX - reference.centreX) / reference.height, 1e-9,
                       "\(element) kx")
            expectNear(b.midY / l.height, a.midY / reference.height, 1e-9, "\(element) fy")
            expectNear(b.height / l.height, a.height / reference.height, 1e-9, "\(element) size")
        }
    }

    @Test("21:9 keeps the board where 1080p has it, shifted to the wider centre; chrome follows the edge")
    func ultrawideAnchoring() {
        let hd = ReferenceFrame.fullHD.layout, wide = ReferenceFrame.ultrawide.layout
        for element in HSElement.allCases {
            let a = hd.rect(element), b = wide.rect(element)
            switch hd.constants.elements[element]!.anchor {
            case .centre: expectNear(b.midX, a.midX + 320, 1e-6, "\(element)")
            case .rightEdge: expectNear(wide.width - b.midX, hd.width - a.midX, 1e-6, "\(element)")
            case .leftEdge: expectNear(b.midX, a.midX, 1e-6, "\(element)")
            }
            expectNear(b.midY, a.midY, 1e-6, "\(element) y")
        }
    }
}

@Suite("Our panels")
struct PanelTests {
    @Test("Every rect lies inside the content", arguments: ReferenceFrame.all)
    func insideContent(frame: ReferenceFrame) {
        let l = frame.layout
        let bounds = CGRect(origin: .zero, size: l.size)
        var rects = HSElement.allCases.map { ($0.rawValue, l.rect($0)) }
        rects += (0..<8).map { ("leaderboard \($0)", l.leaderboardSlot($0)) }
        rects += (0..<7).flatMap { k in [("top \(k)", l.boardSlot(.top, index: k, of: 7)),
                                         ("player \(k)", l.boardSlot(.player, index: k, of: 7)),
                                         ("shop \(k)", l.shopCell(k, of: 7))] }
        rects += (0..<10).map { ("coin \($0)", l.goldCoin($0)) }
        rects.append(("hud", l.hud))
        for (name, r) in rects {
            #expect(bounds.contains(r), "\(name) \(r) outside \(bounds)")
        }
    }

    @Test("The HUD sits in the top-right margin, clear of the board and Hearthstone's UI",
          arguments: ReferenceFrame.all)
    func hudClear(frame: ReferenceFrame) {
        let l = frame.layout
        let hud = l.hud
        // Right of all board art: the frame edge (≈ +0.64 h) and the Deity orb (to +0.647 h).
        #expect(hud.minX >= l.x(kx: 0.65), "hud left \(hud.minX) vs \(l.x(kx: 0.65))")
        #expect(hud.minY > 0 && hud.maxX < l.width)
        for element in HSElement.allCases {
            #expect(!hud.intersects(l.rect(element)), "hud overlaps \(element)")
        }
        for i in 0..<8 { #expect(!hud.intersects(l.leaderboardSlot(i))) }
        #expect(hud.maxY < l.rect(.timerPlate).minY)
    }

    @Test("Our right-margin panels and the hover panel never cover each other", arguments: ReferenceFrame.all)
    func panelsDontOverlap(frame: ReferenceFrame) {
        let l = frame.layout
        let bounds = CGRect(origin: .zero, size: l.size)
        let panels: [(String, CGRect)] = [
            ("hud", l.hud), ("next opponent preview", l.nextOpponentPreview), ("combat odds", l.combatOddsPanel),
            ("tribes", l.tribesPanel), ("misaligned notice", l.alignmentWarning), ("build tips", l.buildTipsPanel),
            ("opponent hover panel", l.opponentPanel), ("advisor", l.advisorPanel),
        ]
        // The combat odds take the preview's place: the preview shows in recruit only, the odds in combat only.
        let exclusive: Set<[String]> = [["next opponent preview", "combat odds"]]
        for (name, rect) in panels {
            #expect(bounds.contains(rect), "\(name) \(rect) outside \(bounds)")
        }
        for i in panels.indices {
            for j in panels.indices where j > i {
                let (a, ra) = panels[i], (b, rb) = panels[j]
                if exclusive.contains([a, b]) { continue }
                #expect(!ra.intersects(rb), "\(a) \(ra) overlaps \(b) \(rb)")
            }
        }
        // Top to bottom in the right margin, in this order.
        #expect(l.combatOddsPanel.maxY < l.tribesPanel.minY)
        #expect(l.tribesPanel.maxY < l.alignmentWarning.minY && l.alignmentWarning.maxY < l.buildTipsPanel.minY)
        #expect(l.buildTipsPanel.maxY < l.advisorPanel.minY)
    }

    @Test("Panel scale follows height, clamped to 0.8…1.3")
    func panelScale() {
        #expect(ReferenceFrame.fullHD.layout.panelScale == 1)
        expectNear(ReferenceFrame.notched.layout.panelScale, 1073.0 / 1080, 1e-9, "notched")
        expectNear(ReferenceFrame.windowed.layout.panelScale, 872.0 / 1080, 1e-9, "windowed")
        #expect(OverlayLayout(contentSize: CGSize(width: 1000, height: 600))!.panelScale == 0.8)
        #expect(OverlayLayout(contentSize: CGSize(width: 3840, height: 2160))!.panelScale == 1.3)
        // The HUD grows with the panel scale.
        let hud = ReferenceFrame.windowed.layout.hud
        expectNear(hud.width, 148 * 872.0 / 1080, 1e-6, "hud width")
    }

    @Test("Constants are versioned")
    func versioned() {
        #expect(LayoutConstants.current.version.hasPrefix("36.6.1"))
        #expect(Set(LayoutConstants.current.elements.keys) == Set(HSElement.allCases))
    }
}
