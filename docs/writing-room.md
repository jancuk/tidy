# Writing in Tidy

Open **Today → Notes** and choose **Start writing**, or start from a journal, email, idea, or project brief. The same starters are available on Today.

The writing room keeps a local draft as you type. Close it and use **Continue** in the draft list to resume, including after restarting Tidy. Drafts live in `writing-drafts.json` next to the Today workspace; they are local to this Mac and are not included in Drive sync. **Save note** (⌘S) publishes the draft to your searchable Notes library and removes the draft after a successful save. Existing notes open in the same editor; discarding a draft preserves the saved version.

- Use the formatting toolbar for headings, lists, links, tables, and code; **Preview** shows the rendered Markdown. Remote images load only when you select them.
- **Focus** hides formatting and organization controls. Set an optional word goal for gentle progress feedback.
- Add tags or pin a note to Today. Copy Markdown or export a `.md` file through Writing options.
- A note changed elsewhere while a draft was open requires **Save as a new note**, preserving both versions.
- A failed draft write stays visibly unsaved and blocks Close. Copy or export remains available. Corrupt draft files are preserved, with a retry action after recovery.

Archive and Completed are browsing views and no longer display a new-task composer.

Validation: `WritingTests` covers restart recovery, exact source preservation, file permissions, discard, conflicting edits, corruption, and failed writes. `WritingExperienceUITests` exercises starting, drafting, resuming, formatting preview, and saving.
