import TavernEngine
import Testing

/// The menu-bar status for the live states, from what the app knows at that moment.
@Suite("Menu-bar live status")
struct LiveStatusTests {
    static func inGame(turn: Int, over: Bool = false) -> ViewState {
        ViewState(
            status: over ? .gameOver : .inGame,
            game: GameView(gameType: "GT_BATTLEGROUNDS", localPlayerID: 6, localHeroCardID: nil, bgTurn: turn)
        )
    }

    @Test("Waiting, restart required and tracking read as the player expects")
    func titles() {
        func status(running: Bool = true, restart: Bool = false, following: Bool = true, view: ViewState = .noGame, scene: String? = nil) -> String {
            LiveStatus(hearthstoneRunning: running, restartRequired: restart, followingSession: following, view: view, scene: scene).title
        }
        #expect(status(running: false) == "Waiting for Hearthstone")
        #expect(status(running: false, restart: true) == "Waiting for Hearthstone")
        #expect(status(following: false) == "Waiting for Hearthstone logs")
        #expect(status(restart: true, view: Self.inGame(turn: 6)) == "Restart Hearthstone required")
        #expect(status() == "Watching Hearthstone — no Battlegrounds game")
        #expect(status(scene: "BACON") == "In the Battlegrounds lobby")
        #expect(status(view: Self.inGame(turn: 0)) == "Tracking game — hero pick")
        #expect(status(view: Self.inGame(turn: 6)) == "Tracking game — Turn 6")
        #expect(status(view: Self.inGame(turn: 12, over: true)) == "Game over — Turn 12")
    }

    @Test("A replayed game drives the tracking status turn by turn")
    func followsReplay() {
        var engine = TavernEngine()
        var titles: [String] = []
        for line in SyntheticLog.soloGame(bgTurns: 2).lines {
            engine.ingest(line)
            let title = LiveStatus(hearthstoneRunning: true, restartRequired: false, followingSession: true, view: engine.state, scene: engine.scene).title
            if titles.last != title { titles.append(title) }
        }
        #expect(titles == [
            "Watching Hearthstone — no Battlegrounds game",
            "Tracking game — hero pick",
            "Tracking game — Turn 1",
            "Tracking game — Turn 2",
            "Game over — Turn 2",
        ])
    }

    @Test("LoadingScreen lines set the scene without changing the view state")
    func scene() {
        var engine = TavernEngine()
        engine.ingestLoadingScreen("D 20:33:52.2481480 LoadingScreen.OnSceneLoaded() - prevMode=HUB currMode=BACON")
        #expect(engine.scene == "BACON")
        engine.ingestLoadingScreen("D 20:34:31.5459560 LoadingScreen.OnScenePreUnload() - prevMode=BACON nextMode=GAMEPLAY m_phase=INVALID")
        #expect(engine.scene == "BACON")
        engine.ingestLoadingScreen("D 20:34:33.0 LoadingScreen.OnSceneLoaded() - prevMode=BACON currMode=GAMEPLAY")
        #expect(engine.scene == "GAMEPLAY")
        #expect(engine.state == .noGame)
        #expect(engine.timeline.isEmpty)
    }
}
