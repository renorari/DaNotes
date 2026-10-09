//
//  RevisionGraphTests.swift
//  DaNotesTests
//

import Testing
@testable import DaNotes

struct RevisionGraphTests {
    @Test func headsOfSingleChainIsTheLastRevision() {
        let note = Note()
        let r1 = NoteRevision(note: note, parentIDs: [], text: "a", deviceID: "d1", deviceName: "D1", kind: .initial)
        let r2 = NoteRevision(note: note, parentIDs: [r1.id], text: "b", deviceID: "d1", deviceName: "D1", kind: .auto)
        #expect(RevisionGraph.heads(of: [r1, r2]).map(\.id) == [r2.id])
    }

    @Test func headsOfDivergedBranchesAreBothTips() {
        let note = Note()
        let base = NoteRevision(note: note, parentIDs: [], text: "base", deviceID: "d1", deviceName: "D1", kind: .initial)
        let a = NoteRevision(note: note, parentIDs: [base.id], text: "a", deviceID: "d1", deviceName: "D1", kind: .auto)
        let b = NoteRevision(note: note, parentIDs: [base.id], text: "b", deviceID: "d2", deviceName: "D2", kind: .auto)
        let heads = Set(RevisionGraph.heads(of: [base, a, b]).map(\.id))
        #expect(heads == Set([a.id, b.id]))
    }

    @Test func commonAncestorFindsNearestSharedParent() {
        let note = Note()
        let root = NoteRevision(note: note, parentIDs: [], text: "root", deviceID: "d", deviceName: "D", kind: .initial)
        let mid = NoteRevision(note: note, parentIDs: [root.id], text: "mid", deviceID: "d", deviceName: "D", kind: .auto)
        let a = NoteRevision(note: note, parentIDs: [mid.id], text: "a", deviceID: "d1", deviceName: "D1", kind: .auto)
        let b = NoteRevision(note: note, parentIDs: [mid.id], text: "b", deviceID: "d2", deviceName: "D2", kind: .auto)
        let all = [root, mid, a, b]
        #expect(RevisionGraph.commonAncestor(a, b, in: all)?.id == mid.id)
    }

    @Test func commonAncestorReturnsNilWithoutSharedHistory() {
        let note = Note()
        let a = NoteRevision(note: note, parentIDs: [], text: "a", deviceID: "d1", deviceName: "D1", kind: .initial)
        let b = NoteRevision(note: note, parentIDs: [], text: "b", deviceID: "d2", deviceName: "D2", kind: .initial)
        #expect(RevisionGraph.commonAncestor(a, b, in: [a, b]) == nil)
    }
}
