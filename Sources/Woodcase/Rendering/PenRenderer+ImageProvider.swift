import CoreGraphics
import Foundation
import ImageIO

public extension PenRenderer {
    /// Creates an ``ImageProvider`` that serves both kinds of image fill: files beside
    /// the `.pen` document, and images downloaded from `http(s)` URLs.
    ///
    /// This is the provider to use for rendering a `.pen` file from the filesystem. The
    /// URL's scheme decides which half answers, so `"./images/photo.png"` is read from
    /// disk and `"https://images.example.com/hero.jpg"` comes from the remote cache.
    ///
    /// Remote images must have been downloaded first —
    /// ``RemoteImageResolver/prepareImages(for:)``, once, before rendering. A remote URL
    /// nobody prepared yields `nil` and its fill is simply not drawn, the same as a
    /// missing file.
    ///
    /// - Parameters:
    ///   - baseDir: The directory to resolve relative URLs against, typically the
    ///     parent directory of the `.pen` file.
    ///   - remote: The resolver holding downloaded remote images. Defaults to
    ///     ``RemoteImageResolver/shared``, which is what `prepareImages` fills.
    /// - Returns: An ``ImageProvider`` covering both local and remote fills.
    static func imageProvider(
        relativeTo baseDir: URL,
        remote: RemoteImageResolver = .shared
    ) -> ImageProvider {
        let file = fileImageProvider(relativeTo: baseDir)
        return { url in
            RemoteImageResolver.isRemote(url) ? remote.cachedImage(for: url) : file(url)
        }
    }

    /// Creates an ``ImageProvider`` that loads images from disk by resolving
    /// URL strings relative to a base directory.
    ///
    /// Handles local fills only. Prefer ``imageProvider(relativeTo:remote:)`` unless you
    /// deliberately want remote fills left undrawn: a remote URL passed here becomes a
    /// nonsense path under `baseDir` and returns `nil`.
    ///
    /// - Parameter baseDir: The directory to resolve relative URLs against,
    ///   typically the parent directory of the `.pen` file.
    /// - Returns: An ``ImageProvider`` that returns a `CGImage` for valid
    ///   image paths, or `nil` for missing or unreadable files.
    static func fileImageProvider(relativeTo baseDir: URL) -> ImageProvider {
        { url in
            let resolved = baseDir.appendingPathComponent(url)
            guard let source = CGImageSourceCreateWithURL(resolved as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                return nil
            }
            return image
        }
    }
}
