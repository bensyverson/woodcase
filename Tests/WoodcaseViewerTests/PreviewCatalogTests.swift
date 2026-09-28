//
//  PreviewCatalogTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The golden previews, driven by ``PreviewCatalog`` rather than by literals here.
///
/// One test renders every state the catalog declares and compares it with
/// `Fixtures/golden/<component>/<state>.html`. The states themselves live beside their
/// components in `Sources/WoodcaseViewer/Components/Previews/`, so the picture a person
/// signs off on and the fixture this suite checks are one declaration.
struct PreviewCatalogTests {
    /// One component and one of its states, so a failure names the pair that broke.
    struct Subject: CustomTestStringConvertible {
        /// The component the state belongs to.
        let component: PreviewComponent

        /// The state.
        let state: PreviewState

        /// The golden's path under `Fixtures/golden`, without an extension.
        var path: String {
            "\(component.slug)/\(state.slug)"
        }

        var testDescription: String {
            path
        }
    }

    /// Every state in the catalog, flattened.
    static let subjects: [Subject] = PreviewCatalog.all.flatMap { component in
        component.states.map { Subject(component: component, state: $0) }
    }

    /// Every component that has ever had a golden, spelled out so a component cannot
    /// quietly leave the catalog and take its preview with it.
    static let componentsWithGoldens = [
        "activity-feed", "activity-row", "artboard-map", "artboard-outline",
        "artboard-overlay", "artboard-page", "artboard-row", "artboard-steps", "avatar",
        "code-pane", "dashboard-page", "details-panel", "disclosure-glyph", "empty-page",
        "export-panel", "file-card", "file-empty-page", "file-list", "follow-picker",
        "id-chip", "keyboard-hint", "kind-mark", "live-badge", "map-page",
        "outline-panel", "outline-row", "pane-grip", "presence-stack",
        "presentation-hint", "render-region", "right-pane", "selection-bar",
        "theme-picker", "top-bar", "variables-panel",
    ]

    /// The files in `Components/` that declare no component, and why each one is there.
    ///
    /// Spelled out one by one rather than derived, so adding a file to that directory
    /// is a decision: either it renders and it earns a preview, or it is listed here
    /// with a reason a reader can disagree with.
    static let notComponents: [String: String] = [
        "ActorColor.swift": "a hashed colour, not markup — it is what an avatar is drawn in",
        "ConnectionState.swift": "the fact a live badge renders; the badge has the previews",
        "EditMarker.swift": "a model derived from the log; ArtboardOverlay draws it, and previews it",
        "Follow.swift": "view state; FollowPicker renders it and has the previews",
        "NodeDetail.swift": "one row of a model; DetailsPanel renders it and has the previews",
        "NodeDetails.swift": "the model behind Details; DetailsPanel renders it and has the previews",
        "RelativeAge.swift": "a formatter producing a string, not markup — its boundaries show in the file cards",
        "ViewState.swift": "the query, parsed; every component takes it and none is it",
        "ViewerClock.swift": "the moment a page renders at",
        "ViewerCodeTarget.swift": "an emitter target; CodePane and ExportPanel offer it",
        "ViewerExportFormat.swift": "an export format; ExportPanel offers it",
        "ViewerLink.swift": "the URL builder every link goes through",
        "ViewerTab.swift": "which panel the right pane shows; RightPane renders it",
        "ViewerVariable.swift": "a resolved variable; VariablesPanel renders it",
    ]

    /// Every file under `Components/` that declares a type conforming to `HTML`, paired
    /// with the source path a catalog entry would have to name.
    ///
    /// Read off disk rather than listed, so a component added tomorrow is caught the
    /// day it lands rather than the day someone remembers this file.
    static var componentFiles: [(file: String, source: String)] {
        let directory = repository
            .appendingPathComponent("Sources/WoodcaseViewer/Components")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let declaration = /public struct \w+: HTML \{/
        return names.filter { $0.hasSuffix(".swift") }.sorted().compactMap { name in
            let text = (try? String(
                contentsOf: directory.appendingPathComponent(name), encoding: .utf8
            )) ?? ""
            guard text.firstMatch(of: declaration) != nil else { return nil }
            return (name, "Sources/WoodcaseViewer/Components/\(name)")
        }
    }

    /// The repository's root, reached from this file.
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("Preview: every state renders what its golden holds", arguments: subjects)
    func stateMatchesItsGolden(subject: Subject) throws {
        try ViewerGolden.check(rendered: subject.state.renderFormatted(), named: subject.path)
    }

    @Test("A component slug names one component and one only")
    func componentSlugsAreUnique() {
        let slugs = PreviewCatalog.all.map(\.slug)
        #expect(Set(slugs).count == slugs.count, "duplicate component slug in the catalog")
    }

    @Test("A state slug names one state within its component")
    func stateSlugsAreUniquePerComponent() {
        for component in PreviewCatalog.all {
            let slugs = component.states.map(\.slug)
            #expect(
                Set(slugs).count == slugs.count,
                "duplicate state slug in \(component.slug)"
            )
        }
    }

