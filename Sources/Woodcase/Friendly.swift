//
//  Friendly.swift
//  Woodcase
//

/// A convenience typealias combining the most commonly useful protocol conformances.
///
/// Types conforming to `Friendly` can be serialized, compared, hashed, and safely
/// shared across concurrency boundaries.
public typealias Friendly = Codable & Equatable & Hashable & Sendable
