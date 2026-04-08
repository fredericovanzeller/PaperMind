// PaperMindMac/Views/SidebarView.swift
// PaperMind — Barra lateral com documentos indexados

import SwiftUI

struct SidebarView: View {
    @ObservedObject var api: APIClient
    @Binding var selectedDocument: DocumentInfo?
    var onSelect: (DocumentInfo) -> Void
    var onDelete: (DocumentInfo) -> Void

    @State private var documents: [DocumentInfo] = []
    @State private var searchText = ""
    @State private var docToDelete: DocumentInfo?
    @State private var showDeleteConfirm = false

    var filteredDocuments: [DocumentInfo] {
        if searchText.isEmpty {
            return documents
        }
        return documents.filter {
            $0.filename.localizedCaseInsensitiveContains(searchText)
            || $0.documentType.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filteredDocuments, selection: $selectedDocument) { doc in
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.filename)
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Label(doc.documentType, systemImage: iconFor(doc.documentType))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(doc.totalChunks) chunks")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .tag(doc)
            .onTapGesture {
                selectedDocument = doc
                onSelect(doc)
            }
            .contextMenu {
                Button(role: .destructive) {
                    docToDelete = doc
                    showDeleteConfirm = true
                } label: {
                    Label("Apagar documento", systemImage: "trash")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Procurar documentos...")
        .navigationTitle("Documentos")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await refreshDocuments() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView(
                    "Sem documentos",
                    systemImage: "doc.badge.plus",
                    description: Text("Arrasta um PDF ou usa ⌘U")
                )
            }
        }
        .task {
            await refreshDocuments()
        }
        .alert("Apagar documento?", isPresented: $showDeleteConfirm) {
            Button("Cancelar", role: .cancel) {
                docToDelete = nil
            }
            Button("Apagar", role: .destructive) {
                if let doc = docToDelete {
                    Task { await deleteDocument(doc) }
                }
            }
        } message: {
            if let doc = docToDelete {
                Text("O documento \"\(doc.filename)\" será removido do índice e apagado.")
            }
        }
    }

    private func deleteDocument(_ doc: DocumentInfo) async {
        do {
            try await api.deleteDocument(doc.filename)
            documents.removeAll { $0.filename == doc.filename }

            // Clear selection and notify parent if the deleted doc was selected
            if selectedDocument?.filename == doc.filename {
                selectedDocument = nil
                onDelete(doc)
            }
        } catch {
            print("Erro ao apagar: \(error.localizedDescription)")
        }
        docToDelete = nil
    }

    private func refreshDocuments() async {
        documents = (try? await api.getDocuments()) ?? []
    }

    private func iconFor(_ type: String) -> String {
        switch type.lowercased() {
        case "contrato": return "signature"
        case "fatura": return "eurosign.circle"
        case "recibo": return "receipt"
        case "carta": return "envelope"
        case "relatorio": return "chart.bar.doc.horizontal"
        case "identificacao": return "person.text.rectangle"
        default: return "doc"
        }
    }
}
