//
//  SyncMonitor.swift
//  DaNotes
//

import CoreData
import Observation

/// Tracks whether CloudKit sync is currently running. SwiftData syncs
/// through `NSPersistentCloudKitContainer` under the hood, which posts an
/// event-changed notification when each setup/import/export starts (no
/// `endDate`) and again when it finishes.
@MainActor
@Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    /// Identifiers of events that have started but not yet finished.
    private var activeEventIDs: Set<UUID> = []

    var isSyncing: Bool { !activeEventIDs.isEmpty }

    private init() {
        Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            )
            for await notification in notifications {
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { continue }
                guard let self else { return }
                if event.endDate == nil {
                    self.activeEventIDs.insert(event.identifier)
                } else {
                    self.activeEventIDs.remove(event.identifier)
                }
            }
        }
    }
}
