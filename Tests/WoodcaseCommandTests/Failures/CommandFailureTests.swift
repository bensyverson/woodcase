//
//  CommandFailureTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The one place a library error becomes a message and a house exit code. Every case
/// of every error type a verb can see has a row here.
@MainActor
@Suite("Error → message + exit code")
struct CommandFailureTests {
    // MARK: - Helpers

    private let penFile = URL(fileURLWithPath: "/tmp/design.pen")
    private let logFile = URL(fileURLWithPath: "/tmp/home/activity.jsonl")

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WoodcaseTests/Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    // MARK: - File errors

    @Test("A file that cannot be opened is a target failure")
    func cannotOpenIsTargetFailure() {
        let failure = CommandFailure.describing(
            PenFileError.cannotOpen(url: penFile, reason: "No such file or directory"),
            editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("/tmp/design.pen"))
        #expect(failure.message.contains("No such file"))
    }

    @Test("A file that is not a .pen document is a target failure")
    func unreadableIsTargetFailure() {
        let failure = CommandFailure.describing(
            PenFileError.unreadable(url: penFile, reason: "unexpected end of file"),
            editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("/tmp/design.pen"))
    }

    @Test("A write that failed is a target failure")
    func writeFailedIsTargetFailure() {
        let failure = CommandFailure.describing(
            PenFileError.writeFailed(url: penFile, reason: "Permission denied"),
            editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("/tmp/design.pen"))
    }

    @Test("A lock held by someone else is a conflict, and the message says who to look for")
    func lockTimeoutIsConflict() {
        let failure = CommandFailure.describing(
            PenFileError.lockTimeout(url: penFile, timeout: .seconds(5)),
            editing: penFile
        )
        #expect(failure.exitCode == .conflict)
        #expect(failure.message.contains("/tmp/design.pen"))
        #expect(failure.message.contains("lsof"))
    }

    // MARK: - The activity log

    @Test("A log the edit could not be appended to is an environment failure that says the edit landed")
    func logAppendFailureIsEnvironment() {
        let failure = CommandFailure.describing(
            PenFileError.writeFailed(url: logFile, reason: "Permission denied"),
            editing: penFile
        )
        #expect(failure.exitCode == .environment)
        #expect(failure.message.contains("/tmp/home/activity.jsonl"))
        #expect(failure.message.contains("/tmp/design.pen"))
        #expect(failure.message.contains("on disk"))
    }

    @Test("A log directory that cannot be created for an ordinary reason keeps the $WOODCASE_HOME remedy")
    func logDirectoryFailureIsEnvironment() {
        let failure = CommandFailure.describing(
            PenFileError.cannotOpen(url: logFile, reason: "No such file or directory"),
            editing: penFile
        )
        #expect(failure.exitCode == .environment)
        #expect(failure.message.contains("WOODCASE_HOME"))
    }

    @Test("The log failure names the directory to make and the command that makes it")
    func logFailureNamesTheNextCommand() {
        let failure = CommandFailure.describing(
            PenFileError.writeFailed(url: logFile, reason: "No such file or directory"),
            editing: penFile
        )
        #expect(failure.message.contains("mkdir -p /tmp/home"))
        // One line, not a decoded NSError paragraph.
        #expect(!failure.message.contains("\n"))
    }

    /// Was "Permission denied" until ``SandboxDenial`` started recognizing that reason
    /// as EPERM/EACCES and gave it the sandbox sentence instead — "check
    /// $WOODCASE_HOME" never fixed a sandbox denial, since the directory itself is
    /// forbidden, not merely misnamed.
    @Test("A log directory the environment forbids creating names the sandbox, not $WOODCASE_HOME")
    func logDirectoryFailureFromASandboxNamesTheSandbox() {
        let failure = CommandFailure.describing(
            PenFileError.cannotOpen(url: logFile, reason: "Operation not permitted"),
            editing: penFile
        )
        #expect(failure.exitCode == .environment)
        #expect(failure.message.lowercased().contains("sandbox"))
        #expect(failure.message.contains(logFile.path))
        #expect(!failure.message.contains("WOODCASE_HOME"))
    }

