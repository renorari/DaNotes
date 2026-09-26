//
//  DaNotesApp.swift
//  DaNotes
//
//  Created by Renorari on 2025/07/03.
//

import SwiftUI

@main
struct DaNotesApp: App {
    var body: some Scene {
        // The app only ever edits one shared note (backed by `@AppStorage`),
        // so there is no "New Window" concept — every window would just show
        // the same note. `Window` gives exactly one window with no "New
        // Window" menu item, but it's macOS/visionOS-only; on iOS/iPadOS,
        // multi-window is instead disabled via
        // `UIApplicationSupportsMultipleScenes = NO` in the build settings.
#if os(macOS)
        Window("DaNotes", id: "main") {
            ContentView()
        }
#else
        WindowGroup {
            ContentView()
        }
#endif
    }
}