    @Test("Every slug is a URL segment: lowercase letters, digits and hyphens")
    func slugsAreURLSegments() {
        let segment = /^[a-z0-9]+(-[a-z0-9]+)*$/
        for component in PreviewCatalog.all {
            #expect(component.slug.wholeMatch(of: segment) != nil, "\(component.slug)")
            for state in component.states {
                #expect(
                    state.slug.wholeMatch(of: segment) != nil,
                    "\(component.slug)/\(state.slug)"
                )
            }
        }
    }

    @Test("Every state carries a note, because a picture with no caption teaches nothing")
    func everyStateHasANote() {
        for component in PreviewCatalog.all {
            for state in component.states {
                #expect(!state.note.isEmpty, "\(component.slug)/\(state.slug) has no note")
                #expect(!state.name.isEmpty, "\(component.slug)/\(state.slug) has no name")
            }
        }
    }

    @Test("Every component says which file to open, and the file is there")
    func everySourcePathExists() {
        for component in PreviewCatalog.all {
            let url = Self.repository.appendingPathComponent(component.source)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "\(component.slug) names \(component.source), which is not in the repository"
            )
            #expect(!component.title.isEmpty, "\(component.slug) has no title")
            #expect(!component.blurb.isEmpty, "\(component.slug) has no blurb")
        }
    }

    @Test("Every component that had a golden is still in the catalog")
    func nothingLostItsPreview() {
        let slugs = Set(PreviewCatalog.all.map(\.slug))
        for expected in Self.componentsWithGoldens {
            #expect(slugs.contains(expected), "\(expected) has no catalog entry")
        }
    }

    @Test("Every component that renders has a catalog entry")
    func everyRenderingComponentIsPreviewed() {
        let sources = Set(PreviewCatalog.all.map(\.source))
        for component in Self.componentFiles {
            let previews = component.file.replacingOccurrences(
                of: ".swift", with: "+Previews.swift"
            )
            #expect(
                sources.contains(component.source),
                "\(component.file) declares an HTML component with no catalog entry: add Components/Previews/\(previews) and register it in PreviewCatalog.all"
            )
        }
    }

    @Test("A file in Components/ that is not previewed is one this test excuses by name")
    func everyExclusionIsStillThereAndStillNotAComponent() {
        let directory = Self.repository
            .appendingPathComponent("Sources/WoodcaseViewer/Components")
        let previewed = Set(Self.componentFiles.map(\.file))
        for (file, reason) in Self.notComponents {
            #expect(
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent(file).path
                ),
                "\(file) is excused from previews (\(reason)) but is no longer in Components/"
            )
            #expect(
                !previewed.contains(file),
                "\(file) is excused from previews (\(reason)) but now declares an HTML component"
            )
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let accounted = previewed.union(Self.notComponents.keys)
        for name in names where name.hasSuffix(".swift") {
            #expect(
                accounted.contains(name),
                "\(name) is neither an HTML component nor listed in notComponents with a reason"
            )
        }
    }

    @Test("Lookup finds a component and a state by slug, and nothing else")
    func lookupBySlug() throws {
        let avatar = try #require(PreviewCatalog.component(slug: "avatar"))
        #expect(avatar.states.count == 4)
        #expect(PreviewCatalog.component(slug: "nope") == nil)

        let small = try #require(PreviewCatalog.state(component: "avatar", slug: "small"))
        #expect(small.name.isEmpty == false)
        #expect(PreviewCatalog.state(component: "avatar", slug: "nope") == nil)
        #expect(PreviewCatalog.state(component: "nope", slug: "small") == nil)
    }
}
