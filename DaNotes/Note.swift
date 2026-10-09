//
//  Note.swift
//  DaNotes
//

import Foundation
import SwiftData

// CloudKit-backed SwiftData models: every stored property needs a default
// value (or must be optional), relationships must be optional, and
// `@Attribute(.unique)` is not allowed.

@Model
final class Note {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isPinned: Bool = false
    /// Updated when the note is selected in the sidebar, independent of `modifiedAt`.
    var lastOpenedAt: Date? = nil
    @Relationship(deleteRule: .cascade, inverse: \NoteAttachment.note)
    var attachments: [NoteAttachment]? = []
    @Relationship(deleteRule: .cascade, inverse: \NoteRevision.note)
    var revisions: [NoteRevision]? = []

    init(text: String = "") {
        self.text = text
    }

    /// `#tags` found in the note's text (see `HashtagParser`).
    var tags: [String] {
        HashtagParser.parse(text)
    }

    /// Whether this note has no content worth keeping (no text, no images),
    /// so it can be discarded automatically instead of cluttering the list.
    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (attachments?.isEmpty ?? true)
    }

    /// The text of the first level-1 Markdown heading (`# Title`), or nil
    /// when the note has none.
    var headingTitle: String? {
        outline.first { $0.level == 1 && !$0.title.isEmpty }?.title
    }

    var outline: [OutlineItem] {
        OutlineItem.parse(text)
    }

    var displayTitle: String {
        headingTitle ?? String(localized: "untitledNote")
    }
}

@Model
final class NoteAttachment {
    /// `UUID.ext` — the name the note's Markdown references the image by.
    var fileName: String = ""
    @Attribute(.externalStorage) var data: Data?
    var note: Note?

    init(fileName: String, data: Data, note: Note) {
        self.fileName = fileName
        self.data = data
        self.note = note
    }
}

// MARK: - Outline

/// A top-level Markdown heading of a note.
struct OutlineItem: Identifiable, Hashable {
    /// Position among the note's top-level headings; matches the order of
    /// the `<h1>`–`<h6>` elements directly under the preview's `#content`.
    let index: Int
    let level: Int
    let title: String
    /// UTF-16 offset of the heading line's start in the note text.
    let location: Int

    var id: Int { index }

    /// Collects ATX (`## Title`) and setext (`Title` + `===`/`---`) headings,
    /// skipping fenced code blocks. Headings nested in quotes or lists are
    /// ignored, as they are in the preview's heading lookup.
    static func parse(_ text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var fence: String?
        var location = 0
        var previous: (line: String, location: Int)?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let lineLocation = location
            location += line.utf16.count + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count

            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                previous = nil
                continue
            }
            guard indent < 4 else {
                previous = nil
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                previous = nil
                continue
            }
            if let (level, title) = atxHeading(trimmed) {
                items.append(OutlineItem(index: items.count, level: level, title: title, location: lineLocation))
                previous = nil
                continue
            }
            if let paragraph = previous, let level = setextLevel(trimmed) {
                items.append(OutlineItem(index: items.count, level: level, title: paragraph.line, location: paragraph.location))
                previous = nil
                continue
            }
            previous = isParagraphLine(trimmed) ? (trimmed, lineLocation) : nil
        }
        return items
    }

    private static func atxHeading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing sequence: `# Title ##` (needs a space before it,
        // so `# C#` keeps its `#`).
        if let range = title.range(of: #"(^|\s)#+$"#, options: .regularExpression) {
            title = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return (hashes, title)
    }

    private static func setextLevel(_ line: String) -> Int? {
        guard let first = line.first, first == "=" || first == "-",
              line.allSatisfy({ $0 == first }) else { return nil }
        return first == "=" ? 1 : 2
    }

    /// Whether a line can be the text of a setext heading: not blank and not
    /// the start of some other block (list, quote, table, math, HTML).
    private static func isParagraphLine(_ line: String) -> Bool {
        !line.isEmpty && line.range(of: #"^([-*+>|<]|\d+[.)]|\$\$)"#, options: .regularExpression) == nil
    }
}

/// A request to scroll the editor and preview to an outline heading. Each
/// tap gets a new `id`, so tapping the same heading again still scrolls.
struct OutlineJump: Equatable {
    let id = UUID()
    let item: OutlineItem
}

// MARK: - Attachment storage

@MainActor
struct ImageAttachmentStore {
    let context: ModelContext

    /// Stores image data as an attachment of `note` and returns the file name
    /// to reference from Markdown.
    func store(_ data: Data, fileExtension: String, in note: Note) -> String {
        let normalizedExtension = fileExtension.lowercased()
        let fileName = normalizedExtension.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(normalizedExtension)"
        context.insert(NoteAttachment(fileName: fileName, data: data, note: note))
        return fileName
    }

    func storeCopiedImage(from sourceURL: URL, in note: Note) throws -> String {
        let data = try Data(contentsOf: sourceURL)
        return store(data, fileExtension: sourceURL.pathExtension, in: note)
    }

    func attachment(named fileName: String) -> NoteAttachment? {
        var descriptor = FetchDescriptor<NoteAttachment>(predicate: #Predicate { $0.fileName == fileName })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func data(named fileName: String) -> Data? {
        attachment(named: fileName)?.data
    }
}

// MARK: - Legacy single-note migration

/// Moves the pre-multi-note content (`@AppStorage("text")` plus the flat
/// Application Support attachments folder) into a SwiftData `Note`, once.
@MainActor
enum LegacyNoteMigrator {
    private static let textKey = "text"
    private static let migratedKey = "DidMigrateLegacyNote"

    static func migrateIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }

        let fileManager = FileManager.default
        let legacyAttachmentsURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DaNotes", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)

        let text = defaults.string(forKey: textKey) ?? ""
        if !text.isEmpty {
            let note = Note(text: text)
            context.insert(note)
            if let legacyAttachmentsURL,
               let urls = try? fileManager.contentsOfDirectory(at: legacyAttachmentsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for url in urls {
                    guard let data = try? Data(contentsOf: url) else { continue }
                    context.insert(NoteAttachment(fileName: url.lastPathComponent, data: data, note: note))
                }
            }
        }

        do {
            try context.save()
        } catch {
            // Leave the legacy data in place so the next launch can retry.
            return
        }
        defaults.set(true, forKey: migratedKey)
        defaults.removeObject(forKey: textKey)
        if let legacyAttachmentsURL {
            try? fileManager.removeItem(at: legacyAttachmentsURL)
        }
    }
}
