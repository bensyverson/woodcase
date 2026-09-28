//
//  TrustFallbackDataFetcher.swift
//  Woodcase
//

import Foundation

/// A fetcher that retries with a second stack when the first could not check the server's
/// certificate at all.
///
/// The one failure it acts on is ``NetworkFailure/Reason/certificateTrustUnavailable``:
/// the request reached the server, but the process could not ask the system whether its
/// certificate is trusted — as inside the Claude Code Bash sandbox, which denies
/// `com.apple.trustd.agent`. A second stack that verifies certificates without that
/// service can still succeed, so the same URL goes to ``fallback``. Every other outcome of
/// ``primary`` — data, an HTTP status, any other transport failure, a certificate that was
/// checked and rejected — is returned or thrown untouched, so the normal path stays one
/// stack and a real trust verdict is never second-guessed.
///
/// When the fallback runs, its outcome is the fetch's outcome, failure included: it is the
/// attempt that could have worked, so its reason names the obstacle that remains.
/// ``StandardDataFetcher/make(environment:)`` composes ``URLSessionDataFetcher`` with
/// ``CurlDataFetcher`` this way on macOS.
public struct TrustFallbackDataFetcher: RemoteDataFetching {
    /// The fetcher every request goes to first.
    public let primary: any RemoteDataFetching
    /// The fetcher a request is retried with when ``primary`` could not check a certificate.
    public let fallback: any RemoteDataFetching

    /// Creates a fetcher that tries `primary`, then `fallback` when trust was unavailable.
    ///
    /// - Parameters:
    ///   - primary: The fetcher every request goes to first.
    ///   - fallback: The fetcher to retry with.
    public init(primary: any RemoteDataFetching, fallback: any RemoteDataFetching) {
        self.primary = primary
        self.fallback = fallback
    }

    /// Fetches through ``primary``, retrying through ``fallback`` only when the primary's
    /// failure is ``RemoteFetchError/unreachable(_:)`` for an unreachable trust service.
    ///
    /// - Parameter url: The URL to fetch.
    /// - Returns: The response body.
    /// - Throws: Whatever ``primary`` threw, or whatever ``fallback`` threw when it ran.
    public func fetch(url: URL) async throws -> Data {
        do {
            return try await primary.fetch(url: url)
        } catch let RemoteFetchError.unreachable(failure) where failure.reason == .certificateTrustUnavailable {
            return try await fallback.fetch(url: url)
        }
    }
}
