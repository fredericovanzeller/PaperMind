// PaperMindIOS/Views/StatusView.swift
// PaperMind — Estado de sincronizacao com o Mac

import SwiftUI

struct StatusView: View {
    @ObservedObject var syncState: SyncState
    @State private var refreshTimer: Timer?

    var body: some View {
        List {
            Section("Sincronizacao") {
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
                        Label("Ultimo processado", systemImage: "checkmark.circle")
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
                    subtitle: "Usa a camara para digitalizar documentos"
                )
                InfoRow(
                    icon: "icloud.and.arrow.up",
                    color: .cyan,
                    title: "2. iCloud sincroniza",
                    subtitle: "O documento e enviado automaticamente via iCloud"
                )
                InfoRow(
                    icon: "desktopcomputer",
                    color: .teal,
                    title: "3. Mac processa",
                    subtitle: "OCR, classificacao e indexacao 100% offline"
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
                    Text("Todos os dados ficam nos teus dispositivos. Nada na cloud de ninguem.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Estado")
        .refreshable {
            await syncState.refreshStatus()
        }
        .onAppear {
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        // Initial fetch
        Task { await syncState.refreshStatus() }
        // Refresh every 30 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { await syncState.refreshStatus() }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
