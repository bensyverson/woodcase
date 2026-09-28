//
//  PenDollarEscape.swift
//  Woodcase
//

import Foundation

/// Woodcase's own escape for a string that has to hold a literal `$`.
///
/// One character, one rule, wherever it is written. In the .pen format a string
/// property beginning with `$` is a reference to a variable of that name, so a caption
/// that reads `$30.00` needs a way to say "this is text". `\$` is that way. The format
/// itself defines no escape — this convention is Woodcase's — so the escape is *read*
/// anywhere in the string and *written* only where the wire form is ambiguous:
///
/// | Stored in the file | Means |
/// |---|---|
/// | `$brand` | a reference to the variable `brand` |
/// | `\$brand` | the literal `$brand` |
/// | `Price: \$30` | the literal `Price: $30` |
/// | `Price: $30` | the literal `Price: $30` — only a *leading* `$` is a reference |
///
/// ``escaped(_:)`` therefore adds a backslash only in front of a leading `$`. A `$` in
/// the middle of a string is written bare, which is what Pen.app — which knows nothing
/// of this convention — needs in order to read it back as the text it is.
///
/// One case cannot survive the round trip: a literal backslash standing immediately
/// before a `$`, which reads as the escape and loses its backslash. Escaping
/// backslashes as well would put a second convention into a format that has none, and
/// buy a case no design document has ever needed; the pair is read as the escape and
/// the trade-off is accepted.
///
/// A `$name` naming a variable the document defines nowhere is a separate rule, and it
/// belongs to text content alone — see ``PenVariableResolver``.
public enum PenDollarEscape {
    /// The escape as it is stored: a backslash and the dollar it protects.
    public static let sequence = "\\$"

    /// The character a leading occurrence of which introduces a variable reference.
    public static let dollar = "$"

    /// A stored string with every `\$` reduced to the `$` it stands for.
    ///
    /// - Parameter string: The string as the file stores it.
    /// - Returns: The text it means.
    public static func unescaped(_ string: String) -> String {
        string.replacingOccurrences(of: sequence, with: dollar)
    }

    /// A literal as the file should store it.
    ///
    /// - Parameter literal: The text to store.
    /// - Returns: The literal with a leading `$` escaped, and every other character —
    ///   a `$` further in included — left exactly as it is.
    public static func escaped(_ literal: String) -> String {
        literal.hasPrefix(dollar) ? "\\" + literal : literal
    }
}
