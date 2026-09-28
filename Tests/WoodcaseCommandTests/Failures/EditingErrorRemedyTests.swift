//
//  EditingErrorRemedyTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The house checklist for errors, applied to every refusal a verb can print.
///
/// `cli-design.md` says an error *names the thing by its path, says what happened, and
/// says the next command*. This suite is the test that rule asked for: every case of
/// ``EditingError`` and ``BatchError`` is rendered through the CLI's own mapper with a
/// representative payload, and the sentence that comes out has to satisfy all three
/// parts of the convention documented on ``BatchErrorMessage``:
///
/// 1. it names the subject — a name path where the node is in the document, otherwise
///    the address, id or key exactly as the caller typed it;
/// 2. it separates the remedy with ` — `;
/// 3. the remedy carries a backticked literal: the `woodcase` command to run next, or
///    the exact text to write.
///
/// ``subject(of:)`` and ``subject(of:)-batch`` switch exhaustively, so a new error case
/// cannot be added without this suite failing to compile — which is what keeps the
/// checklist honest as the vocabulary grows.
@MainActor
@Suite("Every error names a path and a next step")
struct EditingErrorRemedyTests {
    // MARK: - The checklist

    @Test("Every EditingError case names its subject, and says what to do next")
    func everyEditingErrorTeaches() throws {
        let document = try makeDocument()
        for error in Self.editingSamples {
            let message = CommandFailure.describing(error, in: document, editing: penFile).message
            expectTeaching(message, names: subject(of: error), for: "\(error)")
        }
    }

    @Test("Every BatchError case names its subject, and says what to do next")
    func everyBatchErrorTeaches() throws {
        let document = try makeDocument()
        for error in Self.batchSamples {
            let message = CommandFailure.describing(error, in: document, editing: penFile).message
            expectTeaching(message, names: subject(of: error), for: "\(error)")
        }
    }

