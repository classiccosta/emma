# Emma

A macOS menu bar voice assistant that runs entirely on this Mac. Say "Emma", ask something, and she answers out loud. After she speaks you can reply for a few seconds without the wake word. Emma has no memory between conversations and takes no actions on your apps; replies are spoken and shown in the panel.

## Run

```bash
./scripts/build-app.sh
open /Applications/Emma.app
```

The script builds `build/Emma.app` and installs it to `/Applications`, so it can be launched from Spotlight, Launchpad or the Dock.

Needs [LM Studio](https://lmstudio.ai) with `qwen/qwen3-4b-2507` downloaded (`lms get "qwen/qwen3-4b-2507@4bit" --mlx -y`) and [uv](https://docs.astral.sh/uv/) at `~/.local/bin/uv`. Emma starts LM Studio's server and her voice server herself.

First launch asks for Microphone and Speech Recognition access, downloads the Whisper model (about 250 MB) and the Kokoro voice model (about 340 MB). Later launches are offline.

## How it works

| Stage | Component | Where |
|---|---|---|
| Mic capture, 16 kHz resample, end-of-speech detection | `AVAudioEngine` + RMS threshold | `Sources/Emma/Audio/` |
| Wake word "Emma" | Apple `SFSpeechRecognizer`, on-device | `Audio/WakeWordDetector.swift` |
| Transcription | WhisperKit (`small.en`, Neural Engine) | `Audio/Transcriber.swift` |
| Deciding what answers | Stock replies for greetings, goodbyes, declined offers; the model otherwise | `Conversation/ReplyRouter.swift` |
| Reply | Qwen3 4B in LM Studio, local server | `LLM/`, instructions in `ReplyRules/PersonaPrompt.swift` |
| Reply rules | One sentence, "sir" only in greetings and goodbyes, no padding, no pretend app access | `ReplyRules/`, documented in `docs/conversation-rules.md` |
| Voice | Kokoro-82M `bf_emma` sidecar (Apple voice as fallback) | `Speech/`, `sidecars/kokoro/tts_server.py` |
| Menu bar panel and Settings window | SwiftUI `MenuBarExtra` and `Settings` scene | `UI/`, `Settings/` |

## Notes

- WhisperKit is pinned to 0.14.1, the last release that builds with Xcode 15 / Swift 5.10.
- The app is signed ad-hoc, so macOS may ask for permissions again after each rebuild.
- Logs: conversations in `~/Library/Logs/Emma-conversation.log`, the voice server in `~/Library/Logs/Emma-kokoro.log`.
