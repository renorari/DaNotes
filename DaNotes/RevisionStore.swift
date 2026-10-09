//
//  RevisionStore.swift
//  DaNotes
//

import Foundation
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A locally-generated, stable identifier for this device/install — not
/// personal information, just enough to label revisions and merges with
/// "which device made this change" in the history view.
enum DeviceIdentity {
    private static let key = "DaNotesDeviceID"

    static let id: String = {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()

    static var name: String {
#if os(macOS)
        Host.current().localizedName ?? "Mac"
#else
        UIDevice.current.name
#endif
    }
}

/// Turns a note's live `text` into a `NoteRevision` history, and reconciles
/// that history back into `text` when two devices' edits have diverged.
///
/// `Note.text` itself is a plain CloudKit-synced field, so when two devices
/// edit it offline, CloudKit's normal last-write-wins behavior can silently
/// drop one side. Revisions sidestep that: they're never mutated after
/// creation, so CloudKit syncing them is purely additive and can't conflict.
/// Each device commits its own revisions as it edits; when sync brings in a
/// revision from another device, the DAG ends up with more than one head,
/// and `reconcile` folds them back together with a three-way merge.
@MainActor
enum RevisionStore {
    struct PendingConflict: Identifiable {
        let id = UUID()
        let heads: [NoteRevision]
        let segments: [ThreeWayMerge.Segment]
    }

    /// Records `note.text` as a new revision if it differs from the current
    /// head. A no-op if nothing changed since the last commit, so calling
    /// this on a timer or on every note switch is cheap.
    static func commit(note: Note, context: ModelContext, kind: NoteRevision.Kind = .auto) {
        let revisions = note.revisions ?? []
        let heads = RevisionGraph.heads(of: revisions)
        if kind == .auto {
            if heads.count == 1, heads[0].text == note.text { return }
            if revisions.isEmpty, note.isBlank { return }
        }
        // The first revision ever recorded for a pre-existing note is a
        // migration bootstrap, not a "real" edit.
        let effectiveKind: NoteRevision.Kind = (revisions.isEmpty && kind == .auto) ? .initial : kind
        context.insert(NoteRevision(
            note: note,
            parentIDs: heads.map(\.id),
            text: note.text,
            deviceID: DeviceIdentity.id,
            deviceName: DeviceIdentity.name,
            kind: effectiveKind
        ))
        SpotlightIndexer.index(note)
    }

    /// Folds divergent heads back into one. When the merge is clean, applies
    /// it to `note.text` directly and returns `nil`; when lines conflict,
    /// returns the conflict for the UI to resolve instead of touching the
    /// note.
    @discardableResult
    static func reconcile(note: Note, context: ModelContext) -> PendingConflict? {
        let revisions = note.revisions ?? []
        let heads = RevisionGraph.heads(of: revisions)
        guard heads.count > 1 else { return nil }

        // More than two devices diverging at once is rare for a personal
        // notes app; fold heads in pairwise left-to-right rather than
        // generalizing to an n-way merge.
        var mergedText = heads[0].text
        var conflictSegments: [ThreeWayMerge.Segment]?
        for head in heads.dropFirst() {
            let base = RevisionGraph.commonAncestor(heads[0], head, in: revisions)?.text ?? ""
            let segments = ThreeWayMerge.merge(base: base, ours: mergedText, theirs: head.text)
            if ThreeWayMerge.hasConflict(segments) {
                conflictSegments = segments
                break
            }
            mergedText = ThreeWayMerge.resolve(segments, choices: [])
        }

        if let conflictSegments {
            return PendingConflict(heads: heads, segments: conflictSegments)
        }

        applyMerge(text: mergedText, parents: heads, note: note, context: context)
        return nil
    }

    /// Applies the user's per-conflict choices from a `PendingConflict` and
    /// records the result as a merge revision.
    static func resolveConflict(_ conflict: PendingConflict, note: Note, context: ModelContext, choices: [ThreeWayMerge.Choice]) {
        let resolvedText = ThreeWayMerge.resolve(conflict.segments, choices: choices)
        applyMerge(text: resolvedText, parents: conflict.heads, note: note, context: context)
    }

    /// Reverts `note` to an earlier revision's text, recorded as a new
    /// `.restore` revision (history is append-only; nothing is erased).
    static func restore(_ revision: NoteRevision, note: Note, context: ModelContext) {
        note.text = revision.text
        note.modifiedAt = Date()
        let heads = RevisionGraph.heads(of: note.revisions ?? [])
        context.insert(NoteRevision(
            note: note,
            parentIDs: heads.map(\.id),
            text: revision.text,
            deviceID: DeviceIdentity.id,
            deviceName: DeviceIdentity.name,
            kind: .restore
        ))
        SpotlightIndexer.index(note)
    }

    private static func applyMerge(text: String, parents: [NoteRevision], note: Note, context: ModelContext) {
        note.text = text
        note.modifiedAt = Date()
        context.insert(NoteRevision(
            note: note,
            parentIDs: parents.map(\.id),
            text: text,
            deviceID: DeviceIdentity.id,
            deviceName: DeviceIdentity.name,
            kind: .merge
        ))
        SpotlightIndexer.index(note)
    }
}
