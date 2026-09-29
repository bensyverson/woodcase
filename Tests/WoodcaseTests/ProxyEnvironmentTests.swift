//
//  ProxyEnvironmentTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// Reading the conventional proxy variables into a typed route per URL.
///
/// Inside an agent sandbox the only way out is an authenticated HTTP proxy named by
/// `HTTPS_PROXY` and friends, and `URLSession` on Apple platforms never reads them. These
/// pin the parsing and the routing decision, which are pure; the placeholder credentials
/// here are made up.
@Suite("Proxy environment")
struct ProxyEnvironmentTests {
    /// The shape the Claude Code sandbox exports, with invented credentials.
    static let sandboxLike: [String: String] = [
        "HTTPS_PROXY": "http://agent:s3cr%40t@localhost:3128",
        "https_proxy": "http://agent:s3cr%40t@localhost:3128",
        "HTTP_PROXY": "http://agent:s3cr%40t@localhost:3128",
        "NO_PROXY": "localhost,127.0.0.1,::1,169.254.0.0/16,10.0.0.0/8,.internal.example",
    ]

    // MARK: - Parsing

    @Test("An empty environment names no proxy")
    func emptyEnvironment() {
        let proxies = ProxyEnvironment(environment: [:])
        #expect(proxies.https == nil)
        #expect(proxies.http == nil)
        #expect(proxies.exclusions.isEmpty)
        #expect(proxies.isEmpty)
    }

    @Test("HTTPS_PROXY yields host, port and percent-decoded credentials")
    func parsesCredentials() throws {
        let proxies = ProxyEnvironment(environment: Self.sandboxLike)
        let https = try #require(proxies.https)
        #expect(https.host == "localhost")
        #expect(https.port == 3128)
        #expect(https.username == "agent")
        #expect(https.password == "s3cr@t")
        #expect(!proxies.isEmpty)
    }

    @Test("The lowercase variable wins over the uppercase one")
    func lowercaseWins() {
        let proxies = ProxyEnvironment(environment: [
            "https_proxy": "http://lower:1111",
            "HTTPS_PROXY": "http://upper:2222",
        ])
        #expect(proxies.https?.host == "lower")
    }

    @Test("ALL_PROXY covers a scheme that has no variable of its own")
    func allProxyFallback() {
        let proxies = ProxyEnvironment(environment: [
            "ALL_PROXY": "http://everything:8080",
            "http_proxy": "http://plain:8081",
        ])
        #expect(proxies.https?.host == "everything")
        #expect(proxies.http?.host == "plain")
    }

    @Test("An empty value counts as unset")
    func emptyValueIsUnset() {
        let proxies = ProxyEnvironment(environment: ["https_proxy": "", "HTTPS_PROXY": "http://upper:2222"])
        #expect(proxies.https?.host == "upper")
    }

    @Test("A proxy with no scheme is an HTTP proxy, and no port means curl's 1080")
    func schemelessAndPortless() throws {
        let proxies = ProxyEnvironment(environment: ["https_proxy": "proxy.example"])
        let https = try #require(proxies.https)
        #expect(https.host == "proxy.example")
        #expect(https.port == 1080)
        #expect(https.username == nil)
        #expect(https.password == nil)
    }

    @Test("A SOCKS proxy is not an HTTP proxy and is not used", arguments: [
        "socks5h://localhost:1080", "socks5://localhost:1080",
    ])
    func socksIsIgnored(value: String) {
        let proxies = ProxyEnvironment(environment: ["https_proxy": value, "http_proxy": "http://plain:8081"])
        #expect(proxies.https == nil)
        #expect(proxies.http?.host == "plain")
    }

    @Test("The endpoint's description never shows the password")
    func descriptionRedacts() throws {
        let https = try #require(ProxyEnvironment(environment: Self.sandboxLike).https)
        #expect(!https.description.contains("s3cr"))
        #expect(https.description.contains("localhost:3128"))
    }

