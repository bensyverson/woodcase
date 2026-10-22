//
//  PerfFixtureFile.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// A `.pen` file under `Tests/WoodcaseTests/Fixtures` that the budgets and benches
/// measure, found in the source tree.
///
/// Read from the source tree rather than a resource bundle so the suite and
/// `WoodcaseBench` share one copy of each file: the bench is an executable with no test
/// bundle, and copying the fixtures into this target as well would put a second
/// `woodcase-app.pen` in the repository. Both run from a checkout, so the path is there.
/// Read-only: copy a file before writing to it.
public enum PerfFixtureFile: String, Friendly, CaseIterable {
    /// The largest real fixture, a hand-authored document with components, refs,
    /// variables and two themes.
    case woodcaseApp = "woodcase-app.pen"

    /// The settings mockup Ben crashed Penumbra with (2026-10-17): wide, and eight deep.
    case settingsMockup = "settings-mockup.pen"

    /// `Tests/WoodcaseTests/Fixtures`, in the source tree.
    public static let directory: URL = testsDirectory
        .appendingPathComponent("WoodcaseTests")
        .appendingPathComponent("Fixtures")

    /// `Tests/`, in the source tree.
    public static let testsDirectory: URL = .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests")

    /// Where the file is.
    public var url: URL {
        Self.directory.appendingPathComponent(rawValue)
    }
}
