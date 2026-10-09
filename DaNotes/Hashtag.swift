//
//  Hashtag.swift
//  DaNotes
//

import Foundation

/// Parses Bear-style `#tag` hashtags out of a note's Markdown body, so tags
/// need no separate storage and travel for free through editing, sync, and
/// version history.
enum HashtagParser {
    /// Returns the tags referenced in `text`, in order of first appearance,
    /// deduplicated case-insensitively (keeping the first casing seen).
    ///
    /// A hashtag is a run of non-whitespace characters (other than `#`)
    /// immediately after a `#` that starts a line or follows whitespace.
    /// `# Title` (ATX heading syntax, which requires a space after `#`) is
    /// never matched. Fenced code blocks, inline code spans, and `$…$`/`$$…$$`
    /// math are skipped, mirroring `OutlineItem.parse`'s fence handling.
    static func parse(_ text: String) -> [String] {
        var tags: [String] = []
        var seenLowercased: Set<String> = []
        var fence: String?
        var inMathBlock = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count

            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if indent < 4 {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    fence = String(trimmed.prefix(3))
                    continue
                }
                if trimmed.hasPrefix("$$") {
                    inMathBlock.toggle()
                    continue
                }
            }
            if inMathBlock { continue }

            for tag in hashtags(in: stripInlineCodeAndMath(line)) {
                let key = tag.lowercased()
                guard !seenLowercased.contains(key) else { continue }
                seenLowercased.insert(key)
                tags.append(tag)
            }
        }
        return tags
    }

    /// Blanks out inline code spans (`` `…` ``) and inline math (`$…$`) so
    /// hashtags inside them are never matched, while preserving every other
    /// character's position.
    private static func stripInlineCodeAndMath(_ line: String) -> String {
        var chars = Array(line)
        for delimiter: Character in ["`", "$"] {
            var openIndex: Int?
            for i in chars.indices where chars[i] == delimiter {
                if let start = openIndex {
                    for j in start...i { chars[j] = " " }
                    openIndex = nil
                } else {
                    openIndex = i
                }
            }
        }
        return String(chars)
    }

    private static let trailingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}、。!?」』】,")

    private static func hashtags(in line: String) -> [String] {
        var results: [String] = []
        var previousWasBoundary = true
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "#", previousWasBoundary {
                var j = line.index(after: i)
                var raw = ""
                while j < line.endIndex, !line[j].isWhitespace, line[j] != "#" {
                    raw.append(line[j])
                    j = line.index(after: j)
                }
                let tag = raw.trimmingCharacters(in: trailingPunctuation)
                if !tag.isEmpty {
                    results.append(tag)
                }
                previousWasBoundary = false
                i = j
                continue
            }
            previousWasBoundary = c.isWhitespace
            i = line.index(after: i)
        }
        return results
    }
}
