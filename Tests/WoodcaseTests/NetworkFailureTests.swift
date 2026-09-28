//
//  NetworkFailureTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// Turning what the transport threw into a reason a reader can act on.
///
/// The codes here are the ones observed in the Claude Code Bash sandbox on 2026-09-26
/// (see project/2026-09-26-sandbox-font-downloads.md), plus their ordinary neighbours.
@Suite("Network failure classification")
struct NetworkFailureTests {
    /// errSecInternalComponent: what `SecTrustEvaluateWithError` answers when the process
    /// cannot reach `com.apple.trustd.agent`.
    static let errSecInternalComponent = -26276

    @Test("URL-loading codes map to their reasons", arguments: [
        (NSURLErrorCannotFindHost, NetworkFailure.Reason.hostNotFound),
        (NSURLErrorDNSLookupFailed, .hostNotFound),
        (NSURLErrorCannotConnectToHost, .cannotConnect),
        (NSURLErrorNetworkConnectionLost, .cannotConnect),
        (NSURLErrorTimedOut, .timedOut),
        (NSURLErrorNotConnectedToInternet, .offline),
        (NSURLErrorServerCertificateUntrusted, .certificateUntrusted),
        (NSURLErrorServerCertificateHasUnknownRoot, .certificateUntrusted),
        (NSURLErrorBadServerResponse, .other),
    ])
    func urlErrorCodes(code: Int, reason: NetworkFailure.Reason) {
        let error = NSError(domain: NSURLErrorDomain, code: code)
        #expect(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: nil).reason == reason)
    }

    @Test("An untrusted certificate whose re-check cannot reach trustd is the trust service, not the server")
    func trustServiceUnavailable() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        let failure = NetworkFailure(
            classifying: error, trustEvaluationCode: Self.errSecInternalComponent, proxy: "127.0.0.1:3128"
        )
        #expect(failure.reason == .certificateTrustUnavailable)
    }

    @Test("CFNetwork's proxy codes name the proxy", arguments: [
        (306, NetworkFailure.Reason.proxyUnreachable),
        (310, .proxyUnreachable),
        (307, .proxyAuthenticationFailed),
    ])
    func cfNetworkProxyCodes(code: Int, reason: NetworkFailure.Reason) {
        let error = NSError(domain: "kCFErrorDomainCFNetwork", code: code)
        #expect(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: "p:1").reason == reason)
    }

    @Test("EAUTH from the socket layer is a refused proxy login")
    func posixAuthenticationError() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 80)
        #expect(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: "p:1").reason
            == .proxyAuthenticationFailed)
    }

    @Test("EPERM from the socket layer is a connection a sandbox or firewall blocked")
    func posixNotPermitted() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 1)
        #expect(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: nil).reason == .connectionBlocked)
    }

    @Test("A refused connection is the proxy's fault when one was in use")
    func refusedConnection() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 61)
        #expect(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: "p:1").reason == .proxyUnreachable)
        #expect(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: nil).reason == .cannotConnect)
    }

    @Test("The failure keeps the underlying domain and code")
    func keepsUnderlyingCode() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let failure = NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: nil)
        #expect(failure.domain == NSURLErrorDomain)
        #expect(failure.code == NSURLErrorTimedOut)
    }

    @Test("Every reason explains itself, and the trust case names the sandbox setting")
    func descriptions() {
        for reason in NetworkFailure.Reason.allCases {
            let failure = NetworkFailure(reason: reason, domain: "d", code: 1, proxy: nil)
            #expect(!failure.description.isEmpty)
            #expect(failure.description.contains("d 1"), "\(reason) hides the underlying code")
        }
        let trust = NetworkFailure(reason: .certificateTrustUnavailable, domain: "d", code: 1, proxy: nil)
        #expect(trust.description.contains("com.apple.trustd.agent"))
        #expect(trust.description.contains("enableWeakerNetworkIsolation"))
    }

    @Test("A failure through a proxy names it without credentials")
    func namesProxy() {
        let failure = NetworkFailure(reason: .proxyUnreachable, domain: "d", code: 1, proxy: "127.0.0.1:3128")
        #expect(failure.description.contains("127.0.0.1:3128"))
    }
}
