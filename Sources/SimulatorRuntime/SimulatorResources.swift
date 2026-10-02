import Foundation
import GzipSupport

/// The bundled simulator and its pinned card data (Sources/SimulatorRuntime/Resources).
///
/// Both are produced by `scripts/update-simulator.sh`, which refuses a new simulator
/// version unless the golden odds tests pass with it:
/// - `bgs-simulator.js`: `@firestone-hs/simulate-bgs-battle` bundled with esbuild for JavaScriptCore.
/// - `bgs-simulator.pin.json`: the package versions in the bundle.
/// - `simulator-cards.json.gz`: Firestone's card DB (cards_enUS), trimmed to the Battlegrounds
///   cards and the fields the simulator reads. It is pinned with the simulator rather than
///   downloaded, so the app never fetches from Firestone's servers, and tests need no network.
public enum SimulatorResources {
    /// The versions in the bundle.
    public struct Pin: Codable, Hashable, Sendable {
        public var simulator: String
        public var referenceData: String
        public var esbuild: String
    }

    /// The resources can't be found, so the simulator can't run.
    public enum ResourceError: Error, Equatable, CustomStringConvertible {
        /// The app's copied resource bundle is missing from `Contents/Resources`.
        case bundleMissing(URL)

        public var description: String {
            switch self {
            case .bundleMissing(let url): "Simulator resource bundle is missing: \(url.path(percentEncoded: false))"
            }
        }
    }

    static let bundleName = "TavernLens_SimulatorRuntime.bundle"

    public static var scriptURL: URL { get throws { try url("bgs-simulator", "js") } }
    public static var cardsURL: URL { get throws { try url("simulator-cards.json", "gz") } }

    public static var pin: Pin? {
        (try? url("bgs-simulator.pin", "json")).flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Pin.self, from: $0) }
    }

    /// The bundled script's source.
    public static func script() throws -> String {
        try String(contentsOf: scriptURL, encoding: .utf8)
    }

    /// The pinned card DB, decompressed: Firestone's JSON array of cards.
    public static func cardsJSON() throws -> Data {
        try Gzip.decompress(Data(contentsOf: cardsURL))
    }

    /// In the app, the SwiftPM resource bundle is copied into `Contents/Resources` by
    /// `scripts/bundle-app.sh` (SwiftPM's own accessor looks at the bundle root, which code
    /// signing rejects); from `swift build` and `swift test`, `Bundle.module` finds it.
    /// In the app, never fall back to `Bundle.module`: it traps when its bundle is missing.
    /// `moduleBundle` is evaluated only outside an app, and is injectable for tests.
    static func resolveBundle(
        mainResourceURL: URL? = Bundle.main.resourceURL,
        isApp: Bool = Bundle.main.bundleURL.pathExtension == "app",
        moduleBundle: () -> Bundle = { Bundle.module }
    ) throws -> Bundle {
        let expected = (mainResourceURL ?? Bundle.main.bundleURL).appending(path: bundleName)
        if let mainResourceURL, let appBundle = Bundle(url: mainResourceURL.appending(path: bundleName)) {
            return appBundle
        }
        if isApp { throw ResourceError.bundleMissing(expected) }
        return moduleBundle()
    }

    private static let bundle = Result { try resolveBundle() }

    private static func url(_ name: String, _ ext: String) throws -> URL {
        let bundle = try bundle.get()
        return bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
            ?? bundle.bundleURL.appending(path: "Resources/\(name).\(ext)")
    }
}
