//
//  PenBundle+ConvertedFrom.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// The record a bundle keeps of the bare `.pen` it was converted from, so nobody goes
    /// on editing the original as a second source of truth.
    ///
    /// Written at the bundle's root as ``fileName`` — beside `document.pen`, not in
    /// `.woodcase/`, so it is committed with the bundle and a collaborator who still has
    /// the original is warned too. The path is relative to the folder holding the
    /// bundle, so the pair can move together.
    ///
    /// ```json
    /// {"date":"2026-10-05T14:03:11Z","file":"Design.pen","revision":"9f2c…"}
    /// ```
    struct ConvertedFrom: Friendly {
        /// Records a conversion.
        ///
        /// - Parameters:
        ///   - file: The original's path, relative to the folder holding the bundle.
        ///   - revision: The original document's ``EditableDocument/documentRevision``
        ///     when it was converted.
        ///   - date: When it was converted.
        public init(file: String, revision: String, date: Date) {
            self.file = file
            self.revision = revision
            self.date = date
        }

        /// The original's path, relative to the folder holding the bundle.
        public var file: String

        /// The original document's revision when it was converted.
        public var revision: String

        /// When it was converted.
        public var date: Date

        /// The record's file name at the bundle's root.
        public static let fileName = "converted-from.json"

        /// The record a bundle holds, or `nil` when it holds none or it cannot be read.
        ///
        /// - Parameter bundle: The bundle directory.
        /// - Returns: The record.
        public static func read(in bundle: URL) -> ConvertedFrom? {
            guard let data = FileManager.default.contents(atPath: bundle.appendingPathComponent(fileName).path)
            else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(ConvertedFrom.self, from: data)
        }

        /// Writes the record into a bundle.
        ///
        /// - Parameter bundle: The bundle directory.
        /// - Throws: ``PenFileError/writeFailed(url:reason:)`` when it cannot be written.
        public func write(in bundle: URL) throws {
            let url = bundle.appendingPathComponent(Self.fileName)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            do {
                var data = try encoder.encode(self)
                data.append(0x0A)
                try data.write(to: url, options: .atomic)
            } catch {
                throw PenFileError.writeFailed(url: url, reason: PenFileError.oneLineReason(error))
            }
        }

        /// The bundles beside a bare `.pen` that were converted from it, by path.
        ///
        /// - Parameter file: The bare `.pen`.
        /// - Returns: Each bundle in the same folder whose record names `file`, with its
        ///   record, sorted by bundle name.
        public static func bundles(convertedFrom file: URL) -> [(bundle: URL, record: ConvertedFrom)] {
            let folder = file.deletingLastPathComponent()
            let wanted = file.standardizedFileURL.resolvingSymlinksInPath().path
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.sorted().compactMap { name in
                let bundle = folder.appendingPathComponent(name, isDirectory: true)
                guard PenLocation.isBundle(bundle), let record = read(in: bundle) else { return nil }
                let named = folder.appendingPathComponent(record.file).standardizedFileURL.resolvingSymlinksInPath()
                return named.path == wanted ? (bundle, record) : nil
            }
        }

        /// The warning for running on a bare `.pen` that a bundle was converted from, or
        /// `nil` when none was.
        ///
        /// "Design.pen was converted to Design.umbra on 2026-10-05; edit that instead."
        /// When the original's document has changed since, the warning says so: those
        /// edits are not in the bundle.
        ///
        /// - Parameter file: The bare `.pen` a command is about to read or write.
        /// - Returns: One warning line per bundle, joined by newlines, without a
        ///   `woodcase:` prefix.
        public static func warning(for file: URL) -> String? {
            guard PenLocation(file).kind == .file else { return nil }
            let lines = bundles(convertedFrom: file).map { bundle, record in
                var line = "\(file.lastPathComponent) was converted to \(bundle.lastPathComponent) on "
                    + "\(day(record.date)); edit that instead."
                if let current = try? EditableDocument(from: PenParser.parse(contentsOf: file)).documentRevision,
                   current != record.revision
                {
                    line += " \(file.lastPathComponent) has changed since, and those changes are not in the bundle."
                }
                return line
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }

        /// A date as its UTC calendar day, `2026-10-05`.
        private static func day(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter.string(from: date)
        }
    }
}
