# Tidy Redesign — Design Spec

**Date:** 2026-05-24  
**Status:** Approved  
**Scope:** Full UI redesign of the Tidy macOS app — all screens, light + dark mode, user-selectable appearance.

---

## Decisions

| Dimension | Decision | Rationale |
|---|---|---|
| Direction | Clean & Focused | Native macOS feel; white surfaces, system font, no decoration for its own sake |
| Navigation | 54px Icon Rail | Maximum content space; scales as features grow; active indicator matches macOS Sonoma sidebar pattern |
| Home layout | Command Center | Hero card surfaces the primary action immediately; status + quick-access chips below |
| Accent | Graphite | No distraction from content; works equally well in light and dark |
| Appearance | User-selectable (Light / Dark / System) | Stored in `AppStorage`, respects `NSApp.effectiveAppearance` when set to System |

---

## Navigation — Icon Rail

- **Width:** 54px, fixed.
- **Icons:** SF Symbols, weight `.regular`, size 17pt. No labels.
- **Active state:** `RoundedRectangle(cornerRadius: 9)` fill at 11% opacity of the rail foreground color + a 3pt left-edge indicator bar (18pt tall, corner radius 0/3/3/0).
- **Hover state:** 5% fill, no indicator bar.
- **Sections:**
  - Top group (in order): Home, Clipboard, Dev Tools, Correction Log.
  - `Spacer()` pushes the bottom group down.
  - `Divider` (0.5pt).
  - Bottom group: Settings.
- Settings moves out of the toolbar into the rail. The `openSettings()` toolbar button is removed.
- Rail background: `Color(NSColor.controlBackgroundColor)` — adapts to light/dark automatically.
- Border: 0.5pt `Color.separator` on the trailing edge.

---

## Appearance — Light / Dark / System

**Storage key:** `AppDefaults.appearanceMode` (new), values: `"light"`, `"dark"`, `"system"`.  
**Default:** `"system"`.

**Implementation:**
- `AppSettings` exposes `@AppStorage(AppDefaults.appearanceMode) var appearanceMode`.
- `TidyApp` applies `.preferredColorScheme()` to the root window group based on the stored value.
- Settings > General tab adds an "Appearance" picker: System / Light / Dark.

**In SwiftUI:**
```swift
.preferredColorScheme(resolvedColorScheme)
```
where `resolvedColorScheme` is `nil` (system), `.light`, or `.dark`.

---

## Home Screen — Command Center

Replaces the current `HomeView` entirely.

### Hero Card
- Full-width rounded card (`cornerRadius: 13`, continuous).
- **Light:** `LinearGradient(colors: [Color(hex:"#2c2c2e"), Color(hex:"#505050")], startPoint: .topLeading, endPoint: .bottomTrailing)`.
- **Dark:** `LinearGradient(colors: [Color(hex:"#48484a"), Color(hex:"#6e6e73")], ...)`.
- Left: 44×44 icon wrap (`cornerRadius: 12`, white 15% opacity) containing `Image(systemName: "sparkles")`.
- Center: title "Tidy Selected Text" (15pt bold white) + subtitle (12pt, white 58%).
- Right: hotkey badge (monospaced 13pt bold, white 90%, white 13% background, 0.5pt white 20% border, cornerRadius 7).
- `shadow(color: .black.opacity(0.22), radius: 7, y: 3)`.

### Status Row
Three `Capsule` badges side by side (`HStack(spacing: 7)`):
- Accessibility: green when trusted, orange when not.
- Provider name: always green.
- Auto-suggest: green when on, amber when off.
Each badge: 6pt colored dot + label, 11pt semibold, tinted background at 10–15% opacity.

### Quick Access Chips
`HStack(spacing: 10)`, three equal-width chips:
- **Clipboard** — shows live `clipboardService.entries.count`, subtitle "⌃⌥V to open palette".
- **Dev Tools** — count of available tools (static 6), subtitle "JSON, JWT, Diff…".
- **Corrections** — `correctionLogStore.entries.count`, subtitle "Today's log".
Each chip: `cornerRadius: 11`, `Color(NSColor.controlBackgroundColor)` background, 0.5pt separator border. Tapping navigates to the corresponding rail section.

### Hotkeys Card
Two rows in a grouped `RoundedRectangle(cornerRadius: 11)` card:
- Tidy selected text → `⌃⌥G`
- Open clipboard palette → `⌃⌥V`
Monospaced badge styling for the combo. 0.5pt divider between rows.

### Removed from current HomeView
- The `header` block (sparkles icon + big "Tidy" title) — redundant with the titlebar.
- The `actionsGrid` (2×2 ActionCard grid) — replaced by the hero card + chips.
- The "Quick actions" section label.

---

## Clipboard History

Replaces `ClipboardListView`.

