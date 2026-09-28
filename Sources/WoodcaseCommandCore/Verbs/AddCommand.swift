//
//  AddCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Inserts an authored .pen subtree under a parent, or at the document root.
struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Write: insert a .pen subtree under a parent, or at the document root.",
        discussion: """
        An act verb. The subtree is .pen JSON, read from a file with -F (or from \
        standard input with `-F -`). Ids in it are optional: leave "id" out and one \
        is generated — the name → id tree printed back is where those come from. An \
        id you do write is kept, as long as it has no "/" in it, is not already in \
        the file, and is not repeated in the subtree; otherwise the add is refused \
        and the file is untouched.

        Every node in the subtree needs a "name": an unnamed node cannot be \
        addressed by path afterwards, so it is refused rather than silently made \
        unreachable.

        Placement is flex-first. A node added to a laid-out parent takes no \
        coordinates — leave x and y off and let the parent place it. A root-level \
        add (parent `document`) that declares neither x nor y is placed in empty \
        space to the right of the existing roots, because two artboards at the same \
        coordinates sit on top of each other.

        A subtree may contain component instances, not only leaves. A node of type \
        "ref" names the definition it draws in "ref" and carries its own overrides \
        in "descendants", keyed by the definition's child ids — including a \
        "children" array that fills the definition's slot frame. So a board built \
        from a component library is one `add`, rather than one `cp` per instance \
        and an `override` per value. `woodcase schema ref` prints the shape and \
        `woodcase help design` explains the keying.

        \(AddressArgument.addressForms)

        EXAMPLES
          echo '{"type":"text","name":"Caption","content":"Hi"}' \\
            | woodcase add design.pen Card -F - --at 0 --as ana

          # An instance, its overrides and its slot children, in one write:
          echo '{"type":"ref","name":"Row 1","ref":"Card0",
                 "descendants":{"CTtl0":{"content":"Acme"},
                                "CSlt0":{"children":[{"id":"Nte01","type":"text",
                                  "name":"Note","content":"from the instance"}]}}}' \\
            | woodcase add design.pen List -F - --as ana
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The parent to insert into, or `document` for the document root.")
    var parent: String

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp("A .pen subtree as JSON. `-` reads standard input.", valueName: "file")
    )
    var subtreeFile: String

    @OptionGroup var position: PositionOption
    @OptionGroup var revision: RevisionOption
    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    func run() async throws {
        let url = try file.existingFile()
        let parentAddress = try AddressArgument.parent(parent)
        let node = try subtree()
        let index = position.at
        let expected = revision.rev
        let pins = try premise.guards()
        let effect = preview.effect
        let writer = identity.identity
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(at: url, identity: writer, effect: effect, fonts: .shared) { document, recorder in
                let overlapping = RootOverlapWarnings.baseline(in: document)
                do {
                    let findings = try effect.preview(of: document)
                    let result = try BatchApplier.applyOne(
                        .add(BatchOperation.AddOp(
                            node: node, parent: parentAddress, at: index, rev: expected, guards: pins
                        )),
                        to: document,
                        recorder: recorder,
                        log: ActivityLogLocation.log(for: url),
                        file: url
                    )
                    let warnings = RootOverlapWarnings.lines(
                        since: overlapping, in: document, file: url.path
                    )
                    return try WrittenOutcome(
                        rendered: WriteReport(
                            created: result.created,
                            path: result.path,
                            id: result.created.first?.id,
                            nodeRevision: result.created.first.flatMap { document.revision(of: $0.id) },
                            documentRevision: document.documentRevision,
                            warnings: warnings,
                            node: result.node,
                            divergences: result.divergences,
                            dryRun: effect == .dryRun,
                            lint: findings?.introduced(in: document) ?? []
                        ).rendered(json: wantsJSON),
                        warnings: warnings
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
            OutsideWriteNote.report(outcome, json: wantsJSON)
            print(outcome.value.rendered)
            RootOverlapWarnings.report(outcome.value.warnings)
        }
    }

    /// The subtree to insert, decoded from `-F`.
    ///
    /// - Returns: The node, with an empty id marking anything the author left out.
    /// - Throws: ``CommandFailure`` with ``ExitCode/targetFailure`` when the file
    ///   cannot be read, or ``ExitCode/usage`` when it is not a .pen node.
    private func subtree() throws -> PenNode {
        let data = try InputFile.data(at: subtreeFile)
        do {
            return try PenSubtreeDecoder.node(from: JSONDecoder().decode(AnyCodable.self, from: data))
        } catch {
            throw CommandFailure(
                message: "\(subtreeFile) is not a .pen subtree: \(error). A subtree is one JSON "
                    + #"object with a "type" and a "name", and optional "children"."#,
                exitCode: .usage
            )
        }
    }
}
