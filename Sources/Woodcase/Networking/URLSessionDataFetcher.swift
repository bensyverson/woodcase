//
//  URLSessionDataFetcher.swift
//  Woodcase
//

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(Network)
    import Network
#endif
#if canImport(Security)
    import Security
#endif

/// Default ``RemoteDataFetching`` implementation, over `URLSession`, that honors the
/// proxy environment.
///
/// When the environment names no proxy this is plain `URLSession.shared`, and the
/// system's own proxy settings apply as they do for any app. When it does — `HTTPS_PROXY`
/// and friends, read by ``ProxyEnvironment`` — the environment is authoritative, as it is
/// for curl: each request goes through the proxy its scheme names, or direct when
/// `NO_PROXY` excludes its host, and the system settings are not consulted. That is what
/// makes Google Fonts reachable from a process whose only egress is an authenticated
/// proxy, such as the Claude Code Bash sandbox.
///
/// On Apple platforms the proxy is configured with Network's `ProxyConfiguration`, an
/// HTTP `CONNECT` tunnel carrying the variable's Basic credentials — the older
/// `connectionProxyDictionary` route cannot authenticate a `CONNECT` reliably. On Linux,
/// FoundationNetworking's libcurl reads the same variables itself, so the shared session
/// is used throughout.
///
/// Every transport error comes out as ``RemoteFetchError/unreachable(_:)`` with a
/// classified ``NetworkFailure``; see project/2026-09-26-sandbox-font-downloads.md for the
/// failures this was built against. A certificate the process could not check
/// (``NetworkFailure/Reason/certificateTrustUnavailable``) is as far as this fetcher goes;
/// on macOS ``StandardDataFetcher`` puts a ``CurlDataFetcher`` behind it for that case.
public struct URLSessionDataFetcher: RemoteDataFetching {
    /// The proxies read from the environment at creation.
    public let proxies: ProxyEnvironment

    /// The session for requests that go direct.
    private let directSession: URLSession

    /// One session per proxy the environment names.
    private let proxiedSessions: [ProxyEndpoint: URLSession]

    /// Creates a fetcher routed by the given environment's proxy variables.
    ///
    /// - Parameter environment: The variables to read, `ProcessInfo`'s by default.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let proxies = ProxyEnvironment(environment: environment)
        self.proxies = proxies
        guard !proxies.isEmpty else {
            directSession = .shared
            proxiedSessions = [:]
            return
        }
        directSession = URLSession(configuration: Self.configuration(through: nil))
        var sessions: [ProxyEndpoint: URLSession] = [:]
        for endpoint in [proxies.https, proxies.http].compactMap(\.self) where sessions[endpoint] == nil {
            sessions[endpoint] = URLSession(configuration: Self.configuration(through: endpoint))
        }
        proxiedSessions = sessions
    }

    /// Fetches data from the given URL over HTTP, through the proxy its route names.
    ///
    /// - Parameter url: The URL to fetch.
    /// - Returns: The response body.
    /// - Throws: ``RemoteFetchError/httpError(statusCode:)`` for any status other than
    ///   200, ``RemoteFetchError/unreachable(_:)`` when the request got no answer.
    public func fetch(url: URL) async throws -> Data {
        let route = proxies.route(for: url)
        let proxy: ProxyEndpoint? = if case let .proxy(endpoint) = route { endpoint } else { nil }
        let session = proxy.flatMap { proxiedSessions[$0] } ?? directSession
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw RemoteFetchError.unreachable(NetworkFailure(
                classifying: error,
                trustEvaluationCode: Self.trustEvaluationCode(of: error),
                proxy: proxy?.description
            ))
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw RemoteFetchError.httpError(statusCode: http.statusCode)
        }
        return data
    }

    // MARK: - Sessions

    /// An ephemeral configuration that goes through `proxy`, or direct when it is `nil`.
    ///
    /// Ephemeral because a sandboxed process usually cannot write the on-disk URL cache,
    /// and a failed attempt logs half a dozen lines to standard error on every run.
    private static func configuration(through proxy: ProxyEndpoint?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        #if canImport(Network)
            if let proxyConfiguration = proxy.flatMap(proxyConfiguration(for:)) {
                configuration.proxyConfigurations = [proxyConfiguration]
            } else {
                // An empty dictionary is "no proxy" rather than "the system's proxies".
                configuration.connectionProxyDictionary = [:]
            }
        #endif
        return configuration
    }

    #if canImport(Network)
        /// A `CONNECT` proxy configuration for the endpoint, credentials applied.
        private static func proxyConfiguration(for proxy: ProxyEndpoint) -> ProxyConfiguration? {
            guard let port = UInt16(exactly: proxy.port).flatMap(NWEndpoint.Port.init(rawValue:)) else {
                return nil
            }
            let configuration = ProxyConfiguration(
                httpCONNECTProxy: .hostPort(host: NWEndpoint.Host(proxy.connectHost), port: port),
                tlsOptions: nil
            )
            if let username = proxy.username {
                configuration.applyCredential(username: username, password: proxy.password ?? "")
            }
            return configuration
        }
    #endif

    // MARK: - Failures

    /// What re-evaluating the server's trust from a certificate error returns, so a
    /// certificate that could not be *checked* is told apart from one that was checked
    /// and rejected.
    ///
    /// - Parameter error: The error the session threw.
    /// - Returns: The evaluation's error code, `0` when the trust now evaluates, or `nil`
    ///   when the error carries no trust to evaluate.
    private static func trustEvaluationCode(of error: Error) -> Int? {
        #if canImport(Security)
            guard let value = (error as NSError).userInfo[NSURLErrorFailingURLPeerTrustErrorKey],
                  CFGetTypeID(value as CFTypeRef) == SecTrustGetTypeID()
            else { return nil }
            let trust = unsafeDowncast(value as AnyObject, to: SecTrust.self)
            var trustError: CFError?
            guard !SecTrustEvaluateWithError(trust, &trustError) else { return 0 }
            return trustError.map { CFErrorGetCode($0) }
        #else
            return nil
        #endif
    }
}
