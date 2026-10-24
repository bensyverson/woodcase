//
//  PenBundleHistoryFilesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Which of a bundle's `history/` files are writers' files, and copying just those — the
/// public choice an app that writes its own copy of a bundle (Penumbra's `NSDocument`
/// saves) uses, and ``PenBundle/copy(_:to:history:)`` uses too.
struct PenBundleHistoryFilesTests {
    typealias Source = PenBundleHistoryTests.Source

    @Test("historyFiles lists every writer's live and archived file, sorted, and skips the rest of history/")
    func listsWriterFiles() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let history = source.bundle.appendingPathComponent("history")
        try Data().write(to: history.appendingPathComponent(".DS_Store"))

        let files = PenBundle.historyFiles(in: source.bundle)

        #expect(files.map(\.lastPathComponent) == source.carried)
        #expect(files.map(\.standardizedFileURL) == source.carried.map {
            history.appendingPathComponent($0).standardizedFileURL
        })
    }

    @Test("historyFiles is empty for a bundle with no history/")
    func emptyWithoutHistory() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let bare = source.project.root.appendingPathComponent("Bare.umbra")
        try await PenBundle.copy(source.bundle, to: bare, history: .omitted)

        #expect(PenBundle.historyFiles(in: bare).isEmpty)
    }

    @Test("copyHistory copies only the writers' files, byte for byte, creating the directory")
    func copiesWriterFiles() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let directory = source.project.root.appendingPathComponent("Other.umbra/history")

        let copied = try PenBundle.copyHistory(from: source.bundle, into: directory)

        #expect(copied == source.carried.count)
        #expect(source.historyNames(in: directory) == source.carried)
        for name in source.carried {
            #expect(try Data(contentsOf: directory.appendingPathComponent(name))
                == Data(contentsOf: source.bundle.appendingPathComponent("history/\(name)")))
        }
    }
}
