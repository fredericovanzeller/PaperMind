// PaperMindMac/PaperMindApp.swift
// PaperMind — Entry point macOS

import SwiftUI

@main
struct PaperMindApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 750)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
