//
//  EmbedCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Downloads a bundle's remote images and Google Fonts into it —
/// ``Woodcase/PenBundle/embed(_:identity:fetcher:fonts:)``.
struct EmbedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "embed",
        abstract: "Write: download a bundle's remote images and Google Fonts into it.",
        discussion: """
        An act verb, and the only one that reaches the network to change a document. \
        Every http(s) image fill is downloaded into the bundle's images/, every remote \
        declared font into fonts/, and every Google Fonts family a text node uses \
        (and the operating system does not ship) has the file of each face it draws \
        copied into fonts/ and declared in the root `fonts` array. References are \
        rewritten to the local copies, so the bundle renders offline and the same on \
        every machine.

        Nothing is ever embedded on its own: this verb, or `bundle --embed`, is how. \
        The rewrite is one logged change attributed to --as (`replace` rows for the \
        nodes whose fills moved, a `set` row for `fonts`), so `woodcase undo` takes it \
        back. A download that fails leaves its reference remote and is listed as \
        missing. A bare .pen is refused (exit 2): `woodcase bundle` it first.

        EXAMPLE
          woodcase embed design.umbra
        """
    )

    @Argument(help: "The .umbra bundle to make self-contained.")
    var bundle: PenFilePath

    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Downloads, rewrites, and prints the report.
    ///
    /// - Throws: ``CommandFailure`` when the path is not a bundle or cannot be read or
    ///   written.
    func run() async throws {
        let document = try bundle.existingFile()
        guard PenLocation(document).kind == .bundle else {
            throw CommandFailure.describing(PenBundleError.notABundle(document))
        }
        let report: PenBundle.Report
        do {
            report = try await PenBundle.embed(
                document, identity: identity.identity, fetcher: StandardDataFetcher.make(), fonts: .shared
            )
        } catch {
            throw CommandFailure.describing(error, editing: document)
        }
        try print(BundleReport(report, verb: .downloaded).rendered(json: output.json))
    }
}
