//
//  NavigationCoordinator.swift
//  DaNotes
//

import Foundation
import Observation

/// Bridges "open this note" requests from outside the view hierarchy — so
/// far just `OpenNoteIntent`, triggered by tapping a note in Spotlight — into
/// `NoteListView`'s selection.
@MainActor
@Observable
final class NavigationCoordinator {
    static let shared = NavigationCoordinator()
    private init() {}

    var pendingNoteID: UUID?
}
