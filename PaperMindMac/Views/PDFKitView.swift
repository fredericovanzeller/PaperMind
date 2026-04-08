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
        guard let url = url else {
            pdfView.document = nil
            return
        }

        if pdfView.document == nil {
            pdfView.document = PDFDocument(url: url)
        }

        if currentPage > 0 {
            DispatchQueue.main.async {
                if let page = pdfView.document?.page(at: currentPage - 1) {
                    pdfView.go(to: page)
                }
            }
        }
    }
}
