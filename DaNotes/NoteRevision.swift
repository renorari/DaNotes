//
//  NoteRevision.swift
//  DaNotes
//

import Foundation
import SwiftData

/// An immutable snapshot of a note's text, forming a git-like DAG via
/// `parentIDs`. Revisions are never mutated after creation, so CloudKit
/// syncing them is just additive — unlike `Note.text`, they can never
/// conflict with each other, which is what lets `RevisionStore` rebuild a
/// consistent merge from whatever revisions each device has created.
@Model
final class NoteRevision {
    enum Kind: String, Codable {
        /// The first revision recorded for a note that predates this feature.
        case initial
        /// A periodic snapshot taken while editing.
        case auto
        /// Produced by folding multiple heads back into one.
        case merge
        /// Produced by reverting to an earlier revision's text.
        case restore
    }

    var id: UUID = UUID()
    var note: Note?
    /// IDs of the revision(s) this one was created from. Empty for the very
    /// first revision of a note.
    var parentIDs: [UUID] = []
    var text: String = ""
    var createdAt: Date = Date()
    /// Identifies the device that created this revision — not personal
    /// information, just a locally-generated UUID (see `DeviceIdentity`).
    var deviceID: String = ""
    var deviceName: String = ""
    private var kindRaw: String = Kind.auto.rawValue

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .auto }
        set { kindRaw = newValue.rawValue }
    }

    init(note: Note, parentIDs: [UUID], text: String, deviceID: String, deviceName: String, kind: Kind) {
        self.note = note
        self.parentIDs = parentIDs
        self.text = text
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.kindRaw = kind.rawValue
    }
}
