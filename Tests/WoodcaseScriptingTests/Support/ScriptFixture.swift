//
//  ScriptFixture.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase

/// Documents and scratch files the host's tests run against.
///
/// The .pen fixtures live in `Tests/WoodcaseTests/Fixtures` and are found by path, not
/// copied in as a resource: one copy of `batch.pen` in the repository, and the same bytes
/// the CLI's own tests run against, which is what makes the parity suite meaningful.
enum ScriptFixture {
    /// The repository's fixture directory.
    static var directory: URL {
        packageRoot.appendingPathComponent("Tests/WoodcaseTests/Fixtures", isDirectory: true)
    }

    /// The package root, for the greps that read the sources themselves.
    ///
    /// Walked up from this file, so the count of steps is this file's depth: it lives in
    /// `Tests/WoodcaseScriptingTests/Support/`, and moving it means changing the count.
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // this file, leaving Support/
            .deletingLastPathComponent() // Support/, leaving WoodcaseScriptingTests/
            .deletingLastPathComponent() // WoodcaseScriptingTests/, leaving Tests/
            .deletingLastPathComponent() // Tests/, leaving the package root
    }

    /// One fixture's URL.
    ///
    /// - Parameter name: The file name, for example `batch.pen`.
    /// - Returns: Its URL.
    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// One fixture, parsed and flattened.
    ///
    /// - Parameter name: The file name, for example `batch.pen`.
    /// - Returns: The document, ready to hand to the host.
    /// - Throws: Whatever reading or parsing the file throws.
    static func document(_ name: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: url(name)))
    }

    /// A two-node document whose nodes share a name, for the ambiguous-address tests.
    ///
    /// Built in memory rather than added as a fixture: the whole point is one property —
    /// two nodes answering to `Title` — and a file would hide it three directories away.
    static func ambiguous() -> EditableDocument {
        EditableDocument(from: PenDocument(children: [
            PenNode(
                id: "Frm01",
                common: PenNodeCommon(name: "First"),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(id: "Ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData())),
                ]))
            ),
            PenNode(
                id: "Frm02",
                common: PenNodeCommon(name: "Second"),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(id: "Ttl02", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData())),
                ]))
            ),
        ]))
    }

    /// Writes a script to a scratch file that is deleted with the returned handle.
    ///
    /// - Parameters:
    ///   - body: The JavaScript to write.
    ///   - name: The file name to give it.
    /// - Returns: A handle owning the temporary directory.
    /// - Throws: Whatever `FileManager` throws.
    static func file(_ body: String, named name: String) throws -> Scratch {
        let scratch = try Scratch()
        let url = scratch.root.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return scratch.naming(url)
    }

    /// A temporary directory that removes itself.
    final class Scratch {
        /// Makes the directory.
        ///
        /// - Throws: Whatever `FileManager` throws.
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("woodcase-script-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        /// The directory.
        let root: URL

        /// The file the scratch was made for.
        private(set) var file: URL?

        /// Records which file this scratch was made for.
        ///
        /// - Parameter url: The file.
        /// - Returns: `self`, so a caller can chain.
        func naming(_ url: URL) -> Scratch {
            file = url
            return self
        }
    }
}
