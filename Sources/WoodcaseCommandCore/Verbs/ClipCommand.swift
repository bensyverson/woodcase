//
//  ClipCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Prints what a copy of some nodes would put on a pasteboard: a self-contained .pen.
///
/// The verb is an adapter: it resolves each address to the id the expanded document
/// gives it and hands them to ``Woodcase/PenClip/extract(nodeIDs:from:documentID:)``, which decides
/// everything about what the clip carries.
struct ClipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clip",
        abstract: "Read: the nodes a copy takes, as a self-contained .pen on stdout.",
        discussion: """
        A read verb: it takes a shared lock, writes nothing, and leaves the file's \
        bytes and modification date alone. It is what an editor's Copy puts on the \
        pasteboard; `cp` is the verb that duplicates a node inside a file.

        The output is a .pen document that draws on its own. Its first roots are the \
        nodes asked for, in document order, each at the canvas position it was drawn \
        at — a node inside another one asked for travels inside it. After them come \
        the connectors whose two ends are both inside those nodes, asked for or not, \
        their ends naming the copies; a connector with one end outside stays behind. \
        Then come the component definitions those nodes draw, through nested instances and ref \
        chains, copied as stored; a component from an imported library comes along as \
        a local definition under its prefixed id (K:Chip1), so the clip has no \
        imports. It carries the variables the nodes and definitions use, the variables \
        those reference, and every theme axis they need.

        A node inside an instance (an instance path such as Orders/Value) is copied as \
        drawn: overrides applied, detached from its component, under fresh ids derived \
        from the document, so the same copy prints the same bytes every time.

        --json prints {"contentIDs": [...], "connectorIDs": [...], "document": {...}, \
        "origins": {...}} instead: the clip with the ids of the roots that were copied \
        and of the connectors carried, so a reader can tell them from the definitions \
        carried along, and where each copied root came from — \
        its parent and offset there, its board and offset from the board's corner — \
        the offset `woodcase paste --into` a free container keeps.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase clip design.pen Dashboard/Header Orders/Value > clip.pen
          woodcase shot clip.pen
        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @Argument(help: "The nodes to copy — ids, name paths or instance paths.")
    var nodes: [String]

    @OptionGroup var output: OutputOptions

    @OptionGroup var reader: IdentityOptions<Identity.Reader>

    /// Reads the file and prints the clip.
    func run() async throws {
        let url = try file.existingFile()
        let addresses = try nodes.map(AddressArgument.node)
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let diagnostics = PenDiagnosticCollector()
            defer { StandardError.write(diagnostics) }
            let read = try await CommandTransaction.read(at: url, diagnostics: diagnostics, fonts: .shared) { document in
                do {
                    let ids = try addresses.map { try document.expandedID(of: document.resolve($0)) }
                    let clip = try PenClip.extract(nodeIDs: ids, from: document)
                    let text = try wantsJSON ? CanonicalJSON.text(clip) : CanonicalJSON.text(clip.document)
                    return (text: text, revision: document.documentRevision, nodes: clip.contentIDs)
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }.value
            print(read.text)
            await ViewLogging.record(
                .clip, of: url, by: reader.identity, revision: read.revision, nodes: read.nodes, scope: .subtrees
            )
        }
    }
}
