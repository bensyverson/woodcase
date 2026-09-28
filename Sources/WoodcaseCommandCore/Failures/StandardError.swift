//
//  StandardError.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The process's standard error, as one line-writing function.
///
/// Everything a verb says *about* its work goes here — refusals, warnings, the message
/// beside a non-zero exit — so stdout carries only the answer. That is what lets a
/// caller pipe `woodcase tree x.pen --json` into a parser without filtering.
///
/// The writing itself is ``Woodcase/StandardErrorLine``, which the library uses for
/// the few things it has to say on its own account — an unwritable font cache, a font
/// it had to fall back from, a `.gitignore` line a write left behind. One
/// implementation, so the flush that keeps the two streams in order (see there) cannot
/// hold on one side of the package and not the other.
enum StandardError {
    /// Writes one line, adding the newline.
    ///
    /// - Parameter line: The message. A trailing newline is added; the text is written
    ///   verbatim otherwise.
    static func write(_ line: String) {
        StandardErrorLine.write(line)
    }

    /// Writes every diagnostic a collector holds, one line each, in the order collected.
    ///
    /// A read verb passes the collector it parsed with, so what the version gate had to
    /// say — a file from a newer Pen, a different major opened read-only — reaches the
    /// reader instead of being thrown away with the parse.
    ///
    /// - Parameter diagnostics: The collector to drain. An empty one writes nothing.
    static func write(_ diagnostics: PenDiagnosticCollector) {
        for diagnostic in diagnostics.diagnostics {
            write("\(diagnostic)")
        }
    }
}
