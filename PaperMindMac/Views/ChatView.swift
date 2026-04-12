// PaperMindMac/Views/ChatView.swift
// PaperMind — Chat com LLM + streaming + source badges

import SwiftUI

struct ChatView: View {
    @ObservedObject var api: APIClient
    @Binding var messages: [ChatMessage]
    var onSourceTap: (String, Int) -> Void  // (filename, page)

    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Mensagens
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if messages.isEmpty {
                            emptyState
                        }

                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                onSourceTap: onSourceTap
                            )
                            .id(message.id.uuidString)
                        }

                        if isLoading {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo(messages.last?.id.uuidString ?? "typing", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Faz uma pergunta sobre os teus documentos...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }
                    .disabled(isLoading)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
        }
        .navigationTitle("Chat")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Faz uma pergunta sobre os teus documentos")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private func sendMessage() {
        let question = inputText.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }

        // Mensagem do utilizador
        messages.append(ChatMessage(role: .user, text: question))
        inputText = ""
        isLoading = true

        // Mensagem do assistente (vai sendo preenchida via streaming)
        let assistantMessage = ChatMessage(role: .assistant, text: "")
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        api.askStreaming(
            question: question,
            onToken: { token in
                messages[messageIndex].text += token
            },
            onSources: { sources in
                messages[messageIndex].sources = sources
            },
            onComplete: {
                isLoading = false
            }
        )
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var onSourceTap: (String, Int) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.role == .user { Spacer() }

                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        message.role == .user
                            ? Color.accentColor.opacity(0.15)
                            : Color(.controlBackgroundColor)
                    )
                    .cornerRadius(12)

                if message.role == .assistant { Spacer() }
            }

            // Source badges
            if !message.sources.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(message.sources) { source in
                            SourceBadge(source: source, onTap: onSourceTap)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Source Badge

struct SourceBadge: View {
    let source: Source
    var onTap: (String, Int) -> Void

    var body: some View {
        Button {
            onTap(source.filename, source.pageNumber)
        } label: {
            Label(
                "\(source.filename) — p.\(source.pageNumber)",
                systemImage: "doc.text.magnifyingglass"
            )
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(source.excerpt)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .offset(y: sin(phase + Double(i) * 0.8) * 4)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
