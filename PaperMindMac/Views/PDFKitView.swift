// PaperMindMac/Views/PDFKitView.swift
import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let pdfData: Data?
    @Binding var currentPage: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        if let data = pdfData {
            view.document = PDFDocument(data: data)
        }
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Document is set on creation; .id() forces full recreation on data change.
        if currentPage > 0 {
            DispatchQueue.main.async {
                if let page = pdfView.document?.page(at: currentPage - 1) {
                    pdfView.go(to: page)
                }
            }
        }
    }
}
