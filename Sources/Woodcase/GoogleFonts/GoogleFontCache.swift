//
//  GoogleFontCache.swift
//  Woodcase
//

import Foundation

/// Manages on-disk caching of downloaded Google Font TTF files.
///
/// Font files are stored under a root directory organized by normalized family name:
/// ```
/// {rootDirectory}/{directoryName}/{filename}
/// ```
///
/// For example, "IBM Plex Sans" with filename "IBMPlexSans[wdth,wght].ttf" is cached at:
/// ```
/// {rootDirectory}/ibmplexsans/IBMPlexSans[wdth,wght].ttf
/// ```
///
/// Beside a family's font files sits its `METADATA.pb` (``metadataFilename``), cached
/// with the first face downloaded: it says which file serves which face, so a later run
/// can tell a face it holds from one it must fetch without asking the network.
///
/// The root is `$WOODCASE_HOME/fonts` — `~/.woodcase/fonts` by default — unless a caller
/// injects its own with ``init(rootDirectory:)``, which an editor with a platform cache
/// directory of its own does.
public struct GoogleFontCache: Sendable {
    /// The root directory where font files are cached.
    let rootDirectory: URL

    /// Creates a cache backed by the given root directory.
    ///
    /// - Parameter rootDirectory: The directory under which font files are stored.
    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// Creates a cache in the user's Woodcase directory: `$WOODCASE_HOME/fonts`.
    ///
    /// - Parameter environment: The environment to read `$WOODCASE_HOME` from. Defaults
    ///   to this process's.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        rootDirectory = Self.defaultCacheDirectory(in: environment)
    }

    /// The default cache directory: `fonts` inside ``WoodcaseHome/directory(in:)``.
    ///
    /// `~/.woodcase/fonts` unless `$WOODCASE_HOME` says otherwise. Nothing is created
    /// here; the first ``cache(data:family:filename:)`` makes what it needs.
    ///
    /// - Parameter environment: The environment to read `$WOODCASE_HOME` from. Defaults
    ///   to this process's.
    /// - Returns: The directory URL. It need not exist.
    public static func defaultCacheDirectory(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        WoodcaseHome.directory(in: environment)
            .appendingPathComponent(subdirectoryName, isDirectory: true)
    }

    /// The name of the fonts directory inside ``WoodcaseHome``.
    static let subdirectoryName = "fonts"

    /// The name a family's google/fonts metadata is cached under, as the repository
    /// names it.
    public static let metadataFilename = "METADATA.pb"

    /// The file extensions a cached font file has.
    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

    /// Every font file cached for `family`, sorted by name; empty when there are none.
    ///
    /// - Parameter family: The font family name.
    /// - Returns: The files' URLs.
    public func fontFileURLs(family: String) -> [URL] {
        // Built by `fontFileURL`, not taken from the listing, so a file listed here and
        // the same file written by a download are equal URLs.
        let directory = rootDirectory.appendingPathComponent(Self.directoryName(for: family))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { Self.fontExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .sorted()
            .map { fontFileURL(family: family, filename: $0) }
    }

    /// Returns cached font data for the given family and filename, or `nil` on cache miss.
    ///
    /// - Parameters:
    ///   - family: The font family name (e.g. "IBM Plex Sans").
    ///   - filename: The TTF filename (e.g. "IBMPlexSans[wdth,wght].ttf").
    /// - Returns: The cached font data, or `nil` if not cached.
    public func cachedFontData(family: String, filename: String) -> Data? {
        try? Data(contentsOf: fontFileURL(family: family, filename: filename))
    }

    /// The location a font file occupies in this cache, whether or not it exists yet.
    ///
    /// - Parameters:
    ///   - family: The font family name.
    ///   - filename: The TTF filename.
    /// - Returns: The file URL inside the cache.
    public func fontFileURL(family: String, filename: String) -> URL {
        rootDirectory
            .appendingPathComponent(Self.directoryName(for: family))
            .appendingPathComponent(filename)
    }

    /// Writes font data to the cache.
    ///
    /// Creates intermediate directories as needed.
    ///
    /// - Parameters:
    ///   - data: The TTF font data.
    ///   - family: The font family name.
    ///   - filename: The TTF filename.
    public func cache(data: Data, family: String, filename: String) throws {
        let dirURL = rootDirectory
            .appendingPathComponent(Self.directoryName(for: family))
        try FileManager.default.createDirectory(
            at: dirURL,
            withIntermediateDirectories: true
        )
        let fileURL = dirURL.appendingPathComponent(filename)
        try data.write(to: fileURL)
    }

    /// Converts a font family name to the Google Fonts repository directory name.
    ///
    /// The convention is lowercase with all spaces removed:
    /// - "IBM Plex Sans" → "ibmplexsans"
    /// - "Fira Code" → "firacode"
    /// - "Manrope" → "manrope"
    ///
    /// - Parameter family: The display name of the font family.
    /// - Returns: The normalized directory name.
    public static func directoryName(for family: String) -> String {
        family.lowercased().filter { !$0.isWhitespace }
    }
}
