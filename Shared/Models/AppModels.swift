// Shared/Models/AppModels.swift
// PaperMind — Modelos partilhados Mac + iOS

import Foundation
import SwiftUI

// MARK: - API Response Models

struct Source: Codable, Identifiable {
    var id: String { "\(filename)_\(pageNumber)" }
    let filename: String
    let pageNumber: Int
    let excerpt: String
    let relevanceScore: Double

    enum CodingKeys: String, CodingKey {
        case filename
        case pageNumber = "page_number"
        case excerpt
        case relevanceScore = "relevance_score"
    }
}

struct AskResponse: Codable {
    let question: String
    let answer: String
    let sources: [Source]
    let processingTimeMs: Int

    enum CodingKeys: String, CodingKey {
        case question, answer, sources
        case processingTimeMs = "processing_time_ms"
    }
}

struct UploadResponse: Codable {
    let status: String
    let filename: String
    let totalChunks: Int
    let documentType: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, filename, error
        case totalChunks = "total_chunks"
        case documentType = "document_type"
    }
}

struct SyncStatus: Codable {
    let inboxCount: Int
    let processedCount: Int
    let lastSync: String?

    enum CodingKeys: String, CodingKey {
        case inboxCount = "inbox_count"
        case processedCount = "processed_count"
        case lastSync = "last_sync"
    }
}

struct DocumentInfo: Codable, Identifiable, Hashable {
    var id: String { filename }
    let filename: String
    let totalChunks: Int
    let documentType: String
    let dateAdded: String
    let filePath: String

    func category(from categories: [CategoryInfo]) -> CategoryInfo {
        categories.first { $0.name == documentType.lowercased() } ?? CategoryInfo.fallback
    }

    enum CodingKeys: String, CodingKey {
        case filename
        case totalChunks = "total_chunks"
        case documentType = "document_type"
        case dateAdded = "date_added"
        case filePath = "file_path"
    }
}

// MARK: - Category Info (dynamic — built-in + custom)

struct CategoryInfo: Codable, Identifiable, Hashable {
    let name: String
    let displayName: String
    let description: String
    let icon: String
    let color: String
    let isBuiltIn: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case description, icon, color
        case isBuiltIn = "is_built_in"
    }

    var swiftColor: Color {
        switch color {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "teal": return .teal
        case "indigo": return .indigo
        case "brown": return .brown
        case "mint": return .mint
        case "cyan": return .cyan
        default: return .gray
        }
    }

    // Built-in defaults for offline use
    static let builtInCategories: [CategoryInfo] = [
        CategoryInfo(name: "medico", displayName: "Médico / Saúde", description: "", icon: "cross.case.fill", color: "red", isBuiltIn: true),
        CategoryInfo(name: "financeiro", displayName: "Financeiro / Fiscal", description: "", icon: "eurosign.circle.fill", color: "green", isBuiltIn: true),
        CategoryInfo(name: "legal", displayName: "Legal / Contratos", description: "", icon: "doc.text.fill", color: "blue", isBuiltIn: true),
        CategoryInfo(name: "pessoal", displayName: "Pessoal / ID", description: "", icon: "person.text.rectangle.fill", color: "orange", isBuiltIn: true),
        CategoryInfo(name: "outro", displayName: "Outro", description: "", icon: "doc.fill", color: "gray", isBuiltIn: true),
    ]

    static let fallback = CategoryInfo(name: "outro", displayName: "Outro", description: "", icon: "doc.fill", color: "gray", isBuiltIn: true)
}

// MARK: - SSE Event Parsing

struct SSEEvent: Codable {
    let type: String
    let content: String?
    let sources: [Source]?
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    var text: String
    var sources: [Source]
    let timestamp: Date

    enum MessageRole {
        case user
        case assistant
    }

    init(role: MessageRole, text: String, sources: [Source] = [], timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.sources = sources
        self.timestamp = timestamp
    }
}

// MARK: - Inbox Document (iOS)

struct InboxDocument: Identifiable {
    let id = UUID()
    let filename: String
    let capturedAt: Date
    let thumbnailData: Data?
}
