// PaperMindMac/Services/InboxWatcher.swift
// PaperMind — Monitoriza a pasta iCloud/PaperMind/Inbox/ no Mac

import Foundation

class InboxWatcherSwift {
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func startWatching() {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("❌ Não foi possível abrir: \(path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global()
        )

        source?.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.onChange()
            }
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
        print("👁️ A monitorizar Inbox: \(path)")
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }
}
