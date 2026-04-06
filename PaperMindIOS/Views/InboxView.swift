// PaperMindIOS/Views/InboxView.swift
// PaperMind — Lista de documentos aguardando processamento pelo Mac

import SwiftUI

struct InboxView: View {
    @ObservedObject var syncState: SyncState

    var body: some View {
        List {
            if syncState.pendingDocs.isEmpty {
                ContentUnavailableView(
                    "Tudo sincronizado",
                    systemImage: "checkmark.icloud",
                    description: Text("Todos os documentos foram processados pelo Mac")
                )
            } else {
                Section("Aguardam processamento (\(syncState.pendingDocs.count))") {
                    ForEach(syncState.pendingDocs) { doc in
                        HStack(spacing: 12) {
                            // Thumbnail
                            if let data = doc.thumbnailData,
                               let uiImage = UIImage(data: data)
                            {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .cornerRadius(8)
                                    .clipped()
                            } else {
                                Image(systemName: "doc.badge.clock")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                    .frame(width: 44, height: 44)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.filename)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(doc.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "icloud.and.arrow.up")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Inbox")
        .refreshable {
            await syncState.refreshStatus()
        }
    }
}
