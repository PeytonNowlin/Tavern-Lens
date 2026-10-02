import Foundation
import Testing
@testable import SimulatorRuntime

@Suite struct SimulatorResourcesTests {
    @Test func missingAppBundleThrowsInsteadOfTouchingBundleModule() throws {
        let resources = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString)")
        var touchedModule = false
        #expect(throws: SimulatorResources.ResourceError.bundleMissing(resources.appending(path: SimulatorResources.bundleName))) {
            try SimulatorResources.resolveBundle(mainResourceURL: resources, isApp: true) {
                touchedModule = true
                return Bundle.main
            }
        }
        #expect(!touchedModule)
    }

    @Test func nonAppFallsBackToModuleBundle() throws {
        let resources = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString)")
        let bundle = try SimulatorResources.resolveBundle(mainResourceURL: resources, isApp: false) { Bundle.main }
        #expect(bundle == Bundle.main)
    }

    @Test func realResourcesLoad() throws {
        #expect(try !SimulatorResources.script().isEmpty)
        #expect(try !SimulatorResources.cardsJSON().isEmpty)
    }
}
