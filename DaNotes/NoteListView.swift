//
//  NoteListView.swift
//  DaNotes
//

import SwiftUI
import SwiftData

enum SidebarMode: String {
    case notes
    case outline
}

enum NoteSortOrder: String {
    case modified
    case lastOpened
    case created
    case title
}

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.modifiedAt, order: .reverse) private var notes: [Note]
    @State private var selectedNoteID: Note.ID?
    @State private var outlineJump: OutlineJump?
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @AppStorage("SidebarMode") private var sidebarMode: SidebarMode = .notes
    @AppStorage("NoteSortOrder") private var sortOrder: NoteSortOrder = .modified
    @State private var noteToDelete: Note?
    @State private var searchText: String = ""
    @State private var selectedTag: String?

    private var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            // A dedicated NavigationStack scopes this toolbar to the sidebar
            // column. `.navigation` placement is not used here: on macOS it
            // always targets the leading edge of the window's single shared
            // toolbar, which is where the detail pane's own `.navigation`
            // group (the export buttons) lives — so items placed there end
            // up merged with the detail pane's toolbar instead of staying in
            // the sidebar. Automatic placement keeps items scoped to the
            // column that declares them.
            NavigationStack {
                sidebarList
                    .navigationTitle("DaNotes")
                    .toolbar {
                        ToolbarItem {
                            Button(.newNote, systemImage: "square.and.pencil") {
                                createNote()
                            }
                            .keyboardShortcut("n", modifiers: .command)
                        }
                        if sidebarMode == .notes {
                            ToolbarItem {
                                viewOptionsMenu
                            }
                        }
                        ToolbarSpacer()
                        ToolbarItemGroup {
                            Picker(selection: $sidebarMode) {
                                Label(.sidebarNotes, systemImage: "list.bullet").tag(SidebarMode.notes)
                                Label(.sidebarOutline, systemImage: "list.bullet.indent").tag(SidebarMode.outline)
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    .searchable(text: $searchText, prompt: Text(.searchNotesPrompt))
            }
        } detail: {
            if let selectedNote {
                ContentView(note: selectedNote, outlineJump: outlineJump) { tag in
                    selectedTag = tag
                    sidebarMode = .notes
                }
                .id(selectedNote.id)
            } else {
                ContentUnavailableView(.noNoteSelected, systemImage: "note.text")
            }
        }
        .onChange(of: selectedNoteID) { oldValue, newValue in
            outlineJump = nil
            selectedNote?.lastOpenedAt = Date()
            // Discard a note the user navigated away from without ever
            // typing anything into it, so blank notes don't pile up.
            if let oldValue, oldValue != newValue,
               let abandoned = notes.first(where: { $0.id == oldValue }), abandoned.isBlank {
                modelContext.delete(abandoned)
            }
        }
        .onChange(of: sidebarMode) {
            if sidebarMode == .outline {
                searchText = ""
                selectedTag = nil
            }
        }
        // Set by `OpenNoteIntent` when the user taps a note in Spotlight.
        .onChange(of: NavigationCoordinator.shared.pendingNoteID) { _, newValue in
            guard let newValue, notes.contains(where: { $0.id == newValue }) else { return }
            selectedNoteID = newValue
            sidebarMode = .notes
            NavigationCoordinator.shared.pendingNoteID = nil
        }
        .confirmationDialog(
            Text(deleteConfirmationTitle),
            isPresented: Binding(get: { noteToDelete != nil }, set: { if !$0 { noteToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(.deleteNote, role: .destructive) {
                if let noteToDelete { delete(noteToDelete) }
            }
        }
        .onAppear {
            LegacyNoteMigrator.migrateIfNeeded(context: modelContext)
            // Fetch directly: `notes` hasn't picked up a just-migrated note yet.
            let allNotes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
            // The Spotlight index is local to this device, so re-index
            // everything at launch to pick up changes synced in from others.
            SpotlightIndexer.indexAll(allNotes)
            guard selectedNoteID == nil else { return }
            let selected = resumeNote(from: allNotes)
            selectedNoteID = selected.id
            // A blank note left over from a previous session (other than the
            // one just resumed) is clutter, not content — drop it silently.
            for note in allNotes where note.id != selected.id && note.isBlank {
                modelContext.delete(note)
            }
        }
    }

    // A single `List` instance that persists across mode switches, only
    // swapping its row content. NavigationSplitView ties the detail pane's
    // lifecycle to the sidebar's `List(selection:)` identity, so replacing
    // the whole `List` on every mode switch tore down and rebuilt the detail
    // pane (editor + preview), causing a visible flicker.
    @ViewBuilder
    private var sidebarList: some View {
        List(selection: $selectedNoteID) {
            switch sidebarMode {
            case .notes:
                if filteredNotes.isEmpty {
                    ContentUnavailableView(.noMatchingNotes, systemImage: "magnifyingglass")
                } else if pinnedNotes.isEmpty {
                    ForEach(unpinnedNotes) { note in
                        noteRow(note)
                    }
                } else {
                    Section(String(localized: .pinnedSectionTitle)) {
                        ForEach(pinnedNotes) { note in
                            noteRow(note)
                        }
                    }
                    Section(String(localized: .allNotesSectionTitle)) {
                        ForEach(unpinnedNotes) { note in
                            noteRow(note)
                        }
                    }
                }
            case .outline:
                let items = selectedNote?.outline.filter { !$0.title.isEmpty } ?? []
                if items.isEmpty {
                    ContentUnavailableView(.noHeadings, systemImage: "list.bullet.indent")
                } else {
                    ForEach(items) { item in
                        outlineRow(item)
                    }
                }
            }
        }
    }

    // MARK: - Filtering, tagging, sorting

    /// Notes matching the current search text and tag filter, unsorted.
    private var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            matchesTagFilter(note) && matchesSearch(note, query: query)
        }
    }

    private var pinnedNotes: [Note] {
        sorted(filteredNotes.filter(\.isPinned))
    }

    private var unpinnedNotes: [Note] {
        sorted(filteredNotes.filter { !$0.isPinned })
    }

    /// Every tag used by any note, deduplicated case-insensitively and
    /// sorted for display in the filter menu.
    private var allTags: [String] {
        var seenLowercased: Set<String> = []
        var result: [String] = []
        for note in notes {
            for tag in note.tags where !seenLowercased.contains(tag.lowercased()) {
                seenLowercased.insert(tag.lowercased())
                result.append(tag)
            }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func matchesTagFilter(_ note: Note) -> Bool {
        guard let selectedTag else { return true }
        return note.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }
    }

    /// A leading `#` searches tags by prefix; anything else searches the
    /// title and body text.
    private func matchesSearch(_ note: Note, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if query.hasPrefix("#") {
            let needle = query.dropFirst()
            guard !needle.isEmpty else { return true }
            return note.tags.contains { $0.range(of: needle, options: [.caseInsensitive, .anchored]) != nil }
        }
        return note.displayTitle.localizedStandardContains(query) || note.text.localizedStandardContains(query)
    }

    /// A short excerpt of the body line where `query` first matches, with the
    /// match highlighted — shown so a title-only row doesn't leave the user
    /// guessing why a note matched a body search. `nil` when not searching,
    /// searching by tag, or the match is already visible in the title.
    private func bodyMatchSnippet(for note: Note, query: String) -> AttributedString? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !trimmedQuery.hasPrefix("#") else { return nil }
        guard !note.displayTitle.localizedCaseInsensitiveContains(trimmedQuery) else { return nil }

        let fullText = note.text as NSString
        let matchRange = fullText.range(of: trimmedQuery, options: .caseInsensitive)
        guard matchRange.location != NSNotFound else { return nil }

        let line = fullText.substring(with: fullText.lineRange(for: matchRange))
            .trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        let matchInLine = line.range(of: trimmedQuery, options: .caseInsensitive)
        guard matchInLine.location != NSNotFound else { return nil }

        let context = 40
        let start = max(0, matchInLine.location - context)
        let end = min(line.length, matchInLine.location + matchInLine.length + context)
        var snippet = line.substring(with: NSRange(location: start, length: end - start))
        if start > 0 { snippet = "…" + snippet }
        if end < line.length { snippet += "…" }

        var attributed = AttributedString(snippet)
        if let highlightRange = attributed.range(of: trimmedQuery, options: [.caseInsensitive]) {
            attributed[highlightRange].backgroundColor = .yellow.opacity(0.5)
        }
        return attributed
    }

    private func sorted(_ notes: [Note]) -> [Note] {
        switch sortOrder {
        case .modified:
            return notes.sorted { $0.modifiedAt > $1.modifiedAt }
        case .lastOpened:
            return notes.sorted {
                ($0.lastOpenedAt ?? .distantPast) != ($1.lastOpenedAt ?? .distantPast)
                    ? ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
                    : $0.modifiedAt > $1.modifiedAt
            }
        case .created:
            return notes.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return notes.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        }
    }

    // Sort and tag filtering are secondary, infrequently-changed settings, so
    // they're tucked under a single "…" menu (as in Notes/Reminders) rather
    // than each getting their own always-visible toolbar button.
    private var viewOptionsMenu: some View {
        Menu {
            Menu {
                sortOptionButton(.modified, title: .sortByModified)
                sortOptionButton(.lastOpened, title: .sortByLastOpened)
                sortOptionButton(.created, title: .sortByCreated)
                sortOptionButton(.title, title: .sortByTitle)
            } label: {
                Label(.sortMenuTitle, systemImage: "arrow.up.arrow.down")
            }
            Menu {
                Button(.allTagsFilterOption) {
                    selectedTag = nil
                }
                if !allTags.isEmpty {
                    Divider()
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            if selectedTag?.caseInsensitiveCompare(tag) == .orderedSame {
                                Label(tag, systemImage: "checkmark")
                            } else {
                                Text(tag)
                            }
                        }
                    }
                }
            } label: {
                Label(.tagFilterMenuTitle, systemImage: selectedTag == nil ? "tag" : "tag.fill")
            }
        } label: {
            Label(.viewOptions, systemImage: selectedTag == nil ? "ellipsis.circle" : "ellipsis.circle.fill")
        }
    }

    private func sortOptionButton(_ order: NoteSortOrder, title: LocalizedStringResource) -> some View {
        Button {
            sortOrder = order
        } label: {
            if sortOrder == order {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(note.modifiedAt, format: .dateTime)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let snippet = bodyMatchSnippet(for: note, query: searchText) {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
        }
        .tag(note.id)
        .contextMenu {
            Button(note.isPinned ? .unpinNote : .pinNote, systemImage: note.isPinned ? "pin.slash" : "pin") {
                togglePin(note)
            }
            Button(.deleteNote, systemImage: "trash", role: .destructive) {
                requestDelete(note)
            }
        }
        .swipeActions {
            Button(.deleteNote, systemImage: "trash", role: .destructive) {
                requestDelete(note)
            }
            Button(note.isPinned ? .unpinNote : .pinNote, systemImage: note.isPinned ? "pin.slash" : "pin") {
                togglePin(note)
            }
            .tint(.orange)
        }
    }

    private func outlineRow(_ item: OutlineItem) -> some View {
        Button {
            outlineJump = OutlineJump(item: item)
            preferredCompactColumn = .detail
        } label: {
            Text(item.title)
                .font(item.level == 1 ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(item.level <= 2 ? .primary : .secondary)
                .lineLimit(1)
                .padding(.leading, CGFloat(item.level - 1) * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var deleteConfirmationTitle: String {
        String(localized: .deleteNoteConfirm(noteToDelete?.displayTitle ?? ""))
    }

    private func createNote() {
        let note = Note()
        modelContext.insert(note)
        selectedNoteID = note.id
    }

    /// The note to resume into at launch: the one open last time, falling
    /// back to a leftover blank note, then the most recently edited note,
    /// then a freshly created one.
    private func resumeNote(from allNotes: [Note]) -> Note {
        if let previous = allNotes.filter({ $0.lastOpenedAt != nil }).max(by: { $0.lastOpenedAt! < $1.lastOpenedAt! }) {
            return previous
        }
        if let blank = allNotes.first(where: \.isBlank) {
            return blank
        }
        if let latest = allNotes.max(by: { $0.modifiedAt < $1.modifiedAt }) {
            return latest
        }
        let note = Note()
        modelContext.insert(note)
        return note
    }

    private func delete(_ note: Note) {
        if selectedNoteID == note.id {
            selectedNoteID = notes.first { $0.id != note.id }?.id
        }
        SpotlightIndexer.remove(note)
        modelContext.delete(note)
    }

    /// Deletes a blank note immediately (nothing of value to lose); anything
    /// else still goes through the confirmation dialog.
    private func requestDelete(_ note: Note) {
        if note.isBlank {
            delete(note)
        } else {
            noteToDelete = note
        }
    }

    private func togglePin(_ note: Note) {
        note.isPinned.toggle()
    }
}
