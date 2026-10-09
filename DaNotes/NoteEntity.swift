//
//  NoteEntity.swift
//  DaNotes
//

import AppIntents
import CoreSpotlight
import SwiftData

/// Spotlight-searchable projection of a `Note`. Pushed to the index by
/// `SpotlightIndexer` whenever a note's content changes or is removed.
struct NoteEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Note" }
    static var defaultQuery = NoteQuery()

    let id: UUID
    let excerpt: String
    @Property(title: "Title") var title: String

    /// Maps to the Spotlight item's body text, so search matches the note's
    /// content and not just its title.
    @ComputedProperty(indexingKey: \.contentDescription)
    var bodyExcerpt: String { excerpt }

    init(id: UUID, title: String, excerpt: String) {
        self.id = id
        self.excerpt = excerpt
        self.title = title
    }

    init(_ note: Note) {
        self.init(id: note.id, title: note.displayTitle, excerpt: String(note.text.prefix(400)))
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(excerpt)")
    }
}

/// Resolves `NoteEntity` values against the shared model container — this
/// runs outside the SwiftUI environment, so it fetches directly rather than
/// through `@Environment(\.modelContext)`.
struct NoteQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        let ids = Set(identifiers)
        return try await fetchAllNotes().filter { ids.contains($0.id) }.map(NoteEntity.init)
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await fetchAllNotes()
            .filter { $0.displayTitle.localizedStandardContains(trimmed) || $0.text.localizedStandardContains(trimmed) }
            .prefix(25)
            .map(NoteEntity.init)
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        try await fetchAllNotes().prefix(20).map(NoteEntity.init)
    }

    @MainActor
    private func fetchAllNotes() throws -> [Note] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
        return try AppModelContainer.shared.mainContext.fetch(descriptor)
    }
}

/// Opens a note from Spotlight (or another system surface that offers a
/// `NoteEntity`), foregrounding the app and selecting it in the sidebar.
struct OpenNoteIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Note"
    @Parameter(title: "Note") var target: NoteEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationCoordinator.shared.pendingNoteID = target.id
        return .result()
    }
}
