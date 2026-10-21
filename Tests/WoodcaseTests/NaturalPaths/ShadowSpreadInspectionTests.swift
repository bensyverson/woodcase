//
//  ShadowSpreadInspectionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An inspection lists an instance's override of `kind.effects` with each shadow carrying
/// the spread the instance draws it with, so an inspector that edits the list and writes it
/// back restates every spread (leaf oNeklc): a whole `kind.effects` write drops the spreads
/// it does not name.
@MainActor
struct ShadowSpreadInspectionTests {
    private static let shadow = ##"{"type": "shadow", "blur": 0, "color": "#000000"}"##
    private static let dropped = ##"{"type": "shadow", "offset": {"x": 0, "y": 20}, "blur": 0, "color": "#000000"}"##

    /// `Chip` is a component whose root and `Box` child spread their shadow 4; `Inst` overrides
    /// the box's effects with the dropped shadow spread 3, and its root's effects with the
    /// dropped shadow spread 6.
    private static let source = """
    {"version": "2.20", "children": [
      {"type": "frame", "id": "Chp", "name": "Chip", "reusable": true, "width": 80, "height": 40, "layout": "none",
       "effect": \(shadow),
       "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [{"effect": 0, "spread": 4, "shadow": \(shadow)}]}},
       "children": [
        {"type": "rectangle", "id": "Box", "name": "Box", "width": 20, "height": 20, "effect": \(shadow),
         "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [{"effect": 0, "spread": 4, "shadow": \(shadow)}]}}}]},
      {"type": "ref", "id": "Ins", "name": "Inst", "ref": "Chp", "x": 200, "effect": \(dropped),
       "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [{"effect": 0, "spread": 6, "shadow": \(dropped)}]}},
       "descendants": {"Box": {"effect": \(dropped),
         "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [{"effect": 0, "spread": 3, "shadow": \(dropped)}]}}}}}
    ]}
    """

    private func spreads(_ value: AnyCodable?) -> [AnyCodable?] {
        let effects: [AnyCodable] = switch value {
        case let .array(items)?: items
        case let .dictionary(object)?: [.dictionary(object)]
        default: []
        }
        return effects.map { if case let .dictionary(object) = $0 { object["spread"] } else { nil } }
    }

    @Test("A descendant's override of kind.effects is listed with the spread its own metadata stores")
    func descendantOverride() throws {
        let document = try EditableDocument(from: PenParser.parse(Self.source))
        let inspection = try #require(document.inspect(.instanceDescendant(refID: "Ins", descendantKey: "Box")))
        let effects = inspection.overrides.first { $0.path == NodePropertyCodec.effectsPath }
        #expect(spreads(effects?.value) == [3])
    }

    @Test("An instance root's override of kind.effects is listed with the spread the ref node stores")
    func rootOverride() throws {
        let document = try EditableDocument(from: PenParser.parse(Self.source))
        let inspection = try #require(document.inspect(.node(id: "Ins")))
        let effects = inspection.overrides.first { $0.path == NodePropertyCodec.effectsPath }
        #expect(spreads(effects?.value) == [6])
    }
}
