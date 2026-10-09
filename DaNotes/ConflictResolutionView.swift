//
//  ConflictResolutionView.swift
//  DaNotes
//

import SwiftUI
import SwiftData

/// Lets the user resolve the lines `RevisionStore.reconcile` couldn't merge
/// automatically — non-overlapping changes from two devices are already
/// folded together by the time this appears; only the lines both sides
/// changed differently show up here.
struct ConflictResolutionView: View {
    @Bindable var note: Note
    let conflict: RevisionStore.PendingConflict
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [ThreeWayMerge.Choice]

    init(note: Note, conflict: RevisionStore.PendingConflict) {
        self.note = note
        self.conflict = conflict
        let conflictCount = conflict.segments.filter {
            if case .conflict = $0 { return true } else { return false }
        }.count
        _choices = State(initialValue: Array(repeating: .ours, count: conflictCount))
    }

    /// Maps each segment's index to its ordinal among conflicts only (`nil`
    /// for stable segments), so `choices` can be indexed while walking the
    /// full segment list in order.
    private var conflictOrdinals: [Int?] {
        var result: [Int?] = []
        var count = 0
        for segment in conflict.segments {
            if case .conflict = segment {
                result.append(count)
                count += 1
            } else {
                result.append(nil)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(.conflictExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(Array(conflict.segments.enumerated()), id: \.offset) { index, segment in
                        switch segment {
                        case .stable(let lines):
                            Text(lines.joined(separator: "\n"))
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .conflict(_, let ours, let theirs):
                            if let ordinal = conflictOrdinals[index] {
                                conflictBlock(ordinal: ordinal, ours: ours, theirs: theirs)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(Text(.conflictTitle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.applyResolution) {
                        RevisionStore.resolveConflict(conflict, note: note, context: modelContext, choices: choices)
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private func conflictBlock(ordinal: Int, ours: [String], theirs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(.conflictBlockTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Picker(selection: Binding(
                get: { choices[ordinal] },
                set: { choices[ordinal] = $0 }
            )) {
                Text(.conflictChoiceMine).tag(ThreeWayMerge.Choice.ours)
                Text(.conflictChoiceTheirs).tag(ThreeWayMerge.Choice.theirs)
                Text(.conflictChoiceBoth).tag(ThreeWayMerge.Choice.both)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            Group {
                switch choices[ordinal] {
                case .ours: Text(ours.joined(separator: "\n"))
                case .theirs: Text(theirs.joined(separator: "\n"))
                case .both: Text((ours + theirs).joined(separator: "\n"))
                }
            }
            .font(.body.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
