# Meeting Notes

Tidy’s local notetaker captures an in-person discussion or an online call, builds a timestamped transcript during the conversation, then prepares a summary, decisions, action items, and open questions when you finish. Action items can be saved to Today with their source text. Notes and transcripts export together as Markdown.

## Using it

1. Open **Meetings** in the sidebar or use **⌘⇧M**. The menu bar also has a Meeting Notes entry.
2. Choose **Online call → System audio (Google Meet)** to record the other participants and your microphone, even when you are only listening. System audio includes sounds from other apps and tabs: mute unrelated sources. **Selected app** limits capture to an application, but browser helper processes can fall outside that filter. **In person** records only the default microphone. Use headphones to avoid echo.
3. Leave **Take notes for me** enabled for the notetaker workflow. It checks transcription setup before recording, processes audio during the meeting, and uses your selected summary provider when you finish. Local Whisper keeps audio on your Mac; cloud transcription uploads audio as the meeting progresses. Turn the option off for manual audio recording with no AI requests during capture. Inform participants and confirm permission to record. Click **Start notetaker** (or **Start recording** in manual mode) and grant macOS Microphone access. Call recording also needs Screen & System Audio Recording access. Tidy remembers the recording mode, audio source, and selected application’s bundle identifier. If macOS denies call audio access, enable Tidy in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Tidy.
4. Watch the microphone/call meters. A warning appears after 20 seconds without audible call audio and clears when it returns. Silence can be normal while no one else is speaking; microphone activity alone does not confirm participant capture. Add optional **Your notes**, saved locally while recording. **Finish & create meeting notes** automatically processes unfinished audio and creates the notes. **Stop & save without summary** preserves audio and completed transcripts for later. In manual recording mode, **Finish recording** saves without calling AI. Closing the window continues recording in the menu bar. Recording stops and saves automatically at **2 hours**.
5. The notetaker shows a **Live transcript** in roughly 20-second audio parts; transcription speed can add delay. The last part finishes after you stop. A failed live request pauses transcription while audio capture continues, and unfinished parts are retried on finish. Use **Play full recording** to hear both tracks together, with their original timing, before or after transcription. Individual transcript play buttons play only their source track. For manual recordings or interrupted work, choose **Create transcript**. The default **Local Whisper** runs on your Mac and consumes no Codex tokens. This action works independently of cloud summary access, including with local-only AI enabled. Failed or cancelled transcription resumes from unfinished parts. The completed transcript opens automatically, preserving mixed Indonesian and English speech.
6. For manual recordings or saved transcripts, choose **Create meeting notes** to send the transcript to your selected summary provider. Codex CLI is the default. This is an explicit, separate use of your provider allowance. View decisions, next steps, and open questions; click a source timestamp to inspect the supporting words beside the notes and play the original audio. At compact widths the source panel appears below the content.
7. Add follow-ups to **Today**, or copy/export the notes and transcript. Personal notes are included in Markdown exports but are not sent for AI summarization. Open **Preferences** for transcription and summary providers, notes language, or a local model; commands and model overrides are under **Advanced model settings**. Regeneration is available there with a notice that it makes another AI request.

**Local Whisper → Codex CLI needs no transcription API key.** Your audio stays on your Mac; the transcript is sent through your existing Codex login. The Codex model override in Meeting Preferences defaults to the model in Settings → Model. An explicit override applies only to Meetings and is captured for the entire summary run. Codex CLI `exec` does not accept audio files directly, so Whisper handles speech recognition before Codex prepares notes.

Gemini and OpenAI transcription remain optional and require their own saved API keys in **Settings → Model**. Automatic uses OpenAI when its key is saved, otherwise Gemini. Explicit provider choices never silently switch providers on a request failure. Cloud transcription uses that provider’s API quota and billing. OpenAI summaries default to `gpt-4.1-mini`; you can enter another Chat Completions model that supports JSON output.

If a saved Call track is silent or the meeting used In person mode, participant audio that was never captured cannot be recovered. Start a new online recording with System audio and confirm the Call meter moves while another participant speaks. If a Call track already contains audio, full playback and transcription can use it without re-recording.

## Optional Google Meet suggestions

Enable **Preferences → Suggest the notetaker when Google Meet is open**. With Accessibility access, Tidy checks the active supported browser window’s address or title and offers to open notetaker setup for a recognized Meet link. It does not read page contents, join as a bot, infer that a call has started, or record automatically. The same meeting is suggested at most once per hour. Browser metadata availability varies; starting the notetaker manually always remains available.

## Local transcription setup