    // MARK: - Editing errors

    @Test("A stale node revision is a conflict")
    func revisionConflictIsConflict() throws {
        let document = try makeDocument()
        let failure = CommandFailure.describing(
            EditingError.revisionConflict(nodeID: "Ttl01", expected: "old", actual: "new"),
            in: document,
            editing: penFile
        )
        #expect(failure.exitCode == .conflict)
        #expect(failure.message.contains("Title"))
    }

    @Test("A stale document revision is a conflict")
    func documentRevisionConflictIsConflict() throws {
        let document = try makeDocument()
        let failure = CommandFailure.describing(
            BatchError.documentRevisionConflict(expected: "old", actual: "new"),
            in: document,
            editing: penFile
        )
        #expect(failure.exitCode == .conflict)
        #expect(failure.message.contains("re-read"))
    }

    @Test("An unknown property is a usage error carrying the batch message")
    func unknownPropertyIsUsage() throws {
        let document = try makeDocument()
        let failure = CommandFailure.describing(
            EditingError.unknownProperty(nodeID: "Cd101", key: "kind.nonsense", nodeType: "frame"),
            in: document,
            editing: penFile
        )
        #expect(failure.exitCode == .usage)
        // The CLI prints the library's sentence, in the shell's dialect — it does not
        // keep a second copy of it.
        #expect(failure.message == BatchErrorMessage.describe(
            EditingError.unknownProperty(nodeID: "Cd101", key: "kind.nonsense", nodeType: "frame"),
            in: document,
            dialect: .command(file: penFile.path)
        ))
        #expect(failure.message.contains("kind.nonsense"))
    }

    @Test("An address that does not resolve is a usage error")
    func addressNotFoundIsUsage() throws {
        let document = try makeDocument()
        let failure = CommandFailure.describing(
            EditingError.addressNotFound(address: "Canvas/Nope", nearMisses: []),
            in: document,
            editing: penFile
        )
        #expect(failure.exitCode == .usage)
        #expect(failure.message.contains("Canvas/Nope"))
    }

    @Test("A malformed batch line is a usage error")
    func malformedLineIsUsage() throws {
        let document = try makeDocument()
        let failure = CommandFailure.describing(
            BatchError.malformedLine(line: 3, reason: "not JSON"),
            in: document,
            editing: penFile
        )
        #expect(failure.exitCode == .usage)
        #expect(failure.message.contains("line 3"))
    }

    @Test("A guard refusal is a usage error")
    func guardRefusalIsUsage() throws {
        let document = try makeDocument()
        let failure = CommandFailure.describing(
            BatchError.setInsideInstance(address: "Board/Chip/Label", instancePath: "Board/Chip"),
            in: document,
            editing: penFile
        )
        #expect(failure.exitCode == .usage)
        #expect(failure.message.contains("override"))
    }

    // MARK: - Parser errors

    @Test("A file that will not parse is a target failure")
    func parserErrorIsTargetFailure() {
        let failure = CommandFailure.describing(
            PenParserError.unsupportedVersion(url: penFile, version: "3.0"), editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("3.0"))
    }

    @Test("A version string that is not major.minor is told what to do about it")
    func unsupportedVersionCarriesARemedy() {
        let failure = CommandFailure.describing(
            PenParserError.unsupportedVersion(url: penFile, version: "banana"), editing: penFile
        )
        #expect(failure.message == """
        Cannot read /tmp/design.pen: its "version" value "banana" is not a major.minor format version \
        — correct the "version" key with `python3 -m json.tool /tmp/design.pen`.
        """)
    }

    @Test("A different major that does not decode says what failed and what to do")
    func differentMajorCarriesARemedy() {
        let failure = CommandFailure.describing(
            PenParserError.differentMajor(url: penFile, version: "3.0", reason: "children[0].width should be a number"),
            editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message == """
        Cannot read /tmp/design.pen: its format version "3.0" is a different major version from the \
        \(PenDocument.currentFormatVersion) this build models, and it does not read as a 2.x document: \
        children[0].width should be a number — update Woodcase to a build that reads 3.x, or check the \
        file's JSON with `python3 -m json.tool /tmp/design.pen`.
        """)
    }

    @Test("A write refused on a read-only format is a target failure that names the read verbs")
    func readOnlyFormatCarriesARemedy() {
        let failure = CommandFailure.describing(
            PenFormatWriteRefusal(url: penFile, declared: PenFormatVersion(major: 3, minor: 0)),
            editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message == """
        Cannot write /tmp/design.pen: it declares .pen format 3.0, a different major version from the \
        \(PenDocument.currentFormatVersion) this build models, so it is read-only — the read verbs \
        (`woodcase tree`, `get`, `lint`, `render`, `shot`) still work; to edit it, update Woodcase to a \
        build that writes 3.x, or edit it in Pen.
        """)
    }

    @Test("A document that will not decode names the file, the key and the next command")
    func decodingFailureCarriesARemedy() {
        let failure = CommandFailure.describing(
            PenParserError.decodingFailed(url: penFile, underlying: Self.badKeyType),
            editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message == """
        Cannot read /tmp/design.pen: not a .pen document — children[0].id should be a string \
        — check the file's JSON with `python3 -m json.tool /tmp/design.pen`.
        """)
    }

    @Test("A parse of bytes, with no file to name, still says what was wrong")
    func decodingFailureWithNoFile() {
        let failure = CommandFailure.describing(
            PenParserError.decodingFailed(url: nil, underlying: Self.badKeyType)
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message == """
        Cannot read the .pen input: not a .pen document — children[0].id should be a string \
        — check the file's JSON.
        """)
    }

    /// A real `DecodingError` for a key of the wrong type, five levels shallower than
    /// a .pen document but the same shape as the ones one produces.
    private static let badKeyType: any Error = {
        struct Document: Decodable {
            struct Child: Decodable {
                let id: String
            }

            let children: [Child]
        }
        do {
            _ = try JSONDecoder().decode(
                Document.self, from: Data(#"{"children": [{"id": 5}]}"#.utf8)
            )
        } catch {
            return error
        }
        return CocoaError(.coderInvalidValue)
    }()

    @Test("A file that cannot be read by the parser is a target failure")
    func parserReadFailureIsTargetFailure() {
        let failure = CommandFailure.describing(
            PenParserError.fileReadFailed(
                url: penFile,
                underlying: CocoaError(.fileReadNoSuchFile)
            ),
            editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("/tmp/design.pen"))
        #expect(failure.message.contains("ls /tmp"))
    }

    @Test("A malformed --theme pin is a usage error")
    func malformedThemePinIsUsage() {
        let failure = CommandFailure.describing(ThemePinParser.PinError.malformedPin("dark"))
        #expect(failure.exitCode == .usage)
        #expect(failure.message.contains("dark"))
    }

    // MARK: - Render and export errors

    @Test("A frame that fails to render is a target failure")
    func renderFailureIsTargetFailure() {
        let failure = CommandFailure.describing(
            Render.RenderError.renderFailed("Home"), editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("Home"))
    }

    @Test("A PNG that fails to export is a target failure")
    func imageExportFailureIsTargetFailure() {
        let failure = CommandFailure.describing(
            PNGEncoder.EncodingError.destinationUnavailable(penFile), editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("/tmp/design.pen"))
    }

    @Test("A PDF that fails to export is a target failure")
    func pdfExportFailureIsTargetFailure() {
        let failure = CommandFailure.describing(
            PDFExporter.ExportError.failedToCreateContext(penFile), editing: penFile
        )
        #expect(failure.exitCode == .targetFailure)
        #expect(failure.message.contains("/tmp/design.pen"))
    }

    @Test("A BatchError raised with no document still renders its full message")
    func batchErrorWithNoDocumentRendersFully() {
        // A batch that will not decode fails before any document is opened, so this is
        // the mapper `apply` actually goes through — unlike every other BatchError test
        // above, which reads through the transaction's document.
        let failure = CommandFailure.describing(BatchError.malformedLine(line: 3, reason: "not JSON"))
        #expect(failure.exitCode == .usage)
        #expect(failure.message == BatchErrorMessage.describe(BatchError.malformedLine(line: 3, reason: "not JSON")))
        #expect(failure.message.contains("line 3"))
        #expect(failure.message.contains("not JSON"))
    }

    @Test("An EditingError raised with no document still carries its remedy")
    func editingErrorWithNoDocumentCarriesItsRemedy() {
        // Raised outside a transaction — there is no document to turn ids into name
        // paths, but the sentence and its remedy do not depend on one.
        let failure = CommandFailure.describing(
            EditingError.addressNotFound(address: "Canvas/Nope", nearMisses: []),
            editing: penFile
        )
        #expect(failure.exitCode == .usage)
        #expect(failure.message.contains("Canvas/Nope"))
        #expect(failure.message.contains(" — "))
        #expect(failure.message.contains("woodcase tree /tmp/design.pen"))
    }

    @Test("An EditingError raised with no document names its node by id, as typed")
    func editingErrorWithNoDocumentNamesTheNodeAsTyped() {
        let failure = CommandFailure.describing(
            EditingError.revisionConflict(nodeID: "Ttl01", expected: "old", actual: "new"),
            editing: penFile
        )
        #expect(failure.exitCode == .conflict)
        #expect(failure.message.contains("Ttl01"))
        #expect(failure.message.contains("woodcase get /tmp/design.pen Ttl01"))
    }

    // MARK: - ArgumentParser and pass-through

    @Test("ArgumentParser's own validation error stays a usage error")
    func validationErrorIsUsage() {
        let failure = CommandFailure.describing(ValidationError("--at needs a number"))
        #expect(failure.exitCode == .usage)
        #expect(failure.message.contains("--at needs a number"))
    }

    @Test("A failure that has already been mapped passes through unchanged")
    func mappedFailurePassesThrough() {
        let original = CommandFailure(message: "already said it", exitCode: .conflict)
        #expect(CommandFailure.describing(original, editing: penFile) == original)
    }

    @Test("An error the table does not know is an environment failure, never a clean negative")
    func unknownErrorIsEnvironment() {
        struct Odd: Error {}
        let failure = CommandFailure.describing(Odd())
        #expect(failure.exitCode == .environment)
        #expect(!failure.message.isEmpty)
    }

    // MARK: - runReportingFailures

    private struct Probe: AsyncParsableCommand {
        func run() async throws {}
    }

    @Test("A mapped failure becomes its exit code")
    func reportingThrowsTheExitCode() async throws {
        let thrown = await #expect(throws: ExitCode.self) {
            try await Probe().runReportingFailures(editing: penFile) {
                throw PenFileError.lockTimeout(url: penFile, timeout: .seconds(5))
            }
        }
        #expect(thrown == .conflict)
    }

    @Test("An exit code thrown by the body is passed straight out")
    func reportingPassesExitCodesThrough() async throws {
        let thrown = await #expect(throws: ExitCode.self) {
            try await Probe().runReportingFailures {
                throw ExitCode.cleanNegative
            }
        }
        #expect(thrown == .cleanNegative)
    }

    @Test("A clean exit is passed straight out for ArgumentParser to print")
    func reportingPassesCleanExitThrough() async throws {
        await #expect(throws: CleanExit.self) {
            try await Probe().runReportingFailures {
                throw CleanExit.message("nothing to do")
            }
        }
    }

    @Test("A body that succeeds returns its value")
    func reportingReturnsTheValue() async throws {
        let value = try await Probe().runReportingFailures { 42 }
        #expect(value == 42)
    }
}
