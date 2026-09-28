//
//  PreviewProse.swift
//  WoodcaseViewer
//

import Elementary
import Foundation

/// A preview caption — a state's note or a component's blurb — rendered for a person.
///
/// The captions are written in the dialect of the doc comments beside them, and they
/// reached the page verbatim until this existed: four backticks and a slashed symbol
/// path where a reader wanted a name (issue `iblXjP`). This renders the small subset they
/// use, and nothing more:
///
/// - `` `code` `` is `<code>` — the mono voice DESIGN.md gives anything an agent would
///   paste, which is what almost every code span in a note is.
/// - ``` ``Symbol/member`` ```, a DocC symbol link, is `<code>` in Swift's own spelling
///   (`Symbol.member`): the page has no documentation to link it to, and the slash is
///   DocC's path separator, not the symbol's name.
/// - `*emphasis*` is `<em>`.
///
/// Everything else is text, escaped like any other. A backtick or an asterisk inside a
/// code span is code.
public struct PreviewProse: HTML {
    /// Creates the prose.
    ///
    /// - Parameter source: The caption as written.
    public init(_ source: String) {
        self.source = source
    }

    /// The caption as written.
    public let source: String

    /// One run of the caption.
    enum Run: Equatable {
        /// Plain text.
        case text(String)
        /// A code span or a symbol link.
        case code(String)
        /// An emphasised run.
        case emphasis(String)
    }

    /// The caption split into runs, in order.
    var runs: [Run] {
        let markup = /``([^`]+)``|`([^`]+)`|\*([^*\s][^*]*)\*/
        var runs: [Run] = []
        var rest = source[...]
        while let match = rest.firstMatch(of: markup) {
            if match.range.lowerBound > rest.startIndex {
                runs.append(.text(String(rest[rest.startIndex ..< match.range.lowerBound])))
            }
            if let symbol = match.output.1 {
                runs.append(.code(symbol.replacingOccurrences(of: "/", with: ".")))
            } else if let code = match.output.2 {
                runs.append(.code(String(code)))
            } else if let emphasis = match.output.3 {
                runs.append(.emphasis(String(emphasis)))
            }
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty {
            runs.append(.text(String(rest)))
        }
        return runs
    }

    public var body: some HTML {
        for run in runs {
            switch run {
            case let .text(text): text
            case let .code(text): code { text }
            case let .emphasis(text): em { text }
            }
        }
    }
}
