//
//  PenFormatWriteRefusal.swift
//  Woodcase
//

import Foundation

/// A write refused because the document declares a format version this build may
/// read but not write — another major version.
///
/// Reading such a file is a best effort through the 2.x model; writing it back would
/// stamp that model over a schema this build does not know, silently dropping or
/// reshaping whatever changed. So ``PenFileTransaction`` and ``PenFileMigrator`` refuse
/// before anything is written, and the file is left exactly as it was.
///
/// The message says what and why; what to *do* depends on where the reader stands, so
/// the command line adds its own next step.
public struct PenFormatWriteRefusal: Error, Friendly, CustomStringConvertible {
    /// Creates a refusal.
    ///
    /// - Parameters:
    ///   - url: The file the write would have replaced, or `nil` for bytes with no file.
    ///   - declared: The version the document declares.
    public init(url: URL?, declared: PenFormatVersion) {
        self.url = url
        self.declared = declared
    }

    /// The file the write would have replaced, or `nil` for bytes with no file.
    public let url: URL?

    /// The version the document declares.
    public let declared: PenFormatVersion

    /// One line naming the file, the two versions and the fact that it is read-only.
    public var description: String {
        "Cannot write \(url?.path ?? "the .pen input"): it declares .pen format \(declared), "
            + "a different major version from the \(PenFormatVersion.current) this build models, "
            + "so it is read-only"
    }
}
