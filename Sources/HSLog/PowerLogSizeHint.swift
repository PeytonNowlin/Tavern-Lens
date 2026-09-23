import Foundation

/// A session's Power.log keeps growing while Hearthstone stays open (35 MB or more a
/// game), and a file the client has open can't be safely truncated. Past a threshold
/// the menu bar suggests a restart, which starts a new session folder.
public enum PowerLogSizeHint {
    public static let defaultThreshold: Int64 = 800 * ByteSize.megabyte

    /// The hint for a Power.log of `bytes`, or nil while it's under `threshold`.
    public static func message(bytes: Int64, threshold: Int64 = defaultThreshold) -> String? {
        guard threshold > 0, bytes >= threshold else { return nil }
        return "Power.log is \(ByteSize.format(bytes)); restart Hearthstone to rotate"
    }

    /// The size of the file at `url`, or nil if it doesn't exist.
    public static func size(of url: URL) -> Int64? {
        // Not `resourceValues`: a URL caches those, and this is polled.
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}
