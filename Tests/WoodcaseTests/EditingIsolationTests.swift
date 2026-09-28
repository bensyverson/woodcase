//
//  EditingIsolationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The editing layer's isolation contract, asserted three ways.
///
/// ``EditableDocument`` is non-isolated and non-`Sendable`: whoever creates one owns it,
/// on whatever actor they chose, and the compiler refuses to let it cross an isolation
/// boundary. The three tests here are the three halves of that sentence — no global
/// actor pins the library, the document really is not `Sendable`, and a transaction body
/// runs where its caller runs rather than hopping to the main actor.
@Suite("the editing layer's isolation")
struct EditingIsolationTests {
    // MARK: - No global actor pins the library

    /// The Woodcase library's own sources, found beside this test file.
    private static var librarySources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // WoodcaseTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // the package root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Woodcase")
    }

    @Test("no @MainActor appears anywhere in Sources/Woodcase")
    func sourcesCarryNoGlobalActor() throws {
        let root = Self.librarySources
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )
        var pinned: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() where line.contains("@MainActor")
            {
                pinned.append("\(url.lastPathComponent):\(offset + 1)")
            }
        }
        #expect(scanned > 100, "the enumerator should have found the library's sources")
        #expect(
            pinned.isEmpty,
            """
            The editing layer is owned by its creator, not by the main actor. \
            Remove @MainActor from: \(pinned.joined(separator: ", "))
            """
        )
    }

    // MARK: - The document is not Sendable

    /// Reports whether `T` is `Sendable`, by overload resolution.
    ///
    /// `Sendable` is a marker protocol, so it has no runtime witness and no
    /// `is any Sendable.Type` cast. Overload resolution is the compile-time question
    /// asked at runtime: the constrained overload wins whenever the constraint holds, so
    /// the answer is the compiler's own, frozen into a `Bool` a `#expect` can read.
    ///
    /// - Parameter type: The type to ask about.
    /// - Returns: `true` when `T` conforms to `Sendable`.
    private static func isSendable(_: (some Sendable).Type) -> Bool {
        true
    }

    /// The unconstrained overload, chosen only when `T` is not `Sendable`.
    ///
    /// - Parameter type: The type to ask about.
    /// - Returns: `false`, always — reaching this overload *is* the answer.
    private static func isSendable(_: (some Any).Type) -> Bool {
        false
    }

    @Test("EditableDocument and the state it owns are not Sendable")
    func theDocumentIsNotSendable() {
        #expect(Self.isSendable(EditableDocument.self) == false)
        #expect(Self.isSendable(CRDTDocument.self) == false)
        #expect(Self.isSendable(ActivityRecorder.self) == false)
        #expect(Self.isSendable(ExpansionCache.self) == false)
        #expect(Self.isSendable(LayoutCache.self) == false)
        #expect(Self.isSendable(RevisionCache.self) == false)
    }

    @Test("the values that do cross a boundary are still Sendable")
    func theWireTypesAreSendable() {
        #expect(Self.isSendable(PenDocument.self))
        #expect(Self.isSendable(CRDTOperation.self))
        #expect(Self.isSendable(CRDTSnapshot.self))
        #expect(Self.isSendable(ActivityEvent.self))
    }

    // MARK: - A transaction body runs on its caller's isolation

    /// An actor that is emphatically not the main actor, to run a transaction from.
    private actor Owner {
        /// Counts the edits made through this actor, so the body has isolated state to touch.
        var edits = 0

        /// Runs a transaction over `url` from this actor's isolation and reports where it ran.
        ///
        /// The body reads and writes ``edits`` synchronously, which only compiles if the
        /// compiler agrees the body is isolated to this actor; ``Thread/isMainThread`` and
        /// `assumeIsolated` then say the same thing at runtime.
        ///
        /// - Parameter url: The .pen file to read.
        /// - Returns: Whether the body ran on the main thread, and the edit count it saw.
        func read(_ url: URL) async throws -> (onMain: Bool, edits: Int) {
            let outcome = try await PenFileTransaction.read(at: url) { _ in
                self.edits += 1
                let seen = self.assumeIsolated { $0.edits }
                return (onMain: Thread.isMainThread, edits: seen)
            }
            return outcome.value
        }
    }

    @Test("a transaction body runs on the caller's actor, not the main actor")
    func transactionBodyRunsOnTheCallersIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-isolation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("isolation.pen")
        let document = PenDocument(children: [
            PenNode(id: "Root1", common: PenNodeCommon(name: "Root"), kind: .frame(PenNode.FrameData())),
        ])
        try PenParser.encodeForFile(document).write(to: url)

        let ran = try await Owner().read(url)
        #expect(ran.onMain == false, "the body hopped to the main actor instead of staying with its caller")
        #expect(ran.edits == 1, "the body did not see the owning actor's isolated state")
    }
}
