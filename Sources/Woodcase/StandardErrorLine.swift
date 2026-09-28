//
//  StandardErrorLine.swift
//  Woodcase
//

import Foundation

/// The process's standard error, as one line-writing function.
///
/// Most of this library reports through a ``PenDiagnosticCollector`` and lets its
/// caller decide what to print. A handful of things cannot: a side effect nobody asked
/// for and nobody is collecting — an unwritable font cache, a `.gitignore` line a
/// write left behind — has to be said as it happens or not at all. Those go here.
///
/// ## Why the flush
///
/// `print` writes through C `stdio`, which is line-buffered on a terminal but **fully**
/// buffered down a pipe or into a file; this writes straight to file descriptor 2 with
/// no buffer at all. Left alone the two orders disagree, and on a shared terminal — an
/// agent's usual case, both streams to one place — a message written after a table
/// lands *inside* one of its rows. Flushing standard output first costs nothing and
/// makes the interleaving the one a reader expects, for every caller, without any of
/// them remembering.
public enum StandardErrorLine {
    /// Writes one line to standard error, flushing standard output first.
    ///
    /// - Parameter line: The message. A trailing newline is added; the text is written
    ///   verbatim otherwise.
    public static func write(_ line: String) {
        fflush(stdout)
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }
}
