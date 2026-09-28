//
//  MAEReport.swift
//  WoodcaseTests
//

import Foundation

/// Process-wide actor that manages the MAE test report CSV.
///
/// Initializes the file with a header on first write, then appends rows.
/// Safe to call from any test suite without ordering concerns.
actor MAEReport {
    static let shared = MAEReport()

    private let url: URL = {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return projectRoot.appendingPathComponent("performance/mae-test.csv")
    }()

    private var initialized = false

    func record(id: String, mae: Double, limit: Double) {
        if !initialized {
            initialized = true
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? "id,MAE,limit\n".write(to: url, atomically: true, encoding: .utf8)
        }

        let line = "\(id),\(String(format: "%.2f", mae)),\(String(format: "%.1f", limit))\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: url)
        {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}
