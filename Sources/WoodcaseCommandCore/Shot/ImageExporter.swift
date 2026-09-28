import CoreGraphics
import Foundation
import Woodcase

/// Writes `CGImage` instances to PNG files.
///
/// The encoding itself lives in the library, as `PNGEncoder`, because the viewer needs
/// the same bytes without a file; this is the CLI's name for it.
enum ImageExporter {
    /// Writes a `CGImage` as a PNG file at the given URL.
    ///
    /// Creates intermediate directories if needed.
    static func writePNG(_ image: CGImage, to url: URL) throws {
        try PNGEncoder.write(image, to: url)
    }
}
