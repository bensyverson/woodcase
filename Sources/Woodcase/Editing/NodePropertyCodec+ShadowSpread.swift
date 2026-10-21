//
//  NodePropertyCodec+ShadowSpread.swift
//  Woodcase
//

import Foundation

/// A shadow's spread, read and written as a `spread` field on the shadow in `kind.effects`.
///
/// Format 2.19 dropped a shadow's `spread`, and Pen refuses a shadow that carries one, so
/// Woodcase stores each spread in `metadata.woodcase.shadowSpread`, one ``PenShadowSpread``
/// entry per spread shadow, by its place among the effects (<doc:PenMetadataNamespace>).
/// Paths don't address array elements, so the natural spelling is the one CSS, Figma and
/// Sketch use: a field of the shadow (leaf oNeklc;
/// `project/2026-10-20-natural-paths-for-woodcase-properties.md`).
///
/// - **Reading.** ``presentedValue(at:of:)`` reads `kind.effects` with each shadow's spread
///   put back on it — the spread it is drawn with, so a stale entry is not shown. `get`,
///   `tree --props` and the `doc` API read it this way. ``value(at:of:)`` stays the stored
///   value, which undo, merges and replication compare and write back as they are.
/// - **Writing.** A planned write of `kind.effects` restates every spread
///   (``restatingShadowSpreads(_:on:)``): the shadows that carry one are stored, by their
///   new places, and every other entry is dropped — a reordered list keeps each spread on
///   its own shadow, and a spread whose shadow is gone goes with it. Below the planner, a
///   write whose shadows carry a `spread` is folded the same way
///   (``storingNaturalPaths(_:on:)``, ``setting(_:at:on:)``); one that carries none is the
///   plain effects write it always was, so an undo or a peer's write never touches the
///   spreads it did not name.
/// - **Overriding.** An instance override names only what it changes, so an override of
///   `kind.effects` whose shadows carry no `spread` leaves the spreads to the component —
///   an entry still applies where its shadow still matches. One that names a spread stores
///   the override's spreads in its own `metadata.woodcase` (rule 6); a spread of `0` stores
///   an empty list, which clears the component's spreads on that instance alone.
public extension NodePropertyCodec {
    /// The path of a node's effects, whose shadows carry their spreads.
    static let effectsPath = "kind.effects"

    /// The field a shadow's spread is written in.
    static let spreadField = "spread"

    /// The value at a path as a caller reads it: ``value(at:of:)``, with each shadow in
    /// `kind.effects` carrying the spread it is drawn with
    /// (``PenNode/shadowSpread(forEffect:)``).
    ///
    /// - Parameters:
    ///   - path: A path from ``paths(for:)``.
    ///   - node: The node to read.
    /// - Returns: The value; for any path but `kind.effects`, exactly ``value(at:of:)``.
    /// - Throws: What ``value(at:of:)`` throws.
    static func presentedValue(at path: String, of node: PenNode) throws -> AnyCodable {
        let stored = try value(at: path, of: node)
        guard path == effectsPath else { return stored }
        return withSpreads(stored, of: node)
    }

    /// Whether the node draws any of its shadows with a spread.
    ///
    /// - Parameter node: The node.
    /// - Returns: `true` when ``presentedValue(at:of:)`` puts a spread on a shadow.
    static func showsShadowSpread(_ node: PenNode) -> Bool {
        let count = PenRenderer.effects(for: node)?.all.count ?? 0
        return (0 ..< count).contains { node.shadowSpread(forEffect: $0) != nil }
    }