- **Header area:** `navigationTitle`-style `Text("Clipboard History")` (15pt bold) + search bar below it, all inside a `.padding(14, 18, 10)` VStack with a 0.5pt bottom divider.
- **Search bar:** `HStack` with magnifyingglass SF Symbol + plain `TextField`. Background `Color(NSColor.controlBackgroundColor)`, border 0.5pt separator, `cornerRadius: 9`.
- **List rows:** Replace current `List` with `LazyVStack(spacing: 0)` inside a `ScrollView` for full hover-state control.
  - Each row: preview text (13pt, 1 line limit) + metadata row below (11pt secondary: colored app dot + app name + relative time + char count).
  - **App color dot:** 8pt circle, color from a `sourceAppName → Color` lookup table (Safari blue, VS Code green, Chrome orange, Xcode indigo, etc.). Falls back to `Color.secondary`.
  - **Hover Copy button:** appears on `onHover`, positioned `.trailing` with a graphite pill button. Copies to pasteboard on tap.
  - Row separator: 0.5pt `Divider` at 5% opacity.
  - First (most recent) row gets a `Color(NSColor.controlBackgroundColor)` highlight to signal recency.
- **Empty state:** `ContentUnavailableView` unchanged.

---

## Developer Tools

Replaces `DeveloperToolsView`.

### Tool Sidebar
- Width: 200px (down from 270px).
- Background: `Color(NSColor.controlBackgroundColor)`.
- Search field: white/dark background, 0.5pt border, `cornerRadius: 8`, 12pt.
- Tool rows: icon (14pt) + title (12pt semibold) + subtitle (10pt secondary). `cornerRadius: 8` selection highlight.
- Active row: graphite fill (`Color(NSColor.selectedContentBackgroundColor)` maps correctly in both modes, or explicit `Color(hex:"#3a3a3c")` light / `Color.white.opacity(0.12)` dark).

### Tool Content Area
- `ToolScreen` header: lighter background (`Color(NSColor.controlBackgroundColor)`), 0.5pt bottom divider.
- `StatusPill` moves to below the subtitle, not after the toolbar buttons.
- Toolbar buttons: `.bordered` control size `.small`; primary action (Copy Output) uses `.borderedProminent` but with graphite tint override.
- `CodeEditorPanel` / `OutputPanel`: `cornerRadius: 9`, 0.5pt separator border, panel header 11pt semibold secondary.
- Syntax highlighting in `OutputPanel` for JSON: use `AttributedString` with color runs for keys, strings, numbers, booleans.

---

## Settings

Moves from a floating `TabView` window into the main window, accessed via the rail's Settings icon.

- **No separate window** — renders inline as a `screen` within the main `NavigationSplitView` detail.
- `openSettings()` call site (toolbar button) removed. The rail icon triggers `selection = .settings`.
- Add `DashboardSection.settings` case to `DashboardSection` enum with `gear` SF Symbol.
- Layout: header (15pt bold "Settings") + tab row (General, Grammar, Clipboard, Hotkeys) + scrollable body.
- Tab row uses an underline indicator (2pt graphite/white) rather than the default `TabView` style.
- Grouped rows use `Color(NSColor.controlBackgroundColor)` background, `cornerRadius: 11`, 0.5pt separator borders between rows.

### General Tab — new Appearance row
```
Appearance    [System ▾]   (Picker: System / Light / Dark)
```
Stored in `AppDefaults.appearanceMode`. Applied via `.preferredColorScheme` on the window group.

---

## Color & Spacing Tokens

| Token | Light | Dark |
|---|---|---|
| Window bg | `NSColor.windowBackgroundColor` | ← same (adaptive) |
| Rail / sidebar bg | `NSColor.controlBackgroundColor` | ← same (adaptive) |
| Card bg | `NSColor.controlBackgroundColor` | ← same (adaptive) |
| Primary text | `NSColor.labelColor` | ← same |
| Secondary text | `NSColor.secondaryLabelColor` | ← same |
| Separator | `Color.separator` at 1× | ← same |
| Hero card gradient start | `#2c2c2e` | `#48484a` |
| Hero card gradient end | `#505050` | `#6e6e73` |
| Active rail fill | `rgba(58,58,60, 0.11)` | `rgba(255,255,255, 0.10)` |
| Active rail indicator | `Color(hex:"#3a3a3c")` | `Color.white.opacity(0.70)` |

Where possible, prefer `NSColor` adaptive tokens — they handle light/dark automatically without explicit branching.

---

## Files Changed

| File | Change |
|---|---|
| `Tidy/UI/DashboardView.swift` | Replace sidebar with icon rail; add `.settings` section; new `HomeView`, `ClipboardListView` |
| `Tidy/UI/SettingsView.swift` | Remove standalone window sizing; add appearance picker; restyle as inline view |
| `Tidy/UI/DeveloperToolsView.swift` | Slim sidebar to 200px; restyle tool rows and panels |
| `Tidy/Services/AppSettings.swift` | Add `AppDefaults.appearanceMode` key |
| `Tidy/TidyApp.swift` | Apply `.preferredColorScheme` from stored appearance setting |

---

## Out of Scope

- Menu bar popover / HUD redesign — separate task.
- Clipboard palette (`ClipboardPaletteController`) — separate task.
- New features (File Tidy, Work Assistant) — not part of this redesign.
- Syntax highlighting engine — use simple string-based colorization for JSON output; full AST parsing is future work.
