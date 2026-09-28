//
//  RightPanePreviewTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// How the right pane arranges its tabs. The panels behind them are previewed by the
/// catalog; what this suite tests is which tab is offered, and when.
struct RightPanePreviewTests {
    /// The right pane showing the Code tab, which is where the generated file lives now.
    private func pane(state: ViewState) -> RightPane {
        RightPane(
            file: "a1b2c3d4e5f6",
            artboard: Artboard(id: "Cnv01", name: "Canvas", width: 400, height: 300),
            details: nil,
            targets: ViewerCodeTarget.allCases,
            code: ArtboardCode(
                target: .react,
                path: "pages/Canvas.tsx",
                text: "export function Canvas() {\n  return <div />;\n}\n"
            ),
            events: [],
            state: state,
            clock: PreviewFixtures.clock
        )
    }

    @Test("Code is a tab beside Details and Export, not a switch beside them")
    func codeIsAFourthTab() {
        let html = pane(state: ViewState()).render()
        #expect(html.contains("data-tab=\"code\""))
        #expect(html.contains(">Code</a>"))
        // The split view's switch is gone: the pane it opened is this tab.
        #expect(!html.contains("v-code-toggle"))
        #expect(!html.contains("v-code-close"))
    }

    @Test("The Code pane is rendered on every artboard page, picker and all")
    func codePaneShipsWithThePage() {
        let html = pane(state: ViewState()).render()
        #expect(html.contains("<div class=\"v-pane\" data-pane=\"code\">"))
        #expect(html.contains("id=\"v-code\""))
        #expect(html.contains("class=\"v-code-lang\""))
    }

    @Test("Asking for the Code tab shows it — one attribute, as with every other tab")
    func codeTabShows() {
        let html = pane(state: ViewState(tab: .code)).render()
        #expect(html.contains("<aside class=\"v-side v-side-right\" id=\"v-right\" data-tab=\"code\">"))
    }

    @Test("The map page has no Code tab, because it has no artboard to generate one for")
    func theMapHasNoCodeTab() {
        let html = RightPane(
            file: "a1b2c3d4e5f6",
            artboard: nil,
            details: nil,
            targets: [],
            code: nil,
            events: [],
            state: ViewState(),
            clock: PreviewFixtures.clock
        ).render()
        #expect(!html.contains(">Code</a>"))
        #expect(!html.contains("id=\"v-code\""))
    }
}

/// The view state the right pane, the code pane and the export form are driven by.
struct RightPaneStateTests {
    @Test("Selecting a node moves the right pane to Details, and clearing it moves back")
    func selectionPicksTheTab() {
        let selected = ViewState().selecting("Ttl01")
        #expect(selected.tab == .details)
        #expect(selected.query == "?node=Ttl01&tab=details")

        let cleared = selected.selecting(nil)
        #expect(cleared.tab == .activity)
        #expect(cleared.query == "")
    }

    @Test("With a node selected every tab link names its tab, Activity included")
    func activityTabLinkIsExplicit() {
        // Without this the Activity tab's own href would be `?node=…` with no tab,
        // which parses back to Details — a tab that cannot be clicked.
        let selected = ViewState().selecting("Ttl01")
        #expect(selected.showing(.activity).query == "?node=Ttl01&tab=activity")
        #expect(selected.showing(.export).query == "?node=Ttl01&tab=export")
        #expect(ViewState().showing(.export).query == "?tab=export")
    }

    @Test("A default state writes no tab and no lang")
    func defaultsAreSilent() {
        #expect(ViewState().query == "")
        #expect(ViewState().tab == .activity)
        #expect(ViewState().lang == nil)
    }

    @Test("Code is the right pane's fourth tab, and its language rides beside it")
    func codeStateRoundTrips() {
        #expect(ViewerTab.allCases == [.activity, .details, .export, .code])
        #expect(ViewerTab.code.label == "Code")
        let state = ViewState(tab: .code, lang: .themeCSS)
        #expect(state.query == "?tab=code&lang=theme-css")
    }

    @Test("Every export format spells itself the way the query carries it")
    func exportFormatsRoundTrip() {
        for format in ViewerExportFormat.allCases {
            #expect(ViewerExportFormat(query: format.query) == format)
        }
        #expect(ViewerExportFormat(query: "png") == .png)
        #expect(ViewerExportFormat(query: "pdf") == .pdf)
        #expect(ViewerExportFormat(query: "react") == .code(.react))
        #expect(ViewerExportFormat(query: "svg") == nil)
    }

    @Test("The export link carries the format, the size and the theme")
    func exportLink() {
        let link = ViewerLink.export(
            file: "a1",
            artboard: "YGJ0d/nSNTs",
            format: .png,
            scale: 2,
            state: ViewState(theme: ["mode": "dark"])
        )
        #expect(link == "/files/a1/artboards/YGJ0d%2FnSNTs/export?format=png&scale=2&theme=mode%3Adark")
    }

    @Test("The code fragment link carries the language")
    func codeLink() {
        #expect(
            ViewerLink.code(file: "a1", artboard: "Cnv01", state: ViewState(tab: .code, lang: .manifest))
                == "/files/a1/artboards/Cnv01/code?tab=code&lang=manifest"
        )
    }

    @Test("The details fragment replaces the element the tab bar shows")
    func detailsFragmentTarget() {
        #expect(ViewerLink.Fragment.details.target == "v-details")
        #expect(ViewerLink.Fragment.code.target == "v-code")
        #expect(
            ViewerLink.fragment(.details, file: "a1", state: ViewState().selecting("Ttl01"))
                == "/files/a1/details?node=Ttl01&tab=details"
        )
    }

    @Test("The Export and Code panels set commands as code, never as Markdown backticks (MwBN6D)",
          arguments: ["export-panel/default", "code-pane/empty"])
    func panelProseHasNoBackticks(path: String) throws {
        let parts = path.split(separator: "/").map(String.init)
        let component = try #require(PreviewCatalog.component(slug: parts[0]))
        let html = try #require(component.state(slug: parts[1])).render()
        #expect(!html.contains("`"))
        #expect(html.contains("<code>"))
    }
}