    /// A planned write with `kind.effects` restating every spread.
    ///
    /// A write of `kind.effects` is a whole value, so the shadows that carry a `spread`
    /// are the node's spreads after it: their entries, by their places in the new list,
    /// become a write of `common.metadata.woodcase.shadowSpread`, and a list with none
    /// removes the key (a node that holds none is left without metadata it did not have). An explicit write of that key by a caller is refused before this
    /// (``checkNoStoragePaths(_:nodeID:)``).
    ///
    /// - Parameters:
    ///   - properties: The writes, by property path.
    ///   - node: The node written to.
    /// - Returns: The writes, the spreads out of `kind.effects` and into their storage.
    /// - Throws: ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)`` for a
    ///   spread that is not a number, or a shadow that does not decode.
    static func restatingShadowSpreads(
        _ properties: [String: AnyCodable],
        on node: PenNode
    ) throws -> [String: AnyCodable] {
        guard let effects = properties[effectsPath], takesEffects(node.kind) else { return properties }
        let split = try splittingSpreads(of: effects, nodeID: node.id)
        var written = properties
        written[effectsPath] = split.effects
        let spreads = split.spreads ?? []
        if !spreads.isEmpty {
            written[PenMetadata.WoodcaseKey.shadowSpread.path] = PenShadowSpread.metadataValue(of: spreads)
        } else if node.common.metadata?[woodcase: .shadowSpread] != nil {
            written[PenMetadata.WoodcaseKey.shadowSpread.path] = .null
        }
        return written
    }

    // MARK: - Internal

    /// The writes with the spreads `kind.effects` names moved into their storage, as
    /// ``restatingShadowSpreads(_:on:)`` moves them; unchanged when no shadow names one.
    ///
    /// Below the planner a write of `kind.effects` that names no spread is the stored
    /// effects alone — an undo, a merge or a peer's write — and leaves the spreads as they are.
    internal static func storingNamedSpreads(
        _ properties: [String: AnyCodable],
        on node: PenNode
    ) throws -> [String: AnyCodable] {
        guard writesNamedSpread(properties, on: node.kind) else { return properties }
        return try restatingShadowSpreads(properties, on: node)
    }

