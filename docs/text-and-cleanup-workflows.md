# Text, clipboard, and project workflows

These features are available in the working source tree. They are not a claim that a new GitHub release has been published.

## Text actions

Select text in another app and press **Control–Option–Space**. Choose Fix grammar, Make concise, Change tone, Translate, Summarize, or Turn into bullets. Translation accepts a target language; tone offers Professional, Friendly, Casual, Confident, and Empathetic.

Press **Command–Return** to run the action. Compare the original and result side by side, or enable Changes to see a line diff for shorter inputs. **Command–R** retries. Nothing replaces your selection until you choose **Replace selection** (**Command–Shift–Return**). **Command–Shift–C** copies the result as plain text. Escape closes the palette and cancels pending work.

The existing **Control–Option–G** shortcut still performs direct grammar correction. To work with pasted text instead, use **Text → Text Actions…** in the app's menu bar.

Replacement is available when Accessibility exposes the original selection, document text, and a writable selected-text attribute. Tidy checks the application, focused element, selection range, and document again before replacing. Terminals and apps that cannot verify replacement use Copy. After replacement, action editing and rerunning pause to keep Restore original available. Restore original works only while the document still matches the replacement; Copy original remains available when you have made subsequent edits. Applied replacements also retain the original in correction history.

Text actions use the configured API provider or Ollama and enforce local-only AI settings. Grammar uses the existing fallback pipeline with CLI providers excluded. LanguageTool supports grammar only; other transformations need a general-purpose provider, including a suitable local Ollama model. Codex CLI and Claude Code CLI are unavailable in this palette because those runners have filesystem tools. Presets and actions never implicitly add folder or MCP context. Ask AI explicitly transfers the text to a fresh chat draft for review before sending.

Inputs are limited to 100,000 characters. Format JSON, Extract links, and Plain text run locally without an AI request. Link extraction returns unique HTTP(S) links; JSON formatting validates the input before displaying a result.

## Custom actions

Open **Settings → Text Actions**. Create an action with a title and instructions, or start with the PR description and Professional English examples. Instructions describe the transformation; Tidy supplies the selected text separately as data.

An optional shortcut such as `control+option+p` opens the preset with your selection. Run it to preview the result. Shortcuts must include Control or Command. Tidy rejects conflicts with its configured actions and reports registration failures for shortcuts used elsewhere.

Export writes a versioned JSON file containing custom action definitions only. Import shows the instructions for review, adds new copies, and removes global shortcuts from imported presets. It does not execute them. Existing presets are preserved. Limits: 100 custom actions, 80 characters per title, 8,000 characters per instruction, and 1 MB for both an import file and the complete saved collection. An addition that exceeds the limit leaves existing presets unchanged.

## Clipboard favorites and actions

Open the clipboard palette with **Control–Option–V**, or use the Clipboard workspace. Pin an entry to keep it beyond automatic retention. Recopying the same text preserves its ID, original source app, collection, and favorite status. Explicit deletion and Clear history still remove favorites.

Use Actions to put favorites in named collections, filter by collection, open text actions, format JSON, extract links, or save an entry to Today. Unpinning also removes the collection assignment. Whitespace in newly captured snippets is preserved.

Palette shortcuts:

| Shortcut | Action |
| --- | --- |
| Up / Down | Select entry |
| Return or double-click | Paste as plain text into the previous app |
| Command–C | Copy selected entry |
| Command–P | Pin or unpin |
| Command–Shift–F | Toggle favorites filter |
| Command–R | Open rewrite preview |
| Command–Shift–J | Open JSON action |
| Command–Shift–L | Open link extraction |
| Command–T | Save as task in Today |
| Command–Shift–T | Save as note in Today |
| Command–Delete | Delete selected entry |

## Capture into Today

**Control–Option–T** saves the selection in another app as a task planned for today. The menu-bar Capture Selection as Note action and text/clipboard action menus support notes too. Captures retain the complete text in the body, use its first line as a bounded title, and record the source app when available.

An Open source link appears when the source app exposes a document URL, or a clipboard entry consists of a supported URL. Tidy does not infer a browser page for arbitrary clipboard text. Source information is included in Today JSON persistence/sync and Markdown exports. Older items without source metadata still load.

## Developer project cleanup

Choose a project or a folder containing projects in File Tidy. Project markers include Git, Node, Swift packages, Xcode, Rust, Python, Go, Ruby, and Java build manifests. The project summary shows inspected bytes, generated-folder bytes, and Git status. Nested projects are accounted for separately. Hidden build files are included; Git metadata, symlinks, protected home descendants, and Tidy review folders are skipped. Scans can be cancelled and report partial results when traversal limits or read errors occur.

Generated-folder candidates include `node_modules`, `.next`, `.nuxt`, `.turbo`, `dist`, `build`, `coverage`, `DerivedData`, `.build`, `target`, Python caches, and `.xcarchive` directories. Each proposal explains likely contents and regeneration costs. Names alone do not prove files are disposable: candidates require explicit selection and can be inspected in Finder. Tidy flags uncommitted or unavailable Git status, rechecks before applying, and refuses to move a candidate containing tracked files or when the tracked-file check fails.

Project source files are excluded from ordinary document organization. Approved generated folders move into **Tidy Project Review** within the selected root, retaining their relative paths. **These moves do not free disk space.** They stage files for review while preserving recovery; permanent deletion is not part of this workflow.

Recovery paths are written to disk before each move. The undo log remains accessible after restart and after a partially completed batch. Undo never overwrites a newly occupied original path. Keep the review folders until you are satisfied that the project still works.

## Verification

Run the unit suite:

```sh
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' -only-testing:TidyTests CODE_SIGNING_ALLOWED=NO
```

The focused UI smoke test requires a working signed Xcode UI test runner and a GUI session:

```sh
xcodebuild test -project Tidy.xcodeproj -scheme Tidy \
  -destination 'platform=macOS' -only-testing:TidyUITests/WorkflowFeatureUITests \
  CODE_SIGN_IDENTITY='Apple Development' CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=YOUR_TEAM_ID
```

Replace `YOUR_TEAM_ID` with the team for your installed Apple Development certificate. Ad-hoc signing can prevent the macOS UI runner from starting.

Before distributing, manually verify selection replacement and restoration in the apps you support, terminal copy-only behavior, permission denial, focus/selection changes while a request is running, and each configured AI provider. These OS- and account-dependent flows are not proven by local transformation/storage tests.
