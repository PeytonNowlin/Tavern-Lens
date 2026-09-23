# Part: macOS overlay, game detection, log tailing, distribution

Research date: 2026-09-22. Machine: macOS 26.5 (25F71), Apple Silicon, notched built-in display 1710x1107 pt @2x.
HSTracker reference: `HearthSim/HSTracker` shallow clone at commit `c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4` (2026-09-22). Links below use that commit:
`https://github.com/HearthSim/HSTracker/blob/c723bfd4a7f05ff4d2b7809ae95fce9a9a066ac4/<path>#L<n>` (abbreviated below as `HST:<path>#L<n>`).
Apple doc pages are cited by their developer.apple.com URL; their text was pulled from the docs JSON endpoint (`developer.apple.com/tutorials/data/documentation/<path>.json`).

---

## 0. Local facts about Hearthstone on this machine (measured)

Hearthstone finished installing and was launched during this research (process `…/Hearthstone.app/Contents/MacOS/Hearthstone -launch -uid hs_beta`, pid 61750), so I could probe a live instance.

| Fact | Value | How |
|---|---|---|
| Bundle id | **`unity.Blizzard Entertainment.Hearthstone`** (not `com.blizzard.hearthstone`) | `plutil -p /Applications/Hearthstone/Hearthstone.app/Contents/Info.plist` |
| Version | `CFBundleVersion` = `36.6.251952`; `CFBundleShortVersionString` = `1.0` (useless) | same |
| Engine | "Unity Player version 6000.3.11f1" (Unity 6) | `CFBundleGetInfoString` |
| Minimum macOS | `LSMinimumSystemVersion` = `12.0` | Info.plist |
| Architecture | Universal (x86_64 + arm64); running natively as arm64 (`executableArchitecture` = 16777228 = CPU_TYPE_ARM64) | `file …/MacOS/Hearthstone`, NSRunningApplication probe |
| Signing | Developer ID Application: Blizzard Entertainment, Inc. (G847MC6JZ5); CodeDirectory `flags=0x0` (no hardened runtime) | `codesign -dv` |
| Activation policy | `.regular` (0) | probe |
| Window mode at first launch | **Native macOS fullscreen** (`AXFullScreen` = 1), AX frame (0,34) 1710x1073, i.e. the area *below the notch/menu-bar strip* of a 1710x1107 screen | AX probe (below) |
| Logs root | `/Applications/Hearthstone/Logs/` containing one dir per client launch, e.g. `Hearthstone_2026_09_22_20_31_46`, `Hearthstone_2026_09_22_20_33_28` (two launches today) | `ls` |
| Per-session files | `Power.log`, `Zone.log`, `LoadingScreen.log`, `Gameplay.log`, `Decks.log`, `Achievements.log`, `Hearthstone.log`, … (Power.log 663 KB after ~2 min in menus) | `ls -la` |
| log.config | `~/Library/Preferences/Blizzard/Hearthstone/log.config` exists (written 20:30 before first launch) with `[Power] [LoadingScreen] [Zone] [Achievements] [Gameplay] [FullScreenFX] [Decks]`, each `LogLevel=1 FilePrinting=true ConsolePrinting=false ScreenPrinting=false Verbose=true` | `cat` |
| Other bundles | `PlugIns/OSXWindowManagement.bundle` (`Blizzard.OSXWindowManagement`, exports only `_DisableTabBar`), `NativeApiMac.bundle`; `/Applications/Hearthstone/Hearthstone Beta Launcher.app` (`net.battle.bootstrapper`) | `plutil`, `nm -gU` |

Probe programs (compiled with `swiftc`, run from the terminal) are at `scratchpad/wl.swift` and `scratchpad/ax.swift`.

