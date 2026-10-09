//
//  AppModelContainer.swift
//  DaNotes
//

import SwiftData

/// The single `ModelContainer` shared by the SwiftUI app and by code that
/// runs outside the view hierarchy — currently the App Intents entity query,
/// which needs to fetch notes without going through the SwiftUI environment.
enum AppModelContainer {
    // Synced through the CloudKit container in the app's entitlements; without
    // an iCloud account the store simply stays local.
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: Note.self, NoteAttachment.self, NoteRevision.self,
                configurations: ModelConfiguration(cloudKitDatabase: .automatic)
            )
        } catch {
            fatalError("Failed to create the model container: \(error)")
        }
    }()
}
