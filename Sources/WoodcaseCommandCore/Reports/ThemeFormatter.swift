/// Formats theme axes for display.
enum ThemeFormatter {
    /// Formats a themes dictionary as human-readable lines, one per axis.
    ///
    /// Returns `nil` if themes is nil or empty.
    static func format(_ themes: [String: [String]]?) -> String? {
        guard let themes, !themes.isEmpty else { return nil }
        return themes
            .sorted(by: { $0.key < $1.key })
            .map { axis, options in "\(axis): \(options.joined(separator: ", "))" }
            .joined(separator: "\n")
    }
}
