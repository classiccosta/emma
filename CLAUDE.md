# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Emma (the project folder keeps its old name, Jarvis): a macOS 14+ menu bar voice assistant (SwiftUI `MenuBarExtra`, `LSUIElement`). Say "Emma", speak, and she answers out loud. Everything runs on-device: Whisper for speech-to-text, Qwen3 4B in LM Studio for the reply, and Kokoro-82M for her voice (Apple's synthesizer as fallback). She has no tools yet, so she can't act on apps. Not a git repository; back up before large refactors.

Conversation behaviour (routing, "sir", fillers, padding cuts, greetings…) is documented in `docs/conversation-rules.md`. Read it before changing any reply logic, and update it with the change.

## Commands

```bash
./scripts/build-app.sh          # release build, bundle build/Emma.app, ad-hoc sign, install to /Applications
open /Applications/Emma.app
swift build                     # quick compile check (debug)
swift test                      # unit tests, about 1 s
swiftlint                       # lint Sources/ and Tests/ with .swiftlint.yml
swift scripts/make-icon.swift out.png   # regenerate the 1024px icon PNG
uv run --script sidecars/kokoro/tts_server.py   # run the voice server standalone
```

## Constraints

- Xcode 15 / Swift 5.10 (`swift-tools-version: 5.10`). WhisperKit is pinned to `exact: "0.14.1"`, the last release that builds with it; don't bump without checking. Tests use XCTest (Swift Testing needs Xcode 16).
- Strict concurrency is on and the build and tests have zero warnings; keep it that way. WhisperKit is imported with `@preconcurrency`. `AudioCapture` is `@unchecked Sendable`: its state is only touched on its `emma.audio` queue. Mark `@MainActor` on test methods, not test classes.
- SwiftLint comes from the GitHub release binary in `~/.local/bin` (Homebrew can't build it here). Default limits apply: keep files under 400 lines and functions under 50 by splitting by responsibility, not by raising limits. `scripts/` isn't linted.
- The app must run from its bundle (`Info.plist` has the microphone and speech usage strings), so `swift run` gets no mic access. Ad-hoc signing means macOS may ask for permissions again after a rebuild. Bundle ID `com.diogocosta.emma`.
- LM Studio (`lms`) and `uv` are found by `ToolLocator` (common install folders, then the login shell). Model setup: `lms get "qwen/qwen3-4b-2507@4bit" --mlx -y`.

## Architecture (`Sources/Emma`)

Pipeline: mic → wake word → utterance capture → Whisper → `ReplyRouter` → stock reply or model → reply rules → voice.

| Folder | What's there |
|---|---|
| `App/` | `AssistantEngine`: the phase state machine and wiring (no business rules). `ReplySession`: one reply's streaming state, filters and filler timer, created per reply. `ServiceSupervisor`: starts and warms LM Studio and Kokoro, publishes status. `Permissions`, `Phase`, `EmmaApp` |
| `Audio/` | `AudioCapture` (one `AVAudioEngine` tap, 16 kHz resampling), `Endpointer` (pure capture state machine: pre-roll, RMS end of speech, 120 s segments), `WakeWordDetector` (Apple `SFSpeechRecognizer`, on-device, only while idle), `Transcriber` (WhisperKit `small.en`, VAD chunking, `clean()`) |
| `Conversation/` | `ReplyRouter` (what answers an utterance, in priority order), `SmallTalk` / `Decline` (utterance detectors), `ChatHistory`, `Greeting` (`Greeter`, `DayBoundaries`), `StockPhrases` (defaults) and `StockReplies` (rotations, rendered with the form of address), `ConversationLog`, `TranscriptEntry` |
| `ReplyRules/` | `PersonaPrompt` (the model's instructions, built from settings), `ModelTextFilter` (all code-side rules on model sentences), `AddressRule` (`Address`, `Addresser`), `ReplyHeuristics` (detail offers, padding, advice, made-up app actions), `AsideFilter`, `SpeechText`, `TextPattern` |
| `LLM/` | `LocalLLMClient` (streams LM Studio's OpenAI-compatible API, tool-call loop over `EmmaTool`, conforms to `ChatModel`), `ChatStream`, `LMStudio` (server start, warm-up), `JSON` |
| `Speech/` | `Voice` (picks Kokoro or Apple per reply, speaks, previews), `KokoroSpeech` (batched synthesis, ordered playback, pre-synthesis cache), `KokoroServer` (launches the sidecar), `AppleSpeech`, `SpeechOutput`, `SentenceSplitter` |
| `Settings/` | `Settings` (one `Codable` struct saved as `settings.v1`; `Settings.decode` overlays saved JSON on the defaults, so new fields need no decoding code), `SettingsWindow` (6-tab native window; our type shadows SwiftUI's, so the scene is `SwiftUI.Settings`) |
| `UI/` | `PanelView`, `OrbView`, `Phase+Display` (add any new `Phase` case to its three switches) |
| `Support/` | `ToolLocator` |

`sidecars/kokoro/tts_server.py`: a uv inline script (`kokoro-onnx`) on `127.0.0.1:8880` (`/health`, `POST /speak` → 24 kHz WAV with the requested trailing pause). `build-app.sh` copies it into the bundle; `KokoroServer` launches it with `--parent-pid` so it exits with Emma. Data in `~/Library/Application Support/Emma/kokoro/` (only `bf_emma` is kept); log in `~/Library/Logs/Emma-kokoro.log`.

Tests in `Tests/EmmaTests` mirror the source folders. The pure pieces (`Endpointer`, `ReplyRouter`, `ReplySession`, `ModelTextFilter`, `Addresser`, `PersonaPrompt`, `Settings.decode`…) are unit-tested; the engine's audio and UI wiring is checked by running the app and reading the conversation log.
