//
//  PenDocument+FormatVersion.swift
//  Woodcase
//

import Foundation

public extension PenDocument {
    /// The declared ``version``, parsed; `nil` when it is not a `major.minor` string.
    ///
    /// A document from ``PenParser`` always has one — the gate refuses anything else —
    /// so `nil` only happens to a document built by hand.
    var formatVersion: PenFormatVersion? {
        PenFormatVersion(version)
    }

    /// Where the declared version stands against the one Woodcase models, or `nil`
    /// when ``version`` does not parse.
    var formatRelation: PenFormatVersion.Relation? {
        formatVersion?.relation()
    }

    /// Refuses a write to a document whose format this build may only read.
    ///
    /// Every writer calls this before it writes: ``PenFileTransaction`` before running
    /// a write body, ``PenFileMigrator`` before rewriting bytes. An editor that saves an
    /// ``EditableDocument`` itself should do the same.
    ///
    /// - Parameter url: The file the write would replace, for the error; `nil` for
    ///   bytes with no file behind them.
    /// - Throws: ``PenFormatWriteRefusal`` when ``formatRelation`` is read-only.
    func requireWritableFormat(at url: URL?) throws {
        guard let declared = formatVersion, declared.relation().isReadOnly else { return }
        throw PenFormatWriteRefusal(url: url, declared: declared)
    }
}
