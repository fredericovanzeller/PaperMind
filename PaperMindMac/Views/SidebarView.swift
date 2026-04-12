// PaperMindMac/Views/SidebarView.swift
// PaperMind — Barra lateral com documentos agrupados por categoria (built-in + custom)

import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var api: APIClient
    @ObservedObject var categoryManager: CategoryManager
    @Binding var selectedDocument: DocumentInfo?
    var refreshTrigger: UUID
    var onSelect: (DocumentInfo) -> Void
    var onDelete: (DocumentInfo) -> Void

    @State private var documents: [DocumentInfo] = []
    @State private var searchText = ""
    @State private var docToDelete: DocumentInfo?
    @State private var showDeleteConfirm = false
    @State private var isLoading = true
    @State private var showNewCategory = false
    @State private var showReclassifyConfirm = false
    @State private var reclassifyResult: String?
    @State private var showReclassifyDone = false

    var filteredDocuments: [DocumentInfo] {
        if searchText.isEmpty {
            return documents
        }
        return documents.filter {
            $0.filename.localizedCaseInsensitiveContains(searchText)
            || $0.documentType.localizedCaseInsensitiveContains(searchText)
            || categoryManager.category(for: $0.documentType).displayName
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Groups documents by category, following the category list order
    var groupedDocuments: [(CategoryInfo, [DocumentInfo])] {
        let grouped = Dictionary(grouping: filteredDocuments) { doc in
            categoryManager.category(for: doc.documentType).name
        }
        return categoryManager.categories.compactMap { cat in
            guard let docs = grouped[cat.name], !docs.isEmpty else { return nil }
            let sorted = docs.sorted {
                $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
            }
            return (cat, sorted)
        }
    }

    var body: some View {
        List(selection: $selectedDocument) {
            ForEach(groupedDocuments, id: \.0.name) { category, docs in
                Section {
                    ForEach(docs) { doc in
                        let cat = categoryManager.category(for: doc.documentType)
                        DocumentRow(doc: doc, cat: cat)
                            .tag(doc)
                            .contextMenu {
                                categoryContextMenu(for: doc)

                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting(
                                        [URL(fileURLWithPath: doc.filePath)]
                                    )
                                } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    docToDelete = doc
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Apagar documento", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .foregroundStyle(category.swiftColor)
                            .font(.caption)
                        Text(category.displayName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(docs.count)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Procurar documentos...")
        .onChange(of: selectedDocument) { _, newDoc in
            if let doc = newDoc {
                onSelect(doc)
            }
        }
        .navigationTitle("Documentos")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button {
                        showNewCategory = true
                    } label: {
                        Label("Nova categoria", systemImage: "plus.circle")
                    }

                    // Delete custom categories submenu
                    let customCats = categoryManager.categories.filter { !$0.isBuiltIn }
                    if !customCats.isEmpty {
                        Menu {
                            ForEach(customCats) { cat in
                                Button(role: .destructive) {
                                    Task {
                                        try? await categoryManager.deleteCategory(api: api, name: cat.name)
                                        await refreshDocuments()
                                    }
                                } label: {
                                    Label(cat.displayName, systemImage: cat.icon)
                                }
                            }
                        } label: {
                            Label("Apagar categoria", systemImage: "minus.circle")
                        }
                    }

                    Divider()

                    Button {
                        showReclassifyConfirm = true
                    } label: {
                        Label("Reclassificar tudo", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(documents.isEmpty || categoryManager.isReclassifying)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }

                Button {
                    Task { await refreshDocuments() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .overlay {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("A carregar documentos...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if documents.isEmpty {
                ContentUnavailableView(
                    "Sem documentos",
                    systemImage: "doc.badge.plus",
                    description: Text("Arrasta um PDF ou usa ⌘U")
                )
            }
        }
        .overlay {
            if categoryManager.isReclassifying {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text("A reclassificar documentos...")
                                .font(.headline)
                            Text("Isto pode demorar — o LLM analisa cada documento.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(32)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await categoryManager.refresh(api: api)
            await refreshDocuments()
        }
        .onAppear {
            Task {
                await categoryManager.refresh(api: api)
                await refreshDocuments()
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            Task { await refreshDocuments() }
        }
        .alert("Apagar documento?", isPresented: $showDeleteConfirm) {
            Button("Cancelar", role: .cancel) { docToDelete = nil }
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
        .alert("Reclassificar todos?", isPresented: $showReclassifyConfirm) {
            Button("Cancelar", role: .cancel) { }
            Button("Reclassificar") {
                Task {
                    let result = await categoryManager.reclassifyAll(api: api)
                    reclassifyResult = "\(result.changed) de \(result.total) documentos reclassificados."
                    showReclassifyDone = true
                    await refreshDocuments()
                }
            }
        } message: {
            Text("O LLM vai analisar todos os documentos e atribuir a melhor categoria. Isto pode demorar.")
        }
        .alert("Reclassificação concluída", isPresented: $showReclassifyDone) {
            Button("OK") { }
        } message: {
            Text(reclassifyResult ?? "")
        }
        .sheet(isPresented: $showNewCategory) {
            NewCategorySheet(api: api, categoryManager: categoryManager) {
                Task { await refreshDocuments() }
            }
        }
    }

    // MARK: - Context Menu for Category Change

    @ViewBuilder
    private func categoryContextMenu(for doc: DocumentInfo) -> some View {
        Menu {
            ForEach(categoryManager.categories) { cat in
                Button {
                    Task { await updateCategory(doc: doc, to: cat.name) }
                } label: {
                    HStack {
                        Image(systemName: cat.icon)
                        Text(cat.displayName)
                        if doc.documentType.lowercased() == cat.name {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(doc.documentType.lowercased() == cat.name)
            }
        } label: {
            Label("Alterar categoria", systemImage: "tag")
        }
    }

    // MARK: - Document Row

    @ViewBuilder
    private func DocumentRow(doc: DocumentInfo, cat: CategoryInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(doc.filename)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Image(systemName: cat.icon)
                    .font(.caption2)
                    .foregroundStyle(cat.swiftColor)
                Text(cat.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(doc.totalChunks) chunks")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func deleteDocument(_ doc: DocumentInfo) async {
        do {
            try await api.deleteDocument(doc.filename)
            documents.removeAll { $0.filename == doc.filename }

            if selectedDocument?.filename == doc.filename {
                selectedDocument = nil
                onDelete(doc)
            }
        } catch {
            print("Erro ao apagar: \(error.localizedDescription)")
        }
        docToDelete = nil
    }

    private func updateCategory(doc: DocumentInfo, to categoryName: String) async {
        do {
            try await categoryManager.updateDocumentCategory(api: api, filename: doc.filename, categoryName: categoryName)
            await refreshDocuments()
        } catch {
            print("Erro ao atualizar categoria: \(error.localizedDescription)")
        }
    }

    private func refreshDocuments() async {
        documents = (try? await api.getDocuments()) ?? []
        isLoading = false
    }
}

// MARK: - New Category Sheet

struct NewCategorySheet: View {
    let api: APIClient
    @ObservedObject var categoryManager: CategoryManager
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var displayName = ""
    @State private var description = ""
    @State private var selectedIcon = "tag.fill"
    @State private var selectedColor = "purple"
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Nova Categoria")
                    .font(.headline)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            Form {
                Section("Informação") {
                    TextField("Nome (ex: Educação)", text: $displayName)
                        .onChange(of: displayName) { _, newValue in
                            if name.isEmpty || name == slugify(String(displayName.dropLast())) {
                                name = slugify(newValue)
                            }
                        }

                    TextField("Descrição (ajuda o LLM a classificar)", text: $description)
                        .lineLimit(2)
                }

                Section("Ícone") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 8) {
                        ForEach(CategoryManager.availableIcons, id: \.name) { iconInfo in
                            Button {
                                selectedIcon = iconInfo.name
                            } label: {
                                Image(systemName: iconInfo.name)
                                    .font(.title3)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        selectedIcon == iconInfo.name
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(iconInfo.display)
                        }
                    }
                }

                Section("Cor") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 4), spacing: 8) {
                        ForEach(CategoryManager.availableColors, id: \.name) { colorInfo in
                            Button {
                                selectedColor = colorInfo.name
                            } label: {
                                Circle()
                                    .fill(colorInfo.color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if selectedColor == colorInfo.name {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(colorInfo.display)
                        }
                    }
                }

                // Preview
                Section("Pré-visualização") {
                    HStack(spacing: 8) {
                        Image(systemName: selectedIcon)
                            .foregroundStyle(colorFor(selectedColor))
                        Text(displayName.isEmpty ? "Nova Categoria" : displayName)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Criar Categoria") {
                    Task { await createCategory() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 520)
    }

    private func createCategory() async {
        errorMessage = nil
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        do {
            let result = try await categoryManager.createCategory(
                api: api,
                name: name.isEmpty ? slugify(trimmedName) : name,
                displayName: trimmedName,
                description: description,
                icon: selectedIcon,
                color: selectedColor
            )
            if result != nil {
                onDone()
                dismiss()
            } else {
                errorMessage = "Não foi possível criar a categoria. Pode já existir."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func slugify(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func colorFor(_ name: String) -> Color {
        CategoryManager.availableColors.first { $0.name == name }?.color ?? .gray
    }
}
