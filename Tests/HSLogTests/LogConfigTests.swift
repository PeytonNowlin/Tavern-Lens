import Foundation
import HSLog
import Testing

@Suite("Log config repair and the restart-required signal")
struct LogConfigTests {
    /// The log.config found on this Mac during research: every section verbose, Zone included.
    static let researchLogConfig = ["Power", "LoadingScreen", "Zone", "Achievements", "Gameplay", "FullScreenFX", "Decks"]
        .map { "[\($0)]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\nVerbose=true\n" }
        .joined()

    @Test("Missing configs are created with only Power (verbose) and LoadingScreen, and the size cap lifted")
    func createsMissing() throws {
        let install = try TemporaryInstall()
        var setup = LogSetup(locations: install.locations)
        let report = setup.check(hearthstoneRunning: false)

        #expect(report.logConfig == .created)
        #expect(report.clientConfig == .created)
        let logConfig = try #require(install.read(install.locations.logConfigFile))
        #expect(logConfig.contains("[Power]"))
        #expect(logConfig.contains("[LoadingScreen]"))
        #expect(!logConfig.contains("[Zone]"))
        let power = try #require(logConfig.components(separatedBy: "[LoadingScreen]").first)
        #expect(power.contains("Verbose=true"))
        #expect(install.read(install.locations.clientConfigFile) == "[Log]\nFileSizeLimit.Int=-1\n")
        // Fixed before the client launched: its launch will read the new files.
        #expect(!setup.restartRequired)
    }

    @Test("A repair while Hearthstone runs requires a restart until it quits")
    func restartRequired() throws {
        let install = try TemporaryInstall()
        var setup = LogSetup(locations: install.locations)
        setup.check(hearthstoneRunning: true)
        #expect(setup.restartRequired)

        // Checking again finds nothing to fix, but the running client still has the old config.
        let again = setup.check(hearthstoneRunning: true)
        #expect(again.logConfig == .correct && again.clientConfig == .correct)
        #expect(setup.restartRequired)

        setup.hearthstoneTerminated()
        #expect(!setup.restartRequired)
        // The relaunch reads the good config.
        setup.check(hearthstoneRunning: true)
        #expect(!setup.restartRequired)
    }

    @Test("Correct configs are left alone and need no restart")
    func correctUntouched() throws {
        let install = try TemporaryInstall()
        // Same settings as ours, written differently: other order, case, spacing, CRLF.
        try install.write(
            "[LoadingScreen]\r\nVerbose=False\r\nLogLevel = 1\r\nFilePrinting=True\r\nConsolePrinting=false\r\nScreenPrinting=false\r\n\r\n"
                + "[power]\r\nLogLevel=1\r\nFilePrinting=true\r\nConsolePrinting=false\r\nScreenPrinting=false\r\nVerbose=TRUE\r\n",
            to: install.locations.logConfigFile
        )
        try install.write("[Graphics]\nQuality=2\n\n[Log]\nFileSizeLimit.Int = -1\n", to: install.locations.clientConfigFile)
        let before = install.read(install.locations.logConfigFile)

        var setup = LogSetup(locations: install.locations)
        let report = setup.check(hearthstoneRunning: true)
        #expect(report.logConfig == .correct)
        #expect(report.clientConfig == .correct)
        #expect(!report.changedAnything)
        #expect(!setup.restartRequired)
        #expect(install.read(install.locations.logConfigFile) == before)
    }

    @Test("A verbose LoadingScreen section is fine as it is")
    func verboseLoadingScreenAccepted() throws {
        let install = try TemporaryInstall()
        try install.write(
            "[Power]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\nVerbose=true\n\n"
                + "[LoadingScreen]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\nVerbose=true\n",
            to: install.locations.logConfigFile
        )
        try install.write("[Log]\nFileSizeLimit.Int=-1", to: install.locations.clientConfigFile)
        var setup = LogSetup(locations: install.locations)
        let report = setup.check(hearthstoneRunning: true)
        #expect(report.logConfig == .correct && report.clientConfig == .correct)
        #expect(!setup.restartRequired)
    }

