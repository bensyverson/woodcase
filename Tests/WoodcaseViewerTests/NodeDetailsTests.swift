//
//  NodeDetailsTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// What the Details pane reads off a node: every property it actually carries, each one
/// marked as written literally, bound to a variable, or overridden by the instance it
/// sits inside.
struct NodeDetailsTests {
    // MARK: - The bench

    /// Builds the details for one address of one fixture.
    ///
    /// The same three documents the page uses: the editable store (for addressing and
    /// for the definition a node was cloned from), the expanded tree with variables
    /// still written as `$name`, and the resolved tree that says what those names are
    /// worth under this theme.
    @MainActor
    private func details(
        _ fixture: String,
        node: String,
        theme: [String: String] = [:]
    ) async throws -> NodeDetails {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let url = try ViewerFixtures.copy(fixture, into: scratch)
        return try await PenFileTransaction.read(at: url) { document in
            let expanded = PenRefExpander.expand(document.materialize(), for: .canvas)
            return try NodeDetails.of(
                address: node,
                in: document,
                expanded: expanded,
                resolved: PenVariableResolver.resolve(expanded, theme: theme)
            )
        }.value
    }

    // MARK: - Literals

    @MainActor
    @Test("A plain node's properties are marked literal, with the value the file holds")
    func plainNodeIsLiteral() async throws {
        let details = try await details("addressing.pen", node: "Ttl01")

        #expect(details.type == "text")
        #expect(details.name == "Title")
        #expect(details.instance == nil)

        let content = try #require(details.rows.first { $0.path == "kind.content" })
        #expect(content.origin == .literal)
        #expect(content.value == "Dashboard")
        #expect(content.key == "content")
        #expect(content.variables.isEmpty)
        #expect(content.source == nil)
    }

    @MainActor
    @Test("Only the properties the node actually carries are listed")
    func unsetPropertiesAreNotListed() async throws {
        let details = try await details("addressing.pen", node: "Ttl01")
        let paths = details.rows.map(\.path)

        #expect(paths.contains("common.name"))
        #expect(paths.contains("kind.content"))
        // A text node accepts these; this one sets none of them.
        #expect(!paths.contains("kind.fontSize"))
        #expect(!paths.contains("kind.fills"))
        // Sorted, so the shared properties read before the kind's own.
        #expect(paths == paths.sorted())
    }

    // MARK: - Variables

    @MainActor
    @Test("A property written as $name is marked as a variable, resolved under the theme")
    func variableIsMarkedAndResolved() async throws {
        let compact = try await details(
            "parser-themed-variables.pen", node: "label", theme: ["density": "compact"]
        )
        let size = try #require(compact.rows.first { $0.path == "kind.fontSize" })
        #expect(size.origin == .variable)
        #expect(size.variables == ["textSize"])
        #expect(size.value == "14")

        let regular = try await details(
            "parser-themed-variables.pen", node: "label", theme: ["density": "regular"]
        )
        let resized = try #require(regular.rows.first { $0.path == "kind.fontSize" })
        #expect(resized.origin == .variable)
        #expect(resized.value == "18")
    }

    @MainActor
    @Test("A variable nested inside a fill is found, not only a bare $name")
    func variableInsideAFillIsFound() async throws {
        let details = try await details(
            "parser-themed-variables.pen", node: "container", theme: ["mode": "dark"]
        )
        let fills = try #require(details.rows.first { $0.path == "kind.fills" })
        #expect(fills.origin == .variable)
        #expect(fills.variables == ["bgColor"])
        #expect(fills.value.contains("#1A1A1A"))
    }

    // MARK: - Overrides

    @MainActor
    @Test("A node inside an instance shows an overridden property marked with its source")
    func overrideNamesTheInstance() async throws {
        let details = try await details("addressing.pen", node: "Nav01/Lbl01")

        #expect(details.id == "Nav01/Lbl01")
        #expect(details.instance == "Nav01")

        let content = try #require(details.rows.first { $0.path == "kind.content" })
        #expect(content.origin == .override)
        #expect(content.value == "Menu")
        let source = try #require(content.source)
        #expect(source.instance == "Nav01")
        #expect(source.path == "Dashboard/Body/Nav")
        #expect(source.was == "Click")
    }

    @MainActor
    @Test("An override reaching into a nested instance still names the outer instance")
    func nestedOverrideNamesTheOuterInstance() async throws {
        let details = try await details("addressing.pen", node: "Nav01/Bdg01/Cnt01")

        let content = try #require(details.rows.first { $0.path == "kind.content" })
        #expect(content.origin == .override)
        #expect(content.value == "3")
        #expect(content.source?.instance == "Nav01")
        #expect(content.source?.was == "0")
    }

    @MainActor
    @Test("A property the instance leaves alone stays literal, even inside an instance")
    func untouchedPropertyInsideAnInstanceIsLiteral() async throws {
        let details = try await details("addressing.pen", node: "Nav01/Bdg01/Cnt01")
        let name = try #require(details.rows.first { $0.path == "common.name" })
        #expect(name.origin == .literal)
        #expect(name.value == "Count")
    }

    @MainActor
    @Test("An address that names nothing is an error, never an empty list of rows")
    func unknownAddressThrows() async throws {
        await #expect(throws: (any Error).self) {
            try await details("addressing.pen", node: "NoSuchNode")
        }
    }
}