    @Test("A remedy that says to run a command names the file it would run against")
    func remediesNameTheFile() throws {
        let document = try makeDocument()
        let errors = Self.editingSamples.map { $0 as any Error } + Self.batchSamples.map { $0 as any Error }
        for error in errors {
            let message = CommandFailure.describing(error, in: document, editing: penFile).message
            for command in Self.runnableCommands(in: message) {
                #expect(
                    command.contains(penFile.path),
                    "\(error): `\(command)` runs against a document but does not say which"
                )
            }
        }
    }

    /// The backticked `woodcase` commands in a message that act on a document.
    ///
    /// A remedy may also name a verb without running it — "let `woodcase add` generate
    /// one", "run `woodcase apply --help` for the grammar". Those take no file, so the
    /// rule is scoped to a command that carries an operand.
    private static func runnableCommands(in message: String) -> [String] {
        message.matches(of: /`(woodcase [^`]+)`/)
            .map { String($0.1) }
            .filter { command in
                let words = command.split(separator: " ")
                guard words.count > 2 else { return false }
                return !words[2].hasPrefix("-")
            }
    }

    @Test("The dialect switches the remedy and leaves the statement alone")
    func dialectSwitchesOnlyTheRemedy() throws {
        let document = try makeDocument()
        let error = BatchError.setInsideInstance(address: "Board/Chip/Label", instancePath: "Board/Chip")
        let inBatch = BatchErrorMessage.describe(error, in: document)
        let atPrompt = BatchErrorMessage.describe(error, in: document, dialect: .command(file: penFile.path))
        let statement = "Board/Chip/Label is inside the component instance Board/Chip"
        #expect(inBatch.hasPrefix(statement))
        #expect(atPrompt.hasPrefix(statement))
        #expect(inBatch.contains("{\"op\":\"override\""))
        #expect(!inBatch.contains("woodcase override"))
        #expect(atPrompt.contains("`woodcase override \(penFile.path) Board/Chip/Label name=value`"))
        #expect(!atPrompt.contains("{\"op\":\"override\""))
    }

    // MARK: - Assertions

    /// Asserts one message satisfies all three parts of the convention.
    private func expectTeaching(_ message: String, names subject: String, for label: String) {
        #expect(message.contains(subject), "\(label): the message does not name \(subject)")
        #expect(message.contains(" — "), "\(label): the message has no ` — ` remedy clause: \(message)")
        #expect(
            message.firstMatch(of: /`[^`]+`/) != nil,
            "\(label): the remedy names nothing to type: \(message)"
        )
    }

    // MARK: - Samples

    /// One representative payload per ``EditingError`` case.
    private static let editingSamples: [EditingError] = [
        .nodeNotFound(id: "Zz999"),
        .duplicateNodeID(id: "Ttl01"),
        .invalidNodeID(id: "Hero/Card"),
        .parentNotFound(id: "Zz999"),
        .cannotHaveChildren(parentID: "Ttl01"),
        .invalidIndex(index: 7, count: 2),
        .wouldCreateCycle(nodeID: "Cnv01", targetParentID: "Crd01"),
        .variableNotFound(name: "brand"),
        .variableAlreadyExists(name: "brand"),
        .importNotFound(alias: "ui"),
        .importAlreadyExists(alias: "ui"),
        .themeAxisNotFound(name: "mode"),
        .themeAxisAlreadyExists(name: "mode"),
        .notARefNode(id: "Ttl01"),
        .unknownProperty(nodeID: "Cd101", key: "kind.nonsense", nodeType: "frame"),
        .propertyTypeMismatch(nodeID: "Ttl01", key: "kind.fontSize", expected: "a number", actual: "a string"),
        .ambiguousAddress(address: "Title", candidates: [
            NodeAddressCandidate(id: "Ttl01", path: "Canvas/Title"),
            NodeAddressCandidate(id: "Ttl02", path: "Board/Title"),
        ]),
        .addressNotFound(address: "Canvas/Nope", nearMisses: []),
        .addressNotFound(address: "Nope", nearMisses: [
            NodeAddressCandidate(id: "Ttl01", path: "Canvas/Title"),
        ]),
        .addressNotFound(address: "Chip/Count", nearMisses: [
            NodeAddressCandidate(id: "Chi01/Bdg01/Cnt01", path: "Board/Chip/Badge/Count"),
        ]),
        .componentHasInstances(componentID: "Cmp01", instanceIDs: ["Chi01"]),
        .componentTypeChange(componentID: "Cmp01", from: "frame", to: "text", instanceIDs: ["Chi01"]),
        .overrideTargetNotFound(refID: "Chi01", descendantKey: "Nope", candidates: [
            NodeAddressCandidate(id: "Lbl01", path: "Component/Label"),
        ]),
        .overrideOnOwnSlotContent(refID: "Chi01", descendantKey: "Note1", slotPath: "Board/Chip/Body"),
        .overrideValueRejected(
            refID: "Chi01", descendantKey: "Lbl01", key: "content",
            expected: "text or a $variable", actual: "an object"
        ),
        .rootOverrideKeyReserved(refID: "Chi01", key: "opacity", reason: .instanceCommon),
        .rootOverrideKeyReserved(refID: "Chi01", key: "descendants", reason: .refStructure),
        .rootOverrideKeyReserved(refID: "Chi01", key: "type", reason: .identity),
        .rootOverrideValueRejected(
            refID: "Chi01", key: "width", expected: "a number", actual: "an array"
        ),
        .revisionConflict(nodeID: "Ttl01", expected: "0000000000000000", actual: "62b06f8ec3102d5c"),
    ]

    /// One representative payload per ``BatchError`` case.
    private static let batchSamples: [BatchError] = [
        .malformedLine(line: 3, reason: "not JSON"),
        .malformedRow(row: 2, reason: "not JSON"),
        .copyPathNotInSource(row: 3, key: "Nowhere/kind.content", source: "Component"),
        .copyPathNotInSource(row: nil, key: "Nowhere/kind.content", source: "Component"),
        .parameterPathNotFound(name: "label", path: "Body/Missing", component: "Component"),
        .emptyCopyRows,
        .copyTagWithRows(tag: "chips"),
        .unnamedNode(type: "text", locator: "Card/Header"),
        .literalRootOverridesKey(locator: "Card/Chip"),
        .replacementIDMismatch(address: "Canvas/Cards", supplied: "Nope1", kept: "Crd01"),
        .setInsideInstance(address: "Board/Chip/Label", instancePath: "Board/Chip"),
        .structureInsideSlot(address: "Board/Chip/Note", slotPath: "Board/Chip/Body"),
        .overrideOutsideInstance(address: "Canvas/Title", path: "Canvas/Title"),
        .overrideWithoutProperties(address: "Board/Chip/Label"),
        .parentInsideInstance(address: "Board/Chip/Label", instancePath: "Board/Chip"),
        .documentRevisionConflict(expected: "0000000000000000", actual: "62b06f8ec3102d5c"),
        .guardConflict(
            node: "Canvas/Title (Ttl01)", address: "Canvas/Title",
            expected: "0000000000000000", actual: "62b06f8ec3102d5c", writer: "ana"
        ),
        .guardConflict(
            node: "the document", address: nil,
            expected: "0000000000000000", actual: "62b06f8ec3102d5c", writer: ""
        ),
        .guardNodeMissing(node: "Canvas/Gone"),
        .guardOnTag(tag: "hero"),
        .guardWithoutTarget(verb: "var"),
    ]

    /// What the message for this refusal has to name.
    ///
    /// Exhaustive on purpose: a new ``EditingError`` case breaks this switch, and the
    /// author has to say what its message names before the suite compiles again.
    private func subject(of error: EditingError) -> String {
        switch error {
        case let .nodeNotFound(id): id
        case let .duplicateNodeID(id): id
        case let .invalidNodeID(id): id
        case let .parentNotFound(id): id
        case .cannotHaveChildren: "Canvas/Title"
        case let .invalidIndex(index, _): "\(index)"
        case .wouldCreateCycle: "Canvas/Cards"
        case let .variableNotFound(name): name
        case let .variableAlreadyExists(name): name
        case let .importNotFound(alias): alias
        case let .importAlreadyExists(alias): alias
        case let .themeAxisNotFound(name): name
        case let .themeAxisAlreadyExists(name): name
        case .notARefNode: "Canvas/Title"
        case let .unknownProperty(_, key, _): key
        case let .propertyTypeMismatch(_, key, _, _): key
        case let .ambiguousAddress(address, _): address
        case let .addressNotFound(address, _): address
        case .componentHasInstances: "Component"
        case .componentTypeChange: "Component"
        case let .overrideTargetNotFound(_, descendantKey, _): descendantKey
        case let .overrideOnOwnSlotContent(refID, descendantKey, _): "\(refID)/\(descendantKey)"
        case let .overrideValueRejected(_, _, key, _, _): key
        case let .rootOverrideKeyReserved(_, key, _): key
        case let .rootOverrideValueRejected(_, key, _, _): key
        case .revisionConflict: "Canvas/Title"
        }
    }

    /// What the message for this batch-grammar refusal has to name.
    ///
    /// Exhaustive for the same reason as ``subject(of:)``.
    private func subject(of error: BatchError) -> String {
        switch error {
        case let .malformedLine(line, _): "line \(line)"
        case let .malformedRow(row, _): "row \(row)"
        case let .copyPathNotInSource(_, key, _): key
        case let .parameterPathNotFound(name, _, _): name
        case .emptyCopyRows: "copy list"
        case let .copyTagWithRows(tag): tag
        case let .unnamedNode(_, locator): locator
        case let .literalRootOverridesKey(locator): locator
        case let .replacementIDMismatch(address, _, _): address
        case let .setInsideInstance(address, _): address
        case let .structureInsideSlot(address, _): address
        case let .overrideOutsideInstance(address, _): address
        case let .overrideWithoutProperties(address): address
        case let .parentInsideInstance(address, _): address
        case let .documentRevisionConflict(expected, _): expected
        case let .guardConflict(node, _, _, _, _): node
        case let .guardNodeMissing(node): node
        case let .guardOnTag(tag): "@\(tag)"
        case let .guardWithoutTarget(verb): verb
        }
    }

    // MARK: - Fixture

    private let penFile = URL(fileURLWithPath: "/tmp/design.pen")

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WoodcaseTests/Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }
}
