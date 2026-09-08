# Today: Google Drive backup and sync

Open Today and click the cloud button (or **… → Google Drive backup & sync**). This integration uses a folder managed by Google Drive for desktop. Tidy does not sign into a Google account or upload files through the Drive API.

## Connect

1. Install and sign into Google Drive for desktop.
2. Create a private folder in **My Drive**. Make the folder available offline in Finder so Tidy can keep working when the internet is unavailable.
3. In Tidy, select Automatic backup or Two-way sync, then choose that folder. Selecting the folder starts the selected mode.
4. On each additional Mac, choose the same parent folder in My Drive and enable Two-way sync.

Google documents streamed/mirrored files and offline availability in its [Drive for desktop guide](https://support.google.com/drive/answer/13401938?hl=en).

Tidy creates a `Tidy Today` subfolder. Automatic backup writes snapshots after changes. Two-way mode also exchanges item revisions, checking the folder every 15 seconds while Tidy is running. Local edits trigger an update after a short pause. Changes made immediately before quitting are backed up when Tidy next runs.

“Drive folder up to date” means the local folder exchange finished. It does not confirm that Google uploaded the files; check Google Drive's own status. Tidy cannot detect whether an arbitrary chosen folder is actually managed by Drive. A missing or unreadable folder produces a retryable error while local editing remains available.

## What travels

Tasks, notes, routines, completion history, archived items, daily focus, item dates, tags, priorities, and item reminder choices are included. Notification permission/preferences and the active exercise timer remain specific to each Mac. Clipboard history, AI credentials, and connected-account data are excluded.

The folder contains readable JSON backups and change history. Disconnect stops future folder exchanges without deleting copies already in Drive. Files are retained; the UI lists the latest 30 backups. Disconnect all Macs before removing change history: active replicas can republish known revisions. Choosing another folder copies the existing history rather than compacting it.

## Conflicts

Each item/focus-note revision has a unique identifier and references the revisions it replaces. Files are immutable and use unique names, so offline writers do not replace one shared mutable workspace file. Merging does not use computer clocks to decide which edit wins.

Changes to different records merge automatically. Concurrent edits to the same record keep all versions. The currently displayed local version stays visible until review. In **Conflicts**, choose a version or keep all versions as separate items. Alternative daily focus versions become ordinary notes. Editing an unresolved item does not silently discard the competing version. Explicit conflict resolution creates a new revision covering all reviewed versions; if another change arrives later, it can become a new conflict.

Updates wait while an item or daily focus editor is open. Unsaved quick-capture text remains local and is not part of a backup until saved.

## Restore

In **Backups**, choose Restore on a dated backup or use **Open backup** for an exported or local recovery JSON file. A confirmation shows the backup date and record counts. Restoring brings back the saved versions and keeps records created afterward. A copy of the current content is saved under `~/Library/Application Support/Tidy/Today Recovery/` first. Open that folder from Backups to recover a previous version.

In two-way mode, restored records become new revisions that also travel to other Macs. This is a content restore; notification preferences and active timers stay unchanged. A restore is stopped if the workspace changes during recovery-copy creation.

## Implementation and validation

- Local `productivity.json` remains the primary store. The optional `syncJournal` preserves old-file compatibility and records revision ancestry durably with local edits.
- The chosen folder is remembered with a security-scoped bookmark in `productivity-sync-settings.json`.
- JSON validation rejects unknown formats, duplicate or conflicting identifiers, invalid item fields, missing ancestry, and cyclic ancestry before replacing local content.
- Folder I/O runs in a separate actor. New files are written to a hidden temporary path, then moved into place. Readers ignore temporary files; duplicate arrivals are idempotent.
- History exchange is bounded at 50,000 changes / 128 MB total, with a 20 MB per-file limit. Exceeding a limit pauses incoming sync and leaves local content intact. There is no history compaction in this version.
- Tests use independent local folders to simulate two Macs, out-of-order delivery, identical and conflicting edits, recovery, missing folders, malformed files, automatic backup, and persisted folder settings. Live Google Drive upload/download requires the user's configured Drive account and is not asserted by local tests.
