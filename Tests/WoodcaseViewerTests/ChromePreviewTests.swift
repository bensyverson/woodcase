//
//  ChromePreviewTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// How the top bar, the theme picker and the live badge behave. Their pictures are in the preview catalog.
struct ChromePreviewTests {
    private let axes = ["Mode": ["Light", "Dark"], "Base": ["Slate", "Sand"]]

    @Test("Each axis is its own form, so each submits one complete ?theme=")
    func eachAxisIsItsOwnForm() {
        let html = ThemePicker(axes: axes, state: ViewState(), action: "/files/a1").render()
        #expect(html.components(separatedBy: "<form").count == 3)
        #expect(html.contains("name=\"theme\""))
    }

    @Test("An option's value is the whole pin set with that one axis swapped")
    func optionsCarryEveryPin() {
        let picker = ThemePicker.AxisPicker(
            axis: "Mode",
            values: ["Light", "Dark"],
            state: ViewState(theme: ["Base": "Slate"]),
            action: "/files/a1"
        )
        #expect(picker.pinned("Dark") == "Base:Slate,Mode:Dark")
        #expect(picker.pinned(nil) == "Base:Slate")
        #expect(picker.render().contains("value=\"Base:Slate,Mode:Dark\""))
    }

    @Test("The pinned value is the selected option; unpinned selects the default")
    func selectionFollowsThePin() {
        let pinned = ThemePicker(axes: axes, state: ViewState(theme: ["Mode": "Dark"]), action: "/f").render()
        #expect(pinned.contains("<option value=\"Mode:Dark\" selected>Dark</option>"))
        let bare = ThemePicker(axes: axes, state: ViewState(), action: "/f").render()
        #expect(bare.contains("<option value=\"\" selected>default</option>"))
    }

    @Test("The rest of the view state rides along as hidden fields")
    func hiddenFieldsCarryTheState() {
        let html = ThemePicker(
            axes: ["Mode": ["Dark"]],
            state: ViewState(node: "Ttl01", depth: 3),
            action: "/files/a1"
        ).render()
        #expect(html.contains("<input type=\"hidden\" name=\"node\" value=\"Ttl01\">"))
        #expect(html.contains("<input type=\"hidden\" name=\"depth\" value=\"3\">"))
    }

    @Test("The brand is the way back to the root, which is why no crumb says Files")
    func brandLinksToTheRoot() {
        let html = TopBar(
            crumbs: [TopBar.Crumb(label: "banking")],
            presence: [],
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains("<a class=\"v-brand\" href=\"/\""))
        #expect(html.contains(">woodcase</a>"))
        #expect(!html.contains("woodcase serve"))
    }

