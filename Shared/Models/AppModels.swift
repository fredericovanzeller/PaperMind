// Shared/Models/AppModels.swift
// PaperMind — Modelos partilhados Mac + iOS

import Foundation

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

    enum CodingKeys: String, CodingKey {
        case filename
        case totalChunks = "total_chunks"
        case documentType = "document_type"
        case dateAdded = "date_added"
        case filePath = "file_path"
    }
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
