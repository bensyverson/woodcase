//
//  ComponentParameterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The library seams behind a component's declared parameters: reading
/// `common.metadata._props` off a node, and routing a `cp` key through it.
@MainActor
@Suite("Component parameters")
struct ComponentParameterTests {
    /// The fixture document, as an editable one.
    private func document() throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: "component-props", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureMissing.notFound
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private enum FixtureMissing: Error { case notFound }

    // MARK: - Reading the declaration

    @Test("Every declared parameter is read, sorted by name")
    func parametersAreReadInNameOrder() throws {
        let parameters = try document().parameters(ofComponent: "Stc01")

        #expect(parameters.map(\.name) == ["gone", "label", "tint", "width"])
    }

    @Test("A parameter resolves to the descendant its path names, and that node's property")
    func aParameterResolvesToItsDescendant() throws {
        let parameters = try document().parameters(ofComponent: "Stc01")

        let label = try #require(parameters.first { $0.name == "label" })
        #expect(label.path == "Body/Title")
        #expect(label.nodeID == "Ttl01")
        #expect(label.property == "kind.content")
        #expect(label.type == .string)

        let tint = try #require(parameters.first { $0.name == "tint" })
        #expect(tint.nodeID == "Swt01")
        #expect(tint.property == "kind.fills")
        #expect(tint.type == .color)
    }

    @Test("A path that names nothing resolves to nothing, and says so rather than throwing")
    func anUnresolvablePathIsReported() throws {
        let parameters = try document().parameters(ofComponent: "Stc01")

        let gone = try #require(parameters.first { $0.name == "gone" })
        #expect(gone.path == "Body/Missing")
        #expect(gone.nodeID == nil)
        #expect(gone.property == nil)
    }

    @Test("A node that declares nothing has no parameters")
    func aPlainComponentHasNone() throws {
        #expect(try document().parameters(ofComponent: "Pln01").isEmpty)
    }

    // MARK: - The copy seam

    @Test("A parameter name routes a cp key to the descendant and property it declares")
    func aParameterNameRoutesACopyKey() throws {
        let parameters = try document().parameters(ofComponent: "Stc01")

        let (destination, property) = CopyAssignment.destination(of: "label", parameters: parameters)

        #expect(destination == .descendant(path: "Body/Title"))
        #expect(property == "kind.content")
    }

    @Test("A path key is unchanged by the parameters beside it")
    func aPathKeyIsUnchanged() throws {
        let parameters = try document().parameters(ofComponent: "Stc01")

        let (destination, property) = CopyAssignment.destination(
            of: "Body/Title/kind.content", parameters: parameters
        )

        #expect(destination == .descendant(path: "Body/Title"))
        #expect(property == "kind.content")
    }

    @Test("A root key that names no parameter stays on the root")
    func anUndeclaredRootKeyStaysOnTheRoot() throws {
        let parameters = try document().parameters(ofComponent: "Stc01")

        let (destination, property) = CopyAssignment.destination(of: "common.name", parameters: parameters)

        #expect(destination == .root)
        #expect(property == "common.name")
    }

    @Test("A parameter that resolves to nothing leaves its key on the root, for the refusal to catch")
    func anUnresolvableParameterStaysOnTheRoot() throws {
        let parameters = try document().parameters(ofComponent: "Stc01")

        let (destination, _) = CopyAssignment.destination(of: "gone", parameters: parameters)

        #expect(destination == .root)
    }
}