    /// Returns `node` with a `kind.effects` that names spreads written: the effects without
    /// them, and the spreads folded onto the node's metadata.
    ///
    /// - Parameters:
    ///   - effects: The effects value, its shadows naming spreads.
    ///   - node: The node to patch.
    /// - Returns: The patched node.
    /// - Throws: ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    internal static func settingNamedSpreads(_ effects: AnyCodable, on node: PenNode) throws -> PenNode {
        let folded = try folding([effectsPath: effects], onto: node)
        var patched = node
        patched.kind = try setting(folded[effectsPath] ?? .null, at: effectsPath, on: node.kind, nodeID: node.id)
        if let metadata = folded[metadataPath] {
            patched = try setting(metadata, at: metadataPath, on: patched)
        }
        return patched
    }

    /// An override's writes with the spreads its effects name taken out, and the
    /// `shadowSpread` value they make.
    ///
    /// An override names only what it changes, so effects that name no spread leave the
    /// spreads to the component, and the value is `nil`. Effects that name one make the
    /// override's own list — empty when every spread named is `0` — which expansion lays
    /// over the component node's key (rule 6).
    ///
    /// - Parameters:
    ///   - properties: The override's writes, by raw key (`effect`) or path (`kind.effects`).
    ///   - nodeID: The instance, for the error.
    /// - Returns: The writes with no `spread` left on a shadow, and the override's spreads.
    /// - Throws: ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    internal static func splittingOverrideSpreads(
        _ properties: [String: AnyCodable],
        nodeID: String
    ) throws -> (properties: [String: AnyCodable], shadowSpread: AnyCodable?) {
        var written = properties
        var shadowSpread: AnyCodable?
        for name in [rawKey(for: effectsPath), effectsPath] {
            guard let effects = properties[name], namesSpread(effects) else { continue }
            let split = try splittingSpreads(of: effects, nodeID: nodeID)
            written[name] = split.effects
            shadowSpread = PenShadowSpread.metadataValue(of: split.spreads ?? [])
        }
        return (written, shadowSpread)
    }

    /// Whether a write names a spread on a shadow in `kind.effects` of a node that takes effects.
    internal static func writesNamedSpread(_ properties: [String: AnyCodable], on kind: PenNode.Kind) -> Bool {
        guard let effects = properties[effectsPath] else { return false }
        return namesSpread(effects) && takesEffects(kind)
    }

    /// Whether a node of this kind takes effects.
    internal static func takesEffects(_ kind: PenNode.Kind) -> Bool {
        kind.nodeType != nil && PropertyDiff.allKindKeys(kind).contains(effectsPath)
    }

    /// Whether an effects value names a spread on any of its shadows.
    internal static func namesSpread(_ effects: AnyCodable) -> Bool {
        effectObjects(of: effects).contains { isShadow($0) && $0[spreadField] != nil }
    }

    /// An effects value with each shadow's `spread` taken out, and the spreads it named.
    ///
    /// - Parameters:
    ///   - effects: The `kind.effects` value: one effect object, or an array.
    ///   - nodeID: The node written to, for the error.
    /// - Returns: The effects with no `spread` left on a shadow, and the entries of the
    ///   shadows that named a spread other than `0` or `null`, by place — or `nil` for the
    ///   entries when no shadow names a spread at all.
    /// - Throws: ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    internal static func splittingSpreads(
        of effects: AnyCodable,
        nodeID: String
    ) throws -> (effects: AnyCodable, spreads: [PenShadowSpread]?) {
        guard namesSpread(effects) else { return (effects, nil) }
        var spreads: [PenShadowSpread] = []
        func split(_ effect: AnyCodable, at index: Int) throws -> AnyCodable {
            guard case var .dictionary(object) = effect, isShadow(object),
                  let spread = object.removeValue(forKey: spreadField)
            else { return effect }
            let points: Double? = switch spread {
            case .null: 0
            case let .int(whole): Double(whole)
            case let .double(number) where number.isFinite: number
            default: nil
            }
            guard let points else {
                throw EditingError.propertyTypeMismatch(
                    nodeID: nodeID, key: effectsPath,
                    expected: "a number of points for the spread of the shadow at effect \(index)",
                    actual: "spread \(PenPostIt.json(spread))"
                )
            }
            let stripped = AnyCodable.dictionary(object)
            guard points != 0 else { return stripped }
            guard case let .shadow(shadow)? = try? AnyCodableDecoder.decode(PenEffect.self, from: stripped) else {
                throw mismatch(effectsPath, "effects", effects, nodeID)
            }
            spreads.append(PenShadowSpread(effect: index, spread: points, shadow: shadow))
            return stripped
        }
        let stripped: AnyCodable = switch effects {
        case .dictionary: try split(effects, at: 0)
        case let .array(items): try .array(items.enumerated().map { try split($1, at: $0) })
        default: effects
        }
        return (stripped, spreads)
    }

    // MARK: - Private

    /// The stored effects with each shadow carrying the spread it is drawn with.
    private static func withSpreads(_ effects: AnyCodable, of node: PenNode) -> AnyCodable {
        func spread(_ effect: AnyCodable, at index: Int) -> AnyCodable {
            guard case var .dictionary(object) = effect, isShadow(object),
                  let points = node.shadowSpread(forEffect: index)
            else { return effect }
            object[spreadField] = PenMigrationMetadata.number(points)
            return .dictionary(object)
        }
        return switch effects {
        case .dictionary: spread(effects, at: 0)
        case let .array(items): .array(items.enumerated().map { spread($1, at: $0) })
        default: effects
        }
    }

    /// The effect objects a value holds, in order.
    private static func effectObjects(of effects: AnyCodable) -> [[String: AnyCodable]] {
        switch effects {
        case let .dictionary(object): [object]
        case let .array(items): items.compactMap { if case let .dictionary(object) = $0 { object } else { nil } }
        default: []
        }
    }

    /// Whether an effect object is a shadow.
    private static func isShadow(_ object: [String: AnyCodable]) -> Bool {
        object["type"] == .string(PenEffect.EffectType.shadow.rawValue)
    }
}
