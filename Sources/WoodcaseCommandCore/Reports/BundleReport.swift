//
//  BundleReport.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// What `woodcase bundle`, `unbundle` and `embed` answer with: the document written,
/// its revision, how many files came along, and what was left behind.
///
/// ```text
/// Design.umbra/document.pen
/// document  a1b2c3d4e5f60718
/// copied    4 files
/// missing   ./missing.png
/// ```
struct BundleReport: Friendly {
    /// Creates a report from the library's.
    ///
    /// - Parameters:
    ///   - report: What the conversion did.
    ///   - verb: The verb that ran, for the count's label: `copied` or `downloaded`.
    init(_ report: PenBundle.Report, verb: Verb) {
        path = report.document.path
        documentRevision = report.revision
        files = report.copied
        missing = report.missing
        self.verb = verb
    }

    /// How the files came to be in the folder.
    enum Verb: String, Friendly {
        /// Copied from disk — `bundle`, `unbundle`.
        case copied
        /// Fetched over the network — `embed`.
        case downloaded
    }

    /// The `.pen` file written.
    let path: String

    /// Its document revision, to guard the next write with.
    let documentRevision: String

    /// How many image and font files came along.
    let files: Int

    /// The references and families left as they were, because their file could not be
    /// found or fetched.
    let missing: [String]

    /// How the files came to be there.
    let verb: Verb

    /// The outline form.
    var text: String {
        var lines = [path, "document  \(documentRevision)", "\(verb.rawValue)  \(files) file\(files == 1 ? "" : "s")"]
        for reference in missing {
            lines.append("missing   \(reference)")
        }
        return lines.joined(separator: "\n")
    }

    /// The report in whichever form was asked for.
    ///
    /// - Parameter json: Whether to answer in JSON.
    /// - Returns: The text to print.
    /// - Throws: Whatever `JSONEncoder` throws.
    func rendered(json: Bool) throws -> String {
        guard json else { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }
}
