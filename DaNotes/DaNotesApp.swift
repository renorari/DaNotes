//
//  DaNotesApp.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI
import SwiftData

@main
struct DaNotesApp: App {
    private let modelContainer = AppModelContainer.shared

    var body: some Scene {
        // All notes live in one sidebar, so a single window is enough. `Window`
        // gives exactly one window with no "New Window" menu item, but it's
        // macOS/visionOS-only; on iOS/iPadOS, multi-window is instead disabled
        // via `UIApplicationSupportsMultipleScenes = NO` in Info.plist.
#if os(macOS)
        Window("DaNotes", id: "main") {
            NoteListView()
        }
        .modelContainer(modelContainer)
#else
        WindowGroup {
            NoteListView()
        }
        .modelContainer(modelContainer)
#endif
    }
}
