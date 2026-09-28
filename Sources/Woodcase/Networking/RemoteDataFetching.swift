//
//  RemoteDataFetching.swift
//  Woodcase
//

import Foundation

/// A type that can fetch data from a URL.
///
/// This protocol is the library's one networking seam: everything that reaches out to
/// the network — ``GoogleFontResolver`` for TTFs, ``RemoteImageResolver`` for image
/// fills — goes through it, so production code uses ``StandardDataFetcher/make(environment:)``
/// (``URLSessionDataFetcher``, with a ``CurlDataFetcher`` fallback on macOS) and tests
/// inject a mock instead of touching the network.
public protocol RemoteDataFetching: Sendable {
    /// Fetches data from the given URL.
    ///
    /// - Parameter url: The URL to fetch.
    /// - Returns: The response data.
    /// - Throws: ``RemoteFetchError/httpError(statusCode:)`` on non-200 responses, and
    ///   ``RemoteFetchError/unreachable(_:)`` when the request got no answer. A mock may
    ///   throw anything; callers treat an unknown error as unreachable.
    func fetch(url: URL) async throws -> Data
}
