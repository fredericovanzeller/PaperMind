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
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "ok" {
                isBackendAvailable = true
            } else {
                isBackendAvailable = false
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
        request.timeoutInterval = 300  // 5 min — OCR + embedding can be slow

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

    // MARK: - Ask with SSE Streaming (real async streaming)

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

        var request = URLRequest(url: url)
        request.timeoutInterval = 300

        Task {
            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: request)

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let json = String(line.dropFirst(6))

                    if json == "[DONE]" {
                        await MainActor.run { onComplete() }
                        break
                    }

                    if let eventData = json.data(using: .utf8),
                       let event = try? JSONDecoder().decode(SSEEvent.self, from: eventData)
                    {
                        await MainActor.run {
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
            } catch {
                await MainActor.run { onComplete() }
            }
        }
    }

    // MARK: - Sync Status

    func getSyncStatus() async throws -> SyncStatus {
        let url = URL(string: "\(baseURL)/sync/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SyncStatus.self, from: data)
    }

    // MARK: - Process Inbox

    struct ProcessInboxResponse: Codable {
        let processed: Int
        let files: [String]
    }

    func processInbox() async throws -> [String] {
        let url = URL(string: "\(baseURL)/sync/process-inbox")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300  // OCR can be slow
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(ProcessInboxResponse.self, from: data)
        return result.files
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

    // MARK: - Delete Document

    func deleteDocument(_ filename: String) async throws {
        let encoded = filename.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? filename
        let url = URL(string: "\(baseURL)/documents/\(encoded)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Update Document Category

    func updateCategory(filename: String, categoryName: String) async throws {
        let encoded = filename.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? filename
        let url = URL(string: "\(baseURL)/documents/\(encoded)/category")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["category": categoryName]
        request.httpBody = try JSONEncoder().encode(body)
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Categories Management

    func getCategories() async throws -> [CategoryInfo] {
        let url = URL(string: "\(baseURL)/categories")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode([String: [CategoryInfo]].self, from: data)
        return result["categories"] ?? []
    }

    func createCategory(name: String, displayName: String, description: String, icon: String, color: String) async throws -> CategoryInfo? {
        let url = URL(string: "\(baseURL)/categories")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "name": name,
            "display_name": displayName,
            "description": description,
            "icon": icon,
            "color": color,
        ]
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try? JSONDecoder().decode(CategoryInfo.self, from: data)
    }

    func deleteCategory(name: String) async throws {
        let url = URL(string: "\(baseURL)/categories/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Reclassify All Documents

    func reclassifyDocuments() async throws -> (total: Int, changed: Int) {
        let url = URL(string: "\(baseURL)/documents/reclassify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600  // 10 min — reclassifying all can be slow
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let total = json["total"] as? Int ?? 0
            let changed = json["changed"] as? Int ?? 0
            return (total, changed)
        }
        return (0, 0)
    }

    // MARK: - Documents List

    func getDocuments() async throws -> [DocumentInfo] {
        let url = URL(string: "\(baseURL)/documents")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode([String: [DocumentInfo]].self, from: data)
        return result["documents"] ?? []
    }

    // MARK: - Update Settings

    func updateSettings(modelName: String, responseLanguage: String, autoOffMinutes: Int) async throws {
        let url = URL(string: "\(baseURL)/settings")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model_name": modelName,
            "response_language": responseLanguage,
            "auto_off_minutes": autoOffMinutes,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Reindex

    func reindex() async throws -> (reindexed: Int, errors: [String], totalChunks: Int) {
        let url = URL(string: "\(baseURL)/reindex")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let reindexed = json["reindexed"] as? Int ?? 0
            let errors = json["errors"] as? [String] ?? []
            let totalChunks = json["total_chunks"] as? Int ?? 0
            return (reindexed, errors, totalChunks)
        }
        return (0, [], 0)
    }

    // MARK: - Download PDF File

    func getPDFData(filename: String) async throws -> Data {
        let encoded = filename.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? filename
        let url = URL(string: "\(baseURL)/documents/\(encoded)/file")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
