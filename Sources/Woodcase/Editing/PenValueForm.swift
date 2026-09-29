//
//  PenValueForm.swift
//  Woodcase
//

import Foundation

/// One wire form a .pen property value may take.
///
/// A form is the smallest thing both a refusal and the schema help need to know, and
/// they need different halves of it: a refusal wants the phrase ("a `$variable`"), the
/// schema table wants the machine fact (`$number` — a variable, of type number). Before
/// this type the phrase was all there was, a `[String]` of prose, and the machine facts
/// could only have been recovered by parsing English back into types.
///
/// So every form carries both, generated from the same case. Constructing one fixes the
/// wording *and* the fact; neither can drift from the other, because there is only one
/// of them.
///
/// ```swift
/// PenValueForm.variable(.number).phrase      // a $variable
/// PenValueForm.variable(.number).signature   // $number
/// ```
public enum PenValueForm: Friendly {
    /// A JSON number.
    case number

    /// A JSON boolean.
    case boolean

    /// A JSON string, in the role this property reads it as.
    case text(StringRole)

    /// One exact spelling an enumerated property accepts, quoted as the file writes it.
    case spelling(String)

    /// A `"$name"` reference to a variable, which must be of this type.
    case variable(PenVariableType)

    /// A fixed-length JSON array whose slots are named, in order.
    case slots([String])

    /// One JSON object of a nested shape.
    case one(PenNestedShape)

    /// A JSON array of one nested shape.
    case many(PenNestedShape)

    /// A JSON array of any of the forms listed before this one.
    ///
    /// `fills` is the case that needs it: a color string, a fill object, or an array
    /// mixing the two. The alternative — spelling the union twice — is the kind of
    /// repetition that goes stale on one side only.
    case eitherInAnArray

    /// A JSON array whose every element takes one of these forms.
    ///
    /// Unlike ``eitherInAnArray`` the element forms are not accepted on their own: a
    /// mesh gradient's `points` is an array of `[x, y]` or mesh point objects, never a
    /// single point.
    case arrayOf([PenValueForm])

    /// A JSON container whose keys are the caller's own, described in words.
    case open(OpenShape)

    // MARK: - Nested vocabulary

    /// What a string means where a property takes one.
    ///
    /// The distinction is not decoration: `"#FFD166"` and `"M0 0 L10 10"` are both
    /// strings to `JSONDecoder`, and only one of them is a color.
    public enum StringRole: String, Friendly, CaseIterable {
        /// Any string.
        case plain
        /// A color — `"#RRGGBB"`, `"#RRGGBBAA"`, or a named color.
        case color
        /// SVG path data, as the `d` attribute writes it.
        case svgPathData
        /// A blend mode name; one the renderer does not know is kept as written.
        case blendMode
    }

    /// A JSON object or array with no fixed key table — the keys are theme axis names,
    /// descendant ids, or property names the caller chooses.
    ///
    /// There is nothing here for a decoder to drift from: the decoder reads a
    /// dictionary. The phrase and the signature are the whole description.
    public struct OpenShape: Friendly {
        /// Creates the description of an open container.
        ///
        /// - Parameters:
        ///   - phrase: How a refusal words it — "an object of property overrides".
        ///   - signature: How the schema table prints it — `{key: value}`.
        public init(phrase: String, signature: String) {
            self.phrase = phrase
            self.signature = signature
        }

        /// How a refusal words it.
        public let phrase: String

        /// How the schema table prints it.
        public let signature: String
    }

    // MARK: - The two halves

    /// The form as a refusal words it, mid-sentence.
    public var phrase: String {
        switch self {
        case .number: "a number"
        case .boolean: "a boolean"
        case let .text(role): role.phrase
        case let .spelling(value): "\"\(value)\""
        case .variable: "a $variable"
        case let .slots(names): "[\(names.joined(separator: ", "))]"
        case let .one(shape): shape.singular
        case let .many(shape): shape.plural
        case .eitherInAnArray: "an array of either"
        case let .arrayOf(forms): "an array, each element \(forms.map(\.phrase).joined(separator: " or "))"
        case let .open(shape): shape.phrase
        }
    }

    /// The form as the schema table prints it, in a union of alternatives.
    ///
    /// ``eitherInAnArray`` has no signature of its own — it is defined by what precedes
    /// it — so it answers with the empty string here and is resolved by
    /// ``signature(of:)``.
    public var signature: String {
        switch self {
        case .number: "number"
        case .boolean: "boolean"
        case let .text(role): role.signature
        case let .spelling(value): "\"\(value)\""
        case let .variable(type): "$\(type.rawValue)"
        case let .slots(names): "[\(names.joined(separator: ", "))]"
        case let .one(shape): shape.name
        case let .many(shape): "[\(shape.name), …]"
        case .eitherInAnArray: ""
        case let .arrayOf(forms): "[\(Self.signature(of: forms)), …]"
        case let .open(shape): shape.signature
        }
    }

    /// The variable type this form accepts, or `nil` if it is not a variable reference.
    public var variableType: PenVariableType? {
        if case let .variable(type) = self { return type }
        return nil
    }

    /// The nested shape this form describes, if it has one.
    ///
    /// For ``arrayOf(_:)``, the first nested shape among its element forms.
    public var nestedShape: PenNestedShape? {
        switch self {
        case let .one(shape), let .many(shape): shape
        case let .arrayOf(forms): forms.lazy.compactMap(\.nestedShape).first
        default: nil
        }
    }

    // MARK: - Reading a list of forms

    /// A union of forms, as the schema table prints a property's value column.
    ///
    /// - Parameter forms: The forms a property accepts, in the order they should read.
    /// - Returns: The signatures joined with ` | `, with ``eitherInAnArray`` resolved
    ///   to an array of everything before it.
    public static func signature(of forms: [PenValueForm]) -> String {
        var parts: [String] = []
        for form in forms {
            if case .eitherInAnArray = form {
                parts.append("[\(parts.joined(separator: " | ")), …]")
            } else {
                parts.append(form.signature)
            }
        }
        return parts.joined(separator: " | ")
    }

    /// Every exact spelling the forms accept, in the order the decoder declares them.
    ///
    /// - Parameter forms: The forms a property accepts.
    /// - Returns: The unquoted spellings, empty for a property no enumeration decides.
    public static func spellings(of forms: [PenValueForm]) -> [String] {
        forms.compactMap { if case let .spelling(value) = $0 { value } else { nil } }
    }

    /// The variable type the forms accept, or `nil` if none of them is a reference.
    ///
    /// - Parameter forms: The forms a property accepts.
    /// - Returns: The one variable type among them.
    public static func variableType(of forms: [PenValueForm]) -> PenVariableType? {
        forms.lazy.compactMap(\.variableType).first
    }
}

// MARK: - StringRole phrasing

public extension PenValueForm.StringRole {
    /// The role as a refusal words it.
    var phrase: String {
        switch self {
        case .plain: "a string"
        case .color: "a color string"
        case .svgPathData: "an SVG path data string"
        case .blendMode: "a blend mode string"
        }
    }

    /// The role as the schema table prints it.
    var signature: String {
        switch self {
        case .plain: "string"
        case .color: "color"
        case .svgPathData: "svg-path"
        case .blendMode: "blend-mode"
        }
    }
}
