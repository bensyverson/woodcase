//
//  Route.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One method and one path pattern.
///
/// A pattern is path segments separated by `/`. A segment is either a literal, or a
/// named parameter in braces — optionally followed by a literal suffix, which is how
/// the format rides on the path:
///
/// ```text
/// /files/{file}/tree.json
/// /files/{file}/artboards/{artboard}.png
/// ```
///
/// There is no wildcard and no optional segment. A viewer route either names exactly
/// what it serves or it is a different route; a pattern language with more in it would
/// make two routes silently overlap.
public struct Route: Friendly {
    /// Creates a route.
    ///
    /// - Parameters:
    ///   - method: The method this route answers.
    ///   - pattern: The path pattern, beginning with `/`.
    public init(_ method: HTTPRequest.Method, _ pattern: String) {
        self.method = method
        self.pattern = pattern
        let segments = Self.segments(of: pattern)
        self.segments = segments
        specificity = Specificity(segments: segments)
    }

    /// One piece of a pattern, between two slashes.
    enum Segment: Friendly {
        /// Matches this text exactly.
        case literal(String)
        /// Captures the segment under `name`, requiring it to end with `suffix`
        /// (empty when the parameter is the whole segment).
        case parameter(name: String, suffix: String)
    }

    /// The method this route answers.
    public let method: HTTPRequest.Method

    /// The path pattern, as written.
    public let pattern: String

    /// The pattern, parsed once at construction.
    let segments: [Segment]

    /// How narrowly this pattern claims a path, measured once at construction.
    ///
    /// ``ViewerRoutes`` matches the most specific route first, so this is the field that
    /// decides between two routes that both match — see ``Specificity``.
    public let specificity: Specificity

    /// Matches a path against this route's pattern.
    ///
    /// - Parameter path: A path with no percent-encoding in it.
    /// - Returns: The captured parameters, or `nil` if the path does not match.
    public func match(path: String) -> [String: String]? {
        match(segments: Self.parts(of: path))
    }

    /// Matches already-decoded path segments against this route's pattern.
    ///
    /// This is the form the server uses: ``HTTPRequest/segments`` are decoded one by
    /// one, so a captured parameter may itself contain a slash.
    ///
    /// - Parameter parts: The request's decoded path segments.
    /// - Returns: The captured parameters — empty for an all-literal pattern — or `nil`
    ///   if the path does not match.
    public func match(segments parts: [String]) -> [String: String]? {
        guard parts.count == segments.count else { return nil }

        var captured: [String: String] = [:]
        for (segment, part) in zip(segments, parts) {
            switch segment {
            case let .literal(text):
                guard part == text else { return nil }
            case let .parameter(name, suffix):
                guard part.hasSuffix(suffix) else { return nil }
                let value = String(part.dropLast(suffix.count))
                guard !value.isEmpty else { return nil }
                captured[name] = value
            }
        }
        return captured
    }

    /// How narrowly a pattern claims a path.
    ///
    /// A route table can hold two patterns that both match one path —
    /// `/files/{file}/artboards/{artboard}` and `/files/{file}/artboards/{artboard}.png`
    /// both match `…/Cnv01.png`. The one that says more about the path should answer, so
    /// specificity is compared segment by segment, left to right, and the first segment
    /// that differs decides: a literal says the most, a capture with a literal suffix
    /// less, a bare capture least. A pattern with more literals further right does not
    /// overtake one that is narrower earlier.
    ///
    /// Two patterns of the same shape are equal, which leaves ``ViewerRoutes`` free to
    /// break the tie by registration order.
    public struct Specificity: Friendly, Comparable {
        /// How narrowly one segment claims its part of the path.
        ///
        /// The order of the cases *is* the ranking; `rawValue` is only its number.
        public enum Rank: Int, Friendly, Comparable {
            /// `{name}` — anything non-empty.
            case capture = 0
            /// `{name}.png` — anything non-empty ending in a literal suffix.
            case suffixedCapture = 1
            /// `tree.json` — exactly this text.
            case literal = 2

            public static func < (lhs: Rank, rhs: Rank) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        /// Measures a parsed pattern.
        ///
        /// - Parameter segments: The pattern's segments, in order.
        init(segments: [Segment]) {
            ranks = segments.map { segment in
                switch segment {
                case .literal: .literal
                case let .parameter(_, suffix): suffix.isEmpty ? .capture : .suffixedCapture
                }
            }
        }

        /// One rank per segment, left to right.
        let ranks: [Rank]

        public static func < (lhs: Specificity, rhs: Specificity) -> Bool {
            for (left, right) in zip(lhs.ranks, rhs.ranks) where left != right {
                return left < right
            }
            // Patterns of different lengths never match the same path; ordering them by
            // length only keeps the comparison total.
            return lhs.ranks.count < rhs.ranks.count
        }
    }

    // MARK: - Parsing

    /// The non-empty segments of a path, so `/files` and `/files/` are one path.
    private static func parts(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// Parses a pattern into segments.
    private static func segments(of pattern: String) -> [Segment] {
        parts(of: pattern).map { part in
            guard part.hasPrefix("{"), let close = part.firstIndex(of: "}") else {
                return .literal(part)
            }
            let name = String(part[part.index(after: part.startIndex) ..< close])
            let suffix = String(part[part.index(after: close)...])
            return .parameter(name: name, suffix: suffix)
        }
    }
}

extension Route: CustomStringConvertible {
    public var description: String {
        "\(method.rawValue) \(pattern)"
    }
}