    @Test("localhost is dialed as the IPv4 loopback literal; other hosts are left alone")
    func localhostIsDialedAsLoopback() {
        #expect(ProxyEndpoint(host: "localhost", port: 1).connectHost == "127.0.0.1")
        #expect(ProxyEndpoint(host: "LOCALHOST", port: 1).connectHost == "127.0.0.1")
        #expect(ProxyEndpoint(host: "proxy.example", port: 1).connectHost == "proxy.example")
    }

    // MARK: - Routing

    @Test("An https URL goes through the HTTPS proxy")
    func routesHTTPSThroughProxy() throws {
        let proxies = ProxyEnvironment(environment: Self.sandboxLike)
        let url = try #require(URL(string: "https://raw.githubusercontent.com/google/fonts/main/ofl/lobster/METADATA.pb"))
        #expect(try proxies.route(for: url) == .proxy(#require(proxies.https)))
    }

    @Test("An http URL goes through the HTTP proxy")
    func routesHTTPThroughProxy() throws {
        let proxies = ProxyEnvironment(environment: ["http_proxy": "http://plain:8081"])
        let url = try #require(URL(string: "http://images.example/a.png"))
        #expect(try proxies.route(for: url) == .proxy(#require(proxies.http)))
        let secure = try #require(URL(string: "https://images.example/a.png"))
        #expect(proxies.route(for: secure) == .direct, "no HTTPS proxy is configured")
    }

    @Test("NO_PROXY hosts go direct", arguments: [
        "http://localhost:8080/a.png",
        "http://127.0.0.1/a.png",
        "http://[::1]:9000/a.png",
        "http://10.1.2.3/a.png",
        "https://169.254.169.254/latest",
        "https://internal.example/a.png",
        "https://cdn.internal.example/a.png",
    ])
    func excludedHostsGoDirect(url: String) throws {
        var environment = Self.sandboxLike
        environment["HTTP_PROXY"] = "http://agent:pw@localhost:3128"
        let proxies = ProxyEnvironment(environment: environment)
        #expect(try proxies.route(for: #require(URL(string: url))) == .direct)
    }

    @Test("Hosts outside NO_PROXY still use the proxy", arguments: [
        "https://11.0.0.1/a.png",
        "https://notinternal.example/a.png",
        "https://example/a.png",
        "https://172.16.0.1/a.png",
    ])
    func unexcludedHostsUseProxy(url: String) throws {
        let proxies = ProxyEnvironment(environment: Self.sandboxLike)
        let https = try #require(proxies.https)
        #expect(try proxies.route(for: #require(URL(string: url))) == .proxy(https))
    }

    @Test("NO_PROXY=* sends everything direct")
    func wildcardExcludesEverything() throws {
        let proxies = ProxyEnvironment(environment: ["https_proxy": "http://p:1", "no_proxy": "*"])
        #expect(try proxies.route(for: #require(URL(string: "https://anything.example"))) == .direct)
    }

    @Test("NO_PROXY matching ignores case and a leading dot or wildcard")
    func domainSuffixForms() throws {
        let proxies = ProxyEnvironment(environment: [
            "https_proxy": "http://p:1",
            "no_proxy": " Example.COM , *.corp.example ",
        ])
        for host in ["example.com", "www.example.com", "a.corp.example", "corp.example"] {
            let url = try #require(URL(string: "https://\(host)/"))
            #expect(proxies.route(for: url) == .direct, "\(host) should be excluded")
        }
        #expect(try proxies.route(for: #require(URL(string: "https://badexample.com/"))) != .direct)
    }

    @Test("Exclusions parse into typed rules")
    func exclusionsAreTyped() {
        let proxies = ProxyEnvironment(environment: ["no_proxy": "*,.a.example,10.0.0.0/8,::1,bogus/99"])
        #expect(proxies.exclusions.contains(.everything))
        #expect(proxies.exclusions.contains(.domain("a.example")))
        #expect(proxies.exclusions.count == 5)
    }
}
