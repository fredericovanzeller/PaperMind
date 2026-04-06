// PaperMindMac/Services/APIClient.swift
// PaperMind — Comunicação com o backend FastAPI

import Foundation

@MainActor
class APIClient: ObservableObject {
    private let baseURL: String

    @Published var isBackendAvailable = false

    init(baseURL: String = "http://127.0.0.1:8000") {
        self.baseURL = baseURL
    }

    // MARK: - Health Check

    func checkHealth() async {
        guard let url = URL(string: "\(baseURL)/health") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONDecoder().decode([String: String].self, from: data) {
                isBackendAvailable = json["status"] == "ok"
            }
        } catch {
            isBackendAvailable = false
        }
    }

    // MARK: - Upload

    func uploadFile(_ fileURL: URL) async throws -> UploadResponse {
        let url = URL(string: "\(baseURL)/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let fileData = try Data(contentsOf: fileURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }

    // MARK: - Ask (complete response)

    func ask(question: String) async throws -> AskResponse {
        let url = URL(string: "\(baseURL)/ask")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["question": question]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(AskResponse.self, from: data)
    }

    // MARK: - Ask with SSE Streaming

    func askStreaming(
        question: String,
        onToken: @escaping (String) -> Void,
        onSources: @escaping ([Source]) -> Void,
        onComplete: @escaping () -> Void
    ) {
        let encoded = question.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? ""
        guard let url = URL(string: "\(baseURL)/ask/stream?question=\(encoded)") else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data,
                  let text = String(data: data, encoding: .utf8)
            else {
                DispatchQueue.main.async { onComplete() }
                return
            }

            for line in text.components(separatedBy: "\n") {
                guard line.hasPrefix("data: ") else { continue }
                let json = String(line.dropFirst(6))

                if json == "[DONE]" {
                    DispatchQueue.main.async { onComplete() }
                    continue
                }

                if let eventData = json.data(using: .utf8),
                   let event = try? JSONDecoder().decode(SSEEvent.self, from: eventData)
                {
                    DispatchQueue.main.async {
                        switch event.type {
                        case "token":
                            onToken(event.content ?? "")
                        case "sources":
                            onSources(event.sources ?? [])
                        default:
                            break
                        }
                    }
                }
            }
        }.resume()
    }

    // MARK: - Sync Status

    func getSyncStatus() async throws -> SyncStatus {
        let url = URL(string: "\(baseURL)/sync/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SyncStatus.self, from: data)
    }

    // MARK: - Process Inbox

    func processInbox() async throws -> [String] {
        let url = URL(string: "\(baseURL)/sync/process-inbox")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode([String: [String]].self, from: data)
        return result["files"] ?? []
    }

    // MARK: - Model Management

    func unloadModel() async throws {
        let url = URL(string: "\(baseURL)/model/unload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    func loadModel() async throws {
        let url = URL(string: "\(baseURL)/model/load")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Documents List

    func getDocuments() async throws -> [DocumentInfo] {
        let url = URL(string: "\(baseURL)/documents")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode([String: [DocumentInfo]].self, from: data)
        return result["documents"] ?? []
    }
}
