//
//  UnbundleCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Copies a `.umbra` bundle out into a plain folder any `.pen` tool opens —
/// ``Woodcase/PenBundle/export(_:to:identity:)``.
struct UnbundleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unbundle",
        abstract: "Write: copy a .umbra bundle out as a plain .pen folder.",
        discussion: """
        The reverse of `bundle`, as a copy: design.umbra is written out as \
        <folder>/design.pen beside images/ and fonts/ holding every local file it uses, \
        with relative paths that resolve from there — the shape Pen and any other .pen \
        tool open. The bundle is left as it is. The folder defaults to one named after \
        the bundle, beside it (design/); it is created if missing, and nothing in it \
        is overwritten — an existing design.pen there is refused (exit 3).

        The new file's history starts with a `new` row in its own log, attributed to --as.

        EXAMPLE
          woodcase unbundle design.umbra
          woodcase unbundle design.umbra --to ~/Desktop/design-for-pen
        """
    )

    @Argument(help: "The .umbra bundle to copy out.")
    var bundle: PenFilePath

    @Option(name: .long, help: ArgumentHelp("The folder to write into.", valueName: "folder"))
    var to: String?

    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Exports the bundle and prints the report.
    ///
    /// - Throws: ``CommandFailure`` when the path is not a bundle, the folder already
    ///   holds the file, or the folder cannot be written.
    func run() async throws {
        let document = try bundle.existingFile()
        let location = PenLocation(document)
        guard location.kind == .bundle else {
            throw CommandFailure(
                message: "\(bundle.path) is not a .umbra bundle, so there is nothing to unbundle — "
                    + "it is already a plain .pen file any .pen tool opens.",
                exitCode: .usage
            )
        }
        let folder = to.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? location.containingDirectory.appendingPathComponent(location.name, isDirectory: true)
        let report: PenBundle.Report
        do {
            report = try await PenBundle.export(location.url, to: folder, identity: identity.identity)
        } catch {
            throw CommandFailure.describing(error, editing: document)
        }
        try print(BundleReport(report, verb: .copied).rendered(json: output.json))
    }
}
