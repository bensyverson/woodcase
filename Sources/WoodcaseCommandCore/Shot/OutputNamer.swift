import Foundation

/// Computes output filenames and paths for rendered files.
enum OutputNamer {
    /// Computes the output filename for a rendered frame.
    ///
    /// - Parameters:
    ///   - baseName: The .pen filename without extension.
    ///   - frameName: The frame's name (nil for single-frame documents).
    ///   - format: Output format (png or pdf).
    ///   - scale: Render scale factor.
    ///   - isMultiFrame: Whether the document contains multiple frames.
    /// - Returns: A filename like `myfile-Screen1@2x.png`.
    static func filename(
        baseName: String,
        frameName: String?,
        format: OutputFormat,
        scale: Int,
        isMultiFrame: Bool,
        activeThemeValues: [String] = []
    ) -> String {
        // PDF: one file per theme combination (frames are pages)
        if format == .pdf {
            return "\(baseName).pdf"
        }

        var name = baseName
        if isMultiFrame, let frameName {
            var cleaned = frameName
            if !activeThemeValues.isEmpty {
                cleaned = stripThemeSuffixes(cleaned, values: activeThemeValues)
            }
            name += "-\(sanitize(cleaned))"
        }
        if scale > 1 {
            name += "@\(scale)x"
        }
        name += ".png"
        return name
    }

    /// Removes parenthesized substrings that match any of the given theme values.
    private static func stripThemeSuffixes(
        _ name: String, values: [String]
    ) -> String {
        var result = name
        for value in values {
            let pattern = "\\s*\\(\(NSRegularExpression.escapedPattern(for: value))\\)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func sanitize(_ value: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>| ")
        return value.unicodeScalars
            .map { unsafe.contains($0) ? "-" : String($0) }
            .joined()
    }
}