    @Test("Extra sections such as Zone are removed in place, with no extra file in Hearthstone's folder")
    func extraSectionsRepaired() throws {
        let install = try TemporaryInstall()
        try install.write(Self.researchLogConfig, to: install.locations.logConfigFile)
        var setup = LogSetup(locations: install.locations)
        #expect(setup.check(hearthstoneRunning: false).logConfig == .repaired)

        let repaired = try #require(install.read(install.locations.logConfigFile))
        #expect(!repaired.contains("[Zone]"))
        let folder = install.locations.logConfigFile.deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(files.filter { !$0.hasPrefix(".") } == [install.locations.logConfigFile.lastPathComponent], "\(files)")

        // A later repair rewrites it again, still alone.
        try install.write("[Power]\nVerbose=false\n", to: install.locations.logConfigFile)
        #expect(setup.check(hearthstoneRunning: false).logConfig == .repaired)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).filter { !$0.hasPrefix(".") }
            == [install.locations.logConfigFile.lastPathComponent])
    }

    @Test(
        "A wrong Power or LoadingScreen section is repaired",
        arguments: [
            "[Power]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\nVerbose=false\n[LoadingScreen]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\nVerbose=false\n",
            "[Power]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\nVerbose=true\n",
            "[Power]\nLogLevel=1\nFilePrinting=false\nConsolePrinting=false\nScreenPrinting=false\nVerbose=true\n[LoadingScreen]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=false\nVerbose=false\n",
            "[Power]\nLogLevel=1\nFilePrinting=true\nConsolePrinting=false\nScreenPrinting=true\nVerbose=true\n[LoadingScreen]\nLogLevel=1\nFilePrinting=true\n",
            "",
            "garbage \u{FFFD}\n",
        ]
    )
    func wrongLogConfig(contents: String) throws {
        let install = try TemporaryInstall()
        try install.write(contents, to: install.locations.logConfigFile)
        var setup = LogSetup(locations: install.locations)
        #expect(setup.check(hearthstoneRunning: true).logConfig == .repaired)
        #expect(setup.restartRequired)
        #expect(setup.check(hearthstoneRunning: true).logConfig == .correct)
    }

    @Test("client.config gets the unlimited size cap and keeps its other settings")
    func clientConfigPreserved() throws {
        let install = try TemporaryInstall()
        let file = install.locations.clientConfigFile

        try install.write("[Graphics]\nQuality=2\n\n[Log]\nFileSizeLimit.Int=10000\nOther=1\n", to: file)
        var setup = LogSetup(locations: install.locations)
        #expect(setup.check(hearthstoneRunning: false).clientConfig == .repaired)
        #expect(install.read(file) == "[Graphics]\nQuality=2\n\n[Log]\nFileSizeLimit.Int=-1\nOther=1\n")

        try install.write("[Graphics]\nQuality=2\n\n[Aurora]\nEnv=us\n", to: file)
        #expect(setup.check(hearthstoneRunning: false).clientConfig == .repaired)
        #expect(install.read(file) == "[Graphics]\nQuality=2\n\n[Aurora]\nEnv=us\n\n[Log]\nFileSizeLimit.Int=-1\n")

        try install.write("[Log]\nOther=1\n\n[Graphics]\nQuality=2\n", to: file)
        #expect(setup.check(hearthstoneRunning: false).clientConfig == .repaired)
        #expect(install.read(file) == "[Log]\nOther=1\nFileSizeLimit.Int=-1\n\n[Graphics]\nQuality=2\n")
        #expect(setup.check(hearthstoneRunning: false).clientConfig == .correct)
    }

    @Test("Without a Hearthstone install, client.config is reported as failed and log.config is still fixed")
    func notInstalled() throws {
        let install = try TemporaryInstall(installed: false)
        var setup = LogSetup(locations: install.locations)
        let report = setup.check(hearthstoneRunning: false)
        #expect(report.logConfig == .created)
        guard case .failed = report.clientConfig else {
            Issue.record("Expected a failure, got \(report.clientConfig)")
            return
        }
        #expect(report.failures.count == 1)
        #expect(!install.exists(install.locations.installDirectory))
    }
}
