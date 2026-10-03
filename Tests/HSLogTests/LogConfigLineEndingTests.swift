import Foundation
import HSLog
import Testing

@Suite("client.config line endings")
struct LogConfigLineEndingTests {
    @Test("A CRLF client.config stays CRLF when the size cap is added")
    func crlfPreserved() throws {
        let install = try TemporaryInstall()
        let file = install.locations.clientConfigFile
        try install.write("[Graphics]\r\nQuality=2\r\n\r\n[Log]\r\nFileSizeLimit.Int=10000\r\n", to: file)
        var setup = LogSetup(locations: install.locations)
        #expect(setup.check(hearthstoneRunning: false).clientConfig == .repaired)
        let bytes = Array(try #require(install.read(file)).utf8)
        let expected = Array("[Graphics]\r\nQuality=2\r\n\r\n[Log]\r\nFileSizeLimit.Int=-1\r\n".utf8)
        #expect(bytes == expected)
    }

    @Test("A CRLF client.config without a [Log] section gets one appended with CRLF")
    func crlfAppendedSection() throws {
        let install = try TemporaryInstall()
        let file = install.locations.clientConfigFile
        try install.write("[Graphics]\r\nQuality=2\r\n", to: file)
        var setup = LogSetup(locations: install.locations)
        #expect(setup.check(hearthstoneRunning: false).clientConfig == .repaired)
        let bytes = Array(try #require(install.read(file)).utf8)
        #expect(bytes == Array("[Graphics]\r\nQuality=2\r\n\r\n[Log]\r\nFileSizeLimit.Int=-1\r\n".utf8))
    }
}
