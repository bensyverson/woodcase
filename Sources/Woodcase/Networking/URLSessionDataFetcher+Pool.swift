//
//  URLSessionDataFetcher+Pool.swift
//  Woodcase
//

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Synchronization

extension URLSessionDataFetcher {
    /// Which pooled session a request goes through.
    enum SessionRoute: Hashable {
        /// Direct, from a fetcher whose environment names a proxy: such a session must
        /// ignore the system's proxy settings, so it cannot be `URLSession.shared`.
        case direct
        /// Through this proxy, with its credentials.
        case proxy(ProxyEndpoint)
    }

    /// The sessions every fetcher shares, by route.
    ///
    /// A `URLSession` pools its connections — HTTP/2 multiplexing, keep-alive — and is
    /// freed only when invalidated, so a fetcher that made its own would both defeat
    /// pooling and leak when callers make fetchers freely (one per paste, one per image).
    /// Sharing one per route, as `URLSession.shared` is shared, fixes both: the pool holds
    /// one session per distinct proxy the process has seen, plus one direct, and keeps them
    /// for the process's life, so none is ever invalidated.
    private static let pool = Mutex<[SessionRoute: URLSession]>([:])

    /// The pooled session for `route`, made on first use.
    static func pooledSession(_ route: SessionRoute) -> URLSession {
        pool.withLock { sessions in
            if let session = sessions[route] { return session }
            let proxy: ProxyEndpoint? = if case let .proxy(endpoint) = route { endpoint } else { nil }
            let session = URLSession(configuration: configuration(through: proxy))
            sessions[route] = session
            return session
        }
    }
}