1. Install the local tools: `brew install whisper.cpp ffmpeg`.
2. Download a multilingual GGML Whisper model from the [whisper.cpp model repository](https://huggingface.co/ggerganov/whisper.cpp/tree/main). `ggml-small.bin` balances local resource use and transcription quality; `.en` variants support English only.
3. In **Meetings → Preferences**, select **Local Whisper**, then **Choose…** beside the local model to select the `.bin` file. Tidy also checks `~/Library/Application Support/Tidy/Models/ggml-small.bin` by default. Advanced model settings accept a custom Whisper executable or model path.
4. Create the local transcript first. Then select **Codex CLI** in Preferences and choose **Create meeting notes** when ready.

A speech model is downloaded separately; it is not bundled in the app or fetched during transcription. Local Whisper detects the spoken language, preserves the original words, and does not identify individual speakers in mono recordings. Transcript labels identify the recorded source (Room, Microphone, or Call). Larger or better-suited local models can improve accuracy; always review the transcript.

## Data and behavior

- AppState owns MeetingService, which owns recording, playback and processing. Views use the injected service.
- Audio and meeting JSON live in `~/Library/Application Support/Tidy/Meetings/<meeting UUID>/`, with owner-only directories and files. This is filesystem access protection, not additional encryption.
- In-person microphone capture uses AVAudioEngine; call capture uses ScreenCaptureKit with separate system/app and microphone tracks. System capture excludes Tidy’s own audio. There is no silent expansion from a selected app to all system audio. No screen video is saved.
- Audio is written to bounded PCM WAV parts (20 seconds for the notetaker, 60 seconds for manual recording, or approximately 10 MB), with per-part recovery metadata. Source timestamps preserve gaps. The complete recording is never held in memory.
- Local Whisper converts each part to mono 16 kHz PCM with ffmpeg, then invokes whisper-cli directly with language detection and JSON timestamps. The subprocess receives no API credentials, uses private temporary files, and is stopped on cancellation or timeout.
- Gemini transcription uses `gemini-2.5-flash`, inline WAV audio, and a structured JSON response; OpenAI's `gpt-4o-transcribe-diarize` supplies speaker segments via `diarized_json` and automatic chunking. Both retain the original spoken language and validate timestamps before saving. Speaker labels are scoped to each part: the app does not assume that Speaker A in two parts is the same person, or automatically identify people by name.
- Completed transcriptions are persisted after each part. Failed or cancelled requests can be retried without re-uploading completed parts. Existing saved meetings remain readable, and summaries of fully transcribed meetings require no transcription key. A network request already accepted by the provider can still incur charges even when cancelled locally.
- Summary requests send compact JSON rows with short segment/speaker references and verbatim text. UUIDs, repeated field names, and audio timestamps stay local; evidence references are restored to the original transcript IDs after the final merge. Speaker references remain scoped to their audio part. Requests use up to 48,000 bytes of encoded transcript JSON, splitting unusually long segments without dropping text. This reduces repeated prompts and merge calls; it is a byte budget, not an exact token estimate. Regenerating a summary still makes fresh AI calls.
- Long transcripts are summarized in batches and their notes merged. Decisions, actions and questions must cite valid source segment IDs. Owners and due phrases are retained only when stated, and are not converted into scheduled deadlines automatically.
- Codex summary runs use a temporary private working folder, stdin input, ephemeral mode, read-only sandboxing, and disabled user configuration, rules, shell, app/plugin, browser, computer-use and multi-agent features. They do not reuse Ask AI conversations. A recent CLI supporting these flags is required; incompatible versions fail instead of falling back to the general agent invocation.
- Local-only AI blocks cloud transcription and summaries, including Codex. Recording, playback, and standalone Local Whisper transcription remain available. Summary-only requests require a complete, nonempty transcript; they never silently start transcription.
- Recording duration uses the capture host clock. Audio buffers crossing 2 hours are trimmed and later buffers are discarded, including while UI updates are delayed. Automatic stop saves the final parts and marks the reason in meeting history. It cancels ongoing live transcription and does not start final transcription or summarization; you can finish those from the saved meeting.
- Closing the window leaves recording active; the menu bar shows REC and elapsed time. Tidy's Quit commands finish the recording first. Interrupted sessions are shown with a recovery/retry message after restart.
- Delete a meeting to remove its local audio, transcript and summary. Today tasks already created from it remain. Clear Local History preserves saved meetings, just as it preserves Today notes. Codex/provider account-side retention is separate from these local files.

## Commercial direction

The value proposition is **discussion → evidence-backed notes → follow-through in Today**. This first version implements the workflow and uses the user's provider credentials. It does not add payments, enforce a subscription, or promise unlimited transcription.

A paid beta can test demand for searchable meeting history, decisions with source playback, and task capture together. Validate willingness to pay with people who attend recurring meetings, using recording reliability, summary corrections, repeat usage, and action-item adoption as evidence. A possible BYOK price experiment is $8–12/month for Tidy Pro; this is a product hypothesis, not validated demand.

A managed plan with included AI minutes would need a backend for authentication, metering, billing and API key protection. Never ship a shared commercial API key in the Mac binary. Price against actual uploaded audio minutes: call and microphone are separate tracks, so an hour-long call can produce up to two hours of transcription input. Include retry costs, summary tokens, storage and support before setting an allowance. Cloud transcription pricing and model availability should be rechecked before launch.

## Validation

```sh
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:TidyTests/MeetingTests
```

The focused suite covers closed-part availability, live transcript persistence, personal notes during transcription, automatic final processing without repeating completed parts, setup validation, cancellation, live failure recovery, Meet URL validation, mixed playback samples and timing gaps, system capture without a selected app, both sources reaching the summary, live silence warnings, independent local transcription and explicit cloud notes, summary access failures without transcript loss, standalone retries, personal-note persistence/export, silence handling, compact summary payloads and citation restoration across merges, Unicode-safe request splitting, two-hour automatic stopping in both recording modes, final-buffer trimming, recording chunk sizes, silence, gaps, recovery, private file permissions, transcript timestamps, speaker scope, evidence validation, Gemini/OpenAI routing and request formats, missing keys, incomplete Gemini responses, old-record compatibility, local transcript offsets, honest source labels, custom model routing, subprocess timeout, retries, cancellation, task capture, and light/dark rendering. Synthetic audio is used; tests do not activate a microphone or upload audio.

Before a paid release, complete a signed-device test with a real microphone and a Google Meet participant, including headphones/Bluetooth, permission denial, device switching, app exit, screen lock, a long meeting, intermittent network access, Indonesian/English speech, and both providers. Inspect the actual source audio against transcript and summary. Neither a passing build nor synthetic audio tests establish real-call recording reliability.

## References

- [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Whisper.cpp local speech recognition](https://github.com/ggml-org/whisper.cpp)
- [Codex CLI reference](https://learn.chatgpt.com/docs/cli/reference)
- [Gemini audio understanding](https://ai.google.dev/gemini-api/docs/audio)
- [Codex authentication](https://learn.chatgpt.com/docs/auth)
- [OpenAI file transcription](https://developers.openai.com/api/docs/guides/speech-to-text)
- [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [OpenAI API pricing](https://developers.openai.com/api/docs/pricing)

### Native interaction check

`TidyUITests/MeetingExperienceUITests` loads isolated sample meetings and checks source inspection, transcript navigation, Today action capture, Preferences, the transcript-only state, and recording consent. It never activates the microphone or sends an AI request. Run with a valid development signing identity:

```sh
xcodebuild test -project Tidy.xcodeproj -scheme Tidy -destination 'platform=macOS' \
  -only-testing:TidyUITests/MeetingExperienceUITests \
  DEVELOPMENT_TEAM=<team-id> CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_STYLE=Manual
```

## TypeSafe / Jev excerpt notes

In Settings → Model, save the TypeSafe / Jev API key. In Meetings → Preferences, select **TypeSafe / Jev — transcript excerpts**. Advanced model settings offer `jev-latest` (default), `jev-preview`, `jev-1.13.0`, or a custom model ID. You can configure this before adding a key.

Jev classifies transcript passages; Tidy assembles the original text into highlights, decisions, actions, and questions with source references. It does not rewrite, translate, correct grammar, or transcribe audio. Keep using the existing grammar and transcription providers for those tasks. Notes language is disabled for Jev. Owners and dates are not inferred.

Jev results are labeled **Transcript highlights**. Use **Create summary with Codex** above the excerpts to generate written notes from the full saved transcript and select Codex for future notes. Written notes show **Summary**, **Decisions**, **Action items**, and **Open questions**, with explicit empty states. Existing excerpts remain available if generation fails; no re-transcription is required.

Transcripts go to `https://api.typesafe.ai/v1/systemone`; the key stays in macOS Keychain. Local-only AI blocks this provider. Requests use batches of at most 20 passages and roughly 20 KB of source data. Context outside each batch is unavailable, so review apparent decisions and unresolved questions against the full transcript. Oversized single passages produce an error instead of silently truncating them.

Only classifications with both confidence and selected-option probability at least 0.8 are shown. This is a conservative initial display policy, not a validated accuracy guarantee; uncertain passages remain in the transcript. Live quality, especially mixed-language meetings, needs evaluation after an API key is supplied. HTTP 429/529 responses retry with bounded exponential backoff. Failed processing preserves the transcript and existing notes.

Probability validation allows accumulated two-decimal rounding error across the five categories (for example, totals of 0.98 or 1.02). Unknown categories, missing probabilities, out-of-range scores, inconsistent selected categories, and totals outside that rounding allowance still fail validation. `TypeSafeMeetingTests` covers these boundaries and a 2,867-passage meeting with mocked responses across all batches.
