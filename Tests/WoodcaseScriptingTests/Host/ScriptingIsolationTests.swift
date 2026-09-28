//
//  ScriptingIsolationTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
@testable import WoodcaseScripting

/// The two boundaries the host is built on, asserted by reading the sources.
///
/// Both are the kind of rule a compiler will not notice being broken: a stray
/// `import JavaScriptCore` in the library builds perfectly well on a Mac and takes the
/// whole package off Linux, and a `@MainActor` on one host type builds perfectly well
/// until a caller runs a script from an actor of their own.
@Suite("the scripting host's boundaries")
struct ScriptingIsolationTests {
    /// Every Swift file under a directory, with its text.
    private static func sources(under directory: String) throws -> [(name: String, text: String)] {
        let root = ScriptFixture.packageRoot.appendingPathComponent(directory, isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )
        var found: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            try found.append((url.lastPathComponent, String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    @Test("JavaScriptCore never appears in the Woodcase library")
    func theLibraryNeverImportsJavaScriptCore() throws {
        let sources = try Self.sources(under: "Sources/Woodcase")
        #expect(sources.count > 100, "the enumerator should have found the library's sources")
        let offenders = sources.filter { $0.text.contains("JavaScriptCore") }.map(\.name)
        #expect(
            offenders.isEmpty,
            """
            JavaScriptCore is an Apple framework and the library is cross-platform. \
            The host lives in WoodcaseScripting. Remove it from: \(offenders.joined(separator: ", "))
            """
        )
    }

    @Test("no global actor pins the host")
    func theHostCarriesNoGlobalActor() throws {
        let sources = try Self.sources(under: "Sources/WoodcaseScripting")
        #expect(sources.count > 5, "the enumerator should have found the host's sources")
        var pinned: [String] = []
        for source in sources {
            for (offset, line) in source.text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() where line.contains("@MainActor") || line.contains("@globalActor")
            {
                pinned.append("\(source.name):\(offset + 1)")
            }
        }
        #expect(
            pinned.isEmpty,
            """
            The host runs where its caller runs. Remove the annotation from: \
            \(pinned.joined(separator: ", "))
            """
        )
    }

    @Test("every host source compiles to nothing where JavaScriptCore is absent")
    func everyHostSourceIsGuarded() throws {
        let sources = try Self.sources(under: "Sources/WoodcaseScripting")
        let unguarded = sources
            .filter { !$0.text.contains("#if canImport(JavaScriptCore)") }
            .map(\.name)
        #expect(
            unguarded.isEmpty,
            """
            SwiftPM cannot make a target conditional, so each file guards itself. \
            Wrap: \(unguarded.joined(separator: ", "))
            """
        )
    }
}
