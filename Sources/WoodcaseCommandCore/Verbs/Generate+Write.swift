//
//  Generate+Write.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

extension Generate {
    /// Write generated files under `directory`, creating folders as needed and leaving a
    /// ``GeneratedFile/WritePolicy/scaffoldOnce`` file alone when it already exists.
    ///
    /// - Returns: How many files were written.
    /// - Throws: Whatever `FileManager` and the write throw.
    @discardableResult
    static func write(_ files: [GeneratedFile], to directory: URL) throws -> Int {
        let fileManager = FileManager.default
        var written = 0
        for file in files {
            let fileURL = directory.appendingPathComponent(file.path)
            if file.writePolicy == .scaffoldOnce, fileManager.fileExists(atPath: fileURL.path) {
                continue
            }
            let folder = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: folder.path) {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
            written += 1
        }
        return written
    }
}
