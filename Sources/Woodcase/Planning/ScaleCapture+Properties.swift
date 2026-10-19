//
//  ScaleCapture+Properties.swift
//  Woodcase
//

import Foundation

/// What one captured node holds that a scale multiplies, read once at capture, and what it
/// writes for each step.
extension ScaleCapture.Entry {
    /// Every value of `node` a scale multiplies, read as the file holds it.
    ///
    /// Read once, at capture, so a step is arithmetic on these values and never touches the
    /// node or the codec again. A value the node leaves unset is read as what it is drawn at
    /// when that is a number — a text's 16 pt, a stroke's 1 pt, a note's 200 × 200 — and
    /// skipped when it is not (`fit_content`, a size the font decides).
    ///
    /// - Parameters:
    ///   - node: The node as drawn.
    ///   - position: How the node moves.
    /// - Returns: The values, in a fixed order.
    static func values(of node: PenNode, position: Position) -> [Value] {
        var reader = Reader(node: node)
        switch position {
        case .kept:
            break
        case .scaled:
            reader.read("common.x", .length)
            reader.read("common.y", .length)
        case .anchored:
            reader.read("common.x", .coordinate(.x), default: .int(0))
            reader.read("common.y", .coordinate(.y), default: .int(0))
        }
        reader.read("kind.width", .sizing, default: reader.unsetNumber("kind.width"))
        reader.read("kind.height", .sizing, default: reader.unsetNumber("kind.height"))
        if let style = node.noteTextStyle {
            // A note's text style lives in its metadata, which Pen keeps and which wins over
            // its own properties; the size it is drawn at is what scales.
            reader.read(PenMetadata.WoodcaseKey.fontSize.path, .length, drawn: ProportionalScaler.number(style.fontSize))
            if let spacing = style.letterSpacing, spacing != 0 {
                reader.read(
                    PenMetadata.WoodcaseKey.letterSpacing.path, .length, drawn: ProportionalScaler.number(spacing)
                )
            }
        } else {
            reader.read("kind.fontSize", .length, default: reader.unsetNumber("kind.fontSize"))
            reader.read("kind.letterSpacing", .length)
            reader.read(PenMetadata.WoodcaseKey.spans.path, .spans)
        }
        let stroked = (try? NodePropertyCodec.value(at: "kind.stroke", of: node)).map { $0 != .null } ?? false
        reader.read("kind.strokeWidth", .sides, default: stroked ? reader.unsetNumber("kind.strokeWidth") : nil)
        reader.read(PenMetadata.WoodcaseKey.strokeDash.path, .lengths)
        reader.read(PenMetadata.WoodcaseKey.strokeDashOffset.path, .length)
        reader.read("kind.cornerRadius", .lengths)
        reader.read("kind.gap", .length)
        reader.read("kind.padding", .lengths)
        reader.read("kind.effects", .effects)
        reader.read(PenMetadata.WoodcaseKey.shadowSpread.path, .shadowSpreads)
        return reader.values
    }

    /// The node's scaled properties for one step, by property path, holding only what
    /// changes.
    ///
    /// - Parameters:
    ///   - scaler: The step's scaler.
    ///   - anchor: The point that stays still, on the canvas.
    ///   - unscaled: Collects each bound value met.
    /// - Returns: Property path → the value to write.
    func scaledProperties(
        by scaler: inout ProportionalScaler,
        around anchor: PenPoint,
        unscaled: inout [ScalePlan.BoundValue]
    ) -> [String: AnyCodable] {
        let pivot: PenPoint = if case let .anchored(canvasToParent) = position {
            canvasToParent.apply(to: anchor)
        } else {
            anchor
        }
        var properties: [String: AnyCodable] = [:]
        for value in values {
            let scaled = value.rule.apply(to: value.drawn, by: &scaler, about: pivot)
            for variable in scaler.takeBound() {
                unscaled.append(ScalePlan.BoundValue(nodeID: expandedID, property: value.path, variable: variable))
            }
            if scaled != value.held, scaled != value.drawn { properties[value.path] = scaled }
        }
        return properties
    }
}

extension ScaleCapture.Entry {
    /// Reads a node's scalable values in order.
    struct Reader {
        /// The node.
        let node: PenNode

        /// The values read so far.
        var values: [Value] = []

        /// Reads the value at `path`, or `default` when it is unset; a path the node's type
        /// lacks, or one unset with no default, is skipped.
        mutating func read(_ path: String, _ rule: Value.Rule, default fallback: AnyCodable? = nil) {
            guard let held = try? NodePropertyCodec.value(at: path, of: node) else { return }
            let drawn = held == .null ? fallback ?? .null : held
            guard drawn != .null else { return }
            values.append(Value(path: path, held: held, drawn: drawn, rule: rule))
        }

        /// Reads the value at `path` as `drawn` — what the node is drawn with, which it may
        /// not hold there.
        mutating func read(_ path: String, _ rule: Value.Rule, drawn: AnyCodable) {
            let held = (try? NodePropertyCodec.value(at: path, of: node)) ?? .null
            values.append(Value(path: path, held: held, drawn: drawn, rule: rule))
        }

        /// The number a property is drawn at when the node leaves it unset, or `nil` when
        /// that is not a number.
        func unsetNumber(_ path: String) -> AnyCodable? {
            guard let type = node.kind.nodeType,
                  case let .number(value)? = PenSchema.unsetDefault(of: path, on: type)
            else { return nil }
            return ProportionalScaler.number(value)
        }
    }
}
