//
//  FigmaImageFetchError.swift
//  Woodcase
//

/// Why ``FigmaImageFetcher`` could not bring back one image.
public enum FigmaImageFetchError: Error, Friendly {
    /// The URL figmeta named is not an `https` URL, so it was not fetched. A clipboard is
    /// untrusted input, and a `file:` URL would read the local disk.
    case invalidURL(String)
    /// The server answered with something other than the image, or never answered.
    case fetchFailed(RemoteFetchError)
    /// The download took longer than ``FigmaImageFetcher/timeout``.
    case timedOut
    /// The bytes' SHA-1, as lowercase hex, is not the hash they were fetched for: Figma
    /// names an image by the SHA-1 of its bytes, so these are not that image.
    case hashMismatch(actual: String)
    /// The bytes are not a PNG, JPEG, GIF or WebP file.
    case unrecognizedFormat
    /// The calling task was canceled before the image arrived.
    case cancelled
}
