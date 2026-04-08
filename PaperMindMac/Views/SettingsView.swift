// PaperMindMac/Views/SettingsView.swift
// PaperMind — Preferências (⌘,)

import SwiftUI

struct SettingsView: View {
    @AppStorage("mlxModel") private var mlxModel = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    @AppStorage("autoOffMinutes") private var autoOffMinutes = 5
    @AppStorage("iCloudPath") private var iCloudPath = ""
    @AppStorage("responseLanguage") private var responseLanguage = "auto"

    @State private var syncStatus: String?

    var body: some View {
        TabView {
            // Tab: Modelo
            Form {
                Section("Modelo LLM") {
                    Picker("Modelo MLX", selection: $mlxModel) {
                        Text("Llama 3.2 3B (4-bit)").tag("mlx-community/Llama-3.2-3B-Instruct-4bit")
                        Text("Phi-4 Mini (4-bit)").tag("mlx-community/Phi-4-mini-instruct-4bit")
                    }
                    .onChange(of: mlxModel) { pushSettings() }

                    Stepper(
                        "Auto-off: \(autoOffMinutes) min",
                        value: $autoOffMinutes,
                        in: 1...30
                    )
                    .onChange(of: autoOffMinutes) { pushSettings() }

                    Text("O modelo é descarregado da RAM após inatividade.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Modelo", systemImage: "cpu") }

            // Tab: iCloud
            Form {
                Section("iCloud Drive") {
                    TextField("Caminho personalizado (vazio = default)", text: $iCloudPath)
                    Text("Default: ~/Library/Mobile Documents/iCloud~com~frederico~papermind/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("iCloud", systemImage: "icloud") }

            // Tab: Geral
            Form {
                Section("Idioma") {
                    Picker("Idioma de resposta", selection: $responseLanguage) {
                        Text("Automático (segue a pergunta)").tag("auto")
                        Text("Português").tag("pt")
                        Text("English").tag("en")
                    }
                    .onChange(of: responseLanguage) { pushSettings() }
                }

                if let status = syncStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Geral", systemImage: "gear") }
        }
        .frame(width: 450, height: 250)
    }

    /// Envia preferências atuais para o backend via PUT /settings
    private func pushSettings() {
        syncStatus = "A sincronizar..."
        Task {
            let payload: [String: Any] = [
                "model_name": mlxModel,
                "response_language": responseLanguage,
                "auto_off_minutes": autoOffMinutes,
            ]

            guard let url = URL(string: "http://localhost:8000/settings"),
                  let body = try? JSONSerialization.data(withJSONObject: payload)
            else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    syncStatus = "Configurações sincronizadas"
                } else {
                    syncStatus = "Erro ao sincronizar"
                }
            } catch {
                syncStatus = "Backend indisponível"
            }

            // Limpar mensagem após 3 segundos
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            syncStatus = nil
        }
    }
}
