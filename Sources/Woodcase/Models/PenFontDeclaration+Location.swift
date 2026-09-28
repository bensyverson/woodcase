//
//  PenFontDeclaration+Location.swift
//  Woodcase
//

import Foundation

public extension PenFontDeclaration {
    /// Where the font file is, as a URL a loader can open.
    ///
    /// A relative ``url`` is resolved against the directory the .pen file sits in — the
    /// same rule an image fill's path follows (``PenRenderer/imageProvider(relativeTo:remote:)``).
    /// An absolute path becomes a file URL, and a URL with a scheme (`https://…`,
    /// `file://…`) is kept as written.
    ///
    /// ```swift
    /// PenFontDeclaration(name: "B", url: "fonts/B.ttf")
    ///     .resolvedURL(relativeTo: URL(fileURLWithPath: "/designs/brand"))
    /// // file:///designs/brand/fonts/B.ttf
    /// ```
    ///
    /// - Parameter directory: The directory holding the .pen file that declared the font.
    /// - Returns: The file's URL, or `nil` when ``url`` is blank or names a scheme that
    ///   does not parse.
    func resolvedURL(relativeTo directory: URL) -> URL? {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        if address.prefixMatch(of: #/[A-Za-z][A-Za-z0-9+.\-]*:\/\//#) != nil {
            return URL(string: address)
        }
        if address.hasPrefix("/") {
            return URL(fileURLWithPath: address)
        }
        return directory.appendingPathComponent(address)
    }
}
