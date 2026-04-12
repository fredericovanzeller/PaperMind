// PaperMindMac/Services/CategoryManager.swift
// PaperMind — Gestão de categorias (built-in + custom)

import Foundation
import SwiftUI

@MainActor
class CategoryManager: ObservableObject {
    @Published var categories: [CategoryInfo] = CategoryInfo.builtInCategories
    @Published var isReclassifying = false

    /// Fetch all categories from backend
    func refresh(api: APIClient) async {
        do {
            let fetched = try await api.getCategories()
            if !fetched.isEmpty {
                categories = fetched
            }
        } catch {
            // Keep built-in defaults if backend is unreachable
            print("Erro ao carregar categorias: \(error.localizedDescription)")
        }
    }

    /// Find category info for a document type string
    func category(for documentType: String) -> CategoryInfo {
        categories.first { $0.name == documentType.lowercased() } ?? CategoryInfo.fallback
    }

    /// Create a new custom category
    func createCategory(api: APIClient, name: String, displayName: String, description: String, icon: String, color: String) async throws -> CategoryInfo? {
        let result = try await api.createCategory(
            name: name,
            displayName: displayName,
            description: description,
            icon: icon,
            color: color
        )
        await refresh(api: api)
        return result
    }

    /// Delete a custom category
    func deleteCategory(api: APIClient, name: String) async throws {
        try await api.deleteCategory(name: name)
        await refresh(api: api)
    }

    /// Update a document's category
    func updateDocumentCategory(api: APIClient, filename: String, categoryName: String) async throws {
        try await api.updateCategory(filename: filename, categoryName: categoryName)
    }

    /// Reclassify all documents using LLM
    func reclassifyAll(api: APIClient) async -> (total: Int, changed: Int) {
        isReclassifying = true
        defer { isReclassifying = false }

        do {
            let result = try await api.reclassifyDocuments()
            return result
        } catch {
            print("Erro ao reclassificar: \(error.localizedDescription)")
            return (0, 0)
        }
    }

    /// Available colors for custom category picker
    static let availableColors: [(name: String, display: String, color: Color)] = [
        ("purple", "Roxo", .purple),
        ("pink", "Rosa", .pink),
        ("teal", "Teal", .teal),
        ("indigo", "Índigo", .indigo),
        ("brown", "Castanho", .brown),
        ("mint", "Menta", .mint),
        ("cyan", "Ciano", .cyan),
        ("yellow", "Amarelo", .yellow),
    ]

    /// Available icons for custom category picker
    static let availableIcons: [(name: String, display: String)] = [
        ("tag.fill", "Tag"),
        ("folder.fill", "Pasta"),
        ("graduationcap.fill", "Educação"),
        ("briefcase.fill", "Trabalho"),
        ("house.fill", "Casa"),
        ("car.fill", "Veículo"),
        ("airplane", "Viagem"),
        ("pawprint.fill", "Animal"),
        ("leaf.fill", "Natureza"),
        ("wrench.fill", "Técnico"),
        ("book.fill", "Livro"),
        ("music.note", "Música"),
    ]
}
