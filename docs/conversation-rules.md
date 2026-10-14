# Emma's conversation rules

How Emma decides what to say, where each rule lives, and why. Most rules are adjustable in the Settings window; the "Setting" column names the field in `Settings`. When a rule misbehaves, read `~/Library/Logs/Emma-conversation.log` first: it records what Whisper heard, the route taken, the model's raw reply, what was cut and what was said.

Small models drift from prompt rules, so most rules are stated in the prompt (`PersonaPrompt`) **and** enforced in code on every model sentence (`ModelTextFilter`). Test prompt changes by sending sample questions to LM Studio with `curl` before building; with default settings `PersonaPrompt.build` reproduces the prompt tuned in those tests.

## Listening

| Rule | Value | Setting | Code |
|---|---|---|---|
| Wake word "Emma" / "Hey Emma", whole word only ("Gemma" doesn't wake her) | fixed | — | `WakeWordDetector.wakeCount` |
| Silence that ends the user's turn | 3 s default | `endSilence` | `Endpointer` |
| Wait for speech after "Listen now" | 5 s | `noSpeechTimeout` | `Endpointer` |
| Name only ("Emma", nothing after): greet at once, the only exception to end of speech. Whisper still checks the pre-roll and answers a question said before the wake word fired | 1 s | `bareCallWindow` | `AssistantEngine.answerBareCall`, `ReplyRouter.preRollHasRequest` |
| Keep listening after a reply, without the wake word ("Go ahead…"); silence ends it without running Whisper | 6 s, 0 = off | `followUp` | `AssistantEngine.finishReply` |
| Whisper's phantom "Thank you." / "you" from noise is dropped, unless it's a closing within 30 s of a reply | on | `ignoreNoise` | `ReplyRouter.shouldAnswer`, `SmallTalk.isHallucination` |

## Routing (no model call)

`ReplyRouter.route` decides, in this order (unit-tested):

| Order | When | Reply | Then |
|---|---|---|---|
| 1 | Previous reply ended with an offer ("Want…?", "Would you like…", the butler question) and the user refuses ("no", "nothing", "not now") | rotating `declineAcks` ("Very well, sir.") | ends, no follow-up; exchange kept in history |
| 2 | Greeting only ("hi", "hello Emma", "how are you") | period greeting if due, else a `greetReplies` line | fresh conversation, follow-up open |
| 3 | Wrap-up ("thanks", "okay that's all for today", "bye") | rotating `closings` ("Anytime, sir.") | ends, no follow-up |
| 4 | Inconclusive ("um", "oh nothing", "never mind") and `butlerCheck` on | `anythingElse` ("Is there anything else I can do for you, sir?") | it counts as an offer, so "no" ends politely |
| 5 | Anything else | the model | feelings ("I'm sad", "bad day") turn on the no-advice filter |

## Greetings and address

| Rule | Setting | Code |
|---|---|---|
| "Hello sir. Good morning/afternoon/evening." on the first reply after launch and of each part of the day (late night counts as the evening before). Alone, without a question after it | `periodGreeting`, `morningStart`/`afternoonStart`/`eveningStart` | `Greeter`, `StockReplies.greeting` |
| The form of address ("sir") appears only in greetings and goodbyes, at most once per reply; it's added to a model goodbye that lacks it and removed from anything else | `addressForm`, `customAddress`, `addressInGreetings`, `addressInGoodbyes` | `Addresser` (`AddressRule.swift`), `Address.render` for stock phrases |

## What the model says

| Rule | Setting | Prompt | Code net |
|---|---|---|---|
| One sentence; a second only with new information | `replyLength` | yes | padding after the first sentence is cut: reassurance ("Quick and easy"), jokey asides ("Honestly, …"), 1–2 word lines, emoji |
| Jokes rarely (about 1 in 5), inside the sentence, never on serious topics | `jokes` | yes | — |
| No "Want more detail?" offers | `offerMoreDetail` | yes | `ReplyHeuristics.isDetailOffer` |
| Feelings are acknowledged, never advised | `emotionalTone` | yes | for feelings: first sentence only, advice cut, empathy line if nothing's left |
| No invented life (meetings, plans) and no topics the user didn't raise | fixed | yes | — |
| No pretending to use apps (Emma has no tools yet): "I can't open apps yet." | fixed | yes | `ReplyHeuristics.isCapabilityClaim` cuts the claim and what follows, adds "I can't do that yet." Relax this when tools are added |
| Bracketed asides of 3+ words removed | fixed | yes | `AsideFilter` |
| Symbols spoken as words ("86 degrees Fahrenheit", "5 percent"); no markdown, emoji or links read aloud | fixed | yes | `SpeechText.clean` (voice only; the panel keeps the text) |
| Knows today's date and time | fixed | added per request | `LocalLLMClient.now()` |
| Temperature 0.5 (0.7 kept adding quips) | `temperature` | — | — |

## Timing and voice

| Rule | Value | Setting | Code |
|---|---|---|---|
| Filler ("One sec.") after silence while the model hasn't answered; at most 2 per reply, 4 s apart; spoken only | 2 s | `fillersEnabled`, `fillerDelay` | `ReplySession.scheduleFiller` |
| Pre-warm the model and voice on the wake word when idle for 60 s (an idle model gets swapped out on 8 GB and the first request takes ~10 s) | fixed | — | `ServiceSupervisor.prewarm` |
| Voice: Kokoro "Emma" (`bf_emma`, British); Apple voice as fallback | fixed | — | `Voice` |
| Speed and the pause after each sentence | 0.95, 0.3 s | `speechSpeed`, `sentencePause` | `KokoroSpeech`, `sidecars/kokoro/tts_server.py` |
| First sentence synthesized alone (fast start), the rest together (intonation flows; per-sentence sounded monotone) | fixed | — | `KokoroSpeech` |
| Memory: last 20 messages, reset after 10 min idle, on Clear or on a greeting | 20, 10 min | `historyMessages`, `conversationResetMinutes` | `ChatHistory` |

## Tried and rejected

- Intonation (Oct 2026): misaki G2P, a voice blend with `af_heart`, and a DSP pitch rise on questions. Kokoro doesn't raise pitch on `?` with any of them; batching sentences was preferred by ear.
- A filler 1 s after every reply started: it raced the model's ~1 s first sentence and played before quick answers.
- "sir" in every reply, then in questions: the user narrowed it to greetings and goodbyes.
