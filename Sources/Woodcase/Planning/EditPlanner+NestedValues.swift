//
//  EditPlanner+NestedValues.swift
//  Woodcase
//

import Foundation

/// The values inside a structured write — a fill's color, a gradient stop's position, a
/// blur's radius — read against the nested key tables (``PenNestedShape``) that
/// describe them, so each is held to its own key's ``PenNestedShape/Field/constraint``
/// and variable type, as a top-level property is held to its shape's.
extension EditPlanner {
    /// One scalar found inside an object or an array of a written value.
    struct NestedValue {
        /// The key the write names, which every location starts from.
        var property: String

        /// Where it sits under the written key, as steps down into the value.
        var path: [EditRefusal.NestedLocation.Component]

        /// Where it sits, spelled from the written key: `kind.fills[0].colors[1].position`.
        var location: String {
            nestedLocation.spelled(under: property)
        }

        /// Where it sits, as a refusal carries it.
        var nestedLocation: EditRefusal.NestedLocation {
            EditRefusal.NestedLocation(components: path)
        }

        /// The value.
        var value: AnyCodable

        /// The nested key that holds it, or `nil` where no key table describes the spot.
        var field: PenNestedShape.Field?
    }

    /// Every scalar inside a written value, each with the nested key that describes it.
    ///
    /// A bare scalar at the top is not nested and yields nothing: the property's own
    /// shape judges it. An object picks its key table from the forms it was written
    /// against — a fill's `"type"` picks the variant — and an array's elements are read
    /// against the forms an element may take.
    ///
    /// - Parameters:
    ///   - value: The value written.
    ///   - forms: The forms the property accepts.
    ///   - key: The key the write names, which every location starts from.
    /// - Returns: The nested scalars, in key order.
    static func nestedValues(in value: AnyCodable, forms: [PenValueForm], key: String) -> [NestedValue] {
        switch value {
        case .dictionary, .array: walk(value, forms: forms, field: nil, under: key, path: [])
        default: []
        }
    }

    /// The scalars inside a written value that differ from what the node holds at the
    /// same location — the only ones a write is judged by.
    ///
    /// An inspector writes a whole paint list to change one layer, so a value the file
    /// already held (an opacity of 1.5 from Pen, a hand edit) comes back unchanged
    /// beside the edit. Judging it would refuse an edit to fill 0 over a spot the user
    /// never touched; a nested value left as it was passes, as a whole property written
    /// back unchanged does.
    ///
    /// - Parameters:
    ///   - write: The property written, with what the node holds there now.
    ///   - forms: The forms the property accepts.
    /// - Returns: The nested scalars that are new or changed, in key order.
    static func changedNestedValues(_ write: ValueWrite, forms: [PenValueForm]) -> [NestedValue] {
        let written = nestedValues(in: write.value, forms: forms, key: write.key)
        guard let current = write.current else { return written }
        let held = Dictionary(
            nestedValues(in: current, forms: forms, key: write.key).map { ($0.path, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        return written.filter { held[$0.path] != $0.value }
    }

    /// Refuses the first nested number outside its key's constraint.
    ///
    /// - Parameters:
    ///   - write: The property written.
    ///   - nested: The scalars inside its value.
    ///   - address: The address as written.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/outOfRange`` or
    ///   ``EditRefusal/Code/offStep``, its ``EditRefusal/property`` the key written and
    ///   its message the nested location.
    static func checkNestedConstraints(_ write: ValueWrite, _ nested: [NestedValue], address: String) throws {
        for item in nested {
            guard let constraint = item.field?.constraint, let number = number(item.value),
                  let violation = constraint.violation(by: number)
            else { continue }
            let remedy = constraint.nearestAllowed(to: number).map { " — the nearest is \(PenValueConstraint.spell($0))" }
                ?? ""
            throw EditRefusal(
                code: violation == .offStep ? .offStep : .outOfRange,
                address: address,
                property: write.key,
                expected: constraint.summary,
                message: "\(address) \(item.location) is \(PenValueConstraint.spell(number)), "
                    + "but it takes \(constraint.summary)\(remedy)",
                nested: item.nestedLocation
            )
        }
    }

    // MARK: - Private

    /// Walks one value against the forms it may take.
    private static func walk(
        _ value: AnyCodable,
        forms: [PenValueForm],
        field: PenNestedShape.Field?,
        under property: String,
        path: [EditRefusal.NestedLocation.Component]
    ) -> [NestedValue] {
        switch value {
        case let .dictionary(entries):
            let fields = variant(of: entries, among: forms)?.fields ?? []
            return entries.keys.sorted().flatMap { key -> [NestedValue] in
                let item = entries[key] ?? .null
                let described = fields.first { $0.key == key }
                return element(
                    item, forms: described?.forms ?? [], field: described, under: property, path: path + [.key(key)]
                )
            }
        case let .array(items):
            let elementForms = elementForms(of: forms)
            return items.enumerated().flatMap { index, item in
                element(item, forms: elementForms, field: field, under: property, path: path + [.index(index)])
            }
        default:
            return []
        }
    }

    /// One member of an object or an array: walked into when structured, else itself.
    private static func element(
        _ item: AnyCodable,
        forms: [PenValueForm],
        field: PenNestedShape.Field?,
        under property: String,
        path: [EditRefusal.NestedLocation.Component]
    ) -> [NestedValue] {
        switch item {
        case .dictionary, .array: walk(item, forms: forms, field: field, under: property, path: path)
        default: [NestedValue(property: property, path: path, value: item, field: field)]
        }
    }

    /// The variant of the first nested shape among `forms` an object selects, or `nil`
    /// when no shape describes it or its discriminator names no variant.
    private static func variant(of entries: [String: AnyCodable], among forms: [PenValueForm]) -> PenNestedShape.Variant? {
        let shape = forms.lazy.compactMap { form -> PenNestedShape? in
            if case let .one(shape) = form { return shape }
            return nil
        }.first
        guard let shape else { return nil }
        guard let discriminator = shape.discriminator else { return shape.variants.first }
        guard case let .string(spelling)? = entries[discriminator] else { return nil }
        return shape.variants.first { $0.spelling == spelling }
    }

    /// The forms one element of an array written against `forms` may take.
    private static func elementForms(of forms: [PenValueForm]) -> [PenValueForm] {
        var result: [PenValueForm] = []
        for (index, form) in forms.enumerated() {
            switch form {
            case let .many(shape): result.append(.one(shape))
            case let .arrayOf(elements): result.append(contentsOf: elements)
            case .eitherInAnArray: result.append(contentsOf: forms[..<index])
            default: break
            }
        }
        return result
    }

    /// A number standing alone, or `nil`.
    private static func number(_ value: AnyCodable) -> Double? {
        switch value {
        case let .int(number): Double(number)
        case let .double(number): number
        default: nil
        }
    }
}
