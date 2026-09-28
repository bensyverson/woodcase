//
//  EditOperationCodableTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct EditOperationCodableTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func roundTrip(_ operation: EditOperation) throws -> EditOperation {
        let data = try encoder.encode(operation)
        return try decoder.decode(EditOperation.self, from: data)
    }

    // MARK: - Structural operations

    @Test("Round-trip insertNode with rectangle")
    func insertNodeRoundTrip() throws {
        let node = PenNode(
            id: "n1",
            common: PenNodeCommon(name: "Rect"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let op = EditOperation.insertNode(EditOperation.InsertNode(node: node, parentID: "p1", index: 2))

        let decoded = try roundTrip(op)

        if case let .insertNode(params) = decoded {
            #expect(params.node.id == "n1")
            #expect(params.parentID == "p1")
            #expect(params.index == 2)
        } else {
            Issue.record("Expected insertNode")
        }
    }

    @Test("Round-trip deleteNode")
    func deleteNodeRoundTrip() throws {
        let op = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "n1"))
        let decoded = try roundTrip(op)

        if case let .deleteNode(params) = decoded {
            #expect(params.nodeID == "n1")
        } else {
            Issue.record("Expected deleteNode")
        }
    }

    @Test("Round-trip moveNode")
    func moveNodeRoundTrip() throws {
        let op = EditOperation.moveNode(EditOperation.MoveNode(nodeID: "n1", newParentID: "p2", index: 0))
        let decoded = try roundTrip(op)

        if case let .moveNode(params) = decoded {
            #expect(params.nodeID == "n1")
            #expect(params.newParentID == "p2")
            #expect(params.index == 0)
        } else {
            Issue.record("Expected moveNode")
        }
    }

    // MARK: - UpdateCommon

    @Test("Round-trip updateCommon")
    func updateCommonRoundTrip() throws {
        let common = PenNodeCommon(name: "Test", opacity: .literal(0.5), reusable: true)
        let op = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "n1", common: common))
        let decoded = try roundTrip(op)

        if case let .updateCommon(params) = decoded {
            #expect(params.nodeID == "n1")
            #expect(params.common.name == "Test")
            #expect(params.common.opacity == .literal(0.5))
            #expect(params.common.reusable == true)
        } else {
            Issue.record("Expected updateCommon")
        }
    }

    // MARK: - UpdateKind (the problematic case)

    @Test("Round-trip updateKind with frame")
    func updateKindFrame() throws {
        let kind = PenNode.Kind.frame(PenNode.FrameData(
            width: .fixed(200),
            height: .fillContainer(fallback: 100),
            cornerRadius: .uniform(.literal(8))
        ))
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "n1", kind: kind))
        let decoded = try roundTrip(op)

        if case let .updateKind(params) = decoded {
            #expect(params.nodeID == "n1")
            if case let .frame(data) = params.kind {
                #expect(data.width == PenSizing.fixed(200))
                #expect(data.height == PenSizing.fillContainer(fallback: 100))
            } else {
                Issue.record("Expected frame kind")
            }
        } else {
            Issue.record("Expected updateKind")
        }
    }

    @Test("Round-trip updateKind with text")
    func updateKindText() throws {
        let kind = PenNode.Kind.text(PenNode.TextData(
            fontFamily: .literal("Arial"),
            fontSize: .literal(16)
        ))
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "n1", kind: kind))
        let decoded = try roundTrip(op)

        if case let .updateKind(params) = decoded {
            if case let .text(data) = params.kind {
                #expect(data.fontFamily == .literal("Arial"))
                #expect(data.fontSize == .literal(16))
            } else {
                Issue.record("Expected text kind")
            }
        } else {
            Issue.record("Expected updateKind")
        }
    }

    @Test("Round-trip updateKind with rectangle")
    func updateKindRectangle() throws {
        let kind = PenNode.Kind.rectangle(PenNode.RectangleData(
            width: .fixed(50),
            height: .fixed(50)
        ))
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "n1", kind: kind))
        let decoded = try roundTrip(op)

        if case let .updateKind(params) = decoded {
            if case let .rectangle(data) = params.kind {
                #expect(data.width == .fixed(50))
                #expect(data.height == .fixed(50))
            } else {
                Issue.record("Expected rectangle kind")
            }
        } else {
            Issue.record("Expected updateKind")
        }
    }

    @Test("Round-trip updateKind with unknown type")
    func updateKindUnknown() throws {
        let kind = PenNode.Kind.unknown(
            typeName: "widget",
            properties: ["foo": AnyCodable("bar")]
        )
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "n1", kind: kind))
        let decoded = try roundTrip(op)

        if case let .updateKind(params) = decoded {
            if case let .unknown(typeName, props) = params.kind {
                #expect(typeName == "widget")
                #expect(props["foo"] == AnyCodable("bar"))
            } else {
                Issue.record("Expected unknown kind")
            }
        } else {
            Issue.record("Expected updateKind")
        }
    }

    @Test("Round-trip updateKind with group")
    func updateKindGroup() throws {
        let kind = PenNode.Kind.group(PenNode.GroupData(
            blendMode: .multiply,
            children: [
                PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData())),
            ]
        ))
        let op = EditOperation.updateKind(EditOperation.UpdateKind(nodeID: "n1", kind: kind))
        let decoded = try roundTrip(op)

        if case let .updateKind(params) = decoded {
            if case let .group(data) = params.kind {
                #expect(data.blendMode == .multiply)
                #expect(data.children?.count == 1)
            } else {
                Issue.record("Expected group kind")
            }
        } else {
            Issue.record("Expected updateKind")
        }
    }

    // MARK: - Variables

    @Test("Round-trip addVariable")
    func addVariableRoundTrip() throws {
        let variable = PenVariable(type: .color, value: .simple(AnyCodable("#FF0000")))
        let op = EditOperation.addVariable(EditOperation.AddVariable(name: "primary", variable: variable))
        let decoded = try roundTrip(op)

        if case let .addVariable(params) = decoded {
            #expect(params.name == "primary")
            #expect(params.variable.type == .color)
        } else {
            Issue.record("Expected addVariable")
        }
    }

    @Test("Round-trip updateVariable")
    func updateVariableRoundTrip() throws {
        let variable = PenVariable(type: .number, value: .simple(AnyCodable(42)))
        let op = EditOperation.updateVariable(EditOperation.UpdateVariable(name: "count", variable: variable))
        let decoded = try roundTrip(op)

        if case let .updateVariable(params) = decoded {
            #expect(params.name == "count")
        } else {
            Issue.record("Expected updateVariable")
        }
    }

    @Test("Round-trip removeVariable")
    func removeVariableRoundTrip() throws {
        let op = EditOperation.removeVariable(EditOperation.RemoveVariable(name: "unused"))
        let decoded = try roundTrip(op)

        if case let .removeVariable(params) = decoded {
            #expect(params.name == "unused")
        } else {
            Issue.record("Expected removeVariable")
        }
    }

    // MARK: - Imports

    @Test("Round-trip addImport")
    func addImportRoundTrip() throws {
        let op = EditOperation.addImport(EditOperation.AddImport(alias: "icons", path: "./icons.pen"))
        let decoded = try roundTrip(op)

        if case let .addImport(params) = decoded {
            #expect(params.alias == "icons")
            #expect(params.path == "./icons.pen")
        } else {
            Issue.record("Expected addImport")
        }
    }

    @Test("Round-trip updateImport")
    func updateImportRoundTrip() throws {
        let op = EditOperation.updateImport(EditOperation.UpdateImport(alias: "icons", path: "./new-icons.pen"))
        let decoded = try roundTrip(op)

        if case let .updateImport(params) = decoded {
            #expect(params.alias == "icons")
            #expect(params.path == "./new-icons.pen")
        } else {
            Issue.record("Expected updateImport")
        }
    }

    @Test("Round-trip removeImport")
    func removeImportRoundTrip() throws {
        let op = EditOperation.removeImport(EditOperation.RemoveImport(alias: "icons"))
        let decoded = try roundTrip(op)

        if case let .removeImport(params) = decoded {
            #expect(params.alias == "icons")
        } else {
            Issue.record("Expected removeImport")
        }
    }

    // MARK: - Themes

    @Test("Round-trip addThemeAxis")
    func addThemeAxisRoundTrip() throws {
        let op = EditOperation.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"]))
        let decoded = try roundTrip(op)

        if case let .addThemeAxis(params) = decoded {
            #expect(params.name == "mode")
            #expect(params.options == ["light", "dark"])
        } else {
            Issue.record("Expected addThemeAxis")
        }
    }

    @Test("Round-trip updateThemeAxis")
    func updateThemeAxisRoundTrip() throws {
        let op = EditOperation.updateThemeAxis(EditOperation.UpdateThemeAxis(name: "mode", options: ["light", "dark", "auto"]))
        let decoded = try roundTrip(op)

        if case let .updateThemeAxis(params) = decoded {
            #expect(params.name == "mode")
            #expect(params.options == ["light", "dark", "auto"])
        } else {
            Issue.record("Expected updateThemeAxis")
        }
    }

    @Test("Round-trip removeThemeAxis")
    func removeThemeAxisRoundTrip() throws {
        let op = EditOperation.removeThemeAxis(EditOperation.RemoveThemeAxis(name: "mode"))
        let decoded = try roundTrip(op)

        if case let .removeThemeAxis(params) = decoded {
            #expect(params.name == "mode")
        } else {
            Issue.record("Expected removeThemeAxis")
        }
    }

    // MARK: - PenNode Codable unaffected

    @Test("PenNode Codable still works independently")
    func penNodeCodableUnaffected() throws {
        let node = PenNode(
            id: "test",
            common: PenNodeCommon(name: "Test"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100)))
        )
        let data = try encoder.encode(node)
        let decoded = try decoder.decode(PenNode.self, from: data)

        #expect(decoded.id == "test")
        #expect(decoded.common.name == "Test")
        if case let .rectangle(rectData) = decoded.kind {
            #expect(rectData.width == .fixed(100))
        } else {
            Issue.record("Expected rectangle kind")
        }
    }
}
