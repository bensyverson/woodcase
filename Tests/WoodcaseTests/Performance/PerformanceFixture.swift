//
//  PerformanceFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The two documents every budget is measured against, on disk and writable.
///
/// The budgets are stated for a pair of documents on purpose. `woodcase-app.pen` is
/// the largest real file in the repository — the shape a hand-authored document
/// actually has, with components, refs, variables and two themes — and the synthetic
/// document is an order of magnitude bigger than anything hand-authored, which is
/// where a quadratic in the layout engine would show up first.
///
/// Everything here writes into a fresh temporary directory. The bundled fixture is
/// read-only as far as these tests are concerned: a `set` transaction rewrites the
/// file it is given, and rewriting a resource inside the test bundle would corrupt
/// the fixture for every other suite in the run.
enum PerformanceFixture {
    /// How many nodes the synthetic document has.
    ///
    /// Five thousand: an order of magnitude past the largest real fixture, and the
    /// size the performance leaf names.
    static let syntheticNodeCount: Int = 5000

    /// The largest real fixture, 244 KB of hand-authored document.
    ///
    /// - Returns: The bundled `woodcase-app.pen`.
    /// - Throws: An expectation failure when the resource is missing from the bundle.
    static func largestBundled() throws -> URL {
        try #require(
            Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"),
            "woodcase-app.pen is missing from the test bundle."
        )
    }

    /// A writable copy of a `.pen` file in a directory of its own.
    ///
    /// Copied rather than opened in place so the timed transaction is free to write,
    /// and into a fresh directory so the atomic rename has somewhere to put its
    /// temporary neighbour without racing another test.
    ///
    /// - Parameter url: The file to copy.
    /// - Returns: The copy. Delete its parent directory when the test is done.
    /// - Throws: Whatever `FileManager` throws.
    static func workingCopy(of url: URL) throws -> URL {
        let directory = try scratchDirectory()
        let destination = directory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// The synthetic document, generated and written as a real `.pen` file.
    ///
    /// Written through ``PenParser/encodeForFile(_:)``, so what the budget parses is
    /// byte-for-byte what `woodcase` would have written.
    ///
    /// - Parameter nodeCount: How many nodes to generate.
    /// - Returns: The file. Delete its parent directory when the test is done.
    /// - Throws: Whatever the encoder or `FileManager` throws.
    static func syntheticFile(nodeCount: Int = syntheticNodeCount) throws -> URL {
        let directory = try scratchDirectory()
        let destination = directory.appendingPathComponent("synthetic-\(nodeCount).pen")
        let data = try PenParser.encodeForFile(SyntheticPenDocument.make(nodeCount: nodeCount))
        try data.write(to: destination)
        return destination
    }

    /// A path in a fresh temporary directory for a file a test is about to write.
    ///
    /// Nothing is created but the directory, so the caller may write, overwrite, or
    /// never write at all.
    ///
    /// - Parameter name: The file name to place in the directory.
    /// - Returns: The path. Pass it to ``discard(_:)`` when the test is done.
    /// - Throws: Whatever `FileManager` throws.
    static func scratchFile(named name: String) throws -> URL {
        try scratchDirectory().appendingPathComponent(name)
    }

    /// Removes the directory a fixture was placed in.
    ///
    /// Failure is ignored: a temporary directory that outlives the run is untidy, not
    /// a test result, and throwing here would mask the measurement that mattered.
    ///
    /// - Parameter url: A file returned by ``workingCopy(of:)`` or
    ///   ``syntheticFile(nodeCount:)``.
    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Private

    /// A fresh, empty directory under the system temporary directory.
    ///
    /// - Returns: The directory.
    /// - Throws: Whatever `FileManager` throws.
    private static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-performance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
