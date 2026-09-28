import Foundation

/// Computes theme combinations from document themes and user-provided pins.
enum ThemeCombination {
    /// Computes the cartesian product of all theme axes, with pinned axes fixed.
    ///
    /// Returns `[[:]` (a single empty combination) when there are no themes.
    static func allCombinations(
        from themes: [String: [String]]?,
        pins: [String: String]
    ) -> [[String: String]] {
        guard let themes, !themes.isEmpty else { return [[:]] }

        let sortedAxes = themes.keys.sorted()
        var combinations: [[String: String]] = [[:]]

        for axis in sortedAxes {
            guard let options = themes[axis] else { continue }
            let values: [String] = if let pinned = pins[axis] {
                [pinned]
            } else {
                options
            }
            combinations = combinations.flatMap { existing in
                values.map { value in
                    var combo = existing
                    combo[axis] = value
                    return combo
                }
            }
        }

        return combinations
    }

    /// Returns a filesystem-safe subdirectory name for a theme combination.
    ///
    /// Axis values are sorted alphabetically by axis name and joined with `-`.
    /// Returns `nil` for an empty combination.
    static func subdirectoryName(for combination: [String: String]) -> String? {
        guard !combination.isEmpty else { return nil }
        return combination
            .sorted(by: { $0.key < $1.key })
            .map { sanitize($0.value) }
            .joined(separator: "-")
    }

    /// Returns `true` when a frame's theme dictionary is compatible with the
    /// active theme combination.
    ///
    /// - A frame with a `nil` or empty theme is unthemed, and an unthemed artboard
    ///   belongs in every combination — it has nothing pinning it to one.
    /// - Otherwise, every entry in the frame's theme must appear in the
    ///   combination with the same value, so a frame pinned to one option of an
    ///   axis matches only the combinations that carry that option.
    static func frameMatches(
        theme: [String: String]?,
        combination: [String: String]
    ) -> Bool {
        guard let theme, !theme.isEmpty else { return true }
        return theme.allSatisfy { axis, value in
            combination[axis] == value
        }
    }

    private static func sanitize(_ value: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return value.unicodeScalars
            .map { unsafe.contains($0) ? "-" : String($0) }
            .joined()
    }
}
