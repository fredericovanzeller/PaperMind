// PaperMindIOS/Views/StatusView.swift
// PaperMind — Estado de sincronização com o Mac

import SwiftUI

struct StatusView: View {
    @ObservedObject var syncState: SyncState

    var body: some View {
        List {
            Section("Sincronização") {
                HStack {
                    Label("Documentos indexados", systemImage: "doc.on.doc")
                    Spacer()
                    Text("\(syncState.totalProcessed)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Aguardam processamento", systemImage: "hourglass")
                    Spacer()
                    Text("\(syncState.pendingCount)")
                        .foregroundStyle(syncState.pendingCount > 0 ? .orange : .secondary)
                }

                if let lastFile = syncState.lastProcessedFilename {
                    HStack {
                        Label("Último processado", systemImage: "checkmark.circle")
                        Spacer()
                        Text(lastFile)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Como funciona") {
                InfoRow(
                    icon: "camera.viewfinder",
                    color: .blue,
                    title: "1. Fotografa",
                    subtitle: "Usa a câmara para digitalizar documentos"
                )
                InfoRow(
                    icon: "icloud.and.arrow.up",
                    color: .cyan,
                    title: "2. iCloud sincroniza",
                    subtitle: "O documento é enviado automaticamente via iCloud"
                )
                InfoRow(
                    icon: "desktopcomputer",
                    color: .teal,
                    title: "3. Mac processa",
                    subtitle: "OCR, classificação e indexação 100% offline"
                )
                InfoRow(
                    icon: "magnifyingglass",
                    color: .green,
                    title: "4. Pesquisa",
                    subtitle: "Faz perguntas sobre os teus documentos no Mac"
                )
            }

            Section {
                HStack {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                    Text("Todos os dados ficam nos teus dispositivos. Nada na cloud de ninguém.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Estado")
        .refreshable {
            await syncState.refreshStatus()
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
