//
//  PenPropertyShape.swift
//  Woodcase
//

import Foundation

/// The .pen wire shape one property accepts, phrased as a caller has to type it.
///
/// A refusal is only useful if it says what would have been taken instead, and the
/// part hardest to guess is the *spelling*: a fill's type is `"color"`, never
/// `"solid"`; a blur behind a node is `"background_blur"`, never `"backdrop"`. So a
/// shape is **assembled from the types that do the decoding** rather than written
/// out beside them — ``oneOf(_:)`` reads an enumerated property's spellings off the
/// enumeration itself, and the fill and effect key tables come from ``PenFill/schema``
/// and ``PenEffect/schema``. Prose that merely describes a decoder drifts from it;
/// prose generated from one cannot.
///
/// Each accepted form is a ``PenValueForm`` rather than a sentence, so the same shape
/// answers both audiences: ``prose`` words a refusal, and ``signature``,
/// ``spellings``, ``variable`` and ``nested`` are what `woodcase schema` prints.
///
/// ``example`` is the other half: a literal the caller can paste after an `=`.
/// `StructuredPropertyShapeTests` writes every example through
/// ``NodePropertyCodec`` and fails if one of them is not accepted, so an example
/// cannot go stale either.
///
/// ```swift
/// NodePropertyCodec.shape(of: "fills")?.prose
/// // a color string, a fill object, or an array of either
/// // (a fill object's type is one of color, gradient, image, mesh_gradient, shader),
/// // for example [{"type":"color","color":"#FFD166"}]
/// NodePropertyCodec.shape(of: "fills")?.signature
/// // color | fill | [color | fill, …]
/// ```
public struct PenPropertyShape: Friendly {
    /// Creates a shape.
    ///
    /// - Parameters:
    ///   - forms: The accepted forms, in the order they should read.
    ///   - detail: A clause qualifying the forms, usually the spellings a nested
    ///     `"type"` key accepts.
    ///   - example: A literal this property accepts.
    public init(forms: [PenValueForm], detail: String? = nil, example: String? = nil) {
        self.forms = forms
        self.detail = detail
        self.example = example
    }

    /// The accepted forms, in the order they should read.
    public let forms: [PenValueForm]

    /// A clause qualifying the forms — the spellings a nested `"type"` key accepts.
    public let detail: String?

    /// A literal this property accepts, ready to paste after an `=`.
    public let example: String?

    // MARK: - For a refusal

    /// The whole shape in one clause, as a refusal prints it.
    public var prose: String {
        var text = Self.list(forms.map(\.phrase))
        if let detail { text += " (\(detail))" }
        if let example { text += ", for example \(example)" }
        return text
    }

    // MARK: - For the schema table

    /// The accepted forms as one union — `number | "fit_content" | $number`.
    public var signature: String {
        PenValueForm.signature(of: forms)
    }

    /// Every exact spelling this property accepts, empty when no enumeration decides it.
    public var spellings: [String] {
        PenValueForm.spellings(of: forms)
    }

    /// The type a `$variable` written here must have, or `nil` if none is accepted.
    public var variable: PenVariableType? {
        PenValueForm.variableType(of: forms)
    }

    /// Every nested key table this property's forms reference, at any depth.
    public var nested: [PenNestedShape] {
        var seen = Set<String>()
        return forms.compactMap(\.nestedShape).flatMap(\.reachable).filter { seen.insert($0.name).inserted }
    }

    // MARK: - Building a shape

    /// The shape of a property whose value is one of an enumerated type's spellings.
    ///
    /// Pass the enumeration the .pen decoder uses for the property. Only the type is
    /// read, never a value of it, so the shape lists exactly what that decoder takes.
    ///
    /// - Returns: A shape listing every spelling the type accepts, quoted, in the
    ///   order the type declares them.
    public static func oneOf<E: CaseIterable & RawRepresentable>(_: E.Type) -> PenPropertyShape
        where E.RawValue == String
    {
        PenPropertyShape(forms: E.allCases.map { .spelling($0.rawValue) })
    }

    /// A list phrased for a sentence: `a`, `a or b`, `a, b, or c`.
    ///
    /// - Parameter items: The items to list, in the order they should read.
    /// - Returns: The items joined with commas and a final `or`.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) or \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", or \(items[items.count - 1])"
        }
    }
}
