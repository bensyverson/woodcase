//
//  InstanceReportFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// Renders an ``InstanceReport`` as the text `woodcase get --instances` prints.
///
/// The header line is exactly the one a plain `woodcase get` prints for the same node
/// — id, name path, revision — with the count on the end, so a reader who knows one
/// verb reads the other. The instances follow as rows in the shape `woodcase tree`
/// uses: columns padded to the widest cell, joined by two spaces, no line ending in a
/// space, so the output is byte-stable and `awk`-able.
///
/// ```text
/// Cmp01  Chip  rev 3f2a19c0be47d581  3 instances
/// Board/Zeta     Zta01  rev 6b1d0a94f2c37e58
/// Board/Alpha    Alp01  rev 6b1d0a94f2c37e58
/// Second/Middle  Mid01  rev c07e5b3319aa8f42
/// ```
enum InstanceReportFormatter {
    /// Renders the report as text.
    ///
    /// - Parameter report: The definition and its instances.
    /// - Returns: The whole of stdout, with no trailing newline. A definition nothing
    ///   points at is the header line alone, ending `no instances` — never a blank
    ///   answer a reader could mistake for a failed read.
    static func text(_ report: InstanceReport) -> String {
        let definition = report.definition
        let header = "\(definition.id)  \(definition.address)  rev \(definition.rev)  \(count(report))"
        guard !report.instances.isEmpty else { return header }

        let width = report.instances.map(\.address.count).max() ?? 0
        let rows = report.instances.map { instance in
            let padding = String(repeating: " ", count: max(0, width - instance.address.count))
            return "\(instance.address)\(padding)  \(instance.id)  rev \(instance.rev)"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Renders the report as the `--json` object.
    ///
    /// - Parameter report: The definition and its instances.
    /// - Returns: The canonical JSON text.
    /// - Throws: Whatever the JSON encoder throws.
    static func json(_ report: InstanceReport) throws -> String {
        try CanonicalJSON.text(report)
    }

    /// `no instances`, `1 instance` or `N instances`.
    private static func count(_ report: InstanceReport) -> String {
        switch report.instances.count {
        case 0: "no instances"
        case 1: "1 instance"
        case let many: "\(many) instances"
        }
    }
}
