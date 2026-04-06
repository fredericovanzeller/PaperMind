// Shared/Services/iCloudManager.swift
// PaperMind — Gestão de iCloud Drive partilhada Mac + iOS

import Foundation

class iCloudManager: ObservableObject {
    static let shared = iCloudManager()

    private let containerID = "iCloud.com.frederico.papermind"

    /// URL base do container iCloud Drive
    var baseURL: URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: containerID)?
            .appendingPathComponent("Documents")
    }

    /// Pasta Inbox — iPhone deposita aqui
    var inboxURL: URL? {
        baseURL?.appendingPathComponent("Inbox")
    }

    /// Pasta Processed — Mac move ficheiros para aqui
    var processedURL: URL? {
        baseURL?.appendingPathComponent("Processed")
    }

    /// Verifica se iCloud está disponível
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Cria as pastas necessárias se não existirem
    func ensureDirectories() throws {
        guard let inbox = inboxURL, let processed = processedURL else {
            throw PaperMindError.iCloudNotAvailable
        }

        try FileManager.default.createDirectory(
            at: inbox, withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: processed, withIntermediateDirectories: true
        )
    }

    #if os(iOS)
    /// Guardar imagem digitalizada + texto OCR na Inbox
    func saveToInbox(imageData: Data, ocrText: String, format: String = "jpg") throws -> URL {
        guard let inbox = inboxURL else {
            throw PaperMindError.iCloudNotAvailable
        }

        try FileManager.default.createDirectory(
            at: inbox, withIntermediateDirectories: true
        )

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        // Guardar imagem
        let imageURL = inbox.appendingPathComponent("scan_\(timestamp).\(format)")
        try imageData.write(to: imageURL)

        // Guardar texto OCR junto (para o Mac usar directamente)
        let textURL = inbox.appendingPathComponent("scan_\(timestamp).txt")
        try ocrText.write(to: textURL, atomically: true, encoding: .utf8)

        return imageURL
    }
    #endif
}

// MARK: - Errors

enum PaperMindError: LocalizedError {
    case iCloudNotAvailable
    case ocrFailed
    case backendUnavailable

    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Drive não está disponível. Verifica as definições."
        case .ocrFailed:
            return "Não foi possível extrair texto da imagem."
        case .backendUnavailable:
            return "O servidor PaperMind não está a responder."
        }
    }
}
