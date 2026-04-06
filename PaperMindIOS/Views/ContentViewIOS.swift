// PaperMindIOS/Views/ContentView.swift
// PaperMind iOS — Interface principal com tabs

import SwiftUI

struct ContentViewIOS: View {
    @StateObject var syncState = SyncState()
    @State var showCamera = false

    var body: some View {
        TabView {
            // Tab 1: Câmara
            NavigationStack {
                VStack(spacing: 24) {
                    Spacer()

                    Image("papermind-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.tint)

                    Text("PaperMind")
                        .font(.largeTitle.bold())

                    Text("Digitaliza documentos com a câmara.\nO Mac processa tudo automaticamente.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        showCamera = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 64))
                            Text("Digitalizar Documento")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(20)
                    }
                    .padding(.horizontal)

                    if syncState.isProcessing {
                        ProgressView("A processar OCR...")
                            .padding()
                    }

                    Spacer()
                }
                .navigationTitle("Câmara")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Câmara", systemImage: "camera") }

            // Tab 2: Inbox (aguarda sync)
            NavigationStack {
                InboxView(syncState: syncState)
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .badge(syncState.pendingCount)

            // Tab 3: Estado da sincronização
            NavigationStack {
                StatusView(syncState: syncState)
            }
            .tabItem { Label("Estado", systemImage: "checkmark.icloud") }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { images in
                Task { await syncState.processScans(images) }
            }
        }
        .tint(.teal)
    }
}
