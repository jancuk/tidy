# Tidy

Tidy is a macOS productivity companion for cleaning up selected text, keeping a searchable clipboard history, and running small developer text tools from a native SwiftUI menu bar app.

## Features

- Grammar cleanup for selected text with a global hotkey.
- Clipboard history with search, retention settings, and a paste palette.
- Developer tools for JSON formatting, JWT decoding, CSV conversion, cron parsing, text diffing, Base64, URL coding, hashes, UUIDs, timestamps, regex testing, and color conversion.
- Pluggable grammar providers: Gemini, OpenAI, Anthropic, LanguageTool, OpenCode, and local Ollama.
- API keys stored in macOS Keychain.

## Requirements

- macOS 15.3 or newer.
- Xcode 16 or newer.
- Accessibility permission for reading and replacing selected text.
- Network access for cloud grammar providers. Ollama and LanguageTool can be used locally depending on your configuration.

## Getting started

### 1. Clone

```sh
git clone https://github.com/your-username/Tidy.git
cd Tidy
```

### 2. Set your Team ID

Create a `Local.xcconfig` file in the repo root (it is gitignored):

```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

Find your Team ID at [developer.apple.com/account](https://developer.apple.com/account) → Membership Details.  
If you just want to run it without code signing, leave it blank — Xcode will prompt you to choose a team on first build.

### 3. Build and run

Open `Tidy.xcodeproj` in Xcode, select the **Tidy** scheme with **My Mac** as destination, and press `⌘R`.

From the command line:

```sh
xcodebuild -project Tidy.xcodeproj -scheme Tidy -destination 'platform=macOS' build
```

Run unit tests:

```sh
xcodebuild test -project Tidy.xcodeproj -scheme Tidy -destination 'platform=macOS' -only-testing:TidyTests
```

### 4. Add an API key

Open Settings (gear icon in the sidebar) → **Grammar** tab → paste your API key and click **Save API Keys**.

| Provider | Where to get a key |
|---|---|
| Gemini Flash | [aistudio.google.com](https://aistudio.google.com) — free tier available |
| OpenAI | [platform.openai.com](https://platform.openai.com) |
| Anthropic | [console.anthropic.com](https://console.anthropic.com) |
| Ollama | No key needed — runs locally |

Gemini also checks the `GEMINI_API_KEY` environment variable before falling back to the saved Keychain value.

### 5. Grant Accessibility permission

Tidy needs Accessibility access to read selected text and paste the corrected version back. macOS will prompt on first use, or go to **System Settings → Privacy & Security → Accessibility**.

## Roadmap

Tidy's long-term direction is a personal Mac assistant for cleaning up text, files, and daily developer context.

### Next: File Tidy

Help developers clean messy folders like `Downloads` and `Desktop` with a safe, preview-first workflow.

- Scan a selected folder locally.
- Group files by type, date, project hint, and usage pattern.
- Propose moves such as screenshots to `Pictures/Screenshots`, installers to `Downloads/Installers`, archives to `Archives`, and documents to useful folders.
- Detect duplicate files, large stale files, build artifacts, old logs, and temporary exports.
- Show every proposed move before anything changes.
- Let the user approve selected changes.
- Keep an undo log for moved or renamed files.

The first version should be rule-based and local-only. AI suggestions can come later for naming, folder recommendations, and explanations.

### Developer Desk Cleanup

Add developer-aware cleanup checks:

- Find old `node_modules`, `.next`, `dist`, `build`, `.turbo`, `coverage`, `DerivedData`, `.xcarchive`, `.profraw`, and log folders.
- Detect abandoned project folders and warn when a Git repo has uncommitted changes.
- Separate "safe to delete", "archive first", and "needs review" recommendations.
- Surface disk usage by project and generated artifact type.

### Work Assistant

Summarize daily work context across tools, with explicit user permission for each integration.

- Slack summary: unread mentions, decisions, blockers, and threads needing replies.
- Jira summary: assigned issues, stale tickets, due dates, blocked work, and recent changes.
- Pending work summary: combine reminders, open tasks, recent clipboard/context, and user-selected sources into a daily brief.
- Meeting prep: summarize related issues, recent messages, and files before a calendar event.
- End-of-day wrap: list completed work, unresolved questions, and suggested next actions.

These integrations should be opt-in, transparent about what data is read, and avoid storing third-party content unless the user explicitly enables local history.

## Privacy And Security

- API keys are stored in macOS Keychain, not in `UserDefaults` or project files.
- Clipboard history is stored locally.
- Clipboard capture skips common password managers and transient pasteboard content.
- Selected text is sent only to the grammar provider you configure. Cloud providers receive the selected text for grammar correction.
- The app requests Accessibility permission so it can read selected text and paste the corrected result.
- The repository intentionally ignores local assistant worktrees, Xcode user state, profiling files, app databases, and `.env` files.

Before publishing a fork, run a local secret scan and review `git status --ignored` to make sure local state is not staged.

## Repository Hygiene

Do not commit:

- `.claude/` or other local assistant worktrees.
- `xcuserdata/` or `*.xcuserstate`.
- `.env` files or API keys.
- Local SQLite databases or profiling output.

## License

MIT — see [LICENSE](LICENSE).
