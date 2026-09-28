//
//  PenOverrideKeyResolverTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenOverrideKeyResolver`` to the key Pen itself keeps.
///
/// Pen re-saves every override key it can resolve in one canonical form and drops every
/// key it cannot (`slot-override-keys.pen-saved.pen`, written by `scripts/pen-oracle`).
/// So the canonical key the resolver answers for each authored key must be the key in
/// Pen's re-save, and a key Pen dropped must resolve to nothing.
struct PenOverrideKeyResolverTests {
    /// One instance of the fixture: its artboard, its component, and its keys as
    /// authored and as Pen re-saved them.
    struct Case: CustomTestStringConvertible {
        let artboard: String
        let component: String
        let authored: [String]
        let saved: [String]

        var testDescription: String {
            artboard
        }
    }

    static func instances(in file: String) throws -> [String: (component: String, keys: [String])] {
        let url = SlotOverrideKeysSnapshotTests.fixturesDir.appendingPathComponent(file)
        var result: [String: (component: String, keys: [String])] = [:]
        for artboard in try PenParser.parse(Data(contentsOf: url)).children where artboard.common.reusable != true {
            guard let name = artboard.common.name,
                  let instance = artboard.kind.inlineChildren.first,
                  case let .ref(data) = instance.kind
            else { continue }
            result[name] = (data.ref, (data.descendants ?? [:]).keys.sorted())
        }
        return result
    }

    static func cases() throws -> [Case] {
        let authored = try instances(in: "\(SlotOverrideKeysSnapshotTests.fixture).pen")
        let saved = try instances(in: "\(SlotOverrideKeysSnapshotTests.fixture).pen-saved.pen")
        return SlotOverrideKeysSnapshotTests.artboards.compactMap { name in
            guard let instance = authored[name] else { return nil }
            return Case(
                artboard: name, component: instance.component,
                authored: instance.keys, saved: saved[name]?.keys ?? []
            )
        }
    }

    static func registry() throws -> [String: PenNode] {
        let url = SlotOverrideKeysSnapshotTests.fixturesDir
            .appendingPathComponent("\(SlotOverrideKeysSnapshotTests.fixture).pen")
        return try PenRefExpander.buildRegistry(from: PenParser.parse(Data(contentsOf: url)).children)
    }

    @Test("The fixture yields a case for every artboard")
    func everyArtboardIsACase() throws {
        #expect(try Self.cases().map(\.artboard) == SlotOverrideKeysSnapshotTests.artboards)
    }

    @Test("Each key resolves to the key Pen re-saves, or to nothing when Pen drops it", arguments: try cases())
    func canonicalKeyIsPens(_ instance: Case) throws {
        let registry = try Self.registry()
        let resolver = try PenOverrideKeyResolver(component: #require(registry[instance.component]), registry: registry)

        let canonical = Set(instance.authored.compactMap { resolver.target(of: $0)?.canonicalKey })

        #expect(canonical == Set(instance.saved))
        if instance.saved.isEmpty {
            for key in instance.authored {
                #expect(resolver.target(of: key) == nil, "\(key)")
            }
        }
    }

    @Test("A node the component writes into a nested slot is slot content; a nested component's own is not")
    func sites() throws {
        let registry = try Self.registry()
        let scr01 = try PenOverrideKeyResolver(component: #require(registry["Scr01"]), registry: registry)
        let scr03 = try PenOverrideKeyResolver(component: #require(registry["Scr03"]), registry: registry)

        #expect(scr01.target(of: "Ins0A") == .init(canonicalKey: "Ins0A", site: .component))
        #expect(scr01.target(of: "Inj1") == .init(canonicalKey: "Inj1", site: .slotContent))
        #expect(scr01.target(of: "Ins0A/Inj3") == .init(canonicalKey: "Inj3", site: .slotContent))
        #expect(scr01.target(of: "Ins0A/Pln01") == .init(canonicalKey: "Ins0A/Pln01", site: .nested))
        #expect(scr03.target(of: "Mid01/Ins2A/Inj2") == .init(canonicalKey: "Mid01/Ins2A/Inj2", site: .nested))
    }

    @Test("The component root answers to its own id, and a key naming nothing to nothing")
    func rootAndMisses() throws {
        let registry = try Self.registry()
        let scr01 = try PenOverrideKeyResolver(component: #require(registry["Scr01"]), registry: registry)

        #expect(scr01.target(of: "Scr01") == .init(canonicalKey: "Scr01", site: .component))
        #expect(scr01.target(of: "NoSuch") == nil)
        #expect(scr01.target(of: "Ins0A/NoSuch") == nil)
        #expect(scr01.target(of: "") == nil)
    }
}
