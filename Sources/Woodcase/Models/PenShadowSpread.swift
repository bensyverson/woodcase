//
//  PenShadowSpread.swift
//  Woodcase
//

import Foundation

/// How far one of a node's shadows is grown before it is cast — or, negative, shrunk — as
/// a CSS `box-shadow` spread grows its shadow.
///
/// Format 2.19 dropped a shadow's `spread`, and Pen refuses a shadow that carries one, so a
/// node's spreads live in its `metadata.woodcase.shadowSpread`, one entry per spread shadow:
///
/// ```json
/// "metadata": { "type": "woodcase", "woodcase": { "shadowSpread": [
///   { "effect": 0, "spread": 4,
///     "shadow": { "type": "shadow", "shadowType": "outer", "offset": { "x": 0, "y": 4 }, "blur": 8 } }
/// ] } }
/// ```
///
/// A node's effects are one object or an array, so ``effect`` addresses the shadow by its
/// place among them (0 for a lone object). ``shadow`` is the shadow the spread was made
/// for: Pen keeps metadata but cannot see it, so when Pen changes, moves or removes that
/// effect the entry no longer matches what sits at its place, is stale (``isStale(for:)``),
/// and the shadow casts without spread — rather than spreading the wrong shadow. The match
/// ignores what Pen rewrites in a shadow it has not changed (``matches(_:)``).
public struct PenShadowSpread: Friendly {
    /// The shadow's place among the node's effects, counting from 0.
    public var effect: Int

    /// How far the shadow's shape is grown before it is cast, in points; negative shrinks it.
    public var spread: Double

    /// The shadow the spread was made for.
    public var shadow: PenEffect.PenShadowEffect

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - effect: The shadow's place among the node's effects.
    ///   - spread: How far the shadow is grown, in points.
    ///   - shadow: The shadow the spread is made for.
    public init(effect: Int, spread: Double, shadow: PenEffect.PenShadowEffect) {
        self.effect = effect
        self.spread = spread
        self.shadow = shadow
    }

    // MARK: - Stale

    /// Whether the entry no longer applies to `effects`: the effect at its place is gone, is
    /// not a shadow, or is not the shadow it was made for.
    ///
    /// - Parameter effects: The node's effects as they are now.
    /// - Returns: `true` when the shadow casts without this spread.
    public func isStale(for effects: PenEffects?) -> Bool {
        let all = effects?.all ?? []
        guard effect < all.count, case let .shadow(current) = all[effect] else { return true }
        return !matches(current)
    }

    /// Whether `other` is the shadow this entry was made for.
    ///
    /// Compared as Pen draws them, not as they are spelled: an absent `enabled`, type,
    /// offset, blur and blend mode are true, outer, zero, zero and normal, an absent color
    /// is `#000000` — what Pen draws, and writes into a shadow that had none when it saves
    /// (pen CLI 0.3.11, 2026-10-15) — and a hex color's case does not matter. Keys the model
    /// does not claim are ignored.
    ///
    /// - Parameter other: A shadow the node has now.
    /// - Returns: `true` when the two draw the same.
    public func matches(_ other: PenEffect.PenShadowEffect) -> Bool {
        Fingerprint(shadow) == Fingerprint(other)
    }

    /// A shadow as Pen draws it, its defaults filled in.
    private struct Fingerprint: Equatable {
        let enabled: PenValue<Bool>
        let shadowType: PenEffect.PenShadowEffect.ShadowType
        let x: PenValue<Double>
        let y: PenValue<Double>
        let blur: PenValue<Double>
        let color: PenValue<String>
        let blendMode: PenBlendMode

        init(_ shadow: PenEffect.PenShadowEffect) {
            enabled = shadow.enabled ?? .literal(true)
            shadowType = shadow.shadowType ?? .outer
            x = shadow.offset?.x ?? .literal(0)
            y = shadow.offset?.y ?? .literal(0)
            blur = shadow.blur ?? .literal(0)
            color = switch shadow.color {
            case let .literal(hex)?: .literal(hex.uppercased())
            case let other?: other
            case nil: .literal(PenShadowSpread.absentColor)
            }
            blendMode = shadow.blendMode ?? .normal
        }
    }

