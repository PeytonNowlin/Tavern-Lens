// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Module layout follows the Tavern Lens v1 spec (docs/spec/tavern-lens-v1.md).
// Dependencies only point "down" this list:
//   HSLog, PowerParser -> EntityStore -> BGState -> BGIntel -> TavernEngine -> TavernLensApp
// HSData (enums, card data, stats) is shared data used by BGIntel and TavernEngine.
let package = Package(
    name: "TavernLens",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "TavernLens", targets: ["TavernLensApp"]),
        .library(name: "TavernEngine", targets: ["TavernEngine"]),
    ],
    targets: [
        // Log files on disk: discovery, config, tailing, retention. No Battlegrounds knowledge.
        .target(name: "HSLog"),
        // Log lines -> typed power events.
        .target(name: "PowerParser"),
        // Generic, deterministic reducer of power events into entities and tags.
        .target(name: "EntityStore", dependencies: ["PowerParser"]),
        // Battlegrounds projection of the entity store, plus the event-driven game history.
        .target(name: "BGState", dependencies: ["EntityStore", "PowerParser"]),
        // Card data, generated enums, minion pool, hero and build stats.
        .target(name: "HSData", dependencies: ["PowerParser"]),
        // Tribes, builds, shop highlights, hero-pick stats, simulator adapter, advisor.
        .target(name: "BGIntel", dependencies: ["BGState", "HSData"]),
        // Headless composition root: log lines in, timeline of view states and game records out.
        .target(
            name: "TavernEngine",
            dependencies: ["HSLog", "PowerParser", "EntityStore", "BGState", "HSData", "BGIntel"]
        ),
        // Thin menu-bar app: OS integration and UI only.
        .executableTarget(name: "TavernLensApp", dependencies: ["TavernEngine", "HSLog"]),
        .testTarget(
            name: "TavernEngineTests",
            dependencies: ["TavernEngine", "HSLog"],
            // Golden JSON is read from (and recorded into) the source tree via #filePath.
            exclude: ["Golden"],
            swiftSettings: commandLineToolsTesting.swift,
            linkerSettings: commandLineToolsTesting.linker
        ),
        // Seam 3: log housekeeping against a temporary directory tree.
        .testTarget(
            name: "HSLogTests",
            dependencies: ["HSLog"],
            swiftSettings: commandLineToolsTesting.swift,
            linkerSettings: commandLineToolsTesting.linker
        ),
    ]
)

// Swift Testing with Command Line Tools only (no Xcode): SwiftPM doesn't add the CLT's
// Testing.framework to the search paths, and the CLT's `_Testing_Foundation` overlay
// ships without its module, so any test file importing both Testing and Foundation
// fails to build. Point at the framework and turn off cross-import overlays.
// Not applied when Xcode is installed.
var commandLineToolsTesting: (swift: [SwiftSetting], linker: [LinkerSetting]) {
    let frameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: frameworks + "/Testing.framework"),
          !fileManager.fileExists(atPath: "/Applications/Xcode.app")
    else { return ([], []) }
    return (
        [.unsafeFlags(["-F", frameworks, "-Xfrontend", "-disable-cross-import-overlays"])],
        [.unsafeFlags(["-F", frameworks, "-Xlinker", "-rpath", "-Xlinker", frameworks])]
    )
}
