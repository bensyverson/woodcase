//
//  InstanceNearMissTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a miss says when the path had entered a component instance.
///
/// Inside an instance a **name** never skips a step, so `Nav/Count` misses where
/// `Nav/Badge/Count` lands. The definition's own copy of `Count` is the wrong thing to
/// offer: the caller wanted the node *in this instance*, and the address that names it
/// is the full path through the component's tree.
@MainActor
struct InstanceNearMissTests {
    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/addressing.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Runs `body` and returns the ``EditingError`` it threw.
    private func editingError(_ body: () throws -> some Any) -> EditingError? {
        do {
            _ = try body()
            Issue.record("expected an EditingError, but nothing was thrown")
            return nil
        } catch let error as EditingError {
            return error
        } catch {
            Issue.record("expected an EditingError, got \(error)")
            return nil
        }
    }

    private func nearMisses(of error: EditingError?) -> [NodeAddressCandidate] {
        guard case let .addressNotFound(_, misses)? = error else { return [] }
        return misses
    }

    @Test("A name path that skips a step inside an instance is offered the instance path")
    func skippingAStepSuggestsTheInstancePath() throws {
        let doc = try makeDocument()

        let misses = nearMisses(of: editingError { try doc.resolve("Dashboard/Body/Nav/Count") })

        #expect(misses.map(\.path) == ["Dashboard/Body/Nav/Badge/Count"])
        #expect(misses.map(\.id) == ["Nav01/Bdg01/Cnt01"])
    }

    @Test("The suggested instance path resolves to the descendant the caller wanted")
    func theSuggestionResolves() throws {
        let doc = try makeDocument()

        let misses = nearMisses(of: editingError { try doc.resolve("Dashboard/Body/Nav/Count") })
        let suggestion = try #require(misses.first)

        #expect(try doc.resolve(suggestion.path)
            == .instanceDescendant(refID: "Nav01", descendantKey: "Bdg01/Cnt01"))
        #expect(try doc.resolve(suggestion.id)
            == .instanceDescendant(refID: "Nav01", descendantKey: "Bdg01/Cnt01"))
    }

    @Test("A miss outside any instance still lists the document's same-named nodes")
    func aMissOutsideAnInstanceIsUnchanged() throws {
        let doc = try makeDocument()

        let misses = nearMisses(of: editingError { try doc.resolve("Dashboard/Header/Nope") })

        #expect(misses.isEmpty)
    }

    @Test("A miss inside an instance that names nothing in the component falls back")
    func aMissNamingNothingInTheComponent() throws {
        let doc = try makeDocument()

        let misses = nearMisses(of: editingError { try doc.resolve("Dashboard/Body/Nav/Title") })

        // `Title` names two nodes in the document and nothing in the component, so the
        // fallback list — same-named nodes anywhere — is what is left to offer.
        #expect(misses.map(\.path) == ["Dashboard/Body/Title", "Dashboard/Header/Title"])
    }

    @Test("The message says a name path into an instance skips no step")
    func theMessageExplainsTheRule() throws {
        let doc = try makeDocument()
        let error = try #require(editingError { try doc.resolve("Dashboard/Body/Nav/Count") })

        let message = BatchErrorMessage.describe(
            error, in: doc, dialect: .command(file: "design.pen")
        )

        #expect(message.contains("Dashboard/Body/Nav/Badge/Count"))
        #expect(message.contains("every frame"))
    }
}
