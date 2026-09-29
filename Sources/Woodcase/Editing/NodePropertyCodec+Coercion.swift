//
//  NodePropertyCodec+Coercion.swift
//  Woodcase
//

import Foundation

/// The one place a written value is allowed to change type before it is stored.
///
/// A command line carries only strings, so `kind.content=3` arrives as the number `3`,
/// and a caption reading "3" is unmistakably what was meant — there is no other value a
/// text node's content could take from a number. Refusing it taught nothing and cost a
/// round trip, so the number is stored as the string it spells.
///
/// The rule is deliberately narrow. It applies to a **number** written to a property
/// whose shape is a string or a `$variable` — ``NodePropertyCodec/stringFields``, read
/// off ``NodePropertyCodec/shapes`` rather than listed here, so a property that gains
/// or loses that shape moves with the table. Nothing else converts: a string where a
/// number belongs, a boolean where text belongs and an object where content belongs are
/// all still ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``,
/// because each of those has more than one plausible reading and a plausible wrong
/// value is worse than a refusal.
///
/// A node of an unrecognized type is left alone: Woodcase has no schema for it, so it
/// has no grounds to say the number was meant as text.
///
/// The rule follows the value across the instance seam. `override … content=42` is the
/// same typing mistake as `set … kind.content=42`, and the .pen file it lands in is the
/// same one — so ``coercingOverrides(_:on:)`` applies it to an override map too, keyed
/// by the raw .pen name that map uses.
extension NodePropertyCodec {
    /// Every field whose value is a string or a `$variable` reference.
    ///
    /// Derived from ``shapes``, so it cannot drift from the shapes a refusal quotes.
    static let stringFields: Set<String> = Set(
        shapes.filter { $0.value == stringOrVariable }.keys
    )

    /// The value to store for a written one, after the number-to-string rule.
    ///
    /// - Parameters:
    ///   - value: The value as it was written.
    ///   - path: The property path it was written to.
    ///   - kind: The kind of the node being patched. An
    ///     ``PenNode/Kind/unknown(typeName:properties:)`` node is never coerced.
    /// - Returns: The string a number spells when the property takes text, and `value`
    ///   itself in every other case.
    static func coercing(_ value: AnyCodable, at path: String, on kind: PenNode.Kind) -> AnyCodable {
        coercing(value, field: fieldName(of: path), on: kind)
    }

    /// The value to store for one written into a component instance's override map.
    ///
    /// The rule is the one ``coercing(_:at:on:)`` applies; only the vocabulary differs.
    /// An override is keyed by the raw .pen name (`content`, `fill`), so the field the
    /// shape table is keyed by is read back with ``fieldName(forRawKey:)`` rather than
    /// off a dotted path.
    ///
    /// - Parameters:
    ///   - properties: The overrides, keyed as the `descendants` map keys them.
    ///   - kind: The kind of the node inside the component the override patches.
    /// - Returns: The same keys, each value after the number-to-string rule.
    static func coercingOverrides(
        _ properties: [String: AnyCodable],
        on kind: PenNode.Kind
    ) -> [String: AnyCodable] {
        properties.reduce(into: [:]) { result, entry in
            result[entry.key] = coercing(entry.value, field: fieldName(forRawKey: entry.key), on: kind)
        }
    }

    /// The number-to-string rule itself, for whichever vocabulary named the field.
    ///
    /// - Parameters:
    ///   - value: The value as it was written.
    ///   - field: The field it was written to, or `nil` when the caller's key names none.
    ///   - kind: The kind of the node being patched.
    /// - Returns: The string a number spells when the property takes text, and `value`
    ///   itself in every other case.
    private static func coercing(_ value: AnyCodable, field: String?, on kind: PenNode.Kind) -> AnyCodable {
        if case .unknown = kind { return value }
        guard let field, stringFields.contains(field) else { return value }
        guard let spelled = spelling(of: value) else { return value }
        return .string(spelled)
    }

    /// The field a property path names, or `nil` when the path has neither prefix.
    static func fieldName(of path: String) -> String? {
        if path.hasPrefix(commonPrefix) { return String(path.dropFirst(commonPrefix.count)) }
        if path.hasPrefix(kindPrefix) { return String(path.dropFirst(kindPrefix.count)) }
        return nil
    }

    // MARK: - Private

    /// How a number spells itself as text, or `nil` for a value that is not a number.
    ///
    /// An integral value loses its decimal point — `3`, never `3.0` — because that is
    /// what a caller who typed `3` wrote; a fractional one keeps every digit it needs
    /// to read back as the same number.
    private static func spelling(of value: AnyCodable) -> String? {
        switch value {
        case let .int(number):
            return String(number)
        case let .double(number):
            guard number.isFinite else { return nil }
            guard number.rounded() == number, abs(number) < 1e15 else { return String(number) }
            return String(Int64(number))
        default:
            return nil
        }
    }
}
