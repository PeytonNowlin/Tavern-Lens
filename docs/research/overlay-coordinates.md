# Battlegrounds overlay coordinates (where things are inside the Hearthstone window)

Research date: 2026-09-22. Goal: resolution-independent positions of Battlegrounds UI elements inside the Hearthstone (HS) client area, for a native macOS overlay.

Sources (pinned):
- **HSTracker** (MIT), `HearthSim/HSTracker` @ `c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4`. Written below as `HST:<path>#L<n>`, which expands to `https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/<path>#L<n>`.
- **Hearthstone-Deck-Tracker** (HDT, All Rights Reserved, used only as a reference: values are described here, not copied), `HearthSim/Hearthstone-Deck-Tracker` @ `ef8ab6e8380a647d757eec203d310395d6b97ae0`. Written below as `HDT:<path>#L<n>`, which expands to `https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/<path>#L<n>`.
- **Firestone** (Overwolf), `Zero-to-Heroes/firestone` @ `0a30f066eb77a417637d95cec86444456f607ba1`. Used only to cross-check the leaderboard. I found no license file at the clone root, so treat it as reference-only. Written below as `FS:<path>#L<n>`, which expands to `https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/<path>#L<n>`.

Sections 1–5 were first written from tracker code alone. **§8 adds values measured from screenshots**: four captures of the user's own game on this Mac (patch 36.6.1, 1710x1073 content) plus public 16:9 web screenshots. §8 fills the HS-UI elements no tracker knows (hero, hero power, trinkets, gold, tavern buttons and more) and checks the tracker-derived leaderboard and board-row values. Rows filled from screenshots are marked **[screenshot]**. Current HSTracker is largely a line-by-line port of HDT's overlay, with comments naming the HDT member each value comes from. So in most rows below, "HSTracker and HDT agree" means one lineage, not two independent measurements. Firestone is the only independent source, and it covers only the leaderboard.

---

## 1. Coordinate model

Define these over the **HS client (content) area**, in **points**, with the origin at the **top-left** and y pointing **down**:

```
w, h   = content width, height (pt)
s      = h / 1080                 // reference-height scale ("1080p units")
cx     = w / 2
boardW = h * 4/3                  // the centred 4:3 "board" region
ratio  = (4/3) / (w/h)            // HDT ScreenRatio / HSTracker SizeHelper.screenRatio
X(f)   = w*ratio*f + w*(1-ratio)/2   // getScaledXPos: f = 0..1 across the centred 4:3 region
       = cx + (f - 0.5) * (4/3) * h  // same thing, rearranged
y      = fy * h
```

