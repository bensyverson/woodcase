//
//  ProxyExclusion.swift
//  Woodcase
//

import Foundation

/// One `NO_PROXY` entry: a host, domain or address block that goes direct.
///
/// Matching follows curl's reading of the variable. `*` alone excludes everything. A name
/// excludes itself and every subdomain, with a leading `.` or `*.` ignored and case
/// folded. An IP address, or a CIDR block such as `10.0.0.0/8`, excludes URLs whose host
/// *is* an address in it — never a name that might resolve into it, because resolving it
/// is exactly what a sandboxed process cannot do.
public enum ProxyExclusion: Friendly {
    /// `*`: nothing goes through the proxy.
    case everything
    /// A domain, lowercased with no leading dot, excluding itself and its subdomains.
    case domain(String)
    /// An address block: the network's bytes (4 for IPv4, 16 for IPv6) and prefix length.
    case network(address: [UInt8], prefixLength: Int)

    /// Parses one comma-separated entry of a `NO_PROXY` value.
    ///
    /// - Parameter entry: The entry, surrounding whitespace allowed.
    /// - Returns: `nil` for an empty entry.
    public init?(entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "*" {
            self = .everything
            return
        }
        if let block = Self.addressBlock(trimmed) {
            self = .network(address: block.address, prefixLength: block.prefixLength)
            return
        }
        var name = Substring(trimmed)
        if name.hasPrefix("*.") { name = name.dropFirst(2) }
        while name.hasPrefix(".") {
            name = name.dropFirst()
        }
        guard !name.isEmpty else { return nil }
        self = .domain(String(name))
    }

    /// Whether a URL host is excluded by this entry.
    ///
    /// - Parameter host: The URL's host, IPv6 brackets allowed.
    /// - Returns: `true` when the request to `host` should go direct.
    public func matches(host: String) -> Bool {
        let bare = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        switch self {
        case .everything:
            return true
        case let .domain(domain):
            return bare == domain || bare.hasSuffix("." + domain)
        case let .network(address, prefixLength):
            guard let hostBytes = Self.addressBytes(bare), hostBytes.count == address.count else {
                return false
            }
            return Self.prefix(of: hostBytes, equals: address, length: prefixLength)
        }
    }

    // MARK: - Addresses

    /// Reads `address` or `address/prefix` as an address block.
    private static func addressBlock(_ text: String) -> (address: [UInt8], prefixLength: Int)? {
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard let address = addressBytes(parts[0]) else { return nil }
        let bits = address.count * 8
        guard parts.count == 2 else { return (address, bits) }
        guard let length = Int(parts[1]), (0 ... bits).contains(length) else { return nil }
        return (address, length)
    }

    /// The bytes of an IPv4 or IPv6 literal, or `nil` for anything else.
    static func addressBytes(_ text: String) -> [UInt8]? {
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            return withUnsafeBytes(of: &v4) { Array($0) }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 {
            return withUnsafeBytes(of: &v6) { Array($0) }
        }
        return nil
    }

    /// Whether the first `length` bits of two equal-length byte strings agree.
    private static func prefix(of lhs: [UInt8], equals rhs: [UInt8], length: Int) -> Bool {
        var remaining = length
        for (left, right) in zip(lhs, rhs) where remaining > 0 {
            let bits = min(remaining, 8)
            let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - bits))
            if left & mask != right & mask { return false }
            remaining -= bits
        }
        return true
    }
}
