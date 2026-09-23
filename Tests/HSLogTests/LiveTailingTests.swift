import Foundation
import HSLog
import Testing

/// Live following of the session folder and its logs, on a temporary tree.
/// Every wait is bounded by the one-second tracking latency the app promises.
@Suite("Live log following", .serialized)
struct LiveTailingTests {
    static let utc = TimeZone(identifier: "UTC")!

    private func follower(_ install: TemporaryInstall, launchDate: Date? = nil, recorder: EventRecorder) -> LogSessionFollower {
        LogSessionFollower(
            logsDirectory: install.locations.logsDirectory,
            launchDate: launchDate,
            timeZone: Self.utc,
            handler: { recorder.record($0) }
        )
    }

    @Test("An existing log is caught up from the start, then new lines arrive within a second")
    func catchUpThenTail() async throws {
        let install = try TemporaryInstall()
        let session = try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        let power = session.appending(path: LogFileName.power)
        try install.append("D 21:08:40.0 line 1\nD 21:08:40.1 line 2\n", to: power)

        let recorder = EventRecorder()
        let follower = follower(install, recorder: recorder)
        follower.start()
        defer { follower.stop() }

        #expect(await recorder.wait { $0.lines(of: LogFileName.power).count == 2 })
        #expect(recorder.sessions == ["Hearthstone_2026_09_22_21_08_40"])

        try install.append("D 21:08:41.0 line 3\n", to: power)
        #expect(await recorder.wait { $0.lines(of: LogFileName.power).count == 3 })
        #expect(recorder.lines(of: LogFileName.power).last == "D 21:08:41.0 line 3")
    }

    @Test("A line cut mid-write (even mid-character) is held until its newline arrives")
    func partialLines() async throws {
        let install = try TemporaryInstall()
        let session = try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        let power = session.appending(path: LogFileName.power)
        let recorder = EventRecorder()
        let follower = follower(install, recorder: recorder)
        follower.start()
        defer { follower.stop() }
        #expect(await recorder.wait { $0.sessions.count == 1 })

        let name = Array("Entity=Jörmungandr#1234\r\n".utf8)
        let cut = name.firstIndex(of: 0xC3)! + 1  // inside the two-byte "ö"
        try install.append(Array("D 1 TAG_CHANGE ".utf8) + name[..<cut], to: power)
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.lines(of: LogFileName.power).isEmpty)

