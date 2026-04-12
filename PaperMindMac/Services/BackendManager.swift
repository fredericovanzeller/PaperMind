// PaperMindMac/Services/BackendManager.swift
// PaperMind — Manages the Python backend lifecycle (start/stop uvicorn)

import Foundation
import Combine

@MainActor
class BackendManager: ObservableObject {
    @Published var isRunning = false
    @Published var logs: [String] = []

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let maxLogLines = 200
    private let port: Int = 8000

    // MARK: - Port Detection

    nonisolated private func isPortInUse(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    // MARK: - Python Discovery

    nonisolated private func findPython(projectPath: String) -> String? {
        // 1. Try .venv in the project directory
        let venvPython = "\(projectPath)/.venv/bin/python"
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            return venvPython
        }

        // 2. Fallback: which python3
        let whichProcess = Process()
        let pipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["python3"]
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            // Fall through
        }

        return nil
    }

    // MARK: - Project Path

    nonisolated private func resolveProjectPath() -> String {
        if let custom = UserDefaults.standard.string(forKey: "projectPath"), !custom.isEmpty {
            return (custom as NSString).expandingTildeInPath
        }
        return (("~/Developer/PaperMind" as NSString).expandingTildeInPath)
    }

    // MARK: - Start

    func start() {
        // Already managed by us?
        if let p = process, p.isRunning {
            appendLog("[BackendManager] Process already running (PID \(p.processIdentifier))")
            isRunning = true
            return
        }

        let projectPath = resolveProjectPath()

        // Check if port is already in use (e.g., user started manually)
        if isPortInUse(port) {
            appendLog("[BackendManager] Port \(port) already in use — skipping launch")
            isRunning = true
            return
        }

        // Find Python
        guard let pythonPath = findPython(projectPath: projectPath) else {
            appendLog("[BackendManager] ERROR: Could not find Python. Check .venv or install python3.")
            return
        }

        appendLog("[BackendManager] Using Python: \(pythonPath)")
        appendLog("[BackendManager] Project: \(projectPath)")

        // Configure process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-m", "uvicorn", "backend.api:app", "--host", "127.0.0.1", "--port", "\(port)"]
        proc.currentDirectoryURL = URL(fileURLWithPath: projectPath)

        // Environment: inherit current + ensure venv is on PATH
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(projectPath)/.venv/bin:" + (env["PATH"] ?? "/usr/bin:/usr/local/bin")
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        proc.environment = env

        // Pipes for log capture
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        // Read stdout in background
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    self?.appendLog(line)
                }
            }
        }

        // Read stderr in background
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    self?.appendLog(line)
                }
            }
        }

        // Termination handler — update isRunning when process exits
        proc.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.appendLog("[BackendManager] Process exited (code \(process.terminationStatus))")
                // Clean up pipe handlers
                self?.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self?.stderrPipe?.fileHandleForReading.readabilityHandler = nil
            }
        }

        // Launch
        do {
            try proc.run()
            self.process = proc
            self.isRunning = true
            appendLog("[BackendManager] Launched uvicorn (PID \(proc.processIdentifier))")
        } catch {
            appendLog("[BackendManager] ERROR: Failed to launch: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop

    func stop() {
        guard let proc = process else { return }

        // Already terminated?
        guard proc.isRunning else {
            isRunning = false
            process = nil
            return
        }

        appendLog("[BackendManager] Sending SIGTERM to PID \(proc.processIdentifier)...")
        proc.terminate() // Sends SIGTERM

        // Wait up to 5 seconds in background, then SIGKILL if needed
        let pid = proc.processIdentifier
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let deadline = Date().addingTimeInterval(5.0)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }

            if proc.isRunning {
                kill(pid, SIGKILL)
                Task { @MainActor [weak self] in
                    self?.appendLog("[BackendManager] Sent SIGKILL — force terminated")
                }
            }

            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.process = nil
                self?.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self?.stderrPipe?.fileHandleForReading.readabilityHandler = nil
            }
        }
    }

    // MARK: - Logging

    private func appendLog(_ line: String) {
        logs.append(line)
        if logs.count > maxLogLines {
            logs.removeFirst(logs.count - maxLogLines)
        }
    }
}
