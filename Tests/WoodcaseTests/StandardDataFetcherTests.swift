//
//  StandardDataFetcherTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// The one construction point for the fetcher the shared resolvers use. Nothing here
/// fetches: it only inspects what was composed.
@Suite("Standard data fetcher")
struct StandardDataFetcherTests {
    static let environment = ["HTTPS_PROXY": "http://user:pw@localhost:3128"]

    #if os(macOS)
        @Test("On macOS, URLSession first, with curl behind it for an unreachable trust service")
        func composesCurlFallback() throws {
            let fetcher = StandardDataFetcher.make(environment: Self.environment)

            let composed = try #require(fetcher as? TrustFallbackDataFetcher)
            let primary = try #require(composed.primary as? URLSessionDataFetcher)
            let fallback = try #require(composed.fallback as? CurlDataFetcher)
            #expect(primary.proxies == ProxyEnvironment(environment: Self.environment))
            #expect(fallback.environment == Self.environment)
        }
    #else
        @Test("Elsewhere, URLSession alone")
        func urlSessionAlone() {
            #expect(StandardDataFetcher.make(environment: Self.environment) is URLSessionDataFetcher)
        }
    #endif
}
