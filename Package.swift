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
        // gzip with the system zlib: saved log slices and the simulator's bundled card data.
        .target(name: "GzipSupport"),
        // Log files on disk: discovery, config, tailing, retention. No Battlegrounds knowledge.
        .target(name: "HSLog"),
        // Log lines -> typed power events.
        .target(name: "PowerParser", plugins: ["HSEnumsPlugin"]),
        // Generic, deterministic reducer of power events into entities and tags.
        .target(name: "EntityStore", dependencies: ["PowerParser"]),
        // Battlegrounds projection of the entity store, plus the event-driven game history.
        .target(name: "BGState", dependencies: ["EntityStore", "PowerParser"]),
        // Card data, generated enums, minion pool, hero and build stats.
        // Resources: the minion-pool override files and the bundled HSReplay meta period.
        .target(
            name: "HSData", dependencies: ["PowerParser"], resources: [.copy("Resources/bg-pool")],
            plugins: ["HSEnumsPlugin"]
        ),
        // Tribes, builds, shop highlights, hero-pick stats, simulator adapter, advisor.
        .target(name: "BGIntel", dependencies: ["BGState", "HSData", "EntityStore", "PowerParser"]),
        // Firestone's combat simulator (pinned npm package bundled by scripts/update-simulator.sh)
        // in a JavaScriptCore context, with its pinned card data.
        .target(name: "SimulatorRuntime", dependencies: ["GzipSupport"], resources: [.copy("Resources")]),
        // Headless composition root: log lines in, timeline of view states and game records out.
        .target(
            name: "TavernEngine",
            dependencies: [
                "HSLog", "GzipSupport", "PowerParser", "EntityStore", "BGState", "HSData", "BGIntel", "SimulatorRuntime",
            ]
        ),
        // Pure overlay geometry: Hearthstone's content frame -> element rects (seam 2).
        .target(name: "OverlayLayout"),
        // Screen reading without the capture: Vision text recognition of the hero-pick banner
        // (lobby tribes and the alignment check). Needs no permission, so it's tested on images.
        .target(name: "ScreenReading", dependencies: ["BGIntel", "HSData", "OverlayLayout"]),
        // Thin menu-bar app: OS integration and UI only.
        .executableTarget(name: "TavernLensApp", dependencies: ["TavernEngine", "HSLog", "OverlayLayout", "ScreenReading"]),
        // Build-time codegen: HearthstoneJSON enums.json (Data/HearthstoneJSON) -> Swift enum tables.
        .executableTarget(name: "HSEnumsGenerator", path: "Tools/HSEnumsGenerator"),
        .plugin(name: "HSEnumsPlugin", capability: .buildTool(), dependencies: ["HSEnumsGenerator"]),
        .testTarget(
            name: "HSDataTests",
            dependencies: ["HSData", "PowerParser"],
            swiftSettings: commandLineToolsTesting.swift,
            linkerSettings: commandLineToolsTesting.linker
        ),
        .testTarget(
            name: "TavernEngineTests",
            dependencies: ["TavernEngine", "HSLog"],
            // Golden JSON is read from (and recorded into) the source tree via #filePath.
            exclude: ["Golden"],
            swiftSettings: commandLineToolsTesting.swift,
            linkerSettings: commandLineToolsTesting.linker
        ),
        // Seam 2: layout geometry for the measured reference frames.
        .testTarget(
            name: "OverlayLayoutTests",
            dependencies: ["OverlayLayout"],
            swiftSettings: commandLineToolsTesting.swift,
            linkerSettings: commandLineToolsTesting.linker
        ),
        // The hero-pick banner reader on a cropped capture of the player's own hero pick.
        .testTarget(
            name: "ScreenReadingTests",
            dependencies: ["ScreenReading", "OverlayLayout", "BGIntel", "HSData"],
            swiftSettings: commandLineToolsTesting.swift,
            linkerSettings: commandLineToolsTesting.linker
        ),
        // Seam 3: log housekeeping against a temporary directory tree.
        .testTarget(
            name: "HSLogTests",
            dependencies: ["HSLog", "GzipSupport"],
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
