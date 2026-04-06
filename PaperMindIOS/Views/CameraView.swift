// PaperMindIOS/Views/CameraView.swift
// PaperMind — Digitalização de documentos com câmara do iPhone

import SwiftUI
import VisionKit

struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onScan: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Recolher todas as páginas digitalizadas
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(images)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            parent.dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            print("Erro na câmara: \(error.localizedDescription)")
            parent.dismiss()
        }
    }
}
