//
//  RemoteImageCache.swift
//  Woodcase
//

import Foundation

/// Manages on-disk caching of image files downloaded for remote image fills.
///
/// Unlike ``GoogleFontCache``, which has a family name to organize by, an image fill's
/// only identity is its URL — so the cache is flat and the filename *is* the identity:
///
/// ```
/// {rootDirectory}/{16 hex characters}.img
/// ```
///
/// For example `https://images.unsplash.com/photo-42?w=800` might be cached at:
///
/// ```
/// {rootDirectory}/6f1c0a94d3b27e15.img
/// ```
///
/// The root is `$WOODCASE_HOME/images` — `~/.woodcase/images` by default — unless a
/// caller injects its own with ``init(rootDirectory:)``.
public struct RemoteImageCache: Sendable {
    /// The root directory where image files are cached.
    let rootDirectory: URL

    /// The extension every cached image file carries.
    ///
    /// Deliberately inert: `CGImageSource` sniffs the container from the bytes, so the
    /// cache does not have to know — and must not guess — whether a URL served a PNG,
    /// a JPEG or a WebP. A URL that ends in `.jpg` and serves a PNG is common enough
    /// that trusting the path would be a bug.
    static let fileExtension = "img"

    /// Creates a cache backed by the given root directory.
    ///
    /// - Parameter rootDirectory: The directory under which image files are stored.
    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// Creates a cache in the user's Woodcase directory: `$WOODCASE_HOME/images`.
    ///
    /// - Parameter environment: The environment to read `$WOODCASE_HOME` from. Defaults
    ///   to this process's.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        rootDirectory = Self.defaultCacheDirectory(in: environment)
    }

    /// The default cache directory: `images` inside ``WoodcaseHome/directory(in:)``.
    ///
    /// `~/.woodcase/images` unless `$WOODCASE_HOME` says otherwise.
    ///
    /// - Parameter environment: The environment to read `$WOODCASE_HOME` from. Defaults
    ///   to this process's.
    /// - Returns: The directory URL. It is not itself created here; the first write does that.
    public static func defaultCacheDirectory(
        in environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        WoodcaseHome.directory(in: environment)
            .appendingPathComponent(subdirectoryName, isDirectory: true)
    }

    /// The name of the images directory inside ``WoodcaseHome``.
    static let subdirectoryName = "images"

    /// Returns cached image bytes for the given URL, or `nil` on cache miss.
    ///
    /// - Parameter urlString: The image fill's URL, exactly as the .pen file spells it.
    /// - Returns: The cached bytes, or `nil` if nothing is cached for that URL.
    public func cachedImageData(for urlString: String) -> Data? {
        try? Data(contentsOf: imageFileURL(for: urlString))
    }

    /// The location an image occupies in this cache, whether or not it exists yet.
    ///
    /// - Parameter urlString: The image fill's URL.
    /// - Returns: The file URL inside the cache.
    public func imageFileURL(for urlString: String) -> URL {
        rootDirectory.appendingPathComponent(Self.filename(for: urlString))
    }

    /// Writes image bytes to the cache, creating the root directory if needed.
    ///
    /// - Parameters:
    ///   - data: The downloaded image bytes.
    ///   - urlString: The image fill's URL.
    /// - Throws: Whatever `FileManager` or `Data.write` raises — an unwritable cache
    ///   volume, most often. Callers treat that as recoverable.
    public func cache(data: Data, for urlString: String) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: imageFileURL(for: urlString))
    }

    /// The cache filename for a URL: sixteen lowercase hex characters and `.img`.
    ///
    /// The hash is FNV-1a over the whole URL string — query included, because a
    /// resizing query (`?w=800`) names a different image than the same path without
    /// it. FNV-1a rather than Swift's `Hasher` because the name must be stable across
    /// processes: `Hasher` is seeded per process, so a cache keyed by it would miss
    /// every one of its own entries after a restart. It is not a security hash; nothing
    /// here depends on collision resistance beyond keeping distinct URLs apart.
    ///
    /// - Parameter urlString: The image fill's URL.
    /// - Returns: The filename, with extension.
    public static func filename(for urlString: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in urlString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16, uppercase: false)
        let padded = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        return "\(padded).\(fileExtension)"
    }
}
