//
//  NetworkFailure.swift
//  Woodcase
//

import Foundation

/// Why a request got no answer, in terms a reader can act on.
///
/// A fetch that fails at the transport — no DNS, a refused proxy login, a certificate
/// nobody could check — is a different fact from a server that answered "not found", and
/// a caller must be able to say which. ``URLSessionDataFetcher`` and ``CurlDataFetcher``
/// wrap every transport error in one of these, inside ``RemoteFetchError/unreachable(_:)``,
/// keeping the underlying error's domain and code (for curl, ``CurlDataFetcher/errorDomain``
/// and its exit code) so nothing is lost in the translation.
public struct NetworkFailure: Error, Friendly, CustomStringConvertible {
    /// The failure, reduced to what the reader would do about it.
    public enum Reason: String, Friendly, CaseIterable {
        /// The host name could not be resolved.
        case hostNotFound
        /// The connection to the server was refused or dropped.
        case cannotConnect
        /// The operating system refused to open the connection — a sandbox or firewall
        /// with no way out for this destination.
        case connectionBlocked
        /// The request timed out.
        case timedOut
        /// The machine has no network connection.
        case offline
        /// The proxy could not be reached, or refused to open the tunnel.
        case proxyUnreachable
        /// The proxy rejected (or was never given) its credentials.
        case proxyAuthenticationFailed
        /// The server's certificate could not be checked at all, because the process
        /// cannot reach the system's certificate-trust service.
        ///
        /// On macOS ``StandardDataFetcher`` retries such a request with ``CurlDataFetcher``
        /// (see ``TrustFallbackDataFetcher``), whose own outcome replaces this one — so it
        /// reaches a reader only from a fetcher without that fallback: on iOS, or from a
        /// ``URLSessionDataFetcher`` used on its own.
        case certificateTrustUnavailable
        /// The server's certificate was checked and is not trusted.
        case certificateUntrusted
        /// Anything else.
        case other

        /// One clause saying what happened, for the middle of a sentence.
        public var explanation: String {
            switch self {
            case .hostNotFound:
                "the host name could not be resolved"
            case .cannotConnect:
                "the connection to the server failed"
            case .connectionBlocked:
                "the connection was not permitted — a sandbox or firewall blocks it; "
                    + "if the only way out is a proxy, set HTTPS_PROXY"
            case .timedOut:
                "the request timed out"
            case .offline:
                "this machine is not connected to a network"
            case .proxyUnreachable:
                "the proxy could not be reached or would not open a tunnel"
            case .proxyAuthenticationFailed:
                "the proxy rejected its credentials"
            case .certificateTrustUnavailable:
                "the server's certificate could not be checked because this process cannot "
                    + "reach the system certificate-trust service (com.apple.trustd.agent) — "
                    + "a sandbox is blocking it; in the Claude Code Bash sandbox, set "
                    + "`sandbox.enableWeakerNetworkIsolation: true` or run outside the sandbox"
            case .certificateUntrusted:
                "the server's certificate is not trusted"
            case .other:
                "the request failed"
            }
        }
    }

    /// `errSecInternalComponent`: what `SecTrustEvaluateWithError` answers when the process
    /// cannot reach the trust service, as opposed to a verdict on the certificate.
    public static let trustServiceUnavailableCode = -26276

    /// What happened.
    public var reason: Reason
    /// The underlying error's domain.
    public var domain: String
    /// The underlying error's code.
    public var code: Int
    /// The proxy the request went through, as `host:port` without credentials, if any.
    public var proxy: String?

    /// Creates a failure from its parts.
    ///
    /// - Parameters:
    ///   - reason: What happened.
    ///   - domain: The underlying error's domain.
    ///   - code: The underlying error's code.
    ///   - proxy: The proxy in use, as `host:port`, or `nil`.
    public init(reason: Reason, domain: String, code: Int, proxy: String?) {
        self.reason = reason
        self.domain = domain
        self.code = code
        self.proxy = proxy
    }

    /// Classifies an error the transport threw.
    ///
    /// Pure: the one fact that needs the system — whether a rejected certificate could be
    /// evaluated at all — comes in as `trustEvaluationCode`, which the fetcher obtains by
    /// re-evaluating the peer trust the error carries.
    ///
    /// - Parameters:
    ///   - error: The error, bridged to `NSError` for its domain and code.
    ///   - trustEvaluationCode: The code a re-evaluation of the server's trust returned,
    ///     or `nil` when there was none to re-evaluate.
    ///   - proxy: The proxy in use, as `host:port`, or `nil`.
    public init(classifying error: Error, trustEvaluationCode: Int?, proxy: String?) {
        let nsError = error as NSError
        self.init(
            reason: Self.reason(
                domain: nsError.domain, code: nsError.code,
                trustEvaluationCode: trustEvaluationCode, proxy: proxy
            ),
            domain: nsError.domain,
            code: nsError.code,
            proxy: proxy
        )
    }

    /// The URL-loading codes for a certificate the client did not accept.
    private static let certificateCodes: Set<Int> = [
        NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid,
    ]

    /// The CFNetwork codes for a proxy that could not be used: `kCFErrorHTTPProxyConnectionFailure`
    /// and `kCFErrorHTTPSProxyConnectionFailure`.
    private static let proxyConnectionCodes: Set<Int> = [306, 310]

    /// CFNetwork's `kCFErrorHTTPBadProxyCredentials`.
    private static let badProxyCredentialsCode = 307

    /// `EAUTH`, which Network.framework raises when a proxy's challenge goes unanswered.
    private static let posixAuthenticationError = 80

    /// `EPERM`, which a sandbox's socket filter raises on `connect`.
    private static let posixNotPermitted = 1

    /// `ECONNREFUSED`.
    private static let posixConnectionRefused = 61

    private static func reason(domain: String, code: Int, trustEvaluationCode: Int?, proxy: String?) -> Reason {
        switch domain {
        case NSURLErrorDomain, "kCFErrorDomainCFNetwork":
            if proxyConnectionCodes.contains(code) { return .proxyUnreachable }
            if code == badProxyCredentialsCode { return .proxyAuthenticationFailed }
            if certificateCodes.contains(code) {
                return trustEvaluationCode == trustServiceUnavailableCode
                    ? .certificateTrustUnavailable : .certificateUntrusted
            }
            switch code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .hostNotFound
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost: return .cannotConnect
            case NSURLErrorTimedOut: return .timedOut
            case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed: return .offline
            default: return .other
            }
        case NSPOSIXErrorDomain:
            switch code {
            case posixNotPermitted: return .connectionBlocked
            case posixAuthenticationError: return .proxyAuthenticationFailed
            case posixConnectionRefused: return proxy == nil ? .cannotConnect : .proxyUnreachable
            default: return .other
            }
        default:
            return .other
        }
    }

    /// The reason's explanation, the proxy if there was one, and the underlying code.
    public var description: String {
        let via = proxy.map { " (via proxy \($0))" } ?? ""
        return "\(reason.explanation)\(via) [\(domain) \(code)]"
    }
}
