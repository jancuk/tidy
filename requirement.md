# PRD: Tidy — macOS Productivity Companion

**Version:** 0.1 (MVP)
**Owner:** Azhar
**Stack:** Swift + SwiftUI (native macOS, target macOS 14+)
**Status:** Draft for Codex implementation

---

## 1. Product Summary

Tidy is a lightweight macOS menu bar app that combines two productivity primitives:

1. **Inline grammar correction** — fix grammar in any text field, anywhere on macOS, via a hotkey on the currently selected text.
2. **Clipboard history** — Raycast-style command palette listing recent clipboard entries, searchable and pasteable.

Both features are invoked via global hotkeys. The app lives in the menu bar; no dock icon by default.

Tagline: _"Tidy your text."_

---

## 2. Goals & Non-Goals

### Goals (MVP)

- Fix grammar of selected text in-place across any macOS app (Mail, Slack, Notes, browsers, etc.) via a single hotkey.
- Maintain a searchable history of the last N clipboard entries (text only, MVP).
- Sub-300ms UX feedback (loading state) for grammar correction; sub-50ms for clipboard palette open.
- Be unobtrusive: menu bar only, no dock icon, low memory footprint.

### Non-Goals (MVP)

- No real-time underline-as-you-type grammar checking (Grammarly-style overlay).
- No rich content in clipboard (images, files) — text only for v1.
- No cloud sync of clipboard or settings.
- No plugin/extension system (deferred to v2 alongside additional features).
- No multi-language UI (English UI; grammar correction itself can handle any language the model supports).

---

## 3. Target User

Power users on macOS who already use tools like Raycast, Alfred, or Grammarly and want both capabilities in one fast native app. Initial user: Azhar (single-user dogfooding before broader release).

---

## 4. Core User Flows

### 4.1 Grammar Correction (Inline)

**Trigger:** User selects text in any app → presses hotkey (default `⌃⌥G`).

**Happy path:**

1. App captures the currently selected text via Accessibility API.
2. Shows a small floating HUD near the cursor: "Tidying…" with spinner.
3. Sends text to configured cloud API (OpenAI / Anthropic / LanguageTool).
4. On response, replaces the selection in-place by simulating paste of the corrected text.
5. HUD shows brief success state ("✓ Tidied") then auto-dismisses (~800ms).

**Edge cases:**

- No text selected → HUD shows "Select text first" then dismisses.
- API failure / timeout (>10s) → HUD shows error with retry option; original text untouched.
- Text >2000 chars → warn user; allow override.
- Accessibility permission missing → prompt user with link to System Settings.

### 4.2 Clipboard History (Palette)

**Trigger:** Hotkey (default `⌃⌥V`).

**Happy path:**

1. Raycast-style centered window appears with search field focused.
2. Lists clipboard entries newest-first, with preview, source app icon, and timestamp.
3. User types to filter; ↑/↓ to navigate; ↵ to paste into the previously focused app.
4. Window auto-dismisses after paste or on Esc / blur.

**Background:**

- A clipboard watcher polls `NSPasteboard.general.changeCount` every 500ms.
- New text entries are persisted to local storage (SQLite via GRDB).
- Retention: last 200 entries OR last 7 days, whichever is smaller (configurable).
- Duplicates collapse to most recent occurrence.

**Edge cases:**

- Password manager copies → if `org.nspasteboard.ConcealedType` flag present, skip.
- Very large entries (>1MB text) → store truncated preview + full content separately.

---

## 5. Functional Requirements

### 5.1 Grammar Correction

