# Tidy — Agent Reference

## What This App Is

Tidy is a native macOS menu-bar + window app (macOS 15.3+, Xcode 16+, Swift/SwiftUI) that does four things:

1. **Grammar fix** — hotkey `⌃⌥G` reads the selected text in any app via Accessibility API (falls back to ⌘C snapshot), sends it to the configured AI provider, and pastes the corrected text back.
2. **Clipboard history** — polls `NSPasteboard` every 0.5 s, stores entries in a local SQLite database with FTS5 full-text search, and surfaces them via a floating palette (`⌃⌥V`) or the main window.
3. **File Tidy** — scans a user-chosen folder, classifies files (screenshots, installers, archives, documents, media, logs, build artifacts, duplicates, large-stale), proposes moves, lets the user approve, and keeps an undo log.
4. **Developer tools** — JSON formatter/validator, JWT decoder, text diff, Unix time converter, CSV↔JSON, cron parser — all local, no network.

## Project Layout

```
Tidy/
  TidyApp.swift              — @main, WindowGroup + MenuBarExtra + Settings scene
  ContentView.swift          — unused stub
  Models/
    ClipboardEntry.swift
    FileTidyModels.swift     — FileTidyCategory, FileTidyRisk, FileTidyProposal, FileTidyScanResult, etc.
  Providers/
    GrammarProvider.swift    — GrammarProvider protocol, GrammarProviderFactory, prompt constants
    AnthropicProvider.swift
    GeminiProvider.swift
    OpenAIProvider.swift
    OllamaProvider.swift
    OpenCodeProvider.swift
    LanguageToolProvider.swift
  Services/
    AppSettings.swift        — Hotkey struct, AppDefaults enum keys, UserDefaults.registerTidyDefaults()
    AppState.swift           — @MainActor ObservableObject; owns all services, wires hotkeys
    ClipboardService.swift   — NSPasteboard poller, denies password-manager bundle IDs
    FileTidyService.swift    — scan, apply, undo logic; SHA-256 duplicate detection
    GrammarService.swift     — reads selection (AX API or ⌘C fallback), calls provider, pastes back
    HotkeyManager.swift      — Carbon RegisterEventHotKey wrappers
    KeyboardSimulator.swift  — CGEvent ⌘C / ⌘V simulation
    PasteboardSnapshot.swift — saves/restores pasteboard around clipboard ops
    Permissions.swift        — AXIsProcessTrusted, request/open Accessibility settings
    SuggestionMonitor.swift  — watches frontmost-app text changes for auto-suggest
    DeveloperTooling.swift   — dev tool implementations
  Storage/
    ClipboardStore.swift     — SQLite (WAL mode) + FTS5 virtual table; dedup on insert
    CorrectionLogStore.swift — corrections.json (last 50 entries, prepend-newest)
    FileTidyUndoLogStore.swift
  UI/
    DashboardView.swift      — IconRailView sidebar + per-section content views
    SettingsView.swift
    FileTidyView.swift
    DeveloperToolsView.swift
    ClipboardPaletteController.swift
    HUDController.swift      — floating toast (loading / success / warning / error)
    SuggestionPopupController.swift
    ColorExtension.swift     — Color(hex:) helper
  Keychain/
    KeychainStore.swift      — reads/writes API keys (service = "Tidy", account = provider ID)
```

## Architecture

- **Single `AppState`** (`@MainActor ObservableObject`) is created in `TidyApp` and injected via `.environmentObject`. It owns every service.
- Views inject dependencies with `@EnvironmentObject` — never create services themselves.
- All UI code is on the main actor. Background work uses `Task { @MainActor in … }`.
- `ClipboardStore` serialises its own SQLite access on a private `DispatchQueue`.
- `GrammarProviderFactory` is the single factory — add new providers there and in `GrammarProviderID`.

## Key Enums & Constants