    /// The color Pen draws a shadow that names none in, and writes into it on save.
    static let absentColor = "#000000"

    // MARK: - Wire form

    /// Why a metadata value is not shadow spreads Woodcase can draw.
    public struct WireError: Error, Friendly, CustomStringConvertible {
        /// What is wrong, as one clause: `entry 2 has no shadow`.
        public var reason: String

        /// Creates an error.
        ///
        /// - Parameter reason: What is wrong.
        public init(reason: String) {
            self.reason = reason
        }

        /// The reason.
        public var description: String {
            reason
        }
    }

    /// The shape the entries are written in, for a message.
    public static let wireForm = "[{effect, spread, shadow}]"

    /// The keys an entry holds.
    private enum WireKey: String, CaseIterable {
        case effect, spread, shadow
    }

    /// Reads a node's entries from `metadata.woodcase.shadowSpread`.
    ///
    /// The value is an array of objects holding exactly `effect`, a whole number from 0;
    /// `spread`, a finite number; and `shadow`, a shadow effect object. No two entries
    /// address the same effect.
    ///
    /// - Parameter value: The stored value.
    /// - Returns: The entries, in order.
    /// - Throws: ``WireError`` naming the first thing that is not the stored form.
    public static func entries(in value: AnyCodable) throws(WireError) -> [PenShadowSpread] {
        guard case let .array(items) = value else {
            throw WireError(reason: "shadow spreads are an array, \(wireForm)")
        }
        var entries: [PenShadowSpread] = []
        for (index, item) in items.enumerated() {
            let entry = try entry(item, number: index + 1)
            if entries.contains(where: { $0.effect == entry.effect }) {
                throw WireError(reason: "entry \(index + 1) addresses effect \(entry.effect) again")
            }
            entries.append(entry)
        }
        return entries
    }

    /// The entries in their stored form.
    ///
    /// - Parameter entries: The entries.
    /// - Returns: The value of `metadata.woodcase.shadowSpread`.
    public static func metadataValue(of entries: [PenShadowSpread]) -> AnyCodable {
        .array(entries.map(\.metadataValue))
    }

    /// The entry in its stored form.
    public var metadataValue: AnyCodable {
        let shadowValue = (try? NodePropertyCodec.encode(PenEffect.shadow(shadow))) ?? .null
        return .dictionary([
            WireKey.effect.rawValue: .int(effect),
            WireKey.spread.rawValue: PenMigrationMetadata.number(spread),
            WireKey.shadow.rawValue: shadowValue,
        ])
    }

    /// One stored entry.
    private static func entry(_ value: AnyCodable, number: Int) throws(WireError) -> PenShadowSpread {
        func refuse(_ reason: String) -> WireError {
            WireError(reason: "entry \(number) \(reason)")
        }
        guard case let .dictionary(object) = value else { throw refuse("is not an object {effect, spread, shadow}") }
        if let extra = object.keys.sorted().first(where: { WireKey(rawValue: $0) == nil }) {
            throw refuse("has an unknown key \"\(extra)\"; an entry holds only effect, spread and shadow")
        }
        let effect: Int? = switch object[WireKey.effect.rawValue] {
        case let .int(whole)?: whole
        case let .double(number)? where number.rounded() == number && abs(number) < 1e15: Int(number)
        default: nil
        }
        guard let effect, effect >= 0 else { throw refuse("needs effect: the shadow's place, a whole number from 0") }
        let spread: Double? = switch object[WireKey.spread.rawValue] {
        case let .int(whole)?: Double(whole)
        case let .double(number)? where number.isFinite: number
        default: nil
        }
        guard let spread else { throw refuse("needs spread: a number of points") }
        guard let shadowValue = object[WireKey.shadow.rawValue],
              case let .shadow(shadow)? = try? AnyCodableDecoder.decode(PenEffect.self, from: shadowValue)
        else { throw refuse("needs shadow: the shadow effect it was made for, {\"type\": \"shadow\", …}") }
        return PenShadowSpread(effect: effect, spread: spread, shadow: shadow)
    }
}
