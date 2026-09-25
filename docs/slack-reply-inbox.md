# Slack reply inbox

Open **Notifications → Set up reply inbox**. Tidy reuses the Workbench Slack connection from Integration settings and the API/Ollama provider selected in Model settings. Add the names or handles to watch, optionally enter your Slack member ID, and enable monitoring. Auto-refresh defaults to **60 minutes** and runs while Tidy is open; 15, 30, 120, and 240 minutes are also available.

The inbox searches accessible channel/thread mentions and, optionally, incoming DMs without a name mention. Select a discussion to read its context, compare two suggested replies, or request a custom alternative. Choose **Use reply** to edit a suggestion or **Write reply** to start your own. **New message** in the toolbar also works when your connected inbox is empty. Select a thread reply or a new message in the current conversation. **Another channel or DM** accepts a conversation ID starting with C, D, or G and posts a new message there. Select **Review message** to inspect the exact text and destination; only **Send to Slack** sends it. No refresh or AI generation can post. Building the feature does not authorize a live test: a separate approval of the exact test content and destination is required, as recorded in `AGENTS.md`.

When monitoring is enabled, Tidy automatically sends fetched discussion text to the AI provider chosen in Model settings to prepare private suggestions. Choose Ollama or enable local-only AI if those discussions must stay on your computer.

**Clear** and **Clear visible** dismiss items in Tidy and remove generated suggestions. **Cleared → Restore** brings the discussion back. A genuinely newer matching message in the same thread reopens it. Copying or clearing never marks a Slack message read and never counts as a sent reply.

## Request budget and context

- Initial search covers seven days. Later scans overlap the previous completed scan by one day, deduplicate channel/timestamp identifiers, and retain unfinished search pages across refreshes.
- Each pass makes at most four search calls, starting with 10 matches per page, and loads up to three discussion contexts. Workbench truncation halves the search page size and restarts that query with deduplication; retries use the same four-call budget. Reduced page sizes and pending pages survive restarts. Unprocessed discussions remain available for on-demand generation. Topics without suggestions are prioritized, with older attempts ahead of recent attempts.
- Requests share a per-connection, per-method pacing gate: searches at least 3.1 seconds apart, context/history calls at least 61 seconds apart. Calls are serialized within an inbox operation. Fast repeated refresh clicks cannot start another pass within a minute.
- Discussion context is cached for an hour. Changed discussions invalidate generated suggestions. Unchanged context does not trigger another automatic model call. Up to three discussions are analyzed in one AI request.
- HTTP 429 `Retry-After` and tool-level rate-limit errors pause further Slack reads. The inbox persists cooldowns across restarts; no automatic rapid retry loop is used. Other clients using the same Slack credentials can still consume the shared upstream quota.
- The current Workbench history/thread tools expose `limit` but no continuation cursor. Tidy requests 15 messages, reducing to 7, 3, then 1 if Workbench truncates a response; each retry uses the same rate-limit pacing. It explicitly labels partial context when there is more history or the mention is missing from the returned window. Open Slack to inspect the entire thread.
- Only `slack_search_all`, `slack_get_thread_replies`, and `slack_get_channel_history` can be invoked by the reply reader. The separately confirmed composer uses `slack_send_message`. Schema discovery is cached. Tool-enabled CLI providers are excluded from generation; the existing local-only AI setting is honored.

Slack's [rate-limit guidance](https://docs.slack.dev/apis/web-api/rate-limits/) explains per-method limits and `Retry-After`. The conservative context pacing accommodates the restricted tier documented for [conversations.replies](https://docs.slack.dev/reference/methods/conversations.replies/).

## Posting and delivery

The composer supports up to 4,000 characters and sends through the connected Workbench Slack account. It shows the conversation ID and thread timestamp in the review. Changing text or destination requires a new review; reviews expire after five minutes. A reply uses the parent thread timestamp. Choosing a different conversation removes the original thread destination.

Sending invokes only `slack_send_message`, once, after confirmation. The write transport never replays a request after a timeout or session expiry. Duplicate confirmations are blocked. An acknowledged Slack channel and message timestamp produce **Sent to Slack**. A lost or malformed response produces **Delivery unconfirmed**; check Slack before sending again. A matching unconfirmed message requires acknowledging that check before another review. Explicit API rejections preserve the message and rate-limit cooldowns survive restart.

`slack-outbox.json` stores the reviewed text, destination, attempt state, and Slack receipt locally with restricted file permissions. An interrupted send remains unconfirmed after restart. If Tidy cannot record the attempt locally, it does not send. Clearing local history or disconnecting integrations clears this delivery history; it never deletes posted Slack messages. Sent-message indicators are separate from inferred response activity in Insights.

Automated send tests use a mock writer and mock HTTP transport. No live post, reply, reaction, edit, or deletion is part of the automated suite. Live tests require a specific destination and separate explicit approval. Sending requires the Slack permission described in [chat.postMessage](https://docs.slack.dev/reference/methods/chat.postMessage/).

## Insights and daily recap

Insights shows observed discussions, later messages by your configured Slack member ID, local dismissals, and a seven-day discussion chart. Copies and dismissals are not replies. A later message does not prove the original request was resolved. This is not a personal responsibility score: incomplete threads, untracked discussions, offline work, and working hours limit interpretation.

Choose a day and **Summarize day** to generate highlights, decisions, and follow-ups from up to 12 saved discussions. This uses no additional Slack requests, filters messages to the selected calendar day, and caches unchanged recaps. Saved recaps display their generation time.

Cached messages, generated replies, settings, cooldowns, and dismissals are stored in `~/Library/Application Support/Tidy/slack-replies.json` with restricted file permissions. Records are retained for up to 90 days. Privacy Center includes the cache in storage accounting; clearing local history or disconnecting integrations resets this inbox and disables monitoring. Changing watched identity starts a new local inbox. Corrupt cache data is preserved and blocks writes until it can be reloaded.

## Verification

`SlackReplyTests` exercises paging budgets, context caching, batched generation, rate-limit cooldowns, error recovery, clearing during generation, persistent dismissals, identity validation, and recap caching. `SlackSendTests` and `SlackSendTransportTests` cover exact reviewed content, duplicate confirmation, uncertain delivery, connection changes, cooldown persistence, and no automatic replay. `SlackReplyExperienceUITests` uses deterministic fictional discussions, mock AI replies, and a mock sender, including destination changes and final confirmation. Neither suite reads or writes a real Slack workspace.

For isolated UI testing, use `PRODUCT_BUNDLE_IDENTIFIER=sinau.Tidy.SlackPreview` with a separate result bundle and `-only-testing:TidyUITests/SlackReplyExperienceUITests`. The fixture is loaded only when XCTest is present and `TIDY_SLACK_REPLY_FIXTURE=1`.
