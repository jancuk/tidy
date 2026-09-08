# Workspace design

Tidy's main window uses a shared visual language: a warm light/dark canvas, readable surfaces, quiet borders, consistent page headers, and compact rounded actions. `WorkspaceDesign`, `WorkspaceHeader`, `WorkspaceButtonStyle`, and `WorkspaceEmptyState` provide these primitives. Button styling respects compact controls, disabled states, and destructive roles.

Home, Today, Workflows, File Tidy, Clipboard, Tidy Data, developer tools, correction and AI history, Jira, Asana, Settings, Privacy, and the terminal toolbar share the same palette. Dense editors and task workbenches retain their functional layouts.

## Notifications

- Briefing and individual source tabs provide separate overview and reading contexts.
- Search filters readable summaries within the selected source or across all sources in Briefing.
- Saved timestamps and connection status distinguish cached content from a successful live refresh. A source error takes precedence over a cached summary's status.
- Markdown paragraphs and bullets have comfortable spacing; original payloads and tool names are tucked into Source details.
- Malformed structured content is not presented as a finished briefing. The original saved text remains available on demand, with a clear refresh instruction.
- Local fallback summaries extract human-readable fields from structured source data, keep supplied event dates, preserve URLs and email addresses, and bound the displayed output. They do not infer urgency or describe old events as upcoming.

## Navigation and history

- Main navigation groups daily work, tools, connected sources, and history. Keyboard shortcuts and sidebar collapse remain available.
- Clipboard uses a searchable list and a full-content reading pane with selectable text, an optional code font, and a persistent copy action. Selection follows filtered results.
- Corrections have search, readable corrected text, and an expandable original. Copying the correction gives immediate feedback.
- AI Requests can be searched and filtered by source or failure. Expanded cards show the saved request preview, complete error, timing, and status details; they do not imply that full prompts or responses were saved.
- Clearing either history requires confirmation. Settings uses a vertical category rail and scrollable content, with a minimum size for the standalone Settings window.

## Verification boundary

Unit tests cover structured topics, calendar dates, damaged caches, Markdown preservation, links, email addresses, and output limits. Native UI checks use separate app identities, synthetic local notification and history stores, and the existing test-host environment. Clipboard and history stores accept explicit directories so test-host launches do not load or alter personal history. Tests cover full-content clipboard search and isolated history persistence. Asana and Settings do not load account credentials or start account services in that environment. No notification refresh, connected workflow, post, comment, task update, or email-send action is exercised for UI testing.
