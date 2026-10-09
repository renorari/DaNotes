//
//  HistoryView.swift
//  DaNotes
//

import SwiftUI
import SwiftData

/// Browses a note's revision history and lets the user revert to an earlier
/// version. Revisions are recorded automatically by `RevisionStore`; nothing
/// here lets the user create or delete one directly.
struct HistoryView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRevision: NoteRevision?

    private var revisions: [NoteRevision] {
        (note.revisions ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if revisions.isEmpty {
                    ContentUnavailableView(.noHistoryYet, systemImage: "clock.arrow.circlepath")
                } else {
                    List(revisions) { revision in
                        Button {
                            selectedRevision = revision
                        } label: {
                            row(for: revision)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(Text(.historyTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.close) { dismiss() }
                }
            }
            .sheet(item: $selectedRevision) { revision in
                RevisionDetailView(note: note, revision: revision, onRestore: { dismiss() }, onDuplicate: { newNote in
                    NavigationCoordinator.shared.pendingNoteID = newNote.id
                    dismiss()
                })
            }
        }
#if os(macOS)
        // Without an explicit size, macOS sometimes fails to negotiate a
        // reasonable sheet size for a NavigationStack whose content switches
        // between the tiny empty state and a full list, leaving the sheet
        // collapsed and blank.
        .frame(minWidth: 420, idealWidth: 480, minHeight: 420, idealHeight: 560)
#endif
    }

    private func row(for revision: NoteRevision) -> some View {
        let stats = diffStats(revision)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(revision.deviceName)
                    .font(.headline)
                Spacer()
                kindLabel(revision.kind)
            }
            HStack(spacing: 8) {
                Text(revision.createdAt, format: .dateTime)
                if stats.added > 0 {
                    Text("+\(stats.added)").foregroundStyle(.green)
                }
                if stats.removed > 0 {
                    Text("-\(stats.removed)").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func kindLabel(_ kind: NoteRevision.Kind) -> some View {
        switch kind {
        case .merge:
            Label(.revisionKindMerge, systemImage: "arrow.triangle.merge")
                .font(.caption).foregroundStyle(.secondary)
        case .restore:
            Label(.revisionKindRestore, systemImage: "arrow.uturn.backward")
                .font(.caption).foregroundStyle(.secondary)
        case .initial, .auto:
            EmptyView()
        }
    }

    /// Line-level added/removed counts versus the note's current text, just
    /// to give a sense of how big a change this revision represents.
    private func diffStats(_ revision: NoteRevision) -> (added: Int, removed: Int) {
        let current = ThreeWayMerge.lines(note.text)
        let old = ThreeWayMerge.lines(revision.text)
        let diff = current.difference(from: old)
        var added = 0
        var removed = 0
        for change in diff {
            switch change {
            case .insert: added += 1
            case .remove: removed += 1
            }
        }
        return (added, removed)
    }
}

#Preview {
    let note = Note(text: "hello world")
    _ = NoteRevision(note: note, parentIDs: [], text: "hello", deviceID: "d1", deviceName: "MacBook Pro", kind: .initial)
    _ = NoteRevision(note: note, parentIDs: [], text: "hello world", deviceID: "d1", deviceName: "MacBook Pro", kind: .auto)
    return HistoryView(note: note)
        .modelContainer(for: Note.self, inMemory: true)
}

private struct RevisionDetailView: View {
    @Bindable var note: Note
    let revision: NoteRevision
    var onRestore: () -> Void
    var onDuplicate: (Note) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(revision.text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(Text(revision.createdAt, format: .dateTime))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.close) { dismiss() }
                }
                ToolbarItem {
                    Button(.duplicateThisVersion, systemImage: "doc.on.doc") {
                        let newNote = RevisionStore.duplicate(revision, context: modelContext)
                        onDuplicate(newNote)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.restoreThisVersion) {
                        RevisionStore.restore(revision, note: note, context: modelContext)
                        onRestore()
                    }
                }
            }
        }
    }
}
