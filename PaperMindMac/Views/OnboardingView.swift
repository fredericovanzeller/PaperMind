// PaperMindMac/Views/OnboardingView.swift
// PaperMind — First-Run Wizard

import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String)] = [
        (
            "doc.text.magnifyingglass",
            "Bem-vindo ao PaperMind",
            "O PaperMind organiza e pesquisa os teus documentos localmente, com total privacidade. Nenhum dado sai do teu Mac."
        ),
        (
            "square.and.arrow.down",
            "Importa documentos",
            "Arrasta PDFs para a janela principal ou usa o iPhone para digitalizar documentos. O PaperMind extrai o texto, classifica e indexa tudo automaticamente."
        ),
        (
            "message",
            "Pergunta o que quiseres",
            "Faz perguntas em linguagem natural sobre os teus documentos. O PaperMind encontra as respostas e indica exactamente de onde vêm."
        ),
        (
            "gearshape",
            "Requisitos",
            "O PaperMind precisa do Ollama instalado e a correr localmente. Certifica-te que o modelo está descarregado antes de começar.\n\nInstala em: ollama.com"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: steps[currentStep].icon)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)

            // Title
            Text(steps[currentStep].title)
                .font(.title)
                .fontWeight(.semibold)
                .padding(.bottom, 12)

            // Description
            Text(steps[currentStep].description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.bottom, 32)

            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 32)

            Spacer()

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Anterior") {
                        withAnimation { currentStep -= 1 }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Seguinte") {
                        withAnimation { currentStep += 1 }
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Começar") {
                        onComplete()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .frame(width: 600, height: 450)
    }
}