| ID   | Requirement                                                                                                                          |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------ |
| GR-1 | Hotkey is user-configurable; default `⌃⌥G`.                                                                                          |
| GR-2 | Reads selected text via Accessibility API (`AXUIElementCopyAttributeValue` with `kAXSelectedTextAttribute`).                         |
| GR-3 | Falls back to copy-via-`⌘C` if AX read fails, then restores original clipboard afterward.                                            |
| GR-4 | Supports pluggable providers: OpenAI, Anthropic, LanguageTool. User chooses one in Settings.                                         |
| GR-5 | API key stored in macOS Keychain, never in plist/UserDefaults.                                                                       |
| GR-6 | Prompt template is fixed for v1: instruct model to return ONLY corrected text, no commentary.                                        |
| GR-7 | Replaces selection in-place by writing corrected text to clipboard, simulating `⌘V`, then restoring original clipboard ~200ms later. |
| GR-8 | Network timeout: 10s. Retries: 0 (user-initiated retry only).                                                                        |
| GR-9 | Logs last 50 corrections locally (original + corrected) for debugging; user can clear from Settings.                                 |

### 5.2 Clipboard History

| ID    | Requirement                                                                                                                  |
| ----- | ---------------------------------------------------------------------------------------------------------------------------- |
| CL-1  | Hotkey is user-configurable; default `⌃⌥V`.                                                                                  |
| CL-2  | Watches `NSPasteboard.general` for changes; supports plain text (`NSPasteboard.PasteboardType.string`) only in v1.           |
| CL-3  | Persists entries to SQLite at `~/Library/Application Support/Tidy/clipboard.sqlite`.                                         |
| CL-4  | Schema: `id`, `content`, `preview` (first 200 chars), `source_app_bundle_id`, `source_app_name`, `created_at`, `char_count`. |
| CL-5  | Search is full-text (SQLite FTS5) over `content`.                                                                            |
| CL-6  | Palette window: centered, ~720×480px, rounded corners, blurred background (`NSVisualEffectView`).                            |
| CL-7  | Each row: preview text, source app icon, relative timestamp ("2m ago").                                                      |
| CL-8  | ↵ pastes into previously focused app; ⌘C copies without pasting; ⌘⌫ deletes entry.                                           |
| CL-9  | Respects `org.nspasteboard.ConcealedType` and `org.nspasteboard.AutoGeneratedType` flags — skips those entries.              |
| CL-10 | Retention configurable in Settings: max entries (default 200) and max age in days (default 7).                               |

### 5.3 Settings & Menu Bar

| ID   | Requirement                                                                          |
| ---- | ------------------------------------------------------------------------------------ |
| SE-1 | Menu bar icon with dropdown: open palette, tidy clipboard text, open Settings, quit. |
| SE-2 | Settings window (SwiftUI) with tabs: General, Grammar, Clipboard, Hotkeys, About.    |
| SE-3 | Launch at login toggle (uses `SMAppService.mainApp`).                                |
| SE-4 | No dock icon: `LSUIElement = true` in Info.plist.                                    |
| SE-5 | First-run onboarding: prompts for Accessibility permission and API key.              |

---

## 6. Non-Functional Requirements

- **Performance:** Palette open <50ms after hotkey. Grammar fix UX feedback <300ms (loading state visible before network roundtrip completes).
- **Memory:** <100MB resident when idle.
- **Privacy:** No telemetry in MVP. Clipboard never leaves the device. Grammar text leaves device only via user-configured API.
- **Security:** API keys in Keychain. SQLite file has `0600` permissions.
- **Reliability:** App must survive sleep/wake, display changes, and Accessibility permission revocation without crashing.

---

## 7. Architecture

┌─────────────────────────────────────────────┐
│ TidyApp (SwiftUI) │
│ - MenuBarExtra │
│ - SettingsScene │
└─────────────────────────────────────────────┘
│ │ │
▼ ▼ ▼
┌─────────────┐ ┌────────────┐ ┌──────────┐
│ HotkeyMgr │ │ Clipboard │ │ Grammar │
│ (KeyboardShortcuts SPM) │ │ Service │
└─────────────┘ └────────────┘ └──────────┘
│ │
▼ ▼
┌────────────┐ ┌──────────────┐
│ GRDB + │ │ Provider │
│ SQLite FTS │ │ (OpenAI/etc) │
└────────────┘ └──────────────┘
│
▼
┌────────────┐
│ Palette UI │
│ (NSPanel + │
│ SwiftUI) │
└────────────┘

### Modules

