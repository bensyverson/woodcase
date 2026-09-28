//
//  PreviewProseTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The small Markdown subset a preview caption is written in, rendered for a person.
///
/// The notes are written in the same dialect as the doc comments beside them, and until
/// this renderer existed they reached the page verbatim — four backticks and a slashed
/// symbol path where a reader wanted a name (issue `iblXjP`).
struct PreviewProseTests {
    @Test("A code span renders as code, without its backticks")
    func codeSpan() {
        #expect(PreviewProse("the `--as` flag").render() == "the <code>--as</code> flag")
    }

    @Test("A DocC symbol link renders as code, in Swift's dotted spelling")
    func symbolLink() {
        #expect(
            PreviewProse("``ActivityEvent/unattributed`` — a write").render()
                == "<code>ActivityEvent.unattributed</code> — a write"
        )
        #expect(PreviewProse("``ViewerScript``'s table").render() == "<code>ViewerScript</code>'s table")
    }

    @Test("Emphasis renders as emphasis")
    func emphasis() {
        #expect(PreviewProse("names *both* keys").render() == "names <em>both</em> keys")
    }

    @Test("An asterisk inside a code span is code, not emphasis")
    func asteriskInsideCode() {
        #expect(PreviewProse("`*points*` here").render() == "<code>*points*</code> here")
    }

    @Test("Text around the markup is escaped like any other text")
    func textIsEscaped() {
        #expect(PreviewProse("a < b and `x<y`").render() == "a &lt; b and <code>x&lt;y</code>")
    }

    @Test("No note or blurb in the catalog reaches the page with a backtick in it")
    func noCaptionRendersABacktick() {
        for component in PreviewCatalog.all {
            #expect(!PreviewProse(component.blurb).render().contains("`"), "\(component.slug)'s blurb")
            for state in component.states {
                #expect(
                    !PreviewProse(state.note).render().contains("`"),
                    "\(component.slug)/\(state.slug)'s note"
                )
            }
        }
    }
}
