// PaperMindMac/Views/PDFKitView.swift
// PaperMind — PDF Viewer com deep linking por página

import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let url: URL?
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Handle clearing: if url is nil, remove the document
        guard let url = url else {
            if context.coordinator.loadedURL != nil {
                pdfView.document = nil
                context.coordinator.loadedURL = nil
            }
            return
        }

        // Reload only when the URL actually changes (tracked via Coordinator)
        let urlChanged = context.coordinator.loadedURL != url
        if urlChanged {
            let doc = PDFDocument(url: url)
            pdfView.document = doc
            context.coordinator.loadedURL = url
        }

        // Deep linking: jump to page AFTER the document is set
        // Defer to next run loop so PDFView has finished layout
        if currentPage > 0 {
            DispatchQueue.main.async {
                if let page = pdfView.document?.page(at: currentPage - 1) {
                    pdfView.go(to: page)
                }
            }
        }
    }

    class Coordinator {
        var loadedURL: URL?
    }
}
