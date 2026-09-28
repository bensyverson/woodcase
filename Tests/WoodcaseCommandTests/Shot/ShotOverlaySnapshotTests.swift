//
//  ShotOverlaySnapshotTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing

/// Pins the bytes `shot --grid --outline` writes against a committed PNG.
///
/// The geometry tests in ``ShotCommandTests`` prove where the box and the rulers
/// *land*; what a golden adds is everything arithmetic cannot predict — the digits on
/// the ruler, the label in its tag, the two-tone ring's exact ink. Those come out of
/// PixelPeeper, so this is also the test that notices when the dependency moves under
/// us: `.package(…, branch: "main")` follows `main`, and a silent change in how the
/// overlay rasterizes would otherwise reach an agent's screenshot before it reached a
/// test.
///
/// Re-bless with `UPDATE_GOLDEN=1 swift test --filter "shot overlay snapshots"`, then
/// *look at the PNG* before committing it.
@Suite("shot overlay snapshots")
struct ShotOverlaySnapshotTests {
    /// The largest mean absolute error, on the 0–255 channel scale, that still counts
    /// as a match.
    ///
    /// Deliberately tight, and for the same reason PixelPeeper's own overlay goldens
    /// are: on a ~40,000-pixel image one wrong digit is a few dozen pixels flipped by
    /// most of the channel range, which is fractions of a unit of MAE. A tolerance
    /// sized for the renderer's own antialiasing (``PenSnapshotTests`` uses 5–8 against
    /// Pen's exports) would pin nothing here, because both sides of this comparison
    /// come out of the same rasterizer. ``theToleranceBites()`` is the proof that this
    /// number is small enough to fail on a real change.
    static let tolerance: Double = 0.05

    /// Where the golden lives — beside this file, not in the bundle, so
    /// `UPDATE_GOLDEN=1` rewrites the file that is under version control.
    static let fixtures: URL = .init(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    /// The golden's file name.
    static let goldenName = "shot-grid-outline-golden.png"

    /// Renders the annotated shot both tests work from.
    ///
    /// `Board` is 400×300 and `--max 200` shrinks it to 0.5, the only ratio other than
    /// 1 a real `shot` can reach — so the golden also pins that the ruler counts in
    /// layout points while the pixels are halved.
    ///
    /// - Parameters:
    ///   - fixture: The fixture to run against.
    ///   - outlined: The node to box.
    ///   - name: The output file's name inside the fixture's directory.
    /// - Returns: The PNG the binary wrote.
    /// - Throws: Whatever the run or the decode throws.
    private func shoot(
        _ fixture: CommandFixture,
        outlining outlined: String,
        into name: String
    ) throws -> ShotImageProbe {
        let outputPath = fixture.root.appendingPathComponent(name).path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--max", "200", "--grid", "--outline", outlined
        )
        #expect(run.status == 0)
        return try ShotImageProbe(contentsOf: outputPath)
    }

    @Test("An annotated shot matches its golden")
    func annotatedShotMatchesItsGolden() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let rendered = try shoot(fixture, outlining: "A", into: "annotated.png")

        let golden = Self.fixtures.appendingPathComponent(Self.goldenName)
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: Self.fixtures, withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: golden)
            try FileManager.default.copyItem(
                at: fixture.root.appendingPathComponent("annotated.png"),
                to: golden
            )
        }

        let reference = try ShotImageProbe(contentsOf: golden.path)
        #expect(reference.width == rendered.width)
        #expect(reference.height == rendered.height)
        #expect(rendered.meanAbsoluteError(against: reference) <= Self.tolerance)
    }

    /// A tolerance nobody has watched fail is a tolerance that pins nothing.
    ///
    /// The same shot with the box moved to the other rectangle is the same size to the
    /// pixel, so the comparison is a pure content diff — and it must score well past
    /// ``tolerance``.
    @Test(
        "The tolerance bites: boxing a different node fails the comparison",
        .enabled(
            if: ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] != "1",
            "there is nothing to compare against while the golden is being rewritten"
        )
    )
    func theToleranceBites() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let moved = try shoot(fixture, outlining: "B", into: "moved.png")

        let golden = Self.fixtures.appendingPathComponent(Self.goldenName)
        let reference = try ShotImageProbe(contentsOf: golden.path)
        #expect(reference.width == moved.width)
        #expect(moved.meanAbsoluteError(against: reference) > Self.tolerance)
    }
}
