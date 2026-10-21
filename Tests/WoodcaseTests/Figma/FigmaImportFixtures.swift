//
//  FigmaImportFixtures.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Imports the committed Figma fixtures and reads both sides of a mapping: the Figma node
/// as decoded, and the Pen node the importer made of it.
enum FigmaImportFixtures {
    /// A committed case, imported with `options`.
    static func imported(_ caseID: String, options: FigmaImportOptions = FigmaImportOptions()) throws -> FigmaImport {
        try FigmaImporter(options: options).clip(from: FigmaBlobTableTests.message(caseID))
    }

    /// The Pen node named `name` anywhere in `document`.
    static func node(_ name: String, in document: PenDocument) throws -> PenNode {
        var work = document.children
        while let node = work.popLast() {
            if node.common.name == name { return node }
            work += children(of: node)
        }
        Issue.record("no Pen node named \(name)")
        throw FixtureMissing(name: name)
    }

    /// Every node of `document`, roots first.
    static func allNodes(_ document: PenDocument) -> [PenNode] {
        var result: [PenNode] = []
        var work = document.children
        while !work.isEmpty {
            let node = work.removeFirst()
            result.append(node)
            work += children(of: node)
        }
        return result
    }

    /// A node's children, whatever its kind.
    static func children(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }

    /// The losses the import reported for the node named `name`.
    static func losses(_ name: String, in result: FigmaImport) -> [FigmaImportLoss] {
        result.losses.filter { $0.figmaName == name }
    }

    /// The map from a Figma node's own coordinates to the canvas: its transform after every
    /// ancestor's, up to the canvas.
    static func figmaCanvasTransform(_ name: String, in caseID: String) throws -> PenLayoutEngine.PlaneTransform {
        let nodes = try FigmaBlobTableTests.nodes(caseID)
        var byGUID: [String: KiwiValue] = [:]
        for node in nodes {
            byGUID[guidKey(node["guid"])] = node
        }
        var current: KiwiValue? = try FigmaBlobTableTests.node(name, in: caseID)
        var map = PenLayoutEngine.PlaneTransform.identity
        while let node = current, node["type"]?.enumName != "CANVAS" {
            map = transform(of: node).concatenating(map)
            current = node["parentIndex"].flatMap { byGUID[guidKey($0["guid"])] }
        }
        return map
    }

    /// A Figma node's `transform` as a plane map.
    static func transform(of node: KiwiValue) -> PenLayoutEngine.PlaneTransform {
        func value(_ key: String) -> Double {
            Double(node["transform"]?[key]?.floatValue ?? 0)
        }
        return PenLayoutEngine.PlaneTransform(
            a: value("m00"), b: value("m10"), c: value("m01"), d: value("m11"), tx: value("m02"), ty: value("m12")
        )
    }

    /// A Figma node's `size`.
    static func size(of node: KiwiValue) -> (width: Double, height: Double) {
        (Double(node["size"]?["x"]?.floatValue ?? 0), Double(node["size"]?["y"]?.floatValue ?? 0))
    }

    /// The largest distance between where two maps send the corners of a `width` × `height`
    /// box at the origin.
    static func cornerDistance(
        _ lhs: PenLayoutEngine.PlaneTransform, _ rhs: PenLayoutEngine.PlaneTransform, width: Double, height: Double
    ) -> Double {
        var worst = 0.0
        for corner in [PenPoint(x: 0, y: 0), PenPoint(x: width, y: 0), PenPoint(x: 0, y: height), PenPoint(x: width, y: height)] {
            let left = lhs.apply(to: corner)
            let right = rhs.apply(to: corner)
            worst = max(worst, abs(left.x - right.x), abs(left.y - right.y))
        }
        return worst
    }

    private static func guidKey(_ guid: KiwiValue?) -> String {
        "\(guid?["sessionID"]?.uintValue ?? 0):\(guid?["localID"]?.uintValue ?? 0)"
    }

    /// A message of `nodes` under a document and one page, each node a child of the page
    /// unless it names its own parent: what a hand-built mapping test feeds the importer.
    static func message(_ nodes: [KiwiRecord], blobs: [Data] = []) -> KiwiRecord {
        let document = record("NodeChange", [
            "guid": guid(0, 0), "type": .enumeration("DOCUMENT"), "name": .string("Document"),
        ])
        let page = record("NodeChange", [
            "guid": guid(0, 1), "type": .enumeration("CANVAS"), "name": .string("Page 1"),
            "parentIndex": parentIndex(guid(0, 0), "!"),
        ])
        var fields: [String: KiwiValue] = [
            "type": .enumeration("NODE_CHANGES"),
            "nodeChanges": .array([.message(document), .message(page)] + nodes.map { .message($0) }),
        ]
        if !blobs.isEmpty {
            fields["blobs"] = .array(blobs.map { .message(record("Blob", ["bytes": .bytes($0)])) })
        }
        return record("Message", fields)
    }

    /// A node change of `type` named `name` at `(x, y)` in the page, `width` × `height`.
    static func nodeChange(
        _ type: String, name: String, id: UInt32, x: Float = 0, y: Float = 0, width: Float = 10, height: Float = 10,
        parent: KiwiValue = guid(0, 1), position: String = "!", extra: [String: KiwiValue] = [:]
    ) -> KiwiRecord {
        var fields: [String: KiwiValue] = [
            "guid": guid(1, id), "type": .enumeration(type), "name": .string(name),
            "parentIndex": parentIndex(parent, position), "visible": .bool(true), "opacity": .float(1),
            "size": .structure(record("Vector", ["x": .float(width), "y": .float(height)])),
            "transform": .structure(record("Matrix", [
                "m00": .float(1), "m01": .float(0), "m02": .float(x),
                "m10": .float(0), "m11": .float(1), "m12": .float(y),
            ])),
        ]
        fields.merge(extra) { $1 }
        return record("NodeChange", fields)
    }

    /// A GUID value.
    static func guid(_ session: UInt32, _ local: UInt32) -> KiwiValue {
        .structure(record("GUID", ["sessionID": .uint(session), "localID": .uint(local)]))
    }

    /// A solid paint of `r`, `g`, `b`, `a`.
    static func solid(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1, opacity: Float = 1) -> KiwiValue {
        .message(record("Paint", [
            "type": .enumeration("SOLID"), "visible": .bool(true), "opacity": .float(opacity),
            "blendMode": .enumeration("NORMAL"),
            "color": .structure(record("Color", ["r": .float(r), "g": .float(g), "b": .float(b), "a": .float(a)])),
        ]))
    }

    private static func parentIndex(_ parent: KiwiValue, _ position: String) -> KiwiValue {
        .structure(record("ParentIndex", ["guid": parent, "position": .string(position)]))
    }

    private static func record(_ name: String, _ fields: [String: KiwiValue]) -> KiwiRecord {
        KiwiRecord(typeName: name, fields: fields)
    }

    /// Thrown when a fixture lacks a node a test names.
    struct FixtureMissing: Error {
        /// The name looked for.
        var name: String
    }
}
