import Foundation

/// What checking one config file did.
public enum ConfigFileOutcome: Hashable, Sendable {
    /// Already correct; left alone.
    case correct
    /// Didn't exist; written.
    case created
    /// Existed but was wrong; rewritten.
    case repaired
    /// Couldn't be checked or written (for example Hearthstone isn't installed).
    case failed(String)

    /// The file on disk changed, so a running client won't see it until it restarts.
    public var changedFile: Bool { self == .created || self == .repaired }
}

/// The result of checking `log.config` and `client.config`.
public struct LogConfigReport: Hashable, Sendable {
    public var logConfig: ConfigFileOutcome
    public var clientConfig: ConfigFileOutcome

    public var changedAnything: Bool { logConfig.changedFile || clientConfig.changedFile }

    public var failures: [String] {
        [logConfig, clientConfig].compactMap { if case .failed(let reason) = $0 { reason } else { nil } }
    }
}

/// Keeps Hearthstone's two log config files correct.
///
/// - `log.config` enables only `[Power]` (verbose) and `[LoadingScreen]`. Anything
///   else, such as `[Zone]` (which only costs disk I/O), makes it wrong, and it's rewritten
///   in place. Nothing else is written to Hearthstone's preferences folder (no backup).
/// - `client.config` must have `[Log] FileSizeLimit.Int=-1`; without it the client
///   silently stops logging at 10 MB per file. Its other settings are preserved.
///
/// The client reads both only at launch.
public enum LogConfig {
    static let logConfigSections: [(name: String, verbose: Bool)] = [("Power", true), ("LoadingScreen", false)]

    /// The exact `log.config` Tavern Lens writes.
    public static let logConfigContents: String = logConfigSections.map { section in
        """
        [\(section.name)]
        LogLevel=1
        FilePrinting=true
        ConsolePrinting=false
        ScreenPrinting=false
        Verbose=\(section.verbose)

        """
    }.joined(separator: "\n")

    static let clientLogSection = "Log"
    static let fileSizeLimitKey = "FileSizeLimit.Int"
    static let unlimited = "-1"

    /// Checks both files and repairs whichever is missing or wrong.
    public static func ensure(at locations: HearthstoneLocations) -> LogConfigReport {
        LogConfigReport(
            logConfig: ensureLogConfig(at: locations.logConfigFile),
            clientConfig: ensureClientConfig(installDirectory: locations.installDirectory, file: locations.clientConfigFile)
        )
    }

    // MARK: - log.config

    static func ensureLogConfig(at file: URL) -> ConfigFileOutcome {
        let fileManager = FileManager.default
        let path = file.path(percentEncoded: false)
        let existing: String?
        if fileManager.fileExists(atPath: path) {
            guard let data = fileManager.contents(atPath: path) else { return .failed("Can't read \(path)") }
            existing = String(decoding: data, as: UTF8.self)
        } else {
            existing = nil
        }
        if let existing, isCorrectLogConfig(existing) { return .correct }
        do {
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(logConfigContents.utf8).write(to: file, options: .atomic)
        } catch {
            return .failed("Can't write \(path): \(error.localizedDescription)")
        }
        return existing == nil ? .created : .repaired
    }

    /// Exactly the two sections, each logging to file (and not to the console or
    /// screen), with Power verbose. LoadingScreen's own Verbose flag doesn't matter,
    /// so a file that differs only there (as this Mac's did) is left alone.
    static func isCorrectLogConfig(_ text: String) -> Bool {
        let sections = IniDocument(text: text).normalizedSections
        guard Set(sections.keys) == Set(logConfigSections.map { $0.name.lowercased() }) else { return false }
        return logConfigSections.allSatisfy { wanted in
            guard let keys = sections[wanted.name.lowercased()] else { return false }
            return keys["LogLevel"] == "1"
                && keys["FilePrinting"] == "true"
                && keys["ConsolePrinting"] != "true"
                && keys["ScreenPrinting"] != "true"
                && (!wanted.verbose || keys["Verbose"] == "true")
        }
    }

    // MARK: - client.config

    static func ensureClientConfig(installDirectory: URL, file: URL) -> ConfigFileOutcome {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: installDirectory.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .failed("Hearthstone isn't installed at \(installDirectory.path(percentEncoded: false))")
        }
        let path = file.path(percentEncoded: false)
        var document: IniDocument
        let existed = fileManager.fileExists(atPath: path)
        if existed {
            guard let data = fileManager.contents(atPath: path) else { return .failed("Can't read \(path)") }
            document = IniDocument(text: String(decoding: data, as: UTF8.self))
            if document.value(section: clientLogSection, key: fileSizeLimitKey) == unlimited { return .correct }
        } else {
            document = IniDocument(text: "")
        }
        document.set(section: clientLogSection, key: fileSizeLimitKey, value: unlimited)
        do {
            try Data(document.text.utf8).write(to: file, options: .atomic)
        } catch {
            return .failed("Can't write \(path): \(error.localizedDescription)")
        }
        return existed ? .repaired : .created
    }
}

/// A minimal, line-preserving INI document: `[Section]` headers and `key=value` lines.
/// Section names match case-insensitively; keys match exactly after trimming.
struct IniDocument {
    private(set) var lines: [String]

    init(text: String) {
        // "\r\n" is a single Character, so split on any line break rather than on "\n".
        var lines = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
            .map(String.init)
        if lines.last == "" { lines.removeLast() }
        self.lines = lines
    }

    var text: String { lines.map { $0 + "\n" }.joined() }

    private static func sectionName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func keyValue(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
        return (
            String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces),
            String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        )
    }

    /// Sections (lower-cased names) to their keys and lower-cased values. A repeated
    /// key keeps its last value, as a reader would.
    var normalizedSections: [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var current: String?
        for line in lines {
            if let name = Self.sectionName(line) {
                let key = name.lowercased()
                current = key
                if result[key] == nil { result[key] = [:] }
            } else if let current, let pair = Self.keyValue(line) {
                result[current, default: [:]][pair.key] = pair.value.lowercased()
            }
        }
        return result
    }

    func value(section: String, key: String) -> String? {
        var inSection = false
        var found: String?
        for line in lines {
            if let name = Self.sectionName(line) {
                inSection = name.caseInsensitiveCompare(section) == .orderedSame
            } else if inSection, let pair = Self.keyValue(line), pair.key == key {
                found = pair.value
            }
        }
        return found
    }

    /// Sets `key` in `section`: replaces every existing assignment, or adds one at
    /// the end of the section's first occurrence, or appends the section.
    mutating func set(section: String, key: String, value: String) {
        let assignment = "\(key)=\(value)"
        var inSection = false
        var replaced = false
        var insertAt: Int?
        for index in lines.indices {
            if let name = Self.sectionName(lines[index]) {
                if inSection, insertAt == nil { insertAt = index }
                inSection = name.caseInsensitiveCompare(section) == .orderedSame
            } else if inSection, let pair = Self.keyValue(lines[index]), pair.key == key {
                lines[index] = assignment
                replaced = true
            }
        }
        if replaced { return }
        if inSection, insertAt == nil { insertAt = lines.endIndex }
        if var insertAt {
            // Keep a blank separator line after the section, if it had one.
            while insertAt > 0, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertAt -= 1 }
            lines.insert(assignment, at: insertAt)
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines.append("[\(section)]")
            lines.append(assignment)
        }
    }
}
