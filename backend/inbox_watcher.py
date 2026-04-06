"""
PaperMind — Inbox Watcher.

Monitoriza a pasta iCloud/PaperMind/Inbox/.
Quando aparece um novo ficheiro, chama o callback para processar.
"""

import time
import threading
from pathlib import Path
from typing import Callable, Set

SUPPORTED_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png", ".heic"}


class InboxWatcher:
    def __init__(self, inbox_path: str, on_new_file: Callable[[str], None]):
        self.inbox_path = Path(inbox_path)
        self.on_new_file = on_new_file
        self.known_files: Set[Path] = set()
        self._running = False
        self._thread = None

    def start(self):
        """Inicia a monitorização em background."""
        self.inbox_path.mkdir(parents=True, exist_ok=True)
        self._running = True
        self.known_files = set(self.inbox_path.glob("*"))
        self._thread = threading.Thread(target=self._watch, daemon=True)
        self._thread.start()
        print(f"A monitorizar: {self.inbox_path}")

    def stop(self):
        """Para a monitorização."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)

    def _watch(self):
        """Loop de polling — verifica novos ficheiros a cada 2 segundos."""
        while self._running:
            try:
                current = set(self.inbox_path.glob("*"))
                new_files = current - self.known_files

                for f in new_files:
                    if f.suffix.lower() in SUPPORTED_EXTENSIONS:
                        print(f"Novo ficheiro detectado: {f.name}")
                        try:
                            self.on_new_file(str(f))
                        except Exception as e:
                            print(f"Erro ao processar {f.name}: {e}")

                self.known_files = current
            except Exception as e:
                print(f"Erro no watcher: {e}")

            time.sleep(2)
