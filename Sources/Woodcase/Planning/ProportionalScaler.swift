//
//  ProportionalScaler.swift
//  Woodcase
//

import Foundation

/// Multiplies the lengths inside a property's value, in the file's own JSON shape, by one
/// factor, and notes every variable it met instead of a number.
///
/// It works on the wire shape (``NodePropertyCodec``'s ``AnyCodable``) rather than the typed
/// model, so the value it returns is the value to write, and one rule covers every type that
/// has the property: a `padding` is a number, `[v, h]` or `[t, r, b, l]` on every frame. A
/// `$name` is kept as it is — bound values stay bound (``ScalePlan/BoundValue``).
struct ProportionalScaler {
    /// The factor every length is multiplied by.
    let factor: Double

    /// The variables met, by name, since the last ``takeBound()``.
    private var bound: [String] = []

    /// Creates a scaler.
    ///
    /// - Parameter factor: The factor, a positive finite number.
    init(factor: Double) {
        self.factor = factor
    }

    /// The variables met since the last call, emptied.
    mutating func takeBound() -> [String] {
        defer { bound = [] }
        return bound
    }

    // MARK: - Numbers

    /// A length scaled: a number multiplied, a `$name` kept and noted, anything else kept.
    mutating func length(_ value: AnyCodable) -> AnyCodable {
        switch value {
        case let .int(number): Self.number(scaled(Double(number)))
        case let .double(number) where number.isFinite: Self.number(scaled(number))
        case let .string(text) where text.hasPrefix(PenDollarEscape.dollar):
            note(text)
        default: value
        }
    }

    /// A factor multiplied and kept to four decimals (``PenScaleRounding/factor(_:by:)``), so
    /// a note's look scale tracks its type size; anything that is not a number is kept.
    func factor(_ value: AnyCodable) -> AnyCodable {
        switch value {
        case let .int(int): Self.number(PenScaleRounding.factor(Double(int), by: factor))
        case let .double(double) where double.isFinite: Self.number(PenScaleRounding.factor(double, by: factor))
        default: value
        }
    }

    /// A member's coordinate scaled about `pivot`, the anchor's coordinate on the same axis
    /// of its parent: a number moved, a `$name` kept and noted.
    mutating func coordinate(_ value: AnyCodable, about pivot: Double) -> AnyCodable {
        let coordinate: Double
        switch value {
        case let .int(number): coordinate = Double(number)
        case let .double(number) where number.isFinite: coordinate = number
        default: return length(value)
        }
        let moved = pivot + factor * (coordinate - pivot)
        let precision = PenScaleRounding.lengthPrecision
        return Self.number((moved * precision).rounded() / precision)
    }

    /// `length` multiplied and kept to a hundredth of a point
    /// (``PenScaleRounding/length(_:by:)``); a length off zero stays off zero.
    func scaled(_ length: Double) -> Double {
        PenScaleRounding.length(length, by: factor)
    }

    /// A number as the codec writes one: a whole number as `.int`.
    static func number(_ value: Double) -> AnyCodable {
        if value == value.rounded(), abs(value) < Double(Int.max) { return .int(Int(value)) }
        return .double(value)
    }

    /// Notes a `$name` and returns it unchanged.
    private mutating func note(_ reference: String) -> AnyCodable {
        bound.append(String(reference.dropFirst(PenDollarEscape.dollar.count)))
        return .string(reference)
    }

    // MARK: - Shapes

    /// A `width` or `height`: a number scaled, a fallback inside `fit_content(…)` or
    /// `fill_container(…)` scaled, the keyword itself kept — the sizing mode never changes.
    mutating func sizing(_ value: AnyCodable) -> AnyCodable {
        guard case let .string(text) = value, !text.hasPrefix(PenDollarEscape.dollar) else { return length(value) }
        for keyword in Self.sizingKeywords {
            let open = keyword + "("
            guard text.hasPrefix(open), text.hasSuffix(")"),
                  let fallback = Double(text.dropFirst(open.count).dropLast()), fallback.isFinite
            else { continue }
            return .string("\(open)\(Self.spelled(scaled(fallback))))")
        }
        return value
    }

    /// The sizing keywords that may carry a fallback, as `PenSizing` spells them.
    private static let sizingKeywords = ["fit_content", "fill_container"]

    /// A number as a sizing string spells it: no `.0` on a whole number.
    private static func spelled(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// A number or a list of numbers — a `cornerRadius`, a `padding`, a dash pattern.
    mutating func lengths(_ value: AnyCodable) -> AnyCodable {
        guard case let .array(items) = value else { return length(value) }
        return .array(items.map { length($0) })
    }

    /// A number, or an object of numbers — a per-side `strokeWidth`. Keys that are not
    /// lengths are kept.
    mutating func sides(_ value: AnyCodable) -> AnyCodable {
        guard case let .dictionary(object) = value else { return length(value) }
        var scaledObject = object
        for key in Self.sideKeys where object[key] != nil {
            scaledObject[key] = object[key].map { length($0) }
        }
        return .dictionary(scaledObject)
    }

    /// The keys of a per-side stroke width.
    private static let sideKeys = ["top", "right", "bottom", "left"]

    /// A node's `effect`: one effect or a list. A shadow's offset and blur scale, and a
    /// layer or background blur's radius; colors, blend modes and unknown effects are kept.
    mutating func effects(_ value: AnyCodable) -> AnyCodable {
        switch value {
        case let .array(items): .array(items.map { effect($0) })
        case .dictionary: effect(value)
        default: value
        }
    }

    /// One effect, scaled as ``effects(_:)`` describes.
    mutating func effect(_ value: AnyCodable) -> AnyCodable {
        guard case var .dictionary(object) = value, case let .string(type)? = object["type"] else { return value }
        switch type {
        case "shadow":
            if case var .dictionary(offset)? = object["offset"] {
                for axis in ["x", "y"] where offset[axis] != nil {
                    offset[axis] = offset[axis].map { length($0) }
                }
                object["offset"] = .dictionary(offset)
            }
            if let blur = object["blur"] { object["blur"] = length(blur) }
        case "blur", "background_blur":
            if let radius = object["radius"] { object["radius"] = length(radius) }
        default:
            break
        }
        return .dictionary(object)
    }

    /// A `metadata.woodcase.shadowSpread` list: each spread scales, and so does the shadow
    /// it was made for, exactly as the node's own shadow scales — so the entry still matches
    /// it and is not stale (``PenShadowSpread/isStale(for:)``).
    mutating func shadowSpreads(_ value: AnyCodable) -> AnyCodable {
        guard case let .array(entries) = value else { return value }
        return .array(entries.map { entry in
            guard case var .dictionary(object) = entry else { return entry }
            if let spread = object["spread"] { object["spread"] = length(spread) }
            if let shadow = object["shadow"] { object["shadow"] = effect(shadow) }
            return .dictionary(object)
        })
    }

    /// A `metadata.woodcase.spans` object: each run's own `fontSize` scales; the text and
    /// the offsets are kept, so the spans still match the content.
    mutating func spans(_ value: AnyCodable) -> AnyCodable {
        guard case var .dictionary(object) = value, case let .array(runs)? = object["runs"] else { return value }
        object["runs"] = .array(runs.map { run in
            guard case var .dictionary(fields) = run, let size = fields[Self.runFontSize] else { return run }
            fields[Self.runFontSize] = length(size)
            return .dictionary(fields)
        })
        return .dictionary(object)
    }

    /// A run's type-size key on the wire.
    private static let runFontSize = PenTextRun.WireKey.fontSize.rawValue
}
