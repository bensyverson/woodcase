//
//  NewCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Writes the minimum a `.pen` file needs, so `add` and `cp` have something to grow.
///
/// An act verb, but an unusual one: there is no existing file to parse or guard with a
/// revision. It writes through ``Woodcase/PenFileTransaction/create(at:document:identity:log:effect:)``,
/// which creates the file under its lock and records its first activity-log event,
/// `new`. It only ever writes one shape — an empty `children` array and every optional
/// left `nil` — encoded exactly as every other write encodes a document, so the very
/// first `add` sees no unexpected diff.
struct NewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Write: create a .pen file with nothing in it.",
        discussion: """
        An act verb. The file it writes is the minimum a .pen file needs — the \
        current format version and an empty children array — with no themes, \
        imports or variables. `add` and `cp` are how a design grows from there.

        Refused rather than overwritten when the path already exists (exit 3) — \
        `woodcase tree` is the read that shows what is there. The parent directory \
        has to exist already; this does not create one (exit 4, naming it).

        The file's first activity-log event is a `new` row, attributed to --as — \
        `woodcase activity` shows it, and `undo` stops there.

        --dry-run has nothing to lock or roll back here — there is no file yet — so it \
        runs both refusals above and then prints the path, creating nothing. No \
        revision, because no file was made.

        EXAMPLE
          woodcase new design.pen
          woodcase tree design.pen
        """
    )

    @Argument(help: "The .pen file to create.")
    var file: PenFilePath

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Writes the empty document, records it, and prints the outline or `--json` report.
    ///
    /// A `--dry-run` runs both refusals first — a rehearsal that would be refused is
    /// refused, with the same message and the same exit code — and then answers without
    /// creating anything or recording anything.
    ///
    /// - Throws: ``CommandFailure`` with ``ExitCode/conflict`` when the path already
    ///   exists, ``ExitCode/targetFailure`` when its parent directory does not, or
    ///   whatever the write itself fails with.
    func run() async throws {
        let url = file.url
        try refuseIfExisting(at: url)
        try refuseMissingParentDirectory(of: url)

        let document = PenDocument(children: [])
        let outcome: PenFileTransaction.Outcome<String>
        do {
            outcome = try await PenFileTransaction.create(
                at: url, document: document, identity: identity.identity, effect: preview.effect
            )
        } catch {
            throw CommandFailure.describing(error, editing: url)
        }

        guard outcome.commit == .wrote else {
            try print(NewFileReport(
                path: file.path,
                documentRevision: outcome.value,
                dryRun: true,
                lint: DocumentLinter.findings(in: EditableDocument(from: document))
            ).rendered(json: output.json))
            return
        }
        try print(NewFileReport(path: file.path, documentRevision: outcome.value).rendered(json: output.json))
    }

    /// Refuses to overwrite a path that already names something.
    private func refuseIfExisting(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        throw CommandFailure(
            message: "\(file.path) already exists — `woodcase tree \(file.path)` reads it.",
            exitCode: .conflict
        )
    }

    /// Refuses to create the parent directory a missing path would need.
    private func refuseMissingParentDirectory(of url: URL) throws {
        let parent = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CommandFailure(
                message: "Cannot create \(file.path): the directory \(parent.path) does not "
                    + "exist. Create it first — `mkdir -p \(parent.path)`.",
                exitCode: .targetFailure
            )
        }
    }
}
