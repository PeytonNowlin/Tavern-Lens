import Foundation

/// Finds the build number of the installed Hearthstone client.
///
/// The client's `Info.plist` has `CFBundleVersion` like `36.6.251952`; the last
/// component is the build HearthstoneJSON keys its data by.
public enum HearthstoneBuild {
    public static let defaultAppURL = URL(filePath: "/Applications/Hearthstone/Hearthstone.app", directoryHint: .isDirectory)

    /// The build of the Hearthstone app at `appURL`, or nil when it's missing or unreadable. Read-only.
    public static func installed(appURL: URL = defaultAppURL) -> Int? {
        let plist = appURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = info["CFBundleVersion"] as? String
        else { return nil }
        return parse(bundleVersion: version)
    }

    /// `36.6.251952` -> 251952.
    public static func parse(bundleVersion: String) -> Int? {
        guard let last = bundleVersion.split(separator: ".").last, let build = Int(last), build > 0 else { return nil }
        return build
    }
}
