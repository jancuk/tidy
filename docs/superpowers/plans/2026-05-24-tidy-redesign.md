# Tidy Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Tidy's labeled NavigationSplitView sidebar with a 54px icon rail, redesign the Home screen as a Command Center, add user-selectable Light/Dark/System appearance, slim the Developer Tools sidebar, and move Settings inline — all per the approved design spec.

**Architecture:** A plain `HStack` containing a custom `IconRailView` (54px) + a `Divider` + a detail `Group` replaces `NavigationSplitView`. Appearance is stored as `"system"|"light"|"dark"` in `AppStorage` and applied via `.preferredColorScheme` on the `WindowGroup`. All color surfaces use adaptive `NSColor` tokens wherever possible so dark mode is free; the two exceptions (hero card gradient) use explicit hex values per mode.

**Tech Stack:** SwiftUI, AppKit, Swift Testing framework (`@Test` / `#expect`), macOS 15.3+, Xcode 16+.

**Spec:** `docs/superpowers/specs/2026-05-24-tidy-redesign-design.md`

---

## File Map

| File | Action | What changes |
|---|---|---|
| `Tidy/Services/AppSettings.swift` | Modify | Add `appearanceMode` key to `AppDefaults`; register `"system"` default |
| `Tidy/TidyApp.swift` | Modify | Read `appearanceMode`; apply `.preferredColorScheme` to `WindowGroup` |
| `Tidy/UI/ColorExtension.swift` | **Create** | `Color(hex:)` initializer used by hero card gradients |
| `Tidy/UI/DashboardView.swift` | Modify | Add `.settings` case; replace `NavigationSplitView` with `HStack` + `IconRailView`; new `HomeView`; new `ClipboardListView` |
| `Tidy/UI/SettingsView.swift` | Modify | Remove fixed window frame; add appearance picker; restyle as inline grouped view |
| `Tidy/UI/DeveloperToolsView.swift` | Modify | Slim sidebar to 200px; graphite active row; lighter panel headers |
| `TidyTests/TidyTests.swift` | Modify | Add tests for new `AppDefaults` key, `Color(hex:)`, and `DashboardSection` |

---

## Task 1: Add `appearanceMode` key to AppDefaults

**Files:**
- Modify: `Tidy/Services/AppSettings.swift`
- Test: `TidyTests/TidyTests.swift`

- [ ] **Step 1: Write the failing test**

Open `TidyTests/TidyTests.swift` and add inside `struct TidyTests`:

```swift
@Test func appearanceModeDefaultKeyExists() {
    #expect(AppDefaults.appearanceMode == "appearanceMode")
}

@Test func appearanceModeDefaultIsSystem() {
    // registerTidyDefaults writes "system" for a fresh UserDefaults
    let defaults = UserDefaults(suiteName: "test.tidy.appearance")!
    defaults.registerTidyDefaults()
    #expect(defaults.string(forKey: AppDefaults.appearanceMode) == "system")
    defaults.removePersistentDomain(forName: "test.tidy.appearance")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -only-testing:TidyTests/TidyTests/appearanceModeDefaultKeyExists \
  2>&1 | grep -E "FAIL|PASS|error:"
```

Expected: compilation error — `AppDefaults.appearanceMode` does not exist yet.

- [ ] **Step 3: Add the key and default**

In `Tidy/Services/AppSettings.swift`, add to `enum AppDefaults`:

```swift
static let appearanceMode = "appearanceMode"
```

In `registerTidyDefaults()`, add to the `register(defaults:)` dictionary:

```swift
AppDefaults.appearanceMode: "system",
```

The full updated dictionary should be:

```swift
register(defaults: [
    AppDefaults.grammarHotkey: Hotkey.grammarDefault.displayValue,
    AppDefaults.clipboardHotkey: Hotkey.clipboardDefault.displayValue,
    AppDefaults.grammarProvider: GrammarProviderID.gemini.rawValue,
    AppDefaults.clipboardMaxEntries: 200,
    AppDefaults.clipboardMaxAgeDays: 7,
    AppDefaults.didCompleteFirstRun: false,
    AppDefaults.autoSuggestEnabled: true,
    AppDefaults.openCodeModel: "deepseek-v4-flash-free",
    AppDefaults.ollamaBaseURL: "http://localhost:11434",
    AppDefaults.ollamaModel: "gnokit/improve-grammar",
    AppDefaults.appearanceMode: "system",
])
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -only-testing:TidyTests/TidyTests/appearanceModeDefaultKeyExists \
  -only-testing:TidyTests/TidyTests/appearanceModeDefaultIsSystem \
  2>&1 | grep -E "FAIL|PASS|error:"
```

Expected: both `PASS`.

- [ ] **Step 5: Commit**

```bash
git add Tidy/Services/AppSettings.swift TidyTests/TidyTests.swift
git commit -m "feat: add appearanceMode key to AppDefaults"
```

---

## Task 2: Apply preferredColorScheme in TidyApp

**Files:**
- Modify: `Tidy/TidyApp.swift`

- [ ] **Step 1: Replace TidyApp.swift with the updated version**

Replace the entire contents of `Tidy/TidyApp.swift` with:

```swift
import AppKit
import SwiftUI

@main
struct TidyApp: App {
    @StateObject private var appState = AppState()
    @AppStorage(AppDefaults.appearanceMode) private var appearanceMode = "system"

    var body: some Scene {
        WindowGroup("Tidy") {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 820, minHeight: 540)
                .preferredColorScheme(resolvedColorScheme)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Tidy", systemImage: "sparkles") {
            Button {
                appState.openPalette()
            } label: {
                Label("Open Clipboard Palette", systemImage: "doc.on.clipboard")
            }

            Button {
                appState.tidyClipboardText()
            } label: {
                Label("Tidy Clipboard Text", systemImage: "textformat")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Tidy", systemImage: "power")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(resolvedColorScheme)
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
```

Key changes vs the old file:
- `@Environment(\.openSettings)` removed — Settings no longer opened from MenuBarExtra; the rail icon handles it inside the main window. The `Settings {}` scene stays so ⌘, still works.
- `minWidth` drops from 960 to 820 to match the design.
- `.preferredColorScheme(resolvedColorScheme)` applied to both the window group and the Settings scene.

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` (warnings OK).

- [ ] **Step 3: Commit**

```bash
git add Tidy/TidyApp.swift
git commit -m "feat: apply preferredColorScheme from AppStorage in TidyApp"
```

---

## Task 3: Add Color(hex:) extension

**Files:**
- Create: `Tidy/UI/ColorExtension.swift`
- Test: `TidyTests/TidyTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `TidyTests/TidyTests.swift`:

```swift
@Test func colorHexParsesRRGGBB() {
    // Verify the initializer doesn't crash and produces a non-clear color.
    // We compare the resolved RGB components rather than Color equality.
    let c = Color(hex: "#2c2c2e")
    // Convert to NSColor to read components
    let ns = NSColor(c).usingColorSpace(.sRGB)!
    #expect(abs(ns.redComponent   - (0x2c / 255.0)) < 0.01)
    #expect(abs(ns.greenComponent - (0x2c / 255.0)) < 0.01)
    #expect(abs(ns.blueComponent  - (0x2e / 255.0)) < 0.01)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -only-testing:TidyTests/TidyTests/colorHexParsesRRGGBB \
  2>&1 | grep -E "FAIL|PASS|error:"
```

Expected: compilation error — `Color(hex:)` not defined.

- [ ] **Step 3: Create ColorExtension.swift**

Create `Tidy/UI/ColorExtension.swift` with:

