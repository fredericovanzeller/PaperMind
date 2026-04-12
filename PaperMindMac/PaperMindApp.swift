// PaperMindMac/PaperMindApp.swift
// PaperMind — Entry point macOS

import SwiftUI

@main
struct PaperMindApp: App {
    @StateObject private var backendManager = BackendManager()
    @StateObject private var onboarding = OnboardingManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarding.isCompleted {
                    ContentView()
                        .environmentObject(backendManager)
                        .onAppear {
                            backendManager.start()
                        }
                } else {
                    OnboardingView {
                        onboarding.markCompleted()
                        backendManager.start()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                backendManager.stop()
            }
        }
        .defaultSize(width: 1200, height: 750)

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(backendManager)
        }
        #endif
    }
}