- `TidyApp` — app entry, menu bar, settings.
- `HotkeyManager` — global hotkeys (recommend `sindresorhus/KeyboardShortcuts` SPM package).
- `ClipboardService` — pasteboard watcher, persistence, search.
- `GrammarService` — selection capture, provider dispatch, replacement.
- `Providers/` — `OpenAIProvider`, `AnthropicProvider`, `LanguageToolProvider`, each conforming to `GrammarProvider` protocol.
- `UI/Palette` — `NSPanel`-backed floating window hosting SwiftUI.
- `UI/HUD` — small floating HUD for grammar feedback.
- `Storage/` — GRDB models, migrations.
- `Keychain/` — wrapper around `Security` framework.

---

## 8. Provider Protocol

```swift
protocol GrammarProvider {
    var id: String { get }
    var displayName: String { get }
    func fixGrammar(_ text: String, language: String?) async throws -> String
}
```

Each provider reads its API key from Keychain via `KeychainStore.read(key: providerId)`.

---

## 9. Permissions

- **Accessibility** — required for reading selected text and simulating paste. Prompt on first grammar use.
- **Input Monitoring** — required for global hotkeys. Prompt on first launch.
- **Network** — outbound HTTPS to configured provider only.

---

## 10. Open Questions (defer or decide before coding)

1. Should grammar correction support a "preview before replace" mode (diff view) as an option? Recommend: **no for MVP**, add in v1.1.
2. Should clipboard history be excluded for specific apps (e.g., 1Password)? Recommend: **yes**, hardcode a denylist of common password managers in addition to the pasteboard flags.
3. Hotkey conflict detection — should the app warn if the chosen hotkey is taken? Recommend: **yes, basic check**.

---

## 11. Milestones

| Milestone   | Scope                                                                            |
| ----------- | -------------------------------------------------------------------------------- |
| M1 (Week 1) | Project scaffold, menu bar app, settings shell, hotkey package wired up.         |
| M2 (Week 2) | Clipboard watcher + SQLite persistence + palette UI (no search yet).             |
| M3 (Week 3) | Clipboard search (FTS5), paste-on-enter, deletion, retention.                    |
| M4 (Week 4) | Grammar service: AX selection capture, OpenAI provider, inline replacement, HUD. |
| M5 (Week 5) | Anthropic + LanguageTool providers, Keychain, error handling, onboarding.        |
| M6 (Week 6) | Polish, packaging (notarized DMG), README.                                       |

---

## 12. Acceptance Criteria (MVP done when)

- [ ] App runs as menu bar only (no dock icon), launches at login.
- [ ] Pressing default hotkey opens clipboard palette in <100ms; arrow keys and search work.
- [ ] Pressing ↵ pastes selected entry into previously focused app correctly.
- [ ] Selecting text in any standard macOS app and pressing grammar hotkey replaces it with corrected text within 5s on a typical broadband connection.
- [ ] API keys are stored in Keychain and never written to disk in plaintext.
- [ ] Clipboard history persists across app restarts and respects retention limits.
- [ ] All three providers are selectable and functional.
- [ ] Accessibility and Input Monitoring permission flows guide the user through System Settings.
      Replaced throughout: app name (Tidy), bundle path (~/Library/Application Support/Tidy/), module name (TidyApp), and HUD copy ("Tidying…" / "✓ Tidied"). Added the tagline under the product summary.
      Want me to draft the Codex scaffolding prompt next — the one you'd paste in to kick off the actual implementation?You said: create me step to how create mac os ap with above requireement,create me step to how create mac os ap with above requireement,9:12 PMClaude responded: Here's a step-by-step guide to building Tidy from zero to a working MVP.Here's a step-by-step guide to building Tidy from zero to a working MVP. I'll structure it so each step is small enough to hand to Codex one at a time.
      markdown# Tidy — Implementation Guide

A step-by-step path from empty folder to working macOS app. Each step is scoped to be ~1–3 hours of work and produces a runnable, testable checkpoint.

---

## Phase 0: Prerequisites

### Step 0.1 — Install tooling

