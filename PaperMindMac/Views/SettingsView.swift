// PaperMindMac/Views/SettingsView.swift
// PaperMind — Preferências (⌘,)

import SwiftUI

struct SettingsView: View {
    @AppStorage("mlxModel") private var mlxModel = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    @AppStorage("autoOffMinutes") private var autoOffMinutes = 5
    @AppStorage("iCloudPath") private var iCloudPath = ""
    @AppStorage("responseLanguage") private var responseLanguage = "auto"

    var body: some View {
        TabView {
            // Tab: Modelo
            Form {
                Section("Modelo LLM") {
                    Picker("Modelo MLX", selection: $mlxModel) {
                        Text("Llama 3.2 3B (4-bit)").tag("mlx-community/Llama-3.2-3B-Instruct-4bit")
                        Text("Phi-4 Mini (4-bit)").tag("mlx-community/Phi-4-mini-instruct-4bit")
                    }

                    Stepper(
                        "Auto-off: \(autoOffMinutes) min",
                        value: $autoOffMinutes,
                        in: 1...30
                    )
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
                }
            }
            .tabItem { Label("Geral", systemImage: "gear") }
        }
        .frame(width: 450, height: 250)
    }
}
