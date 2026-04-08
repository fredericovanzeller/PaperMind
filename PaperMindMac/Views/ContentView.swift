// PaperMindMac/Views/ContentView.swift
// PaperMind — Layout principal macOS: 3 painéis

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @StateObject private var api = APIClient()
    @State private var selectedDocument: DocumentInfo?
    @State private var pdfURL: URL?
    @State private var currentPage: Int = 0
    @State private var messages: [ChatMessage] = []
    @State private var isBackendReady = false
    @State private var isDragging = false

    var body: some View {
        NavigationSplitView {
            // Painel esquerdo: documentos indexados
            SidebarView(
                api: api,
                selectedDocument: $selectedDocument,
                onSelect: { doc in
                    currentPage = 0
                    pdfURL = URL(fileURLWithPath: doc.filePath)
                },
                onDelete: { _ in
                    pdfURL = nil
                    currentPage = 0
                }
            )
        } content: {
            // Painel central: PDF viewer com deep linking
            PDFKitView(url: pdfURL, currentPage: $currentPage)
                .id(pdfURL)
                .overlay {
                    if pdfURL == nil {
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
        }
        // Drop zone para arrastar PDFs
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            print("DEBUG: drop received, \(providers.count) providers")
            for provider in providers {
                print("DEBUG: provider types: \(provider.registeredTypeIdentifiers)")
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    print("DEBUG: data=\(data?.count ?? -1) error=\(String(describing: error))")
                    guard let data = data,
                          let path = String(data: data, encoding: .utf8),
                          let url = URL(string: path.trimmingCharacters(in: .whitespacesAndNewlines))
                    else { return }
                    print("DEBUG: uploading \(url)")
                    Task { _ = try? await api.uploadFile(url) }
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
        .task {
            await api.checkHealth()
            isBackendReady = api.isBackendAvailable
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

        for url in panel.urls {
            Task { _ = try? await api.uploadFile(url) }
        }
    }
}
