//
//  OutlinePreviewTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// How the outline panel and the variables section behave. Their pictures are in the preview catalog.
struct OutlinePreviewTests {
    private let file = "a1b2c3d4e5f6"

    @Test("A row is a link that carries the rest of the view state forward")
    func rowKeepsState() {
        let state = ViewState(theme: ["Mode": "Dark"])
        let html = OutlineRow(row: PreviewFixtures.row(id: "Ttl01", name: "Title"), file: file, artboard: "Cnv01", state: state).render()
        // `tab=details` rides along because selecting a node is what the Details
        // pane is for — see ``ViewState/selecting(_:)``. The link names the artboard on
        // screen: `/files/{id}?node=…` is the map, and a row that wrote it would
        // navigate out of the artboard it was clicked in.
        #expect(html.contains(
            "href=\"/files/a1b2c3d4e5f6/artboards/Cnv01"
                + "?node=Ttl01&amp;theme=Mode%3ADark&amp;tab=details\""
        ))
    }

    @Test("Clicking the selected row deselects it")
    func selectedRowDeselects() {
        let state = ViewState(node: "Ttl01")
        let row = OutlineRow(row: PreviewFixtures.row(id: "Ttl01", name: "Title"), file: file, artboard: "Cnv01", state: state)
        #expect(row.isSelected)
        #expect(row.render().contains("href=\"/files/a1b2c3d4e5f6/artboards/Cnv01\""))
        #expect(row.render().contains("is-selected"))
    }

    @Test("A name path selects the same row an id does")
    func addressSelectsToo() {
        let row = PreviewFixtures.row(id: "Ttl01", address: "Dashboard/Header/Title", name: "Title")
        #expect(OutlineRow(row: row, file: file, artboard: "Cnv01", state: ViewState(node: "Dashboard/Header/Title")).isSelected)
    }

    @Test("A recently touched row carries its first editor's color and lists them all")
    func touchedRowCarriesColor() {
        let html = OutlineRow(
            row: PreviewFixtures.row(id: "Ttl01", name: "Title"),
            file: file,
            artboard: "Cnv01",
            state: ViewState(),
            editors: ["claude-a", "ben"]
        ).render()
        #expect(html.contains("is-touched"))
        #expect(html.contains("--v-actor: hsl(152 85% 48%)"))
        #expect(html.contains("data-editors=\"claude-a ben\""))
    }

    @Test("An untouched row carries no color at all")
    func untouchedRowHasNoColor() {
        let html = OutlineRow(row: PreviewFixtures.row(id: "Ttl01", name: "Title"), file: file, artboard: "Cnv01", state: ViewState()).render()
        #expect(!html.contains("--v-actor"))
        #expect(!html.contains("is-touched"))
    }

    @Test("An unnamed node reads as its id marker")
    func unnamedRowUsesIDMarker() {
        let row = OutlineRow(row: PreviewFixtures.row(id: "g7Ttw"), file: file, artboard: "Cnv01", state: ViewState())
        #expect(row.label == "#g7Ttw")
        #expect(row.render().contains("is-unnamed"))
    }

    @Test("Rects read the way the tree verb prints them, and a missing one is not zero")
    func rectsMatchTheVerb() {
        #expect(OutlineRow.rectText(PenRect(x: 728, y: 24, width: 320, height: 172)) == "728,24 320×172")
        #expect(OutlineRow.rectText(PenRect(x: 0.5, y: 0, width: 10, height: 10)) == "0.5,0 10×10")
        #expect(OutlineRow.rectText(nil) == "—")
    }

    @Test("An outline row carries no x/y or w/h — that lives in the Details pane")
    func outlineRowCarriesNoRect() {
        let row = PreviewFixtures.row(id: "Ttl01", name: "Title", rect: PenRect(x: 728, y: 24, width: 320, height: 172))
        let html = OutlineRow(row: row, file: file, artboard: "Cnv01", state: ViewState()).render()
        #expect(!html.contains("v-outline-rect"))
        #expect(!html.contains("728,24"))
    }

    @Test("The artboard list keeps its rect column")
    func artboardRowKeepsItsRect() {
        let artboard = Artboard(id: "Cnv01", name: "Dashboard", x: 728, y: 24, width: 320, height: 172)
        let html = ArtboardRow(artboard: artboard, file: file, state: ViewState()).render()
        #expect(html.contains("v-outline-rect"))
        #expect(html.contains("728,24 320×172"))
    }

    @Test("A row with children carries the shared SVG disclosure glyph")
    func rowWithChildrenCarriesTheDisclosureGlyph() {
        let row = PreviewFixtures.row(id: "Crd01", name: "Cards", childCount: 2)
        let html = OutlineRow(row: row, file: file, artboard: "Cnv01", state: ViewState()).render()
        #expect(html.contains("class=\"v-disclose has-children\""))
        #expect(html.contains("v-disclosure-glyph"))
        #expect(html.contains("<svg"))
    }

    @Test("A leaf row carries a blank disclosure spacer, never the glyph")
    func leafRowCarriesABlankSpacer() {
        let row = PreviewFixtures.row(id: "Ttl01", name: "Title", childCount: 0)
        let html = OutlineRow(row: row, file: file, artboard: "Cnv01", state: ViewState()).render()
        #expect(html.contains("class=\"v-disclose\""))
        #expect(!html.contains("has-children"))
        #expect(!html.contains("v-disclosure-glyph"))
        #expect(!html.contains("<svg"))
    }

    @Test("Glyphs distinguish a definition from an instance from a frame")
    func glyphsDistinguishKinds() {
        #expect(OutlineRow.Glyph.of(PreviewFixtures.row(id: "a", type: "frame")) == .frame)
        #expect(OutlineRow.Glyph.of(PreviewFixtures.row(id: "a", type: "text")) == .text)
        #expect(OutlineRow.Glyph.of(PreviewFixtures.row(id: "a", type: "ref", isInstance: true)) == .instance)
        #expect(OutlineRow.Glyph.of(PreviewFixtures.row(id: "a", type: "frame", isReusable: true)) == .component)
        #expect(OutlineRow.Glyph.of(PreviewFixtures.row(id: "a", type: "sparkle")) == .other)
    }

    @Test("A definition, an instance and a slot each carry a distinct, labeled mark")
    func kindMarksAreDistinctAndLabeled() {
        let component = KindMark(isReusable: true, isInstance: false, isSlot: false)
        let instance = KindMark(isReusable: false, isInstance: true, isSlot: false)
        let slot = KindMark(isReusable: false, isInstance: false, isSlot: true)
        let plain = KindMark(isReusable: false, isInstance: false, isSlot: false)

        #expect(component.kind == .component)
        #expect(instance.kind == .instance)
        #expect(slot.kind == .slot)
        #expect(plain.kind == nil)

        let html = component.render()
        #expect(html.contains("v-kind-mark v-kind-component"))
        #expect(html.contains("title=\"Reusable component definition\""))
        #expect(html.contains(">component<"))
        #expect(instance.render().contains(">instance<"))
        #expect(slot.render().contains(">slot<"))
        #expect(plain.render().isEmpty)
    }

    @Test("A definition mark wins over an instance or slot mark on the same node")
    func kindMarkPrecedenceFavorsTheDefinition() {
        #expect(KindMark(isReusable: true, isInstance: true, isSlot: true).kind == .component)
        #expect(KindMark(isReusable: false, isInstance: true, isSlot: true).kind == .instance)
    }

    @Test("An id chip is a monospace, clickable span carrying the id to copy")
    func idChipCarriesTheIDToCopy() {
        let html = IdChip(id: "Vr7Kd").render()
        #expect(html.contains("class=\"v-id-chip\""))
        #expect(html.contains("data-copy-id=\"Vr7Kd\""))
        #expect(html.contains(">Vr7Kd<"))
        #expect(html.contains("title="))
    }

    @Test("An id chip's extra classes ride alongside the base class")
    func idChipAcceptsExtraClasses() {
        let html = IdChip(id: "Vr7Kd", extraClasses: "v-outline-id").render()
        #expect(html.contains("class=\"v-id-chip v-outline-id\""))
    }

    @Test("A long revision is shortened in the header but kept whole in the title")
    func revisionIsShortened() {
        #expect(OutlinePanel.shortRevision("3f2a91c0d4e5b678") == "3f2a…b678")
        #expect(OutlinePanel.shortRevision("short") == "short")
    }

    @Test("A color variable gets a swatch; a string does not")
    func swatchesFollowType() {
        let document = PenDocument(version: "2.17", variables: [
            "accent": PenVariable(type: .color, value: .simple("#2FBF6F")),
            "headline": PenVariable(type: .string, value: .simple("Overview")),
        ], children: [])
        let rows = ViewerVariable.rows(of: document, theme: [:])
        #expect(rows.map(\.name) == ["accent", "headline"])
        #expect(rows[0].swatch == "#2FBF6F")
        #expect(rows[1].swatch == nil)
    }

    @Test("A themed variable reads as the value the pinned theme selects")
    func themedVariableFollowsTheTheme() {
        let document = PenDocument(version: "2.17", variables: [
            "bg": PenVariable(type: .color, value: .themed([
                PenThemedValue(value: "#F6F5F1", theme: ["mode": "light"]),
                PenThemedValue(value: "#161615", theme: ["mode": "dark"]),
            ])),
        ], children: [])
        #expect(ViewerVariable.rows(of: document, theme: ["mode": "dark"])[0].value == "#161615")
        #expect(ViewerVariable.rows(of: document, theme: ["mode": "light"])[0].value == "#F6F5F1")
    }

    @Test("A variable's last editor comes from the log's inverse operations, not its node ids")
    func variableAttributionUsesInverses() {
        let event = ActivityEvent(
            time: PreviewFixtures.now.addingTimeInterval(-4),
            identity: "ben",
            file: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen"),
            op: .var,
            nodes: [],
            paths: [],
            inverse: [.updateVariable(EditOperation.UpdateVariable(
                name: "accent", variable: PenVariable(type: .color, value: .simple("#000000"))
            ))],
            revision: "3f2a91c0d4e5b678"
        )
        let document = PenDocument(version: "2.17", variables: [
            "accent": PenVariable(type: .color, value: .simple("#2FBF6F")),
        ], children: [])
        let rows = ViewerVariable.rows(of: document, theme: [:], events: [event])
        #expect(rows[0].lastEditor == "ben")
    }

    @Test("A boolean variable renders as a labeled pill")
    func booleansRenderAsAPill() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(name: "dark-mode", type: .boolean, value: "true"),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains("v-bool-pill"))
        #expect(html.contains("data-value=\"true\""))
        #expect(html.contains(">true<"))
    }

    @Test("A number variable's value carries a distinct numeric class")
    func numbersCarryANumericClass() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(name: "spacing-md", type: .number, value: "16"),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains("v-variable-value v-variable-number"))
        #expect(html.contains(">16<"))
    }

    @Test("A string variable's value renders as plain text")
    func stringsRenderAsPlainText() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(name: "font-primary", type: .string, value: "IBM Plex Sans"),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains("v-variable-value v-variable-string"))
        #expect(html.contains(">IBM Plex Sans<"))
    }

    @Test("A themed number variable lists each variant with its axis=option label")
    func themedNumberVariableListsVariants() {
        let document = PenDocument(version: "2.17", variables: [
            "card-radius": PenVariable(type: .number, value: .themed([
                PenThemedValue(value: 4, theme: ["density": "compact"]),
                PenThemedValue(value: 8, theme: ["density": "regular"]),
            ])),
        ], children: [])
        let rows = ViewerVariable.rows(of: document, theme: ["density": "regular"])
        #expect(rows[0].value == "8")
        #expect(rows[0].variants == [
            ViewerVariable.Variant(axis: "density=compact", value: "4"),
            ViewerVariable.Variant(axis: "density=regular", value: "8"),
        ])
    }

    @Test("A themed color variable's variants each carry a swatch; a themed number's carry none")
    func onlyColorVariantsCarrySwatches() throws {
        let document = PenDocument(version: "2.17", variables: [
            "bg": PenVariable(type: .color, value: .themed([
                PenThemedValue(value: "#F6F5F1", theme: ["mode": "light"]),
                PenThemedValue(value: "#161615", theme: ["mode": "dark"]),
            ])),
            "card-radius": PenVariable(type: .number, value: .themed([
                PenThemedValue(value: 4, theme: ["density": "compact"]),
                PenThemedValue(value: 8, theme: ["density": "regular"]),
            ])),
        ], children: [])
        let rows = ViewerVariable.rows(of: document, theme: [:])
        let bg = try #require(rows.first { $0.name == "bg" })
        let cardRadius = try #require(rows.first { $0.name == "card-radius" })
        #expect(bg.variants.map(\.swatch) == ["#F6F5F1", "#161615"])
        #expect(cardRadius.variants.map(\.swatch) == [nil, nil])
    }

    @Test("An unconditional variant's axis reads as `*`, the same mark an unthemed value's row uses")
    func unconditionalVariantReadsAsStar() {
        let document = PenDocument(version: "2.17", variables: [
            "bg": PenVariable(type: .color, value: .themed([
                PenThemedValue(value: "#F6F5F1", theme: nil),
            ])),
        ], children: [])
        let rows = ViewerVariable.rows(of: document, theme: [:])
        #expect(rows[0].variants == [ViewerVariable.Variant(axis: "*", value: "#F6F5F1", swatch: "#F6F5F1")])
    }

    @Test("The variables panel carries a collapse toggle")
    func panelHasACollapseToggle() {
        let html = VariablesPanel(variables: [], axes: [:], clock: PreviewFixtures.clock).render()
        #expect(html.contains("v-variables-toggle"))
    }

    @Test("The header's disclosure glyph and title share one flush-left group; the axes note is what's pushed right")
    func headerGroupsTheToggleWithTheTitle() {
        let html = VariablesPanel(variables: [], axes: ["mode": ["light", "dark"]], clock: PreviewFixtures.clock).render()
        #expect(html.contains(
            "<div class=\"v-panel-head-title\"><button class=\"v-variables-toggle\" type=\"button\" "
                + "title=\"Collapse or expand the variables list\"><span class=\"v-disclosure-glyph\""
        ))
        #expect(html.contains("<h2 class=\"v-panel-title\">Variables</h2></div>"))
    }

    @Test("Each row's summary opens behind the same disclosure glyph the header uses")
    func rowSummaryCarriesTheGlyph() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(name: "dark-mode", type: .boolean, value: "true"),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains("<summary class=\"v-variable-summary\"><span class=\"v-disclosure-glyph\""))
    }

    @Test("A themed color variable expands to one table row per axis, each carrying its own swatch")
    func themedColorExpandsToATableWithSwatches() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(
                name: "bg", type: .color, value: "#F6F5F1", swatch: "#F6F5F1",
                variants: [
                    ViewerVariable.Variant(axis: "mode=light", value: "#F6F5F1", swatch: "#F6F5F1"),
                    ViewerVariable.Variant(axis: "mode=dark", value: "#161615", swatch: "#161615"),
                ]
            ),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains(
            "<div class=\"v-variant-row\"><span class=\"v-variant-axis\">mode=light</span>"
                + "<span class=\"v-variant-value\"><span class=\"v-swatch\" style=\"--v-swatch: #F6F5F1\" title=\"#F6F5F1\"></span>#F6F5F1</span></div>"
        ))
        #expect(html.contains(
            "<div class=\"v-variant-row\"><span class=\"v-variant-axis\">mode=dark</span>"
                + "<span class=\"v-variant-value\"><span class=\"v-swatch\" style=\"--v-swatch: #161615\" title=\"#161615\"></span>#161615</span></div>"
        ))
        // No bullet list left behind — the table replaces it outright.
        #expect(!html.contains("v-variable-variants"))
        #expect(!html.contains("<ul"))
    }

    @Test("A themed number variable's table rows carry no swatch")
    func themedNumberExpandsWithNoSwatch() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(
                name: "card-radius", type: .number, value: "8",
                variants: [
                    ViewerVariable.Variant(axis: "density=compact", value: "4"),
                    ViewerVariable.Variant(axis: "density=regular", value: "8"),
                ]
            ),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains(
            "<div class=\"v-variant-row\"><span class=\"v-variant-axis\">density=compact</span>"
                + "<span class=\"v-variant-value\">4</span></div>"
        ))
        #expect(!html.contains("v-swatch\" style"))
    }

    @Test("An unthemed color variable still expands to a one-row table, its axis reading `*`")
    func unthemedVariableGetsAOneRowTable() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(name: "accent", type: .color, value: "#2FBF6F", swatch: "#2FBF6F"),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains(
            "<div class=\"v-variant-row\"><span class=\"v-variant-axis\">*</span>"
                + "<span class=\"v-variant-value\"><span class=\"v-swatch\" style=\"--v-swatch: #2FBF6F\" title=\"#2FBF6F\"></span>#2FBF6F</span></div>"
        ))
    }

    @Test("A number variable with no variants still expands to a one-row table, with no swatch")
    func unthemedNumberGetsAOneRowTableWithNoSwatch() {
        let html = VariablesPanel.VariableRow(
            variable: ViewerVariable(name: "spacing-md", type: .number, value: "16"),
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains(
            "<div class=\"v-variant-row\"><span class=\"v-variant-axis\">*</span><span class=\"v-variant-value\">16</span></div>"
        ))
    }

    @Test("An id chip carries both its words, so a copy flash is a class and never a rewrite (ymsE0s)")
    func idChipCarriesBothWords() {
        let resting = IdChip(id: "Vr7Kd").render()
        #expect(resting.contains(#"<span class="v-id-chip-id">Vr7Kd</span>"#))
        #expect(resting.contains(#"<span class="v-copied" aria-hidden="true">copied</span>"#))
        let copied = IdChip(id: "Vr7Kd", copied: true).render()
        #expect(copied.contains("is-copied"))
        #expect(copied.contains(#"<span class="v-id-chip-id">Vr7Kd</span>"#))
        #expect(!ViewerScript.javaScript.contains("textContent = \"copied\""))
    }

    @Test("The footer's copy button carries both its words, and the script only flips a class (ymsE0s)")
    func copyButtonCarriesBothWords() throws {
        let component = try #require(PreviewCatalog.component(slug: "selection-bar"))
        let html = try #require(component.state(slug: "default")).render()
        #expect(html.contains(#"<span class="v-copy-label">copy address</span>"#))
        #expect(html.contains(#"<span class="v-copied" aria-hidden="true">copied</span>"#))
    }
}
