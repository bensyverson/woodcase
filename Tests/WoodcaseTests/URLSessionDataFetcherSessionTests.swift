//
//  URLSessionDataFetcherSessionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `URLSessionDataFetcher` shares one `URLSession` per route across every instance, so
/// fetchers made per paste or per image pool their connections and leave no session
/// behind un-invalidated.
struct URLSessionDataFetcherSessionTests {
    private static let url = URL(string: "https://example.test/image")!

    @Test("With no proxy, every fetcher uses the shared session")
    func direct() {
        let fetcher = URLSessionDataFetcher(environment: [:])
        #expect(fetcher.session(for: Self.url) === URLSession.shared)
    }

    @Test("Two fetchers routed through the same proxy share one session")
    func sameProxy() {
        let environment = ["HTTPS_PROXY": "http://proxy.test:8080"]
        let first = URLSessionDataFetcher(environment: environment)
        let second = URLSessionDataFetcher(environment: environment)
        #expect(first.session(for: Self.url) === second.session(for: Self.url))
        #expect(first.session(for: Self.url) !== URLSession.shared)
    }

    @Test("Fetchers routed through different proxies do not share a session")
    func differentProxies() {
        let first = URLSessionDataFetcher(environment: ["HTTPS_PROXY": "http://proxy.test:8080"])
        let second = URLSessionDataFetcher(environment: ["HTTPS_PROXY": "http://other.test:8080"])
        #expect(first.session(for: Self.url) !== second.session(for: Self.url))
    }

    @Test("A host the environment excludes goes direct through one session shared by proxied fetchers")
    func excludedHost() {
        let environment = ["HTTPS_PROXY": "http://proxy.test:8080", "NO_PROXY": "example.test"]
        let first = URLSessionDataFetcher(environment: environment)
        let second = URLSessionDataFetcher(environment: environment)
        #expect(first.session(for: Self.url) === second.session(for: Self.url))
        #expect(first.session(for: Self.url) !== URLSession.shared)
    }
}
