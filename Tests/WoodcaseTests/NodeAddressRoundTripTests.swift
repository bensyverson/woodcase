//
//  NodeAddressRoundTripTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The contract between a read and a write: every address a settled tree row prints —
/// its id-path, its `address` column, and the name path an error message would print
/// for it — resolves back to the node the row describes.
///
/// The sharp case is a `ref` nested inside a component below a container: the id-path
/// the tree prints (`Card1/Btn02`) names the outer instance and the node, and skips
/// the group in between, because that is exactly how Pen keys its `descendants` map.
@MainActor
struct NodeAddressRoundTripTests {
    // MARK: - Helpers

    private func document(_ fixture: String) throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixture)")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Runs `body` and returns the ``EditingError`` it threw, recording an issue if it threw nothing.
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

    // MARK: - Every row round-trips

    @Test(
        "Every address an expanded tree row prints resolves back to that row",
        arguments: AddressFixture.both
    )
    func expandedRowAddressesResolve(fixture: String) throws {
        let doc = try document(fixture)
        for row in try TreeView.rows(of: doc, expandInstances: true) {
            let resolved = try doc.resolve(row.address)
            #expect(
                resolved.address == row.id,
                "address \(row.address) resolved to \(resolved.address), not \(row.id)"
            )
            #expect(try doc.resolve(row.id) == resolved, "the id-path \(row.id) does not resolve to its row")
            let path = doc.namePath(of: resolved)
            #expect(try doc.resolve(path) == resolved, "the name path \(path) does not resolve back")
        }
    }

    @Test(
        "Every expanded row's target settles under the row's id",
        arguments: AddressFixture.both
    )
    func expandedIDsMatchRowIDs(fixture: String) throws {
        let doc = try document(fixture)
        for row in try TreeView.rows(of: doc, expandInstances: true) {
            let expanded = try doc.expandedID(of: doc.resolve(row.address))
            if row.isInstance {
                // An instance's expanded root keeps the component's own id under the ref's.
                #expect(expanded.hasPrefix("\(row.id)\(NodeAddress.separator)"), "instance \(row.id)")
            } else {
                #expect(expanded == row.id)
            }
        }
    }

    // MARK: - A ref below a container

    @Test("A node below a container inside a component is addressed by the id-path the tree prints")
    func nestedRefBelowAGroupResolves() throws {
        let doc = try document(AddressFixture.nested)
        #expect(try doc.resolve("Card1/Ttl03")
            == .instanceDescendant(refID: "Card1", descendantKey: "Ttl03"))
        #expect(try doc.resolve("Card1/Btn02")
            == .instanceDescendant(refID: "Card1", descendantKey: "Btn02"))
        #expect(try doc.resolve("Card1/Btn02/Lbl02")
            == .instanceDescendant(refID: "Card1", descendantKey: "Btn02/Lbl02"))
        #expect(try doc.resolve("Card1/Btn02/Ico02")
            == .instanceDescendant(refID: "Card1", descendantKey: "Btn02/Ico02"))
    }

    @Test("A component definition's own nested instance is addressed the same way")
    func definitionsNestedInstanceResolves() throws {
        let doc = try document(AddressFixture.nested)
        #expect(try doc.resolve("Btn02/Ico02")
            == .instanceDescendant(refID: "Btn02", descendantKey: "Ico02"))
    }

    @Test("The keys those addresses produce are the keys the fixture's overrides already store")
    func keysMatchTheStoredOverrides() throws {
        let doc = try document(AddressFixture.nested)
        guard case let .ref(refData) = try #require(doc.node(id: "Card1")).kind else {
            Issue.record("Card1 is not a ref")
            return
        }
        let stored = Set((refData.descendants ?? [:]).keys)
        let title = try #require(doc.resolve("Card1/Ttl03").descendantKey)
        let label = try #require(doc.resolve("Card1/Btn02/Lbl02").descendantKey)
        #expect(stored.contains(title))
        #expect(stored.contains(label))
    }

    // MARK: - Ids skip levels, names do not

    @Test("Inside an instance an id may skip the containers, a name may not")
    func namesStillNeedEveryStep() throws {
        let doc = try document(AddressFixture.nested)
        let target = ResolvedNodeAddress.instanceDescendant(refID: "Card1", descendantKey: "Ttl03")

        #expect(editingError { try doc.resolve("Card1/Title") }?.isAddressNotFound == true)
        #expect(try doc.resolve("Card1/Row/Title") == target)
        #expect(try doc.resolve("Card1/#Ttl03") == target)
    }

    @Test("The component root is still not a segment of its own")
    func componentRootIsNotASegment() throws {
        let doc = try document(AddressFixture.nested)
        #expect(editingError { try doc.resolve("Card1/CardBase/Row") }?.isAddressNotFound == true)
    }

    // MARK: - Name paths

    @Test("A descendant's name path names every step, including the containers its key skips")
    func namePathNamesEveryStep() throws {
        let doc = try document(AddressFixture.nested)
        #expect(doc.namePath(ofDescendant: "Ttl03", in: "Card1") == "Page/Card/Row/Title")
        #expect(doc.namePath(ofDescendant: "Btn02", in: "Card1") == "Page/Card/Row/Button")
        #expect(doc.namePath(ofDescendant: "Btn02/Ico02", in: "Card1")
            == "Page/Card/Row/Button/Stack/Icon")
    }
}

/// The fixtures this suite runs over, outside the suite so the `@Test` macro can
/// read them without hopping to the main actor.
private enum AddressFixture {
    /// The instance whose component nests another instance below a group.
    static let nested = "addressing-nested-instance.pen"

    /// Both instance fixtures: the flat one, and the one with a container in the way.
    static let both = ["addressing.pen", nested]
}

private extension EditingError {
    /// Whether this is ``EditingError/addressNotFound(address:nearMisses:)``.
    var isAddressNotFound: Bool {
        if case .addressNotFound = self { return true }
        return false
    }
}
