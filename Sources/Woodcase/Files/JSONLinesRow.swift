//
//  JSONLinesRow.swift
//  Woodcase
//

import Foundation

/// A value one line of a ``JSONLinesFile`` decodes to: an ``ActivityEvent`` or a
/// ``ViewEvent``.
protocol JSONLinesRow: Sendable {
    /// Reads a row back from one line of JSON.
    ///
    /// - Parameters:
    ///   - line: The line's bytes, without its newline.
    ///   - decoder: A decoder to reuse across lines.
    /// - Throws: `DecodingError` if the line is not a row of this kind; the reader
    ///   counts it as skipped and steps over it.
    init(line: Data, using decoder: JSONDecoder) throws
}

extension ActivityEvent: JSONLinesRow {}
