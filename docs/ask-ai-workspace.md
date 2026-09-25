# Ask AI workspace

Open Ask AI with `⌃⌥J`, or **Text → Ask AI…** (`⌘⇧J`) while Tidy is active. Resize the window or collapse chat history to give answers more room. The window follows the Light, Dark, or System appearance chosen in Settings.

## Conversation controls

- **Return** sends; **Shift–Return** adds a line. The composer grows with your draft and scrolls for longer messages.
- **New chat** (`⌘N` inside Ask AI) starts a fresh conversation. **Escape** closes the panel; an active response continues.
- Choose an AI provider below the conversation title. This selection does not change the grammar provider in Settings. Provider credentials and model settings come from Settings.
- **Stop** cancels waiting for a response and preserves your question and follow-up draft. With CLI providers, the subprocess may continue until its timeout; its later output is ignored.
- **Edit** loads a previous question into the composer. Sending replaces that question and its later replies. Cancel leaves the conversation intact.
- **Try again** requests a replacement answer. The previous answer stays visible until a replacement succeeds. Request errors are shown separately from the transcript.
- Copy individual messages or code blocks. The conversation menu also offers **Copy conversation** and **Export as Markdown…**.

Answers support headings, lists, quotes, links, fenced code, and simple Markdown tables. Answers appear when the provider completes; token streaming is not currently implemented. Scrolling upward keeps your reading position; **Latest** returns to the bottom.

## History and privacy

Regular conversations are saved in `~/Library/Application Support/Tidy/ai-conversations.json` with owner-only file permissions. Search covers titles and message text. Right-click a conversation to rename or delete it. Privacy Center's **Clear local history** includes saved chats.

History holds up to 100 conversations and 10 MB. If storage is full or unavailable, Tidy keeps the current conversation in memory and displays an error. Export it, then delete older conversations to make room. Damaged history files are preserved instead of overwritten.

**Temporary chat** excludes messages from both Tidy's conversation history and request diagnostics. Provider retention policies still apply. CLI providers are unavailable in temporary chats because they maintain their own session files. Regular request diagnostics remain separate from chat history; deleting a single chat does not delete those diagnostics.

## Adding context

Use **Add context** to choose working folders or connected MCP sources. Selected sources appear as removable chips and are included with subsequent messages. You can also use `@mcp-…` and `@!folder` mentions. Only explicitly chosen folders are available to folder mentions.

Reopening a saved chat restores its messages. Add context again if you want fresh folder or integration data; reopening history does not automatically grant source access. A question's attachment labels record the source names used at the time, and previous answers may still contain information from those sources.

Cloud providers receive the question, conversation history, and selected context. Ollama and local-only controls follow the existing Privacy Center settings. Source credentials remain in Keychain.