- macOS 14+ (Sonoma or later) on your dev machine.
- Xcode 15+ from the App Store.
- Command line tools: `xcode-select --install`.
- (Optional) Homebrew: `brew install swiftlint xcodes`.

### Step 0.2 — Apple Developer account

- Free Apple ID is enough for local builds and dogfooding.
- Paid Developer Program ($99/yr) only needed for notarized distribution.

### Step 0.3 — Codex / AI coding setup

- Have your editor of choice ready (Cursor, VS Code + Codex CLI, or Xcode itself).
- Keep the PRD open in a side panel for reference.

---

## Phase 1: Project Scaffold (Milestone M1)

### Step 1.1 — Create Xcode project

1. Xcode → File → New → Project → **macOS → App**.
2. Product Name: `Tidy`.
3. Team: your Apple ID.
4. Bundle Identifier: `id.azhar.tidy` (or `com.azhar.tidy`).
5. Interface: **SwiftUI**.
6. Language: **Swift**.
7. Storage: **None** (we'll add GRDB later).
8. Uncheck "Include Tests" for now (add later).
9. Save to `~/Projects/tidy`.

### Step 1.2 — Initialize Git

```bash
cd ~/Projects/tidy
git init
echo ".DS_Store
xcuserdata/
*.xcuserstate
DerivedData/
build/" > .gitignore
git add . && git commit -m "Initial Xcode scaffold"
```

### Step 1.3 — Configure as menu bar app

1. Open `Info.plist` → add key `Application is agent (UIElement)` → set to `YES`. This is `LSUIElement = true`.
2. In `TidyApp.swift`, replace `WindowGroup` with `MenuBarExtra`:

```swift
@main
struct TidyApp: App {
    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "sparkles") {
            Text("Hello from Tidy")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

3. Build & run (⌘R). You should see a sparkles icon in the menu bar and no dock icon.

**Checkpoint:** menu bar icon appears, "Quit" works.

### Step 1.4 — Add Settings scene

1. Add a new SwiftUI file `SettingsView.swift` with a `TabView` containing empty tabs: General, Grammar, Clipboard, Hotkeys, About.
2. In `TidyApp.swift`, add a `Settings` scene:

```swift
Settings {
    SettingsView()
}
```

3. In the `MenuBarExtra`, add a "Settings…" button using `SettingsLink` (macOS 14+).

**Checkpoint:** clicking Settings from menu bar opens a tabbed window.

### Step 1.5 — Add KeyboardShortcuts package

1. File → Add Package Dependencies → enter `https://github.com/sindresorhus/KeyboardShortcuts`.
2. Choose latest version, add to Tidy target.
3. Create `HotkeyNames.swift`:

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let fixGrammar = Self("fixGrammar", default: .init(.g, modifiers: [.control, .option]))
    static let openClipboard = Self("openClipboard", default: .init(.v, modifiers: [.control, .option]))
}
```

4. In the Hotkeys tab of `SettingsView`, add two `KeyboardShortcuts.Recorder` rows.

**Checkpoint:** hotkey recorders show and accept keystrokes. Run the app; hotkeys don't do anything yet — that's fine.

### Step 1.6 — Wire hotkey handlers (stubs)

In `TidyApp.swift` `init()`:

```swift
KeyboardShortcuts.onKeyUp(for: .fixGrammar) {
    print("⌃⌥G pressed")
}
KeyboardShortcuts.onKeyUp(for: .openClipboard) {
    print("⌃⌥V pressed")
}
```

**Checkpoint:** pressing the hotkeys logs to Xcode console. Grant Input Monitoring permission when prompted.

Commit: `git commit -am "M1: scaffold, menu bar, settings, hotkeys wired"`.

---

## Phase 2: Clipboard History (Milestones M2–M3)

### Step 2.1 — Add GRDB package

1. Add `https://github.com/groue/GRDB.swift` via Swift Package Manager.
2. Create folder `Storage/` in project navigator.

### Step 2.2 — Define the database

Create `Storage/Database.swift`:

```swift
import GRDB
import Foundation

final class Database {
    static let shared = try! Database()
    let dbQueue: DatabaseQueue

    private init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("Tidy", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dbURL = folder.appendingPathComponent("clipboard.sqlite")
        dbQueue = try DatabaseQueue(path: dbURL.path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clipboard_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content", .text).notNull()
                t.column("preview", .text).notNull()
                t.column("source_app_bundle_id", .text)
                t.column("source_app_name", .text)
                t.column("created_at", .datetime).notNull()
                t.column("char_count", .integer).notNull()
            }
            try db.create(virtualTable: "clipboard_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clipboard_entries")
                t.column("content")
            }
        }
        try migrator.migrate(dbQueue)
    }
}
```

### Step 2.3 — Clipboard watcher

Create `Services/ClipboardService.swift`:

```swift
import AppKit
import GRDB
import Combine

@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Respect privacy flags
        let types = pb.types ?? []
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        if types.contains(concealed) { return }

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }

        let frontApp = NSWorkspace.shared.frontmostApplication
        save(text: text, app: frontApp)
    }

    private func save(text: String, app: NSRunningApplication?) {
        let preview = String(text.prefix(200))
        try? Database.shared.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO clipboard_entries (content, preview, source_app_bundle_id, source_app_name, created_at, char_count)
                VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [text, preview, app?.bundleIdentifier, app?.localizedName, Date(), text.count])
        }
    }
}
```

Start it in `TidyApp.init()`: `ClipboardService.shared.start()`.

**Checkpoint:** copy some text, then open the SQLite file (`sqlite3 ~/Library/Application\ Support/Tidy/clipboard.sqlite "SELECT * FROM clipboard_entries"`) to verify entries are saving.

### Step 2.4 — Palette window

Create `UI/PaletteWindow.swift` — an `NSPanel` subclass that floats, has no title bar, and centers itself:

```swift
import AppKit
import SwiftUI

final class PaletteWindowController: NSWindowController {
    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: PaletteView())
        panel.center()
        self.init(window: panel)
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible { window.orderOut(nil) }
        else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

Wire `openClipboard` hotkey to call `paletteController.toggle()`.

### Step 2.5 — Palette UI

Create `UI/PaletteView.swift` with:

- A search `TextField` at the top.
- A `List` of entries, with `@FetchRequest`-like loading from GRDB (use `ValueObservation`).
- Rows show preview, app name, relative timestamp.

Add keyboard handling: ↑/↓ to move selection, ↵ to paste, Esc to close.

### Step 2.6 — Paste-on-enter

When ↵ is pressed:

1. Hide the palette.
2. Write the entry's content to `NSPasteboard.general`.
3. Simulate `⌘V` using `CGEvent`:

```swift
func simulatePaste() {
    let src = CGEventSource(stateID: .hidSystemState)
    let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
    cmdDown?.flags = .maskCommand
    let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
    vDown?.flags = .maskCommand
    let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
    vUp?.flags = .maskCommand
    let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
    [cmdDown, vDown, vUp, cmdUp].forEach { $0?.post(tap: .cghidEventTap) }
}
```

### Step 2.7 — Search via FTS5

Filter list using `MATCH` queries against `clipboard_fts`. Debounce input ~150ms.

### Step 2.8 — Retention

Add a daily cleanup task that deletes entries older than N days or beyond N most recent. Run on app launch and once per hour.

**Checkpoint M2–M3 done:** clipboard palette opens, searches, pastes into previous app, respects retention.

Commit: `git commit -am "M2-M3: clipboard history with palette and search"`.

---

## Phase 3: Grammar Correction (Milestones M4–M5)

### Step 3.1 — Keychain wrapper

Create `Keychain/KeychainStore.swift` using `Security` framework — basic `read`, `write`, `delete` for string keys.

### Step 3.2 — Provider protocol

Create `Providers/GrammarProvider.swift`:

```swift
protocol GrammarProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func fixGrammar(_ text: String, language: String?) async throws -> String
}
```

### Step 3.3 — OpenAI provider (first)

Create `Providers/OpenAIProvider.swift`. POST to `https://api.openai.com/v1/chat/completions` with `gpt-4o-mini`. System prompt:
You are a grammar correction tool. Return ONLY the corrected version of the user's text. No explanations, no quotes, no preamble. Preserve the original language, tone, and formatting.