    @Test("The stream badge names every state it can be in, and shows one of them")
    func liveBadgeNamesEveryState() {
        let html = LiveBadge().render()
        for state in ConnectionState.allCases {
            #expect(html.contains("data-state=\"\(state.rawValue)\">\(state.label)<"))
            // The state is an attribute the script writes; which label is visible is the
            // stylesheet's answer to it, so every case needs its rule or the badge lies.
            #expect(ViewerStylesheet.css.contains(
                ".v-live[data-state=\"\(state.rawValue)\"] .v-live-label[data-state=\"\(state.rawValue)\"]"
            ))
        }
        // `connecting` is where the server starts the badge; the other two are the only
        // states the script ever writes, and it writes them from this same enum.
        for written in [ConnectionState.live, .lost] {
            #expect(ViewerScript.javaScript.contains("live(\"\(written.rawValue)\")"))
        }
        #expect(ConnectionState.lost.label == "disconnected")
        // DESIGN.md's *Live badge*: the arriving state is still in progress, and says so.
        #expect(ConnectionState.connecting.label == "connecting…")
        #expect(html.contains("id=\"v-live\" data-state=\"\(ConnectionState.connecting.rawValue)\""))
    }

    @Test("The key hint is a button that opens a popover, not a tooltip that does nothing")
    func keyHintOpensAPopover() {
        let html = KeyboardHint().render()
        #expect(html.contains("<button class=\"v-key-hint\" type=\"button\" popovertarget=\"v-keys\""))
        #expect(html.contains("id=\"v-keys\""))
        #expect(html.contains("popover"))
        #expect(!html.contains("title=\"Keyboard shortcuts"))
        for shortcut in KeyboardHint.shortcuts {
            #expect(html.contains(shortcut.keys))
            #expect(html.contains(shortcut.does))
        }
        // Shown by the popover's own machinery, so the rule that hides it must not be
        // the one that wins once it is open.
        #expect(ViewerStylesheet.css.contains(".v-key-hint-popover:popover-open"))
    }

    @Test("The presentation button is offered over an artboard and nowhere else")
    func presentationButtonIsForArtboards() {
        let artboard = TopBar(
            crumbs: [TopBar.Crumb(label: "banking")],
            presence: [],
            clock: PreviewFixtures.clock,
            subject: .artboard
        ).render()
        #expect(artboard.contains("id=\"v-present\""))
        #expect(artboard.contains("title=\"Presentation (f)\""))

        // The map is a file's page too — it follows — but there is no one artboard on it
        // to fill the screen with, so it is offered no way to try.
        for subject in [TopBar.Subject.files, .map] {
            let html = TopBar(
                crumbs: [TopBar.Crumb(label: "banking")],
                presence: [],
                clock: PreviewFixtures.clock,
                subject: subject
            ).render()
            #expect(!html.contains("id=\"v-present\""), "\(subject) has no artboard to present")
        }
    }

    @Test("The last crumb is the page you are on and is not a link")
    func lastCrumbIsNotALink() {
        let html = TopBar(
            crumbs: [
                TopBar.Crumb(label: "banking", href: "/files/a1b2c3d4e5f6"),
                TopBar.Crumb(label: "Dashboard"),
            ],
            presence: [],
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains(
            "<a class=\"v-crumb\" href=\"/files/a1b2c3d4e5f6\" title=\"banking\">banking</a>"
        ))
        #expect(html.contains("<span class=\"v-crumb is-current\">Dashboard</span>"))
    }

    @Test("The crumb that leads back to the map says so with a glyph and its own class")
    func mapCrumbIsMarked() {
        let html = TopBar(
            crumbs: [
                TopBar.Crumb(label: "banking", href: "/files/a1b2c3d4e5f6", leads: .map),
                TopBar.Crumb(label: "Dashboard"),
            ],
            presence: [],
            clock: PreviewFixtures.clock
        ).render()
        #expect(html.contains("class=\"v-crumb v-crumb-map\""))
        #expect(html.contains("<span class=\"v-crumb-glyph\">▦</span>banking"))
        #expect(html.contains("title=\"Every artboard in this file\""))
        // The class is the hook the script hangs the file-wide unread dot on.
        #expect(ViewerStylesheet.css.contains(".v-crumb-map[data-unread=\"1\"]"))
    }

    @Test("A theme picker with no axes renders nothing at all, not an empty flex item (MqMUlS)")
    func themePickerWithNoAxesRendersNothing() {
        #expect(ThemePicker(axes: [:], state: ViewState(), action: "/").render().isEmpty)
        let bar = TopBar(crumbs: [TopBar.Crumb(label: "files")], presence: [], clock: PreviewFixtures.clock)
        #expect(!bar.render().contains("v-theme"))
    }

    @Test("Over the preview catalog the bar is the trail alone: nothing live to show")
    func previewSubjectIsATrail() {
        let html = TopBar(
            crumbs: [TopBar.Crumb(label: "Previews")],
            presence: [],
            clock: PreviewFixtures.clock,
            subject: .previews
        ).render()
        #expect(html.contains("v-brand"))
        #expect(html.contains(">Previews<"))
        for absent in ["v-live", "v-presence", "v-key-hint", "v-theme", "v-follow", "v-present"] {
            #expect(!html.contains("class=\"\(absent)"), "the previews bar carries \(absent)")
        }
    }

    @Test("An unattributed writer is named in words wherever a name is written (JFazoq)")
    func unattributedPresenceSaysSo() {
        let stack = PresenceStack(
            identities: [
                PreviewFixtures.identity(ActivityEvent.unattributed, secondsAgo: 2),
                PreviewFixtures.identity("claude-a", secondsAgo: 60),
            ],
            clock: PreviewFixtures.clock
        ).render()
        #expect(stack.contains(#"2 active · <span class="v-presence-name is-unattributed">unattributed</span> editing"#))
        #expect(!stack.contains(#"<span class="v-presence-name"></span>"#))
    }
}
