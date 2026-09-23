import Foundation

/// Data files shipped with HSData (`Sources/HSData/Resources`).
///
/// In the app, `scripts/bundle-app.sh` copies them to `Contents/Resources/HSData`, which is
/// looked up first: SwiftPM's resource bundle is a flat folder that its accessor expects next
/// to the app's root, where code signing rejects it. `swift build` and `swift test` runs use
/// SwiftPM's bundle.
enum HSDataResources {
    /// A folder or file in the resources, e.g. `bg-pool/overrides`.
    static func url(_ path: String) -> URL? {
        let fileManager = FileManager.default
        func existing(_ url: URL) -> URL? { fileManager.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil }
        // In the app, never fall back to `Bundle.module`: it traps when its bundle is missing.
        if let app = Bundle.main.resourceURL?.appending(path: "HSData", directoryHint: .isDirectory), existing(app) != nil {
            return existing(app.appending(path: path))
        }
        return existing(Bundle.module.bundleURL.appending(path: path))
    }
}