```swift
import SwiftUI

extension Color {
    /// Initialise from a six-digit hex string, with or without a leading `#`.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                     .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >>  8) & 0xFF) / 255
        let b = Double( rgb        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

Also add `ColorExtension.swift` to the Xcode project target. (In Xcode: right-click `Tidy/UI` group → Add Files, or it is auto-picked up if using folder references.)

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -only-testing:TidyTests/TidyTests/colorHexParsesRRGGBB \
  2>&1 | grep -E "FAIL|PASS|error:"
```

Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add Tidy/UI/ColorExtension.swift TidyTests/TidyTests.swift
git commit -m "feat: add Color(hex:) extension"
```

---

## Task 4: Add `.settings` case to DashboardSection + write IconRailView

**Files:**
- Modify: `Tidy/UI/DashboardView.swift`
- Test: `TidyTests/TidyTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `TidyTests/TidyTests.swift`:

```swift
@Test func dashboardSectionIncludesSettings() {
    #expect(DashboardSection.allCases.contains(.settings))
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -only-testing:TidyTests/TidyTests/dashboardSectionIncludesSettings \
  2>&1 | grep -E "FAIL|PASS|error:"
```

Expected: compilation error — `.settings` does not exist on `DashboardSection`.

- [ ] **Step 3: Update DashboardSection enum**

Replace the `DashboardSection` enum at the top of `Tidy/UI/DashboardView.swift` with:

```swift
enum DashboardSection: String, Identifiable, CaseIterable {
    case home
    case clipboard
    case developerTools
    case correctionLog
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:          "Home"
        case .clipboard:     "Clipboard History"
        case .developerTools: "Developer Tools"
        case .correctionLog: "Correction Log"
        case .settings:      "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:          "house"
        case .clipboard:     "doc.on.clipboard"
        case .developerTools: "chevron.left.forwardslash.chevron.right"
        case .correctionLog: "checkmark.rectangle"
        case .settings:      "gear"
        }
    }

    /// Whether this section appears in the bottom rail group (below the divider).
    var isBottomGroup: Bool { self == .settings }
}
```

- [ ] **Step 4: Add IconRailView below DashboardSection**

After the `DashboardSection` enum, add the new `IconRailView`. Add this code before the `DashboardView` struct:

```swift
struct IconRailView: View {
    @Binding var selection: DashboardSection

