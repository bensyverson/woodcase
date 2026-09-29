//
//  ProxyEndpoint.swift
//  Woodcase
//

import Foundation

/// One HTTP proxy, as an `HTTPS_PROXY`-style variable names it: host, port and optional
/// Basic credentials.
///
/// Only plain `http://` proxies are modeled — the kind the Claude Code sandbox and most
/// corporate egress hand out, and the kind an HTTP `CONNECT` tunnel speaks to. A value
/// with any other scheme (`socks5h://`, `https://`) is not an HTTP proxy and parses to
/// `nil`, so the request falls through to the next variable or goes direct.
///
/// The password is carried because the proxy demands it, but ``description`` never prints
/// it: an endpoint that ends up in a diagnostic must not leak the credential.
public struct ProxyEndpoint: Friendly, CustomStringConvertible {
    /// The port curl assumes when a proxy variable names none.
    public static let defaultPort = 1080

    /// The loopback literal a proxy host of `localhost` is dialed as.
    ///
    /// Inside a sandbox with no name resolution — the Claude Code Bash sandbox denies the
    /// `mDNSResponder` service — even `localhost` cannot be looked up, and the proxy is
    /// unreachable by name. RFC 6761 lets an application treat `localhost` as loopback
    /// without asking a resolver, which is what curl does; this does the same, choosing
    /// IPv4 because that is where the sandbox's proxy listens.
    public static let loopbackLiteral = "127.0.0.1"

    /// The proxy's host, as written.
    public var host: String
    /// The proxy's port.
    public var port: Int
    /// The user name from the URL's userinfo, percent-decoded.
    public var username: String?
    /// The password from the URL's userinfo, percent-decoded. Never printed.
    public var password: String?

    /// Creates an endpoint.
    ///
    /// - Parameters:
    ///   - host: The proxy's host name or address.
    ///   - port: The proxy's port.
    ///   - username: The Basic-auth user, if the proxy wants one.
    ///   - password: The Basic-auth password, if the proxy wants one.
    public init(host: String, port: Int, username: String? = nil, password: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    /// Parses a proxy variable's value, such as `http://user:pass@localhost:3128`.
    ///
    /// A value with no scheme is taken as `http://`, and one with no port gets
    /// ``defaultPort``, both as curl reads them.
    ///
    /// - Parameter value: The variable's value.
    /// - Returns: `nil` when the value is not an `http` proxy URL with a host.
    public init?(proxyURL value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let spelled = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let components = URLComponents(string: spelled),
              components.scheme?.lowercased() == "http",
              let host = components.host, !host.isEmpty
        else { return nil }
        self.init(
            host: host,
            port: components.port ?? Self.defaultPort,
            username: components.user.flatMap { $0.isEmpty ? nil : $0 },
            password: components.password
        )
    }

    /// The host to open the connection to: ``host``, except that `localhost` becomes
    /// ``loopbackLiteral`` so no resolver is needed.
    public var connectHost: String {
        host.lowercased() == "localhost" ? Self.loopbackLiteral : host
    }

    /// Whether the endpoint carries a user name to answer the proxy's challenge with.
    public var hasCredentials: Bool {
        username != nil
    }

    /// `host:port` — never the credentials. Safe to print.
    public var description: String {
        "\(host):\(port)"
    }
}
