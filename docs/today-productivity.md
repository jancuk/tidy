# Today: a local daily workspace

Today gives Tidy a personal workspace for daily focus, pending work, notes, reminders, and custom routines. Open it from the sidebar, Home, the menu bar, or Command–Shift–T. No connected account or AI provider is required.

## Start and finish the day

The morning overview shows planned or due tasks, overdue tasks, all pending tasks, and items completed today. Write an intention in **Plan my day**, then move pending items into Today. Unfinished planned tasks carry forward until completed, removed from the plan, or rescheduled. Notes can be pinned as daily reference material.

**Start My Day** opens local daily planning. **Wrap Up My Day** opens the same dated note for reflection. Older daily notes are available in **Daily focus history** and included in Markdown exports. These actions do not call connected services.

## Capture and organize

- **Tasks:** title, detailed next steps, priority, tags, optional planned day and due time; completion can be undone.
- **Notes:** multiline plain text for ideas, code, links, and context; searchable by title, body, and tags.
- **Exercises:** custom coding practice, movement breaks, or any routine; once, daily, weekday, or weekly schedules; editable duration and completion history.
- **Archive:** removes an item from active views and scheduled reminders while keeping it recoverable.

Search covers active workspace items regardless of the selected category. In Archive, search covers archived items. The multiline composer uses Return for a new line and Command–Return to save. Select Task, Note, or Exercise; the details button carries the first line into the title and the rest into the editor. Cancelling keeps the draft, and saving clears it. The spacious editor offers an optional code font, with planning, tags, and reminders in an expandable section. Editing and quick capture are available without leaving Tidy. The menu bar provides capture shortcuts and an active session indicator.

## Routines and timers

Start a routine timer, pause/resume it, stop it, or explicitly log completion. Timers use an end timestamp, survive restart, and never automatically claim an exercise was performed. Recurring exercises can be logged once per local day, with undo for that day's completion. One-time exercises use normal completion status.

Routine reminders repeat on their configured schedule even if the routine is already marked complete that day. Disable the reminder or archive the routine to stop it. Weekday reminders run Monday–Friday; weekly routines use the selected weekday.

## Local reminders

Notifications are off by default. Enabling them explicitly requests macOS notification permission. Each item can optionally notify at its due/reminder time. There is also an optional daily planning reminder and a timer-finished notification when alerts are enabled. Scheduled notifications are handled by macOS and do not require the Tidy window to remain open; delivery remains subject to system notification and Focus settings.

Expired one-time reminders remain visible instead of being sent retroactively. Snooze moves a one-time reminder 15 minutes forward. Completing or archiving a task cancels its pending alert. Tidy removes only requests in its own productivity namespace. It reports permission and scheduling failures, and prevents configurations exceeding 64 alert requests rather than silently dropping them. Weekday routines use five requests each.

Reminders use local notifications, not Slack, email, calendar events, or AI. This feature does not create any content in external services.

## Persistence and ownership

`~/Library/Application Support/Tidy/productivity.json` contains notes, tasks, routine completions, daily focus notes, preferences, and any active timer. Writes are atomic and the file is restricted to its owner. Failed writes keep the previous published state; unreadable, unsupported, or duplicate-record files block editing rather than replacing the original with an empty workspace.

The Privacy Center lists this file. Clearing diagnostic and clipboard history preserves this personal workspace. Export all notes, plans, routine history, and daily reflections as Markdown from the workspace menu. Archiving is recoverable; permanent deletion is not included. Optional [folder-based backup and sync](today-google-drive-sync.md) is available through a user-chosen folder managed by Google Drive for desktop.

## Verification and test boundary

Unit tests use temporary folders or in-memory storage and a fake notification service. Tests cover capture/search, day rollover, persistence, corrupted files, failed writes, archiving/restoring, daily/weekday/weekly schedules, permission denial, cancellation, snooze, reminder limits, timer pause/restart/completion, and export. Native UI checks use a separate temporary app with an in-memory Today workspace and a silent notification adapter.

No test posts Slack messages, sends email, creates calendar events, or delivers real notification content.