    private var topSections: [DashboardSection] {
        DashboardSection.allCases.filter { !$0.isBottomGroup }
    }
    private var bottomSections: [DashboardSection] {
        DashboardSection.allCases.filter { $0.isBottomGroup }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(topSections) { section in
                railButton(section)
            }
            Spacer()
            Divider()
                .frame(width: 28)
                .padding(.vertical, 4)
            ForEach(bottomSections) { section in
                railButton(section)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 54)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    @ViewBuilder
    private func railButton(_ section: DashboardSection) -> some View {
        let active = selection == section
        Button {
            selection = section
        } label: {
            ZStack(alignment: .leading) {
                // Active left-edge indicator bar
                if active {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(NSColor.labelColor).opacity(0.7))
                        .frame(width: 3, height: 18)
                        .offset(x: -1)
                }
                // Icon background + icon
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active
                        ? Color(NSColor.labelColor).opacity(0.11)
                        : Color.clear)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(active
                                ? Color(NSColor.labelColor)
                                : Color(NSColor.secondaryLabelColor))
                    }
            }
            .frame(width: 54, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -only-testing:TidyTests/TidyTests/dashboardSectionIncludesSettings \
  2>&1 | grep -E "FAIL|PASS|error:"
```

Expected: `PASS`.

- [ ] **Step 6: Commit**

```bash
git add Tidy/UI/DashboardView.swift TidyTests/TidyTests.swift
git commit -m "feat: add settings section and IconRailView to DashboardView"
```

---

## Task 5: Replace DashboardView body with icon rail layout

**Files:**
- Modify: `Tidy/UI/DashboardView.swift`

- [ ] **Step 1: Replace DashboardView struct**

Replace the entire `DashboardView` struct with:

```swift
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: DashboardSection = .home

    var body: some View {
        HStack(spacing: 0) {
            IconRailView(selection: $selection)

            Group {
                switch selection {
                case .home:
                    HomeView()
                case .clipboard:
                    ClipboardListView()
                        .environmentObject(appState.clipboardService)
                case .developerTools:
                    DeveloperToolsView()
                case .correctionLog:
                    CorrectionLogView()
                case .settings:
                    SettingsView()
                        .environmentObject(appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
```

Note: `NavigationSplitView` is gone. The `@Environment(\.openSettings)` import and the toolbar button are also gone — the gear icon in the rail handles navigation to Settings.

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' 2>&1 | grep -E "^.*error:|BUILD"
```

Expected: `BUILD SUCCEEDED`. If `HomeView` or `CorrectionLogView` references missing bindings from the old structure, fix them in the next task.

- [ ] **Step 3: Commit**

```bash
git add Tidy/UI/DashboardView.swift
git commit -m "refactor: replace NavigationSplitView with icon rail HStack in DashboardView"
```

---

## Task 6: Implement new HomeView (Command Center)

**Files:**
- Modify: `Tidy/UI/DashboardView.swift`

- [ ] **Step 1: Replace HomeView with Command Center layout**

Find and replace the entire `HomeView` struct (and its helpers `statusCard`, `actionsGrid`, `hotkeysCard`, `statusBadge`, `hotkeyRow`, `ActionCard`, `providerDisplayName`) in `DashboardView.swift` with:

```swift
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppDefaults.autoSuggestEnabled) private var autoSuggestEnabled = true
    @AppStorage(AppDefaults.grammarProvider) private var grammarProvider = GrammarProviderID.gemini.rawValue
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                statusRow
                quickAccessSection
                hotkeysCard
                Spacer(minLength: 12)
            }
            .padding(22)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(permissionTimer) { _ in
            accessibilityTrusted = Permissions.isAccessibilityTrusted
        }
    }

    // MARK: Hero Card

    @Environment(\.colorScheme) private var colorScheme

    private var heroGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "#48484a"), Color(hex: "#6e6e73")],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [Color(hex: "#2c2c2e"), Color(hex: "#505050")],
                startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Tidy Selected Text")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Select text in any app, then press the hotkey to fix grammar instantly.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("⌃⌥G")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
        }
        .padding(18)
        .background(heroGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
    }

    // MARK: Status Row

    private var statusRow: some View {
        HStack(spacing: 7) {
            statusBadge(
                title: accessibilityTrusted ? "Accessibility on" : "Accessibility needed",
                tint: accessibilityTrusted ? .green : .orange
            )
            statusBadge(title: providerDisplayName, tint: .green)
            statusBadge(
                title: autoSuggestEnabled ? "Auto-suggest on" : "Auto-suggest off",
                tint: autoSuggestEnabled ? .green : .orange
            )
        }
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.1), in: Capsule())
    }

    // MARK: Quick Access Chips

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Access")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .textCase(.uppercase)
                .kerning(0.5)

            HStack(spacing: 10) {
                quickChip(
                    icon: "doc.on.clipboard",
                    count: appState.clipboardService.entries.count,
                    label: "Clipboard",
                    subtitle: "⌃⌥V to open palette"
                )
                quickChip(
                    icon: "chevron.left.forwardslash.chevron.right",
                    count: DeveloperTool.allCases.count,
                    label: "Dev Tools",
                    subtitle: "JSON, JWT, Diff…"
                )
                quickChip(
                    icon: "checkmark.rectangle",
                    count: appState.correctionLogStore.entries.count,
                    label: "Corrections",
                    subtitle: "Today's log"
                )
            }
        }
    }

    private func quickChip(icon: String, count: Int, label: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(NSColor.labelColor))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.separator.opacity(0.6), lineWidth: 0.5)
        )
    }

    // MARK: Hotkeys Card

    private var hotkeysCard: some View {
        VStack(spacing: 0) {
            hotkeyRow(label: "Tidy selected text", combo: "⌃⌥G")
            Divider().opacity(0.5)
            hotkeyRow(label: "Open clipboard palette", combo: "⌃⌥V")
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.separator.opacity(0.6), lineWidth: 0.5)
        )
    }

    private func hotkeyRow(label: String, combo: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            Text(combo)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(NSColor.labelColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.separator, lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var providerDisplayName: String {
        GrammarProviderID(rawValue: grammarProvider)?.displayName ?? grammarProvider
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' 2>&1 | grep -E "^.*error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tidy/UI/DashboardView.swift
git commit -m "feat: implement Command Center HomeView with hero card and quick chips"
```

---

## Task 7: Redesign ClipboardListView with hover copy + app color dots

**Files:**
- Modify: `Tidy/UI/DashboardView.swift`

- [ ] **Step 1: Replace ClipboardListView**

Find and replace the `ClipboardListView` struct in `DashboardView.swift` with:

```swift
struct ClipboardListView: View {
    @EnvironmentObject private var clipboardService: ClipboardService

    var body: some View {
        VStack(spacing: 0) {
            // Header + search
            VStack(alignment: .leading, spacing: 10) {
                Text("Clipboard History")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    TextField("Search \(clipboardService.entries.count) items…", text: $clipboardService.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.separator.opacity(0.8), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Divider() }

            // List
            if clipboardService.entries.isEmpty {
                ContentUnavailableView(
                    "No clipboard history yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy some text and it will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(clipboardService.entries.enumerated()), id: \.element.id) { index, entry in
                            ClipboardRowView(entry: entry, isFirst: index == 0) {
                                clipboardService.delete(entry)
                            }
                            if index < clipboardService.entries.count - 1 {
                                Divider().opacity(0.4).padding(.leading, 18)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let isFirst: Bool
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(appColor(for: entry.sourceAppName))
                        .frame(width: 7, height: 7)
                    if let app = entry.sourceAppName {
                        Text(app)
                    }
                    Text(entry.createdAt, style: .relative)
                    Text("·")
                    Text("\(entry.charCount) chars")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.content, forType: .string)
                } label: {
                    Text("Copy")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.labelColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(isFirst || isHovered
            ? Color(NSColor.controlBackgroundColor)
            : Color.clear)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.content, forType: .string)
            }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func appColor(for appName: String?) -> Color {
        switch appName?.lowercased() {
        case "safari":    return Color(red: 0, green: 0.478, blue: 1)
        case "chrome", "google chrome": return Color(red: 1, green: 0.584, blue: 0)
        case "firefox":   return Color(red: 1, green: 0.4, blue: 0.1)
        case "xcode":     return Color(red: 0.345, blue: 0.835, green: 0.525)
        case "vs code", "visual studio code", "code": return Color(red: 0.2, green: 0.784, blue: 0.349)
        case "terminal", "iterm2", "iterm": return Color(red: 0, green: 0, blue: 0)
        case "notes":     return Color(red: 1, green: 0.231, blue: 0.188)
        case "slack":     return Color(red: 0.44, green: 0.15, blue: 0.6)
        default:          return Color(NSColor.secondaryLabelColor)
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' 2>&1 | grep -E "^.*error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tidy/UI/DashboardView.swift
git commit -m "feat: redesign ClipboardListView with hover copy and app color dots"
```

---

## Task 8: Redesign DeveloperToolsView

**Files:**
- Modify: `Tidy/UI/DeveloperToolsView.swift`

- [ ] **Step 1: Update sidebar width and tool row styling**

In `DeveloperToolsView.swift`, find `toolsSidebar` computed property. Replace it with:

```swift
private var toolsSidebar: some View {
    VStack(spacing: 0) {
        // Search field
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            TextField("Search tools", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.separator.opacity(0.8), lineWidth: 0.5)
        )
        .padding(10)

        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(tools) { tool in
                    ToolSidebarRow(tool: tool, selected: selection == tool) {
                        selection = tool
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
    .frame(width: 200)
    .background(Color(NSColor.controlBackgroundColor))
    .overlay(alignment: .trailing) { Divider() }
}
```

- [ ] **Step 2: Update ToolSidebarRow**

Replace the `ToolSidebarRow` struct with:

```swift
private struct ToolSidebarRow: View {
    let tool: DeveloperTool
    let selected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(selected ? .white : Color(NSColor.secondaryLabelColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? .white : Color(NSColor.labelColor))
                    Text(tool.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(selected ? .white.opacity(0.7) : Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected
                        ? Color(NSColor.labelColor).opacity(0.85)
                        : (isHovered ? Color(NSColor.labelColor).opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 3: Update ToolScreen header and StatusPill**

Replace the `ToolScreen` struct with:

```swift
private struct ToolScreen<ToolbarContent: View, Content: View>: View {
    let title: String
    let subtitle: String
    let status: String
    let isError: Bool
    @ViewBuilder let toolbar: ToolbarContent
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                    Spacer()
                    HStack(spacing: 6) { toolbar }
                        .controlSize(.small)
                }
                StatusPill(text: status, isError: isError)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            content.padding(14)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
```

Replace the `StatusPill` struct with:

```swift
private struct StatusPill: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isError ? Color.red : Color.green)
                .frame(width: 6, height: 6)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isError ? Color.red : Color.green)
    }
}
```

- [ ] **Step 4: Update PanelHeader for lighter styling**

Replace the `PanelHeader` struct with:

```swift
private struct PanelHeader<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            Spacer()
            HStack(spacing: 8) { content }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}
```

- [ ] **Step 5: Build to confirm it compiles**

```bash
xcodebuild build -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' 2>&1 | grep -E "^.*error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Tidy/UI/DeveloperToolsView.swift
git commit -m "feat: slim DeveloperToolsView sidebar to 200px with graphite active state"
```

---

## Task 9: Redesign SettingsView — inline layout + appearance picker

**Files:**
- Modify: `Tidy/UI/SettingsView.swift`

- [ ] **Step 1: Replace SettingsView with new inline version**

Replace the entire contents of `Tidy/UI/SettingsView.swift` with:

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppDefaults.grammarProvider)     private var grammarProvider    = GrammarProviderID.gemini.rawValue
    @AppStorage(AppDefaults.grammarHotkey)       private var grammarHotkey      = Hotkey.grammarDefault.displayValue
    @AppStorage(AppDefaults.clipboardHotkey)     private var clipboardHotkey    = Hotkey.clipboardDefault.displayValue
    @AppStorage(AppDefaults.clipboardMaxEntries) private var maxEntries         = 200
    @AppStorage(AppDefaults.clipboardMaxAgeDays) private var maxAgeDays         = 7
    @AppStorage(AppDefaults.openCodeModel)       private var openCodeModel      = "deepseek-v4-flash-free"
    @AppStorage(AppDefaults.ollamaBaseURL)       private var ollamaBaseURL      = "http://localhost:11434"
    @AppStorage(AppDefaults.ollamaModel)         private var ollamaModel        = "gnokit/improve-grammar"
    @AppStorage(AppDefaults.appearanceMode)      private var appearanceMode     = "system"

    @State private var launchAtLogin   = false
    @State private var keyValues: [String: String] = [:]
    @State private var statusMessage   = ""
    @State private var selectedTab     = SettingsTab.general

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            content
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            launchAtLogin = appState.launchAtLoginEnabled
            loadKeychainValues()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: Tab Bar

    enum SettingsTab: String, CaseIterable {
        case general  = "General"
        case grammar  = "Grammar"
        case clipboard = "Clipboard"
        case hotkeys  = "Hotkeys"
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab
                            ? Color(NSColor.labelColor)
                            : Color(NSColor.secondaryLabelColor))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(Color(NSColor.labelColor).opacity(0.8))
                                    .frame(height: 2)
                                    .offset(y: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedTab {
                case .general:   generalContent
                case .grammar:   grammarContent
                case .clipboard: clipboardContent
                case .hotkeys:   hotkeysContent
                }
            }
            .padding(20)
        }
    }

    // MARK: General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "App") {
                settingsGroup {
                    settingsToggleRow(
                        label: "Launch at login",
                        isOn: $launchAtLogin,
                        onChange: { value in
                            do { try appState.setLaunchAtLogin(value) }
                            catch {
                                statusMessage = error.localizedDescription
                                launchAtLogin = appState.launchAtLoginEnabled
                            }
                        }
                    )
                }
            }

            settingsSection(title: "Appearance") {
                settingsGroup {
                    HStack {
                        Text("Color scheme")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Picker("", selection: $appearanceMode) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            settingsSection(title: "Permissions") {
                settingsGroup {
                    HStack {
                        Label(
                            Permissions.isAccessibilityTrusted ? "Accessibility allowed" : "Accessibility needed",
                            systemImage: Permissions.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(Permissions.isAccessibilityTrusted ? Color.green : Color.orange)
                        Spacer()
                        if !Permissions.isAccessibilityTrusted {
                            Button("Open Settings") { Permissions.openAccessibilitySettings() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
        }
    }

    // MARK: Grammar

    private var grammarContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "Provider") {
                settingsGroup {
                    HStack {
                        Text("Provider")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Picker("", selection: $grammarProvider) {
                            ForEach(GrammarProviderID.allCases) { p in
                                Text(p.displayName).tag(p.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            settingsSection(title: "API Keys") {
                settingsGroup {
                    ForEach(GrammarProviderID.allCases.filter(\.requiresAPIKey)) { provider in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text(provider.displayName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(NSColor.labelColor))
                                Spacer()
                                SecureField("API key", text: binding(for: provider.rawValue))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            Divider().opacity(0.5)
                        }
                    }
                    HStack {
                        Button("Save API Keys") { saveKeychainValues() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Clear Correction Log") { appState.correctionLogStore.clear() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer()
                        Text("\(appState.correctionLogStore.entries.count) corrections logged")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            if grammarProvider == GrammarProviderID.openCode.rawValue {
                settingsSection(title: "OpenCode") {
                    settingsGroup {
                        settingsTextRow(label: "Model", binding: $openCodeModel, prompt: "e.g. deepseek-v4-flash-free")
                    }
                }
            }

            if grammarProvider == GrammarProviderID.ollama.rawValue {
                settingsSection(title: "Ollama") {
                    settingsGroup {
                        settingsTextRow(label: "Base URL", binding: $ollamaBaseURL, prompt: "http://localhost:11434")
                        Divider().opacity(0.5)
                        settingsTextRow(label: "Model", binding: $ollamaModel, prompt: "e.g. gnokit/improve-grammar")
                    }
                    Text("Runs locally — no API key required.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
        }
    }

    // MARK: Clipboard

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "Retention") {
                settingsGroup {
                    HStack {
                        Text("Maximum entries")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Stepper("\(maxEntries)", value: $maxEntries, in: 10...1000, step: 10)
                            .onChange(of: maxEntries) { _, _ in applyRetention() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    Divider().opacity(0.5)
                    HStack {
                        Text("Maximum age")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Stepper("\(maxAgeDays) days", value: $maxAgeDays, in: 1...90)
                            .onChange(of: maxAgeDays) { _, _ in applyRetention() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            settingsSection(title: "Actions") {
                HStack {
                    Button("Open Palette") { appState.openPalette() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Clear History", role: .destructive) { appState.clipboardService.clear() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: Hotkeys

    private var hotkeysContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "Shortcuts") {
                settingsGroup {
                    settingsTextRow(label: "Tidy selected text", binding: $grammarHotkey, prompt: "control+option+g")
                    Divider().opacity(0.5)
                    settingsTextRow(label: "Clipboard palette", binding: $clipboardHotkey, prompt: "control+option+v")
                }
                Text("Format: control+option+g or command+shift+v")
                    .font(.footnote)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Button("Apply Hotkeys") { appState.registerHotkeys() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: Reusable row helpers

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .textCase(.uppercase)
                .kerning(0.5)
            content()
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.separator.opacity(0.6), lineWidth: 0.5)
        )
    }

    private func settingsToggleRow(label: String, isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { _, v in onChange?(v) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsTextRow(label: String, binding: Binding<String>, prompt: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            TextField(prompt, text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { appState.registerHotkeys() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Keychain helpers

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { keyValues[key, default: ""] }, set: { keyValues[key] = $0 })
    }

    private func loadKeychainValues() {
        for p in GrammarProviderID.allCases { keyValues[p.rawValue] = KeychainStore.read(key: p.rawValue) ?? "" }
    }

    private func saveKeychainValues() {
        for (key, value) in keyValues {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainStore.delete(key: key)
            } else {
                try? KeychainStore.save(value, key: key)
            }
        }
    }

    private func applyRetention() {
        appState.clipboardService.applyRetention(maxEntries: maxEntries, maxAgeDays: maxAgeDays)
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' 2>&1 | grep -E "^.*error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Tidy/UI/SettingsView.swift
git commit -m "feat: redesign SettingsView as inline view with appearance picker"
```

---

## Task 10: Run full test suite + final build verification

**Files:** none (verification only)

- [ ] **Step 1: Run all tests**

```bash
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -only-testing:TidyTests \
  2>&1 | grep -E "FAIL|PASS|error:|Test Suite"
```

Expected: all existing tests pass + the new tests added in Tasks 1 and 3–4 pass. No regressions.

- [ ] **Step 2: Build release to catch any lingering issues**

```bash
xcodebuild build -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' \
  -configuration Release 2>&1 | grep -E "^.*error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Final commit**

```bash
git add .
git commit -m "feat: complete Tidy redesign — icon rail, Command Center home, dark mode, inline settings"
```

---

## Self-Review Checklist

| Spec requirement | Covered in task |
|---|---|
| 54px icon rail replacing labeled sidebar | Task 4 (IconRailView), Task 5 (DashboardView body) |
| Active rail: fill + 3pt left indicator | Task 4 (IconRailView `railButton`) |
| Settings icon pinned to bottom with divider | Task 4 (IconRailView `isBottomGroup`) |
| Settings removed from toolbar | Task 5 (DashboardView body has no toolbar) |
| `appearanceMode` key + `"system"` default | Task 1 |
| `.preferredColorScheme` applied to window | Task 2 |
| Appearance picker in Settings > General | Task 9 (generalContent) |
| Hero card with graphite gradient (light + dark) | Task 6 (`heroGradient`, `heroCard`) |
| Hero card: icon wrap + title + kbd badge | Task 6 (`heroCard`) |
| Status row: green/amber capsule badges | Task 6 (`statusRow`, `statusBadge`) |
| Quick access chips with live counts | Task 6 (`quickAccessSection`, `quickChip`) |
| Hotkeys card (two rows, kbd badge) | Task 6 (`hotkeysCard`, `hotkeyRow`) |
| Old HomeView header + ActionCard grid removed | Task 6 (full HomeView replacement) |
| Clipboard: header + integrated search bar | Task 7 (`ClipboardListView`) |
| Clipboard: app color dot per row | Task 7 (`ClipboardRowView.appColor`) |
| Clipboard: hover reveals Copy button | Task 7 (`ClipboardRowView`, `isHovered`) |
| Clipboard: first row highlighted | Task 7 (`isFirst` param) |
| Dev tools sidebar 200px | Task 8 (`toolsSidebar` width) |
| Dev tools active row: graphite (not blue) | Task 8 (`ToolSidebarRow`) |
| Dev tools panel headers lighter | Task 8 (`PanelHeader`) |
| Settings inline (no fixed window frame) | Task 9 (no `.frame(width:640, height:430)`) |
| Settings: section labels + grouped rows | Task 9 (all tabs) |
| `Color(hex:)` for hero card gradients | Task 3 |