| Symbol | Location | Purpose |
|--------|----------|---------|
| `AppDefaults` | `AppSettings.swift` | `UserDefaults` string keys |
| `GrammarProviderID` | `GrammarProvider.swift` | `.gemini`, `.openAI`, `.anthropic`, `.languageTool`, `.openCode`, `.ollama` |
| `DashboardSection` | `DashboardView.swift` | `.home`, `.fileTidy`, `.clipboard`, `.developerTools`, `.correctionLog`, `.settings` |
| `FileTidyCategory` | `FileTidyModels.swift` | 12 file categories used for proposal classification |
| `FileTidyRisk` | `FileTidyModels.swift` | `.low`, `.review`, `.high` — controls default selection |
| `GrammarProviderError` | `GrammarProvider.swift` | `.missingAPIKey`, `.invalidResponse`, `.httpError`, `.emptyCorrection` |

## Default Hotkeys

| Action | Default | `AppDefaults` key |
|--------|---------|------------------|
| Fix grammar | `⌃⌥G` | `grammarHotkey` |
| Clipboard palette | `⌃⌥V` | `clipboardHotkey` |

Both are stored as display strings (e.g. `"control+option+g"`) and parsed back by `Hotkey.parse(_:fallback:)`.

## Data Stored on Disk

| File | Path | Format |
|------|------|--------|
| Clipboard DB | `~/Library/Application Support/Tidy/clipboard.sqlite` | SQLite WAL + FTS5 |
| Corrections log | `~/Library/Application Support/Tidy/corrections.json` | JSON array, max 50 |
| Undo log | `~/Library/Application Support/Tidy/` | (FileTidyUndoLogStore) |
| API keys | macOS Keychain | service `"Tidy"`, account = provider raw ID |

## Grammar Provider System

Every provider conforms to `GrammarProvider`:

```swift
protocol GrammarProvider {
    var id: String { get }
    var displayName: String { get }
    func fixGrammar(_ text: String, language: String?) async throws -> String
}
```

`GrammarProviderFactory.provider(for:)` instantiates the right one. The shared system prompt (`GrammarProviderFactory.prompt`) and input wrapper (`GrammarProviderFactory.inputPrompt(for:)`) are used by all providers to prevent prompt injection from the corrected text.

## Build & Test

```sh
# Build
xcodebuild -project Tidy.xcodeproj -scheme Tidy -destination 'platform=macOS' build

# Run unit tests only
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' -only-testing:TidyTests

# Run in Xcode: scheme Tidy, destination My Mac, ⌘R
```

`Local.xcconfig` in the repo root (gitignored) must contain `DEVELOPMENT_TEAM = <your-team-id>` for signing. Leave blank to let Xcode prompt.

## Required Permissions

- **Accessibility** — must be granted for `GrammarService` to read selected text and paste corrections. Requested on first launch; can be opened via `Permissions.openAccessibilitySettings()`.
- **Network** — cloud providers (Gemini, OpenAI, Anthropic, OpenCode) need network access. Ollama and LanguageTool are local.

## What NOT to Commit

- `.claude/` and `worktrees/`
- `xcuserdata/` or `*.xcuserstate`
- `Local.xcconfig`
- `*.sqlite`, `*.profraw`, `corrections.json`
- `.env` files or API keys

## Adding a New Grammar Provider

1. Create `Tidy/Providers/MyProvider.swift` conforming to `GrammarProvider`.
2. Add a case to `GrammarProviderID` in `GrammarProvider.swift`.
3. Add the case to `GrammarProviderFactory.provider(for:)`.
4. Add the case to `SettingsView` provider picker UI.
5. Store/retrieve its API key via `KeychainStore` with account = `GrammarProviderID.rawValue`.

## Adding a New Developer Tool

1. Add a case to `DeveloperTool` enum in `DeveloperTooling.swift`.
2. Implement the tool logic there.
3. Add the UI branch in `DeveloperToolsView.swift`.

## Clipboard Privacy

`ClipboardService` skips entries whose `sourceAppBundleID` matches the `deniedBundleIDs` set (1Password, LastPass, Bitwarden, Dashlane). Add new password managers there if needed.
