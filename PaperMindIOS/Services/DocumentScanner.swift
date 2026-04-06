// PaperMindIOS/Services/DocumentScanner.swift
// PaperMind — OCR no iPhone via Apple Vision (antes de enviar ao iCloud)

import Vision
import UIKit

class DocumentScanner {

    /// Extrai texto de uma imagem usando Apple Vision OCR.
    /// O iPhone faz OCR antes de guardar — garante que o texto está disponível
    /// mesmo offline, e o Mac apenas precisa de fazer chunking + embeddings.
    static func extractText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error = error {
                    print("OCR error: \(error.localizedDescription)")
                    continuation.resume(returning: "")
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
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                print("VNImageRequestHandler failed: \(error)")
                continuation.resume(returning: "")
            }
        }
    }

    /// Avalia a qualidade do OCR (percentagem de confiança média)
    static func assessQuality(from image: UIImage) async -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                guard !observations.isEmpty else {
                    continuation.resume(returning: 0.0)
                    return
                }

                let avgConfidence = observations
                    .compactMap { $0.topCandidates(1).first?.confidence }
                    .reduce(0, +) / Float(observations.count)

                continuation.resume(returning: Double(avgConfidence))
            }

            request.recognitionLanguages = ["pt-PT", "pt-BR", "en-US"]
            request.recognitionLevel = .accurate

            try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        }
    }
}
