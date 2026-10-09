//
//  ThreeWayMerge.swift
//  DaNotes
//

import Foundation

/// Line-based three-way merge ("diff3"), implemented as two ordinary 2-way
/// diffs (`ours` vs `base`, `theirs` vs `base`) synchronized at the lines
/// left unchanged by *both* sides. Between two such anchors, a hunk is:
/// - identical on both sides → stable (even if both sides changed it the
///   same way — not treated as a conflict)
/// - changed on exactly one side → stable, taking that side's text
/// - changed differently on both sides → a conflict
enum ThreeWayMerge {
    enum Segment: Equatable {
        case stable([String])
        case conflict(base: [String], ours: [String], theirs: [String])
    }

    enum Choice: Hashable {
        case ours
        case theirs
        case both
    }

    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    static func join(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    static func hasConflict(_ segments: [Segment]) -> Bool {
        segments.contains { if case .conflict = $0 { return true } else { return false } }
    }

    /// Merges `ours` and `theirs`, both derived from `base`.
    static func merge(base: String, ours: String, theirs: String) -> [Segment] {
        let baseLines = lines(base)
        let oursLines = lines(ours)
        let theirsLines = lines(theirs)

        if oursLines == theirsLines {
            return [.stable(oursLines)]
        }

        // For each base line not removed on a given side, the index (in that
        // side) of the corresponding line — lines are matched in order, so
        // this also tells us the range "between" any two matched lines.
        let matchedOurs = matchedIndices(from: baseLines, to: oursLines)
        let matchedTheirs = matchedIndices(from: baseLines, to: theirsLines)
        // Anchors: base lines left untouched by *both* sides. Guaranteed
        // identical to the corresponding ours/theirs line, since diffing
        // only removes elements that differ.
        let anchors = baseLines.indices.filter { matchedOurs[$0] != nil && matchedTheirs[$0] != nil }

        var segments: [Segment] = []
        var prevBase = -1
        var prevOurs = -1
        var prevTheirs = -1

        func flushHunk(upToBase nextBase: Int, ours nextOurs: Int, theirs nextTheirs: Int) {
            let baseSlice = Array(baseLines[(prevBase + 1)..<nextBase])
            let oursSlice = Array(oursLines[(prevOurs + 1)..<nextOurs])
            let theirsSlice = Array(theirsLines[(prevTheirs + 1)..<nextTheirs])
            guard !(baseSlice.isEmpty && oursSlice.isEmpty && theirsSlice.isEmpty) else { return }
            if oursSlice == theirsSlice {
                segments.append(.stable(oursSlice))
            } else if oursSlice == baseSlice {
                segments.append(.stable(theirsSlice))
            } else if theirsSlice == baseSlice {
                segments.append(.stable(oursSlice))
            } else {
                segments.append(.conflict(base: baseSlice, ours: oursSlice, theirs: theirsSlice))
            }
        }

        for anchor in anchors {
            let oursIndex = matchedOurs[anchor]!
            let theirsIndex = matchedTheirs[anchor]!
            flushHunk(upToBase: anchor, ours: oursIndex, theirs: theirsIndex)
            segments.append(.stable([baseLines[anchor]]))
            prevBase = anchor
            prevOurs = oursIndex
            prevTheirs = theirsIndex
        }
        flushHunk(upToBase: baseLines.count, ours: oursLines.count, theirs: theirsLines.count)

        return mergeAdjacentStable(segments)
    }

    /// Reconstructs the merged text, resolving each `.conflict` segment in
    /// order using `choices` (defaulting to `.ours` for any conflict past
    /// the end of `choices`).
    static func resolve(_ segments: [Segment], choices: [Choice]) -> String {
        var result: [String] = []
        var conflictIndex = 0
        for segment in segments {
            switch segment {
            case .stable(let lines):
                result.append(contentsOf: lines)
            case .conflict(_, let ours, let theirs):
                let choice = conflictIndex < choices.count ? choices[conflictIndex] : .ours
                switch choice {
                case .ours: result.append(contentsOf: ours)
                case .theirs: result.append(contentsOf: theirs)
                case .both: result.append(contentsOf: ours + theirs)
                }
                conflictIndex += 1
            }
        }
        return join(result)
    }

    private static func mergeAdjacentStable(_ segments: [Segment]) -> [Segment] {
        var result: [Segment] = []
        for segment in segments {
            if case .stable(let lines) = segment, case .stable(let previous) = result.last {
                result[result.count - 1] = .stable(previous + lines)
            } else {
                result.append(segment)
            }
        }
        return result
    }

    /// Maps each `base` index *not* removed in `target` to its index in
    /// `target`, preserving order — the two line up exactly because a 2-way
    /// diff only ever removes non-matching elements.
    private static func matchedIndices(from base: [String], to target: [String]) -> [Int: Int] {
        let diff = target.difference(from: base)
        var removedBase: Set<Int> = []
        var insertedTarget: Set<Int> = []
        for change in diff {
            switch change {
            case .remove(let offset, _, _):
                removedBase.insert(offset)
            case .insert(let offset, _, _):
                insertedTarget.insert(offset)
            }
        }
        var mapping: [Int: Int] = [:]
        var targetIndex = 0
        for baseIndex in base.indices {
            if removedBase.contains(baseIndex) { continue }
            while insertedTarget.contains(targetIndex) { targetIndex += 1 }
            mapping[baseIndex] = targetIndex
            targetIndex += 1
        }
        return mapping
    }
}
