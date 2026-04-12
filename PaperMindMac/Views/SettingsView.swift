// PaperMindMac/Views/SettingsView.swift
// PaperMind — Preferências (⌘,)

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var backendManager: BackendManager

    // MARK: - Modelo
    @AppStorage("modelName") private var modelName = "gemma4-nothink"
    @AppStorage("responseLanguage") private var responseLanguage = "auto"
    @AppStorage("autoOffMinutes") private var autoOffMinutes = 10

    // MARK: - Armazenamento
    @AppStorage("projectPath") private var projectPath = ""

    // MARK: - Avançado
    @AppStorage("autoStartBackend") private var autoStartBackend = true

    @State private var syncStatus: String?
    @State private var documentCount: Int?
    @State private var isReindexing = false
    @State private var isReclassifying = false
    @State private var showReindexConfirm = false
    @State private var showReclassifyConfirm = false
    @State private var operationResult: String?

    private let api = APIClient()

    var body: some View {
        TabView {
            modelTab
                .tabItem { Label("Modelo", systemImage: "cpu") }
            storageTab
                .tabItem { Label("Armazenamento", systemImage: "externaldrive") }
            advancedTab
                .tabItem { Label("Avançado", systemImage: "gearshape.2") }
        }
        .frame(width: 520, height: 400)
    }

    // MARK: - Tab: Modelo

    private var modelTab: some View {
        Form {
            Section("Modelo LLM (Ollama)") {
                TextField("Nome do modelo", text: $modelName)
                    .textFieldStyle(.roundedBorder)

                Picker("Idioma de resposta", selection: $responseLanguage) {
                    Text("Auto (segue a pergunta)").tag("auto")
                    Text("Português").tag("pt")
                    Text("English").tag("en")
                }

                Stepper(
                    "Auto-off: \(autoOffMinutes) min",
                    value: $autoOffMinutes,
                    in: 1...60
                )

                Text("O modelo é descarregado da RAM após inatividade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Aplicar") {
                        pushSettings()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Descarregar modelos") {
                        NSWorkspace.shared.open(URL(string: "https://ollama.ai")!)
                    }

                    Spacer()

                    if let status = syncStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Tab: Armazenamento

    private var storageTab: some View {
        Form {
            Section("Pasta do projecto") {
                HStack {
                    TextField("~/Developer/PaperMind", text: $projectPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Escolher pasta...") {
                        chooseFolder()
                    }
                }

                Text("Onde o PaperMind guarda documentos e a base de dados vectorial.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Documentos indexados") {
                HStack {
                    if let count = documentCount {
                        Text("\(count) documentos indexados")
                    } else {
                        Text("A carregar...")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .onAppear { loadDocumentCount() }

                HStack(spacing: 12) {
                    Button("Re-indexar tudo") {
                        showReindexConfirm = true
                    }
                    .disabled(isReindexing || isReclassifying)
                    .confirmationDialog(
                        "Re-indexar todos os documentos?",
                        isPresented: $showReindexConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Re-indexar", role: .destructive) { performReindex() }
                    } message: {
                        Text("Isto vai reconstruir todos os embeddings. Pode demorar vários minutos.")
                    }

                    Button("Reclassificar tudo") {
                        showReclassifyConfirm = true
                    }
                    .disabled(isReindexing || isReclassifying)
                    .confirmationDialog(
                        "Reclassificar todos os documentos?",
                        isPresented: $showReclassifyConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Reclassificar", role: .destructive) { performReclassify() }
                    } message: {
                        Text("Isto vai re-classificar todos os documentos com o modelo actual.")
                    }

                    if isReindexing || isReclassifying {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let result = operationResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // MARK: - Tab: Avançado

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Opções") {
                    Toggle("Iniciar backend automaticamente", isOn: $autoStartBackend)

                    Button("Reset Onboarding") {
                        OnboardingManager().reset()
                    }
                }

                Section("Backend") {
                    HStack {
                        Circle()
                            .fill(backendManager.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(backendManager.isRunning ? "Backend a correr" : "Backend parado")
                            .font(.headline)
                        Spacer()
                        Button(backendManager.isRunning ? "Parar" : "Iniciar") {
                            if backendManager.isRunning {
                                backendManager.stop()
                            } else {
                                backendManager.start()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding([.horizontal, .top])

            // Logs
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(backendManager.logs.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .id(i)
                        }
                    }
                    .padding(.horizontal)
                }
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onChange(of: backendManager.logs.count) {
                    withAnimation {
                        proxy.scrollTo(backendManager.logs.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func pushSettings() {
        syncStatus = "A sincronizar..."
        Task {
            do {
                try await api.updateSettings(
                    modelName: modelName,
                    responseLanguage: responseLanguage,
                    autoOffMinutes: autoOffMinutes
                )
                syncStatus = "Configurações aplicadas"
            } catch {
                syncStatus = "Erro: backend indisponível"
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            syncStatus = nil
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Escolhe a pasta do projecto PaperMind"
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
        }
    }

    private func loadDocumentCount() {
        Task {
            do {
                let docs = try await api.getDocuments()
                documentCount = docs.count
            } catch {
                documentCount = 0
            }
        }
    }

    private func performReindex() {
        isReindexing = true
        operationResult = "A re-indexar..."
        Task {
            do {
                let result = try await api.reindex()
                operationResult = "Re-indexados: \(result.reindexed) docs, \(result.totalChunks) chunks"
                loadDocumentCount()
            } catch {
                operationResult = "Erro na re-indexação"
            }
            isReindexing = false
        }
    }

    private func performReclassify() {
        isReclassifying = true
        operationResult = "A reclassificar..."
        Task {
            do {
                let result = try await api.reclassifyDocuments()
                operationResult = "Reclassificados: \(result.total) docs, \(result.changed) alterados"
            } catch {
                operationResult = "Erro na reclassificação"
            }
            isReclassifying = false
        }
    }
}
