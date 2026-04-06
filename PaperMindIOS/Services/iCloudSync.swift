// PaperMindIOS/Services/iCloudSync.swift
// PaperMind — Sincronização iOS ↔ iCloud + estado

import Foundation
import UIKit

@MainActor
class SyncState: ObservableObject {
    @Published var pendingDocs: [InboxDocument] = []
    @Published var pendingCount: Int = 0
    @Published var totalProcessed: Int = 0
    @Published var lastProcessedFilename: String?
    @Published var isProcessing = false

    private let iCloud = iCloudManager.shared

    /// Processa imagens digitalizadas: OCR → guardar no iCloud Inbox
    func processScans(_ images: [UIImage]) async {
        isProcessing = true
        defer { isProcessing = false }

        for image in images {
            // 1. OCR no iPhone
            let ocrText = await DocumentScanner.extractText(from: image)

            // 2. Verificar qualidade
            let quality = await DocumentScanner.assessQuality(from: image)
            if quality < 0.3 {
                print("⚠️ Qualidade OCR baixa (\(Int(quality * 100))%) — foto possivelmente desfocada")
            }

            // 3. Guardar no iCloud Inbox
            do {
                guard let jpegData = image.jpegData(compressionQuality: 0.85) else { continue }
                let url = try iCloud.saveToInbox(
                    imageData: jpegData,
                    ocrText: ocrText
                )

                let doc = InboxDocument(
                    filename: url.lastPathComponent,
                    capturedAt: Date(),
                    thumbnailData: image.jpegData(compressionQuality: 0.3)
                )
                pendingDocs.append(doc)
                pendingCount = pendingDocs.count

                print("✅ Guardado no iCloud: \(url.lastPathComponent)")
            } catch {
                print("❌ Erro ao guardar: \(error.localizedDescription)")
            }
        }
    }

    /// Lê status.json do iCloud para saber o que o Mac já processou
    func refreshStatus() async {
        guard let baseURL = iCloud.baseURL else { return }
        let statusURL = baseURL.appendingPathComponent("status.json")

        guard let data = try? Data(contentsOf: statusURL),
              let status = try? JSONDecoder().decode(MacStatus.self, from: data)
        else { return }

        totalProcessed = status.totalDocuments
        lastProcessedFilename = status.lastFilename
        pendingCount = status.pendingCount

        // Remover da lista de pending os que já foram processados
        if status.pendingCount == 0 {
            pendingDocs.removeAll()
        }
    }
}

// MARK: - Mac Status (lido do status.json no iCloud)

struct MacStatus: Codable {
    let lastProcessed: String
    let totalDocuments: Int
    let lastFilename: String
    let pendingCount: Int

    enum CodingKeys: String, CodingKey {
        case lastProcessed = "last_processed"
        case totalDocuments = "total_documents"
        case lastFilename = "last_filename"
        case pendingCount = "pending_count"
    }
}
