//
//  DesignTopicComponentClaimsTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// Every rule `woodcase help design` states about components, run against a file.
///
/// This is the half of the topic the Quill run paid for: four agents deep-built every
/// composite because one message denied slot filling, and a brief told a fifth to keep
/// child *names* stable when the overrides are keyed by *ids*. So each claim here is
/// asserted twice — that the topic still says it, and that the command it names still
/// does it. The naming, value and read half is in ``DesignTopicClaimsTests``.
@Suite("What `help design` claims about components")
struct DesignTopicComponentClaimsTests {
    // MARK: - Id-keyed overrides

    @Test("An override survives renaming the definition's child, because it is keyed by id")
    func overridesAreKeyedByID() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "child ids")

        #expect(try fixture.run(
            "override", fixture.file.path, "Filled/Title", "content=Overridden", "--as", "ana"
        ).status == 0)
        #expect(try fixture.run(
            "set", fixture.file.path, "Card/Title", "common.name=Heading", "--as", "ana"
        ).status == 0)

        let after = try fixture.run("tree", fixture.file.path, "Filled", "--expand", "--props", "kind.content")
        #expect(after.status == 0)
        #expect(after.stdout.contains("Heading"), "the definition's child was not renamed")
        #expect(after.stdout.contains("Overridden"), "renaming the definition's child dropped the override")
    }

    @Test("`replace` on a live definition drops every override whose id it does not carry forward")
    func replaceDropsOverridesItDoesNotCarry() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "does not carry")

        #expect(try fixture.run(
            "override", fixture.file.path, "Filled/Title", "content=Overridden", "--as", "ana"
        ).status == 0)
        #expect(try fixture.run("tree", fixture.file.path, "Filled", "--expand", "--props", "kind.content")
            .stdout.contains("Overridden"))

        let rebuilt = try fixture.run(
            ["replace", fixture.file.path, "Card", "-F", "-", "--as", "ana"],
            stdin: Data(##"""
            {"type":"frame","name":"Card","reusable":true,"width":200,"height":"fit_content",
             "layout":"vertical","gap":8,"padding":8,"children":[
              {"type":"text","name":"Title","content":"Card","fontSize":16,"fill":"#111111",
               "width":160,"height":20}]}
            """##.utf8)
        )
        #expect(rebuilt.status == 0)

        let after = try fixture.run("tree", fixture.file.path, "Filled", "--expand", "--props", "kind.content")
        #expect(after.status == 0)
        #expect(
            !after.stdout.contains("Overridden"),
            "the override outlived a replace that minted a new id for the node it named"
        )
    }

    @Test("`replace --help` says the overrides it does not carry forward are dropped")
    func replaceHelpSaysWhatItDrops() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        let run = try fixture.run("replace", "--help")
        #expect(run.status == 0)
        // ArgumentParser rewraps a discussion, so a claim is checked against the text
        // with its line breaks folded out rather than against the wrapped lines.
        let prose = run.stdout.split(separator: "\n").joined(separator: " ")
        for phrase in [
            "overrides are keyed by the DEFINITION'S CHILD IDS",
            "does not carry forward is dropped",
            "get <definition> --instances",
        ] {
            #expect(prose.contains(phrase), "replace --help does not say: \(phrase)")
        }
    }

    // MARK: - Variants

    @Test("enabled=false on an instance descendant is the variant mechanism")
    func enabledFalseIsTheVariantMechanism() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "enabled=false")

        let before = try Self.rootHeight(of: "Filled", in: fixture)
        let written = try fixture.run(
            "override", fixture.file.path, "Filled/Footer", "enabled=false", "--as", "ana"
        )
        #expect(written.status == 0)
        #expect(written.stdout.contains("note"), "the variant idiom is not reported as a note")

        let after = try Self.rootHeight(of: "Filled", in: fixture)
        #expect(after < before, "a disabled child did not leave the layout: \(before)pt to \(after)pt")

        let listing = try fixture.run("tree", fixture.file.path, "Filled", "--expand")
        #expect(listing.status == 0)
        #expect(listing.stdout.contains("Footer"), "the disabled child is not listed at all")
    }

    // MARK: - Refs in an add subtree

    @Test("A ref may be written inline in an `add` subtree, filling a slot in the same write")
    func refsMayBeWrittenInlineInAnAddSubtree() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "\"type\":\"ref\"")

        let added = try fixture.run(
            ["add", fixture.file.path, "Page", "-F", "-", "--as", "ana"],
            stdin: Data(##"""
            {"type":"ref","name":"Inline","ref":"Card0","descendants":{"CSlt0":{"children":[
              {"id":"Inl01","type":"text","name":"Inline note","content":"filled inline",
               "fontSize":12,"fill":"#333333","width":150,"height":16}]}}}
            """##.utf8)
        )
        #expect(added.status == 0, "\(added.stderr)")

        let read = try fixture.run("tree", fixture.file.path, "Inline", "--expand", "--props", "kind.content")
        #expect(read.status == 0)
        #expect(read.stdout.contains("filled inline"), "the inline ref's slot children did not render")
    }

    // MARK: - Slots

    @Test("A slot frame is filled from the instance by overriding its children")
    func slotsAreFilledByOverridingChildren() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "children=")

        let filled = try fixture.run(
            "override", fixture.file.path, "Empty/Body",
            ##"children=[{"id":"Late0","type":"text","name":"Late","content":"added later","##
                + ##""fontSize":12,"fill":"#333333","width":150,"height":16}]"##,
            "--as", "ana"
        )
        #expect(filled.status == 0, "\(filled.stderr)")
        #expect(
            !filled.stdout.contains("nothing will read it"),
            "filling a slot was reported as an override nothing reads"
        )

        let read = try fixture.run("tree", fixture.file.path, "Empty", "--expand", "--props", "kind.content")
        #expect(read.status == 0)
        #expect(read.stdout.contains("added later"), "tree --expand does not show the injected children")
    }

    @Test("An injected child needs an id, and its name path never skips the slot frame")
    func injectedChildrenNeedIDsAndNamesGoThroughTheSlot() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "`get Inst/Note0` reads one")

        let unnamed = try fixture.run(
            "override", fixture.file.path, "Empty/Body",
            ##"children=[{"type":"text","name":"Late","content":"x","fill":"#333333"}]"##,
            "--as", "ana"
        )
        #expect(unnamed.status != 0, "an injected child with no id was accepted")
        #expect(unnamed.stderr.contains("id"), "the refusal does not name the missing id")

        // `Filled/Body/Note` is the address; a name path never skips the slot frame.
        let unreachable = try fixture.run("get", fixture.file.path, "Filled/Note")
        #expect(unreachable.status == 2, "a name path skipped the slot frame")
    }

    // MARK: - The instance root

    @Test("`override <instance>` writes the component root; `set <instance>` writes the ref node")
    func overrideWritesTheRootAndSetWritesTheRef() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "the ref node")

        let root = try fixture.run("override", fixture.file.path, "Filled", "gap=20", "--as", "ana")
        #expect(root.status == 0, "\(root.stderr)")

        let ref = try fixture.run("set", fixture.file.path, "Filled", "common.x=20", "--as", "ana")
        #expect(ref.status == 0, "\(ref.stderr)")

        // A key the ref reserves for itself belongs to `set`, and the refusal says so.
        let reserved = try fixture.run("override", fixture.file.path, "Filled", "opacity=0.5", "--as", "ana")
        #expect(reserved.status != 0, "override wrote a key the ref reserves for itself")
        #expect(reserved.stderr.contains("woodcase set"), "the refusal does not name the command that works")
    }

    @Test("--unset removes an override; key=null does not")
    func unsetRemovesAnOverrideAndNullDoesNot() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "--unset")

        #expect(try fixture.run(
            "override", fixture.file.path, "Filled/Title", "fontSize=22", "--as", "ana"
        ).status == 0)

        let nulled = try fixture.run(
            "override", fixture.file.path, "Filled/Title", "fontSize=null", "--as", "ana"
        )
        #expect(nulled.status == 0)
        let stored = try Self.overrides(of: "Filled", in: fixture)["CTtl0"] as? [String: Any]
        #expect(stored?.keys.contains("fontSize") == true, "key=null removed the override instead of storing a null")

        let unset = try fixture.run(
            "override", fixture.file.path, "Filled/Title", "--unset", "fontSize", "--as", "ana"
        )
        #expect(unset.status == 0)
        let remaining = try Self.overrides(of: "Filled", in: fixture)["CTtl0"] as? [String: Any]
        #expect(remaining?["fontSize"] == nil, "--unset left the override behind")
    }

    // MARK: - Reads over a component

    @Test("`get <definition> --instances` lists who instances it")
    func getInstancesListsWhoDrawsTheDefinition() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "--instances")

        let run = try fixture.run("get", fixture.file.path, "Card", "--instances")
        #expect(run.status == 0)
        #expect(run.stdout.contains("Page/Filled"), "the instance list omits Page/Filled")
        #expect(run.stdout.contains("Page/Empty"), "the instance list omits Page/Empty")
    }

    @Test("`get <instance> --expand` is the bulk content read")
    func getExpandIsTheBulkContentRead() throws {
        let fixture = try CommandFixture(fixture: "slot-fill.pen")
        try Self.expectDesignTopic(fixture, teaches: "--expand")

        let run = try fixture.run("get", fixture.file.path, "Filled", "--expand")
        #expect(run.status == 0)
        // One read, and the whole instance comes back: the definition's own children,
        // the overrides applied, and the nested instance inside the filled slot.
        for content in ["Card", "filled from the instance", "live"] {
            #expect(run.stdout.contains(content), "--expand did not carry \(content)")
        }
    }

    // MARK: - Helpers

    /// Asserts `woodcase help design` still carries a claim, before the claim is tested.
    ///
    /// - Parameters:
    ///   - fixture: The fixture whose binary to run.
    ///   - phrase: The wording the topic must still contain.
    /// - Throws: Whatever launching the binary throws.
    private static func expectDesignTopic(_ fixture: CommandFixture, teaches phrase: String) throws {
        let run = try fixture.run("help", "design")
        #expect(run.status == 0)
        #expect(run.stdout.contains(phrase), "`help design` no longer says \(phrase)")
    }

    /// One instance's stored `descendants` map, read back through `get --json`.
    ///
    /// - Parameters:
    ///   - address: The instance to read.
    ///   - fixture: The fixture holding the file.
    /// - Returns: The map, empty when the instance carries none.
    /// - Throws: Whatever launching the binary throws.
    private static func overrides(of address: String, in fixture: CommandFixture) throws -> [String: Any] {
        let run = try fixture.run("get", fixture.file.path, address, "--json")
        #expect(run.status == 0)
        guard let object = try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any],
              let node = object["node"] as? [String: Any]
        else {
            Issue.record("get --json carried no node for \(address): \(run.stdout)")
            return [:]
        }
        return node["descendants"] as? [String: Any] ?? [:]
    }

    /// The settled height of one node, read from `tree --json`.
    ///
    /// - Parameters:
    ///   - address: The node to read.
    ///   - fixture: The fixture holding the file.
    /// - Returns: The height in points.
    /// - Throws: Whatever launching the binary throws.
    private static func rootHeight(of address: String, in fixture: CommandFixture) throws -> Double {
        let run = try fixture.run("tree", fixture.file.path, address, "--json")
        #expect(run.status == 0)
        guard let object = try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any],
              let rows = object["rows"] as? [[String: Any]],
              let rect = rows.first?["rect"] as? [String: Any],
              let height = rect["height"] as? Double
        else {
            Issue.record("tree --json carried no rect for \(address): \(run.stdout)")
            return 0
        }
        return height
    }
}
