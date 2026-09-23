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

    public static var scriptURL: URL { url("bgs-simulator", "js") }
    public static var cardsURL: URL { url("simulator-cards.json", "gz") }

    public static var pin: Pin? {
        (try? Data(contentsOf: url("bgs-simulator.pin", "json"))).flatMap { try? JSONDecoder().decode(Pin.self, from: $0) }
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
    private static let bundle: Bundle = {
        if let resources = Bundle.main.resourceURL,
           let appBundle = Bundle(url: resources.appending(path: "TavernLens_SimulatorRuntime.bundle")) {
            return appBundle
        }
        return Bundle.module
    }()

    private static func url(_ name: String, _ ext: String) -> URL {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
            ?? bundle.bundleURL.appending(path: "Resources/\(name).\(ext)")
    }
}