- **Everything scales with height alone.** `X(f)` depends only on `cx` and `h`. A wider window just moves the whole layout outward from the centre, so x positions are best stored as **centre-relative offsets in units of h**: `x = cx + kx*h`, with `kx = (f-0.5)*4/3`. Sources: `HDT:Utility/Helper.cs#L429`, `HST:HSTracker/Core/SizeHelper.swift#L209-L211`, `#L247-L261`, `HDT:Windows/OverlayWindow.xaml.cs#L495`.
- There are two element families:
  1. **Game-geometry elements** (board rows, hand, leaderboard labels, hit ellipses). Both trackers compute these straight from `w`/`h` fractions in real window pixels, with no extra scale. See `HST:HSTracker/UIs/Overlay/Board/BoardOverlayView.swift#L65-L90`.
  2. **Tracker panels** (Bob's Buddy, opponent-info drop-down, top bar, pickers, pinning markers). These are authored on a **1080-high reference canvas** of virtual width `w/s`. HSTracker scales that canvas by `s = h/1080` with no clamp (`HST:HSTracker/UIs/Overlay/Root/RootOverlayView.swift#L153-L161`, `#L526-L528`). HDT scales panels such as Bob's Buddy, the opponent info and the top bar by **`AutoScaling = clamp(h/1080, 0.8, 1.3)`** (`HDT:Windows/OverlayWindow.Update.cs#L742-L744`). The pickers and pinning use plain `h/1080` (`#L797-L819`). At h = 1073 the two scales are the same (0.9935).
- **Which frame to use**: HSTracker takes the AX window frame. When the window is *not* fullscreen it subtracts a title-bar height, computed once as `NSWindow.frame.height - contentRect.height` for a `.titled` window. The bottom stays fixed and the top drops by that amount (`HST:HSTracker/Core/SizeHelper.swift#L123-L148`, `HST:HSTracker/AppDelegate.swift#L492-L502`). Fullscreen on this Mac: AX frame (0,34) 1710x1073, the area below the notch strip (see `macos-overlay-and-platform.md` §0).
- **Retina**: all of this is in points. Never multiply by `backingScaleFactor`.
- **AppKit placement**: these are top-left coordinates. To position an `NSWindow`/`NSPanel` over a rect `(x, y, rw, rh)`, use `appKitY = contentFrameAppKit.maxY - y - rh`. Inside a flipped NSView or a SwiftUI canvas the numbers can be used as they are.

---

## 2. Element table

Fractions: `fy` is a fraction of h. `X(f)` is a fraction across the centred 4:3 region. "@1080" means points on the 1080-high reference canvas, multiplied by `s`. Slot indices are 0-based unless a line says otherwise.

### 2a. Leaderboard (left edge of the board)

| Element | Coord system | Value / formula | HSTracker | HDT | Notes |
|---|---|---|---|---|---|
| Leaderboard top | fy | `0.15 h` | `HST:HSTracker/UIs/Battlegrounds/BattlegroundsOpponentDeadForView.swift#L62` | `HDT:Windows/OverlayWindow.MouseOverDetection.cs#L48` | Firestone: `top: 15vh` (`FS:libs/legacy/feature-shell/src/lib/js/components/overlays/_full-screen-overlays.component.scss#L34-L39`), which agrees. |
| Solo tile (8 slots) | fy | tile height = tile width = `0.69 h / 8 = 0.08625 h`. Slot i top = `0.15h + i*0.08625h`. Leaderboard bottom ≈ `0.84 h` | `…DeadForView.swift#L63-L64`, `#L143-L149` | `HDT:Windows/OverlayWindow.xaml.cs#L509`, `#L513`; `MouseOverDetection.cs#L137-L147` | Firestone: 74vh column, each item 11.8% ≈ `0.0873 h` (`FS:libs/legacy/feature-shell/src/lib/js/components/battlegrounds/overlay/bgs-leaderboard-empty-card.component.scss#L2`), which agrees to within 1%. |
| Duos tile (4 teams x 2) | fy | tile = `0.69h*(1-0.137)/8 = 0.07443 h`, inter-team gap = `0.69h*0.137/3 = 0.03151 h`. Slot i top = `0.15h + i*tile + floor(i/2)*gap` | `…DeadForView.swift#L60`, `#L65-L69`, `#L144-L147` | `HDT:Windows/OverlayWindow.xaml.cs#L510-L512`; `MouseOverDetection.cs#L120-L133` | Three gaps between four teams. The team block spans the same 0.69 h as solo. |
| Tile left x | X(f) | `X(0) + ~0` = left edge of the 4:3 region → `cx - 0.6667 h`. The dead-for label nudge is `X((4-i)*0.0017)`, so the leaderboard leans slightly (perspective). The next opponent's portrait sticks out, and its label gets `+0.023` (solo) / `+0.015` (duos) in f ≈ `+0.031 h` / `+0.020 h` | `…DeadForView.swift#L55-L57`, `#L152-L163` | `MouseOverDetection.cs#L42-L46`, `#L108-L115`, `#L126-L131` | Firestone: left = game-area left + 3vh, with a game area 1.4 h wide → `cx - 0.67 h`, which agrees. |
| Dead-for label per-slot pixel nudges | px (unscaled) | Slots 0..7 Margin (x,y): tile text (2,-13) (2,-14) (1,-15) (0.5,-15) (0,-13) (-2,-14) (-1.5,-13) (-2.5,-11). "Turns" text (2.5,0) (2.5,-2) (2,-3) (0.5,-3) (0.5,-1) (-1.5,-2) (-1,-1) (-2,1). Font 15 px, not scaled | `…DeadForView.swift#L30-L49` | `HDT:Windows/OverlayWindow.xaml#L383-L398` | Cosmetic only. |
| Which slot is which player | tags | Slot index = `PLAYER_LEADERBOARD_PLACE - 1` (Duos: team slot = place-1, tiles `2j`, `2j+1`). The next opponent's slot comes from the next opponent hero's `PLAYER_LEADERBOARD_PLACE`. Dead-for counts fill from the **bottom** up (index = heroCount-1, going down), because dead players hold the last places | `HST:HSTracker/Logging/OpponentDeadForTracker.swift#L37-L45`; `HST:HSTracker/UIs/Battlegrounds/BattlegroundsOpponentInfoViewModel.swift#L98-L108` | `HDT:OpponentDeadForTracker.cs#L39-L42` | HDT guards `place >= 0 && place < 8`. HSTracker uses `> 0 && <= 8`. Firestone also sorts players by `leaderboardPlace` (`FS:libs/legacy/feature-shell/src/lib/js/components/overlays/bgs-leaderboard-widget-wrapper.component.ts#L108-L114`). |
| **Which slot is hovered** | memory, not geometry | Both trackers read the hovered leaderboard entity id from **game memory** (HearthMirror `GetBattlegroundsLeaderboardHoveredEntityId`, polled every 16 ms). They do **not** hit-test the tiles | `HST:HSTracker/HearthWatcher/BattlegroundsLeaderboardWatcher.swift#L19-L36` | `HDT:Hearthstone/Watchers.cs#L533-L534` | HDT still declares `_leaderboardIcons` rectangles and positions them at `top = 0.15h + i*tile`, `left = X(0.001*(7-i))`, but the list is never filled (legacy). **We have no memory reading, so we must hit-test tiles ourselves** with the rects above. |
| Per-opponent hover panel (last-seen board, tier/triples) | @1080, top-centre | Not placed next to the portrait. It is a drop-down **pinned to the top edge, horizontally centred**: `left = w/2 - panelW*scale/2`, `top = 0`. Boxes are 150 @1080 tall. The board box has min width 740 and holds 110-wide minions overlapping by 10. The tiers box is 2 rows of 3 tiles. An optional deity box sits on the left and an optional (HSTracker-only) quest box on the right | `HST:HSTracker/UIs/Battlegrounds/BattlegroundsOpponentInfoView.swift#L22-L37`, `#L55-L73`; `RootOverlayView.swift#L318-L322` | `HDT:Windows/OverlayWindow.xaml.cs#L287-L295`; `Controls/Overlay/Battlegrounds/BattlegroundsOpponentInfo.xaml#L16`, `#L33`, `#L66` | While the panel is up, Bob's Buddy and the top bar are hidden (HSTracker) or faded to 0.3 (HDT). Any leaderboard hover fades the panels over mid-screen to 0.3, because HS draws that player's board there (`BattlegroundsOpponentInfoViewModel.swift#L47-L55`, `#L156-L184`). |

### 2b. Board rows, shop, hand (hover and hit geometry)

| Element | Coord system | Value / formula | HSTracker | HDT | Notes |
|---|---|---|---|---|---|
| Row height | fy | `BoardHeight = 0.158 h` | `HST:HSTracker/UIs/Overlay/Board/BoardOverlayView.swift#L73` | `HDT:Windows/OverlayWindow.MouseOverDetection.cs#L38` | |
| Minion hit ellipse width | h | `MinionWidth = w*0.63/7*ratio = 0.12 h` | `BoardOverlayView.swift#L75-L77` | `MouseOverDetection.cs#L39` | |
| Gap either side | h | `w*ratio*0.0029 = 0.003867 h` (Mercenaries: 0.01). **Slot pitch = 0.12 h + 2*0.003867 h = 0.12773 h** | `BoardOverlayView.swift#L81-L83` | `MouseOverDetection.cs#L57-L63` | |
| Horizontal centring by count | h | The row is an HStack of the n *occupied* slots, centred on `cx`. Slot k of n: `centreX = cx + (k - (n-1)/2) * 0.12773 h` (odd n puts the middle minion at cx; even n puts cx between two minions) | `BoardOverlayView.swift#L111-L131` | `HDT:Windows/OverlayWindow.xaml#L303-L317` (full-width grid, centred ItemsControl) | Same rule for Bob's shop (3–7). Hearthstone centres its shop the same way (see the pinning row). |
| Player's board row (recruit and combat) | fy | top = `0.5h - 0.03h = 0.47 h`, centre y = `0.549 h` | `BoardOverlayView.swift#L141-L152` | `HDT:Windows/OverlayWindow.Update.cs#L532-L533` | |
| Opponent row = **Bob's shop** in recruit, **opponent's warband in combat** | fy | top = `0.5h - 0.158h - 0.045h = 0.297 h`, centre y = `0.376 h` | `BoardOverlayView.swift#L133-L139` | `Update.cs#L529-L530` | Which entities sit there comes from the opposing PLAY zone sorted by `ZONE_POSITION` (`HST:HSTracker/UIs/Overlay/Board/BoardOverlayViewModel.swift#L116-L120`). |
| Shop minion cells (pinning markers) | @1080, centred | Each cell `138 x 190` @1080 (`0.1278h x 0.1759h`), n occupied cells centred on cx. Vertical centre `540 - 145 = 395` @1080 → **centre y 0.3657 h, top 0.2778 h** | `HST:HSTracker/UIs/Battlegrounds/MinionPinning/BattlegroundsMinionPinningShopView.swift#L27-L41`, `#L62-L64` | `HDT:Controls/Overlay/Battlegrounds/MinionPinning/BattlegroundsMinionPinningShop.xaml#L14`; `BattlegroundsMinionPinningCard.xaml#L17-L18` | The pitch matches the minion row (0.1278 h), but the centre is about 0.01 h higher than the hover-ellipse row (0.376 h). When the cursor hovers a shop minion, HS lifts it out of the row and the rest shift one slot. HSTracker/HDT read `mousedOverSlot` from memory (`BattlegroundsMinionPinningViewModel.swift#L364-L399`). |
| Player's hand card rects | h | Fan centre `(cx - 0.035h, 0.95h)`. Card rect `0.125h x 0.189h`, rotated about its centre. Spacing = `min(0.127h, 0.36*boardW/n)` (i.e. `min(h/10*1.27, 0.48h/n)`). x_i = `handCX - spacing/2*(n-1-2i)`. y and angle follow a fan curve (see §4) | `BoardOverlayView.swift#L157-L228` | `MouseOverDetection.cs#L40-L41`, `#L55`, `#L387-L416`, `#L150-L158` | Walk the cards back to front so the top card wins. |
| Hover detection | — | Ellipse test against each minion ellipse (opponent row first, then player, per index), then rotated-rect test for the hand. Hover fires after **250 ms** with the cursor moved less than √3 px (tolerance 3 on the *squared* distance) | `HST:HSTracker/UIs/Overlay/Board/BoardMouseOverDetection.swift#L29-L34`, `#L60-L118`, `#L130-L149`; `BoardOverlayView.swift#L30-L50` | `MouseOverDetection.cs#L34-L35`, `#L278-L362`, `#L689-L720` | HDT also has a 30 ms/5 px `_battlegroundsTiersMouseOver` for the tier panel. |

### 2c. Hero, hero power, trinkets, anomaly: where HS draws its **big-card pop-ups**

The trackers never draw over the hero portrait, HP, gold, the tavern-tier button, refresh or freeze. They only know the rects where **HS draws its own enlarged-card tooltip** when those are hovered. They use these rects to cut holes in the overlay (the "opacity mask") so their panels don't cover HS's tooltips. `DrawCardRegion(fx, fy, cardH, aspect)`: `x = X(fx)`, `y = fy*h`, `height = cardH*h`, `width = height*aspect`. Source: `HDT:Utility/RegionDrawer/RegionDrawer.cs#L77-L92`, port `HST:HSTracker/Core/RegionDrawer.swift#L85-L100`.

| Pop-up region | Value | HSTracker `Core/RegionDrawer.swift` | HDT `Utility/RegionDrawer/RegionDrawer.cs` |
|---|---|---|---|
| Hovered board minion big card | `offsetX = 0.2 + rel*0.098` (right side) / `0.575 + rel*0.098` (left side), where `rel = pos - (n+1)/2`; y 0.35 (player) / 0.175 (opponent); height 0.39h, aspect 28/39 | `#L176-L214` | `#L168-L203` |
| Player hero power big card | `X(0.70)`, y `0.57h`, height `0.44h`, aspect 24/42 (opponent y 0.04) | `#L311-L320` | `#L284-L291` |
| BG trinket big card (pos 1-based) | player: `X(0.463 - 0.0525*(pos-1))`, y `0.525 - 0.06*(pos-1)`; opponent y `-0.02 + 0.01*(pos-1)`; height 0.365h, aspect 25/36.5 | `#L344-L376` | `#L313-L338` |
| BG hero trinket big card | `X(0.383)`, y 0.48 (player) / -0.03 (opponent) | `#L378-L405` | `#L340-L363` |
| Hero-pick hero-power tooltip | (4 heroes only) `heroX = 0.05975 + i*0.236`, pop-up at `heroX + 0.135` (tooltip on right) or `- 0.16` (on left), y 0.215, height 0.39h | `#L407-L443` | `#L365-L395` |
| Mulligan anomaly big card | `X(0.383)`, y 0.16, height 0.45h | `#L445-L458` | `#L397-L404` |
| Trinket-pick block (n cards) | `leftEdge = 0.51 - n*0.192/2`, cards every 0.192, y 0.32, height 0.32h, aspect 25/36.5 | `#L487-L511` | `#L432-L452` |

**Not found in either tracker: hero portrait, HP, gold, tavern-tier/upgrade button, refresh, freeze, quest progress area, turn number shown by HS.** These are now **measured from screenshots in §8** and stored as `(kx, fy)` in §3. Still not measured: the quest icon and the buddy meter, because neither mechanic is in the current season's screenshots.

### 2d. Tracker panels (our own overlay chrome)

| Element | Coord system | Value | HSTracker | HDT | Notes |
|---|---|---|---|---|---|
| Bob's Buddy panel | @1080 | Top-centre: `left = w/2 - W*scale/2`, `top = 0`. Results row 55 @1080 tall, bottom bar ≤ 352 @1080 wide | `HST:HSTracker/UIs/Overlay/Root/RootOverlayView.swift#L278-L300`; `UIs/Battlegrounds/BobsBuddy/BobsBuddyPanelView.swift#L29-L40` | `HDT:Windows/OverlayWindow.xaml.cs#L277-L285` | Slides down from the top. Hidden while the opponent-info panel is up. |
| Top bar: turn counter, tier/tribe "Battlegrounds minions" strip, guides tabs | @1080, top-right | Anchored at `right = 0, top = 0` of the window. Turn counter 49 @1080 tall, sitting left of the tabs. Tabs panel 249 wide, buttons 83x49. Hover mask 350x120 @1080 in the top-right corner | `RootOverlayView.swift#L416-L462`; `UIs/Battlegrounds/BattlegroundsTurnCounterView.swift#L55`; `UIs/Battlegrounds/Guides/GuidesTabsView.swift#L31`, `#L234-L235` | `HDT:Windows/OverlayWindow.xaml#L488`, `#L562`; `OverlayWindow.xaml.cs#L266-L275` | Tied to the window edge, not to the 4:3 region: on 21:9 it sits in the right-hand bar. |
| Session recap | % of window | `left = 0% * w`, `top = 15% * h` by default. Draggable, and the new percentages are saved. HDT scales it only by its own setting | `HST:HSTracker/Core/Settings.swift#L366-L372`; `UIs/Battlegrounds/Session/BattlegroundsSessionOverlayView.swift#L10-L22`, `#L71-L72` | `HDT:Config.cs#L876-L879`; `Windows/OverlayWindow.Update.cs#L640-L641` | Its default spot overlaps the leaderboard x on a 4:3 window (X(0) = 0), so it is intended for the lobby. |
| Notifications (hero/mulligan) | fy | right 0, bottom `0.04 h` (timewarp: 0.05 h) | `UIs/Battlegrounds/Notifications/BattlegroundsNotificationsView.swift#L41-L48` | `OverlayWindow.xaml.cs#L233-L264` | |
| Inspiration panel | X, fy | `X(0.175)`, `0.13 h` (65% of the 4:3 width) | `RootOverlayView.swift#L519-L523` | `OverlayWindow.xaml.cs#L353-L358` | |
| Tier-7 pre-lobby | X, fy | `X(0.079)`, `0.103 h` | `RootOverlayView.swift#L402-L407` | `OverlayWindow.xaml.cs#L325-L330` | Lobby only. |
| In-game anomaly badge (hover trigger) | X, fy | `X(0.90)`, y `0.33 h`, w `0.13 h`, h `0.10 h` | `HST:HSTracker/UIs/Battlegrounds/Guides/Anomalies/AnomalyGuideBadgeTriggerView.swift#L33-L35` | `HDT:Windows/OverlayWindow.Tooltips.cs#L248-L278` | This is where HS shows the anomaly during the game: right side of the board, just above the middle. |
| Anomaly at hero pick | X, fy | `X(0.635)`, y `0.0825 h`, w `0.1188 h`, h `0.123 h` | `…/AnomalyGuideMulliganTriggerView.swift#L39-L42` | `Tooltips.cs#L371-L394` | |

### 2e. Pick screens

| Element | Value | HSTracker | HDT | Notes |
|---|---|---|---|---|
| **Hero pick** (hover trigger per hero) | `leftEdge = 0.5 - (n*0.165 + (n-1)*0.075)/2` (n = 4 → 0.0575). Hero i: `left = X(leftEdge + i*0.235)`, width `0.165*4/3 h = 0.22 h`, top `0.21 h`, height `0.40 h` (HDT also shifts the trigger left by 0.165 when the game's tooltip is on the left) | `HST:HSTracker/UIs/Battlegrounds/Guides/Heroes/BattlegroundsHeroGuideTriggerView.swift#L34-L44`, `#L66-L81` (hard-codes n = 4) | `HDT:Windows/OverlayWindow.Tooltips.cs#L214-L246` (uses the real zoneSize) | The stats plates below the heroes are 266x568 @1080 in 340-wide cells, centred at `cx + 7s`, row centre `540 + 28.5` @1080 (`HST:…/HeroPicking/BattlegroundsHeroPickingView.swift#L26-L31`, `#L59-L68`; `HDT:Controls/Overlay/Battlegrounds/HeroPicking/BattlegroundsHeroPicking.xaml#L30`, `#L38`). Hero centres from the plates: `cx + (7 + (i-1.5)*340)s` → pitch `0.3148 h`. This matches the trigger pitch 0.235*4/3 = 0.3133 h. The RegionDrawer set (0.1725/0.0635 → pitch 0.3147 h) agrees too. HDT says it is only confident about the layout for exactly 4 heroes. For 2–3 heroes, use the n-generalised leftEdge above (**unverified**). |
| **Trinket pick** | Card p (0-based): `left = X(0.122 + p*0.192)`, top `0.28 h`, w `0.25 h`, h `0.35 h`. RegionDrawer version: `X(0.51 - n*0.096 + p*0.192)`, y 0.32 | `HST:HSTracker/Logging/Game.swift#L4256-L4272` | `Tooltips.cs#L280-L314` | Stats plates 252x430 @1080 in 277-wide cells, centred at `(cx + 10s, 540 - 82.5)` @1080 (`…/TrinketPicking/BattlegroundsTrinketPickingView.swift#L28-L30`, `#L62-L71`; `HDT:Controls/Overlay/Battlegrounds/TrinketPicking/BattlegroundsTrinketPicking.xaml#L30`, `#L38`). |
| **Quest pick** | Reward p: `left = X(0.117 + p*0.27)`, top `0.22 h`, w `0.30 h`, h `0.55 h` | `Game.swift#L4294-L4310` | `Tooltips.cs#L316-L360` | Plates 273x880 @1080 in 385-wide cells, centred at `(cx - 2.5s, 540 + 77)` @1080 (`…/QuestPicking/BattlegroundsQuestPickingView.swift#L24-L26`, `#L42-L51`; `HDT:…/QuestPicking/BattlegroundsQuestPicking.xaml#L19`, `#L26`). |
| Generic discover (4/3/2/1 cards) | For **related-cards** triggers HDT uses fractions of the **full window width** (`vm.Left = 0.116+0.2p` etc. times w), not X(f) | — | `Tooltips.cs#L619-L646` | This is an inconsistency inside HDT. Prefer `RegionDrawer.DrawDiscoverCardRegions` (X-based: spacing 0.27, centre 0.53, y 0.29). |

---

## 3. Swift constants (normalized)

Pseudo-code. `kx` values are centre-relative multiples of **h** (`x = w/2 + kx*h`). `fy` values are multiples of h measured from the top. All sizes are multiples of h.

```swift
/// All values: fractions of client height h; x is relative to the horizontal centre.
/// Tracker part: derived from HSTracker c723bfd / HDT ef8ab6e. Board rows and leaderboard were checked against screenshots (§8c).
/// The [screenshot] part below was measured from screenshots (§8d).
struct BGLayout {
    // Model
    static func x(fourThreeFraction f: CGFloat) -> CGFloat { (f - 0.5) * 4.0 / 3.0 }  // -> kx

    // Leaderboard
    static let leaderboardTop: CGFloat      = 0.15
    static let leaderboardSpan: CGFloat     = 0.69
    static let soloTile: CGFloat            = 0.69 / 8            // 0.08625 (square)
    static let duosTile: CGFloat            = 0.69 * (1 - 0.137) / 8  // 0.074426
    static let duosTeamGap: CGFloat         = 0.69 * 0.137 / 3    // 0.031510
    static let leaderboardLeftKx: CGFloat   = -2.0 / 3.0          // X(0)
    // Dead-for label x for slot i: kx = leaderboardLeftKx + CGFloat(4 - i) * leaderboardLeanKx (+ popout if next opp)
    static let leaderboardLeanKx: CGFloat  = 0.0017 * 4.0 / 3.0   // 0.002267 per slot
    static let nextOpponentPopoutKx: CGFloat     = 0.023 * 4.0 / 3.0   // 0.03067 (duos: 0.015*4/3 = 0.02)
    static func soloSlotTop(_ i: Int) -> CGFloat { leaderboardTop + CGFloat(i) * soloTile }
    static func duosSlotTop(_ i: Int) -> CGFloat {
        leaderboardTop + CGFloat(i) * duosTile + CGFloat(i / 2) * duosTeamGap }

    // Board rows (recruit: top row = Bob's shop; combat: top row = opponent)
    static let rowHeight: CGFloat       = 0.158
    static let playerRowTop: CGFloat    = 0.47          // centre 0.549
    static let topRowTop: CGFloat       = 0.297         // centre 0.376
    static let minionEllipseW: CGFloat  = 0.12
    static let minionGap: CGFloat       = 0.0029 * 4.0 / 3.0   // 0.0038667 each side
    static let slotPitch: CGFloat       = 0.12 + 2 * 0.0029 * 4.0 / 3.0  // 0.127733
    static func slotCentreKx(_ k: Int, of n: Int) -> CGFloat { (CGFloat(k) - CGFloat(n - 1) / 2) * slotPitch }

    // Shop cells as HDT's pinning markers see them (138x190 @1080)
    static let shopCellW: CGFloat = 138.0 / 1080, shopCellH: CGFloat = 190.0 / 1080
    static let shopCentreY: CGFloat = 395.0 / 1080          // 0.36574

    // Hand
    static let handCentreKx: CGFloat = -0.035, handCentreY: CGFloat = 0.95
    static let handCardW: CGFloat = 0.125, handCardH: CGFloat = 0.189

    // Pick screens (left edges as kx; top/size in h)
    static func heroPickLeftKx(_ i: Int, of n: Int = 4) -> CGFloat {
        let edge = 0.5 - (CGFloat(n) * 0.165 + CGFloat(n - 1) * 0.075) / 2
        return x(fourThreeFraction: edge + CGFloat(i) * 0.235) }
    static let heroPickTop: CGFloat = 0.21, heroPickW: CGFloat = 0.22, heroPickH: CGFloat = 0.40
    static func trinketPickLeftKx(_ p: Int) -> CGFloat { x(fourThreeFraction: 0.122 + CGFloat(p) * 0.192) }
    static let trinketPickTop: CGFloat = 0.28, trinketPickW: CGFloat = 0.25, trinketPickH: CGFloat = 0.35
    static func questPickLeftKx(_ p: Int) -> CGFloat { x(fourThreeFraction: 0.117 + CGFloat(p) * 0.27) }
    static let questPickTop: CGFloat = 0.22, questPickW: CGFloat = 0.30, questPickH: CGFloat = 0.55

    // Anomaly
    static let anomalyInGame = (kx: x(fourThreeFraction: 0.90), y: 0.33, w: 0.13, h: 0.10)   // kx = +0.5333
    static let anomalyHeroPick = (kx: x(fourThreeFraction: 0.635), y: 0.0825, w: 0.1188, h: 0.123) // kx = +0.18

    // Our own panels: 1080-reference, scale = h/1080 (HDT clamps to 0.8...1.3 for top-anchored panels)
    static let bobsBuddyAnchor = "top-centre, y = 0"
    static let topBarAnchor    = "top-right of window, y = 0"
    static let sessionDefault  = (leftOfWidth: 0.0, topOfHeight: 0.15)

    // ---- [screenshot] HS UI measured from screenshots (§8), NOT tracker-derived ----
    // Primary source: user's own patch-36.6.1 captures at 1710x1073; cross-checked on 16:9 web shots.
    // Rect = (kx of centre, fy of centre, w, h), all in units of h. Hit rects are the visible art bounds;
    // pad by ~0.005 h. Uncertainty is about ±0.004 h unless noted.
    typealias R = (kx: CGFloat, fy: CGFloat, w: CGFloat, h: CGFloat)
    // Tavern controls (recruit phase, top of board)
    static let tavernUpgradeButton: R = (-0.157, 0.187, 0.088, 0.112)
    static let tavernUpgradeCost: R   = (-0.158, 0.139, 0.040, 0.040)   // gold coin with the cost number
    static let bobTierBadge: R        = (-0.071, 0.209, 0.060, 0.062)   // current tavern tier shield
    static let bobPortrait: R         = (+0.002, 0.176, 0.139, 0.153)
    static let refreshButton: R       = (+0.155, 0.189, 0.088, 0.116)
    static let refreshCost: R         = (+0.155, 0.139, 0.040, 0.040)
    static let freezeButton: R        = (+0.257, 0.165, 0.076, 0.112)
    static let freezeCost: R          = (+0.258, 0.122, 0.033, 0.033)
    // Right side of the board
    static let timerPlate: R          = (+0.547, 0.459, 0.137, 0.060)   // "27s" in recruit, "Combat" in combat
    static let deityOrb: R            = (+0.598, 0.284, 0.096, 0.094)   // season orb with cost + lock (36.x)
    static let deityCost: R           = (+0.600, 0.245, 0.032, 0.032)
    static let duosTeammatePortal: R  = (+0.623, 0.588, 0.151, 0.183)   // Duos only: drag here to pass; ±0.012
    // Player hero cluster (same place in recruit and combat)
    static let heroPortrait: R        = ( 0.000, 0.763, 0.148, 0.165)
    static let heroCrest: R           = (-0.002, 0.669, 0.049, 0.049)   // eye medallion above the portrait
    static let heroArmor: R           = (+0.066, 0.782, 0.052, 0.049)
    static let heroHealth: R          = (+0.068, 0.835, 0.046, 0.040)
    static let heroPower: R           = (+0.165, 0.767, 0.134, 0.134)   // ±0.005 across 6 shots
    static let heroPowerCost: R       = (+0.166, 0.706, 0.048, 0.048)
    static let trinketSlotNear: R     = (-0.129, 0.810, 0.094, 0.094)   // lower slot, next to the hero
    static let trinketSlotOuter: R    = (-0.200, 0.742, 0.094, 0.094)   // upper-left slot; older/Duos shots ~+0.006 kx
    // Gold (bottom right)
    static let goldPill: R            = (+0.279, 0.924, 0.080, 0.035)   // "3/3" text
    static func goldCoin(_ i: Int) -> R { (0.343 + CGFloat(i) * 0.0282, 0.927, 0.025, 0.025) }
    // Opponent hero cluster (combat phase, top of board): the player's cluster, mirrored top to bottom
    static let oppHeroPortrait: R     = ( 0.000, 0.178, 0.134, 0.148)
    static let oppHeroCrest: R        = (+0.002, 0.100, 0.046, 0.046)
    static let oppHeroArmor: R        = (+0.067, 0.193, 0.051, 0.048)
    static let oppHeroHealth: R       = (+0.067, 0.244, 0.043, 0.036)
    static let oppHeroPower: R        = (+0.163, 0.223, 0.129, 0.129)
    static let oppTrinketNear: R      = (-0.116, 0.153, 0.092, 0.092)   // upper slot, next to the hero
    static let oppTrinketOuter: R     = (-0.190, 0.214, 0.094, 0.094)
    // Leaderboard extras
    static let leaderboardCrown: R    = (-0.610, 0.141, 0.060, 0.043)
    static func rankBadgeCentre(_ i: Int) -> (kx: CGFloat, fy: CGFloat) {   // i >= 1; diameter ~0.032
        (-0.646 - 0.003 * CGFloat(i - 1), leaderboardTop + CGFloat(i) * soloTile + 0.010) }
    // Hero-pick screen
    static let pickTribesText: R      = (+0.002, 0.171, 0.175, 0.049)   // lobby tribes, 3 lines under the title; OCR here
    static let pickTitle: R           = (+0.003, 0.124, 0.257, 0.030)   // "Choose a Hero"
    static let pickBannerPlate: R     = (+0.010, 0.152, 0.343, 0.123)
    static let pickTrinketMedallion: R = (-0.229, 0.149, 0.111, 0.110)
    static let pickDeityOrb: R        = (+0.239, 0.149, 0.113, 0.116)
    static let pickHeroCentreKx: [CGFloat] = [-0.461, -0.150, +0.166, +0.481]   // arch apex x; pitch 0.314
    static let pickHeroTop: CGFloat = 0.298, pickHeroBottom: CGFloat = 0.622, pickHeroW: CGFloat = 0.235
    static let pickRerollPlateFy: CGFloat = 0.676, pickConfirm: R = (+0.004, 0.792, 0.131, 0.069)
    // HS chrome anchored to the WINDOW edges, not to cx (distances in h from that edge)
    static let settingsGearFromRight: CGFloat = 0.040, journalFromRight: CGFloat = 0.126, chromeBottomRowFy: CGFloat = 0.976

    // Still TODO (not on screen in any shot so far): questProgress icon, buddyMeter.
}
```

---

## 4. Worked numbers

These come from `scratchpad/coords.py`, which implements the formulas above. Top-left origin, points.

| Quantity | **1710x1073** (this Mac, fullscreen) | **1920x1080** | 1440x872 (1440x900 windowed, 28-pt title bar) | 2560x1080 (21:9) |
|---|---|---|---|---|
| s = h/1080 | 0.9935 | 1.0 | 0.8074 | 1.0 |
| 4:3 region x | 139.7 … 1570.3 | 240 … 1680 | 138.7 … 1301.3 | 560 … 2000 |
| Leaderboard x (tile) | 139.7 … 232.2 | 240 … 333.1 | 138.7 … 213.9 | 560 … 653.1 |
| Solo slot tops (tile 92.55 / 93.15 / 75.21) | 161, 253, 346, 439, 531, 624, 716, 809 (bottom 901) | 162, 255, 348, 441, 535, 628, 721, 814 (bottom 907) | 131, 206, 281, 356, 432, 507, 582, 657 | = 1080p |
| Duos slot tops | 161, 241, 354, 434, 548, 628, 742, 821 | 162, 242, 357, 437, 552, 632, 746, 827 | 131, 196, 288, 353, 445, 510, 603, 668 | = 1080p |
| Slot pitch / ellipse w / row h | 137.1 / 128.8 / 169.5 | 138.0 / 129.6 / 170.6 | 111.4 / 104.6 / 137.8 | = 1080p |
| Player row centre y | 589.1 | 592.9 | 478.7 | 592.9 |
| Shop / top row centre y (ellipse row; pinning cell) | 403.4; 392.4 | 406.1; 395.0 | 327.9; 318.9 | = 1080p |
| 7 minions centre x | 444, 581, 718, 855, 992, 1129, 1266 | 546, 684, 822, 960, 1098, 1236, 1374 | 386 … 1054 | 866 … 1694 |
| 3 minions centre x | 718, 855, 992 | 822, 960, 1098 | 609, 720, 831 | 1142, 1280, 1418 |
| Hero-pick trigger lefts (w, top, h) | 222, 558, 894, 1231 (236, 225, 429) | 323, 661, 1000, 1338 (238, 227, 432) | 206, 479, 752, 1025 | 643 … 1658 |
| Trinket-pick lefts (top 0.28h) | 314, 589, 864, 1138 | 416, 692, 969, 1245 | 281, 504, 727, 950 | 736 … 1565 |
| Quest-pick lefts (top 0.22h) | 307, 693, 1080 | 408, 797, 1186 | 275, 589, 903 | 728, 1117, 1506 |
| Anomaly badge (x, y, w, h) | 1427, 354, 139, 107 | 1536, 356, 140, 108 | 1185, 288, 113, 87 | 1856, 356, 140, 108 |

Spot checks:
- **1920x1080**: `X(0) = 1920*0.75*0 + 1920*(0.25)/2 = 240`. Tile = 1080*0.69/8 = 93.15. Slot 3 top = 162 + 3*93.15 = 441.5.
- **1710x1073**: ratio = 1.3333/1.5936 = 0.8367, so `X(0) = 1710*(1-0.8367)/2 = 139.7`. Row pitch = 0.127733*1073 = 137.06. Player row centre = 0.549*1073 = 589.1. A 4-minion board has centres at 855 ± 68.5 and 855 ± 205.6, giving 649.4, 786.5, 923.5, 1060.6.
- **Hand fan** (1920x1080, 5 cards): the fan centre is x = 960 - 0.035*1080 = 922.2. Spacing = min(1080/10*1.27 = 137.2, 1440*0.36/5 = 103.7) = 103.7, so `x_i = 922.2 - 51.84*(4 - 2i)` → 714.8, 818.5, 922.2, 1025.9, 1129.6. Base y = 0.95*1080 = 1026, and the outer cards sit lower because of the fan term `(|i - n/2|^2 / 4n) * 0.11`.
- Cross-source check at 1920x1080: the hero-pick centre for hero 0 is 442 (trigger) vs 457 (stats plate) vs 450 (RegionDrawer). The sources agree to within 15 pt (0.8% of w).

---

## 5. Aspect ratio, windowed, Retina, notch

- **16:9 / 16:10 / MacBook 1710x1073 (~1.594:1) / 21:9**: the formulas need no special cases. Board content stays at `cx ± k*h`, and the extra width becomes empty side margin. On 21:9, only the window-edge-anchored chrome (top bar, notifications, session recap at `0%` of w) moves away from the board. Consider anchoring our panels to the 4:3 region (`X(1)` instead of `w`) so they stay near the board on ultrawide. **Unverified**: whether HS itself keeps the leaderboard at X(0) on 21:9. Both trackers assume it does, and neither special-cases ultrawide (a search for "ultrawide/21:9" in both repos finds nothing). Also unverified: narrower than 4:3 (w/h < 1.333), where `ratio > 1` would put X(0) < 0. HS probably letterboxes there, and the formulas would be wrong.
- **Windowed**: use the **content** rect (window frame minus title bar). HSTracker subtracts a title-bar height it measures at runtime, only when `AXFullScreen == 0`. Better: read the AX frame and subtract `NSWindow.frameRect(forContentRect:)`-style chrome, or measure the difference once. For the 1440x900 example above, h = 872, so everything shrinks by 0.807.
- **Fullscreen on a notched Mac**: the AX frame is already the area below the notch (y = 34, 1710x1073). Use it as it is. Do not use `NSScreen.frame` (1710x1107): its 34 extra points would shift every y by about 3%.
- **Retina**: use points throughout (1710x1073 pt = 3420x2146 px). The only place pixels matter is when crossing into `CGWindowListCreateImage` or `ScreenCaptureKit` images.
- **Rounding**: HDT casts width to `(int)` inside `GetScaledXPos`. The effect is sub-pixel, so ignore it.

## 6. Caveats

- **HS UI changes with patches.** Every constant here is hand-tuned. HDT's comments ("we're only confident about the layout if the zone contains exactly 4") and its per-slot label nudges show they were fitted by eye. Re-check after each major BG patch. Plan a debug overlay that draws the rects, plus a calibration offset in settings. HDT has a `Config.Instance.Debug` path for board and hand regions (`MouseOverDetection.cs#L68-L102`), but the minion part of it is commented out.
- **Duos**: leaderboard geometry differs (the tile/gap formula above). The next-opponent pop-out uses 0.015 instead of 0.023. Leaderboard place is per team (1–4). The teammate hover counts as "own" (no opponent panel). Duos also adds the **teammate portal** on the right of the board: a swirl with the teammate's hero in it, which you drag cards onto to pass them and click to view the teammate's board. It is now measured from screenshots (§8, `duosTeammatePortal`). No separate pass button was seen in these shots.
- **Shop hover**: HS lifts the hovered shop minion and re-lays out the row, so geometry-only hit tests can be off by one slot while hovering. The trackers avoid this by reading `mousedOverSlot` from memory, which we can't do. Mitigation: hit-test using the count from the *log* state, and accept a brief mismatch.
- **Two centre-y values for the top row** (0.376 h for the hover ellipses, 0.366 h for the pinning cells). The minion art spans both, so a rect from `0.2778h` to `0.4535h` covers both.
- **HSTracker vs HDT scale**: HSTracker's panel subtree uses unclamped `h/1080`. HDT clamps top panels to 0.8–1.3. On 1440x872 (s = 0.807) the clamp barely matters; at h < 864 it does.
- **Session recap** default (0, 0.15h) overlaps the leaderboard on narrow windows. It is meant for the lobby, or for the user to move.
- Screenshot verification: see §8. Leaderboard pitch, shop and board pitch, and the centring model all check out. Two small differences: the visible player-row minions sit about 0.005 h higher than the 0.549 h ellipse centre, and hero-pick portraits sit about 0.018 h right of HDT's trigger boxes. Re-measure after each major patch, because season mechanics (the Deity orb and the crest medallion) move in and out.

## 7. Citation index (permalinks)

HSTracker (`https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/…`):
- `HSTracker/Core/SizeHelper.swift#L123-L148`, `#L205-L211`, `#L247-L261`
- `HSTracker/AppDelegate.swift#L492-L502`
- `HSTracker/UIs/Overlay/Root/RootOverlayView.swift#L153-L161`, `#L278-L322`, `#L402-L462`, `#L519-L528`
- `HSTracker/UIs/Overlay/Board/BoardOverlayView.swift#L30-L50`, `#L73-L228`
- `HSTracker/UIs/Overlay/Board/BoardMouseOverDetection.swift#L29-L149`
- `HSTracker/UIs/Overlay/Board/BoardOverlayViewModel.swift#L116-L120`
- `HSTracker/UIs/Battlegrounds/BattlegroundsOpponentDeadForView.swift#L30-L163`
- `HSTracker/UIs/Battlegrounds/BattlegroundsOpponentInfoView.swift#L22-L73`
- `HSTracker/UIs/Battlegrounds/BattlegroundsOpponentInfoViewModel.swift#L47-L55`, `#L98-L108`, `#L131-L185`
- `HSTracker/HearthWatcher/BattlegroundsLeaderboardWatcher.swift#L19-L36`
- `HSTracker/Logging/OpponentDeadForTracker.swift#L37-L45`
- `HSTracker/UIs/Battlegrounds/MinionPinning/BattlegroundsMinionPinningShopView.swift#L27-L64`
- `HSTracker/UIs/Battlegrounds/MinionPinning/BattlegroundsMinionPinningViewModel.swift#L364-L399`
- `HSTracker/UIs/Battlegrounds/HeroPicking/BattlegroundsHeroPickingView.swift#L26-L68`
- `HSTracker/UIs/Battlegrounds/Guides/Heroes/BattlegroundsHeroGuideTriggerView.swift#L34-L81`
- `HSTracker/UIs/Battlegrounds/TrinketPicking/BattlegroundsTrinketPickingView.swift#L28-L71`
- `HSTracker/UIs/Battlegrounds/QuestPicking/BattlegroundsQuestPickingView.swift#L24-L51`
- `HSTracker/Logging/Game.swift#L4256-L4310`
- `HSTracker/UIs/Battlegrounds/Guides/Anomalies/AnomalyGuideBadgeTriggerView.swift#L33-L35`, `AnomalyGuideMulliganTriggerView.swift#L39-L42`
- `HSTracker/Core/RegionDrawer.swift#L85-L511`
- `HSTracker/Core/Settings.swift#L366-L372`; `HSTracker/UIs/Battlegrounds/Session/BattlegroundsSessionOverlayView.swift#L10-L72`

HDT (`https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/Hearthstone%20Deck%20Tracker/…`):
- `Utility/Helper.cs#L429`
- `Windows/OverlayWindow.xaml.cs#L495`, `#L509-L513`, `#L233-L295`, `#L325-L358`
- `Windows/OverlayWindow.MouseOverDetection.cs#L34-L158`, `#L278-L362`, `#L387-L416`, `#L689-L720`
- `Windows/OverlayWindow.Update.cs#L529-L533`, `#L640-L641`, `#L742-L819`
- `Windows/OverlayWindow.Tooltips.cs#L214-L394`, `#L619-L646`
- `Windows/OverlayWindow.xaml#L303-L317`, `#L383-L398`, `#L417-L418`, `#L488`, `#L562`
- `Utility/RegionDrawer/RegionDrawer.cs#L9-L452`
- `Controls/Overlay/Battlegrounds/HeroPicking/BattlegroundsHeroPicking.xaml#L30-L38`, `TrinketPicking/BattlegroundsTrinketPicking.xaml#L30-L38`, `QuestPicking/BattlegroundsQuestPicking.xaml#L19-L26`, `MinionPinning/BattlegroundsMinionPinningShop.xaml#L14`, `MinionPinning/BattlegroundsMinionPinningCard.xaml#L17-L18`, `BattlegroundsOpponentInfo.xaml#L16-L66`
- `OpponentDeadForTracker.cs#L39-L42`; `Hearthstone/Watchers.cs#L533-L534`; `Config.cs#L876-L879`

Firestone (`https://github.com/Zero-to-Heroes/firestone/blob/0a30f066eb77a417637d95cec86444456f607ba1/…`):
- `libs/legacy/feature-shell/src/lib/js/components/overlays/_full-screen-overlays.component.scss#L11-L39`
- `libs/legacy/feature-shell/src/lib/js/components/battlegrounds/overlay/bgs-leaderboard-empty-card.component.scss#L2`
- `libs/legacy/feature-shell/src/lib/js/components/overlays/bgs-leaderboard-widget-wrapper.component.ts#L108-L114`

---

## 8. Measured from screenshots [screenshot]

Measured 2026-09-22. **These values come from pixels, not tracker code.** Nothing here was captured from the screen by the agent, and Hearthstone was not touched. The images stay outside the repo (session scratchpad only).

### 8a. Sources

| ID | Source | Date | Size (content) | Full frame? | Phase | Used for |
|---|---|---|---|---|---|---|
| **U4** | User's own capture, this Mac, patch 36.6.1 | 2026-09-22 | 2000x1295 file (downscaled from 1710x1107 full screen). Rows 0–39 are the black notch/menu strip, so the content is **2000x1255** = 1710x1073 x 1.1696 | Yes, once the strip is cropped | Recruit, turn 1: 3 minions + 1 spell in the shop, 2 locked trinket slots, gold 3/3 | **Primary reference frame** for all of §8 |
| **U5** | User capture, same session | 2026-09-22 | 2000x1258, 3-row black strip at the top → 2000x1255 | Yes | Combat, 1 v 1 minions, opponent hero at the top | Opponent cluster; confirms the player cluster |
| **U3** | User capture, same session | 2026-09-22 | 2000x1199: a **crop**, upscaled. Registered to U4 by SIFT (scale 0.9599, offset (18.3, 17.5) px), so the crop is exactly U4's frame | Crop | Hero pick (4 heroes, 2 locked), lobby tribes in the banner | Hero-pick screen |
| U2 | User capture, same session | 2026-09-22 | 2000x1257, 2-row strip → 2000x1255 | Yes | BG lobby (not in game) | Window-edge chrome only |
| W1 | HDT issue #4676 attachment `https://github.com/user-attachments/assets/d31ba6c9-39bb-4ca3-a016-a4acdcaed383` (also `…/529f0987-33f2-46cc-aef0-4312a79015b0`) | 2025-12-08 | 1920x1080 | Yes (16:9; the HDT overlay is drawn on top) | Recruit, turn 3: 3+3 minions | 16:9 check; player board row |
| W2 | HDT issue #4585 attachment `https://github.com/user-attachments/assets/3de6aa16-fa67-4999-8fd2-960bef90baad` | 2024-10-21 | 2560x1440 | Yes (16:9) | Recruit, turn 1, trinket slots | 16:9 at 1440p check |
| W3 | r/BobsTavern "Once upon a time, this was a winning board" `https://i.redd.it/u8ewlasvkhkh1.png` (post `https://www.reddit.com/r/BobsTavern/comments/1vtd2zx/`) | 2026-08-20 | 1920x1080 | Nearly (registered scale is 0.3% off the model, so there may be a slight crop) | Recruit, turn 15: 4 shop + 7 board | Player row, 7-minion pitch |
| D1 | r/BobsTavern Duos post `https://i.redd.it/7qqw00jdd90f1.png` (`…/comments/1kkha37/`) | 2025-05-12 | 1920x1080 | Yes | **Duos** recruit, 5 shop items | Teammate portal, Duos leaderboard |
| D2 | r/BobsTavern Duos post `https://i.redd.it/6p4ap55b1std1.png` (`…/comments/1fzyylf/`) | 2024-10-09 | 2624x1638, with 29-px bars top and bottom → 2624x1580 | Yes, inside the bars | **Duos** recruit | Teammate portal (second sample) |

Rejected: HSTracker #1378 (cropped hero pick), r/BobsTavern `688u9qep2aig1` and `b9vu6gocvswf1` (cropped horizontally), HDT #4606 (windowed Windows capture with title bar and taskbar), and results/stats screens.

**Method.** Each image was reduced to its content rect, then registered to U4 with SIFT + RANSAC as a 4-DOF similarity (OpenCV `estimateAffinePartial2D`). Element positions were read on U4's 2000x1255 frame. Circular elements were fitted with Hough circles (about ±2 px), and the others read from zoomed crops with a 10-px grid (about ±5 px). They were then converted with `kx = (x − 1000)/1255`, `fy = y/1255`. 1 px = 0.0008 h, so **typical uncertainty is ±0.002 h (circle fits) to ±0.004 h (edges read by eye)**.

### 8b. The coordinate model itself is confirmed

When the 16:9 shots are registered to the 1.594:1 user frame, the model predicts scale `= 1255/H` and x-offset `= 1000 − scale·W/2` (height-only scaling, centred on cx), with zero y-offset:

| Shot | Fitted scale | Model scale | Fitted tx | Model tx | ty | SIFT inliers |
|---|---|---|---|---|---|---|
| W1 1920x1080 | 1.1621 | 1.1620 | −115.8 | −115.6 | −0.1 | 1606 |
| W2 2560x1440 | 0.8722 | 0.8715 | −118.8 | −115.6 | +0.1 | 394 |
| W3 1920x1080 | 1.1659 | 1.1620 | −120.4 | −115.6 | −3.1 | 1006 |
| D1 1920x1080 | 1.1622 | 1.1620 | −116.1 | −115.6 | −0.1 | — |
| U5 (same Mac) | 1.0002 | 1 | −0.1 | 0 | −0.4 | 1119 |

So the §1 model (everything scales with h, x relative to cx) holds for **all board-anchored HS UI** across 16:9 and 1710x1073, to within about 0.1–0.3%.

**Exception: HS chrome anchored to the window edges.** The name labels (opponent name top-left, player name bottom-left), the clock, the friends button, the journal and the settings gear stay at fixed h-distances from the **window** edges, not from cx. Measured: gear centre 0.040 h from the right edge (U4: 0.040, W1: 0.041), journal 0.126 h from the right (U4: 0.126, W1: 0.126), clock about 0.13 h from the left, bottom-row centre y 0.976 h. On wide windows these separate from the board.

### 8c. Checks of the tracker-derived values

| Value (§2) | Tracker model | Measured | Verdict |
|---|---|---|---|
| Leaderboard slot pitch | 0.08625 h | 108.2 px = **0.0862 h** (U4 and U5, slots 1–6) | OK, exact |
| Leaderboard slot centre | `0.15 + (i+0.5)·0.08625` | Visible red tile frame centres: slot 1 0.2781, slot 2 0.3637, slot 3 0.4498, slot 4 0.5359, slot 5 0.6227, slot 6 0.7096 → model − **0.0013 ± 0.0005** | OK (use the model; the visible frame is inset) |
| Leaderboard tile size / x | square 0.08625 h, left at X(0) = kx −0.667 | The visible framed portrait is **0.056 h wide x 0.074 h tall**. Frame left kx −0.629 (slot 1) … −0.660 (slot 6), frame centre kx −0.601 … −0.623 (about −0.004 per slot downward, the perspective lean). Rank badges stick out to about kx −0.665. The next-opponent tile pops out and grows (U4 slot 7: 0.100 x 0.109 h) | OK. The model rect contains the art; x lean confirmed |
| Leaderboard crown | — | centre (−0.610, 0.141), 0.060 x 0.043 h, above slot 0 | new |
| Rank badge (slots ≥ 1) | — | centre kx −0.646 − 0.003·(i−1), fy = slot top + 0.010, Ø ≈ 0.032 h | new |
| Duos team blocks | team j top `0.15 + j·0.1804`, block 0.149 h | D1: 0.140 (glow-obscured), 0.328, 0.503, 0.697 vs model 0.150, 0.330, 0.511, 0.691 | OK, within ±0.008 h (lower-res source) |
| Shop / top-row centre x (4 items) | cx + (k−1.5)·0.12773 h | 758, 922, 1083, 1241 px vs model 759.6, 919.8, 1080.2, 1240.5 → Δ ≤ 3 px (0.002 h) | OK, pitch and centring |
| Shop row y | ellipse centre 0.376, pinning cell 0.2778–0.4537 (centre 0.3657) | Minion oval 0.305–0.440 (centre **0.372**). Whole card incl. tier shield **0.280–0.446** (centre 0.363). Same in W3 and D1 | OK. The oval centre is between the two tracker values; the pinning cell fits the whole card |
| Player board row y | top 0.47, centre 0.549, height 0.158 | Oval 0.476–0.610, centre **0.5435** (W3, 7 minions; W1 agrees) | Small offset: visible centre is 0.0055 h higher; the 0.158-tall hover band still contains the oval |
| Board slot pitch | 0.12773 h | 159–160 px = **0.127 h** (W3, 7 minions, middle one at cx) | OK |
| Hero-pick centres | HDT trigger centre kx −0.480, −0.167, +0.147, +0.460; stats plates −0.466, −0.151, +0.164, +0.479 | Arch apex x (U3): **−0.461, −0.150, +0.166, +0.481**, pitch 0.314 h | OK. Matches the **stats-plate** formula within 0.005. The HDT trigger box is about 0.018 h left |
| Hero-pick portrait y | trigger top 0.21, height 0.40 (to 0.61) | Arch top **0.298**, name-plate bottom **0.622** | Offset: the trigger starts about 0.09 h above the art (it covers HS's tooltip area). Use 0.298–0.622 for the portrait itself |
| In-game anomaly badge | X(0.90) → kx +0.533, y 0.33 | No anomaly in these lobbies. The **Deity orb** (below) occupies about kx +0.60, fy 0.28, overlapping the badge's hover rect | Not verified; beware the overlap in seasons with both |

### 8d. New elements (fill the §2c TODO)

Centre and bounds are in `kx` (centre-relative, units of h) and `fy`. **Primary** = U4/U5/U3 on this Mac. **Cross-check** = other shots registered to the same frame (min…max of centre values).

| Element | Centre kx | Centre fy | Bounds kx | Bounds fy | Cross-check spread (centre) | Notes |
|---|---|---|---|---|---|---|
| **Tavern-upgrade button** (star shield) | −0.157 | 0.187 | −0.201 … −0.113 | 0.131 … 0.243 | — | Hit area = the shield. Recruit phase only |
| Tavern-upgrade **cost** coin | −0.158 | 0.139 | −0.179 … −0.139 | 0.119 … 0.159 | kx −0.156…−0.160, fy 0.138…0.141 (U4, D1, D2, W1, W2, W3) | Read the cost digit here (OCR) |
| Bob's current tier badge | −0.071 | 0.209 | −0.101 … −0.041 | 0.177 … 0.239 | — | Star count = tavern tier |
| Bob / tavern portrait | +0.002 | 0.176 | −0.068 … +0.072 | 0.100 … 0.253 | — | In combat the opponent hero takes this spot (below) |
| **Refresh (reroll) button** | +0.155 | 0.189 | +0.112 … +0.199 | 0.131 … 0.247 | — | Green glow when affordable |
| Refresh **cost** coin | +0.155 | 0.139 | +0.135 … +0.175 | 0.119 … 0.159 | kx +0.155…+0.156, fy 0.138…0.141 (6 shots) | |
| **Freeze button** | +0.257 | 0.165 | +0.219 … +0.295 | 0.112 … 0.223 | — | Sits higher and is smaller than refresh |
| Freeze cost coin | +0.258 | 0.122 | +0.241 … +0.275 | 0.104 … 0.138 | kx +0.258…+0.259, fy 0.121…0.124 (4 shots) | |
| Turn timer / phase plate | +0.547 | 0.459 | +0.478 … +0.615 | 0.428 … 0.488 | U4 "27s", U5 "Combat", D1 "13s" at the same spot (±0.002) | The rope runs left from here along y ≈ 0.46 |
| **Deity orb** (36.x season orb, cost + lock) | +0.598 | 0.284 | +0.551 … +0.647 | 0.239 … 0.333 | U4 vs U5 ±0.003 | Seasonal. Cost coin at (+0.600, 0.245) Ø 0.032, lock at (+0.603, 0.327) |
| **Player hero portrait** | 0.000 | 0.763 | −0.074 … +0.074 | 0.681 … 0.846 | U5 (combat) same ±0.005 | Arch-shaped; the rect is the frame |
| Hero crest medallion (eye emblem) | −0.002 | 0.669 | −0.027 … +0.022 | 0.644 … 0.693 | U5 ±0.002 | Seasonal (36.x). Purpose not confirmed from stills |
| Hero **armor** (shield) | +0.066 | 0.782 | +0.040 … +0.092 | 0.757 … 0.806 | — | Hidden at 0 armor |
| Hero **health** (drop) | +0.068 | 0.835 | +0.045 … +0.092 | 0.817 … 0.857 | D1 same | OCR target for HP |
| **Hero power** | +0.165 | 0.767 | +0.098 … +0.232 | 0.700 … 0.834 | kx +0.159…+0.167, fy 0.764…0.770 (U4, U5, D1, D2, W1, W2, W3) | Ring Ø 0.130–0.142 h (the glow varies). One slot in all shots. **Two-hero-power heroes: not seen**, so treat as TODO |
| Hero-power cost coin | +0.166 | 0.706 | +0.142 … +0.190 | 0.682 … 0.730 | — | |
| **Trinket slot, near** (lower, next to the hero) | −0.129 | 0.810 | −0.176 … −0.082 | 0.763 … 0.857 | kx −0.122…−0.129 (U4, U5, D1, D2, W2) | Ø 0.094 h. Locked padlock on top until unlocked. Older/Duos shots sit about +0.006 kx |
| **Trinket slot, outer** (upper-left) | −0.200 | 0.742 | −0.247 … −0.153 | 0.695 … 0.789 | kx −0.194…−0.201, fy 0.740…0.745 | Which slot holds the lesser vs the greater trinket is **not determined** from stills. HDT's pop-up offsets (pos 2 further left and higher) suggest pos 1 = near, pos 2 = outer (unverified) |
| **Gold** text pill ("3/3") | +0.279 | 0.924 | +0.239 … +0.319 | 0.907 … 0.942 | D1 "3/8", D2 "4/4" same ±0.002 | OCR current/max gold here |
| Gold coin i (0-based) | +0.343 + 0.0282·i | 0.927 | Ø 0.025 | | W2 same | Up to 10 coins |
| **Opponent hero portrait** (combat) | 0.000 | 0.178 | −0.067 … +0.067 | 0.104 … 0.253 | — (U5 only) | Replaces Bob's portrait in combat. The tavern buttons are gone |
| Opponent crest medallion | +0.002 | 0.100 | −0.022 … +0.025 | 0.077 … 0.124 | | |
| Opponent armor / health | +0.067 / +0.067 | 0.193 / 0.244 | ±0.026 / ±0.022 | | | |
| Opponent hero power | +0.163 | 0.223 | +0.098 … +0.227 | 0.159 … 0.288 | | Shown face-down (dark) during combat |
| Opponent trinket, near / outer | −0.116 / −0.190 | 0.153 / 0.214 | Ø 0.093 | | | Mirror image of the player's: the near slot is the **upper** one |
| **Duos teammate portal** (drag to pass; shows teammate hero) | +0.623 | 0.588 | +0.550 … +0.701 | 0.502 … 0.685 | D1 (+0.622, 0.588), D2 (+0.627, 0.587) | Duos only. Soft swirl edge, so ±0.012. No separate "pass" button seen |
| Hero pick: **lobby tribes text** | +0.002 | 0.171 | −0.085 … +0.089 | 0.146 … 0.195 | U3 only | 3 centred lines (≈ fy 0.152, 0.169, 0.187) under "Choose a Hero" (title fy 0.109–0.139). **OCR rect for the tribe list**: pad to kx ±0.10, fy 0.14–0.20 |
| Hero pick: banner plate | +0.010 | 0.152 | −0.162 … +0.182 | 0.091 … 0.214 | | Trinket-style medallion to the left (−0.229, 0.149, Ø 0.11), Deity orb to the right (+0.239, 0.149, Ø 0.115), crest below (+0.005, 0.218) |
| Hero pick: portraits | −0.461, −0.150, +0.166, +0.481 | 0.460 | each ±0.117 wide | 0.298 … 0.622 | | Lock icons on locked heroes at about fy 0.49. Armor shield at centre kx + 0.086, fy 0.457 |
| Hero pick: reroll plates / Confirm | −0.153, +0.166 / +0.004 | 0.676 / 0.792 | plates 0.171 x 0.063; Confirm 0.131 x 0.069 | | | Reroll plates under the unlocked heroes only |

**Still not measured** (no such UI in any shot): the quest icon/progress (no quests this season), the buddy meter, and the dual-hero-power layout. Tavern-spell/discover overlays and hand cards were not re-measured. One hand card in D2 sits at about (−0.04, 0.93), consistent with the §2b fan centre.

**Confidence.** High for the tavern controls, hero cluster, gold, timer and leaderboard: multiple shots at two aspect ratios agree to within 0.003–0.006 h. Medium for the opponent cluster, the hero-pick banner and the Deity orb (one session, one patch). Medium-low for the Duos portal (soft edges, two older web shots) and for the seasonal elements (the crest, the Deity orb), which will move or disappear with season changes.
