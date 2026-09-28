//
//  TrustFallbackDataFetcherTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// The decorator that retries with a second stack only when the first could not check a
/// certificate at all.
@Suite("Trust fallback fetcher")
struct TrustFallbackDataFetcherTests {
    /// A fetcher that answers every URL with one scripted outcome and counts its calls.
    final class ScriptedFetcher: RemoteDataFetching, @unchecked Sendable {
        let outcome: Result<Data, RemoteFetchError>
        private let lock = NSLock()
        private var count = 0

        init(_ outcome: Result<Data, RemoteFetchError>) {
            self.outcome = outcome
        }

        var calls: Int {
            lock.withLock { count }
        }

        func fetch(url _: URL) async throws -> Data {
            lock.withLock { count += 1 }
            return try outcome.get()
        }
    }

    static let url = URL(string: "https://example.invalid/font.ttf")!

    static func unreachable(_ reason: NetworkFailure.Reason) -> RemoteFetchError {
        .unreachable(NetworkFailure(reason: reason, domain: NSURLErrorDomain, code: -1202, proxy: "127.0.0.1:1"))
    }

    @Test("A certificate nobody could check is retried with the fallback")
    func fallsBackOnTrustUnavailable() async throws {
        let primary = ScriptedFetcher(.failure(Self.unreachable(.certificateTrustUnavailable)))
        let fallback = ScriptedFetcher(.success(Data("ttf".utf8)))
        let fetcher = TrustFallbackDataFetcher(primary: primary, fallback: fallback)

        let data = try await fetcher.fetch(url: Self.url)

        #expect(data == Data("ttf".utf8))
        #expect(primary.calls == 1)
        #expect(fallback.calls == 1)
    }

    @Test("The fallback's own failure is what the caller sees")
    func fallbackFailureSurfaces() async {
        let primary = ScriptedFetcher(.failure(Self.unreachable(.certificateTrustUnavailable)))
        let fallback = ScriptedFetcher(.failure(.httpError(statusCode: 404)))
        let fetcher = TrustFallbackDataFetcher(primary: primary, fallback: fallback)

        await #expect(throws: RemoteFetchError.httpError(statusCode: 404)) {
            try await fetcher.fetch(url: Self.url)
        }
    }

    @Test("Every other transport failure passes through untouched", arguments: NetworkFailure.Reason.allCases.filter {
        $0 != .certificateTrustUnavailable
    })
    func otherFailuresPassThrough(reason: NetworkFailure.Reason) async {
        let primary = ScriptedFetcher(.failure(Self.unreachable(reason)))
        let fallback = ScriptedFetcher(.success(Data()))
        let fetcher = TrustFallbackDataFetcher(primary: primary, fallback: fallback)

        await #expect(throws: Self.unreachable(reason)) {
            try await fetcher.fetch(url: Self.url)
        }
        #expect(fallback.calls == 0)
    }

    @Test("A server's answer passes through untouched")
    func httpErrorPassesThrough() async {
        let primary = ScriptedFetcher(.failure(.httpError(statusCode: 404)))
        let fallback = ScriptedFetcher(.success(Data()))
        let fetcher = TrustFallbackDataFetcher(primary: primary, fallback: fallback)

        await #expect(throws: RemoteFetchError.httpError(statusCode: 404)) {
            try await fetcher.fetch(url: Self.url)
        }
        #expect(fallback.calls == 0)
    }

    @Test("Success passes through without touching the fallback")
    func successPassesThrough() async throws {
        let primary = ScriptedFetcher(.success(Data("body".utf8)))
        let fallback = ScriptedFetcher(.success(Data("other".utf8)))
        let fetcher = TrustFallbackDataFetcher(primary: primary, fallback: fallback)

        #expect(try await fetcher.fetch(url: Self.url) == Data("body".utf8))
        #expect(fallback.calls == 0)
    }
}
