//
//  ThreeWayMergeTests.swift
//  DaNotesTests
//

import Testing
@testable import DaNotes

struct ThreeWayMergeTests {
    @Test func nonOverlappingChangesMergeCleanly() {
        let segments = ThreeWayMerge.merge(
            base: "line1\nline2\nline3",
            ours: "line1-edited\nline2\nline3",
            theirs: "line1\nline2\nline3-edited"
        )
        #expect(!ThreeWayMerge.hasConflict(segments))
        #expect(ThreeWayMerge.resolve(segments, choices: []) == "line1-edited\nline2\nline3-edited")
    }

    @Test func sameLineEditedDifferentlyConflicts() {
        let segments = ThreeWayMerge.merge(base: "hello\nworld", ours: "hello\nour world", theirs: "hello\ntheir world")
        #expect(ThreeWayMerge.hasConflict(segments))
        #expect(ThreeWayMerge.resolve(segments, choices: [.ours]) == "hello\nour world")
        #expect(ThreeWayMerge.resolve(segments, choices: [.theirs]) == "hello\ntheir world")
        #expect(ThreeWayMerge.resolve(segments, choices: [.both]) == "hello\nour world\ntheir world")
    }

    @Test func identicalChangeOnBothSidesIsNotAConflict() {
        let segments = ThreeWayMerge.merge(base: "a\nb", ours: "a\nb\nc", theirs: "a\nb\nc")
        #expect(!ThreeWayMerge.hasConflict(segments))
        #expect(ThreeWayMerge.resolve(segments, choices: []) == "a\nb\nc")
    }

    @Test func differentAppendsAtEndConflict() {
        let segments = ThreeWayMerge.merge(base: "a\nb", ours: "a\nb\nours-new-line", theirs: "a\nb\ntheirs-new-line")
        #expect(ThreeWayMerge.hasConflict(segments))
    }

    @Test func onlyOneSideChangedFastForwards() {
        let segments = ThreeWayMerge.merge(base: "x\ny\nz", ours: "x\ny\nz", theirs: "x\ny-changed\nz")
        #expect(!ThreeWayMerge.hasConflict(segments))
        #expect(ThreeWayMerge.resolve(segments, choices: []) == "x\ny-changed\nz")
    }

    @Test func identicalOursAndTheirsShortCircuits() {
        let segments = ThreeWayMerge.merge(base: "a", ours: "a\nb", theirs: "a\nb")
        #expect(!ThreeWayMerge.hasConflict(segments))
        #expect(ThreeWayMerge.resolve(segments, choices: []) == "a\nb")
    }
}
