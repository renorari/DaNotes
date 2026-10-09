//
//  HashtagParserTests.swift
//  DaNotesTests
//

import Testing
@testable import DaNotes

struct HashtagParserTests {
    @Test func parsesSimpleTag() {
        #expect(HashtagParser.parse("hello #world") == ["world"])
    }

    @Test func ignoresAtxHeadings() {
        #expect(HashtagParser.parse("# Title\ntext") == [])
    }

    @Test func ignoresTagsInFencedCodeBlocks() {
        let text = "```\n#notatag\n```\n#realtag"
        #expect(HashtagParser.parse(text) == ["realtag"])
    }

    @Test func ignoresTagsInInlineCode() {
        #expect(HashtagParser.parse("use `#notatag` here, but #realtag works") == ["realtag"])
    }

    @Test func ignoresTagsInMath() {
        #expect(HashtagParser.parse("$#notatag$ #realtag") == ["realtag"])
    }

    @Test func dedupesCaseInsensitivelyKeepingFirstCasing() {
        #expect(HashtagParser.parse("#Swift #swift #SWIFT") == ["Swift"])
    }

    @Test func stripsTrailingPunctuation() {
        #expect(HashtagParser.parse("check #this, and #that.") == ["this", "that"])
    }

    @Test func supportsJapaneseTags() {
        #expect(HashtagParser.parse("今日は #仕事 をした") == ["仕事"])
    }

    @Test func supportsNestedTagsWithSlash() {
        #expect(HashtagParser.parse("#work/project") == ["work/project"])
    }

    @Test func requiresBoundaryBeforeHash() {
        #expect(HashtagParser.parse("price#5 is not a tag") == [])
    }
}