**CGWindowList probe result** (process had `CGPreflightScreenCaptureAccess() == false`, i.e. no Screen Recording permission):
- Hearthstone windows returned with `kCGWindowOwnerName = "Hearthstone"`, `kCGWindowLayer = 0`, `kCGWindowBounds` populated (main window 1710x1073 at y=34, plus a 1710x44 strip and several 34-pt tall/offscreen helper windows and a 500x500 offscreen window).
- `kCGWindowName` was **absent** on every window.
- Conclusion: bounds/owner/pid/layer work without Screen Recording; the window title does not. You must pick the "main" window by largest area on layer 0 (exactly what HSTracker does, see §2).

**AX probe result** (host process was Accessibility-trusted): one window, title "Hearthstone", subrole `AXStandardWindow`, `AXFullScreen = 1`, position (0,34), size (1710,1073). `AXObserverCreate` succeeded.

---

## 1. Overlay over a native-fullscreen game on its own Space

**Yes, it works**, and HSTracker ships it on by default.

- Apple: `.canJoinAllSpaces` — "The window can appear in all spaces. The menu bar behaves this way." https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces
- Apple: `.fullScreenAuxiliary` — "The window displays on the same space as the full screen window." https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary
- Apple: `.stationary` — "Mission Control doesn't affect the window, so it stays visible and stationary, like the desktop window." https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary (optional; stops the overlay from being shuffled around in Mission Control).
- Apple: `.transient` — "The window floats in Spaces and hides in Mission Control. This is the default behavior if windowLevel isn't equal to normal." https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/transient
- Apple: `.ignoresCycle` keeps it out of Cmd-` cycling. https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/ignorescycle
- Apple: `NSWindow.Level` — "The stacking of levels takes precedence over the stacking of windows within each level." https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct

**What HSTracker does** (`HST:HSTracker/UIs/Trackers/WindowManager.swift#L94-L124`):
- level = `CGWindowLevelForKey(.normalWindow) + 1` — "just above Hearthstone (normal level) but below any system UI level so macOS Notification Center, menu bar, and status items can render above them" (L94-L101).
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` when the "Allow HSTracker to run on fullscreen mode" preference is on (L107-L112); the setting `canJoinFullscreen` defaults to `true` (`HST:HSTracker/Core/Settings.swift#L185-L186`; checkbox label in `HST:HSTracker/UIs/Preferences/Base.lproj/TrackersPreferences.xib#L260`).
- styleMask `[.borderless, .nonactivatingPanel]` when locked (L114-L121); window class is `NSPanel` (`customClass="NSPanel"` in `RootOverlayWindow.xib#L16`).
- Every tooltip panel repeats the pattern and additionally sets `hidesOnDeactivate = false` (`HST:HSTracker/UIs/Tooltips/RelatedCardsTooltipPanel.swift#L423-L437`, `#L463-L469`).
- **Fullscreen transition caveat**: when HS enters/leaves fullscreen it moves to a different Space and "A window that was already shown before the transition doesn't automatically get recomposited into the new Space … An explicit hide+reshow forces the window server to re-evaluate Space membership", followed by `orderFrontRegardless()` (`HST:HSTracker/Logging/Game.swift#L597-L611`). They also listen to `NSWorkspace.activeSpaceDidChangeNotification` (`HST:HSTracker/Logging/CoreManager.swift#L383-L390`; Apple: https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification).

