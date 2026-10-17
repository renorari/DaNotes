//
//  AppModelContainer.swift
//  DaNotes
//

import CoreData
import SwiftData

/// The single `ModelContainer` shared by the SwiftUI app and by code that
/// runs outside the view hierarchy — currently the App Intents entity query,
/// which needs to fetch notes without going through the SwiftUI environment.
enum AppModelContainer {
    private static let cloudKitContainerIdentifier = "iCloud.net.renorari.apps.DaNotes"

    // Synced through the CloudKit container in the app's entitlements; without
    // an iCloud account the store simply stays local.
    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(cloudKitDatabase: .automatic)
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
                try initializeCloudKitSchema(storeURL: configuration.url)
            }
#endif
            return try ModelContainer(
                for: Note.self, NoteAttachment.self, NoteRevision.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create the model container: \(error)")
        }
    }()

#if DEBUG
    /// Creates every record type and field in the CloudKit *development*
    /// schema, ready to deploy to production from CloudKit Console. Production
    /// never creates types on demand, so TestFlight/App Store builds can't sync
    /// until this has been done for the current model. It blocks other CloudKit
    /// work while running, so it's opt-in via the `-InitializeCloudKitSchema`
    /// launch argument rather than run on every debug launch.
    private static func initializeCloudKitSchema(storeURL: URL) throws {
        try autoreleasepool {
            let description = NSPersistentStoreDescription(url: storeURL)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
            description.shouldAddStoreAsynchronously = false
            guard let model = NSManagedObjectModel.makeManagedObjectModel(
                for: [Note.self, NoteAttachment.self, NoteRevision.self]
            ) else { return }

            let container = NSPersistentCloudKitContainer(name: "DaNotes", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }

            try container.initializeCloudKitSchema()
            // Unload before SwiftData opens the same store, so the two stacks
            // don't both try to sync it.
            if let store = container.persistentStoreCoordinator.persistentStores.first {
                try container.persistentStoreCoordinator.remove(store)
            }
        }
    }
#endif
}
