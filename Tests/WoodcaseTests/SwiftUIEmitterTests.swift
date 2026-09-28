//
//  SwiftUIEmitterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The shape of what ``SwiftUIEmitter`` writes: the package layout, the deployment floor
/// and the support file. What a node becomes is ``SwiftUIEmitterNodeTests``.
struct SwiftUIEmitterTests {
    // MARK: - Options

    @Test("The default floor is iOS 26 / macOS 26")
    func defaultFloor() {
        #expect(SwiftUIEmitter.Options().deploymentFloor == .iOS26)
        #expect(SwiftUIEmitter.DeploymentFloor.iOS26.iOSVersion == "26.0")
        #expect(SwiftUIEmitter.DeploymentFloor.iOS26.macOSVersion == "26.0")
        #expect(SwiftUIEmitter.DeploymentFloor.iOS18.iOSVersion == "18.0")
        #expect(SwiftUIEmitter.DeploymentFloor.iOS18.macOSVersion == "15.0")
    }

    @Test("The default module is PenUI")
    func defaultModule() {
        #expect(SwiftUIEmitter.Options().moduleName == "PenUI")
    }

    // MARK: - Package layout

    @Test("A page lands under Sources/<Module>/Pages, the support file under Support")
    func packageLayout() throws {
        let options = SwiftUIEmitter.Options(moduleName: "Acme")
        let paths = try SwiftUIFixtures.emit("layout-nested", options: options).files.map(\.path).sorted()
        // The catalog's files are pinned by SwiftUIEmitterCatalogTests.
        let views = paths.filter { !$0.contains("/Support/") && !$0.contains("Catalog/") }
        // Resources/ is always written, so the directory Package.swift declares exists.
        #expect(views == ["Package.swift", "Sources/Acme/Pages/LayoutNested.swift", "Sources/Acme/Resources/.gitkeep"])
        // Every template, one file per concern; PenSupport.swift is always among them.
        let support = try SwiftUIEmitter.supportTemplates().keys.sorted().map { "Sources/Acme/Support/\($0)" }
        #expect(paths.filter { $0.contains("/Support/") } == support)
        #expect(support.contains("Sources/Acme/Support/PenSupport.swift"))
    }

    @Test("Package.swift names the module and the floor's platforms, and follows them on every run")
    func manifestCarriesTheFloor() throws {
        let modern = try manifest(.iOS26)
        #expect(modern.content.contains(#"name: "PenUI""#))
        #expect(modern.content.contains(#".iOS("26.0")"#))
        #expect(modern.content.contains(#".macOS("26.0")"#))
        #expect(modern.writePolicy == .always)

        let lower = try manifest(.iOS18)
        #expect(lower.content.contains(#".iOS("18.0")"#))
        #expect(lower.content.contains(#".macOS("15.0")"#))
    }

    @Test("Page code is identical at every floor: only the manifest moves")
    func pageCodeIgnoresTheFloor() throws {
        for fixture in ["layout-nested", "render-text"] {
            let modern = try SwiftUIFixtures.page(fixture, options: .init(deploymentFloor: .iOS26))
            let lower = try SwiftUIFixtures.page(fixture, options: .init(deploymentFloor: .iOS18))
            #expect(modern == lower)
        }
    }

    // MARK: - Support file

    @Test("Every bundled support template is emitted verbatim under Support, in name order")
    func supportFilesAreTheTemplates() throws {
        let emitted = try SwiftUIFixtures.emit("render-text").files.filter { $0.path.contains("/Support/") }
        let names = emitted.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        #expect(try names == SwiftUIEmitter.supportTemplates().keys.sorted())
        for file in emitted {
            let name = URL(fileURLWithPath: file.path).lastPathComponent
            #expect(try file.content == SwiftUIEmitter.supportTemplates()[name], "\(name) is not its template")
        }
    }

    @Test("PenSupport.swift holds the availability branches and the font face")
    func penSupportHoldsTheBranches() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates()["PenSupport.swift"])
        #expect(support.contains("import SwiftUI"))
        #expect(support.contains("#available(iOS 26, macOS 26, *)"))
        #expect(support.contains("kCTFontOpticalSizeAttribute"))
    }

    @Test("A page opens with a header naming its frame, imports SwiftUI, and is public")
    func pageHeader() throws {
        let page = try SwiftUIFixtures.page("layout-nested")
        #expect(page.content.contains("import SwiftUI\n"))
        #expect(page.content.contains("public struct LayoutNested: View {"))
        #expect(page.content.contains("public init() {}"))
        #expect(page.content.contains("public var body: some View {"))
        #expect(page.content.contains("#Preview {"))
        #expect(page.content.contains(#""layout-nested""#))
    }

    // MARK: - Helpers

    private func manifest(_ floor: SwiftUIEmitter.DeploymentFloor) throws -> GeneratedFile {
        try #require(
            SwiftUIFixtures.emit("layout-nested", options: .init(deploymentFloor: floor))
                .files.first { $0.path == "Package.swift" }
        )
    }
}
