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

## Build

Open `Tidy.xcodeproj` in Xcode and run the `Tidy` target.

From the command line:

```sh
xcodebuild -project Tidy.xcodeproj -scheme Tidy -destination 'platform=macOS' build
```

Run unit tests:

```sh
xcodebuild test -project Tidy.xcodeproj -scheme Tidy -destination 'platform=macOS' -only-testing:TidyTests
```

## Configuration

Open Tidy settings from the menu bar app.

- Choose a grammar provider.
- Save provider API keys in the Grammar settings tab.
- Configure Ollama base URL and model if using a local model.
- Adjust clipboard retention and hotkeys.

Gemini also checks `VITE_GEMINI_API_KEY` or `GEMINI_API_KEY` from the app environment before falling back to the saved Keychain value.

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

No license has been added yet. Add one before accepting external contributions.
