// PaperMindMac/Views/ContentView.swift
// PaperMind — Layout principal macOS: 3 painéis

import SwiftUI

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
                    pdfURL = URL(fileURLWithPath: doc.filePath)
                }
            )
        } content: {
            // Painel central: PDF viewer com deep linking
            PDFKitView(url: pdfURL, currentPage: $currentPage)
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
        // Drop zone para arrastar PDFs
        .onDrop(of: [.pdf, .image], isTargeted: $isDragging) { providers in
            providers.forEach { provider in
                provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil)
                    {
                        Task { _ = try? await api.uploadFile(url) }
                    }
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
}
