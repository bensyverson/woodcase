//
//  UndoStepTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins the one rule an undo makes decisions with: which step of the activity log's
/// tail may be reversed, which is stepped over, and which is a conflict it refuses to
/// guess past.
///
/// The rule moved from the CLI into the library with ``ActivityUndo``, so these tests
/// moved with it: a library caller reversing an edit gets the same decisions the verb
/// does, because it is the same enum.
struct UndoStepTests {
    // MARK: - Helpers

    private static let file = URL(fileURLWithPath: "/tmp/undo-step.pen")

    /// One event, with only the fields the decision reads.
    private static func event(
        op: ActivityEvent.Kind = .set,
        identity: String = "ana",
        revision: String
    ) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: 1),
            identity: identity,
            file: file,
            op: op,
            nodes: ["Ttl01"],
            paths: ["Canvas/Title"],
            inverse: [],
            revision: revision
        )
    }

    /// The decision for one event, with the defaults a plain `undo --as ana` uses.
    private static func decide(
        _ event: ActivityEvent,
        currentRevision: String = "aaaa",
        identity: String = "ana",
        allIdentities: Bool = false,
        afterUndo: Bool = false
    ) -> UndoStep {
        UndoStep.decide(
            event,
            currentRevision: currentRevision,
            identity: identity,
            allIdentities: allIdentities,
            afterUndo: afterUndo
        )
    }

    // MARK: - The event to reverse

    @Test("An event by this identity whose revision is the file's current one is undone")
    func matchingEventIsUndone() {
        let candidate = Self.event(revision: "aaaa")
        #expect(Self.decide(candidate) == .undo(candidate))
    }

    // MARK: - Undo events are stepped over, never replayed

    @Test("An undo event is stepped over, so undo never becomes redo", arguments: ["ana", "bo"])
    func undoEventIsSteppedOver(identity: String) {
        // Even one whose revision matches and whose identity is ours: replaying an
        // undo's inverse would re-apply the edit it reversed.
        let candidate = Self.event(op: .undo, identity: identity, revision: "aaaa")
        #expect(Self.decide(candidate) == .stepOverUndo)
    }

    // MARK: - Already reversed

    @Test("After an undo event, a stale candidate is one that undo already reversed")
    func staleCandidateAfterUndoIsSteppedOver() {
        let candidate = Self.event(revision: "bbbb")
        #expect(Self.decide(candidate, afterUndo: true) == .stepOverUndone)
    }

    @Test("With no undo passed, a stale candidate is a conflict rather than a skip")
    func staleCandidateWithoutUndoIsBlocked() {
        let candidate = Self.event(revision: "bbbb")
        #expect(Self.decide(candidate, afterUndo: false) == .blockedByStale(candidate))
    }

    // MARK: - Another identity

    @Test("Another identity's event blocks the undo")
    func otherIdentityBlocks() {
        let candidate = Self.event(identity: "bo", revision: "aaaa")
        #expect(Self.decide(candidate) == .blockedByOther(candidate))
    }

    @Test("Identity is checked before the revision, so the message can name the person")
    func otherIdentityBlocksBeforeStaleness() {
        let candidate = Self.event(identity: "bo", revision: "bbbb")
        #expect(Self.decide(candidate, afterUndo: true) == .blockedByOther(candidate))
    }

    @Test("--all makes another identity's event undoable")
    func allIdentitiesUndoesAnyone() {
        let candidate = Self.event(identity: "bo", revision: "aaaa")
        #expect(Self.decide(candidate, allIdentities: true) == .undo(candidate))
    }

    @Test("--all does not make an undo event replayable")
    func allIdentitiesStillStepsOverUndo() {
        let candidate = Self.event(op: .undo, identity: "bo", revision: "aaaa")
        #expect(Self.decide(candidate, allIdentities: true) == .stepOverUndo)
    }

    // MARK: - An edit made outside woodcase

    @Test("An external event is the end of the walk, whatever revision the file is at")
    func externalEventBlocks() {
        let matching = Self.event(op: .external, identity: ActivityEvent.unattributed, revision: "aaaa")
        let stale = Self.event(op: .external, identity: ActivityEvent.unattributed, revision: "bbbb")
        #expect(Self.decide(matching) == .blockedByExternal(matching))
        #expect(Self.decide(stale) == .blockedByExternal(stale))
    }

    @Test("An external event is refused before the identity check, which would blame nobody")
    func externalEventOutranksIdentity() {
        // It is unattributed by definition, so "somebody else edited later" would name
        // the empty writer — a worse sentence than the true one.
        let candidate = Self.event(op: .external, identity: ActivityEvent.unattributed, revision: "aaaa")
        #expect(Self.decide(candidate, identity: "ana") == .blockedByExternal(candidate))
        #expect(Self.decide(candidate, allIdentities: true) == .blockedByExternal(candidate))
    }

    @Test("An external event is not explained away by an undo the scan already passed")
    func externalEventSurvivesTheHeuristic() {
        let candidate = Self.event(op: .external, identity: ActivityEvent.unattributed, revision: "bbbb")
        #expect(Self.decide(candidate, afterUndo: true) == .blockedByExternal(candidate))
    }
}
