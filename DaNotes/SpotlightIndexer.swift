//
//  SpotlightIndexer.swift
//  DaNotes
//

import AppIntents
import CoreSpotlight

/// Keeps this device's Spotlight index in sync with `Note` content.
///
/// The index is local to each device — it isn't part of the CloudKit sync —
/// so besides pushing updates as notes change, the whole library is
/// re-indexed once at launch to pick up anything that arrived via sync while
/// this device was closed.
@MainActor
enum SpotlightIndexer {
    static func index(_ note: Note) {
        guard !note.isBlank else { return }
        let entity = NoteEntity(note)
        Task {
            try? await CSSearchableIndex.default().indexAppEntities([entity])
        }
    }

    static func indexAll(_ notes: [Note]) {
        let entities = notes.filter { !$0.isBlank }.map(NoteEntity.init)
        guard !entities.isEmpty else { return }
        Task {
            try? await CSSearchableIndex.default().indexAppEntities(entities)
        }
    }

    static func remove(_ note: Note) {
        let id = note.id
        Task {
            try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [id], ofType: NoteEntity.self)
        }
    }
}
