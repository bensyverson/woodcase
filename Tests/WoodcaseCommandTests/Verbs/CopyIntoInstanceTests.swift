//
//  CopyIntoInstanceTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Placing a component and titling it in one command.
///
/// Copying a reusable component makes a `ref`, and a `ref` stores nothing of its
/// own — so the nested property `cp --help` puts in its own example had nowhere to
/// land and the whole copy was abandoned. `cp` now writes those as the instance's
/// overrides, translating the property-path vocabulary into the raw .pen names the
/// `descendants` map is keyed in.
@Suite("woodcase cp into a component instance")
struct CopyIntoInstanceTests {
    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    @Test("A nested property on a placed component becomes an override, in the same write")
    func nestedPropertyBecomesAnOverride() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas",
            "common.name=Chip", "Label/kind.content=Hello", "--as", "ana"
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        #expect(run.stderr.isEmpty)

        let probe = try PenFileProbe(fixture.file)
        let copy = try #require(probe.node("Canvas/Chip"))
        #expect(overrides(of: copy)["Lbl01"]?.properties["content"] == .string("Hello"))
    }

    @Test("The translation covers a common path and a renamed JSON key")
    func translatesCommonAndRenamedKeys() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas",
            "common.name=Chip", "Label/common.name=Tag", "Label/kind.fills=#FF0000"
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        let stored = try overrides(of: PenFileProbe(fixture.file).node("Canvas/Chip"))["Lbl01"]
        #expect(stored?.properties["name"] == .string("Tag"))
        #expect(stored?.properties["fill"] == .string("#FF0000"))
    }

    @Test("A raw .pen name on a nested property is taken as written")
    func rawNamesStillWork() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas",
            "common.name=Chip", "Label/content=Raw"
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        let stored = try overrides(of: PenFileProbe(fixture.file).node("Canvas/Chip"))["Lbl01"]
        #expect(stored?.properties["content"] == .string("Raw"))
    }

    @Test("A nested property that names nothing in the placed component is still refused")
    func unknownNestedPathIsRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas", "Nowhere/kind.content=Hello"
        )

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("Nowhere"))
        #expect(try PenFileProbe(fixture.file).node("Canvas/Component") == nil)
    }

    @Test("The overrides land on the copy, never on the component it was placed from")
    func theComponentIsUntouched() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            "cp", fixture.file.path, "Component", "Canvas",
            "common.name=Chip", "Label/kind.content=Hello"
        )

        #expect(run.status == 0, "cp failed: \(run.stderr)")
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.node("Component/Label")?.textContent == "chip")
    }
}
