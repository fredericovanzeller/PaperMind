// PaperMindMac/Services/OnboardingManager.swift
// PaperMind — First-Run Wizard state

import SwiftUI

class OnboardingManager: ObservableObject {
    @AppStorage("onboardingCompleted") var isCompleted: Bool = false

    func markCompleted() {
        isCompleted = true
    }

    func reset() {
        isCompleted = false
    }
}
