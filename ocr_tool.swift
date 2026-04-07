import Vision
import Foundation
import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("Uso: ocr_tool <caminho_da_imagem>\n", stderr)
    exit(1)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)

guard let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Erro: não foi possível carregar a imagem: \(path)\n", stderr)
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var resultText = ""

let request = VNRecognizeTextRequest { req, error in
    if let error = error {
        fputs("OCR erro: \(error.localizedDescription)\n", stderr)
        semaphore.signal()
        return
    }

    let observations = req.results as? [VNRecognizedTextObservation] ?? []
    resultText = observations
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")

    semaphore.signal()
}

request.recognitionLanguages = ["pt-PT", "pt-BR", "en-US"]
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

do {
    try VNImageRequestHandler(cgImage: cgImage).perform([request])
} catch {
    fputs("Erro VNImageRequestHandler: \(error)\n", stderr)
    exit(1)
}

semaphore.wait()
print(resultText)
