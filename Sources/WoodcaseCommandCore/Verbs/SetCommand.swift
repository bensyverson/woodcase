//
//  SetCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Patches properties on one existing node.
struct SetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Write: set properties on one node.",
        discussion: """
        An act verb. Keys are property paths — "common.name", "kind.width", \
        "kind.fills" — and only the keys given are touched; everything else on the \
        node is left exactly as it was. Setting a key to null clears it. A key the \
        node does not have is refused with the list of the ones it does.

        \(PropertyAssignment.valueRules)

        common.metadata is an object, and writing it REPLACES the whole thing — every \
        key already there, _props and _role included, goes with it. \
        common.metadata.<key>=<value> writes ONE entry instead, merging it into what \
        is there and creating the object if there is none; a dot goes deeper, so \
        common.metadata._props.label=Body/Title declares one parameter without \
        rewriting the others. An object a deep key creates carries type: "unknown" \
        beside the entry, the schema requiring metadata.type, so choose it in the same \
        write: common.metadata.type=component common.metadata._role=button. Setting a \
        deep key to null removes that one entry. No other property takes a deep key.

        Properties can also come from a JSON object with -F, and a key=value on the \
        command line wins over the same key in that file.

        A node *inside* a component instance stores nothing of its own; `set` says \
        so and points at `woodcase override`.

        On a component INSTANCE itself, `set` writes the ref node — where it sits and \
        whether it draws, so common.x, common.opacity, kind.ref. The properties of the \
        component it *shows* are root overrides: `woodcase override <instance> \
        width=320`, with no path after the address. Aim either verb at the other's \
        half and the refusal names the one that works.

        \(AddressArgument.addressForms)

        EXAMPLES
          woodcase set design.pen Card/Title kind.content=Hello kind.fontSize=18 \\
            --rev 4f2a1b0c9d8e7f60 --as ana
          woodcase set design.pen Card common.metadata._props.label=Body/Title
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The node to patch.")
    var node: String

    @Argument(help: "Properties to set, as key=value.")
    var assignments: [String] = []

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp("A JSON object of properties. `-` reads standard input.", valueName: "file")
    )
    var propertiesFile: String?

    @OptionGroup var revision: RevisionOption
    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    func run() async throws {
        let url = try file.existingFile()
        let target = try AddressArgument.node(node)
        let properties = try PropertyAssignment.properties(from: assignments, file: propertiesFile)
        guard !properties.isEmpty else {
            throw CommandFailure(
                message: "set needs at least one key=value to set. \(PropertyAssignment.valueRules)",
                exitCode: .usage
            )
        }
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
                    let id = try document.resolve(target).targetID
                    let result = try BatchApplier.applyOne(
                        .set(BatchOperation.SetOp(
                            target: target, props: properties, rev: expected, guards: pins
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
                            path: result.path ?? document.namePath(of: id),
                            id: id,
                            nodeRevision: document.revision(of: id),
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
}
