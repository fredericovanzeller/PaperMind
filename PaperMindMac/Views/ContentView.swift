// PaperMindMac/Views/ContentView.swift
// PaperMind — Layout principal macOS: 3 painéis

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var backendManager: BackendManager
    @StateObject private var api = APIClient()
    @StateObject private var catManager = CategoryManager()
    @State private var selectedDocument: DocumentInfo?
    @State private var pdfData: Data?
    @State private var pdfDocName: String = ""
    @State private var currentPage: Int = 0
    @State private var messages: [ChatMessage] = []
    @State private var isBackendReady = false
    @State private var isDragging = false
    @State private var refreshTrigger = UUID()
    @State private var isUploading = false
    @State private var uploadStatusMessage = ""
    @State private var uploadedFileNames: [String] = []
    @State private var uploadErrors: [String] = []
    @State private var showUploadDone = false
    @State private var showUploadError = false

    var body: some View {
        NavigationSplitView {
            // Painel esquerdo: documentos indexados
            SidebarView(
                api: api,
                categoryManager: catManager,
                selectedDocument: $selectedDocument,
                refreshTrigger: refreshTrigger,
                onSelect: { doc in
                    currentPage = 0
                    Task {
                        do {
                            let data = try await api.getPDFData(filename: doc.filename)
                            pdfData = data
                            pdfDocName = doc.filename
                        } catch {
                            print("ERROR loading PDF: \(error)")
                        }
                    }
                },
                onDelete: { _ in
                    pdfData = nil
                    pdfDocName = ""
                    currentPage = 0
                }
            )
        } content: {
            // Painel central: PDF viewer com deep linking
            Group {
                if let data = pdfData {
                    PDFKitView(pdfData: data, currentPage: $currentPage)
                        .id(pdfDocName)
                } else {
                    ContentUnavailableView(
                        "Nenhum documento selecionado",
                        systemImage: "doc.text",
                        description: Text("Seleciona um documento na barra lateral")
                    )
                }
            }
        } detail: {
            // Painel direito: chat com o LLM
            ChatView(api: api, messages: $messages) { filename, page in
                // Deep linking: clicar numa fonte abre a página no PDF
                currentPage = page
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Adicionar documento (⌘U)")
                .keyboardShortcut("u", modifiers: .command)
            }
            ToolbarItem(placement: .status) {
                if !isBackendReady {
                    HStack(spacing: 6) {
                        if backendManager.isRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("A iniciar backend...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Backend offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        // Drop zone para arrastar PDFs
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    guard let data = data,
                          let path = String(data: data, encoding: .utf8),
                          let url = URL(string: path.trimmingCharacters(in: .whitespacesAndNewlines))
                    else { return }
                    Task { await uploadFiles([url]) }
                }
            }
            return true
        }
        .overlay {
            if isDragging {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.05))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 40))
                            Text("Largar para indexar")
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding()
            }
        }
        // Upload progress overlay
        .overlay {
            if isUploading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text(uploadStatusMessage)
                                .font(.headline)
                            Text("Isto pode demorar alguns segundos...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(32)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
            }
        }
        .alert("Upload concluído", isPresented: $showUploadDone) {
            Button("OK") { }
        } message: {
            if uploadedFileNames.count == 1 {
                Text("\"\(uploadedFileNames.first ?? "")\" foi indexado com sucesso.")
            } else {
                Text("\(uploadedFileNames.count) documentos indexados com sucesso.")
            }
        }
        .alert("Erro no upload", isPresented: $showUploadError) {
            Button("OK") { }
        } message: {
            Text(uploadErrors.joined(separator: "\n"))
        }
        .task {
            // Fast poll (1s) until backend responds, then slow poll (30s) to detect disconnects
            while !Task.isCancelled {
                await api.checkHealth()
                isBackendReady = api.isBackendAvailable
                let interval: UInt64 = isBackendReady ? 30_000_000_000 : 1_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Adicionar documento"
        panel.allowedContentTypes = [.pdf, .jpeg, .png]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        Task { await uploadFiles(panel.urls) }
    }

    private func uploadFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        await MainActor.run {
            isUploading = true
            uploadedFileNames = []
            uploadErrors = []
            uploadStatusMessage = urls.count == 1
                ? "A indexar \(urls.first!.lastPathComponent)..."
                : "A indexar \(urls.count) documentos..."
        }

        for (index, url) in urls.enumerated() {
            await MainActor.run {
                if urls.count > 1 {
                    uploadStatusMessage = "A indexar \(index + 1) de \(urls.count): \(url.lastPathComponent)..."
                }
            }
            do {
                let result = try await api.uploadFile(url)
                if result.status == "success" {
                    await MainActor.run { uploadedFileNames.append(result.filename) }
                } else {
                    let errorMsg = result.error ?? "Erro desconhecido"
                    await MainActor.run { uploadErrors.append("\(url.lastPathComponent): \(errorMsg)") }
                }
            } catch {
                await MainActor.run { uploadErrors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }

        // Brief pause for backend to finalize indexing
        await MainActor.run { uploadStatusMessage = "A finalizar..." }
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await MainActor.run {
            isUploading = false
            refreshTrigger = UUID()
            if !uploadedFileNames.isEmpty {
                showUploadDone = true
            } else if !uploadErrors.isEmpty {
                showUploadError = true
            }
        }
    }
}
