//
//  PenSizing.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Sizing behavior for a .pen node's width or height.
///
/// In the .pen format, dimensions can be:
/// - A fixed number (e.g. `200`)
/// - `"fit_content"` — auto-size to children (with optional fallback: `"fit_content(200)"`)
/// - `"fill_container"` — match parent size (with optional fallback: `"fill_container(300)"`)
/// - A variable reference (e.g. `"$spacing.large"`)
public enum PenSizing: Friendly {
    /// A fixed pixel value.
    case fixed(Double)
    /// Size to fit children. Fallback used when there are no children.
    case fitContent(fallback: Double?)
    /// Fill the parent container. Fallback used when parent has no layout.
    case fillContainer(fallback: Double?)
    /// A variable reference (without `$` prefix).
    case variable(String)

    /// Whether this sizing mode sizes to content.
    public var isFitContent: Bool {
        if case .fitContent = self { return true }
        return false
    }

    /// The fixed pixel value, or `nil` if this is not a fixed sizing.
    public var fixedValue: Double? {
        if case let .fixed(v) = self { return v }
        return nil
    }
}

// MARK: - Codable

extension PenSizing {
    private nonisolated(unsafe) static let sizingPattern = /^(fit_content|fill_container)(?:\((\d+(?:\.\d+)?)\))?$/

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Double.self) {
            self = .fixed(number)
            return
        }

        let string = try container.decode(String.self)

        if string.hasPrefix("$") {
            self = .variable(String(string.dropFirst()))
            return
        }

        if let match = string.wholeMatch(of: PenSizing.sizingPattern) {
            let keyword = String(match.1)
            let fallback: Double? = if let fallbackStr = match.2 {
                Double(String(fallbackStr))
            } else {
                nil
            }

            if keyword == "fit_content" {
                self = .fitContent(fallback: fallback)
            } else {
                self = .fillContainer(fallback: fallback)
            }
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid PenSizing value: \(string)"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .fixed(value):
            try container.encode(value)
        case let .fitContent(fallback):
            if let fallback {
                try container.encode("fit_content(\(Self.formatNumber(fallback)))")
            } else {
                try container.encode("fit_content")
            }
        case let .fillContainer(fallback):
            if let fallback {
                try container.encode("fill_container(\(Self.formatNumber(fallback)))")
            } else {
                try container.encode("fill_container")
            }
        case let .variable(name):
            try container.encode("$\(name)")
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), !value.isInfinite {
            return String(Int(value))
        }
        return String(value)
    }
}
