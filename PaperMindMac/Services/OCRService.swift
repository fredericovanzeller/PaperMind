// PaperMindMac/Services/OCRService.swift
// PaperMind — OCR no Mac via Apple Vision (Fase 4)

import Vision
import AppKit

class OCRService {

    /// Extrai texto de uma imagem no Mac usando Apple Vision.
    /// Suporta: .jpg, .png, .heic, .tiff
    static func extractText(from imageURL: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                if let err = err {
                    continuation.resume(throwing: err)
                    return
                }

                let text = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""

                continuation.resume(returning: text)
            }

            request.recognitionLanguages = ["pt-PT", "pt-BR", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                try VNImageRequestHandler(url: imageURL).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
