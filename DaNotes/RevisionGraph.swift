//
//  RevisionGraph.swift
//  DaNotes
//

import Foundation

/// Pure graph operations over a note's `NoteRevision` DAG. Kept free of
/// SwiftData/`ModelContext` so it's trivial to unit test.
enum RevisionGraph {
    /// Revisions not referenced as a parent by any other revision — i.e. the
    /// tip(s) of the history. More than one head means two devices each
    /// committed from the same point before seeing the other's commit.
    static func heads(of revisions: [NoteRevision]) -> [NoteRevision] {
        let referenced = Set(revisions.flatMap(\.parentIDs))
        return revisions.filter { !referenced.contains($0.id) }
    }

    /// The nearest common ancestor of `a` and `b`, used as the merge base.
    /// Returns `nil` if they share no ancestor (treated as merging from an
    /// empty base).
    static func commonAncestor(_ a: NoteRevision, _ b: NoteRevision, in revisions: [NoteRevision]) -> NoteRevision? {
        let byID = Dictionary(uniqueKeysWithValues: revisions.map { ($0.id, $0) })

        func ancestorOrder(from start: NoteRevision) -> [UUID] {
            var visited: Set<UUID> = []
            var order: [UUID] = []
            var queue: [UUID] = [start.id]
            while !queue.isEmpty {
                let id = queue.removeFirst()
                guard visited.insert(id).inserted else { continue }
                order.append(id)
                if let revision = byID[id] {
                    queue.append(contentsOf: revision.parentIDs)
                }
            }
            return order
        }

        let aAncestors = ancestorOrder(from: a)
        let bAncestors = Set(ancestorOrder(from: b))
        guard let commonID = aAncestors.first(where: bAncestors.contains) else { return nil }
        return byID[commonID]
    }
}
