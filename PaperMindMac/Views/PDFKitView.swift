// PaperMindMac/Views/PDFKitView.swift
// PaperMind — PDF Viewer com deep linking por página

import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let url: URL?
    @Binding var currentPage: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        guard let url = url else { return }

        // Só recarregar se o URL mudou
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }

        // Deep linking: ir para a página da fonte citada
        if currentPage > 0,
           let page = pdfView.document?.page(at: currentPage - 1)
        {
            pdfView.go(to: page)
        }
    }
}