        try install.append(Array(name[cut...]) + Array("D 2 bad \u{FF}".utf8) + [0xFF] + Array("byte\n".utf8), to: power)
        #expect(await recorder.wait { $0.lines(of: LogFileName.power).count == 2 })
        let lines = recorder.lines(of: LogFileName.power)
        #expect(lines.first == "D 1 TAG_CHANGE Entity=Jörmungandr#1234")
        #expect(lines.last?.hasPrefix("D 2 bad") == true)
        #expect(lines.last?.hasSuffix("byte") == true)
    }

    @Test("A new session folder (Hearthstone restarted) is picked up within a second")
    func switchesToNewSession() async throws {
        let install = try TemporaryInstall()
        let first = try install.makeSession("Hearthstone_2026_09_22_20_33_28")
        try install.append("old session\n", to: first.appending(path: LogFileName.power))

        let recorder = EventRecorder()
        let follower = follower(install, recorder: recorder)
        follower.start()
        defer { follower.stop() }
        #expect(await recorder.wait { $0.lines(of: LogFileName.power) == ["old session"] })

        let second = try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        #expect(await recorder.wait { $0.sessions.last == "Hearthstone_2026_09_22_21_08_40" })
        try install.append("new power\n", to: second.appending(path: LogFileName.power))
        try install.append("D 21:08:52 LoadingScreen.OnSceneLoaded() - prevMode=HUB currMode=BACON\n", to: second.appending(path: LogFileName.loadingScreen))
        #expect(await recorder.wait {
            $0.lines(of: LogFileName.power) == ["new power"] && $0.lines(of: LogFileName.loadingScreen).count == 1
        })
        // The old session is no longer followed.
        try install.append("late old line\n", to: first.appending(path: LogFileName.power))
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.lines(of: LogFileName.power) == ["new power"])
        #expect(recorder.sessions == ["Hearthstone_2026_09_22_20_33_28", "Hearthstone_2026_09_22_21_08_40"])
    }

    @Test("A client launched after the newest folder waits for its own folder")
    func waitsForLaunchFolder() async throws {
        let install = try TemporaryInstall()
        try install.makeSession("Hearthstone_2026_09_22_20_33_28")
        let launch = try #require(LogSession(directory: URL(filePath: "/Hearthstone_2026_09_22_21_08_40"), timeZone: Self.utc)).started

        let recorder = EventRecorder()
        let follower = follower(install, launchDate: launch, recorder: recorder)
        follower.start()
        defer { follower.stop() }
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.sessions.isEmpty)

        try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        #expect(await recorder.wait { $0.sessions == ["Hearthstone_2026_09_22_21_08_40"] })
    }

    @Test("The Logs folder may not exist when following starts")
    func logsFolderAppearsLater() async throws {
        let install = try TemporaryInstall()
        let recorder = EventRecorder()
        let follower = follower(install, recorder: recorder)
        follower.start()
        defer { follower.stop() }
        try await Task.sleep(for: .milliseconds(300))

        let session = try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        try install.append("first\n", to: session.appending(path: LogFileName.power))
        #expect(await recorder.wait { $0.lines(of: LogFileName.power) == ["first"] })
    }

    @Test("A truncated or replaced log is read again from its start")
    func truncationAndReplacement() async throws {
        let install = try TemporaryInstall()
        let session = try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        let power = session.appending(path: LogFileName.power)
        try install.append("one\ntwo\nthree\n", to: power)
        let recorder = EventRecorder()
        let follower = follower(install, recorder: recorder)
        follower.start()
        defer { follower.stop() }
        #expect(await recorder.wait { $0.lines(of: LogFileName.power).count == 3 })

        // Truncated in place.
        let handle = try FileHandle(forWritingTo: power)
        try handle.truncate(atOffset: 0)
        try handle.close()
        try install.append("four\n", to: power)
        #expect(await recorder.wait { $0.lines(of: LogFileName.power).last == "four" })

        // Deleted and written anew (a different file at the same path).
        try FileManager.default.removeItem(at: power)
        try install.append("five\n", to: power)
        #expect(await recorder.wait { $0.lines(of: LogFileName.power).last == "five" })
        #expect(recorder.lines(of: LogFileName.power) == ["one", "two", "three", "four", "five"])
    }

    @Test("No events arrive after stop")
    func stopEndsDelivery() async throws {
        let install = try TemporaryInstall()
        let session = try install.makeSession("Hearthstone_2026_09_22_21_08_40")
        let power = session.appending(path: LogFileName.power)
        let recorder = EventRecorder()
        let follower = follower(install, recorder: recorder)
        follower.start()
        #expect(await recorder.wait { $0.sessions.count == 1 })
        follower.stop()
        try install.append("after stop\n", to: power)
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.lines(of: LogFileName.power).isEmpty)
    }
}

@Suite("LoadingScreen scene lines")
struct LoadingScreenLineTests {
    @Test("Scene loads and unloads are recognised; other lines aren't")
    func parse() {
        #expect(LoadingScreenEvent(line: "D 20:33:52.2481480 LoadingScreen.OnSceneLoaded() - prevMode=HUB currMode=BACON")
            == .sceneLoaded(previous: "HUB", current: "BACON"))
        #expect(LoadingScreenEvent(line: "D 20:34:31.5459560 LoadingScreen.OnScenePreUnload() - prevMode=BACON nextMode=GAMEPLAY m_phase=INVALID")
            == .sceneUnloading(previous: "BACON", next: "GAMEPLAY"))
        #expect(LoadingScreenEvent(line: "D 20:33:35.5623690 LoadingScreen.OnSceneLoaded() - m_assetLoadStartTimestamp=5250943222583012114") == nil)
        #expect(LoadingScreenEvent(line: "D 20:34:33.15 MulliganManager.HandleGameStart() - IsPastBeginPhase()=False") == nil)
    }
}
