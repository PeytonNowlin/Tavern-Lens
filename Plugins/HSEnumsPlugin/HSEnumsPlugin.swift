import Foundation
import PackagePlugin

/// Generates enum tables from the committed HearthstoneJSON `enums.json` on every build.
///
/// - PowerParser gets the GameTag name tables (`GameTag.names`, `GameTag.nameByNumber`).
/// - HSData gets every other enum group as `HS.<Group>`.
///
/// The input lives in `Data/HearthstoneJSON/` (`enums.json` plus `enums.build`, the build it
/// was fetched for). Refresh both with `scripts/update-enums.sh`.
@main
struct HSEnumsPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let mode: String
        switch target.name {
        case "PowerParser": mode = "gametag"
        case "HSData": mode = "enums"
        default: return []
        }
        let data = context.package.directoryURL.appending(path: "Data/HearthstoneJSON")
        let enumsJSON = data.appending(path: "enums.json")
        let enumsBuild = data.appending(path: "enums.build")
        let output = context.pluginWorkDirectoryURL.appending(path: "Generated\(target.name)Enums.swift")
        return [
            .buildCommand(
                displayName: "Generating \(target.name) enums from HearthstoneJSON enums.json",
                executable: try context.tool(named: "HSEnumsGenerator").url,
                arguments: [mode, enumsJSON.path(percentEncoded: false), enumsBuild.path(percentEncoded: false),
                            output.path(percentEncoded: false)],
                inputFiles: [enumsJSON, enumsBuild],
                outputFiles: [output]
            ),
        ]
    }
}