History / user guidance: in 2016 the author said "it's not possible to 'overlay' a fullscreen window. So you have to play Hearthstone in windowed mode" (https://github.com/HearthSim/HSTracker/issues/287); later changelog: "You can play with Hearthstone on fullscreen !" and multiple fullscreen fixes (`HST:CHANGELOG.md#L2619`, `#L2575`, `#L2016`, `#L1527-L1528`). Today no "use windowed mode" guidance is needed; the preference exists as an escape hatch.

**Hearthstone's fullscreen = native macOS fullscreen Space**, not borderless-windowed: AX reports `AXFullScreen = 1` on this machine, and `UnityPlayer.dylib` contains `toggleFullScreen:` (§0). Unity's docs describe `FullScreenWindow` as "borderless full-screen" and, on macOS, `MaximizedWindow` as "a full-screen window with a hidden menu bar and dock" (https://docs.unity3d.com/Manual/PlayerSettings-macOS.html, https://docs.unity3d.com/ScriptReference/FullScreenMode.html) — Unity doesn't document the Spaces mapping, so trust the AX probe.

**Recommended combo for our app:**
```
NSPanel, styleMask [.borderless, .nonactivatingPanel]
level = .normal + 1   (HSTracker)  — or .floating if you must beat other floating palettes
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
hidesOnDeactivate = false, isOpaque = false, backgroundColor = .clear, hasShadow = false
```
Caveats:
- Avoid `.screenSaver`/`.statusBar` levels — they cover Notification Center / menus (HSTracker's rationale above).
- `.canJoinAllSpaces` means the overlay would appear on *every* Space; you must `orderOut` it when HS isn't frontmost (§4) or it will float over the desktop.
- Notch: the fullscreen HS window starts at y=34 below the notch strip on notched MacBooks (§0). Always position from the measured window frame, never from `NSScreen.frame`.
- Stage Manager: `.auxiliary` (macOS 13+) is "for About or Settings windows as well as utility panes" and is mutually exclusive with `.primary`/`.canJoinAllApplications` (https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/auxiliary). Not needed for the overlay; test Stage Manager manually.
- Consider `LSUIElement`/`.accessory` activation policy (no Dock icon/menu bar; https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory) for a pure companion; HSTracker is a regular app and still works, so this is a product choice, not a requirement.

---

## 2. Getting Hearthstone's window frame

### CGWindowListCopyWindowInfo
- Apple: returns per-window dictionaries; "Generating the dictionaries for system windows is a relatively expensive operation … profile your code." https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)
- `kCGWindowBounds`: CGRect dict "in screen space, where the origin is in the upper-left corner of the main display" → decode with `CGRect(dictionaryRepresentation:)` and flip to AppKit's bottom-left coords. https://developer.apple.com/documentation/coregraphics/kcgwindowbounds
- `kCGWindowName`: "(Note that few applications set the Quartz window name.)" https://developer.apple.com/documentation/coregraphics/kcgwindowname
- **Permission**: since 10.15, `kCGWindowName` is withheld unless the app has Screen Recording permission; bounds/owner are not. Sources: https://gist.github.com/chockenberry/164ab2d3dd76736f81c9e9eed63d81bf , https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess/ ; **confirmed on macOS 26.5 here** (§0: bounds present, name absent, preflight false). So: **no Screen Recording needed** if we match by `kCGWindowOwnerPID` (from NSRunningApplication) or owner name, not title.
- Screen Recording is best avoided anyway: macOS 15 re-prompts users periodically for capture permission (monthly) — https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/ , https://mjtsai.com/blog/2024/08/08/sequoia-screen-recording-prompts-and-the-persistent-content-capture-entitlement/ . `CGWindowListCreateImage` is marked `SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)` in the macOS SDK `CGWindow.h` (line 274 of the local CLT SDK) — use ScreenCaptureKit (`SCShareableContent`, `SCWindow.frame`, macOS 12.3+) only if we ever need pixels: https://developer.apple.com/documentation/screencapturekit/scshareablecontent , https://developer.apple.com/documentation/screencapturekit/scwindow/frame . ScreenCaptureKit requires Screen Recording, so don't use it just for frames.
- Screen Recording APIs if needed: `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` (macOS 10.15+): https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess() , https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()

### Accessibility (AXUIElement / AXObserver)
- Requires the user to grant Accessibility; check/prompt with `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- Gives `kAXPositionAttribute`, `kAXSizeAttribute`, and the (string) `"AXFullScreen"` attribute. https://developer.apple.com/documentation/applicationservices/axuielement
- Observers: `AXObserverCreate(pid, cb, &obs)` + `AXObserverAddNotification` + add `AXObserverGetRunLoopSource` to the main run loop. https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate , https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification
- `kAXWindowMovedNotification` / `kAXWindowResizedNotification` are "sent at the end of the … operation, not during it" — so the overlay lags during a drag; acceptable (hide during drag or poll faster). https://developer.apple.com/documentation/applicationservices/kaxwindowmovednotification , https://developer.apple.com/documentation/applicationservices/kaxwindowresizednotification ; `kAXFocusedWindowChangedNotification` https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowchangednotification
- **Not available in a sandbox** (Apple DTS: accessibility privilege is not usable by sandboxed / Mac App Store apps; suggests CGEventTap + Input Monitoring for key events only): https://developer.apple.com/forums/thread/707680 , https://developer.apple.com/forums/thread/749494

### What HSTracker does (`HST:HSTracker/Core/SizeHelper.swift#L29-L126`)
1. `CGWindowListCopyWindowInfo(.excludeDesktopElements)`, filter `kCGWindowOwnerName == "Hearthstone" && kCGWindowLayer == 0 && kCGWindowIsOnscreen == 1`, take the **largest-area** window (L38-L50) — necessary because HS owns several layer-0 helper windows (seen in §0).
2. Then AX on the owner pid: `kAXFocusedWindowAttribute` → `AXFullScreen`, position, size (L52-L86). Comment L58-L59: "kCGWindowBounds can return a stale Mission Control thumbnail rect for some time after MC dismisses; AX reflects HS's actual NSWindow.frame." AX rect is preferred, CG bounds are the fallback when AX fails (L94-L95).
3. Flip Y using `NSScreen.screens.first` (L102-L107; comment warns it "assumes that the first screen in the list is the active one" — a multi-monitor bug to avoid: use the screen containing the window).
4. If AX unavailable, infers fullscreen as "window frame == some NSScreen.frame" (L111-L118) — note this would **fail on notched Macs** since the fullscreen frame is 34 pt shorter than the screen (§0).
5. Asks for Accessibility at launch: `AXIsProcessTrustedWithOptions(prompt: true)` (`HST:HSTracker/AppDelegate.swift#L95-L100`).
6. **Polling, not observers**: GUI loop runs every `guiUpdateDelay = 0.5 s` and re-reads the frame every 4th tick (~2 s) or on any GUI update, re-laying out if frame or fullscreen flag changed (`HST:HSTracker/Logging/Game.swift#L42`, `#L1567-L1596`, `#L224-L226`).

**Recommendation**: CGWindowList by pid (no permission) polled at 4–10 Hz only while HS is frontmost (cheap: one list call; cache window number and use `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` for the hot path), plus AXObserver for moved/resized/fullscreen when Accessibility is granted. Make Accessibility optional ("improves fullscreen/Mission Control accuracy").

---

## 3. Detecting Hearthstone running / frontmost

- Bundle id is **`unity.Blizzard Entertainment.Hearthstone`** (§0). HSTracker matches the same id (`HST:HSTracker/Logging/CoreManager.swift#L491-L494`) but its notification handlers match `localizedName == "Hearthstone"` (L405-L470). Prefer bundle id; the launcher is a different id (`net.battle.bootstrapper`).
- Initial state: `NSWorkspace.shared.runningApplications` (+ `NSRunningApplication.isActive`: "Indicates whether the application is currently frontmost", KVO-observable) https://developer.apple.com/documentation/appkit/nsrunningapplication/isactive ; `NSWorkspace.frontmostApplication` ("the app that receives key events", KVO-compliant) https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication
- Changes: `didLaunchApplicationNotification`, `didTerminateApplicationNotification`, `didActivateApplicationNotification`, `didDeactivateApplicationNotification` on **`NSWorkspace.shared.notificationCenter`** ("If you use a different notification center to register, you won't receive the notification"); userInfo `NSWorkspace.applicationUserInfoKey` → `NSRunningApplication`. https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification . HSTracker registers exactly these five (`HST:HSTracker/Logging/CoreManager.swift#L380-L396`).
- HSTracker also refuses to track if HS runs under Rosetta (`executableArchitecture == x86_64`) because its memory reader needs arm64 (`HST:HSTracker/Logging/CoreManager.swift#L275-L283`). We don't need that (log-only), but it's cheap to warn.
- Build number: HSTracker parses `CFBundleVersion` `a.b.<build>` from the running app's Info.plist on launch (`HST:HSTracker/Logging/CoreManager.swift#L406-L418`); here `36.6.251952` → build 251952.

---

## 4. Hiding when HS is not frontmost; Retina; aspect ratio

**Visibility**: show only when `HS.isActive || ourApp.isActive` (HSTracker's `shouldShowTracker` also keeps the overlay while HSTracker itself is active so you can interact: `HST:HSTracker/Logging/Game.swift#L244-L253`, and `setSelfActivated` handlers `CoreManager.swift#L446-L474`). Use `orderOut`/`orderFront` (or `alphaValue = 0`) on activate/deactivate notifications. Because `NSPanel.hidesOnDeactivate` defaults to `true` ("The default value for NSWindow is false; the default value for NSPanel is true", https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate) and our app is almost never active, set it to `false` or the panel disappears immediately — HSTracker does so on its panels.
- `orderFrontRegardless()` "Moves the window to the front of its level, even if its application isn't active" https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()

**Retina**: work entirely in points. CGWindowList/AX/NSWindow frames are all in points (the probe returned 1710x1073 on a 2x screen). `backingScaleFactor` is only for "rare cases when the explicit scale factor is needed" https://developer.apple.com/documentation/appkit/nsscreen/backingscalefactor . Coordinate flip: `appKitY = primaryScreen.frame.maxY - cgRect.maxY` where primary = `NSScreen.screens[0]` (the display with the menu bar / CG origin), and pick the target screen by intersection for multi-monitor.

**Game-board-relative positioning** (HDT/HSTracker model):
- Current HSTracker root overlay = one full-HS-window SwiftUI canvas, with `scale = geometry.size.height / 1080` and a virtual canvas width `geometry.size.width / scale` — all elements authored on a 1080-high reference (`HST:HSTracker/UIs/Overlay/Root/RootOverlayView.swift#L146-L155`; tooltip note "HDT's vm.Scale = Height / 1080" `RelatedCardsTooltipPanel.swift#L452-L457`).
- Hearthstone renders the board as a centered **4:3** region; width beyond that is decorative. HSTracker's `screenRatio = (4/3) / (w/h)` and `getScaledXPos(left, width, ratio) = width*ratio*left + width*(1-ratio)/2` map a 0–1 x-fraction inside the 4:3 board to window x; y is `fraction * height` (`HST:HSTracker/Core/SizeHelper.swift#L205-L211`, `#L247-L262`, examples L264-L308). `hearthstoneBoardWidth = height * 1.5` (L205-L207) is used for wider (3:2) BG-era layout.
- Windowed mode: subtract title-bar height (`titlebarHeight`) when not fullscreen (L134-L139); tracker frames also offset 50 pt for the game menu when windowed (L233-L243).
- Guard against NaN when the window is degenerate — HSTracker notes a NaN reaching a SwiftUI layout modifier "traps the process" (L249-L261).

---

## 5. Click-through vs interactive regions; non-activating

- `ignoresMouseEvents` is **per-window**: "whether the window is transparent to mouse events." https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents
- `.nonactivatingPanel`: "a panel … that does not activate the owning app" — clicks on it won't steal focus from Hearthstone. https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- `canBecomeKey` is true only "if the window has a title bar or a resize bar" — a borderless panel can't become key unless you subclass and override (only do so for text fields). https://developer.apple.com/documentation/appkit/nswindow/canbecomekey ; `isFloatingPanel` guidance https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel
- **HSTracker's hit-testing trick** (`HST:HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift#L28-L119`): one full-window `NSHostingView`, `ignoresMouseEvents = true` by default; SwiftUI children publish their frames via an `InteractiveRegionPreferenceKey`; a **global** `NSEvent` `.mouseMoved` monitor (fires while the cursor is over HS) plus a **local** monitor (fires once the window receives events) plus a 150 ms backstop timer compare `NSEvent.mouseLocation` with those rects and flip `ignoresMouseEvents` only while the cursor is inside an interactive rect. Hover effects over click-through areas are driven from the same cursor tracking because SwiftUI `.onHover` never fires while the window ignores mouse events (L100-L106, L122-L135).
  - Apple: global monitors receive "copies of events the system posts to other applications"; mouse-moved is allowed without special privilege, key events need Accessibility trust. https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
- Simpler alternative: **separate small panels** for interactive widgets (each with `ignoresMouseEvents = false`) and one big click-through panel for passive visuals. Fewer moving parts; HSTracker moved *from* many windows *to* one root canvas for layout parity with HDT, not because multiple windows fail.
- Locked vs unlocked: HSTracker sets `ignoresMouseEvents = Settings.windowsLocked` and adds `.titled/.resizable` when unlocked so users can drag (`HST:HSTracker/UIs/Trackers/OverWindowController.swift#L30-L34`, `WindowManager.swift#L114-L121`).

---

## 6. Tailing growing log files

Options:
- **DispatchSource file-system object (kqueue vnode)**: `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)` with `.extend`/`.write`/`.delete`/`.rename`; source starts inactive, call `activate()`. https://developer.apple.com/documentation/dispatch/dispatchsource/makefilesystemobjectsource(filedescriptor:eventmask:queue:) , event set https://developer.apple.com/documentation/dispatch/dispatchsource/filesystemevent . Lowest latency, zero CPU when idle, one fd per file. Must handle delete/rename by reopening. Can also open the **Logs directory** fd and watch `.write` to detect a new `Hearthstone_*` session directory.
- **FSEvents**: directory-hierarchy notifications, with `kFSEventStreamCreateFlagFileEvents` for per-file events ("Use this flag with care as it will generate significantly more events"). https://developer.apple.com/documentation/coreservices/file_system_events , https://developer.apple.com/documentation/coreservices/1455376-fseventstreamcreateflags/kfseventstreamcreateflagfileevents . Coalesced with a latency parameter; good for "new session dir appeared", overkill for tailing.
- **Polling**: what both HearthSim trackers do.
  - HSTracker: one thread per log, loop `seek(offset) → read to EOF → split lines → Thread.sleep(0.05 s)`; reopen if the handle fails or file disappears; start offset found by scanning backwards in 4 KB blocks for an entry point (`HST:HSTracker/Logging/LogReaderManager.swift#L16`, `HST:HSTracker/Logging/LogReader.swift#L92-L162`, `#L215-L260`). It deletes stale log files not open by HS using `proc_listpidspath` (`HST:HSTracker/Utility/FileUtils.m#L15-L60`, `LogReader.swift#L28-L43`).
  - HSTracker gets the session directory from **HearthMirror memory reading** (`MirrorHelper.getLogSessionDir()`, `HST:HSTracker/Logging/CoreManager.swift#L286-L296`), which is why it needs `com.apple.security.cs.debugger` etc. (§7). We should not copy that.
  - HDT (Windows) instead picks the newest subdirectory of `Logs` by creation time, re-checked at most every 5 s, and treats it as active only if a file in it can't be moved (locked by HS); polls every 100 ms. https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogReader/LogFileWatcher.cs#L36-L94 , `UpdateDelay = 100` https://github.com/HearthSim/Hearthstone-Deck-Tracker/blob/ef8ab6e8380a647d757eec203d310395d6b97ae0/HearthWatcher/LogWatcher.cs#L15
- **Recommendation**: newest `Logs/Hearthstone_YYYY_MM_DD_HH_MM_SS` dir (name sorts lexicographically = chronologically; confirm with creation date; on macOS "is HS writing it" can be checked with `proc_listpidspath` like HSTracker). Watch `Logs/` with a DispatchSource (or FSEvents) for new session dirs + on `didLaunchApplication`. Tail `Power.log` with a DispatchSource `.extend|.write|.delete|.rename` **plus** a slow safety poll (e.g. 250 ms–1 s) because vnode events can be missed across reopen/rename; keep a byte offset and only consume up to the last `\n` (buffer partial lines — HSTracker counts bytes per kept line, which is fragile). Detect truncation (`size < offset` → reset). Power.log grew ~660 KB in 2 minutes of menus, so parse incrementally on a background queue.
- log.config: HSTracker writes missing zones to `~/Library/Preferences/Blizzard/Hearthstone/log.config` (`HST:HSTracker/Logging/CoreManager.swift#L135-L240`, path `#L482-L485`; Power requires `Verbose=true`) and also writes `client.config` = `[Log]\nFileSizeLimit.Int=-1` in the Hearthstone install dir to lift the log size cap, notifying "restart required" if it had to change it (`HST:HSTracker/Utility/Helper.swift#L59-L79`, called from `CoreManager.swift#L419-L421`). No `client.config` exists here yet.

---

## 7. Distribution: sandbox vs Developer ID

Needs: read `/Applications/Hearthstone/Logs/**`, write `~/Library/Preferences/Blizzard/Hearthstone/log.config`, ideally write `/Applications/Hearthstone/client.config`, window frame (CGWindowList; AX optional).

**Mac App Store / App Sandbox is a poor fit:**
- MAS requires sandboxing (Guideline 2.4.5(i)) and forbids non-MAS updaters (2.4.5(vii)). https://developer.apple.com/app-store/review/guidelines/
- Access outside the container requires user-selected files/security-scoped bookmarks or temporary exceptions. https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- Temporary exceptions exist — `com.apple.security.temporary-exception.files.absolute-path.read-only` (for `/Applications/Hearthstone/Logs/`) and `…files.home-relative-path.read-write` (for `/Library/Preferences/Blizzard/Hearthstone/`) — but must be justified in App Store Connect and are discretionary. https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html
- Security-scoped bookmarks would work (user picks the Hearthstone folder once via NSOpenPanel, store bookmark), but `~/Library/Preferences` is awkward to ask users to pick and `/Applications/Hearthstone` writes may be refused.
- **Accessibility API unavailable to sandboxed apps** (§2). CGWindowList bounds likely still work in a sandbox (not verified here).
- Net: MAS is possible only in a degraded form (bookmark-picked folder, no AX, no client.config) with review risk. Not recommended.

**Recommended: Developer ID + Hardened Runtime + notarization, distributed as DMG/ZIP, Sparkle 2 for updates.**
- Hardened Runtime is required for notarization; add exception entitlements only if needed. https://developer.apple.com/documentation/security/hardened-runtime . A log-reading overlay needs **none** of HSTracker's exceptions: HSTracker's entitlements are `cs.allow-dyld-environment-variables`, `cs.allow-jit`, `cs.debugger`, `cs.disable-library-validation` (for memory reading / its Mono bridge) (`HST:HSTracker/HSTracker.entitlements`), with `ENABLE_HARDENED_RUNTIME = YES`, no sandbox, deployment target 10.15 (`HST:HSTracker.xcodeproj/project.pbxproj`, lines ~9027-9160). It also warns users that memory reading "needs elevated privileges … If macOS asks you for your system password" (`HST:HSTracker/AppDelegate.swift#L103-L112`).
- Notarize with `notarytool` (altool/Xcode ≤13 no longer accepted since 2023-11-01), then staple. https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Sparkle 2: `generate_keys` (EdDSA, private key in Keychain), `SUFeedURL` + `SUPublicEDKey` in Info.plist, `generate_appcast`, HTTPS feed. https://sparkle-project.org/documentation/ . HSTracker uses Sparkle via SPM with `SUFeedURL https://hsdecktracker.net/hstracker/appcast2.xml`, `SUPublicEDKey`, automatic checks on, auto-update off (`HST:HSTracker/Info.plist`).
- Permissions UX: none required for core features (logs + CGWindowList bounds). Optional Accessibility (better fullscreen/move tracking). Do not require Screen Recording.

---

## 8. SwiftUI vs AppKit for the overlay; minimum macOS

- Use **AppKit for the window shell** (NSPanel subclass: style, level, collection behavior, `ignoresMouseEvents`, ordering) and **SwiftUI for content** via `NSHostingView` ("An AppKit view that hosts a SwiftUI view hierarchy … The hosting view also coordinates event delivery", macOS 10.15+). https://developer.apple.com/documentation/swiftui/nshostingview . SwiftUI `Window`/`WindowGroup` scenes don't expose nonactivating panels/levels cleanly; HSTracker uses exactly this hybrid (`contentView = NSHostingView(...)`, `HST:HSTracker/UIs/Overlay/Root/RootOverlayWindow.swift#L25-L40`, `RelatedCardsTooltipPanel.swift#L436`).
- Performance notes: keep the hosting view transparent (`isOpaque = false`, `backgroundColor = .clear`); avoid re-publishing the whole model on every log line — batch updates to the main actor (HSTracker coalesces GUI updates on a 0.5 s loop, `Game.swift#L242-L253`, `#L1567-L1596`); use `@Observable` (macOS 14+) for fine-grained invalidation; avoid continuous animations/blur over a full-screen transparent window (compositing cost over a 60 fps game); guard geometry against NaN/Inf (HSTracker's crash note, `SizeHelper.swift#L249-L261`).
- **Minimum macOS**: Hearthstone itself requires 12.0 (§0). Recommend **macOS 14 Sonoma** as the floor (Observation framework, mature SwiftUI on macOS, `SCREEN_CAPTURE` APIs not needed) — or 15 if you want to target only current Sequoia/Tahoe users and test less. Test matrix: 14, 15, 26 on Apple Silicon; notched and non-notched displays; windowed and native fullscreen; Stage Manager on/off; multi-monitor.

---

## Quick answers

1. Yes: NSPanel `[.borderless, .nonactivatingPanel]`, level `.normal+1`, `[.canJoinAllSpaces, .fullScreenAuxiliary]` (+ `.stationary`, `.ignoresCycle`), `hidesOnDeactivate=false`; hide+reshow on fullscreen transitions. HS uses native macOS fullscreen by default; no "play windowed" guidance needed today.
2. CGWindowList bounds/owner/pid need no permission (verified 26.5), names do (Screen Recording). AX needs Accessibility, gives fullscreen flag and non-stale frame; HSTracker = CGWindowList pick-largest + AX, polled ~2 s.
3. Bundle id `unity.Blizzard Entertainment.Hearthstone`, universal arm64 native; NSWorkspace launch/terminate/activate/deactivate + activeSpaceDidChange.
4. Show only when HS (or us) is active; points not pixels; 4:3 centered board math `(4/3)/(w/h)`, 1080-high reference scaling.
5. Window-level `ignoresMouseEvents`; toggle by cursor-in-interactive-rect via global+local mouseMoved monitors, or split into separate panels; nonactivating panels keep HS focused.
6. HSTracker/HDT poll (50/100 ms). Recommend DispatchSource vnode + slow backup poll; newest `Logs/Hearthstone_*` session dir.
7. Developer ID + hardened runtime (no exception entitlements) + notarytool + Sparkle 2; MAS only in degraded form (temp exceptions/bookmarks, no AX).
8. AppKit NSPanel shell + SwiftUI via NSHostingView; min macOS 14.
