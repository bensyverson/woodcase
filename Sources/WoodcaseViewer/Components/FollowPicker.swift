//
//  FollowPicker.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One control in the top bar: whose writes should move the page.
///
/// Its options are *nobody*, *anyone*, and one entry per identity the activity log has
/// seen — server-rendered from the same list the presence stack draws, in the same order
/// of first appearance, so an agent keeps its place in both.
///
/// ## Why it is a form, and a fragment
///
/// A `GET` form with a real submit button, hidden by CSS only once the script has marked
/// the document as scripted: with the script off, choosing a name and pressing *apply*
/// still produces a URL that describes the view, which is the rule for every affordance
/// on this page. And it is the ``ViewerLink/Fragment/follow`` fragment, because the
/// control changes without the file changing — manual navigation drops follow, and the
/// dropdown that says so is server-rendered rather than edited in JavaScript.
///
/// ## Resuming
///
/// When ``ViewState/follow`` is ``Follow/paused(_:)`` the control reads *nobody* and
/// grows a link that names who it would resume. The link is the same view state with the
/// follow switched back on, so it carries the theme pins and the selection forward
/// untouched.
public struct FollowPicker: HTML {
    /// Creates a control.
    ///
    /// - Parameters:
    ///   - identities: Who the log has seen, in its order of first appearance.
    ///   - state: The current view state, whose other parts ride along as hidden fields.
    ///   - action: The path the form submits to — the page you are on.
    public init(identities: [ViewerPresence.Identity], state: ViewState, action: String) {
        self.identities = identities
        self.state = state
        self.action = action
    }

    /// Who the log has seen, in its order of first appearance.
    public let identities: [ViewerPresence.Identity]

    /// The current view state.
    public let state: ViewState

    /// The path the form submits to.
    public let action: String

    /// The value the dropdown shows as chosen.
    ///
    /// A paused follow reads as `nobody`: it *is* nobody until the resume link beside it
    /// is clicked, and a dropdown claiming otherwise would be lying about what the next
    /// change will do.
    var selected: String {
        guard case let .following(target) = state.follow else { return "nobody" }
        return target.query
    }

    /// Where the resume link goes, when there is something to resume.
    var resume: String? {
        guard case let .paused(target) = state.follow else { return nil }
        return action + state.following(.following(target)).query
    }

    /// The names the dropdown offers, in the log's order of first appearance.
    ///
    /// A URL can name someone the log has not seen — a page opened before that agent's
    /// first write, or a link pasted from another session. That name is appended rather
    /// than dropped: a control whose selected value is not among its options silently
    /// reads as *nobody*, which would tell the viewer they are following no one while
    /// the page follows someone.
    var names: [String] {
        var names = identities.map(\.name)
        if case let .identity(name) = state.follow.target, !names.contains(name) {
            names.append(name)
        }
        return names
    }

    public var body: some HTML {
        div(.class("v-follow"), .id(ViewerLink.Fragment.follow.target)) {
            form(.class("v-follow-form"), .method(.get), .action(action)) {
                if let node = state.node {
                    input(.type(.hidden), .name("node"), .value(node))
                }
                if !state.theme.isEmpty {
                    input(.type(.hidden), .name("theme"), .value(ThemeQuery.canonical(state.theme)))
                }
                if let depth = state.depth {
                    input(.type(.hidden), .name("depth"), .value(String(depth)))
                }
                label(.class("v-follow-label"), .for("v-follow-select")) { "follow:" }
                select(.id("v-follow-select"), .class("v-follow-select"), .name("follow")) {
                    option(.value("nobody")) { "nobody" }
                        .attributes(.selected, when: selected == "nobody")
                    option(.value("anyone")) { "anyone" }
                        .attributes(.selected, when: selected == "anyone")
                    for name in names {
                        option(.value(name)) { name }
                            .attributes(.selected, when: selected == name)
                    }
                }
                button(.class("v-go"), .type(.submit)) { "apply" }
            }
            if let resume, let target = state.follow.target {
                a(.class("v-follow-resume"), .href(resume)) { "resume following \(target.label)" }
            }
        }
    }
}
