//
//  ProxyEnvironment.swift
//  Woodcase
//

import Foundation

/// The proxies the conventional environment variables name, and the route each URL takes.
///
/// `URLSession` on Apple platforms takes its proxies from System Configuration and never
/// reads `HTTPS_PROXY`. That is right for an app, and wrong for a command-line tool run
/// where the environment is the only thing that knows the way out — an agent sandbox
/// whose sole egress is an authenticated proxy on localhost, a CI runner, a corporate
/// shell. ``URLSessionDataFetcher`` reads this to route its requests the way curl would.
///
/// Parsing and routing are pure: this type never touches the network, so every rule
/// here is unit-tested without a proxy.
///
/// ## Variables
///
/// - term `https_proxy`, `HTTPS_PROXY`: the proxy for `https` URLs.
/// - term `http_proxy`, `HTTP_PROXY`: the proxy for `http` URLs.
/// - term `all_proxy`, `ALL_PROXY`: the proxy for either, when its own variable is unset.
/// - term `no_proxy`, `NO_PROXY`: comma-separated ``ProxyExclusion`` entries that go
///   direct.
///
/// The lowercase spelling wins when both are set, as in curl; an empty value counts as
/// unset. Only `http://` proxies are used (see ``ProxyEndpoint``).
public struct ProxyEnvironment: Friendly {
    /// Where one request goes.
    public enum Route: Friendly {
        /// Straight to the origin, with no proxy.
        case direct
        /// Through this proxy, by an HTTP `CONNECT` tunnel.
        case proxy(ProxyEndpoint)
    }

    /// The proxy for `https` URLs, if any.
    public var https: ProxyEndpoint?
    /// The proxy for `http` URLs, if any.
    public var http: ProxyEndpoint?
    /// The hosts that bypass both proxies.
    public var exclusions: [ProxyExclusion]

    /// Creates a proxy environment from its parts.
    ///
    /// - Parameters:
    ///   - https: The proxy for `https` URLs.
    ///   - http: The proxy for `http` URLs.
    ///   - exclusions: The hosts that go direct.
    public init(https: ProxyEndpoint? = nil, http: ProxyEndpoint? = nil, exclusions: [ProxyExclusion] = []) {
        self.https = https
        self.http = http
        self.exclusions = exclusions
    }

    /// Reads the proxy variables out of an environment.
    ///
    /// - Parameter environment: The variables, usually `ProcessInfo.processInfo.environment`.
    public init(environment: [String: String]) {
        func value(_ name: String) -> String? {
            for spelling in [name.lowercased(), name.uppercased()] {
                if let value = environment[spelling], !value.isEmpty { return value }
            }
            return nil
        }
        func endpoint(_ name: String) -> ProxyEndpoint? {
            (value(name) ?? value("all_proxy")).flatMap(ProxyEndpoint.init(proxyURL:))
        }
        self.init(
            https: endpoint("https_proxy"),
            http: endpoint("http_proxy"),
            exclusions: (value("no_proxy") ?? "")
                .split(separator: ",")
                .compactMap { ProxyExclusion(entry: String($0)) }
        )
    }

    /// Whether the environment names no proxy at all — the case in which the system's own
    /// proxy settings should decide.
    public var isEmpty: Bool {
        https == nil && http == nil
    }

    /// The route a request for `url` takes.
    ///
    /// - Parameter url: The URL about to be fetched.
    /// - Returns: ``Route/direct`` for an excluded host, an unproxied scheme or a URL
    ///   with no host; otherwise the scheme's proxy.
    public func route(for url: URL) -> Route {
        guard let host = url.host, !host.isEmpty else { return .direct }
        let proxy: ProxyEndpoint? = switch url.scheme?.lowercased() {
        case "https": https
        case "http": http
        default: nil
        }
        guard let proxy, !exclusions.contains(where: { $0.matches(host: host) }) else {
            return .direct
        }
        return .proxy(proxy)
    }
}
