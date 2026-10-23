//
//  BundleCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Converts a bare `.pen` into a `.umbra` bundle in place, taking its local images and
/// fonts along — ``Woodcase/PenBundle/convert(_:identity:)``.
struct BundleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bundle",
        abstract: "Write: convert a .pen file into a .umbra bundle beside it.",
        discussion: """
        An act verb. design.pen becomes design.umbra/document.pen: every local image \
        fill and declared font it points at is copied into the bundle's images/ and \
        fonts/, and its path rewritten. The original is removed, so Git sees a rename; \
        the bundle records where it came from, and any later command run on a \
        design.pen that comes back warns you to edit the bundle instead.

        A bundle keeps its own shared history in design.umbra/history/, one file per \
        writer, which starts with a `new` row attributed to --as; the original's history stays in \
        the log it was written to. Remote images and Google Fonts stay remote unless \
        you pass --embed, which downloads them into the bundle (see `woodcase embed`).

        Refused when design.umbra already exists (exit 3). A reference to a file that \
        is not there is left as it was and listed as missing.

        EXAMPLE
          woodcase bundle design.pen
          woodcase tree design.umbra
        """
    )

    @Argument(help: "The .pen file to convert.")
    var file: PenFilePath

    @Flag(name: .long, help: "Also download remote images and Google Fonts into the bundle.")
    var embed = false

    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Converts the file, embeds if asked, and prints the report.
    ///
    /// - Throws: ``CommandFailure`` when the file cannot be read, the bundle's path is
    ///   taken, or the bundle cannot be written.
    func run() async throws {
        let url = try file.existingFile()
        var report: PenBundle.Report
        do {
            report = try await PenBundle.convert(url, identity: identity.identity)
            if embed {
                let embedded = try await PenBundle.embed(
                    report.document, identity: identity.identity,
                    fetcher: StandardDataFetcher.make(), fonts: .shared
                )
                report.revision = embedded.revision
                report.copied += embedded.copied
                report.missing += embedded.missing
            }
        } catch {
            throw CommandFailure.describing(error, editing: url)
        }
        try print(BundleReport(report, verb: .copied).rendered(json: output.json))
    }
}
