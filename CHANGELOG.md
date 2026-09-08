# Changelog

All notable user-facing changes to Tidy are recorded here. This project uses
semantic versioning and keeps unreleased work at the top.

## Unreleased

### Added

- Today workspace with tasks, notes, routines, local reminders, and optional folder-based backup and conflict-aware sync.
- Guided CSV lookup, replacement, joins, reconciliation, analysis, saved settings, and intermediate result tables.
- Shared workspace styling and clearer notification and history reading views.
- Text-action palette with grammar, concise, tone, translation, summary, and bullet actions; before/after previews, retry, checked replacement, and original recovery.
- Custom action presets with editable instructions, optional global shortcuts, and reviewed JSON import/export.
- Clipboard favorites and collections, local JSON/link actions, and keyboard capture into Today.
- Tasks and notes captured from selections or clipboard entries retain full text and available source links.
- Developer project sizes, hidden generated-folder detection, Git warnings, and tracked-file protection.

### Fixed

- Clipboard recopy preserves favorites and collection metadata; automatic retention keeps pinned entries.
- File Tidy writes recovery paths before moves, keeps undo available after restart, and checks batches before changing files.
- Text actions preserve typed punctuation and keep original recovery available after replacement.
- Oversized preset additions leave the existing, reloadable collection intact.
- Text actions exclude CLI providers with filesystem tools, including grammar fallbacks.

## 1.0.0 - 2026-08-19

### Added

- Initial public release of Tidy for Apple silicon Macs running macOS 15.3 or newer.
- Keyboard-first grammar correction in any app, with cloud and local AI providers.
- Searchable local clipboard history and the quick-access clipboard palette.
- Preview-first file organization with duplicate detection and undo support.
- Local developer tools for JSON, JWT, diffs, Unix time, CSV/JSON, and cron expressions.
- Automated macOS CI for unit tests and release builds.
- Signed, notarized GitHub release workflow with DMG packaging.
- Daily engineering briefing across configured notification sources.
- Privacy Center with local data inventory, history clearing, credential reset,
  and enforced local-only AI processing.
- Goal-based onboarding and personalized navigation.
- Outcome-focused developer workflows for daily briefing, meeting preparation,
  project cleanup, context sharing, and end-of-day updates.
- Connector SDK foundation with capability and retention declarations.
