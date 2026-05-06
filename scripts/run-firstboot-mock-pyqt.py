#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import threading

from PyQt6.QtCore import QObject, QUrl, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine


STATE_FILE = os.environ["THORCH_FIRSTBOOT_STATE_FILE"]
DONE_FILE = os.environ["THORCH_FIRSTBOOT_DONE_FILE"]
QML_FILE = os.environ["THORCH_FIRSTBOOT_QML"]
HELPER = os.environ["THORCH_FIRSTBOOT_CTL"]
BOOT_ROLE = os.environ.get("THORCH_FIRSTBOOT_BOOT_ROLE", "sd")


def load_state():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as handle:
            state = json.load(handle)
            return state if isinstance(state, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


class Backend(QObject):
    applyFinished = pyqtSignal(bool, str, str)
    wifiScanFinished = pyqtSignal(bool, str, "QVariant")
    wifiConnectFinished = pyqtSignal(bool, str)
    rebootStarted = pyqtSignal(bool, str)
    postActionStarted = pyqtSignal(bool, str)
    postActionProgress = pyqtSignal(int, str, str)
    postActionFinished = pyqtSignal(bool, str, str)
    resetFinished = pyqtSignal(bool, str)
    closeRequested = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._done = os.path.exists(DONE_FILE)
        self._state = load_state()

    @pyqtProperty(bool, constant=True)
    def done(self):
        return self._done

    @pyqtProperty("QVariant", constant=True)
    def initialState(self):
        return self._state

    @pyqtProperty(str, constant=True)
    def initialBootRole(self):
        return BOOT_ROLE

    def _run_helper(self, action, payload=None):
        try:
            proc = subprocess.run(
                [HELPER, action],
                input=payload,
                text=True,
                capture_output=True,
                check=False,
            )
        except OSError as exc:
            return False, f"Could not start helper: {exc}", {}

        output = (proc.stdout or "").strip()
        error = (proc.stderr or "").strip()
        result = {}
        if output:
            try:
                result = json.loads(output.splitlines()[-1])
            except json.JSONDecodeError:
                pass
        if output and "output" not in result:
            result["output"] = output
        message = result.get("message") or output or error or f"setup helper exited with {proc.returncode}"
        return proc.returncode == 0, message, result

    def _run_helper_stream(self, action):
        try:
            proc = subprocess.Popen(
                [HELPER, action],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=1,
            )
        except OSError as exc:
            return False, f"Could not start helper: {exc}", {}

        final = {}
        output_lines = []
        if proc.stdout is not None:
            for raw_line in proc.stdout:
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    output_lines.append(line)
                    del output_lines[:-160]
                    continue

                if event.get("event") == "progress":
                    self.postActionProgress.emit(
                        int(event.get("progress", 0)),
                        event.get("message", ""),
                        event.get("output", ""),
                    )
                elif "ok" in event:
                    final = event

        rc = proc.wait()
        if not final:
            output = "\n".join(output_lines)
            return False, output or f"helper exited with {rc}", {"output": output}
        return rc == 0 and bool(final.get("ok")), final.get("message", ""), final

    @pyqtSlot("QVariant")
    def apply(self, config):
        try:
            if hasattr(config, "toVariant"):
                config = config.toVariant()
            payload = json.dumps(dict(config), separators=(",", ":"))
        except Exception as exc:
            self.applyFinished.emit(False, f"Could not read setup settings: {exc}", "")
            return

        ok, message, result = self._run_helper("apply-json", payload)
        self._done = os.path.exists(DONE_FILE)
        self._state = load_state()
        self.applyFinished.emit(ok, message, result.get("nextAction", "") if ok else "")

    @pyqtSlot()
    def scanWifi(self):
        def worker():
            ok, message, result = self._run_helper("wifi-scan-json")
            self.wifiScanFinished.emit(ok, message, result.get("networks", []))

        threading.Thread(target=worker, daemon=True).start()

    @pyqtSlot(str, str)
    def connectWifi(self, ssid, password):
        def worker():
            payload = json.dumps({"ssid": ssid, "password": password}, separators=(",", ":"))
            ok, message, _result = self._run_helper("wifi-connect-json", payload)
            self.wifiConnectFinished.emit(ok, message)

        threading.Thread(target=worker, daemon=True).start()

    @pyqtSlot()
    def skipFirstboot(self):
        self.postActionStarted.emit(True, "Mock: skipping first boot setup.")

        def worker():
            ok, message, result = self._run_helper("finish-json")
            self._done = os.path.exists(DONE_FILE)
            self._state = load_state()
            if ok:
                message = "Mock: first boot setup was skipped."
            self.postActionFinished.emit(ok, message, result.get("output", ""))
            if ok:
                self.closeRequested.emit()

        threading.Thread(target=worker, daemon=True).start()

    @pyqtSlot()
    def resetFirstboot(self):
        def worker():
            ok, message, _result = self._run_helper("reset-json")
            self._done = os.path.exists(DONE_FILE)
            self._state = load_state()
            self.resetFinished.emit(ok, message)

        threading.Thread(target=worker, daemon=True).start()

    @pyqtSlot(str)
    def launchPostAction(self, action):
        labels = {
            "install-internal": "Mock: installing to internal storage.",
            "expand-sd": "Mock: using the rest of the SD card.",
            "finish-firstboot": "Mock: finishing setup.",
            "finish-and-launch-steam": "Mock: finishing setup and launching Steam.",
            "steam-setup": "Mock: installing Steam support.",
            "waydroid-setup": "Mock: installing Android app support.",
        }
        self.postActionStarted.emit(True, labels.get(action, f"Mock: starting {action}."))

        def worker():
            if action == "install-internal":
                ok, message, result = self._run_helper_stream("install-internal-stream-json")
            elif action == "expand-sd":
                ok, message, result = self._run_helper("expand-sd-json")
            elif action == "finish-firstboot":
                ok, message, result = self._run_helper("finish-json")
            elif action == "finish-and-launch-steam":
                ok, message, result = self._run_helper("finish-json")
                if ok:
                    message = "Mock: Steam is launching."
                    result = {"output": "Mock: FEX ready\nMock: Steam launcher ready\nMock: SteamOS mode started"}
            elif action == "steam-setup":
                ok = True
                message = "Mock: Steam support is installed."
                result = {"output": "Mock: FEX ready\nMock: Steam launcher ready"}
            elif action == "waydroid-setup":
                ok, message, result = self._run_helper("mark-waydroid-json")
                if ok:
                    message = "Mock: Android app support is installed."
                    result = {"output": "Mock: Waydroid package installed\nMock: Android images initialized"}
            else:
                ok = False
                message = f"Mock: unsupported action {action}"
                result = {}
            self._done = os.path.exists(DONE_FILE)
            self._state = load_state()
            self.postActionFinished.emit(ok, message, result.get("output", ""))
            if ok and action == "finish-and-launch-steam":
                self.closeRequested.emit()

        threading.Thread(target=worker, daemon=True).start()

    @pyqtSlot()
    def reboot(self):
        self.rebootStarted.emit(True, "Mock reboot requested.")


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()
    backend = Backend()
    backend.closeRequested.connect(app.quit)
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(QML_FILE))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
