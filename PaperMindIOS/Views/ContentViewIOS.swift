// PaperMindIOS/Views/ContentViewIOS.swift
// PaperMind iOS — Interface principal com tabs

import SwiftUI

struct ContentViewIOS: View {
    @StateObject var syncState = SyncState()
    @State var showCamera = false
    @State private var showScanSuccess = false
    @State private var scanCount = 0

    var body: some View {
        TabView {
            // Tab 1: Digitalizar
            NavigationStack {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundStyle(.teal)

                    Text("PaperMind")
                        .font(.largeTitle.bold())

                    Text("Digitaliza documentos com a camara.\nO Mac processa tudo automaticamente.")
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

                    if showScanSuccess {
                        Label(
                            scanCount == 1
                                ? "Documento enviado para o Mac"
                                : "\(scanCount) paginas enviadas para o Mac",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer()
                }
                .navigationTitle("Camara")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Camara", systemImage: "camera") }

            // Tab 2: Estado
            NavigationStack {
                StatusView(syncState: syncState)
            }
            .tabItem { Label("Estado", systemImage: "checkmark.icloud") }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { images in
                scanCount = images.count
                Task {
                    await syncState.processScans(images)
                    withAnimation {
                        showScanSuccess = true
                    }
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    withAnimation {
                        showScanSuccess = false
                    }
                }
            }
        }
        .tint(.teal)
    }
}
