import Foundation
import Testing
@testable import HSData

@Suite struct OverrideLoadingTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "overrides-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func poolOverridesReportMalformedFileAsSkipped() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"patch":"1.0","valid_from":"2026-01-01T00:00:00Z"}"#.utf8).write(to: dir.appending(path: "a.json"))
        try Data("{ not json".utf8).write(to: dir.appending(path: "b.json"))

        let report = PoolOverrides.loadReport(directory: dir)
        #expect(report.loaded.map(\.patch) == ["1.0"])
        #expect(report.skipped.map(\.file) == ["b.json"])
        #expect(PoolOverrides.load(directory: dir).count == 1)
    }

    @Test func buildOverridesReportMalformedFileAsSkipped() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"patch":"1.0","valid_from":"2026-01-01T00:00:00Z"}"#.utf8).write(to: dir.appending(path: "a.json"))
        try Data(#"{"patch":"2.0"}"#.utf8).write(to: dir.appending(path: "b.json"))

        let report = BuildOverrides.loadReport(directory: dir)
        #expect(report.loaded.map(\.patch) == ["1.0"])
        #expect(report.skipped.map(\.file) == ["b.json"])
    }
}
