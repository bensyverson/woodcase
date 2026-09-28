//
//  InjectedAddressTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The address of a child an instance injects into a component's slot frame.
///
/// `tree --expand` prints such a child as an id path (`Inst0/Note0`), and that path
/// has to be an address like any other: it resolves, it names itself back, and an
/// override written to it is the one the expansion applies.
@MainActor
struct InjectedAddressTests {
    // MARK: - Fixture

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func document() throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: "slot-fill", withExtension: "pen", subdirectory: "Fixtures"
        ) else {
            throw FixtureLoadError.notFound("slot-fill.pen")
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    // MARK: - Resolving

    @Test("An injected child resolves by the id path tree --expand prints")
    func injectedChildResolvesByIDPath() throws {
        let doc = try document()
        #expect(try doc.resolve("Inst0/Note0")
            == .instanceDescendant(refID: "Inst0", descendantKey: "Note0"))
        #expect(try doc.resolve("Inst0/Tag00")
            == .instanceDescendant(refID: "Inst0", descendantKey: "Tag00"))
    }

    @Test("An injected child resolves by name, stepping through the slot frame")
    func injectedChildResolvesByName() throws {
        let doc = try document()
        #expect(try doc.resolve("Page/Filled/Body/Note")
            == .instanceDescendant(refID: "Inst0", descendantKey: "Note0"))
    }

    @Test("A descendant of an injected ref resolves, keyed the way the expander applies it")
    func injectedRefDescendantResolves() throws {
        let doc = try document()
        #expect(try doc.resolve("Inst0/Tag00/BTxt0")
            == .instanceDescendant(refID: "Inst0", descendantKey: "Tag00/BTxt0"))
        #expect(try doc.resolve("Page/Filled/Body/Tag/BadgeText")
            == .instanceDescendant(refID: "Inst0", descendantKey: "Tag00/BTxt0"))
    }

    @Test("An instance that injected nothing does not answer to another's injected id")
    func injectionDoesNotLeakBetweenInstances() throws {
        let doc = try document()
        #expect(throws: EditingError.self) { try doc.resolve("Inst1/Note0") }
    }

    @Test("Every id tree --expand prints resolves back to that same id")
    func everyPrintedIDRoundTrips() throws {
        let doc = try document()
        let rows = try TreeView.rows(of: doc, root: "Page0", expandInstances: true)
        for row in rows where row.id.contains(NodeAddress.separator) {
            let resolved = try doc.resolve(row.id)
            #expect(resolved.address == row.id, "\(row.id) resolved to \(resolved.address)")
        }
    }

    @Test("An injected node is a legal tree root, and an injected ref still expands")
    func aninjectedNodeIsATreeRoot() throws {
        let doc = try document()
        let note = try TreeView.rows(of: doc, root: "Inst0/Note0")
        #expect(note.map(\.id) == ["Inst0/Note0"])
        #expect(note.first?.name == "Note")

        let tag = try TreeView.rows(of: doc, root: "Inst0/Tag00", expandInstances: true)
        #expect(tag.map(\.id) == ["Inst0/Tag00", "Inst0/Tag00/BTxt0"])
    }

    // MARK: - Naming

    @Test("An injected child names itself by the path through the slot frame")
    func injectedChildHasANamePath() throws {
        let doc = try document()
        #expect(doc.namePath(ofDescendant: "Note0", in: "Inst0") == "Page/Filled/Body/Note")
        #expect(doc.namePath(ofDescendant: "Tag00/BTxt0", in: "Inst0")
            == "Page/Filled/Body/Tag/BadgeText")
    }

    @Test("The name path of an injected child resolves back to it")
    func injectedNamePathRoundTrips() throws {
        let doc = try document()
        let resolved = ResolvedNodeAddress.instanceDescendant(refID: "Inst0", descendantKey: "Note0")
        #expect(try doc.resolve(doc.namePath(of: resolved)) == resolved)
    }

    // MARK: - The guard

    // An injected child is the instance's own slot content: Pen drops any key of that
    // instance naming it, bare or by path, and draws it as written (measured with the
    // `pen` CLI, `project/2026-09-26-slot-override-keys.md`, follow-up). So a raw
    // operation storing such a key is refused, and an override *addressed* to the child
    // is rewritten into the slot's children instead — `SlotFillRewriteTests`.

    @Test("The children an instance injects are addresses, not keys it can override")
    func injectedChildrenAreAddressesNotKeys() throws {
        let doc = try document()
        let addressable = doc.addressableDescendantKeys(ofInstance: "Inst0")
        let overridable = doc.overridableDescendantKeys(ofInstance: "Inst0")
        for key in ["Note0", "Tag00", "Tag00/BTxt0"] {
            #expect(addressable.contains(key))
            #expect(!overridable.contains(key))
        }
        #expect(overridable.contains("CTtl0"))
        #expect(doc.ownSlotContentKeys(ofInstance: "Inst1").isEmpty)
    }

    @Test("A raw override op on an injected child is refused, naming the slot it lives in")
    func overrideOnAnInjectedChildIsRefused() throws {
        let doc = try document()
        for key in ["Note0", "Tag00/BTxt0"] {
            let error = #expect(throws: EditingError.self) {
                try doc.apply(.overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "Inst0", descendantID: key, properties: ["content": .string("Hi")]
                )))
            }
            guard case let .overrideOnOwnSlotContent(refID, descendantKey, slotPath)? = error else {
                Issue.record("\(key) was not refused as the instance's own slot content: \(String(describing: error))")
                continue
            }
            #expect(refID == "Inst0")
            #expect(descendantKey == key)
            #expect(slotPath == "Page/Filled/Body")
        }
    }

    @Test("A stored override on an injected child does not reach the expansion")
    func storedOverrideOnAnInjectedChildIsDropped() throws {
        let parsed = try PenParser.parse(contentsOf: #require(Bundle.module.url(
            forResource: "slot-fill", withExtension: "pen", subdirectory: "Fixtures"
        )))
        var children = parsed.children
        let page = try #require(children.firstIndex { $0.id == "Page0" })
        guard case var .frame(frame) = children[page].kind,
              let index = frame.children?.firstIndex(where: { $0.id == "Inst0" }),
              case var .ref(data)? = frame.children?[index].kind
        else {
            Issue.record("slot-fill.pen no longer has Inst0 on Page0")
            return
        }
        data.descendants?["Note0"] = PenDescendantOverride(properties: ["content": .string("Hi")])
        frame.children?[index].kind = .ref(data)
        children[page].kind = .frame(frame)
        var edited = parsed
        edited.children = children
        let doc = EditableDocument(from: edited)

        let rows = try TreeView.rows(
            of: doc, root: "Page0", expandInstances: true, properties: ["kind.content"]
        )
        let note = try #require(rows.first { $0.id == "Inst0/Note0" })
        #expect(note.properties?["kind.content"] == .string("filled from the instance"))
    }

    @Test("A miss inside the instance offers the injected children among the candidates")
    func nearMissesNameTheInjectedChildren() throws {
        let doc = try document()
        let error = #expect(throws: EditingError.self) { try doc.resolve("Filled/Note") }
        guard case let .addressNotFound(_, nearMisses)? = error else {
            Issue.record("resolve did not fail with addressNotFound")
            return
        }
        #expect(nearMisses.contains { $0.id == "Inst0/Note0" })
        #expect(nearMisses.contains { $0.path == "Page/Filled/Body/Note" })
    }
}
