# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "kokoro-onnx",
#   "numpy",
# ]
# ///
"""Local Kokoro-82M text-to-speech server for Emma.

Listens on 127.0.0.1 only. Emma launches it with `uv run --script tts_server.py --parent-pid <pid>`
and it exits when that process is gone.

    GET  /health  -> {"ready": bool, "status": str}
    POST /speak   {"text": str, "voice": str, "speed": float} -> audio/wav (16-bit, 24 kHz mono)

Run standalone for testing:
    uv run --script sidecars/kokoro/tts_server.py
"""

import argparse
import io
import json
import os
import sys
import threading
import time
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np

MODEL_URL = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/"
FILES = ["kokoro-v1.0.onnx", "voices-v1.0.bin"]
MODEL_DIR = Path.home() / "Library/Application Support/Emma/kokoro"
# Emma speaks with one voice, so only that voice's style vector is kept on disk.
VOICE = "bf_emma"
VOICES_FILE = MODEL_DIR / "voices-emma.npz"

state = {"ready": False, "status": "starting"}
kokoro = None
synth_lock = threading.Lock()


def log(message):
    print(time.strftime("%H:%M:%S"), message, flush=True)


def download(name):
    target = MODEL_DIR / name
    if target.exists():
        return
    part = target.with_suffix(target.suffix + ".part")
    for attempt in range(1, 4):
        try:
            log(f"downloading {name} (attempt {attempt})")

            def progress(blocks, block_size, total):
                if total > 0:
                    state["status"] = f"downloading voice model {min(100, blocks * block_size * 100 // total)}%"

            urllib.request.urlretrieve(MODEL_URL + name, part, progress)
            part.rename(target)
            return
        except OSError as error:
            log(f"download failed: {error}")
            time.sleep(3)
    raise RuntimeError(f"could not download {name}")


def load():
    global kokoro
    try:
        MODEL_DIR.mkdir(parents=True, exist_ok=True)
        download(FILES[0])
        if not VOICES_FILE.exists():
            download(FILES[1])
            full = MODEL_DIR / FILES[1]
            np.savez(VOICES_FILE, **{VOICE: np.load(full)[VOICE]})
            full.unlink()
            log(f"kept only {VOICE}, removed {full.name}")
        state["status"] = "loading voice model"
        from kokoro_onnx import Kokoro

        kokoro = Kokoro(str(MODEL_DIR / FILES[0]), str(VOICES_FILE))
        state.update(ready=True, status="ready")
        log("ready")
    except Exception as error:  # noqa: BLE001 - reported to Emma through /health
        state["status"] = f"failed: {error}"
        log(state["status"])


def to_wav(samples, sample_rate):
    pcm = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(pcm.tobytes())
    return buffer.getvalue()


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, content_type="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, code, value):
        self.send(code, json.dumps(value).encode())

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, state)
        else:
            self.send_json(404 if state["ready"] else 503, {"error": state["status"]})

    def do_POST(self):
        if self.path != "/speak":
            return self.send_json(404, {"error": "not found"})
        if not kokoro:
            return self.send_json(503, {"error": state["status"]})
        try:
            request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            text = str(request["text"]).strip()
            voice = request.get("voice", VOICE)
            speed = min(2.0, max(0.5, float(request.get("speed", 1.0))))
            lang = "en-gb" if voice.startswith("b") else "en-us"
            started = time.time()
            with synth_lock:
                samples, sample_rate = kokoro.create(text, voice=voice, speed=speed, lang=lang, clause_pause=0.15)
            # Each request is one sentence with its edges trimmed, so add the breath before the next one.
            sentence_pause = min(1.0, max(0.0, float(request.get("pause", 0.3))))
            pause = sentence_pause if text.rstrip("\"')\u201d\u2019").endswith((".", "!", "?")) else sentence_pause / 2
            samples = np.concatenate([samples, np.zeros(int(pause * sample_rate), dtype=samples.dtype)])
            log(f"{time.time() - started:.2f}s for {len(text)} chars")
            self.send(200, to_wav(samples, sample_rate), "audio/wav")
        except Exception as error:  # noqa: BLE001 - one bad sentence must not kill the server
            self.send_json(500, {"error": str(error)})

    def log_message(self, *args):
        pass


def watch_parent(pid):
    while True:
        try:
            os.kill(pid, 0)
        except OSError:
            log("parent gone, exiting")
            os._exit(0)
        time.sleep(2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8880)
    parser.add_argument("--parent-pid", type=int)
    args = parser.parse_args()

    if args.parent_pid:
        threading.Thread(target=watch_parent, args=(args.parent_pid,), daemon=True).start()
    threading.Thread(target=load, daemon=True).start()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    log(f"listening on 127.0.0.1:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
