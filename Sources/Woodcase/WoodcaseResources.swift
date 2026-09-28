//
//  WoodcaseResources.swift
//  Woodcase
//

import Foundation

/// Finds the library's resource bundle — the icon fonts and the SwiftUI and viewer
/// templates — without trapping when it is missing.
///
/// SwiftPM's generated `Bundle.module` calls `fatalError` when the bundle is not where it
/// looks, and `swift package experimental-install` copies the executable without it, so
/// an installed `woodcase` died on its first template read. This searches the same
/// places, adds the directory of the executable with every symlink resolved (a Homebrew
/// or `scripts/install` layout links `bin/woodcase` to a `libexec/` copy that has the
/// bundle beside it), and throws ``Missing`` when none of them holds it.
public enum WoodcaseResources {
    /// The bundle's directory name, as SwiftPM names it after the package and target.
    public static let bundleName = "Woodcase_Woodcase.bundle"

    /// The resource bundle, found once per process.
    ///
    /// - Returns: The bundle.
    /// - Throws: ``Missing`` when no searched directory holds it.
    public static func bundle() throws -> Bundle {
        try located.get()
    }

    private static let located: Result<Bundle, Missing> = Result {
        try locate(in: searchDirectories(
            executable: Bundle.main.executableURL,
            others: [Bundle.main.resourceURL, Bundle(for: BundleFinder.self).resourceURL, Bundle.main.bundleURL]
        ))
    }.mapError { $0 as? Missing ?? Missing(searched: []) }

    /// The directories to look in for the bundle, in order and without repeats: `others`,
    /// then the executable's own directory, then that directory with symlinks resolved.
    ///
    /// - Parameters:
    ///   - executable: The running executable as invoked — possibly a symlink.
    ///   - others: Directories searched first: an app's resources, a framework's, and
    ///     the main bundle's own directory, which are where SwiftPM looks.
    /// - Returns: The directories.
    static func searchDirectories(executable: URL?, others: [URL?]) -> [URL] {
        var directories = others.compactMap(\.self)
        if let executable {
            directories.append(executable.deletingLastPathComponent())
            directories.append(executable.resolvingSymlinksInPath().deletingLastPathComponent())
        }
        var seen: Set<String> = []
        return directories.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// The first bundle named ``bundleName`` in `directories`.
    ///
    /// - Parameter directories: Where to look, in order.
    /// - Returns: The bundle.
    /// - Throws: ``Missing`` naming every directory searched.
    static func locate(in directories: [URL]) throws -> Bundle {
        for directory in directories {
            let url = directory.appendingPathComponent(bundleName, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        throw Missing(searched: directories)
    }

    /// The resource bundle is in none of the places searched — usually an install that
    /// copied the `woodcase` executable without the bundle SwiftPM builds beside it.
    public struct Missing: Error, Friendly, CustomStringConvertible {
        /// Every directory looked in, in order.
        public let searched: [URL]

        /// What is missing, where it was looked for, and how to install so it is not.
        public var description: String {
            """
            Woodcase's resources are missing: no \(WoodcaseResources.bundleName) in \
            \(searched.map(\.path).joined(separator: ", ")). The woodcase binary needs that \
            bundle beside it, which `swift package experimental-install` does not copy. \
            Reinstall with scripts/install from a Woodcase checkout, or \
            `brew install bensyverson/tap/woodcase`.
            """
        }
    }

    /// Anchors `Bundle(for:)` to this module, for a framework build.
    private final class BundleFinder {}
}