### Step 3.4 — Selection capture

Create `Services/SelectionService.swift`:

- Try AX path first: get focused element via `AXUIElementCreateSystemWide`, then `kAXFocusedUIElementAttribute`, then `kAXSelectedTextAttribute`.
- Fallback: save current clipboard, simulate `⌘C`, wait 100ms, read clipboard, restore later.

### Step 3.5 — Grammar service orchestration

Create `Services/GrammarService.swift`:

1. Capture selection.
2. Show HUD with "Tidying…".
3. Call selected provider.
4. Write result to pasteboard, simulate `⌘V`.
5. Restore previous pasteboard after 200ms.
6. Update HUD to "✓ Tidied", dismiss after 800ms.

Wire `fixGrammar` hotkey to `GrammarService.shared.run()`.

### Step 3.6 — HUD window

Create a tiny `NSPanel` (~200×60) that appears near the cursor (`NSEvent.mouseLocation`) with a spinner and status text.

### Step 3.7 — Settings: Grammar tab

Add a provider picker, API key field (SecureField, stored to Keychain), and a "Test connection" button.

### Step 3.8 — Anthropic + LanguageTool providers

Implement two more providers conforming to the same protocol. Update picker.

### Step 3.9 — Permissions onboarding

On first launch, show a window guiding the user through:

1. Accessibility permission (open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
2. Input Monitoring permission.
3. API key entry.

**Checkpoint M4–M5 done:** select text anywhere, press `⌃⌥G`, text gets replaced with corrected version.

Commit: `git commit -am "M4-M5: grammar correction across providers"`.

---

## Phase 4: Polish & Ship (Milestone M6)

### Step 4.1 — Error handling pass

- Network errors → HUD shows retryable message.
- AX permission revoked → menu bar shows warning badge.
- Empty selection → friendly HUD message.

### Step 4.2 — Launch at login

Use `SMAppService.mainApp.register()`. Toggle in General settings.

### Step 4.3 — App icon

Create an icon (broom or sparkle motif). Use a tool like `Icon Composer` or generate a 1024×1024 PNG and let Xcode handle sizes.

### Step 4.4 — Code signing & notarization (optional)

If you want to share builds:

1. Enable Developer ID signing in Xcode.
2. Archive → Distribute App → Developer ID → Upload for notarization.
3. Staple ticket, create a DMG with `create-dmg`.

### Step 4.5 — README + screenshots

Document install, hotkeys, providers, permissions. Add 2–3 screenshots.

### Step 4.6 — Light testing

- Test grammar fix in Slack, Mail, Chrome (Gmail compose), Notes, VS Code.
- Test clipboard palette repeatedly to check for crashes or leaks.
- Use Instruments → Leaks and Allocations briefly.

---

## Tips for working with Codex

- Feed it the PRD plus the current step. Don't ask it to do multiple phases at once.
- After each step, build & run before moving on. Errors compound fast in Swift.
- When Codex generates AX or `CGEvent` code, double-check key codes against [HIToolbox/Events.h](https://developer.apple.com/documentation/coregraphics/cgkeycode) — they're easy to get wrong.
- For SwiftUI state management, prefer `@StateObject` + `ObservableObject` over `@Observable` macro until you're on macOS 15+ as primary target.
- Keep a `NOTES.md` in the repo with decisions and gotchas — feed it back to Codex for context on later steps.

---

## Quick reference: hotkey → behavior table

| Hotkey            | Action                                    |
| ----------------- | ----------------------------------------- |
| `⌃⌥G`             | Tidy selected text (grammar fix in place) |
| `⌃⌥V`             | Open clipboard palette                    |
| `Esc`             | Close palette / dismiss HUD               |
| `↵` (in palette)  | Paste selected entry                      |
| `⌘⌫` (in palette) | Delete entry                              |
| `⌘C` (in palette) | Copy without pasting                      |
