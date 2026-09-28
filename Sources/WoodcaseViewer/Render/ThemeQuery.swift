//
//  ThemeQuery.swift
//  WoodcaseViewer
//

import Foundation

/// Reads and writes the `?theme=` query parameter.
///
/// The viewer's URLs pin theme axes the way the design notes write them,
/// `?theme=Mode:Dark,Base:Slate`, because `=` inside a query value reads badly. The
/// CLI's `--theme Mode=Dark` spelling is accepted too: an agent that already knows one
/// form should not have to learn the other to use the same axes.
///
/// ``canonical(_:)`` is the reverse, and is what the render cache keys on — one
/// selection has exactly one spelling there, however it arrived.
public enum ThemeQuery {
    /// Parses a `?theme=` value into pinned axes.
    ///
    /// - Parameter value: The query parameter, or `nil` when it is absent.
    /// - Returns: The pinned axes; empty for an absent or empty parameter.
    /// - Throws: ``ViewerError/malformedTheme(_:)`` naming the pin that could not be
    ///   read. A pin that does not parse is an error, never a silently dropped axis.
    public static func parse(_ value: String?) throws -> [String: String] {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return [:] }

        var pins: [String: String] = [:]
        for pin in value.split(separator: ",", omittingEmptySubsequences: true) {
            let text = String(pin)
            guard let separator = text.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                throw ViewerError.malformedTheme(text.trimmingCharacters(in: .whitespaces))
            }
            let axis = text[text.startIndex ..< separator].trimmingCharacters(in: .whitespaces)
            let pinned = text[text.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !axis.isEmpty, !pinned.isEmpty else {
                throw ViewerError.malformedTheme(text.trimmingCharacters(in: .whitespaces))
            }
            pins[axis] = pinned
        }
        return pins
    }

    /// The canonical spelling of a selection: axes sorted, joined with colons and commas.
    ///
    /// - Parameter theme: The pinned axes.
    /// - Returns: The canonical text, empty when nothing is pinned.
    public static func canonical(_ theme: [String: String]) -> String {
        theme.keys.sorted().map { "\($0):\(theme[$0] ?? "")" }.joined(separator: ",")
    }
}
